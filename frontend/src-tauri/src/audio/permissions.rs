
use anyhow::Result;
use log::{info, warn, error};

#[cfg(target_os = "macos")]
use std::process::Command;

#[cfg(target_os = "macos")]
pub fn check_screen_recording_permission() -> bool {
    info!("ℹ️  Core Audio tap requires Audio Capture permission (macOS 14.4+)");
    info!("📍 Permission dialog will appear automatically when recording starts");
    info!("   If already granted: System Settings → Privacy & Security → Audio Capture");

    true
}

#[cfg(not(target_os = "macos"))]
pub fn check_screen_recording_permission() -> bool {
    true
}

#[cfg(target_os = "macos")]
pub fn request_screen_recording_permission() -> Result<()> {
    info!("🔐 Opening System Settings for Audio Capture permission...");

    let result = Command::new("open")
        .arg("x-apple.systempreferences:com.apple.preference.security")
        .spawn();

    match result {
        Ok(_) => {
            info!("✅ Opened System Settings - navigate to Privacy & Security → Audio Capture");
            info!("👉 Please enable Audio Capture permission and restart the app");
            Ok(())
        }
        Err(e) => {
            error!("❌ Failed to open System Settings: {}", e);
            Err(anyhow::anyhow!("Failed to open System Settings: {}", e))
        }
    }
}

#[cfg(not(target_os = "macos"))]
pub fn request_screen_recording_permission() -> Result<()> {
    Ok(())
}

pub fn ensure_screen_recording_permission() -> bool {
    if check_screen_recording_permission() {
        return true;
    }

    warn!("Audio Capture permission not granted - requesting...");

    if let Err(e) = request_screen_recording_permission() {
        error!("Failed to request Audio Capture permission: {}", e);
        return false;
    }

    false
}

#[tauri::command]
pub async fn check_screen_recording_permission_command() -> bool {
    check_screen_recording_permission()
}

#[tauri::command]
pub async fn request_screen_recording_permission_command() -> Result<(), String> {
    request_screen_recording_permission()
        .map_err(|e| e.to_string())
}

#[cfg(target_os = "macos")]
pub fn trigger_system_audio_permission() -> Result<bool> {
    info!("🔐 Triggering Audio Capture permission request...");

    match crate::audio::capture::CoreAudioCapture::new() {
        Ok(capture) => {
            info!("✅ Core Audio tap created successfully");

            match capture.stream() {
                Ok(_stream) => {
                    std::thread::sleep(std::time::Duration::from_millis(600));
                    info!("✅ Audio Capture stream started — permission prompt shown if needed");
                    Ok(true)
                }
                Err(e) => {
                    let error_msg = e.to_string().to_lowercase();
                    if error_msg.contains("permission") || error_msg.contains("denied") {
                        info!("🔐 Audio Capture permission denied");
                        return Ok(false);
                    }
                    warn!("⚠️ Failed to start Core Audio stream: {}", e);
                    Ok(false)
                }
            }
        }
        Err(e) => {
            let error_msg = e.to_string().to_lowercase();
            if error_msg.contains("permission") || error_msg.contains("denied") {
                info!("🔐 Audio Capture permission denied");
                info!("👉 Please grant Audio Capture permission in System Settings");
                return Ok(false);
            }
            warn!("⚠️ Failed to create Core Audio tap: {}", e);

            Ok(false)
        }
    }
}

#[cfg(not(target_os = "macos"))]
pub fn trigger_system_audio_permission() -> Result<bool> {

    info!("System audio permissions not required on this platform");
    Ok(true)
}

#[tauri::command]
pub async fn trigger_system_audio_permission_command() -> Result<bool, String> {

    tokio::task::spawn_blocking(|| {
        trigger_system_audio_permission()
    })
    .await
    .map_err(|e| format!("Task join error: {}", e))?
    .map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_check_permission() {
        let has_permission = check_screen_recording_permission();
        println!("Has Screen Recording permission: {}", has_permission);
    }
}