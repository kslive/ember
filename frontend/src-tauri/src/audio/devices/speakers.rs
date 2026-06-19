use anyhow::{anyhow, Result};
use cpal::traits::{HostTrait, DeviceTrait};
use log::{info, warn};

use super::configuration::{AudioDevice, DeviceType};

pub fn default_output_device() -> Result<AudioDevice> {
    #[cfg(target_os = "macos")]
    {

        let host = cpal::default_host();
        let device = host
            .default_output_device()
            .ok_or_else(|| anyhow!("No default output device found"))?;
        return Ok(AudioDevice::new(device.name()?, DeviceType::Output));
    }

    #[cfg(target_os = "windows")]
    {

        if let Ok(wasapi_host) = cpal::host_from_id(cpal::HostId::Wasapi) {
            if let Some(device) = wasapi_host.default_output_device() {
                if let Ok(name) = device.name() {
                    return Ok(AudioDevice::new(name, DeviceType::Output));
                }
            }
        }

        let host = cpal::default_host();
        let device = host
            .default_output_device()
            .ok_or_else(|| anyhow!("No default output device found"))?;
        return Ok(AudioDevice::new(device.name()?, DeviceType::Output));
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        let host = cpal::default_host();
        let device = host
            .default_output_device()
            .ok_or_else(|| anyhow!("No default output device found"))?;
        return Ok(AudioDevice::new(device.name()?, DeviceType::Output));
    }
}

pub fn find_builtin_output_device() -> Result<Option<AudioDevice>> {
    let host = cpal::default_host();

    let builtin_patterns = [

        "macbook",
        "built-in speakers",
        "built-in output",
        "internal speakers",

        "speakers",
        "realtek",
        "conexant",
        "high definition audio",

        "hda intel",
        "built-in audio",
        "analog output",
    ];

    for device in host.output_devices()? {
        if let Ok(name) = device.name() {
            let name_lower = name.to_lowercase();

            for pattern in &builtin_patterns {
                if name_lower.contains(pattern) {

                    if name_lower.contains("bluetooth") ||
                       name_lower.contains("airpods") ||
                       name_lower.contains("wireless") {
                        continue;
                    }

                    if name_lower.contains("blackhole") ||
                       name_lower.contains("vb-audio") ||
                       name_lower.contains("virtual") ||
                       name_lower.contains("loopback") {
                        continue;
                    }

                    info!("🔊 Found built-in speaker: '{}'", name);
                    return Ok(Some(AudioDevice::new(name, DeviceType::Output)));
                }
            }
        }
    }

    warn!("⚠️ No built-in speaker found (searched {} patterns)", builtin_patterns.len());
    Ok(None)
}