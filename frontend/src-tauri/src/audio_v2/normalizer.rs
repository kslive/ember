

use anyhow::Result;

pub struct AudioNormalizer {
    target_lufs: f64,

    _placeholder: (),
}

impl AudioNormalizer {

    pub fn new(target_lufs: f64) -> Self {
        Self {
            target_lufs,
            _placeholder: (),
        }
    }

    pub fn normalize(&mut self, audio: &[f32]) -> Vec<f32> {

        let peak = audio.iter().map(|&x| x.abs()).fold(0.0f32, f32::max);
        if peak > 0.0 {
            let gain = 0.25 / peak;
            audio.iter().map(|&x| (x * gain).max(-1.0).min(1.0)).collect()
        } else {
            audio.to_vec()
        }
    }
}
