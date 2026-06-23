

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::{anyhow, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tokio::fs::{self, OpenOptions};
use tokio::io::{AsyncWriteExt, BufWriter};
use tokio::sync::RwLock;
use tokio::time::timeout;

use super::models::{self, get_available_models, get_model_by_name};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadProgress {

    pub downloaded_bytes: u64,

    pub total_bytes: u64,

    pub downloaded_mb: f64,

    pub total_mb: f64,

    pub speed_mbps: f64,

    pub percent: u8,
}

impl DownloadProgress {
    pub fn new(downloaded: u64, total: u64, speed_mbps: f64) -> Self {
        let percent = if total > 0 {
            ((downloaded as f64 / total as f64) * 100.0) as u8
        } else {
            0
        };
        Self {
            downloaded_bytes: downloaded,
            total_bytes: total,
            downloaded_mb: downloaded as f64 / (1024.0 * 1024.0),
            total_mb: total as f64 / (1024.0 * 1024.0),
            speed_mbps,
            percent,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ModelStatus {

    NotDownloaded,

    Downloading { progress: u8 },

    Available,

    Corrupted { file_size: u64, expected_min_size: u64 },

    Error(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelInfo {

    pub name: String,

    pub display_name: String,

    pub status: ModelStatus,

    pub path: PathBuf,

    pub size_mb: u64,

    pub context_size: u32,

    pub description: String,

    #[serde(rename = "gguf_file")]
    pub model_id: String,
}

#[derive(Debug, Clone)]
struct HfSibling {
    rfilename: String,
    size: Option<u64>,
}

#[derive(Debug, Clone, Deserialize)]
struct HfTreeEntry {
    path: String,
    #[serde(default)]
    size: u64,
    #[serde(rename = "type", default)]
    kind: Option<String>,
}

fn is_wanted_repo_file(rfilename: &str) -> bool {
    if rfilename.contains('/') {
        return false;
    }

    const EXACT: &[&str] = &[
        "config.json",
        "tokenizer.json",
        "tokenizer_config.json",
        "vocab.json",
        "merges.txt",
        "special_tokens_map.json",
        "added_tokens.json",
        "generation_config.json",
    ];

    if EXACT.contains(&rfilename) {
        return true;
    }

    rfilename.ends_with(".safetensors")
        || rfilename.ends_with(".safetensors.index.json")
        || rfilename.ends_with(".model")
}

pub struct ModelManager {

    models_dir: PathBuf,

    available_models: Arc<RwLock<HashMap<String, ModelInfo>>>,

    active_downloads: Arc<RwLock<HashSet<String>>>,

    cancel_download_flag: Arc<RwLock<Option<String>>>,
}

impl ModelManager {

    pub fn new() -> Result<Self> {
        Self::new_with_models_dir(None)
    }

    pub fn new_with_models_dir(models_dir: Option<PathBuf>) -> Result<Self> {
        let models_dir = if let Some(dir) = models_dir {
            dir
        } else {

            let current_dir = std::env::current_dir()
                .map_err(|e| anyhow!("Failed to get current directory: {}", e))?;

            if cfg!(debug_assertions) {

                current_dir.join("models").join("summary")
            } else {

                log::warn!("ModelManager: No models directory provided, using fallback path");
                dirs::data_dir()
                    .or_else(|| dirs::home_dir())
                    .ok_or_else(|| anyhow!("Could not find system data directory"))?
                    .join("Ember")
                    .join("models")
                    .join("summary")
            }
        };

        log::info!(
            "Built-in AI ModelManager using directory: {}",
            models_dir.display()
        );

        Ok(Self {
            models_dir,
            available_models: Arc::new(RwLock::new(HashMap::new())),
            active_downloads: Arc::new(RwLock::new(HashSet::new())),
            cancel_download_flag: Arc::new(RwLock::new(None)),
        })
    }

    pub async fn init(&self) -> Result<()> {

        if !self.models_dir.exists() {
            fs::create_dir_all(&self.models_dir).await?;
            log::info!("Created models directory: {}", self.models_dir.display());
        }

        self.scan_models().await?;

        Ok(())
    }

    fn model_dir(&self, model_id: &str) -> PathBuf {
        self.models_dir.join(model_id)
    }

    pub async fn scan_models(&self) -> Result<()> {
        let start = std::time::Instant::now();

        log::info!(
            "Starting model scan in directory: {}",
            self.models_dir.display()
        );

        let model_defs = get_available_models();
        let mut models_map = HashMap::new();

        for model_def in model_defs {
            let model_path = self.model_dir(&model_def.model_id);
            log::debug!(
                "Checking model '{}' at path: {}",
                model_def.name,
                model_path.display()
            );

            let is_actively_downloading = {
                let active = self.active_downloads.read().await;
                active.contains(&model_def.name)
            };

            if is_actively_downloading {
                let existing_info = {
                    let models = self.available_models.read().await;
                    models.get(&model_def.name).cloned()
                };

                if let Some(info) = existing_info {

                    models_map.insert(model_def.name.clone(), info);
                    log::debug!(
                        "Model '{}': Preserving Downloading status during scan",
                        model_def.name
                    );
                    continue;
                }
            }

            let status = if models::is_model_dir_valid(&model_path) {
                log::info!("Model '{}': AVAILABLE", model_def.name);
                ModelStatus::Available
            } else {
                log::debug!("Model '{}': NOT DOWNLOADED (config.json + *.safetensors missing)", model_def.name);
                ModelStatus::NotDownloaded
            };

            let model_info = ModelInfo {
                name: model_def.name.clone(),
                display_name: model_def.display_name.clone(),
                status,
                path: model_path,
                size_mb: model_def.size_mb,
                context_size: model_def.context_size,
                description: model_def.description.clone(),
                model_id: model_def.model_id.clone(),
            };

            models_map.insert(model_def.name.clone(), model_info);
        }

        let model_count = models_map.len();

        let mut models = self.available_models.write().await;
        *models = models_map;

        let elapsed = start.elapsed();
        log::info!(
            "Model scan complete: {} models checked in {:?}",
            model_count,
            elapsed
        );
        Ok(())
    }

    pub async fn list_models(&self) -> Vec<ModelInfo> {
        self.available_models
            .read()
            .await
            .values()
            .cloned()
            .collect()
    }

    pub async fn get_model_info(&self, model_name: &str) -> Option<ModelInfo> {
        self.available_models
            .read()
            .await
            .get(model_name)
            .cloned()
    }

    pub async fn is_model_ready(&self, model_name: &str, refresh: bool) -> bool {
        if refresh {
            if let Err(e) = self.scan_models().await {
                log::error!("Failed to scan models: {}", e);
                return false;
            }
        }

        if let Some(info) = self.get_model_info(model_name).await {
            info.status == ModelStatus::Available
        } else {
            false
        }
    }

    pub async fn download_model(
        &self,
        model_name: &str,
        progress_callback: Option<Box<dyn Fn(u8) + Send + Sync>>,
    ) -> Result<()> {

        let detailed_callback: Option<Box<dyn Fn(DownloadProgress) + Send + Sync>> =
            progress_callback.map(|cb| {
                Box::new(move |p: DownloadProgress| cb(p.percent)) as Box<dyn Fn(DownloadProgress) + Send + Sync>
            });
        self.download_model_detailed(model_name, detailed_callback).await
    }

    pub async fn download_model_detailed(
        &self,
        model_name: &str,
        progress_callback: Option<Box<dyn Fn(DownloadProgress) + Send + Sync>>,
    ) -> Result<()> {
        log::info!("Starting download for model: {}", model_name);

        {
            let active = self.active_downloads.read().await;
            if active.contains(model_name) {
                log::warn!("Download already in progress for model: {}", model_name);
                return Err(anyhow!("Download already in progress"));
            }
        }

        let model_def = get_model_by_name(model_name)
            .ok_or_else(|| anyhow!("Unknown model: {}", model_name))?;

        {
            let mut active = self.active_downloads.write().await;
            active.insert(model_name.to_string());
        }

        {
            let mut cancel_flag = self.cancel_download_flag.write().await;
            *cancel_flag = None;
        }

        {
            let mut models = self.available_models.write().await;
            if let Some(model_info) = models.get_mut(model_name) {
                model_info.status = ModelStatus::Downloading { progress: 0 };
            }
        }

        let model_dir = self.model_dir(&model_def.model_id);

        if models::is_model_dir_valid(&model_dir) {
            log::info!(
                "Model '{}' already present and valid at {}, skipping download",
                model_name,
                model_dir.display()
            );
            self.mark_available(model_name, &model_dir).await;
            self.clear_active(model_name).await;
            if let Some(ref callback) = progress_callback {
                callback(DownloadProgress::new(1, 1, 0.0));
            }
            return Ok(());
        }

        let result = self
            .download_repo(&model_def.model_id, &model_dir, model_name, &progress_callback)
            .await;

        match result {
            Ok(()) => {
                if !models::is_model_dir_valid(&model_dir) {
                    let err = "Validation failed: config.json or *.safetensors missing after download";
                    log::error!("{}", err);
                    self.mark_error(model_name, err).await;
                    self.clear_active(model_name).await;
                    return Err(anyhow!("{}", err));
                }

                log::info!("Download completed for model: {}", model_name);
                self.mark_available(model_name, &model_dir).await;
                self.clear_active(model_name).await;
                if let Some(ref callback) = progress_callback {
                    callback(DownloadProgress::new(1, 1, 0.0));
                }
                Ok(())
            }
            Err(e) => {
                let msg = e.to_string();
                if msg.starts_with("CANCELLED:") {
                    self.mark_not_downloaded(model_name).await;
                } else {
                    self.mark_error(model_name, &msg).await;
                }
                self.clear_active(model_name).await;
                Err(e)
            }
        }
    }

    async fn download_repo(
        &self,
        model_id: &str,
        model_dir: &PathBuf,
        model_name: &str,
        progress_callback: &Option<Box<dyn Fn(DownloadProgress) + Send + Sync>>,
    ) -> Result<()> {
        if !model_dir.exists() {
            fs::create_dir_all(model_dir).await?;
        }

        let client = Client::builder()
            .tcp_nodelay(true)
            .pool_max_idle_per_host(1)
            .timeout(Duration::from_secs(3600))
            .connect_timeout(Duration::from_secs(30))
            .build()
            .map_err(|e| anyhow!("Failed to create HTTP client: {}", e))?;

        let api_url = format!(
            "https://huggingface.co/api/models/{}/tree/main?recursive=true",
            model_id
        );
        log::info!("Listing repo files: {}", api_url);

        let api_resp = client
            .get(&api_url)
            .send()
            .await
            .map_err(|e| anyhow!("Failed to query HuggingFace API: {}", e))?;

        if !api_resp.status().is_success() {
            return Err(anyhow!(
                "HuggingFace API returned status {} for {}",
                api_resp.status(),
                model_id
            ));
        }

        let tree: Vec<HfTreeEntry> = api_resp
            .json()
            .await
            .map_err(|e| anyhow!("Failed to parse HuggingFace API response: {}", e))?;

        let files: Vec<HfSibling> = tree
            .into_iter()
            .filter(|e| e.kind.as_deref() != Some("directory") && is_wanted_repo_file(&e.path))
            .map(|e| HfSibling { rfilename: e.path, size: Some(e.size) })
            .collect();

        if files.is_empty() {
            return Err(anyhow!("No downloadable model files found in repo {}", model_id));
        }

        let has_safetensors = files.iter().any(|f| f.rfilename.ends_with(".safetensors"));
        let has_config = files.iter().any(|f| f.rfilename == "config.json");
        if !has_safetensors || !has_config {
            return Err(anyhow!(
                "Repo {} is missing required files (config.json and/or *.safetensors)",
                model_id
            ));
        }

        log::info!("Repo {} has {} wanted files", model_id, files.len());

        let total_known: u64 = files.iter().filter_map(|f| f.size).sum();
        let sizes_complete = files.iter().all(|f| f.size.is_some());
        let aggregate_total = if sizes_complete { total_known } else { 0 };

        let mut aggregate_done: u64 = 0;

        let download_start = std::time::Instant::now();
        let mut last_report = std::time::Instant::now();
        let mut last_percent: u8 = 0;
        let mut bytes_since_report: u64 = 0;

        if let Some(ref cb) = progress_callback {
            cb(DownloadProgress::new(0, aggregate_total, 0.0));
        }

        for sibling in &files {
            {
                let cancel_flag = self.cancel_download_flag.read().await;
                if cancel_flag.as_ref() == Some(&model_name.to_string()) {
                    return Err(anyhow!("CANCELLED: Download cancelled by user"));
                }
            }

            let rfilename = &sibling.rfilename;
            let dest = model_dir.join(rfilename);

            if let Some(parent) = dest.parent() {
                if !parent.exists() {
                    fs::create_dir_all(parent).await?;
                }
            }

            if let Some(expected_size) = sibling.size {
                if dest.exists() {
                    if let Ok(meta) = fs::metadata(&dest).await {
                        if meta.len() == expected_size {
                            log::info!("Skipping already-complete file: {}", rfilename);
                            aggregate_done += expected_size;
                            continue;
                        }
                    }
                }
            }

            let file_url = format!(
                "https://huggingface.co/{}/resolve/main/{}",
                model_id, rfilename
            );

            let existing_size: u64 = if dest.exists() {
                fs::metadata(&dest).await.map(|m| m.len()).unwrap_or(0)
            } else {
                0
            };

            let resume_from = match sibling.size {
                Some(expected) if existing_size > 0 && existing_size < expected => existing_size,
                _ => 0,
            };

            let mut request = client.get(&file_url);
            if resume_from > 0 {
                request = request.header("Range", format!("bytes={}-", resume_from));
            }

            let response = request
                .send()
                .await
                .map_err(|e| anyhow!("Failed to download {}: {}", rfilename, e))?;

            let resuming = response.status() == reqwest::StatusCode::PARTIAL_CONTENT && resume_from > 0;

            if !response.status().is_success() && !resuming {
                return Err(anyhow!(
                    "Download of {} failed with status: {}",
                    rfilename,
                    response.status()
                ));
            }

            let per_file_total = sibling
                .size
                .or_else(|| response.content_length().map(|cl| resume_from + cl))
                .unwrap_or(0);

            let file = if resuming {
                aggregate_done += resume_from;
                OpenOptions::new()
                    .write(true)
                    .append(true)
                    .open(&dest)
                    .await
                    .map_err(|e| anyhow!("Failed to open {} for append: {}", rfilename, e))?
            } else {
                fs::File::create(&dest)
                    .await
                    .map_err(|e| anyhow!("Failed to create {}: {}", rfilename, e))?
            };

            let mut writer = BufWriter::with_capacity(8 * 1024 * 1024, file);
            let mut file_downloaded: u64 = resume_from;

            use futures_util::StreamExt;
            let mut stream = response.bytes_stream();

            loop {
                {
                    let cancel_flag = self.cancel_download_flag.read().await;
                    if cancel_flag.as_ref() == Some(&model_name.to_string()) {
                        let _ = writer.flush().await;
                        return Err(anyhow!("CANCELLED: Download cancelled by user"));
                    }
                }

                let next_result = timeout(Duration::from_secs(30), stream.next()).await;

                let chunk = match next_result {
                    Err(_) => {
                        let _ = writer.flush().await;
                        return Err(anyhow!(
                            "Download timeout - No data received for 30 seconds ({})",
                            rfilename
                        ));
                    }
                    Ok(None) => break,
                    Ok(Some(chunk_result)) => match chunk_result {
                        Ok(c) => c,
                        Err(e) => {
                            let _ = writer.flush().await;
                            let error_msg = if e.is_timeout() {
                                "Connection timeout - Check your internet"
                            } else if e.is_connect() {
                                "Connection failed - Check your internet"
                            } else if e.is_body() {
                                "Stream interrupted - Network unstable"
                            } else {
                                "Download error"
                            };
                            return Err(anyhow!("{}: {} ({})", error_msg, e, rfilename));
                        }
                    },
                };

                let chunk_len = chunk.len() as u64;
                writer
                    .write_all(&chunk)
                    .await
                    .map_err(|e| anyhow!("Error writing {}: {}", rfilename, e))?;

                file_downloaded += chunk_len;
                aggregate_done += chunk_len;
                bytes_since_report += chunk_len;

                let percent = if aggregate_total > 0 {
                    ((aggregate_done as f64 / aggregate_total as f64) * 100.0).min(100.0) as u8
                } else if per_file_total > 0 {
                    ((file_downloaded as f64 / per_file_total as f64) * 100.0).min(100.0) as u8
                } else {
                    0
                };

                let elapsed_since_report = last_report.elapsed();
                let should_report =
                    percent > last_percent || elapsed_since_report.as_millis() >= 500;

                if should_report {
                    let speed_mbps = if elapsed_since_report.as_secs_f64() > 0.0 {
                        (bytes_since_report as f64 / (1024.0 * 1024.0))
                            / elapsed_since_report.as_secs_f64()
                    } else {
                        let total_elapsed = download_start.elapsed().as_secs_f64();
                        if total_elapsed > 0.0 {
                            (aggregate_done as f64 / (1024.0 * 1024.0)) / total_elapsed
                        } else {
                            0.0
                        }
                    };

                    {
                        let mut models = self.available_models.write().await;
                        if let Some(model_info) = models.get_mut(model_name) {
                            model_info.status = ModelStatus::Downloading { progress: percent };
                        }
                    }

                    if let Some(ref cb) = progress_callback {
                        cb(DownloadProgress::new(aggregate_done, aggregate_total.max(aggregate_done), speed_mbps));
                    }

                    last_percent = percent;
                    last_report = std::time::Instant::now();
                    bytes_since_report = 0;
                }
            }

            writer.flush().await?;
            drop(writer);
            log::info!("Downloaded file: {}", rfilename);
        }

        {
            let mut models = self.available_models.write().await;
            if let Some(model_info) = models.get_mut(model_name) {
                model_info.status = ModelStatus::Downloading { progress: 100 };
            }
        }
        if let Some(ref cb) = progress_callback {
            let total = aggregate_total.max(aggregate_done).max(1);
            cb(DownloadProgress::new(total, total, 0.0));
        }

        Ok(())
    }

    async fn mark_available(&self, model_name: &str, model_dir: &PathBuf) {
        let mut models = self.available_models.write().await;
        if let Some(model_info) = models.get_mut(model_name) {
            model_info.status = ModelStatus::Available;
            model_info.path = model_dir.clone();
        }
    }

    async fn mark_error(&self, model_name: &str, msg: &str) {
        let mut models = self.available_models.write().await;
        if let Some(model_info) = models.get_mut(model_name) {
            model_info.status = ModelStatus::Error(msg.to_string());
        }
    }

    async fn mark_not_downloaded(&self, model_name: &str) {
        let mut models = self.available_models.write().await;
        if let Some(model_info) = models.get_mut(model_name) {
            model_info.status = ModelStatus::NotDownloaded;
        }
    }

    async fn clear_active(&self, model_name: &str) {
        let mut active = self.active_downloads.write().await;
        active.remove(model_name);
    }

    pub async fn cancel_download(&self, model_name: &str) -> Result<()> {
        log::info!("Cancelling download for model: {}", model_name);

        {
            let mut cancel_flag = self.cancel_download_flag.write().await;
            *cancel_flag = Some(model_name.to_string());
        }

        {
            let mut models = self.available_models.write().await;
            if let Some(model_info) = models.get_mut(model_name) {
                model_info.status = ModelStatus::NotDownloaded;
            }
        }

        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

        Ok(())
    }

    pub async fn delete_model(&self, model_name: &str) -> Result<()> {
        log::info!("Deleting model: {}", model_name);

        let model_def = get_model_by_name(model_name)
            .ok_or_else(|| anyhow!("Unknown model: {}", model_name))?;

        let model_dir = self.model_dir(&model_def.model_id);

        if model_dir.exists() {
            fs::remove_dir_all(&model_dir).await?;
            log::info!("Deleted model directory: {}", model_dir.display());
        }

        {
            let mut models = self.available_models.write().await;
            if let Some(model_info) = models.get_mut(model_name) {
                model_info.status = ModelStatus::NotDownloaded;
            }
        }

        Ok(())
    }

    pub fn get_models_directory(&self) -> PathBuf {
        self.models_dir.clone()
    }
}
