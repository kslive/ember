

use anyhow::Result;
use log::{info, warn};

use super::configuration::AudioDevice;
use super::microphone::{default_input_device, find_builtin_input_device};
use super::speakers::default_output_device;
use crate::audio::device_detection::InputDeviceKind;

#[cfg(target_os = "macos")]
pub fn get_safe_recording_devices_macos() -> Result<(Option<AudioDevice>, Option<AudioDevice>)> {
    info!("🔍 [macOS] Selecting recording devices with Bluetooth detection...");

    let default_mic = default_input_device().ok();
    let default_speaker = default_output_device().ok();

    let final_mic = if let Some(ref mic) = default_mic {

        let device_kind = InputDeviceKind::detect(&mic.name, 512, 48000);

        if device_kind.is_bluetooth() {
            warn!("🎧 Bluetooth microphone detected: '{}'", mic.name);
            warn!("   Bluetooth introduces variable sample rates with Core Audio");

            match find_builtin_input_device()? {
                Some(builtin_mic) => {
                    info!("→ ✅ Overriding to stable built-in microphone: '{}'", builtin_mic.name);
                    info!("   Built-in provides consistent sample rates for reliable mixing");
                    Some(builtin_mic)
                }
                None => {
                    warn!("→ ⚠️ No built-in microphone found - using Bluetooth anyway");
                    warn!("   Recording may experience sample rate sync issues");
                    warn!("   Consider using wired microphone for better stability");
                    Some(mic.clone())
                }
            }
        } else {

            info!("✅ Using wired/built-in microphone: '{}' (device type: {:?})", mic.name, device_kind);
            Some(mic.clone())
        }
    } else {
        warn!("⚠️ No default microphone found");
        None
    };

    let final_speaker = if let Some(ref speaker) = default_speaker {
        let device_kind = InputDeviceKind::detect(&speaker.name, 512, 48000);

        if device_kind.is_bluetooth() {
            warn!("🔊 Bluetooth speaker detected: '{}'", speaker.name);
            info!("   macOS: ScreenCaptureKit captures digital stream BEFORE Bluetooth encoding");
            info!("   Keeping Bluetooth speaker - captures from active output (pristine quality)");
            Some(speaker.clone())
        } else {
            info!("✅ Using wired/built-in speaker: '{}' (device type: {:?})", speaker.name, device_kind);
            Some(speaker.clone())
        }
    } else {
        warn!("⚠️ No default speaker found - system audio will not be recorded");
        None
    };

    match (&final_mic, &final_speaker) {
        (Some(mic), Some(speaker)) => {
            info!("📋 [macOS] Recording device selection complete:");
            info!("   Microphone: '{}'", mic.name);
            info!("   System Audio: '{}' (via ScreenCaptureKit)", speaker.name);
        }
        (Some(mic), None) => {
            info!("📋 [macOS] Recording device selection complete:");
            info!("   Microphone: '{}' (system audio unavailable)", mic.name);
        }
        (None, Some(speaker)) => {
            warn!("📋 [macOS] Recording device selection complete:");
            warn!("   System Audio: '{}' (microphone unavailable)", speaker.name);
        }
        (None, None) => {
            warn!("❌ No recording devices available - cannot start recording");
        }
    }

    Ok((final_mic, final_speaker))
}

#[cfg(not(target_os = "macos"))]
pub fn get_safe_recording_devices() -> Result<(Option<AudioDevice>, Option<AudioDevice>)> {
    info!("🔍 Selecting default recording devices (no Bluetooth override on this platform)");

    let mic = default_input_device().ok();
    let speaker = default_output_device().ok();

    Ok((mic, speaker))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[cfg(target_os = "macos")]
    fn test_bluetooth_override_logic() {

    }
}
