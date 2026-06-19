use crate::notifications::types::{Notification, NotificationPriority, NotificationTimeout};
use anyhow::{Result, anyhow};
use log::{info as log_info, error as log_error};
use tauri::{AppHandle, Runtime};
use tauri_plugin_notification::NotificationExt;
use std::time::Duration;

pub struct SystemNotificationHandler<R: Runtime> {
    app_handle: AppHandle<R>,
}

impl<R: Runtime> SystemNotificationHandler<R> {
    pub fn new(app_handle: AppHandle<R>) -> Self {
        Self {
            app_handle,
        }
    }

    pub async fn show_notification(&self, notification: Notification) -> Result<()> {
        log_info!("Attempting to show notification: {}", notification.title);

        if self.is_dnd_active().await && self.should_respect_dnd(&notification) {
            log_info!("DND is active, skipping notification: {}", notification.title);
            return Ok(());
        }

        log_info!("Showing Tauri notification: {}", notification.title);

        let builder = self.app_handle.notification().builder()
            .title(&notification.title)
            .body(&notification.body);

        match builder.show() {
            Ok(_) => {
                log_info!("Successfully showed Tauri notification: {}", notification.title);
                Ok(())
            }
            Err(e) => {
                log_error!("Failed to show Tauri notification: {}", e);
                Err(anyhow!("Failed to show notification: {}", e))
            }
        }
    }

    pub async fn is_dnd_active(&self) -> bool {

        false
    }

    pub async fn get_system_dnd_status(&self) -> bool {

        false
    }

    pub async fn request_permission(&self) -> Result<bool> {
        log_info!("Requesting notification permission");

        log_info!("Notification permission granted (automatic for Tauri apps)");
        Ok(true)
    }

    #[allow(dead_code)]
    async fn show_test_notification(&self) -> Result<()> {
        let test_notification = Notification::test_notification();
        self.show_notification(test_notification).await
    }

    fn should_respect_dnd(&self, notification: &Notification) -> bool {
        match notification.priority {
            NotificationPriority::Critical => false,
            _ => true,
        }
    }

    pub async fn clear_notifications(&self) -> Result<()> {
        log_info!("Clearing all notifications");

        Ok(())
    }
}

impl From<&NotificationTimeout> for Option<Duration> {
    fn from(timeout: &NotificationTimeout) -> Self {
        match timeout {
            NotificationTimeout::Never => None,
            NotificationTimeout::Seconds(secs) => Some(Duration::from_secs(*secs)),
            NotificationTimeout::Default => Some(Duration::from_secs(5)),
        }
    }
}