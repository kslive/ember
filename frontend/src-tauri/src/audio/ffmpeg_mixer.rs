

use std::collections::VecDeque;
use std::time::{Duration, Instant};
use log::{debug, warn, info};

use super::device_detection::InputDeviceKind;

pub const RNNOISE_APPLY_ENABLED: bool = false;

#[allow(dead_code)]
#[derive(Debug, Clone, Copy)]
struct Timestamp {
    instant: Instant,
    sample_count: u64,
}

#[allow(dead_code)]
impl Timestamp {
    fn new() -> Self {
        Self {
            instant: Instant::now(),
            sample_count: 0,
        }
    }

    fn advance(&mut self, samples: usize) {
        self.sample_count += samples as u64;
    }

    fn elapsed(&self) -> Duration {
        self.instant.elapsed()
    }
}

#[derive(Debug, Clone)]
struct TimestampedChunk {
    samples: Vec<f32>,
    timestamp: Instant,
    #[allow(dead_code)]
    sample_rate: u32,
}

impl TimestampedChunk {
    fn new(samples: Vec<f32>, sample_rate: u32) -> Self {
        Self {
            samples,
            timestamp: Instant::now(),
            sample_rate,
        }
    }

    #[allow(dead_code)]
    fn duration_ms(&self) -> f64 {
        (self.samples.len() as f64 / self.sample_rate as f64) * 1000.0
    }

    fn age(&self) -> Duration {
        self.timestamp.elapsed()
    }
}

struct SourceBuffer {

    device_name: String,

    device_kind: InputDeviceKind,

    chunks: VecDeque<TimestampedChunk>,

    buffer_timeout: Duration,

    sample_rate: u32,

    total_samples: usize,

    chunks_received: u64,
    gaps_detected: u32,
    silence_inserted_samples: u64,
    last_chunk_time: Option<Instant>,
}

impl SourceBuffer {
    fn new(device_name: String, device_kind: InputDeviceKind, sample_rate: u32) -> Self {

        let (min_timeout, max_timeout) = device_kind.buffer_timeout();

        let buffer_timeout = max_timeout;

        info!("📦 SourceBuffer created for '{}' ({:?})", device_name, device_kind);
        info!("   Sample rate: {} Hz", sample_rate);
        info!("   Buffer timeout: {:.0}ms (range: {:.0}ms - {:.0}ms)",
              buffer_timeout.as_secs_f64() * 1000.0,
              min_timeout.as_secs_f64() * 1000.0,
              max_timeout.as_secs_f64() * 1000.0);

        Self {
            device_name,
            device_kind,
            chunks: VecDeque::new(),
            buffer_timeout,
            sample_rate,
            total_samples: 0,
            chunks_received: 0,
            gaps_detected: 0,
            silence_inserted_samples: 0,
            last_chunk_time: None,
        }
    }

    fn push(&mut self, samples: Vec<f32>) {
        let chunk = TimestampedChunk::new(samples, self.sample_rate);

        if let Some(last_time) = self.last_chunk_time {
            let gap_duration = last_time.elapsed();
            let expected_duration = Duration::from_secs_f64(
                chunk.samples.len() as f64 / self.sample_rate as f64
            );

            if gap_duration > expected_duration.mul_f32(2.0) {
                self.gaps_detected += 1;

                if self.device_kind.is_bluetooth() {
                    debug!("⚠️ Gap detected in '{}': {:.1}ms (expected ~{:.1}ms)",
                           self.device_name,
                           gap_duration.as_secs_f64() * 1000.0,
                           expected_duration.as_secs_f64() * 1000.0);
                } else {
                    warn!("⚠️ Unexpected gap in wired device '{}': {:.1}ms",
                          self.device_name,
                          gap_duration.as_secs_f64() * 1000.0);
                }
            }
        }

        self.total_samples += chunk.samples.len();
        self.chunks.push_back(chunk);
        self.chunks_received += 1;
        self.last_chunk_time = Some(Instant::now());
    }

    fn has_data(&self) -> bool {
        if let Some(oldest_chunk) = self.chunks.front() {

            oldest_chunk.age() >= self.buffer_timeout
        } else {
            false
        }
    }

