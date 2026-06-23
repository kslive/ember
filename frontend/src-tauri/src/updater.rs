use serde::Serialize;
use tauri::AppHandle;
use tauri_plugin_updater::UpdaterExt;

#[derive(Serialize)]
pub struct UpdateInfo {
    pub available: bool,
    pub version: String,
    pub notes: Option<String>,
    pub pub_date: Option<String>,
}

#[tauri::command]
pub async fn check_update(app: AppHandle) -> Result<UpdateInfo, String> {
    let updater = app
        .updater()
        .map_err(|e| format!("Failed to build updater: {}", e))?;

    match updater
        .check()
        .await
        .map_err(|e| format!("Failed to check for updates: {}", e))?
    {
        Some(update) => Ok(UpdateInfo {
            available: true,
            version: update.version,
            notes: update.body,
            pub_date: update.date.map(|d| d.to_string()),
        }),
        None => Ok(UpdateInfo {
            available: false,
            version: app.package_info().version.to_string(),
            notes: None,
            pub_date: None,
        }),
    }
}

#[tauri::command]
pub async fn install_update(app: AppHandle) -> Result<(), String> {
    let updater = app
        .updater()
        .map_err(|e| format!("Failed to build updater: {}", e))?;

    let update = updater
        .check()
        .await
        .map_err(|e| format!("Failed to check for updates: {}", e))?;

    if let Some(update) = update {
        update
            .download_and_install(|_chunk, _total| {}, || {})
            .await
            .map_err(|e| format!("Failed to download and install update: {}", e))?;

        #[cfg(target_os = "macos")]
        {
            if let Ok(exe) = std::env::current_exe() {
                if let Some(app_bundle) = exe
                    .ancestors()
                    .find(|p| p.extension().map(|e| e == "app").unwrap_or(false))
                {
                    let _ = std::process::Command::new("xattr")
                        .args(["-dr", "com.apple.quarantine"])
                        .arg(app_bundle)
                        .status();
                }
            }
        }

        app.restart();
    }

    Ok(())
}
