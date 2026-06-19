use tauri::{
    Emitter,
    menu::{MenuBuilder, MenuItemBuilder, PredefinedMenuItem},
    tray::TrayIconBuilder,
    AppHandle, Manager, Runtime,
};

#[derive(Debug, Clone)]
pub enum RecordingState {
    Stopped,
    Starting,
    Recording,
    Pausing,
    Paused,
    Resuming,
    Stopping,
}

fn tray_glyph_rgba(rgb: [u8; 3]) -> (Vec<u8>, u32, u32) {
    const W: usize = 44;
    const H: usize = 44;
    let mut rgba = vec![0u8; W * H * 4];
    let scale = W as f32 / 24.0;

    struct Arc { cx: f32, cy: f32, r: f32, side: f32, y0: f32, y1: f32 }
    let arcs = [
        Arc { cx: 12.43, cy: 12.0, r: 5.0, side:  1.0, y0: 8.5, y1: 15.5 },
        Arc { cx: 11.57, cy: 12.0, r: 5.0, side: -1.0, y0: 8.5, y1: 15.5 },
        Arc { cx: 12.57, cy: 12.0, r: 9.5, side:  1.0, y0: 5.5, y1: 18.5 },
        Arc { cx: 11.43, cy: 12.0, r: 9.5, side: -1.0, y0: 5.5, y1: 18.5 },
    ];
    let hw = 1.0f32;
    let aa = 0.9f32;
    let (dot_x, dot_y, dot_r) = (12.0f32, 12.0f32, 2.4f32);

    for py in 0..H {
        for px in 0..W {
            let x = (px as f32 + 0.5) / scale;
            let y = (py as f32 + 0.5) / scale;
            let mut cov = 0.0f32;

            for a in &arcs {
                if (x - a.cx) * a.side < -0.05 { continue; }
                if y < a.y0 - 0.2 || y > a.y1 + 0.2 { continue; }
                let d = (((x - a.cx).powi(2) + (y - a.cy).powi(2)).sqrt() - a.r).abs();
                cov = cov.max((0.5 + (hw - d) / aa).clamp(0.0, 1.0));
            }
            let dd = ((x - dot_x).powi(2) + (y - dot_y).powi(2)).sqrt() - dot_r;
            cov = cov.max((0.5 - dd / aa).clamp(0.0, 1.0));

            if cov > 0.0 {
                let idx = (py * W + px) * 4;
                rgba[idx] = rgb[0];
                rgba[idx + 1] = rgb[1];
                rgba[idx + 2] = rgb[2];
                rgba[idx + 3] = (cov * 255.0) as u8;
            }
        }
    }

    (rgba, W as u32, H as u32)
}

fn apply_tray_icon<R: Runtime>(app: &AppHandle<R>, recording: bool) {
    if let Some(tray) = app.tray_by_id("main-tray") {
        let rgb = if recording { [249u8, 115, 22] } else { [0u8, 0, 0] };
        let (rgba, w, h) = tray_glyph_rgba(rgb);
        let _ = tray.set_icon(Some(tauri::image::Image::new_owned(rgba, w, h)));
        let _ = tray.set_icon_as_template(!recording);
    }
}

pub fn create_tray<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<()> {

    let menu = build_menu(app, RecordingState::Stopped, true)?;

    let (rgba, w, h) = tray_glyph_rgba([0, 0, 0]);
    let icon = tauri::image::Image::new_owned(rgba, w, h);

    TrayIconBuilder::with_id("main-tray")
        .menu(&menu)
        .tooltip("Ember")
        .icon(icon)
        .icon_as_template(true)
        .on_menu_event(|app, event| handle_menu_event(app, event.id.as_ref()))
        .build(app)?;

    update_tray_menu(app);

    Ok(())
}