    fn pop_samples(&mut self, sample_count: usize) -> Option<Vec<f32>> {
        if !self.has_data() {
            return None;
        }

        let mut result = Vec::with_capacity(sample_count);

        while result.len() < sample_count {
            if let Some(chunk) = self.chunks.front_mut() {
                let remaining = sample_count - result.len();
                let available = chunk.samples.len();

                if available <= remaining {

                    result.extend_from_slice(&chunk.samples);
                    self.total_samples -= chunk.samples.len();
                    self.chunks.pop_front();
                } else {

                    result.extend_from_slice(&chunk.samples[..remaining]);
                    chunk.samples.drain(..remaining);
                    self.total_samples -= remaining;
                    break;
                }
            } else {

                let silence_count = sample_count - result.len();
                result.resize(sample_count, 0.0);
                self.silence_inserted_samples += silence_count as u64;

                debug!("🔇 Inserted {:.1}ms silence for '{}' (buffer underrun)",
                       (silence_count as f64 / self.sample_rate as f64) * 1000.0,
                       self.device_name);
                break;
            }
        }

        Some(result)
    }

    fn buffer_size(&self) -> usize {
        self.total_samples
    }

    fn buffer_latency_ms(&self) -> f64 {
        (self.total_samples as f64 / self.sample_rate as f64) * 1000.0
    }

    fn stats(&self) -> BufferStats {
        BufferStats {
            device_name: self.device_name.clone(),
            device_kind: self.device_kind,
            buffer_size: self.total_samples,
            buffer_latency_ms: self.buffer_latency_ms(),
            chunks_received: self.chunks_received,
            gaps_detected: self.gaps_detected,
            silence_inserted_ms: (self.silence_inserted_samples as f64 / self.sample_rate as f64) * 1000.0,
        }
    }
}

#[derive(Debug, Clone)]
pub struct BufferStats {
    pub device_name: String,
    pub device_kind: InputDeviceKind,
    pub buffer_size: usize,
    pub buffer_latency_ms: f64,
    pub chunks_received: u64,
    pub gaps_detected: u32,
    pub silence_inserted_ms: f64,
}

struct AudioMixer {

    mic_ducking: f32,

    system_ducking: f32,

    adaptive_ducking: bool,
}

impl AudioMixer {
    fn new(adaptive_ducking: bool) -> Self {
        Self {
            mic_ducking: 1.0,
            system_ducking: 0.60,
            adaptive_ducking,
        }
    }

    fn mix(&mut self, mic: &[f32], system: &[f32]) -> Vec<f32> {
        assert_eq!(mic.len(), system.len(), "Mic and system audio must have same length");

        let mut result = Vec::with_capacity(mic.len());

        if self.adaptive_ducking {

            let mic_rms = calculate_rms(mic);

            const SPEECH_THRESHOLD: f32 = 0.01;

            let is_speech = mic_rms > SPEECH_THRESHOLD;

            let system_gain = if is_speech {
                self.system_ducking
            } else {
                1.0
            };

            for (m, s) in mic.iter().zip(system.iter()) {
                let mixed = (m * self.mic_ducking) + (s * system_gain);

                result.push(mixed.clamp(-1.0, 1.0));
            }
        } else {

            for (m, s) in mic.iter().zip(system.iter()) {
                let mixed = m + s;

                result.push(mixed.clamp(-1.0, 1.0));
            }
        }

        result
    }
}

pub struct FFmpegAudioMixer {
    mic_buffer: SourceBuffer,
    system_buffer: SourceBuffer,
    mixer: AudioMixer,
    #[allow(dead_code)]
    sample_rate: u32,

    mixing_window_samples: usize,

    windows_mixed: u64,
}

impl FFmpegAudioMixer {

