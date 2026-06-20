use crate::database::repositories::{
    meeting::MeetingsRepository, setting::SettingsRepository, summary::SummaryProcessesRepository,
};
use crate::summary::llm_client::LLMProvider;
use crate::summary::processor::{extract_meeting_name_from_markdown, generate_meeting_summary};
use crate::ollama::metadata::ModelMetadataCache;
use sqlx::SqlitePool;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::{AppHandle, Manager};
use tokio_util::sync::CancellationToken;
use tracing::{error, info, warn};
use once_cell::sync::Lazy;

static METADATA_CACHE: Lazy<ModelMetadataCache> = Lazy::new(|| {
    ModelMetadataCache::new(Duration::from_secs(300))
});

static CANCELLATION_REGISTRY: Lazy<Arc<Mutex<HashMap<String, CancellationToken>>>> =
    Lazy::new(|| Arc::new(Mutex::new(HashMap::new())));

pub struct SummaryService;

impl SummaryService {

    fn register_cancellation_token(meeting_id: &str) -> CancellationToken {
        let token = CancellationToken::new();
        if let Ok(mut registry) = CANCELLATION_REGISTRY.lock() {
            registry.insert(meeting_id.to_string(), token.clone());
            info!("Registered cancellation token for meeting: {}", meeting_id);
        }
        token
    }

    pub fn cancel_summary(meeting_id: &str) -> bool {
        if let Ok(registry) = CANCELLATION_REGISTRY.lock() {
            if let Some(token) = registry.get(meeting_id) {
                info!("Cancelling summary generation for meeting: {}", meeting_id);
                token.cancel();
                return true;
            }
        }
        warn!("No active summary generation found for meeting: {}", meeting_id);
        false
    }

    fn cleanup_cancellation_token(meeting_id: &str) {
        if let Ok(mut registry) = CANCELLATION_REGISTRY.lock() {
            if registry.remove(meeting_id).is_some() {
                info!("Cleaned up cancellation token for meeting: {}", meeting_id);
            }
        }
    }

