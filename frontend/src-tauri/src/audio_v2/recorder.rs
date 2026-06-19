

use anyhow::Result;
use tokio::sync::mpsc;
use std::sync::Arc;
use futures_util::StreamExt;
use log::{info, warn, error};

use super::stream::{ModernAudioStreamManager, ProcessedAudio};
use super::mixer::{AudioMixer, MixingMode};
use super::normalizer::AudioNormalizer;
use super::sync::AudioSynchronizer;
use crate::audio::core::AudioDevice;
use crate::audio::recording_state::DeviceType;

pub struct ModernRecorder {
    stream_manager: ModernAudioStreamManager,
    mixer: AudioMixer,
    normalizer: AudioNormalizer,
    synchronizer: AudioSynchronizer,
    mic_buffer: Vec<ProcessedAudio>,
    system_buffer: Vec<ProcessedAudio>,
    is_recording: bool,
    sample_rate: u32,
}

impl ModernRecorder {

    pub fn new(sample_rate: u32) -> Self {
        Self {
            stream_manager: ModernAudioStreamManager::new(),
            mixer: AudioMixer::new(MixingMode::Professional),
            normalizer: AudioNormalizer::new(-23.0),
            synchronizer: AudioSynchronizer::new(1),
            mic_buffer: Vec::new(),
            system_buffer: Vec::new(),
            is_recording: false,
            sample_rate,
        }
    }

    pub async fn start(
        &mut self,
        microphone_device: Option<Arc<AudioDevice>>,
        system_device: Option<Arc<AudioDevice>>,
    ) -> Result<mpsc::UnboundedSender<ProcessedAudio>> {
        info!("Starting modern recorder with async streams");

        self.stream_manager.start_streams(microphone_device, system_device).await?;

        let (sender, mut receiver) = mpsc::unbounded_channel::<ProcessedAudio>();

        let mut mixer = self.mixer.clone();
        let mut normalizer = self.normalizer.clone();
        let mut synchronizer = self.synchronizer.clone();
        let mut mic_buffer = Vec::new();
        let mut system_buffer = Vec::new();

        tokio::spawn(async move {
            info!("Modern recording task started");

            while let Some(audio) = receiver.recv().await {
                match audio.device_type {
                    DeviceType::Microphone => {
                        mic_buffer.push(audio);
                    }
                    DeviceType::System => {
                        system_buffer.push(audio);
                    }
                }

                if mic_buffer.len() >= 10 || system_buffer.len() >= 10 {
                    Self::process_buffers(
                        &mut mixer,
                        &mut normalizer,
                        &mut synchronizer,
                        &mut mic_buffer,
                        &mut system_buffer,
                    ).await;
                }
            }

            Self::process_buffers(
                &mut mixer,
                &mut normalizer,
                &mut synchronizer,
                &mut mic_buffer,
                &mut system_buffer,
            ).await;

            info!("Modern recording task completed");
        });

        self.is_recording = true;
        info!("Modern recorder started successfully");

        Ok(sender)
    }

    async fn process_buffers(
        mixer: &mut AudioMixer,
        normalizer: &mut AudioNormalizer,
        synchronizer: &mut AudioSynchronizer,
        mic_buffer: &mut Vec<ProcessedAudio>,
        system_buffer: &mut Vec<ProcessedAudio>,
    ) {
        if mic_buffer.is_empty() && system_buffer.is_empty() {
            return;
        }

        let mic_samples: Vec<f32> = mic_buffer.iter()
            .flat_map(|audio| &audio.samples)
            .cloned()
            .collect();

        let system_samples: Vec<f32> = system_buffer.iter()
            .flat_map(|audio| &audio.samples)
            .cloned()
            .collect();

        let mixed = mixer.mix(&mic_samples, &system_samples);

        let normalized = normalizer.normalize(&mixed);

        info!("Processed {} mic samples and {} system samples into {} mixed samples",
              mic_samples.len(), system_samples.len(), normalized.len());

        mic_buffer.clear();
        system_buffer.clear();
    }

    pub async fn stop(&mut self) -> Result<Option<String>> {
        info!("Stopping modern recorder");

        if !self.is_recording {
            return Ok(None);
        }

        self.stream_manager.stop_streams()?;

        self.is_recording = false;
        info!("Modern recorder stopped successfully");

        Ok(None)
    }

    pub fn is_recording(&self) -> bool {
        self.is_recording
    }

    pub fn get_level_stats(&self) -> super::mixer::AudioLevelStats {
        self.mixer.get_level_stats()
    }

    pub fn set_mixing_mode(&mut self, mode: MixingMode) {
        self.mixer.set_mixing_mode(mode);
    }

    pub fn active_stream_count(&self) -> usize {
        self.stream_manager.active_stream_count()
    }
}

impl Default for ModernRecorder {
    fn default() -> Self {
        Self::new(48000)
    }
}
