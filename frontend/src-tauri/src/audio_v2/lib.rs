

pub mod stream;
pub mod mixer;
pub mod normalizer;
pub mod resampler;
pub mod recorder;
pub mod compatibility;
pub mod sync;
pub mod limiter;

pub use stream::{ModernAudioStream, ModernAudioStreamManager, ProcessedAudio, UnifiedAudioStream};
pub use mixer::{AudioMixer, MixingMode, AudioLevelStats};
pub use normalizer::AudioNormalizer;
pub use resampler::DynamicResampler;
pub use recorder::ModernRecorder;
pub use compatibility::{LegacyBridge, AudioMode, AudioQualityMetrics};
pub use sync::{AudioSynchronizer, SynchronizedChunk};
pub use limiter::TruePeakLimiter;

use anyhow::Result;
use std::sync::Arc;

#[derive(Debug, Clone)]
pub struct AudioConfig {

    pub target_sample_rate: u32,

    pub normalization_target_lufs: f64,

    pub sync_tolerance_ms: u32,

    pub enable_true_peak_limiting: bool,

    pub mixing_mode: MixingMode,
}

#[derive(Debug, Clone)]
pub enum MixingMode {

    Fixed { mic_ratio: f32, system_ratio: f32 },

    Dynamic,

    Professional,
}

impl Default for AudioConfig {
    fn default() -> Self {
        Self {
            target_sample_rate: 48000,
            normalization_target_lufs: -23.0,
            sync_tolerance_ms: 1,
            enable_true_peak_limiting: true,
            mixing_mode: MixingMode::Professional,
        }
    }
}

pub struct ModernAudioSystem {
    config: AudioConfig,
    stream: Option<AudioStream>,
    recorder: Option<ModernRecorder>,
}

impl ModernAudioSystem {

    pub fn new() -> Self {
        Self {
            config: AudioConfig::default(),
            stream: None,
            recorder: None,
        }
    }

    pub fn with_config(config: AudioConfig) -> Self {
        Self {
            config,
            stream: None,
            recorder: None,
        }
    }

    pub async fn initialize(&mut self) -> Result<()> {

        Ok(())
    }

    pub async fn start_recording(&mut self) -> Result<()> {

        Ok(())
    }

    pub async fn stop_recording(&mut self) -> Result<Option<String>> {

        Ok(None)
    }

    pub fn config(&self) -> &AudioConfig {
        &self.config
    }

    pub fn update_config(&mut self, config: AudioConfig) {
        self.config = config;
    }
}

impl Default for ModernAudioSystem {
    fn default() -> Self {
        Self::new()
    }
}
