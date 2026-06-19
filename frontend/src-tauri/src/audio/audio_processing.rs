use anyhow::Result;
use chrono::Utc;
use log::{debug, info, warn};
use realfft::num_complex::{Complex32, ComplexFloat};
use realfft::RealFftPlanner;
use rubato::{
    Resampler, SincFixedIn, SincInterpolationParameters, SincInterpolationType, WindowFunction,
};
use std::path::PathBuf;
use nnnoiseless::DenoiseState;

use super::encode::encode_single_audio;

pub fn sanitize_filename(name: &str) -> String {
    name.chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            c if c.is_control() => '_',
            c => c,
        })
        .collect::<String>()
        .trim()
        .to_string()
}

pub fn create_meeting_folder(
    base_path: &PathBuf,
    meeting_name: &str,
    create_checkpoints_dir: bool,
) -> Result<PathBuf> {
    let timestamp = Utc::now().format("%Y-%m-%d_%H-%M").to_string();
    let sanitized_name = sanitize_filename(meeting_name);
    let folder_name = format!("{}_{}", sanitized_name, timestamp);
    let meeting_folder = base_path.join(folder_name);

    std::fs::create_dir_all(&meeting_folder)?;

    if create_checkpoints_dir {
        let checkpoints_dir = meeting_folder.join(".checkpoints");
        std::fs::create_dir_all(&checkpoints_dir)?;
        log::info!("Created meeting folder with checkpoints: {}", meeting_folder.display());
    } else {
        log::info!("Created meeting folder without checkpoints: {}", meeting_folder.display());
    }

    Ok(meeting_folder)
}

pub fn normalize_v2(audio: &[f32]) -> Vec<f32> {
    let rms = (audio.iter().map(|&x| x * x).sum::<f32>() / audio.len() as f32).sqrt();
    let peak = audio
        .iter()
        .fold(0.0f32, |max, &sample| max.max(sample.abs()));

    if rms == 0.0 || peak == 0.0 {
        return audio.to_vec();
    }

    let target_rms = 0.9;
    let target_peak = 0.95;

    let rms_scaling = target_rms / rms;
    let peak_scaling = target_peak / peak;

    let min_scaling = 1.5;
    let scaling_factor = (rms_scaling.min(peak_scaling)).max(min_scaling);

    audio
        .iter()
        .map(|&sample| {
            let scaled = sample * scaling_factor;

            if scaled > 0.95 {
                0.95 + (scaled - 0.95) * 0.05
            } else if scaled < -0.95 {
                -0.95 + (scaled + 0.95) * 0.05
            } else {
                scaled
            }
        })
        .collect()
}

struct TruePeakLimiter {
    lookahead_samples: usize,
    buffer: Vec<f32>,
    gain_reduction: Vec<f32>,
    current_position: usize,
}

impl TruePeakLimiter {
    fn new(sample_rate: u32) -> Self {
        const LIMITER_LOOKAHEAD_MS: usize = 10;
        let lookahead_samples = ((sample_rate as usize * LIMITER_LOOKAHEAD_MS) / 1000).max(1);

        Self {
            lookahead_samples,
            buffer: vec![0.0; lookahead_samples],
            gain_reduction: vec![1.0; lookahead_samples],
            current_position: 0,
        }
    }

    fn process(&mut self, sample: f32, true_peak_limit: f32) -> f32 {
        self.buffer[self.current_position] = sample;

        let sample_abs = sample.abs();
        if sample_abs > true_peak_limit {
            let reduction = true_peak_limit / sample_abs;
            self.gain_reduction[self.current_position] = reduction;
        } else {
            self.gain_reduction[self.current_position] = 1.0;
        }

        let output_position = (self.current_position + 1) % self.lookahead_samples;
        let output_sample = self.buffer[output_position] * self.gain_reduction[output_position];

        self.current_position = output_position;
        output_sample
    }
}

pub struct LoudnessNormalizer {
    ebur128: ebur128::EbuR128,
    limiter: TruePeakLimiter,
    gain_linear: f32,
    loudness_buffer: Vec<f32>,
    true_peak_limit: f32,
}

impl LoudnessNormalizer {

    pub fn new(channels: u32, sample_rate: u32) -> Result<Self> {
        const TRUE_PEAK_LIMIT: f64 = -1.0;
        const ANALYZE_CHUNK_SIZE: usize = 512;

        let ebur128 = ebur128::EbuR128::new(channels, sample_rate, ebur128::Mode::I | ebur128::Mode::TRUE_PEAK)
            .map_err(|e| anyhow::anyhow!("Failed to create EBU R128 normalizer: {}", e))?;

        let true_peak_limit = 10_f32.powf(TRUE_PEAK_LIMIT as f32 / 20.0);

        Ok(Self {
            ebur128,
            limiter: TruePeakLimiter::new(sample_rate),
            gain_linear: 1.0,
            loudness_buffer: Vec::with_capacity(ANALYZE_CHUNK_SIZE),
            true_peak_limit,
        })
    }

