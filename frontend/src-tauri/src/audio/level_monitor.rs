use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::sync::Mutex;
use tokio::time::{interval, Duration};
use tauri::{AppHandle, Emitter, Runtime};
use anyhow::Result;
use log::{debug, error, info, warn};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{Sample, SampleFormat, SampleRate, StreamConfig};
use serde::Serialize;

use super::audio_processing::audio_to_mono;

#[derive(Debug, Serialize, Clone)]
pub struct AudioLevelData {
    pub device_name: String,
    pub device_type: String,
    pub rms_level: f32,
    pub peak_level: f32,
    pub is_active: bool,
}

#[derive(Debug, Serialize, Clone)]
pub struct AudioLevelUpdate {
    pub timestamp: u64,
    pub levels: Vec<AudioLevelData>,
}

pub struct AudioLevelMonitor {
    monitored_devices: Arc<Mutex<Vec<String>>>,
    streams: Arc<Mutex<Vec<cpal::Stream>>>,
}

impl AudioLevelMonitor {
    pub fn new() -> Self {
        Self {
            monitored_devices: Arc::new(Mutex::new(Vec::new())),
            streams: Arc::new(Mutex::new(Vec::new())),
        }
    }

    pub async fn start_monitoring<R: Runtime>(
        &mut self,
        app_handle: AppHandle<R>,
        device_names: Vec<String>,
    ) -> Result<()> {
        if AUDIO_LEVEL_STATE.is_monitoring.load(Ordering::SeqCst) {

            AUDIO_LEVEL_STATE.is_monitoring.store(false, Ordering::SeqCst);
        }

        info!("Starting audio level monitoring for devices: {:?}", device_names);

        AUDIO_LEVEL_STATE.is_monitoring.store(true, Ordering::SeqCst);
        *self.monitored_devices.lock().await = device_names.clone();

        {
            let mut streams = self.streams.lock().await;
            streams.clear();
        }

        let host = cpal::default_host();
        let level_data = Arc::new(Mutex::new(Vec::<AudioLevelData>::new()));

        for device_name in &device_names {
            if let Ok(device) = self.find_device_by_name(&host, device_name) {
                if let Ok(stream) = self.create_level_stream(&device, device_name, level_data.clone()).await {
                    let mut streams = self.streams.lock().await;
                    streams.push(stream);
                } else {
                    warn!("Failed to create audio stream for device: {}", device_name);
                }
            } else {
                warn!("Device not found: {}", device_name);
            }
        }

        let app_handle_clone = app_handle.clone();
        let level_data_clone = level_data.clone();

        tokio::spawn(async move {
            let mut interval = interval(Duration::from_millis(100));

            while AUDIO_LEVEL_STATE.is_monitoring.load(Ordering::SeqCst) {
                interval.tick().await;

                let levels = {
                    let mut data = level_data_clone.lock().await;
                    let current_levels = data.clone();
                    data.clear();
                    current_levels
                };

                if !levels.is_empty() {
                    let update = AudioLevelUpdate {
                        timestamp: std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .unwrap_or_default()
                            .as_millis() as u64,
                        levels,
                    };

                    if let Err(e) = app_handle_clone.emit("audio-levels", &update) {
                        error!("Failed to emit audio levels: {}", e);
                    }
                }
            }
        });

        Ok(())
    }

    pub async fn stop_monitoring(&self) -> Result<()> {
        info!("Stopping audio level monitoring");

        AUDIO_LEVEL_STATE.is_monitoring.store(false, Ordering::SeqCst);

        {
            let mut streams = self.streams.lock().await;
            streams.clear();
        }

        self.monitored_devices.lock().await.clear();

        Ok(())
    }

    pub fn is_monitoring(&self) -> bool {
        AUDIO_LEVEL_STATE.is_monitoring.load(Ordering::SeqCst)
    }

    fn find_device_by_name(&self, host: &cpal::Host, device_name: &str) -> Result<cpal::Device> {

        if let Ok(input_devices) = host.input_devices() {
            for device in input_devices {
                if let Ok(name) = device.name() {
                    if name == device_name {
                        return Ok(device);
                    }
                }
            }
        }

        if let Ok(output_devices) = host.output_devices() {
            for device in output_devices {
                if let Ok(name) = device.name() {
                    if name == device_name {
                        return Ok(device);
                    }
                }
            }
        }

        Err(anyhow::anyhow!("Device not found: {}", device_name))
    }