    pub async fn process_transcript_background<R: tauri::Runtime>(
        _app: AppHandle<R>,
        pool: SqlitePool,
        meeting_id: String,
        text: String,
        model_provider: String,
        model_name: String,
        custom_prompt: String,
        template_id: String,
    ) {
        let start_time = Instant::now();
        info!(
            "Starting background processing for meeting_id: {}",
            meeting_id
        );

        let cancellation_token = Self::register_cancellation_token(&meeting_id);

        let provider = match LLMProvider::from_str(&model_provider) {
            Ok(p) => p,
            Err(e) => {
                Self::update_process_failed(&pool, &meeting_id, &e).await;
                return;
            }
        };

        let api_key = if provider == LLMProvider::Ollama || provider == LLMProvider::BuiltInAI || provider == LLMProvider::CustomOpenAI {

            String::new()
        } else {
            match SettingsRepository::get_api_key(&pool, &model_provider).await {
                Ok(Some(key)) if !key.is_empty() => key,
                Ok(None) | Ok(Some(_)) => {
                    let err_msg = format!("API key not found for {}", &model_provider);
                    Self::update_process_failed(&pool, &meeting_id, &err_msg).await;
                    return;
                }
                Err(e) => {
                    let err_msg = format!("Failed to retrieve API key for {}: {}", &model_provider, e);
                    Self::update_process_failed(&pool, &meeting_id, &err_msg).await;
                    return;
                }
            }
        };

        let ollama_endpoint = if provider == LLMProvider::Ollama {
            match SettingsRepository::get_model_config(&pool).await {
                Ok(Some(config)) => config.ollama_endpoint,
                Ok(None) => None,
                Err(e) => {
                    info!("Failed to retrieve Ollama endpoint: {}, using default", e);
                    None
                }
            }
        } else {
            None
        };

        let (custom_openai_endpoint, custom_openai_api_key, custom_openai_max_tokens, custom_openai_temperature, custom_openai_top_p) =
            if provider == LLMProvider::CustomOpenAI {
                match SettingsRepository::get_custom_openai_config(&pool).await {
                    Ok(Some(config)) => {
                        info!("✓ Using custom OpenAI endpoint: {}", config.endpoint);
                        (
                            Some(config.endpoint),
                            config.api_key,
                            config.max_tokens.map(|t| t as u32),
                            config.temperature,
                            config.top_p,
                        )
                    }
                    Ok(None) => {
                        let err_msg = "Custom OpenAI provider selected but no configuration found";
                        Self::update_process_failed(&pool, &meeting_id, err_msg).await;
                        return;
                    }
                    Err(e) => {
                        let err_msg = format!("Failed to retrieve custom OpenAI config: {}", e);
                        Self::update_process_failed(&pool, &meeting_id, &err_msg).await;
                        return;
                    }
                }
            } else {
                (None, None, None, None, None)
            };

        let final_api_key = if provider == LLMProvider::CustomOpenAI {
            custom_openai_api_key.unwrap_or_default()
        } else {
            api_key
        };

        let token_threshold = if provider == LLMProvider::Ollama {
            match METADATA_CACHE.get_or_fetch(&model_name, ollama_endpoint.as_deref()).await {
                Ok(metadata) => {

                    let optimal = metadata.context_size.saturating_sub(300);
                    info!(
                        "✓ Using dynamic context for {}: {} tokens (chunk size: {})",
                        model_name, metadata.context_size, optimal
                    );
                    optimal
                }
                Err(e) => {
                    warn!(
                        "Failed to fetch context for {}: {}. Using default 4000",
                        model_name, e
                    );
                    4000
                }
            }
        } else if provider == LLMProvider::BuiltInAI {

            use crate::summary::summary_engine::models;
            let model = models::get_model_by_name(&model_name)
                .ok_or_else(|| format!("Unknown model: {}", model_name));

            match model {
                Ok(model_def) => {

                    let reserve = models::DEFAULT_MAX_TOKENS as u32 + 512;
                    let optimal = model_def.context_size.saturating_sub(reserve).max(1024) as usize;
                    info!(
                        "✓ Using BuiltInAI context size: {} tokens (single-pass threshold: {})",
                        model_def.context_size, optimal
                    );
                    optimal
                }
                Err(e) => {
                    warn!("{}, using default 1536", e);
                    1536
                }
            }
        } else {

            100000
        };

        let app_data_dir = _app.path().app_data_dir().ok();

        // Generate the summary in the current UI language.
        let locale = crate::current_locale(&_app);

        let client = reqwest::Client::new();
        let result = generate_meeting_summary(
            &client,
            &provider,
            &model_name,
            &final_api_key,
            &text,
            &custom_prompt,
            &template_id,
            token_threshold,
            ollama_endpoint.as_deref(),
            custom_openai_endpoint.as_deref(),
            custom_openai_max_tokens,
            custom_openai_temperature,
            custom_openai_top_p,
            app_data_dir.as_ref(),
            Some(&cancellation_token),
            &locale,
        )
        .await;

        let duration = start_time.elapsed().as_secs_f64();

        Self::cleanup_cancellation_token(&meeting_id);

        match result {
            Ok((mut final_markdown, num_chunks)) => {
                if num_chunks == 0 && final_markdown.is_empty() {
                    Self::update_process_failed(
                        &pool,
                        &meeting_id,
                        "Summary generation failed: No content was processed.",
                    )
                    .await;
                    return;
                }

                info!(
                    "✓ Successfully processed {} chunks for meeting_id: {}. Duration: {:.2}s",
                    num_chunks, meeting_id, duration
                );
                info!("final markdown is {}", &final_markdown);

                if let Some(topic_raw) = extract_meeting_name_from_markdown(&final_markdown) {
                    let topic = topic_raw
                        .trim()
                        .trim_start_matches(|c| c == '#' || c == '📞' || c == ' ')
                        .trim()
                        .to_string();
                    if !topic.is_empty() {

                        let (date_str, time_str) =
                            match MeetingsRepository::get_meeting_metadata(&pool, &meeting_id).await {
                                Ok(Some(m)) => {
                                    let local = m.created_at.0.with_timezone(&chrono::Local);
                                    (
                                        local.format("%Y-%m-%d").to_string(),
                                        local.format("%H:%M").to_string(),
                                    )
                                }
                                _ => {
                                    let now = chrono::Local::now();
                                    (
                                        now.format("%Y-%m-%d").to_string(),
                                        now.format("%H:%M").to_string(),
                                    )
                                }
                            };

                        let _ = &time_str;
                        let app_title = {
                            let t = topic.trim();
                            if t.chars().count() <= 15 {
                                t.to_string()
                            } else {
                                let mut out = String::new();
                                for word in t.split_whitespace() {
                                    let cand = if out.is_empty() {
                                        word.to_string()
                                    } else {
                                        format!("{} {}", out, word)
                                    };
                                    if cand.chars().count() > 15 {
                                        break;
                                    }
                                    out = cand;
                                }
                                if out.is_empty() {
                                    t.chars().take(15).collect()
                                } else {
                                    out
                                }
                            }
                        };
                        info!(
                            "Updating meeting title to '{}' for meeting_id: {}",
                            app_title, meeting_id
                        );
                        if let Err(e) =
                            MeetingsRepository::update_meeting_title(&pool, &meeting_id, &app_title)
                                .await
                        {
                            error!("Failed to update meeting title for {}: {}", meeting_id, e);
                        }

                        let mut found_h1 = false;
                        let body: String = final_markdown
                            .lines()
                            .filter(|line| {
                                if found_h1 {
                                    return true;
                                }
                                if line.trim_start().starts_with("# ") {
                                    found_h1 = true;
                                }
                                false
                            })
                            .collect::<Vec<_>>()
                            .join("\n");
                        let body = if found_h1 {
                            body.trim_start().to_string()
                        } else {
                            final_markdown.trim_start().to_string()
                        };
                        final_markdown = format!("# {} — {}\n\n{}", date_str, topic, body);
                    }
                }

                let result_json = serde_json::json!({
                    "markdown": final_markdown,
                });

                if let Err(e) = SummaryProcessesRepository::update_process_completed(
                    &pool,
                    &meeting_id,
                    result_json,
                    num_chunks,
                    duration,
                )
                .await
                {
                    error!(
                        "Failed to save completed process for {}: {}",
                        meeting_id, e
                    );
                } else {
                    info!(
                        "Summary saved successfully for meeting_id: {}",
                        meeting_id
                    );

                    Self::delete_meeting_audio(&pool, &meeting_id).await;
                }
            }
            Err(e) => {

                if e.contains("cancelled") {
                    info!("Summary generation was cancelled for meeting_id: {}", meeting_id);
                    if let Err(db_err) = SummaryProcessesRepository::update_process_cancelled(&pool, &meeting_id).await {
                        error!("Failed to update DB status to cancelled for {}: {}", meeting_id, db_err);
                    }
                } else {
                    Self::update_process_failed(&pool, &meeting_id, &e).await;
                }
            }
        }
    }

