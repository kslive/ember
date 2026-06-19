

use anyhow::Result;

pub struct DynamicResampler {

    _placeholder: (),
}

impl DynamicResampler {

    pub fn new(target_rate: u32) -> Self {
        Self { _placeholder: () }
    }

    pub fn handle_rate_change(&mut self) {

    }

    pub fn resample(&mut self, audio: &[f32], from_rate: u32, to_rate: u32) -> Vec<f32> {

        if from_rate == to_rate {
            return audio.to_vec();
        }

        let ratio = from_rate as f64 / to_rate as f64;
        let new_len = (audio.len() as f64 / ratio) as usize;
        let mut resampled = Vec::with_capacity(new_len);

        for i in 0..new_len {
            let src_pos = i as f64 * ratio;
            let src_idx = src_pos as usize;
            let fraction = src_pos - src_idx as f64;

            if src_idx + 1 < audio.len() {
                let sample1 = audio[src_idx];
                let sample2 = audio[src_idx + 1];
                let interpolated = sample1 + (sample2 - sample1) * fraction as f32;
                resampled.push(interpolated);
            } else if src_idx < audio.len() {
                resampled.push(audio[src_idx]);
            }
        }

        resampled
    }
}
