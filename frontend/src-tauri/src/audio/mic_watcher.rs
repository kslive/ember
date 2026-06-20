

use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use serde::Serialize;
use tauri::{AppHandle, Emitter, Runtime};

#[cfg(target_os = "macos")]
use cidre::core_audio as ca;

static RUNNING: AtomicBool = AtomicBool::new(false);

static FORCE_REEMIT: AtomicBool = AtomicBool::new(false);

static AUTO_SESSION: AtomicBool = AtomicBool::new(false);

const AUTOSTART_DEBOUNCE_SECS: u32 = 5;

#[derive(Debug, Clone, Serialize)]
struct MicUsagePayload {
    active: bool,
    pids: Vec<i32>,
}

#[cfg(target_os = "macos")]
fn list_external_input_pids(self_pid: i32) -> Vec<i32> {
    let processes = match ca::System::processes() {
        Ok(p) => p,
        Err(e) => {
            log::warn!("mic_watcher: System::processes failed: {:?}", e);
            return Vec::new();
        }
    };

    let mut external = Vec::new();
    for proc in processes {
        let pid = match proc.pid() {
            Ok(p) => p,
            Err(_) => continue,
        };
        if pid as i32 == self_pid || pid == 0 {
            continue;
        }
        match proc.is_running_input() {
            Ok(true) => external.push(pid as i32),
            _ => {}
        }
    }
    external
}

#[cfg(not(target_os = "macos"))]
fn list_external_input_pids(_self_pid: i32) -> Vec<i32> {
    Vec::new()
}

pub fn start<R: Runtime>(app: &AppHandle<R>) {
    if RUNNING.swap(true, Ordering::SeqCst) {
        return;
    }
    let app = app.clone();
    let self_pid = std::process::id() as i32;
    log::info!("mic_watcher: starting (self_pid = {})", self_pid);

    tauri::async_runtime::spawn(async move {
        let mut last_active = false;
        let mut last_pids: Vec<i32> = Vec::new();
        let mut tick: u64 = 0;

        let mut active_secs: u32 = 0;

        while RUNNING.load(Ordering::SeqCst) {
            let pids = list_external_input_pids(self_pid);
            let active = !pids.is_empty();

            tick += 1;
            if tick % 15 == 0 {
                log::debug!("mic_watcher tick: external input pids = {:?} (active={})", pids, active);
            }

            let forced = FORCE_REEMIT.swap(false, Ordering::SeqCst);
            if forced || active != last_active || pids != last_pids {
                log::info!("mic_watcher: state change → active={}, pids={:?}", active, pids);
                let _ = app.emit("mic-usage-changed", MicUsagePayload { active, pids: pids.clone() });
                last_active = active;
                last_pids = pids;
            }

            let recording = crate::audio::recording_commands::is_recording().await;
            if active {
                if recording {
                    active_secs = 0;
                } else {
                    active_secs = active_secs.saturating_add(1);
                    if active_secs >= AUTOSTART_DEBOUNCE_SECS && !AUTO_SESSION.load(Ordering::SeqCst) {
                        let ts = chrono::Local::now().format("%Y-%m-%d %H:%M").to_string();
                        let prefix = match crate::current_locale(&app).as_str() {
                            "ru" => "Запись",
                            "zh" => "录音",
                            _ => "Recording",
                        };
                        log::info!("mic_watcher: external mic active {}s → auto-starting recording", active_secs);
                        match crate::audio::recording_commands::start_recording_with_meeting_name(
                            app.clone(),
                            Some(format!("{} {}", prefix, ts)),
                        ).await {
                            Ok(()) => AUTO_SESSION.store(true, Ordering::SeqCst),
                            Err(e) => log::error!("mic_watcher: auto-start failed: {}", e),
                        }
                        active_secs = 0;
                    }
                }
            } else {
                active_secs = 0;
                if AUTO_SESSION.load(Ordering::SeqCst) {
                    if recording {
                        log::info!("mic_watcher: external mic released → auto-stopping recording");
                        if let Err(e) = crate::audio::recording_commands::auto_stop_recording(app.clone()).await {
                            log::error!("mic_watcher: auto-stop failed: {}", e);
                        }
                    }
                    AUTO_SESSION.store(false, Ordering::SeqCst);
                }
            }

            tokio::time::sleep(Duration::from_millis(1000)).await;
        }
        log::info!("mic_watcher: stopped");
    });
}

pub fn stop() {
    RUNNING.store(false, Ordering::SeqCst);
}

#[tauri::command]
pub fn mic_watcher_resync() {
    FORCE_REEMIT.store(true, Ordering::SeqCst);
}
