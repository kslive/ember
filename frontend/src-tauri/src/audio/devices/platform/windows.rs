use anyhow::{anyhow, Result};
use cpal::traits::{DeviceTrait, HostTrait};
use log::{debug, info, warn};

use crate::audio::devices::configuration::{AudioDevice, DeviceType};

pub fn configure_windows_audio(host: &cpal::Host) -> Result<Vec<AudioDevice>> {
    let mut devices = Vec::new();

    if let Ok(wasapi_host) = cpal::host_from_id(cpal::HostId::Wasapi) {
        debug!("Using WASAPI host for Windows audio device enumeration");

        if let Ok(output_devices) = wasapi_host.output_devices() {
            for device in output_devices {
                if let Ok(name) = device.name() {

                    devices.push(AudioDevice::new(name.clone(), DeviceType::Output));
                }
            }
        } else {
            warn!("Failed to enumerate WASAPI output devices");
        }

        if let Ok(input_devices) = wasapi_host.input_devices() {
            for device in input_devices {
                if let Ok(name) = device.name() {

                    devices.push(AudioDevice::new(name.clone(), DeviceType::Input));
                }
            }
        } else {
            warn!("Failed to enumerate WASAPI input devices");
        }
    } else {
        warn!("Failed to create WASAPI host, falling back to default host");
    }

    if devices.is_empty() {
        debug!("WASAPI device enumeration failed or returned no devices, falling back to default host");

        if let Ok(input_devices) = host.input_devices() {
            for device in input_devices {
                if let Ok(name) = device.name() {

                    devices.push(AudioDevice::new(name.clone(), DeviceType::Input));
                }
            }
        } else {
            warn!("Failed to enumerate input devices from default host");
        }

        if let Ok(output_devices) = host.output_devices() {
            for device in output_devices {
                if let Ok(name) = device.name() {

                    devices.push(AudioDevice::new(name.clone(), DeviceType::Output));
                }
            }
        } else {
            warn!("Failed to enumerate output devices from default host");
        }
    }

    if devices.is_empty() {
        warn!("No audio devices found, adding default devices only");

        if let Some(device) = host.default_input_device() {
            if let Ok(name) = device.name() {

                devices.push(AudioDevice::new(name, DeviceType::Input));
            }
        }

        if let Some(device) = host.default_output_device() {
            if let Ok(name) = device.name() {

                devices.push(AudioDevice::new(name, DeviceType::Output));
            }
        }
    }

    debug!("Found {} Windows audio devices", devices.len());
    Ok(devices)
}

pub fn get_windows_device(audio_device: &AudioDevice) -> Result<(cpal::Device, cpal::SupportedStreamConfig)> {
    let wasapi_host = cpal::host_from_id(cpal::HostId::Wasapi)
        .map_err(|e| anyhow!("Failed to create WASAPI host: {}", e))?;

    let base_name = if audio_device.name.ends_with(" (input)") {
        audio_device.name.trim_end_matches(" (input)")
    } else if audio_device.name.ends_with(" (output)") {
        audio_device.name.trim_end_matches(" (output)")
    } else {
        &audio_device.name
    };

    info!("Looking for Windows device with base name: {}", base_name);

    match audio_device.device_type {
        DeviceType::Input => {
            for device in wasapi_host.input_devices()? {
                if let Ok(name) = device.name() {
                    info!("Checking input device: {}", name);

                    if name == base_name || name.contains(base_name) {

                        match device.default_input_config() {
                            Ok(default_config) => {

                                return Ok((device, default_config));
                            },
                            Err(e) => {
                                warn!("Failed to get default input config: {}. Trying supported configs...", e);

                                if let Ok(supported_configs) = device.supported_input_configs() {
                                    let configs: Vec<_> = supported_configs.collect();
                                    if configs.is_empty() {
                                        warn!("No supported input configurations found for device: {}", name);
                                    } else {

                                        for config in &configs {
                                            if config.sample_format() == cpal::SampleFormat::F32 && config.channels() == 2 {
                                                let config = config.with_max_sample_rate();

                                                return Ok((device, config));
                                            }
                                        }

                                        for config in &configs {
                                            if config.sample_format() == cpal::SampleFormat::F32 {
                                                let config = config.with_max_sample_rate();

                                                return Ok((device, config));
                                            }
                                        }

                                        let config = configs[0].with_max_sample_rate();
                                        info!("Using fallback input config: {:?}", config);
                                        return Ok((device, config));
                                    }
                                } else {
                                    warn!("Could not enumerate supported configurations for device: {}", name);
                                }

                                return Err(anyhow!("No compatible input configuration found for device: {}", name));
                            }
                        }
                    }
                }
            }

            info!("No matching input device found, trying default input device");
            if let Some(default_device) = wasapi_host.default_input_device() {
                if let Ok(_name) = default_device.name() {

                    if let Ok(config) = default_device.default_input_config() {
                        return Ok((default_device, config));
                    } else if let Ok(supported_configs) = default_device.supported_input_configs() {
                        if let Some(config) = supported_configs.into_iter().next() {
                            return Ok((default_device, config.with_max_sample_rate()));
                        }
                    }
                }
            }
        }
        DeviceType::Output => {
            for device in wasapi_host.output_devices()? {
                if let Ok(name) = device.name() {
                    info!("Checking output device: {}", name);

                    if name == base_name || name.contains(base_name) {

                        if let Ok(supported_configs) = device.supported_output_configs() {
                            let configs: Vec<_> = supported_configs.collect();
                            if configs.is_empty() {
                                warn!("No supported output configurations found for device: {}", name);
                            } else {

                                for config in &configs {
                                    if config.sample_format() == cpal::SampleFormat::F32 && config.channels() == 2 {
                                        let config = config.with_max_sample_rate();
                                        info!("Using stereo F32 output config: {:?}", config);
                                        return Ok((device, config));
                                    }
                                }

                                for config in &configs {
                                    if config.sample_format() == cpal::SampleFormat::F32 {
                                        let config = config.with_max_sample_rate();

                                        return Ok((device, config));
                                    }
                                }

                                let config = configs[0].with_max_sample_rate();

                                return Ok((device, config));
                            }
                        } else {
                            warn!("Could not enumerate supported configurations for device: {}", name);
                        }

                        if let Ok(default_config) = device.default_output_config() {

                            return Ok((device, default_config));
                        }
                    }
                }
            }

            info!("No matching output device found, trying default output device");
            if let Some(default_device) = wasapi_host.default_output_device() {
                if let Ok(name) = default_device.name() {
                    info!("Using default output device: {}", name);
                    if let Ok(config) = default_device.default_output_config() {
                        return Ok((default_device, config));
                    } else if let Ok(supported_configs) = default_device.supported_output_configs() {
                        if let Some(config) = supported_configs.into_iter().next() {
                            return Ok((default_device, config.with_max_sample_rate()));
                        }
                    }
                }
            }
        }
    }

    Err(anyhow!("Device not found or no compatible configuration available: {}", audio_device.name))
}