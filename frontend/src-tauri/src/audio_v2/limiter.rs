

pub struct TruePeakLimiter {

    _placeholder: (),
}

impl TruePeakLimiter {

    pub fn new(sample_rate: u32, lookahead_ms: usize) -> Self {
        Self { _placeholder: () }
    }

    pub fn process(&mut self, sample: f32, limit: f32) -> f32 {

        sample.max(-limit).min(limit)
    }
}