fn handle_menu_event<R: Runtime>(app: &AppHandle<R>, item_id: &str) {
    match item_id {
        "toggle_recording" => toggle_recording_handler(app),
        "pause_recording" => pause_recording_handler(app),
        "resume_recording" => resume_recording_handler(app),
        "stop_recording" => stop_recording_handler(app),
        "open_window" => focus_main_window(app),
        "settings" => {
            focus_main_window(app);
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.eval("window.location.assign('/settings')");
            }
        }
        "quit" => app.exit(0),
        _ => {}
    }
}
fn toggle_recording_handler<R: Runtime>(app: &AppHandle<R>) {

    let app_clone = app.clone();
    tauri::async_runtime::spawn(async move {
        if crate::is_recording().await {

            set_tray_state(&app_clone, RecordingState::Stopping);

            log::info!("Tray toggle: Stopping recording...");

            let data_dir = match app_clone.path().app_data_dir() {
                Ok(dir) => dir,
                Err(e) => {
                    log::error!("Failed to get app data dir: {}", e);
                    update_tray_menu_async(&app_clone).await;
                    return;
                }
            };

            let timestamp = chrono::Local::now().format("%Y-%m-%dT%H-%M-%S").to_string();
            let save_path = data_dir.join(format!("recording-{}.wav", timestamp));

            let stop_result = crate::audio::recording_commands::stop_recording(
                app_clone.clone(),
                crate::audio::recording_commands::RecordingArgs {
                    save_path: save_path.to_string_lossy().to_string(),
                },
            )
            .await;

            match stop_result {
                Ok(_) => {
                    log::info!("Tray toggle: Recording stopped successfully");

                    if let Err(e) = app_clone.emit("recording-stop-complete", true) {
                        log::error!("Tray toggle: Failed to emit recording-stop-complete event: {}", e);
                    }
                }
                Err(e) => {
                    log::error!("Tray toggle: Failed to stop recording: {}", e);

                    update_tray_menu_async(&app_clone).await;
                }
            }
        } else {

            set_tray_state(&app_clone, RecordingState::Starting);

            log::info!("Tray toggle: starting recording directly via Rust command (no frontend round-trip)");

            let ts = chrono::Local::now().format("%Y-%m-%d %H:%M").to_string();
            let meeting_name = format!("Запись {}", ts);

            match crate::audio::recording_commands::start_recording_with_meeting_name(
                app_clone.clone(),
                Some(meeting_name),
            )
            .await
            {
                Ok(()) => {
                    log::info!("Tray toggle: recording started from tray");

                }
                Err(e) => {
                    log::error!("Tray toggle: failed to start recording: {}", e);

                    set_tray_state(&app_clone, RecordingState::Stopped);
                    update_tray_menu_async(&app_clone).await;

                    let _ = app_clone.emit("tray-start-failed", e);
                }
            }
        }
    });
}

fn pause_recording_handler<R: Runtime>(app: &AppHandle<R>) {

    set_tray_state(app, RecordingState::Pausing);

    let app_clone = app.clone();
    tauri::async_runtime::spawn(async move {
        if let Err(e) = crate::audio::recording_commands::pause_recording(app_clone.clone()).await {
            log::error!("Failed to pause recording from tray: {}", e);

            update_tray_menu_async(&app_clone).await;
        } else {
            log::info!("Recording paused from tray");

        }
    });
}

fn resume_recording_handler<R: Runtime>(app: &AppHandle<R>) {

    set_tray_state(app, RecordingState::Resuming);

    let app_clone = app.clone();
    tauri::async_runtime::spawn(async move {
        if let Err(e) = crate::audio::recording_commands::resume_recording(app_clone.clone()).await
        {
            log::error!("Failed to resume recording from tray: {}", e);

            update_tray_menu_async(&app_clone).await;
        } else {
            log::info!("Recording resumed from tray");

        }
    });
}

fn stop_recording_handler<R: Runtime>(app: &AppHandle<R>) {

    set_tray_state(app, RecordingState::Stopping);

    let app_clone = app.clone();
    tauri::async_runtime::spawn(async move {
        log::info!("Tray: Stopping recording...");

        let data_dir = match app_clone.path().app_data_dir() {
            Ok(dir) => dir,
            Err(e) => {
                log::error!("Failed to get app data dir: {}", e);
                update_tray_menu_async(&app_clone).await;
                return;
            }
        };

        let timestamp = chrono::Local::now().format("%Y-%m-%dT%H-%M-%S").to_string();
        let save_path = data_dir.join(format!("recording-{}.wav", timestamp));

        let stop_result = crate::audio::recording_commands::stop_recording(
            app_clone.clone(),
            crate::audio::recording_commands::RecordingArgs {
                save_path: save_path.to_string_lossy().to_string(),
            },
        )
        .await;

        match stop_result {
            Ok(_) => {
                log::info!("Tray: Recording stopped successfully");

                if let Err(e) = app_clone.emit("recording-stop-complete", true) {
                    log::error!("Tray: Failed to emit recording-stop-complete event: {}", e);
                }
            }
            Err(e) => {
                log::error!("Tray: Failed to stop recording: {}", e);

                update_tray_menu_async(&app_clone).await;
            }
        }
    });
}

pub fn update_tray_menu<R: Runtime>(app: &AppHandle<R>) {

    let app_clone = app.clone();
    tauri::async_runtime::spawn(async move {

        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
        update_tray_menu_async(&app_clone).await;
    });
}

pub fn set_tray_state<R: Runtime>(app: &AppHandle<R>, state: RecordingState) {
    log::info!("Tray: Setting intermediate state: {:?}", state);

    if let Ok(menu) = build_menu(app, state, true) {
        if let Some(tray) = app.tray_by_id("main-tray") {
            let result = tray.set_menu(Some(menu));
            log::info!("Tray: Intermediate state menu update result: {:?}", result);
        } else {
            log::warn!("Tray: Could not find tray with id 'main-tray'");
        }
    } else {
        log::error!("Tray: Failed to build menu for intermediate state");
    }
}