    pub fn normalize_loudness(&mut self, samples: &[f32]) -> Vec<f32> {
        if samples.is_empty() {
            return Vec::new();
        }

        const TARGET_LUFS: f64 = -23.0;
        const ANALYZE_CHUNK_SIZE: usize = 512;

        let mut normalized_samples = Vec::with_capacity(samples.len());

        for &sample in samples {

            self.loudness_buffer.push(sample);

            if self.loudness_buffer.len() >= ANALYZE_CHUNK_SIZE {
                if let Err(e) = self.ebur128.add_frames_f32(&self.loudness_buffer) {
                    warn!("Failed to add frames to EBU R128: {}", e);
                } else {

                    if let Ok(current_lufs) = self.ebur128.loudness_global() {
                        if current_lufs.is_finite() && current_lufs < 0.0 {
                            let gain_db = TARGET_LUFS - current_lufs;
                            self.gain_linear = 10_f32.powf(gain_db as f32 / 20.0);
                        }
                    }
                }
                self.loudness_buffer.clear();
            }

            let amplified = sample * self.gain_linear;
            let limited = self.limiter.process(amplified, self.true_peak_limit);

            normalized_samples.push(limited);
        }

        normalized_samples
    }
}

pub struct NoiseSuppressionProcessor {
    denoiser: DenoiseState<'static>,
    frame_buffer: Vec<f32>,
    frame_size: usize,
}

impl NoiseSuppressionProcessor {

    pub fn new(sample_rate: u32) -> Result<Self> {
        if sample_rate != 48000 {
            return Err(anyhow::anyhow!(
                "Noise suppression requires 48kHz sample rate, got {}Hz",
                sample_rate
            ));
        }

        const FRAME_SIZE: usize = DenoiseState::FRAME_SIZE;

        info!("Initializing RNNoise noise suppression (frame size: {} samples, 10ms @ 48kHz)", FRAME_SIZE);

        Ok(Self {
            denoiser: *DenoiseState::new(),
            frame_buffer: Vec::with_capacity(FRAME_SIZE * 2),
            frame_size: FRAME_SIZE,
        })
    }

    pub fn process(&mut self, samples: &[f32]) -> Vec<f32> {
        if samples.is_empty() {
            return Vec::new();
        }

        let input_len = samples.len();

        self.frame_buffer.extend_from_slice(samples);

        let mut output = Vec::with_capacity(input_len);

        while self.frame_buffer.len() >= self.frame_size {

            let frame: Vec<f32> = self.frame_buffer.drain(0..self.frame_size).collect();

            let mut denoised_frame = vec![0.0f32; self.frame_size];

            let _vad_prob = self.denoiser.process_frame(&mut denoised_frame, &frame);

            output.extend_from_slice(&denoised_frame);
        }

        output
    }

    pub fn buffered_samples(&self) -> usize {
        self.frame_buffer.len()
    }

    pub fn flush(&mut self) -> Vec<f32> {
        if self.frame_buffer.is_empty() {
            return Vec::new();
        }

        let remaining = self.frame_buffer.len();
        let mut input_frame = self.frame_buffer.clone();
        if input_frame.len() < self.frame_size {
            input_frame.resize(self.frame_size, 0.0);
        }

        let mut output = vec![0.0f32; self.frame_size];
        self.denoiser.process_frame(&mut output, &input_frame);
        self.frame_buffer.clear();

        output.truncate(remaining);
        output
    }
}

pub struct HighPassFilter {
    #[allow(dead_code)]
    sample_rate: f32,
    #[allow(dead_code)]
    cutoff_hz: f32,

    alpha: f32,
    prev_input: f32,
    prev_output: f32,
}

impl HighPassFilter {

    pub fn new(sample_rate: u32, cutoff_hz: f32) -> Self {
        let sample_rate_f = sample_rate as f32;
        let rc = 1.0 / (2.0 * std::f32::consts::PI * cutoff_hz);
        let dt = 1.0 / sample_rate_f;
        let alpha = rc / (rc + dt);

        info!("Initializing high-pass filter: cutoff={}Hz @ {}Hz", cutoff_hz, sample_rate);

        Self {
            sample_rate: sample_rate_f,
            cutoff_hz,
            alpha,
            prev_input: 0.0,
            prev_output: 0.0,
        }
    }

