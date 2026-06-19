use std::sync::Arc;
use tokio::sync::mpsc;
use anyhow::Result;
use log::{debug, error, info, warn};

use super::devices::{AudioDevice, list_audio_devices};

#[cfg(target_os = "macos")]
use super::devices::get_safe_recording_devices_macos;

#[cfg(not(target_os = "macos"))]
use super::devices::{default_input_device, default_output_device};
use super::recording_state::{RecordingState, AudioChunk, DeviceType as RecordingDeviceType};
use super::pipeline::AudioPipelineManager;
use super::stream::AudioStreamManager;
use super::recording_saver::RecordingSaver;
use super::device_monitor::{AudioDeviceMonitor, DeviceEvent, DeviceMonitorType};

pub enum StreamManagerType {
    Standard(AudioStreamManager),
}

pub struct RecordingManager {
    state: Arc<RecordingState>,
    stream_manager: AudioStreamManager,
    pipeline_manager: AudioPipelineManager,
    recording_saver: RecordingSaver,
    device_monitor: Option<AudioDeviceMonitor>,
    device_event_receiver: Option<mpsc::UnboundedReceiver<DeviceEvent>>,
}

unsafe impl Send for RecordingManager {}

impl RecordingManager {

    pub fn new() -> Self {
        let state = RecordingState::new();
        let stream_manager = AudioStreamManager::new(state.clone());
        let pipeline_manager = AudioPipelineManager::new();
        let (device_monitor, device_event_receiver) = AudioDeviceMonitor::new();

        Self {
            state,
            stream_manager,
            pipeline_manager,
            recording_saver: RecordingSaver::new(),
            device_monitor: Some(device_monitor),
            device_event_receiver: Some(device_event_receiver),
        }
    }

    pub async fn start_recording(
        &mut self,
        microphone_device: Option<Arc<AudioDevice>>,
        system_device: Option<Arc<AudioDevice>>,
        auto_save: bool,
    ) -> Result<mpsc::UnboundedReceiver<AudioChunk>> {
        info!("Starting recording manager (auto_save: {})", auto_save);

        let (transcription_sender, transcription_receiver) = mpsc::unbounded_channel::<AudioChunk>();

        let recording_sender = self.recording_saver.start_accumulation(auto_save);

        self.state.start_recording()?;

        let (mic_name, mic_kind) = if let Some(ref mic) = microphone_device {
            let device_kind = super::device_detection::InputDeviceKind::detect(&mic.name, 512, 48000);
            (mic.name.clone(), device_kind)
        } else {
            ("No Microphone".to_string(), super::device_detection::InputDeviceKind::Unknown)
        };

        let (sys_name, sys_kind) = if let Some(ref sys) = system_device {
            let device_kind = super::device_detection::InputDeviceKind::detect(&sys.name, 512, 48000);
            (sys.name.clone(), device_kind)
        } else {
            ("No System Audio".to_string(), super::device_detection::InputDeviceKind::Unknown)
        };

        self.recording_saver.set_device_info(
            microphone_device.as_ref().map(|d| d.name.clone()),
            system_device.as_ref().map(|d| d.name.clone())
        );

        self.pipeline_manager.start(
            self.state.clone(),
            transcription_sender,
            0,
            48000,
            Some(recording_sender),
            mic_name,
            mic_kind,
            sys_name,
            sys_kind,
        )?;

        tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;

        self.stream_manager.start_streams(microphone_device.clone(), system_device.clone(), None).await?;

        if let Some(ref mut monitor) = self.device_monitor {
            if let Err(e) = monitor.start_monitoring(microphone_device, system_device) {
                warn!("Failed to start device monitoring: {}", e);

            } else {
                info!("✅ Device monitoring started");
            }
        }

        info!("Recording manager started successfully with {} active streams",
               self.stream_manager.active_stream_count());

        Ok(transcription_receiver)
    }

    pub async fn start_recording_with_defaults_and_auto_save(&mut self, auto_save: bool) -> Result<mpsc::UnboundedReceiver<AudioChunk>> {
        #[cfg(target_os = "macos")]
        {
            info!("🎙️ [macOS] Starting recording with smart device selection (Bluetooth override enabled)");

            let (microphone_device, system_device) = get_safe_recording_devices_macos()?;

            let microphone_device = microphone_device.map(Arc::new);
            let system_device = system_device.map(Arc::new);

            if microphone_device.is_none() {
                return Err(anyhow::anyhow!("❌ No microphone device available for recording"));
            }

            self.start_recording(microphone_device, system_device, auto_save).await
        }

        #[cfg(not(target_os = "macos"))]
        {
            info!("Starting recording with default devices");

            let microphone_device = match default_input_device() {
                Ok(device) => {
                    info!("Using default microphone: {}", device.name);
                    Some(Arc::new(device))
                }
                Err(e) => {
                    warn!("No default microphone available: {}", e);
                    None
                }
            };

            let system_device = match default_output_device() {
                Ok(device) => {
                    info!("Using default system audio: {}", device.name);
                    Some(Arc::new(device))
                }
                Err(e) => {
                    warn!("No default system audio available: {}", e);
                    None
                }
            };

            if microphone_device.is_none() {
                return Err(anyhow::anyhow!("No microphone device available"));
            }

            self.start_recording(microphone_device, system_device, auto_save).await
        }
    }

