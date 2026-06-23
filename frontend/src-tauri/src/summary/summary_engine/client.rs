

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use std::sync::RwLock;
use tokio::sync::Mutex;
use tokio_util::sync::CancellationToken;

use super::models;
use super::sidecar::SidecarManager;

#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum Request {
    Generate {
        prompt: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        system: Option<String>,
        max_tokens: Option<i32>,
        context_size: Option<u32>,
        model_path: Option<String>,

        temperature: Option<f32>,
        top_k: Option<i32>,
        top_p: Option<f32>,
        stop_tokens: Option<Vec<String>>,
    },
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum Response {
    Response { text: String, error: Option<String> },
    Error { message: String },
}

lazy_static::lazy_static! {
    static ref SIDECAR_MANAGER: Arc<Mutex<Option<Arc<SidecarManager>>>> = Arc::new(Mutex::new(None));
}

static MODEL_PATH_CACHE: Lazy<RwLock<HashMap<String, PathBuf>>> = Lazy::new(|| {
    RwLock::new(HashMap::new())
});

pub async fn init_sidecar_manager(app_data_dir: PathBuf) -> Result<()> {
    let manager = SidecarManager::new(app_data_dir)?;
    let mut global_manager = SIDECAR_MANAGER.lock().await;
    *global_manager = Some(Arc::new(manager));
    Ok(())
}

async fn get_sidecar_manager() -> Result<Arc<SidecarManager>> {
    let global_manager = SIDECAR_MANAGER.lock().await;
    global_manager
        .clone()
        .ok_or_else(|| anyhow!("Sidecar manager not initialized. Call init_sidecar_manager first."))
}

fn get_cached_model_path(app_data_dir: &PathBuf, model_name: &str) -> Result<PathBuf> {

    {
        let cache = MODEL_PATH_CACHE.read().unwrap();
        if let Some(path) = cache.get(model_name) {

            if models::is_model_dir_valid(path) {
                return Ok(path.clone());
            }
        }
    }

    let mut cache = MODEL_PATH_CACHE.write().unwrap();

    if let Some(path) = cache.get(model_name) {
        if models::is_model_dir_valid(path) {
            return Ok(path.clone());
        }
    }

    let model_path = models::get_model_path(app_data_dir, model_name)?;

    if !models::is_model_dir_valid(&model_path) {
        return Err(anyhow!(
            "Model directory not found or incomplete: {}. Please download the model '{}' first.",
            model_path.display(),
            model_name
        ));
    }

    cache.insert(model_name.to_string(), model_path.clone());
    Ok(model_path)
}

pub async fn generate_with_builtin(
    app_data_dir: &PathBuf,
    model_name: &str,
    system_prompt: &str,
    user_prompt: &str,
    cancellation_token: Option<&CancellationToken>,
) -> Result<String> {

    if let Some(token) = cancellation_token {
        if token.is_cancelled() {
            return Err(anyhow!("Generation cancelled before starting"));
        }
    }

    log::info!("Built-in AI generation request");
    log::info!("Model: {}", model_name);

    let model_def = models::get_model_by_name(model_name)
        .ok_or_else(|| anyhow!("Unknown model: {}", model_name))?;

    let model_path = get_cached_model_path(app_data_dir, model_name)?;

    let manager = {
        let mut global_manager = SIDECAR_MANAGER.lock().await;
        if global_manager.is_none() {
            log::info!("Initializing sidecar manager");
            let new_manager = SidecarManager::new(app_data_dir.clone())?;
            *global_manager = Some(Arc::new(new_manager));
        }
        global_manager.clone().unwrap()
    };

    manager.ensure_running(model_path.clone()).await?;

    if let Some(token) = cancellation_token {
        if token.is_cancelled() {
            return Err(anyhow!("Generation cancelled during sidecar startup"));
        }
    }

    let system = if system_prompt.is_empty() {
        None
    } else {
        Some(system_prompt.to_string())
    };

    let request = Request::Generate {
        prompt: user_prompt.to_string(),
        system,
        max_tokens: Some(models::DEFAULT_MAX_TOKENS),
        context_size: Some(model_def.context_size),
        model_path: Some(model_path.to_string_lossy().to_string()),
        temperature: Some(model_def.sampling.temperature),
        top_k: Some(model_def.sampling.top_k),
        top_p: Some(model_def.sampling.top_p),
        stop_tokens: Some(model_def.sampling.stop_tokens.clone()),
    };

    let request_json = serde_json::to_string(&request)?;

    let timeout = Duration::from_secs(models::GENERATION_TIMEOUT_SECS);

    log::info!("Sending generation request to sidecar");

    let response_json = if let Some(token) = cancellation_token {
        tokio::select! {
            result = manager.send_request(request_json, timeout) => {
                result?
            }
            _ = token.cancelled() => {
                log::warn!("Generation cancelled by user, shutting down sidecar");

                if let Err(e) = manager.shutdown().await {
                    log::error!("Failed to shutdown sidecar during cancellation: {}", e);
                }
                return Err(anyhow!("Generation cancelled by user"));
            }
        }
    } else {
        manager.send_request(request_json, timeout).await?
    };

    if let Some(token) = cancellation_token {
        if token.is_cancelled() {
            return Err(anyhow!("Generation cancelled"));
        }
    }

    let response: Response = serde_json::from_str(&response_json)
        .with_context(|| format!("Failed to parse response: {}", response_json))?;

    match response {
        Response::Response { text, error } => {
            if let Some(err_msg) = error {
                Err(anyhow!("Generation failed: {}", err_msg))
            } else {
                log::info!("Generation completed: {} chars", text.len());
                Ok(text)
            }
        }
        Response::Error { message } => Err(anyhow!("Sidecar error: {}", message)),
    }
}