    pub fn process(&mut self, samples: &[f32]) -> Vec<f32> {
        let mut output = Vec::with_capacity(samples.len());

        for &sample in samples {

            let filtered = self.alpha * (self.prev_output + sample - self.prev_input);

            self.prev_input = sample;
            self.prev_output = filtered;

            output.push(filtered);
        }

        output
    }

    pub fn reset(&mut self) {
        self.prev_input = 0.0;
        self.prev_output = 0.0;
    }
}

pub fn spectral_subtraction(audio: &[f32], d: f32) -> Result<Vec<f32>> {
    let mut real_planner = RealFftPlanner::<f32>::new();
    let window_size = 1600;

    if audio.is_empty() {
        return Ok(Vec::new());
    }

    let processed_audio = if audio.len() > window_size {
        warn!("Audio length {} exceeds window size {}, truncating", audio.len(), window_size);
        &audio[..window_size]
    } else {
        audio
    };

    let r2c = real_planner.plan_fft_forward(window_size);
    let mut y = r2c.make_output_vec();

    let mut padded_audio = processed_audio.to_vec();
    if processed_audio.len() < window_size {
        let padding_needed = window_size - processed_audio.len();
        padded_audio.extend(vec![0.0f32; padding_needed]);
    }

    let mut indata = padded_audio;
    r2c.process(&mut indata, &mut y)?;

    let mut processed_audio = y
        .iter()
        .map(|&x| {
            let magnitude_y = x.abs().powf(2.0);

            let div = 1.0 - (d / magnitude_y);

            let gain = {
                if div > 0.0 {
                    f32::sqrt(div)
                } else {
                    0.0f32
                }
            };

            x * gain
        })
        .collect::<Vec<Complex32>>();

    let c2r = real_planner.plan_fft_inverse(window_size);

    let mut outdata = c2r.make_output_vec();

    c2r.process(&mut processed_audio, &mut outdata)?;

    Ok(outdata)
}

pub fn average_noise_spectrum(audio: &[f32]) -> f32 {
    let mut total_sum = 0.0f32;

    for sample in audio {
        let magnitude = sample.abs();

        total_sum += magnitude.powf(2.0);
    }

    total_sum / audio.len() as f32
}

pub fn audio_to_mono(audio: &[f32], channels: u16) -> Vec<f32> {
    let mut mono_samples = Vec::with_capacity(audio.len() / channels as usize);

    let effective_channels = if channels > 2 { 2 } else { channels };

    for chunk in audio.chunks(channels as usize) {

        let sum: f32 = chunk.iter().take(effective_channels as usize).sum();

        let mono_sample = sum / effective_channels as f32;

        mono_samples.push(mono_sample);
    }

    mono_samples
}

pub fn resample(input: &[f32], from_sample_rate: u32, to_sample_rate: u32) -> Result<Vec<f32>> {
    if input.is_empty() {
        return Ok(Vec::new());
    }

    if from_sample_rate == to_sample_rate {
        return Ok(input.to_vec());
    }

    let ratio = to_sample_rate as f64 / from_sample_rate as f64;

    let (sinc_len, interpolation_type, oversampling) = if ratio >= 2.0 {

        debug!("High-quality upsampling: {}Hz → {}Hz (ratio: {:.2}x)",
               from_sample_rate, to_sample_rate, ratio);
        (
            512,
            SincInterpolationType::Cubic,
            512,
        )
    } else if ratio >= 1.5 {

        debug!("Moderate upsampling: {}Hz → {}Hz (ratio: {:.2}x)",
               from_sample_rate, to_sample_rate, ratio);
        (
            384,
            SincInterpolationType::Cubic,
            384,
        )
    } else if ratio > 1.0 {

        debug!("Small upsampling: {}Hz → {}Hz (ratio: {:.2}x)",
               from_sample_rate, to_sample_rate, ratio);
        (
            256,
            SincInterpolationType::Linear,
            256,
        )
    } else if ratio <= 0.5 {

        debug!("Anti-aliased downsampling: {}Hz → {}Hz (ratio: {:.2}x)",
               from_sample_rate, to_sample_rate, ratio);
        (
            512,
            SincInterpolationType::Cubic,
            512,
        )
    } else {

        debug!("Moderate downsampling: {}Hz → {}Hz (ratio: {:.2}x)",
               from_sample_rate, to_sample_rate, ratio);
        (
            384,
            SincInterpolationType::Linear,
            384,
        )
    };

    let params = SincInterpolationParameters {
        sinc_len,
        f_cutoff: 0.95,
        interpolation: interpolation_type,
        oversampling_factor: oversampling,
        window: WindowFunction::BlackmanHarris2,
    };

    let mut resampler = SincFixedIn::<f32>::new(
        ratio,
        2.0,
        params,
        input.len(),
        1,
    )?;

    let waves_in = vec![input.to_vec()];
    let waves_out = resampler.process(&waves_in, None)?;

    debug!("Resampling complete: {} samples → {} samples",
           input.len(), waves_out[0].len());

    Ok(waves_out.into_iter().next().unwrap())
}