    pub async fn stop_streams_only(&mut self) -> Result<()> {
        info!("Stopping recording streams only");

        if let Some(ref mut monitor) = self.device_monitor {
            monitor.stop_monitoring().await;
        }

        self.state.stop_recording();

        if let Err(e) = self.stream_manager.stop_streams() {
            error!("Error stopping audio streams: {}", e);
        }

        if let Err(e) = self.pipeline_manager.stop().await {
            error!("Error stopping audio pipeline: {}", e);
        }

        debug!("Recording streams stopped successfully");
        Ok(())
    }

    pub async fn stop_streams_and_force_flush(&mut self) -> Result<()> {
        info!("🚀 Stopping recording streams with IMMEDIATE pipeline flush");

        if let Some(ref mut monitor) = self.device_monitor {
            info!("Stopping device monitor first...");
            monitor.stop_monitoring().await;
        }

        self.state.stop_recording();

        if let Err(e) = self.stream_manager.stop_streams() {
            error!("Error stopping audio streams: {}", e);
        }

        debug!("💨 Forcing pipeline to flush accumulated audio immediately");
        if let Err(e) = self.pipeline_manager.force_flush_and_stop().await {
            error!("Error during force flush: {}", e);
        }

        self.state.cleanup();

        info!("✅ Recording streams stopped with immediate flush completed");
        Ok(())
    }

    pub async fn save_recording_only<R: tauri::Runtime>(&mut self, app: &tauri::AppHandle<R>) -> Result<()> {
        debug!("Saving recording with transcript chunks");

        let recording_duration = self.state.get_active_recording_duration();
        info!("Recording duration from state: {:?}s", recording_duration);

        match self.recording_saver.stop_and_save(app, recording_duration).await {
            Ok(Some(file_path)) => {
                info!("Recording saved successfully to: {}", file_path);
            }
            Ok(None) => {
                debug!("Recording not saved (auto-save disabled or no audio data)");
            }
            Err(e) => {
                error!("Failed to save recording: {}", e);

            }
        }

        debug!("Recording save operation completed");
        Ok(())
    }

    pub async fn stop_recording<R: tauri::Runtime>(&mut self, app: &tauri::AppHandle<R>) -> Result<()> {
        info!("Stopping recording manager");

        let recording_duration = self.state.get_active_recording_duration();
        info!("Recording duration before stop: {:?}s", recording_duration);

        self.state.stop_recording();

        if let Err(e) = self.stream_manager.stop_streams() {
            error!("Error stopping audio streams: {}", e);
        }

        if let Err(e) = self.pipeline_manager.stop().await {
            error!("Error stopping audio pipeline: {}", e);
        }

        match self.recording_saver.stop_and_save(app, recording_duration).await {
            Ok(Some(file_path)) => {
                info!("Recording saved successfully to: {}", file_path);
            }
            Ok(None) => {
                info!("Recording not saved (auto-save disabled or no audio data)");
            }
            Err(e) => {
                error!("Failed to save recording: {}", e);

            }
        }

        info!("Recording manager stopped");
        Ok(())
    }

    pub fn get_recording_stats(&self) -> (usize, u32) {
        self.recording_saver.get_stats()
    }

    pub fn is_recording(&self) -> bool {
        self.state.is_recording()
    }

    pub fn pause_recording(&self) -> Result<()> {
        info!("Pausing recording");
        self.state.pause_recording()
    }

    pub fn resume_recording(&self) -> Result<()> {
        info!("Resuming recording");
        self.state.resume_recording()
    }

    pub fn is_paused(&self) -> bool {
        self.state.is_paused()
    }

    pub fn is_active(&self) -> bool {
        self.state.is_active()
    }

    pub fn get_stats(&self) -> super::recording_state::RecordingStats {
        self.state.get_stats()
    }

    pub fn get_recording_duration(&self) -> Option<f64> {
        self.state.get_recording_duration()
    }

    pub fn get_active_recording_duration(&self) -> Option<f64> {
        self.state.get_active_recording_duration()
    }

    pub fn get_total_pause_duration(&self) -> f64 {
        self.state.get_total_pause_duration()
    }

    pub fn get_current_pause_duration(&self) -> Option<f64> {
        self.state.get_current_pause_duration()
    }

    pub fn get_error_info(&self) -> (u32, Option<super::recording_state::AudioError>) {
        (self.state.get_error_count(), self.state.get_last_error())
    }

    pub fn active_stream_count(&self) -> usize {
        self.stream_manager.active_stream_count()
    }

