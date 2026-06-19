

use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};

use serde::Serialize;
use tauri::{AppHandle, Emitter, Runtime};

static MIC_PEAK_BITS: AtomicU32 = AtomicU32::new(0);
static SYS_PEAK_BITS: AtomicU32 = AtomicU32::new(0);

pub fn set_mic_peak(v: f32) {
    MIC_PEAK_BITS.store(v.to_bits(), Ordering::Relaxed);
}

pub fn set_sys_peak(v: f32) {
    SYS_PEAK_BITS.store(v.to_bits(), Ordering::Relaxed);
}

pub fn mic_peak() -> f32 {
    f32::from_bits(MIC_PEAK_BITS.load(Ordering::Relaxed))
}

pub fn sys_peak() -> f32 {
    f32::from_bits(SYS_PEAK_BITS.load(Ordering::Relaxed))
}

pub fn reset() {
    MIC_PEAK_BITS.store(0, Ordering::Relaxed);
    SYS_PEAK_BITS.store(0, Ordering::Relaxed);
}

static PUMP_RUNNING: AtomicBool = AtomicBool::new(false);

#[derive(Debug, Clone, Serialize)]
struct AudioLevelsPayload {
    microphone: LevelOne,
    system: LevelOne,
}

#[derive(Debug, Clone, Serialize)]
struct LevelOne {
    rms: f32,
    peak: f32,
}

pub fn start_pump<R: Runtime>(app: &AppHandle<R>) {
    if PUMP_RUNNING.swap(true, Ordering::SeqCst) {
        return;
    }
    reset();
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        while PUMP_RUNNING.load(Ordering::SeqCst) {
            let m = mic_peak();
            let s = sys_peak();
            let payload = AudioLevelsPayload {
                microphone: LevelOne { rms: m, peak: m },
                system: LevelOne { rms: s, peak: s },
            };
            let _ = app.emit("audio-levels", payload);

            set_mic_peak(m * 0.7);
            set_sys_peak(s * 0.7);
            tokio::time::sleep(std::time::Duration::from_millis(60)).await;
        }
    });
}

pub fn stop_pump() {
    PUMP_RUNNING.store(false, Ordering::SeqCst);
    reset();
}