pub fn resample_audio(input: &[f32], from_sample_rate: u32, to_sample_rate: u32) -> Vec<f32> {
    match resample(input, from_sample_rate, to_sample_rate) {
        Ok(result) => result,
        Err(e) => {
            debug!("Resampling failed: {}, returning original audio", e);
            input.to_vec()
        }
    }
}

pub fn write_audio_to_file(
    audio: &[f32],
    sample_rate: u32,
    output_path: &PathBuf,
    device: &str,
    skip_encoding: bool,
) -> Result<String> {
    write_audio_to_file_with_meeting_name(audio, sample_rate, output_path, device, skip_encoding, None)
}

pub fn write_audio_to_file_with_meeting_name(
    audio: &[f32],
    sample_rate: u32,
    output_path: &PathBuf,
    device: &str,
    skip_encoding: bool,
    meeting_name: Option<&str>,
) -> Result<String> {
    let timestamp = Utc::now().format("%Y-%m-%d_%H-%M-%S").to_string();
    let sanitized_device_name = device.replace(['/', '\\'], "_");

    let final_output_path = if let Some(name) = meeting_name {
        let sanitized_meeting_name = sanitize_filename(name);
        let meeting_folder = output_path.join(&sanitized_meeting_name);

        if !meeting_folder.exists() {
            std::fs::create_dir_all(&meeting_folder)?;
        }

        meeting_folder
    } else {
        output_path.clone()
    };

    let file_path = final_output_path
        .join(format!("{}_{}.mp4", sanitized_device_name, timestamp))
        .to_str()
        .expect("Failed to create valid path")
        .to_string();
    let file_path_clone = file_path.clone();

    if !skip_encoding {
        encode_single_audio(
            bytemuck::cast_slice(audio),
            sample_rate,
            1,
            &file_path.into(),
        )?;
    }
    Ok(file_path_clone)
}

pub fn write_transcript_to_file(
    transcript_text: &str,
    output_path: &PathBuf,
    meeting_name: Option<&str>,
) -> Result<String> {
    let timestamp = Utc::now().format("%Y-%m-%d_%H-%M-%S").to_string();

    let final_output_path = if let Some(name) = meeting_name {
        let sanitized_meeting_name = sanitize_filename(name);
        let meeting_folder = output_path.join(&sanitized_meeting_name);

        if !meeting_folder.exists() {
            std::fs::create_dir_all(&meeting_folder)?;
        }

        meeting_folder
    } else {
        output_path.clone()
    };

    let file_path = final_output_path.join(format!("transcript_{}.txt", timestamp));

    std::fs::write(&file_path, transcript_text)?;

    Ok(file_path.to_string_lossy().to_string())
}

pub fn write_transcript_json_to_file(
    segments: &[super::recording_saver::TranscriptSegment],
    output_path: &PathBuf,
    meeting_name: Option<&str>,
    audio_filename: &str,
    recording_duration: f64,
) -> Result<String> {
    use serde_json::json;

    let timestamp = Utc::now().format("%Y-%m-%d_%H-%M-%S").to_string();

    let final_output_path = if let Some(name) = meeting_name {
        let sanitized_meeting_name = sanitize_filename(name);
        let meeting_folder = output_path.join(&sanitized_meeting_name);

        if !meeting_folder.exists() {
            std::fs::create_dir_all(&meeting_folder)?;
        }

        meeting_folder
    } else {
        output_path.clone()
    };

    let file_path = final_output_path.join(format!("transcript_{}.json", timestamp));

    let transcript_json = json!({
        "version": "1.0",
        "recording_duration": recording_duration,
        "audio_file": audio_filename,
        "sample_rate": 48000,
        "created_at": Utc::now().to_rfc3339(),
        "meeting_name": meeting_name,
        "segments": segments,
    });

    let json_string = serde_json::to_string_pretty(&transcript_json)?;
    std::fs::write(&file_path, json_string)?;

    Ok(file_path.to_string_lossy().to_string())
}