pub async fn shutdown_sidecar_gracefully() -> Result<()> {
    let manager_opt = {
        let mut global_manager = SIDECAR_MANAGER.lock().await;
        global_manager.take()
    };

    if let Some(manager) = manager_opt {
        log::info!("Detaching sidecar manager for graceful shutdown");

        tokio::spawn(async move {
            if let Err(e) = manager.shutdown_gracefully().await {
                log::error!("Error during graceful shutdown: {}", e);
            }
        });
    }

    Ok(())
}

pub async fn force_shutdown_sidecar() -> Result<()> {
    let manager_opt = {
        let mut global_manager = SIDECAR_MANAGER.lock().await;
        global_manager.take()
    };

    if let Some(manager) = manager_opt {
        log::info!("Force shutting down sidecar for app exit");

        manager.shutdown().await?;
    }

    Ok(())
}

pub async fn is_sidecar_healthy() -> bool {
    if let Ok(manager) = get_sidecar_manager().await {
        manager.is_healthy()
    } else {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_request_serialization() {
        let request = Request::Generate {
            prompt: "test prompt".to_string(),
            system: Some("test system".to_string()),
            max_tokens: Some(512),
            context_size: Some(2048),
            model_path: Some("/path/to/model-dir".to_string()),
            temperature: Some(0.7),
            top_k: Some(20),
            top_p: Some(0.8),
            stop_tokens: Some(vec!["<|im_end|>".to_string()]),
        };

        let json = serde_json::to_string(&request).unwrap();
        assert!(json.contains("\"type\":\"generate\""));
        assert!(json.contains("\"prompt\":\"test prompt\""));
        assert!(json.contains("\"system\":\"test system\""));
        assert!(json.contains("\"max_tokens\":512"));
        assert!(json.contains("\"temperature\":0.7"));
    }

    #[test]
    fn test_request_serialization_omits_none_system() {
        let request = Request::Generate {
            prompt: "test prompt".to_string(),
            system: None,
            max_tokens: Some(512),
            context_size: Some(2048),
            model_path: Some("/path/to/model-dir".to_string()),
            temperature: Some(0.7),
            top_k: Some(20),
            top_p: Some(0.8),
            stop_tokens: Some(vec!["<|im_end|>".to_string()]),
        };

        let json = serde_json::to_string(&request).unwrap();
        assert!(!json.contains("\"system\""));
    }

    #[test]
    fn test_response_deserialization() {
        let json = r#"{"type":"response","text":"generated text","error":null}"#;
        let response: Response = serde_json::from_str(json).unwrap();

        match response {
            Response::Response { text, error } => {
                assert_eq!(text, "generated text");
                assert!(error.is_none());
            }
            _ => panic!("Wrong response type"),
        }
    }

    #[test]
    fn test_error_response_deserialization() {
        let json = r#"{"type":"error","message":"something went wrong"}"#;
        let response: Response = serde_json::from_str(json).unwrap();

        match response {
            Response::Error { message } => {
                assert_eq!(message, "something went wrong");
            }
            _ => panic!("Wrong response type"),
        }
    }
}