    async fn delete_meeting_audio(pool: &SqlitePool, meeting_id: &str) {
        let folder_path = match MeetingsRepository::get_meeting_metadata(pool, meeting_id).await {
            Ok(Some(m)) => m.folder_path,
            Ok(None) => None,
            Err(e) => {
                warn!("delete_meeting_audio: could not load meeting {}: {}", meeting_id, e);
                None
            }
        };

        let Some(folder) = folder_path else {

            return;
        };

        let folder = std::path::Path::new(&folder);

        let audio = folder.join("audio.mp4");
        if audio.exists() {
            match std::fs::remove_file(&audio) {
                Ok(()) => info!("Deleted audio after summary: {}", audio.display()),
                Err(e) => warn!("Failed to delete audio {}: {}", audio.display(), e),
            }
        }

        let checkpoints = folder.join(".checkpoints");
        if checkpoints.exists() {
            if let Err(e) = std::fs::remove_dir_all(&checkpoints) {
                warn!("Failed to remove checkpoints dir {}: {}", checkpoints.display(), e);
            }
        }
    }

    async fn update_process_failed(pool: &SqlitePool, meeting_id: &str, error_msg: &str) {
        error!(
            "Processing failed for meeting_id {}: {}",
            meeting_id, error_msg
        );
        if let Err(e) =
            SummaryProcessesRepository::update_process_failed(pool, meeting_id, error_msg).await
        {
            error!(
                "Failed to update DB status to failed for {}: {}",
                meeting_id, e
            );
        }
    }
}
