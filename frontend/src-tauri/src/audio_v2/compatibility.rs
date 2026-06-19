

use anyhow::Result;
use std::sync::Arc;
use tokio::sync::mpsc;

use super::{ModernAudioSystem, AudioConfig};
use crate::audio::recording_saver::RecordingSaver;
use crate::audio::recording_state::{AudioChunk, RecordingState};

pub struct LegacyBridge {
    legacy_saver: Option<RecordingSaver>,
    modern_system: Option<ModernAudioSystem>,
    mode: AudioMode,
}

#[derive(Debug, Clone)]
pub enum AudioMode {

    Legacy,

    Modern,

    Hybrid,
}

impl LegacyBridge {

    pub fn new(mode: AudioMode) -> Self {
        Self {
            legacy_saver: None,
            modern_system: None,
            mode,
        }
    }

    pub async fn initialize(&mut self) -> Result<()> {
        match self.mode {
            AudioMode::Legacy => {
                self.legacy_saver = Some(RecordingSaver::new());
                log::info!("Initialized legacy audio system");
            }
            AudioMode::Modern => {
                self.modern_system = Some(ModernAudioSystem::new());
                if let Some(ref mut system) = self.modern_system {
                    system.initialize().await?;
                }
                log::info!("Initialized modern audio system");
            }
            AudioMode::Hybrid => {
                self.legacy_saver = Some(RecordingSaver::new());
                self.modern_system = Some(ModernAudioSystem::new());
                if let Some(ref mut system) = self.modern_system {
                    system.initialize().await?;
                }
                log::info!("Initialized hybrid audio system (both legacy and modern)");
            }
        }
        Ok(())
    }

    pub async fn start_recording<R: tauri::Runtime>(
        &mut self,
        app: &tauri::AppHandle<R>,
    ) -> Result<mpsc::UnboundedSender<AudioChunk>> {
        match self.mode {
            AudioMode::Legacy => {
                if let Some(ref mut saver) = self.legacy_saver {
                    let sender = saver.start_accumulation();
                    log::info!("Started recording with legacy system");
                    Ok(sender)
                } else {
                    Err(anyhow::anyhow!("Legacy saver not initialized"))
                }
            }
            AudioMode::Modern => {
                if let Some(ref mut system) = self.modern_system {
                    system.start_recording().await?;

                    Err(anyhow::anyhow!("Modern system sender not yet implemented"))
                } else {
                    Err(anyhow::anyhow!("Modern system not initialized"))
                }
            }
            AudioMode::Hybrid => {

                let legacy_sender = if let Some(ref mut saver) = self.legacy_saver {
                    let sender = saver.start_accumulation();
                    log::info!("Started recording with legacy system");
                    Some(sender)
                } else {
                    None
                };

                if let Some(ref mut system) = self.modern_system {
                    system.start_recording().await?;
                    log::info!("Started recording with modern system");
                }

                legacy_sender.ok_or_else(|| anyhow::anyhow!("Failed to start legacy recording"))
            }
        }
    }

    pub async fn stop_recording<R: tauri::Runtime>(
        &mut self,
        app: &tauri::AppHandle<R>,
    ) -> Result<Option<String>> {
        match self.mode {
            AudioMode::Legacy => {
                if let Some(ref mut saver) = self.legacy_saver {
                    let result = saver.stop_and_save(app).await;
                    log::info!("Stopped recording with legacy system");
                    result.map_err(|e| anyhow::anyhow!("Legacy recording failed: {}", e))
                } else {
                    Err(anyhow::anyhow!("Legacy saver not initialized"))
                }
            }
            AudioMode::Modern => {
                if let Some(ref mut system) = self.modern_system {
                    let result = system.stop_recording().await;
                    log::info!("Stopped recording with modern system");
                    result.map_err(|e| anyhow::anyhow!("Modern recording failed: {}", e))
                } else {
                    Err(anyhow::anyhow!("Modern system not initialized"))
                }
            }
            AudioMode::Hybrid => {

                let legacy_result = if let Some(ref mut saver) = self.legacy_saver {
                    saver.stop_and_save(app).await.ok()
                } else {
                    None
                };

                let modern_result = if let Some(ref mut system) = self.modern_system {
                    system.stop_recording().await.ok()
                } else {
                    None
                };

                log::info!("Stopped recording with both systems");

                Ok(modern_result.or(legacy_result).flatten())
            }
        }
    }

    pub fn mode(&self) -> &AudioMode {
        &self.mode
    }

    pub async fn switch_mode(&mut self, new_mode: AudioMode) -> Result<()> {
        log::info!("Switching audio mode from {:?} to {:?}", self.mode, new_mode);
        self.mode = new_mode;
        self.initialize().await
    }

    pub fn get_quality_metrics(&self) -> Option<AudioQualityMetrics> {
        match self.mode {
            AudioMode::Modern | AudioMode::Hybrid => {

                Some(AudioQualityMetrics::default())
            }
            AudioMode::Legacy => None,
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct AudioQualityMetrics {

    pub sync_accuracy_ms: f64,

    pub peak_level: f32,

    pub rms_level: f32,

    pub lufs_level: f64,

    pub true_peak_level: f32,

    pub clipping_events: u32,
}

impl Default for LegacyBridge {
    fn default() -> Self {
        Self::new(AudioMode::Legacy)
    }
}

pub mod feature_flags {

    pub fn is_legacy_enabled() -> bool {
        cfg!(feature = "legacy-audio")
    }

    pub fn is_modern_enabled() -> bool {
        cfg!(feature = "modern-audio")
    }

    pub fn is_hybrid_enabled() -> bool {
        cfg!(feature = "hybrid-mode")
    }

    pub fn default_mode() -> super::AudioMode {
        if is_hybrid_enabled() {
            super::AudioMode::Hybrid
        } else if is_modern_enabled() {
            super::AudioMode::Modern
        } else {
            super::AudioMode::Legacy
        }
    }
}