    async fn create_level_stream(
        &self,
        device: &cpal::Device,
        device_name: &str,
        level_data: Arc<Mutex<Vec<AudioLevelData>>>,
    ) -> Result<cpal::Stream> {
        let device_name = device_name.to_string();

        let (config, is_input) = if let Ok(input_config) = device.default_input_config() {
            (input_config, true)
        } else if let Ok(output_config) = device.default_output_config() {
            (output_config, false)
        } else {
            return Err(anyhow::anyhow!("Failed to get any config for device: {}", device_name));
        };

        let sample_rate = config.sample_rate().0;
        let channels = config.channels();
        let sample_format = config.sample_format();

        debug!("Creating audio level stream for {}: {}Hz, {} channels, {:?}, is_input: {}",
               device_name, sample_rate, channels, sample_format, is_input);

        let device_type = if is_input { "input" } else { "output" };

        let stream_config = StreamConfig {
            channels,
            sample_rate: SampleRate(sample_rate),
            buffer_size: cpal::BufferSize::Default,
        };

        let level_data_clone = level_data.clone();
        let device_name_clone = device_name.clone();
        let device_type_clone = device_type.to_string();

        match sample_format {
            SampleFormat::F32 => {
                let stream = if is_input {
                    device.build_input_stream(
                        &stream_config,
                        move |data: &[f32], _: &cpal::InputCallbackInfo| {
                            process_audio_levels(
                                data,
                                channels,
                                &device_name_clone,
                                &device_type_clone,
                                level_data_clone.clone(),
                            );
                        },
                        |err| error!("Audio stream error: {}", err),
                        None,
                    )?
                } else {

                    return Err(anyhow::anyhow!("Output device monitoring not supported yet: {}", device_name));
                };

                stream.play()?;
                Ok(stream)
            }
            SampleFormat::I16 => {
                if !is_input {
                    return Err(anyhow::anyhow!("Output device monitoring not supported yet: {}", device_name));
                }

                let stream = device.build_input_stream(
                    &stream_config,
                    move |data: &[i16], _: &cpal::InputCallbackInfo| {
                        let f32_data: Vec<f32> = data.iter().map(|&s| s.to_sample()).collect();
                        process_audio_levels(
                            &f32_data,
                            channels,
                            &device_name_clone,
                            &device_type_clone,
                            level_data_clone.clone(),
                        );
                    },
                    |err| error!("Audio stream error: {}", err),
                    None,
                )?;

                stream.play()?;
                Ok(stream)
            }
            SampleFormat::U16 => {
                if !is_input {
                    return Err(anyhow::anyhow!("Output device monitoring not supported yet: {}", device_name));
                }

                let stream = device.build_input_stream(
                    &stream_config,
                    move |data: &[u16], _: &cpal::InputCallbackInfo| {
                        let f32_data: Vec<f32> = data.iter().map(|&s| s.to_sample()).collect();
                        process_audio_levels(
                            &f32_data,
                            channels,
                            &device_name_clone,
                            &device_type_clone,
                            level_data_clone.clone(),
                        );
                    },
                    |err| error!("Audio stream error: {}", err),
                    None,
                )?;

                stream.play()?;
                Ok(stream)
            }
            _ => Err(anyhow::anyhow!("Unsupported sample format: {:?}", sample_format)),
        }
    }
}

fn process_audio_levels(
    data: &[f32],
    channels: u16,
    device_name: &str,
    device_type: &str,
    level_data: Arc<Mutex<Vec<AudioLevelData>>>,
) {
    if data.is_empty() {
        return;
    }

    let mono_data = if channels > 1 {
        audio_to_mono(data, channels)
    } else {
        data.to_vec()
    };

    let rms = if !mono_data.is_empty() {
        (mono_data.iter().map(|&x| x * x).sum::<f32>() / mono_data.len() as f32).sqrt()
    } else {
        0.0
    };

    let peak = mono_data.iter().map(|&x| x.abs()).fold(0.0, f32::max);

    let is_active = rms > 0.001;

    let level_data_entry = AudioLevelData {
        device_name: device_name.to_string(),
        device_type: device_type.to_string(),
        rms_level: rms.min(1.0),
        peak_level: peak.min(1.0),
        is_active,
    };

    if let Ok(mut levels) = level_data.try_lock() {

        levels.retain(|l| l.device_name != device_name);
        levels.push(level_data_entry);
    }
}

struct AudioLevelState {
    is_monitoring: AtomicBool,

}

lazy_static::lazy_static! {
    static ref AUDIO_LEVEL_STATE: AudioLevelState = AudioLevelState {
        is_monitoring: AtomicBool::new(false),
    };
}

pub fn is_monitoring() -> bool {
    AUDIO_LEVEL_STATE.is_monitoring.load(Ordering::SeqCst)
}

pub async fn stop_monitoring() -> Result<()> {
    AUDIO_LEVEL_STATE.is_monitoring.store(false, Ordering::SeqCst);
    info!("Audio level monitoring stopped globally");
    Ok(())
}