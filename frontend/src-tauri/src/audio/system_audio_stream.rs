use std::sync::Arc;
use anyhow::Result;
use log::{error, info, warn};
use tokio::sync::mpsc;

use super::devices::AudioDevice;
use super::pipeline::AudioCapture;
use super::recording_state::{RecordingState, DeviceType};
use super::capture::{SystemAudioCapture, SystemAudioStream};

pub struct SystemAudioStreamManager {
    device: Arc<AudioDevice>,
    stream: Option<SystemAudioStream>,
    _capture_task: Option<tokio::task::JoinHandle<()>>,
}

impl SystemAudioStreamManager {

    pub async fn create(
        device: Arc<AudioDevice>,
        state: Arc<RecordingState>,
        recording_sender: Option<mpsc::UnboundedSender<super::recording_state::AudioChunk>>,
    ) -> Result<Self> {
        info!("Creating system audio stream for device: {}", device.name);

        let system_capture = SystemAudioCapture::new()?;
        let mut system_stream = system_capture.start_system_audio_capture()?;

        let audio_capture = AudioCapture::new(
            device.clone(),
            state.clone(),
            system_stream.sample_rate(),
            2,
            DeviceType::Output,
            recording_sender,
        );

        let capture_task = tokio::spawn(async move {
            use futures_util::StreamExt;

            let mut buffer = Vec::new();
            let mut frame_count = 0;
            let frames_per_chunk = 1024;

            while let Some(sample) = system_stream.next().await {
                buffer.push(sample);
                frame_count += 1;

                if frame_count >= frames_per_chunk {
                    audio_capture.process_audio_data(&buffer);
                    buffer.clear();
                    frame_count = 0;
                }
            }

            if !buffer.is_empty() {
                audio_capture.process_audio_data(&buffer);
            }

            info!("System audio capture task ended");
        });

        info!("System audio stream started for device: {}", device.name);

        Ok(Self {
            device,
            stream: Some(system_stream),
            _capture_task: Some(capture_task),
        })
    }

    pub fn device(&self) -> &AudioDevice {
        &self.device
    }

    pub fn stop(mut self) -> Result<()> {
        info!("Stopping system audio stream for device: {}", self.device.name);

        if let Some(stream) = self.stream.take() {
            drop(stream);
        }

        if let Some(task) = self._capture_task.take() {
            task.abort();
        }

        Ok(())
    }
}

pub struct EnhancedAudioStreamManager {
    microphone_stream: Option<super::stream::AudioStream>,
    system_stream: Option<SystemAudioStreamManager>,
    state: Arc<RecordingState>,
}

impl EnhancedAudioStreamManager {
    pub fn new(state: Arc<RecordingState>) -> Self {
        Self {
            microphone_stream: None,
            system_stream: None,
            state,
        }
    }

    pub async fn start_streams(
        &mut self,
        microphone_device: Option<Arc<AudioDevice>>,
        system_device: Option<Arc<AudioDevice>>,
        recording_sender: Option<mpsc::UnboundedSender<super::recording_state::AudioChunk>>,
    ) -> Result<()> {
        info!("Starting enhanced audio streams");

        if let Some(mic_device) = microphone_device {
            info!("Starting microphone stream: {}", mic_device.name);
            let mic_stream = super::stream::AudioStream::create(
                mic_device,
                self.state.clone(),
                DeviceType::Input,
                recording_sender.clone(),
            ).await?;
            self.microphone_stream = Some(mic_stream);
        }

        if let Some(sys_device) = system_device {
            info!("Starting enhanced system audio stream: {}", sys_device.name);

            if should_use_enhanced_system_audio(&sys_device) {
                info!("Using enhanced Core Audio system capture for: {}", sys_device.name);
                let sys_stream = SystemAudioStreamManager::create(
                    sys_device,
                    self.state.clone(),
                    recording_sender,
                ).await?;
                self.system_stream = Some(sys_stream);
            } else {
                info!("Falling back to ScreenCaptureKit for: {}", sys_device.name);

                let sys_stream = super::stream::AudioStream::create(
                    sys_device,
                    self.state.clone(),
                    DeviceType::Output,
                    recording_sender,
                ).await?;

                warn!("Fallback ScreenCaptureKit stream created but not stored in enhanced manager");
            }
        }

        let mic_count = if self.microphone_stream.is_some() { 1 } else { 0 };
        let sys_count = if self.system_stream.is_some() { 1 } else { 0 };

        info!("Enhanced audio streams started: {} microphone, {} system audio",
               mic_count, sys_count);

        Ok(())
    }

    pub async fn stop_streams(&mut self) -> Result<()> {
        info!("Stopping enhanced audio streams");

        if let Some(mic_stream) = self.microphone_stream.take() {
            mic_stream.stop()?;
        }

        if let Some(sys_stream) = self.system_stream.take() {
            sys_stream.stop()?;
        }

        info!("Enhanced audio streams stopped");
        Ok(())
    }

    pub fn active_stream_count(&self) -> usize {
        let mut count = 0;
        if self.microphone_stream.is_some() {
            count += 1;
        }
        if self.system_stream.is_some() {
            count += 1;
        }
        count
    }
}

fn should_use_enhanced_system_audio(device: &AudioDevice) -> bool {

    #[cfg(target_os = "macos")]
    {

        true
    }

    #[cfg(not(target_os = "macos"))]
    {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_should_use_enhanced_system_audio() {
        let device = Arc::new(AudioDevice::new("Test Device".to_string(), super::super::DeviceType::Output));

        #[cfg(target_os = "macos")]
        assert!(should_use_enhanced_system_audio(&device));

        #[cfg(not(target_os = "macos"))]
        assert!(!should_use_enhanced_system_audio(&device));
    }
}