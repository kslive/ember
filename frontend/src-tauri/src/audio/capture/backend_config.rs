
use serde::{Deserialize, Serialize};
use std::sync::{Arc, RwLock};
use once_cell::sync::Lazy;
use log::info;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AudioCaptureBackend {

    ScreenCaptureKit,

    #[cfg(target_os = "macos")]
    CoreAudio,
}

impl AudioCaptureBackend {

    pub fn name(&self) -> &'static str {
        match self {
            AudioCaptureBackend::ScreenCaptureKit => "ScreenCaptureKit",
            #[cfg(target_os = "macos")]
            AudioCaptureBackend::CoreAudio => "Core Audio",
        }
    }

    pub fn description(&self) -> &'static str {
        match self {
            AudioCaptureBackend::ScreenCaptureKit => {
                "Apple's ScreenCaptureKit framework - Higher level API with good compatibility"
            }
            #[cfg(target_os = "macos")]
            AudioCaptureBackend::CoreAudio => {
                "Direct Core Audio API - Lower latency, more control over audio pipeline"
            }
        }
    }

    pub fn from_string(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "screencapturekit" => Some(AudioCaptureBackend::ScreenCaptureKit),
            #[cfg(target_os = "macos")]
            "coreaudio" | "core_audio" => Some(AudioCaptureBackend::CoreAudio),
            _ => None,
        }
    }

    pub fn to_string(&self) -> String {
        match self {
            AudioCaptureBackend::ScreenCaptureKit => "screencapturekit".to_string(),
            #[cfg(target_os = "macos")]
            AudioCaptureBackend::CoreAudio => "coreaudio".to_string(),
        }
    }

    pub fn available_backends() -> Vec<Self> {
        #[cfg(target_os = "macos")]
        {
            vec![AudioCaptureBackend::ScreenCaptureKit, AudioCaptureBackend::CoreAudio]
        }

        #[cfg(not(target_os = "macos"))]
        {
            vec![AudioCaptureBackend::ScreenCaptureKit]
        }
    }

    pub fn default() -> Self {
        #[cfg(target_os = "macos")]
        return AudioCaptureBackend::CoreAudio;

        #[cfg(not(target_os = "macos"))]
        return AudioCaptureBackend::ScreenCaptureKit;
    }
}

impl Default for AudioCaptureBackend {
    fn default() -> Self {
        Self::default()
    }
}

impl std::fmt::Display for AudioCaptureBackend {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.name())
    }
}

pub struct BackendConfig {
    current_backend: RwLock<AudioCaptureBackend>,
}

impl BackendConfig {
    fn new() -> Self {
        Self {
            current_backend: RwLock::new(AudioCaptureBackend::default()),
        }
    }

    pub fn get(&self) -> AudioCaptureBackend {
        *self.current_backend.read().unwrap()
    }

    pub fn set(&self, backend: AudioCaptureBackend) {
        info!("Switching audio capture backend to: {:?}", backend);
        *self.current_backend.write().unwrap() = backend;
    }

    pub fn available(&self) -> Vec<AudioCaptureBackend> {
        AudioCaptureBackend::available_backends()
    }

    pub fn reset(&self) {
        self.set(AudioCaptureBackend::default());
    }
}

pub static BACKEND_CONFIG: Lazy<Arc<BackendConfig>> = Lazy::new(|| {
    Arc::new(BackendConfig::new())
});

pub fn get_current_backend() -> AudioCaptureBackend {
    BACKEND_CONFIG.get()
}

pub fn set_current_backend(backend: AudioCaptureBackend) {
    BACKEND_CONFIG.set(backend);
}

pub fn get_available_backends() -> Vec<AudioCaptureBackend> {
    BACKEND_CONFIG.available()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_backend_to_string() {
        assert_eq!(AudioCaptureBackend::ScreenCaptureKit.to_string(), "screencapturekit");
        #[cfg(target_os = "macos")]
        assert_eq!(AudioCaptureBackend::CoreAudio.to_string(), "coreaudio");
    }

    #[test]
    fn test_backend_from_string() {
        assert_eq!(
            AudioCaptureBackend::from_string("screencapturekit"),
            Some(AudioCaptureBackend::ScreenCaptureKit)
        );
        #[cfg(target_os = "macos")]
        {
            assert_eq!(
                AudioCaptureBackend::from_string("coreaudio"),
                Some(AudioCaptureBackend::CoreAudio)
            );
            assert_eq!(
                AudioCaptureBackend::from_string("core_audio"),
                Some(AudioCaptureBackend::CoreAudio)
            );
        }
    }

    #[test]
    fn test_available_backends() {
        let backends = AudioCaptureBackend::available_backends();
        assert!(backends.contains(&AudioCaptureBackend::ScreenCaptureKit));

        #[cfg(target_os = "macos")]
        assert!(backends.contains(&AudioCaptureBackend::CoreAudio));
    }

    #[test]
    fn test_default_backend() {
        #[cfg(target_os = "macos")]
        assert_eq!(AudioCaptureBackend::default(), AudioCaptureBackend::CoreAudio);

        #[cfg(not(target_os = "macos"))]
        assert_eq!(AudioCaptureBackend::default(), AudioCaptureBackend::ScreenCaptureKit);
    }

    #[test]
    fn test_backend_config() {
        let config = BackendConfig::new();

        #[cfg(target_os = "macos")]
        assert_eq!(config.get(), AudioCaptureBackend::CoreAudio);

        #[cfg(not(target_os = "macos"))]
        assert_eq!(config.get(), AudioCaptureBackend::ScreenCaptureKit);

        #[cfg(target_os = "macos")]
        {

            config.set(AudioCaptureBackend::CoreAudio);
            assert_eq!(config.get(), AudioCaptureBackend::CoreAudio);
        }

        config.reset();
        #[cfg(target_os = "macos")]
        assert_eq!(config.get(), AudioCaptureBackend::CoreAudio);

        #[cfg(not(target_os = "macos"))]
        assert_eq!(config.get(), AudioCaptureBackend::ScreenCaptureKit);
    }
}