    pub fn new(
        mic_device_name: String,
        mic_device_kind: InputDeviceKind,
        system_device_name: String,
        system_device_kind: InputDeviceKind,
        sample_rate: u32,
    ) -> Self {
        info!("🎛️ Creating FFmpeg Adaptive Audio Mixer");
        info!("   Microphone: '{}' ({:?})", mic_device_name, mic_device_kind);
        info!("   System Audio: '{}' ({:?})", system_device_name, system_device_kind);
        info!("   Sample Rate: {} Hz", sample_rate);

        let mixing_window_samples = ((sample_rate as f64 * 0.050) as usize).max(1);
        info!("   Mixing Window: {:.1}ms ({} samples)",
              (mixing_window_samples as f64 / sample_rate as f64) * 1000.0,
              mixing_window_samples);

        Self {
            mic_buffer: SourceBuffer::new(mic_device_name, mic_device_kind, sample_rate),
            system_buffer: SourceBuffer::new(system_device_name, system_device_kind, sample_rate),
            mixer: AudioMixer::new(true),
            sample_rate,
            mixing_window_samples,
            windows_mixed: 0,
        }
    }

    pub fn push_mic(&mut self, samples: Vec<f32>) {
        self.mic_buffer.push(samples);
    }

    pub fn push_system(&mut self, samples: Vec<f32>) {
        self.system_buffer.push(samples);
    }

    pub fn has_data_ready(&self) -> bool {
        self.mic_buffer.has_data() && self.system_buffer.has_data()
    }

    pub fn pop_mixed(&mut self) -> Option<Vec<f32>> {
        if !self.has_data_ready() {
            return None;
        }

        let mic_samples = self.mic_buffer.pop_samples(self.mixing_window_samples)?;
        let system_samples = self.system_buffer.pop_samples(self.mixing_window_samples)?;

        let mixed = self.mixer.mix(&mic_samples, &system_samples);

        self.windows_mixed += 1;

        if self.windows_mixed % 200 == 0 {
            self.log_stats();
        }

        Some(mixed)
    }

    pub fn get_stats(&self) -> (BufferStats, BufferStats) {
        (self.mic_buffer.stats(), self.system_buffer.stats())
    }

    fn log_stats(&self) {
        let (mic_stats, sys_stats) = self.get_stats();

        info!("🎛️ Mixer Statistics (after {} windows):", self.windows_mixed);
        info!("   Mic: {:.0}ms buffer, {} gaps, {:.1}ms silence inserted",
              mic_stats.buffer_latency_ms,
              mic_stats.gaps_detected,
              mic_stats.silence_inserted_ms);
        info!("   System: {:.0}ms buffer, {} gaps, {:.1}ms silence inserted",
              sys_stats.buffer_latency_ms,
              sys_stats.gaps_detected,
              sys_stats.silence_inserted_ms);
    }

    pub fn mic_buffer_size(&self) -> usize {
        self.mic_buffer.buffer_size()
    }

    pub fn system_buffer_size(&self) -> usize {
        self.system_buffer.buffer_size()
    }
}

fn calculate_rms(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }

    let sum_squares: f32 = samples.iter().map(|s| s * s).sum();
    (sum_squares / samples.len() as f32).sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_source_buffer_basic() {
        let mut buffer = SourceBuffer::new(
            "Test Mic".to_string(),
            InputDeviceKind::Wired,
            48000,
        );

        buffer.push(vec![0.1, 0.2, 0.3, 0.4]);

        assert_eq!(buffer.buffer_size(), 4);
        assert_eq!(buffer.chunks_received, 1);
    }

    #[test]
    fn test_ffmpeg_mixer_creation() {
        let mixer = FFmpegAudioMixer::new(
            "Test Mic".to_string(),
            InputDeviceKind::Wired,
            "Test System".to_string(),
            InputDeviceKind::Wired,
            48000,
        );

        assert_eq!(mixer.sample_rate, 48000);
        assert_eq!(mixer.mixing_window_samples, 2400);
    }

    #[test]
    fn test_rms_calculation() {
        let samples = vec![0.5, -0.5, 0.5, -0.5];
        let rms = calculate_rms(&samples);
        assert!((rms - 0.5).abs() < 0.001);
    }

    #[test]
    fn test_audio_mixer_clipping_prevention() {
        let mut mixer = AudioMixer::new(false);

        let mic = vec![0.8, 0.8, 0.8, 0.8];
        let system = vec![0.8, 0.8, 0.8, 0.8];

        let mixed = mixer.mix(&mic, &system);

        for sample in mixed {
            assert!(sample <= 1.0 && sample >= -1.0);
        }
    }
}