async fn get_current_recording_state() -> RecordingState {

    let is_recording = crate::audio::recording_commands::is_recording().await;
    log::info!(
        "Tray: get_current_recording_state - is_recording: {}",
        is_recording
    );

    if !is_recording {
        log::info!("Tray: Recording state is Stopped");
        return RecordingState::Stopped;
    }

    let is_paused = crate::audio::recording_commands::is_recording_paused().await;
    log::info!("Tray: is_paused: {}", is_paused);

    if is_paused {
        log::info!("Tray: Recording state is Paused");
        RecordingState::Paused
    } else {
        log::info!("Tray: Recording state is Recording");
        RecordingState::Recording
    }
}

async fn check_can_record<R: Runtime>(app: &AppHandle<R>) -> bool {

    let onboarding_complete = match crate::onboarding::load_onboarding_status(app).await {
        Ok(status) => status.completed,
        Err(e) => {
            log::warn!("Tray: Failed to load onboarding status: {}, assuming complete", e);
            true
        }
    };

    if onboarding_complete {
        return true;
    }

    match crate::parakeet_engine::commands::parakeet_has_available_models().await {
        Ok(has_models) => has_models,
        Err(e) => {
            log::warn!("Tray: Failed to check Parakeet models: {}, assuming not ready", e);
            false
        }
    }
}

pub async fn update_tray_menu_async<R: Runtime>(app: &AppHandle<R>) {
    log::info!("Tray: update_tray_menu_async called");

    let recording_state = get_current_recording_state().await;
    log::info!("Tray: Current recording state: {:?}", recording_state);

    let can_record = check_can_record(app).await;
    log::info!("Tray: can_record: {}", can_record);

    if let Ok(menu) = build_menu(app, recording_state, can_record) {
        if let Some(tray) = app.tray_by_id("main-tray") {
            let result = tray.set_menu(Some(menu));
            log::info!("Tray: Menu update result: {:?}", result);
        } else {
            log::warn!("Tray: Could not find tray with id 'main-tray'");
        }
    } else {
        log::error!("Tray: Failed to build menu");
    }
}

fn build_menu<R: Runtime>(
    app: &AppHandle<R>,
    state: RecordingState,
    can_record: bool,
) -> tauri::Result<tauri::menu::Menu<R>> {
    let mut builder = MenuBuilder::new(app);

    if !can_record {
        builder = builder.item(
            &MenuItemBuilder::new("⏳ Загрузка модели расшифровки…")
                .enabled(false)
                .build(app)?,
        );
    } else {
        match state {
            RecordingState::Stopped => {
                builder = builder
                    .item(&MenuItemBuilder::with_id("toggle_recording", "Начать запись").build(app)?);
            }
            RecordingState::Starting => {
                builder = builder.item(
                    &MenuItemBuilder::new("🔄 Запуск записи…")
                        .enabled(false)
                        .build(app)?,
                );
            }
            RecordingState::Recording => {
                builder = builder
                    .item(&MenuItemBuilder::with_id("pause_recording", "⏸ Пауза записи").build(app)?)
                    .item(&MenuItemBuilder::with_id("stop_recording", "⏹ Остановить запись").build(app)?);
            }
            RecordingState::Pausing => {
                builder = builder
                    .item(
                        &MenuItemBuilder::new("⏸ Пауза…")
                            .enabled(false)
                            .build(app)?,
                    )
                    .item(&MenuItemBuilder::with_id("stop_recording", "⏹ Остановить запись").build(app)?);
            }
            RecordingState::Paused => {
                builder = builder
                    .item(
                        &MenuItemBuilder::with_id("resume_recording", "▶ Продолжить запись")
                            .build(app)?,
                    )
                    .item(&MenuItemBuilder::with_id("stop_recording", "⏹ Остановить запись").build(app)?);
            }
            RecordingState::Resuming => {
                builder = builder
                    .item(
                        &MenuItemBuilder::new("▶ Возобновление…")
                            .enabled(false)
                            .build(app)?,
                    )
                    .item(&MenuItemBuilder::with_id("stop_recording", "⏹ Остановить запись").build(app)?);
            }
            RecordingState::Stopping => {
                builder = builder.item(
                    &MenuItemBuilder::new("⏹ Остановка…")
                        .enabled(false)
                        .build(app)?,
                );
            }
        }
    }

    builder
        .item(&PredefinedMenuItem::separator(app)?)
        .item(&MenuItemBuilder::with_id("open_window", "Открыть главное окно").build(app)?)
        .item(&MenuItemBuilder::with_id("settings", "Настройки").build(app)?)
        .item(&PredefinedMenuItem::separator(app)?)
        .item(&MenuItemBuilder::with_id("quit", "Выход").build(app)?)
        .build()
}

fn focus_main_window<R: Runtime>(app: &AppHandle<R>) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
        let _ = window.eval("window.focus()");
    } else {
        log::warn!("Could not find main window");
    }
}
