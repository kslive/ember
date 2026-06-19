use serde::{Deserialize, Serialize};
use std::sync::RwLock;
use std::time::{Duration, Instant};
use tauri::command;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct GroqModel {
    pub id: String,
    pub owned_by: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GroqApiModel {
    id: String,
    owned_by: Option<String>,
    #[allow(dead_code)]
    object: String,
}

#[derive(Debug, Deserialize)]
struct GroqApiResponse {
    data: Vec<GroqApiModel>,
}

struct CacheEntry {
    models: Vec<GroqModel>,
    fetched_at: Instant,
}

static MODELS_CACHE: RwLock<Option<CacheEntry>> = RwLock::new(None);

const CACHE_TTL_SECS: u64 = 300;

const FALLBACK_MODELS: &[&str] = &["llama-3.3-70b-versatile"];

fn get_fallback_models() -> Vec<GroqModel> {
    FALLBACK_MODELS
        .iter()
        .map(|id| GroqModel {
            id: id.to_string(),
            owned_by: None,
        })
        .collect()
}

fn is_chat_model(model_id: &str) -> bool {
    let id = model_id.to_lowercase();

    !id.contains("whisper")
        && !id.contains("embed")
        && !id.contains("guard")
        && !id.contains("tool-use")
}

#[command]
pub async fn get_groq_models(api_key: Option<String>) -> Result<Vec<GroqModel>, String> {

    let api_key = match api_key {
        Some(key) if !key.trim().is_empty() => key.trim().to_string(),
        _ => {
            log::info!("No Groq API key provided, returning fallback models");
            return Ok(get_fallback_models());
        }
    };

    {
        let cache = MODELS_CACHE.read().map_err(|e| e.to_string())?;
        if let Some(entry) = cache.as_ref() {
            if entry.fetched_at.elapsed() < Duration::from_secs(CACHE_TTL_SECS) {
                log::info!("Returning cached Groq models ({} models)", entry.models.len());
                return Ok(entry.models.clone());
            }
        }
    }

    log::info!("Fetching Groq models from API...");
    let client = reqwest::Client::new();

    let response = match client
        .get("https://api.groq.com/openai/v1/models")
        .header("Authorization", format!("Bearer {}", api_key))
        .timeout(Duration::from_secs(5))
        .send()
        .await
    {
        Ok(resp) => resp,
        Err(e) => {
            log::warn!("Failed to fetch Groq models: {}. Using fallback.", e);
            return Ok(get_fallback_models());
        }
    };

    if !response.status().is_success() {
        let status = response.status();
        log::warn!(
            "Groq API returned status {}. Using fallback models.",
            status
        );
        return Ok(get_fallback_models());
    }

    let api_response: GroqApiResponse = match response.json().await {
        Ok(data) => data,
        Err(e) => {
            log::warn!("Failed to parse Groq response: {}. Using fallback.", e);
            return Ok(get_fallback_models());
        }
    };

    let models: Vec<GroqModel> = api_response
        .data
        .into_iter()
        .filter(|m| is_chat_model(&m.id))
        .map(|m| GroqModel {
            id: m.id,
            owned_by: m.owned_by,
        })
        .collect();

    if models.is_empty() {
        log::warn!("No chat models returned from Groq API. Using fallback.");
        return Ok(get_fallback_models());
    }

    log::info!("Fetched {} Groq models from API", models.len());

    {
        let mut cache = MODELS_CACHE.write().map_err(|e| e.to_string())?;
        *cache = Some(CacheEntry {
            models: models.clone(),
            fetched_at: Instant::now(),
        });
    }

    Ok(models)
}

pub fn clear_cache() {
    if let Ok(mut cache) = MODELS_CACHE.write() {
        *cache = None;
        log::info!("Groq models cache cleared");
    }
}