    pub fn set_error_callback<F>(&self, callback: F)
    where
        F: Fn(&super::recording_state::AudioError) + Send + Sync + 'static,
    {
        self.state.set_error_callback(callback);
    }

    pub fn has_fatal_error(&self) -> bool {
        self.state.has_fatal_error()
    }

    pub fn set_meeting_name(&mut self, name: Option<String>) {
        self.recording_saver.set_meeting_name(name);
    }

    pub fn add_transcript_segment(&self, segment: super::recording_saver::TranscriptSegment) {
        self.recording_saver.add_transcript_segment(segment);
    }

    pub fn add_transcript_chunk(&self, text: String) {
        self.recording_saver.add_transcript_chunk(text);
    }

    pub fn get_transcript_segments(&self) -> Vec<super::recording_saver::TranscriptSegment> {
        self.recording_saver.get_transcript_segments()
    }

    pub fn get_meeting_name(&self) -> Option<String> {
        self.recording_saver.get_meeting_name()
    }

    pub async fn cleanup_without_save(&mut self) {
        if self.is_recording() {
            debug!("Stopping recording without saving during cleanup");

            self.state.stop_recording();

            if let Err(e) = self.stream_manager.stop_streams() {
                error!("Error stopping audio streams during cleanup: {}", e);
            }

            if let Err(e) = self.pipeline_manager.stop().await {
                error!("Error stopping audio pipeline during cleanup: {}", e);
            }
        }
        self.state.cleanup();
    }

    pub fn get_meeting_folder(&self) -> Option<std::path::PathBuf> {
        self.recording_saver.get_meeting_folder().map(|p| p.clone())
    }

    pub fn poll_device_events(&mut self) -> Option<DeviceEvent> {
        if let Some(ref mut receiver) = self.device_event_receiver {
            receiver.try_recv().ok()
        } else {
            None
        }
    }

    pub async fn attempt_device_reconnect(&mut self, device_name: &str, device_type: DeviceMonitorType) -> Result<bool> {
        info!("🔄 Attempting to reconnect device: {} ({:?})", device_name, device_type);

        let available_devices = list_audio_devices().await?;

        let device = available_devices.iter()
            .find(|d| d.name == device_name)
            .cloned();

        if let Some(device) = device {
            info!("✅ Device '{}' found, recreating stream...", device_name);

            let device_arc: Arc<AudioDevice> = Arc::new(device);
            match device_type {
                DeviceMonitorType::Microphone => {

                    let system_device = self.state.get_system_device();

                    self.stream_manager.stop_streams()?;
                    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

                    self.stream_manager.start_streams(Some(device_arc.clone()), system_device, None).await?;
                    self.state.set_microphone_device(device_arc);

                    info!("✅ Microphone reconnected successfully");
                    Ok(true)
                }
                DeviceMonitorType::SystemAudio => {

                    let microphone_device = self.state.get_microphone_device();

                    self.stream_manager.stop_streams()?;
                    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

                    self.stream_manager.start_streams(microphone_device, Some(device_arc.clone()), None).await?;
                    self.state.set_system_device(device_arc);

                    info!("✅ System audio reconnected successfully");
                    Ok(true)
                }
            }
        } else {
            warn!("❌ Device '{}' not yet available", device_name);
            Ok(false)
        }
    }

    pub async fn handle_device_disconnect(&mut self, device_name: String, device_type: DeviceMonitorType) {
        warn!("📱 Device disconnected: {} ({:?})", device_name, device_type);

        let device = match device_type {
            DeviceMonitorType::Microphone => self.state.get_microphone_device(),
            DeviceMonitorType::SystemAudio => self.state.get_system_device(),
        };

        if let Some(device) = device {
            let recording_device_type = match device_type {
                DeviceMonitorType::Microphone => RecordingDeviceType::Microphone,
                DeviceMonitorType::SystemAudio => RecordingDeviceType::System,
            };
            self.state.start_reconnecting(device, recording_device_type);
        }
    }

    pub async fn handle_device_reconnect(&mut self, device_name: String, device_type: DeviceMonitorType) -> Result<()> {
        info!("📱 Device reconnected: {} ({:?})", device_name, device_type);

        match self.attempt_device_reconnect(&device_name, device_type).await {
            Ok(true) => {
                info!("✅ Successfully reconnected device: {}", device_name);
                self.state.stop_reconnecting();
                Ok(())
            }
            Ok(false) => {
                warn!("Device reconnect attempt failed (device not yet available)");
                Err(anyhow::anyhow!("Device not available"))
            }
            Err(e) => {
                error!("Device reconnect failed: {}", e);
                Err(e)
            }
        }
    }

    pub fn is_reconnecting(&self) -> bool {
        self.state.is_reconnecting()
    }

    pub fn get_state(&self) -> &Arc<RecordingState> {
        &self.state
    }
}

impl Default for RecordingManager {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for RecordingManager {
    fn drop(&mut self) {

        self.state.cleanup();
    }
}