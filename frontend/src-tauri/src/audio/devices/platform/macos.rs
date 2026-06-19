use anyhow::Result;
use cpal::traits::{DeviceTrait, HostTrait};

use crate::audio::devices::configuration::{AudioDevice, DeviceType};

pub fn configure_macos_audio(host: &cpal::Host) -> Result<Vec<AudioDevice>> {
    let mut devices: Vec<AudioDevice> = Vec::new();

    for device in host.input_devices()? {
        if let Ok(name) = device.name() {
            devices.push(AudioDevice::new(name, DeviceType::Input));
        }
    }

    fn should_include_output_device(name: &str) -> bool {

        !name.to_lowercase().contains("speakers")
    }

    for device in host.output_devices()? {
        if let Ok(name) = device.name() {
            if should_include_output_device(&name) {
                devices.push(AudioDevice::new(name, DeviceType::Output));
            }
        }
    }

    Ok(devices)
}