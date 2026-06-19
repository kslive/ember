use anyhow::{anyhow, Result};
use cpal::traits::{HostTrait, DeviceTrait};
use log::{info, warn};

use super::configuration::{AudioDevice, DeviceType};

pub fn default_input_device() -> Result<AudioDevice> {
    let host = cpal::default_host();
    let device = host
        .default_input_device()
        .ok_or_else(|| anyhow!("No default input device found"))?;
    Ok(AudioDevice::new(device.name()?, DeviceType::Input))
}

pub fn find_builtin_input_device() -> Result<Option<AudioDevice>> {
    let host = cpal::default_host();

    let builtin_patterns = [

        "macbook",
        "built-in microphone",
        "internal microphone",

        "microphone array",
        "realtek",
        "conexant",

        "hda intel",
        "built-in audio",
    ];

    for device in host.input_devices()? {
        if let Ok(name) = device.name() {
            let name_lower = name.to_lowercase();

            for pattern in &builtin_patterns {
                if name_lower.contains(pattern) {

                    if name_lower.contains("bluetooth") ||
                       name_lower.contains("airpods") ||
                       name_lower.contains("wireless") {
                        continue;
                    }

                    info!("🎤 Found built-in microphone: '{}'", name);
                    return Ok(Some(AudioDevice::new(name, DeviceType::Input)));
                }
            }
        }
    }

    warn!("⚠️ No built-in microphone found (searched {} patterns)", builtin_patterns.len());
    Ok(None)
}