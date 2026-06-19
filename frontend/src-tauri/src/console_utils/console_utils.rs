#[cfg(target_os = "windows")]
use std::ptr;
#[cfg(target_os = "windows")]
use env_logger;
#[cfg(target_os = "macos")]
use std::process::Command;

#[cfg(target_os = "windows")]
#[link(name = "kernel32")]
extern "system" {
    fn AllocConsole() -> i32;
    #[allow(dead_code)]
    fn FreeConsole() -> i32;
    fn GetConsoleWindow() -> *mut std::ffi::c_void;
    fn ShowWindow(hwnd: *mut std::ffi::c_void, n_cmd_show: i32) -> i32;
}

#[cfg(target_os = "windows")]
const SW_HIDE: i32 = 0;
#[cfg(target_os = "windows")]
const SW_SHOW: i32 = 5;

#[tauri::command]
pub fn show_console() -> Result<String, String> {
    #[cfg(target_os = "windows")]
    unsafe {
        let console_window = GetConsoleWindow();
        if console_window == ptr::null_mut() {

            if AllocConsole() == 0 {
                return Err("Failed to allocate console".to_string());
            }

            std::env::set_var("RUST_LOG", "info");
            env_logger::init();
        } else {

            ShowWindow(console_window, SW_SHOW);
        }
        Ok("Console shown".to_string())
    }

    #[cfg(target_os = "macos")]
    {

        match Command::new("osascript")
            .arg("-e")
            .arg(r#"
                tell application "Terminal"
                    activate
                    do script "log stream --process ember --level info --style compact"
                end tell
            "#)
            .spawn()
        {
            Ok(_) => Ok("Console opened in Terminal".to_string()),
            Err(e) => Err(format!("Failed to open console: {}", e)),
        }
    }

    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        Ok("Console control is only available on Windows and macOS".to_string())
    }
}

#[tauri::command]
pub fn hide_console() -> Result<String, String> {
    #[cfg(target_os = "windows")]
    unsafe {
        let console_window = GetConsoleWindow();
        if console_window != ptr::null_mut() {
            ShowWindow(console_window, SW_HIDE);
            Ok("Console hidden".to_string())
        } else {
            Err("No console window found".to_string())
        }
    }

    #[cfg(target_os = "macos")]
    {

        match Command::new("osascript")
            .arg("-e")
            .arg(r#"
                tell application "Terminal"
                    set windowList to windows
                    repeat with aWindow in windowList
                        if contents of selected tab of aWindow contains "log stream --process ember" then
                            close aWindow
                        end if
                    end repeat
                end tell
            "#)
            .spawn()
        {
            Ok(_) => Ok("Console closed".to_string()),
            Err(e) => Err(format!("Failed to close console: {}", e)),
        }
    }

    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        Ok("Console control is only available on Windows and macOS".to_string())
    }
}

#[tauri::command]
pub fn toggle_console() -> Result<String, String> {
    #[cfg(target_os = "windows")]
    unsafe {
        let console_window = GetConsoleWindow();
        if console_window == ptr::null_mut() {
            show_console()
        } else {

            hide_console()
        }
    }

    #[cfg(target_os = "macos")]
    {

        let check_result = Command::new("osascript")
            .arg("-e")
            .arg(r#"
                tell application "Terminal"
                    set windowList to windows
                    repeat with aWindow in windowList
                        if contents of selected tab of aWindow contains "log stream --process ember" then
                            return "found"
                        end if
                    end repeat
                    return "not found"
                end tell
            "#)
            .output();

        match check_result {
            Ok(output) => {
                let output_str = String::from_utf8_lossy(&output.stdout);
                if output_str.trim() == "found" {
                    hide_console()
                } else {
                    show_console()
                }
            }
            Err(_) => show_console()
        }
    }

    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        Ok("Console control is only available on Windows and macOS".to_string())
    }
}