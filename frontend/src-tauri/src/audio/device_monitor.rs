
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use anyhow::Result;
use log::{debug, info, warn, error};

use super::devices::{AudioDevice, list_audio_devices};

#[derive(Debug, Clone)]
pub enum DeviceEvent {

    DeviceDisconnected {
        device_name: String,
        device_type: DeviceMonitorType,
    },

    DeviceReconnected {
        device_name: String,
        device_type: DeviceMonitorType,
    },

    DeviceListChanged,
}

#[derive(Debug, Clone, PartialEq)]
pub enum DeviceMonitorType {
    Microphone,
    SystemAudio,
}

#[derive(Debug, Clone)]
struct MonitoredDevice {
    name: String,
    device_type: DeviceMonitorType,
    consecutive_missing: u32,
    is_bluetooth: bool,
}

impl MonitoredDevice {
    fn new(name: String, device_type: DeviceMonitorType) -> Self {

        let is_bluetooth = name.to_lowercase().contains("airpods")
            || name.to_lowercase().contains("bluetooth")
            || name.to_lowercase().contains("wireless");

        Self {
            name,
            device_type,
            consecutive_missing: 0,
            is_bluetooth,
        }
    }

    fn disconnect_threshold(&self) -> u32 {

        if self.is_bluetooth {
            3
        } else {
            2
        }
    }

    #[allow(dead_code)]
    fn reconnect_interval(&self) -> Duration {
        if self.is_bluetooth {
            Duration::from_secs(5)
        } else {
            Duration::from_secs(3)
        }
    }
}

pub struct AudioDeviceMonitor {
    monitor_handle: Option<JoinHandle<()>>,
    event_sender: mpsc::UnboundedSender<DeviceEvent>,
    stop_signal: Arc<tokio::sync::Notify>,
}

impl AudioDeviceMonitor {

    pub fn new() -> (Self, mpsc::UnboundedReceiver<DeviceEvent>) {
        let (event_sender, event_receiver) = mpsc::unbounded_channel();
        let stop_signal = Arc::new(tokio::sync::Notify::new());

        (
            Self {
                monitor_handle: None,
                event_sender,
                stop_signal,
            },
            event_receiver,
        )
    }

    pub fn start_monitoring(
        &mut self,
        microphone: Option<Arc<AudioDevice>>,
        system_audio: Option<Arc<AudioDevice>>,
    ) -> Result<()> {
        if self.monitor_handle.is_some() {
            warn!("Device monitor already running");
            return Ok(());
        }

        let mut monitored_devices = Vec::new();

        if let Some(mic) = microphone {
            monitored_devices.push(MonitoredDevice::new(
                mic.name.clone(),
                DeviceMonitorType::Microphone,
            ));
            info!("🔍 Monitoring microphone: '{}' (Bluetooth: {})",
                  mic.name, monitored_devices.last().unwrap().is_bluetooth);
        }

        if let Some(sys) = system_audio {
            monitored_devices.push(MonitoredDevice::new(
                sys.name.clone(),
                DeviceMonitorType::SystemAudio,
            ));
            info!("🔍 Monitoring system audio: '{}' (Bluetooth: {})",
                  sys.name, monitored_devices.last().unwrap().is_bluetooth);
        }

        if monitored_devices.is_empty() {
            return Err(anyhow::anyhow!("No devices to monitor"));
        }

        let event_sender = self.event_sender.clone();
        let stop_signal = self.stop_signal.clone();

        let handle = tokio::spawn(async move {
            Self::monitor_loop(monitored_devices, event_sender, stop_signal).await;
        });

        self.monitor_handle = Some(handle);
        info!("✅ Device monitor started");
        Ok(())
    }

    pub async fn stop_monitoring(&mut self) {
        info!("Stopping device monitor");
        self.stop_signal.notify_one();

        if let Some(handle) = self.monitor_handle.take() {
            let _ = handle.await;
        }

        info!("Device monitor stopped");
    }

    async fn monitor_loop(
        mut monitored_devices: Vec<MonitoredDevice>,
        event_sender: mpsc::UnboundedSender<DeviceEvent>,
        stop_signal: Arc<tokio::sync::Notify>,
    ) {
        let mut last_device_list = Vec::new();
        let check_interval = Duration::from_secs(2);

        loop {

            tokio::select! {
                _ = stop_signal.notified() => {
                    info!("Device monitor received stop signal");
                    break;
                }
                _ = tokio::time::sleep(check_interval) => {

                }
            }

            let current_devices = match list_audio_devices().await {
                Ok(devices) => devices,
                Err(e) => {
                    error!("Failed to list audio devices: {}", e);
                    continue;
                }
            };

            if current_devices.len() != last_device_list.len() {
                debug!("Device list changed: {} -> {} devices",
                       last_device_list.len(), current_devices.len());
                let _ = event_sender.send(DeviceEvent::DeviceListChanged);
            }
            last_device_list = current_devices.clone();

            for monitored in &mut monitored_devices {
                let device_found = current_devices.iter().any(|d| d.name == monitored.name);

                if device_found {

                    if monitored.consecutive_missing > 0 {

                        info!("✅ Device '{}' reconnected after {} missing checks",
                              monitored.name, monitored.consecutive_missing);

                        let _ = event_sender.send(DeviceEvent::DeviceReconnected {
                            device_name: monitored.name.clone(),
                            device_type: monitored.device_type.clone(),
                        });

                        monitored.consecutive_missing = 0;
                    }
                } else {

                    monitored.consecutive_missing += 1;

                    debug!("⚠️ Device '{}' missing for {} checks (threshold: {})",
                          monitored.name, monitored.consecutive_missing,
                          monitored.disconnect_threshold());

                    if monitored.consecutive_missing == monitored.disconnect_threshold() {
                        warn!("❌ Device '{}' ({:?}) disconnected!",
                              monitored.name, monitored.device_type);

                        let _ = event_sender.send(DeviceEvent::DeviceDisconnected {
                            device_name: monitored.name.clone(),
                            device_type: monitored.device_type.clone(),
                        });
                    }
                }
            }

            let has_missing = monitored_devices.iter().any(|d| d.consecutive_missing > 0);
            let next_interval = if has_missing {
                Duration::from_secs(2)
            } else {
                Duration::from_secs(5)
            };

            if next_interval != check_interval {
                debug!("Adjusting monitor interval to {:?}", next_interval);
            }
        }
    }
}

impl Default for AudioDeviceMonitor {
    fn default() -> Self {
        Self::new().0
    }
}

impl Drop for AudioDeviceMonitor {
    fn drop(&mut self) {

        self.stop_signal.notify_one();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bluetooth_detection() {
        let airpods = MonitoredDevice::new(
            "John's AirPods Pro".to_string(),
            DeviceMonitorType::Microphone,
        );
        assert!(airpods.is_bluetooth);
        assert_eq!(airpods.disconnect_threshold(), 3);

        let builtin = MonitoredDevice::new(
            "Built-in Microphone".to_string(),
            DeviceMonitorType::Microphone,
        );
        assert!(!builtin.is_bluetooth);
        assert_eq!(builtin.disconnect_threshold(), 2);
    }

    #[tokio::test]
    async fn test_monitor_creation() {
        let (mut monitor, _receiver) = AudioDeviceMonitor::new();
        assert!(monitor.monitor_handle.is_none());

        monitor.stop_monitoring().await;
    }
}
