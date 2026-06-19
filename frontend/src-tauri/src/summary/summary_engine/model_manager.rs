

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

use super::models::{get_available_models, get_model_by_name};

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

    pub gguf_file: String,
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

    pub async fn scan_models(&self) -> Result<()> {
        let start = std::time::Instant::now();

        log::info!(
            "Starting model scan in directory: {}",
            self.models_dir.display()
        );

        let model_defs = get_available_models();
        let mut models_map = HashMap::new();

        for model_def in model_defs {
            let model_path = self.models_dir.join(&model_def.gguf_file);
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

            let status = if model_path.exists() {

                match fs::metadata(&model_path).await {
                    Ok(metadata) => {
                        let file_size_mb = metadata.len() / (1024 * 1024);

                        let expected_min = (model_def.size_mb as f64 * 0.9) as u64;
                        let expected_max = (model_def.size_mb as f64 * 1.1) as u64;

                        log::info!(
                            "Model '{}': found {} MB (expected {}-{} MB)",
                            model_def.name,
                            file_size_mb,
                            expected_min,
                            expected_max
                        );

                        if file_size_mb >= expected_min && file_size_mb <= expected_max {
                            log::info!("Model '{}': AVAILABLE", model_def.name);
                            ModelStatus::Available
                        } else {
                            log::warn!(
                                "Model '{}': CORRUPTED (size mismatch: {} MB, expected {} MB)",
                                model_def.name,
                                file_size_mb,
                                model_def.size_mb
                            );
                            ModelStatus::Corrupted {
                                file_size: file_size_mb,
                                expected_min_size: expected_min,
                            }
                        }
                    }
                    Err(e) => {
                        log::error!(
                            "Model '{}': Failed to read metadata: {}",
                            model_def.name,
                            e
                        );
                        ModelStatus::Error(format!("Failed to read metadata: {}", e))
                    }
                }
            } else {
                log::debug!("Model '{}': NOT FOUND", model_def.name);
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
                gguf_file: model_def.gguf_file.clone(),
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
        progress_callback: Option<Box<dyn Fn(u8) + Send>>,
    ) -> Result<()> {

        let detailed_callback: Option<Box<dyn Fn(DownloadProgress) + Send>> =
            progress_callback.map(|cb| {
                Box::new(move |p: DownloadProgress| cb(p.percent)) as Box<dyn Fn(DownloadProgress) + Send>
            });
        self.download_model_detailed(model_name, detailed_callback).await
    }

    pub async fn download_model_detailed(
        &self,
        model_name: &str,
        progress_callback: Option<Box<dyn Fn(DownloadProgress) + Send>>,
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

        let file_path = self.models_dir.join(&model_def.gguf_file);

        if file_path.exists() {
            if let Ok(metadata) = fs::metadata(&file_path).await {
                let file_size_mb = metadata.len() / (1024 * 1024);
                let expected_min = (model_def.size_mb as f64 * 0.9) as u64;
                let expected_max = (model_def.size_mb as f64 * 1.1) as u64;

                if file_size_mb >= expected_min && file_size_mb <= expected_max {
                    log::info!(
                        "Model '{}' already exists and is valid ({} MB), skipping download",
                        model_name,
                        file_size_mb
                    );

                    {
                        let mut models = self.available_models.write().await;
                        if let Some(model_info) = models.get_mut(model_name) {
                            model_info.status = ModelStatus::Available;
                        }
                    }

                    {
                        let mut active = self.active_downloads.write().await;
                        active.remove(model_name);
                    }

                    if let Some(ref callback) = progress_callback {
                        let total = metadata.len();
                        callback(DownloadProgress::new(total, total, 0.0));
                    }

                    return Ok(());
                } else if file_size_mb > expected_max {

                    log::warn!(
                        "Model '{}' exists but is too large ({} MB, expected max {} MB), deleting and re-downloading",
                        model_name,
                        file_size_mb,
                        expected_max
                    );
                    if let Err(e) = fs::remove_file(&file_path).await {
                        log::warn!("Failed to delete oversized model file: {}", e);
                    }
                } else {

                    log::info!(
                        "Model '{}' exists but is incomplete ({} MB, expected min {} MB), will resume download",
                        model_name,
                        file_size_mb,
                        expected_min
                    );

                }
            }
        }

        log::info!("Downloading from: {}", model_def.download_url);
        log::info!("Saving to: {}", file_path.display());

        if !self.models_dir.exists() {
            fs::create_dir_all(&self.models_dir).await?;
        }

        let existing_size: u64 = if file_path.exists() {
            fs::metadata(&file_path)
                .await
                .map(|m| m.len())
                .unwrap_or(0)
        } else {
            0
        };

        let client = Client::builder()
            .tcp_nodelay(true)
            .pool_max_idle_per_host(1)
            .timeout(Duration::from_secs(3600))
            .connect_timeout(Duration::from_secs(30))
            .build()
            .map_err(|e| anyhow!("Failed to create HTTP client: {}", e))?;

        let mut request = client.get(&model_def.download_url);
        if existing_size > 0 {
            log::info!(
                "Resuming download from byte {} ({:.1} MB)",
                existing_size,
                existing_size as f64 / (1024.0 * 1024.0)
            );
            request = request.header("Range", format!("bytes={}-", existing_size));
        }

        let response = request
            .send()
            .await
            .map_err(|e| anyhow!("Failed to start download: {}", e))?;

        let (total_size, resuming) = if response.status() == reqwest::StatusCode::PARTIAL_CONTENT {

            let remaining = response.content_length().unwrap_or(0);
            log::info!("Server supports resume, {} MB remaining", remaining / (1024 * 1024));
            (existing_size + remaining, true)
        } else if response.status().is_success() {

            if existing_size > 0 {
                log::warn!("Server doesn't support resume, starting fresh download");
            }
            (response.content_length().unwrap_or(0), false)
        } else {
            let mut active = self.active_downloads.write().await;
            active.remove(model_name);
            return Err(anyhow!("Download failed with status: {}", response.status()));
        };

        log::info!("Total size: {} MB", total_size / (1024 * 1024));

        let file = if resuming {
            OpenOptions::new()
                .write(true)
                .append(true)
                .open(&file_path)
                .await
                .map_err(|e| anyhow!("Failed to open file for append: {}", e))?
        } else {
            fs::File::create(&file_path)
                .await
                .map_err(|e| anyhow!("Failed to create file: {}", e))?
        };

        let mut writer = BufWriter::with_capacity(8 * 1024 * 1024, file);

        let mut downloaded: u64 = if resuming { existing_size } else { 0 };

        if let Some(ref callback) = progress_callback {
            callback(DownloadProgress::new(downloaded, total_size, 0.0));
        }
        log::info!(
            "Starting at {:.1} MB / {:.1} MB",
            downloaded as f64 / (1024.0 * 1024.0),
            total_size as f64 / (1024.0 * 1024.0)
        );

        let mut last_progress_percent = if total_size > 0 {
            ((downloaded as f64 / total_size as f64) * 100.0) as u8
        } else {
            0
        };
        let mut last_report_time = std::time::Instant::now();
        let mut bytes_since_last_report: u64 = 0;
        let download_start_time = std::time::Instant::now();
        let start_downloaded = downloaded;

        use futures_util::StreamExt;
        let mut stream = response.bytes_stream();

        loop {

            {
                let cancel_flag = self.cancel_download_flag.read().await;
                if cancel_flag.as_ref() == Some(&model_name.to_string()) {
                    log::info!("Download cancelled for model: {}", model_name);

                    let _ = writer.flush().await;
                    drop(writer);

                    let mut active = self.active_downloads.write().await;
                    active.remove(model_name);

                    {
                        let mut models = self.available_models.write().await;
                        if let Some(model_info) = models.get_mut(model_name) {
                            model_info.status = ModelStatus::NotDownloaded;
                        }
                    }

                    return Err(anyhow!("CANCELLED: Download cancelled by user"));
                }
            }

            let next_result = timeout(Duration::from_secs(30), stream.next()).await;

            let chunk = match next_result {

                Err(_) => {
                    log::warn!("Download timeout for {}: no data received for 30 seconds", model_name);
                    let _ = writer.flush().await;

                    let mut active = self.active_downloads.write().await;
                    active.remove(model_name);

                    {
                        let mut models = self.available_models.write().await;
                        if let Some(model_info) = models.get_mut(model_name) {
                            model_info.status = ModelStatus::Error("Download timeout - No data received for 30 seconds".to_string());
                        }
                    }

                    return Err(anyhow!("Download timeout - No data received for 30 seconds"));
                },

                Ok(None) => break,

                Ok(Some(chunk_result)) => {
                    match chunk_result {
                        Ok(c) => c,

                        Err(e) => {
                            log::error!("Download error for {}: {:?}", model_name, e);
                            let _ = writer.flush().await;

                            let mut active = self.active_downloads.write().await;
                            active.remove(model_name);

                            let error_msg = if e.is_timeout() {
                                "Connection timeout - Check your internet"
                            } else if e.is_connect() {
                                "Connection failed - Check your internet"
                            } else if e.is_body() {
                                "Stream interrupted - Network unstable"
                            } else {
                                "Download error"
                            };

                            {
                                let mut models = self.available_models.write().await;
                                if let Some(model_info) = models.get_mut(model_name) {
                                    model_info.status = ModelStatus::Error(error_msg.to_string());
                                }
                            }

                            return Err(anyhow!("{}: {}", error_msg, e));
                        }
                    }
                }
            };
            let chunk_len = chunk.len() as u64;
            writer
                .write_all(&chunk)
                .await
                .map_err(|e| anyhow!("Error writing to file: {}", e))?;

            downloaded += chunk_len;
            bytes_since_last_report += chunk_len;

            let progress_percent = if total_size > 0 {
                let exact_percent = (downloaded as f64 / total_size as f64) * 100.0;
                exact_percent.min(100.0) as u8
            } else {
                0
            };

            let elapsed_since_report = last_report_time.elapsed();
            let is_download_complete = downloaded >= total_size;
            let should_report = progress_percent > last_progress_percent
                || is_download_complete
                || elapsed_since_report.as_millis() >= 500;

            if should_report {

                let speed_mbps = if elapsed_since_report.as_secs_f64() > 0.0 {
                    (bytes_since_last_report as f64 / (1024.0 * 1024.0)) / elapsed_since_report.as_secs_f64()
                } else {

                    let total_elapsed = download_start_time.elapsed().as_secs_f64();
                    if total_elapsed > 0.0 {
                        ((downloaded - start_downloaded) as f64 / (1024.0 * 1024.0)) / total_elapsed
                    } else {
                        0.0
                    }
                };

                log::info!(
                    "Download: {:.1} MB / {:.1} MB ({:.1} MB/s)",
                    downloaded as f64 / (1024.0 * 1024.0),
                    total_size as f64 / (1024.0 * 1024.0),
                    speed_mbps
                );

                {
                    let mut models = self.available_models.write().await;
                    if let Some(model_info) = models.get_mut(model_name) {
                        model_info.status = ModelStatus::Downloading {
                            progress: if is_download_complete { 100 } else { progress_percent }
                        };
                    }
                }

                if let Some(ref callback) = progress_callback {
                    callback(DownloadProgress::new(downloaded, total_size, speed_mbps));
                }

                last_progress_percent = progress_percent;
                last_report_time = std::time::Instant::now();
                bytes_since_last_report = 0;
            }
        }

        writer.flush().await?;
        drop(writer);

        log::info!("Download completed for model: {}", model_name);

        {
            let mut models = self.available_models.write().await;
            if let Some(model_info) = models.get_mut(model_name) {
                model_info.status = ModelStatus::Downloading { progress: 100 };
            }
        }

        if let Some(ref callback) = progress_callback {
            callback(DownloadProgress::new(total_size, total_size, 0.0));
        }

        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

        if let Err(e) = self.validate_gguf_file(&file_path).await {
            log::error!("Downloaded file failed validation: {}", e);

            let _ = fs::remove_file(&file_path).await;

            {
                let mut models = self.available_models.write().await;
                if let Some(model_info) = models.get_mut(model_name) {
                    model_info.status = ModelStatus::Error(format!("Validation failed: {}", e));
                }
            }

            let mut active = self.active_downloads.write().await;
            active.remove(model_name);

            return Err(anyhow!("File validation failed: {}", e));
        }

        {
            let mut models = self.available_models.write().await;
            if let Some(model_info) = models.get_mut(model_name) {
                model_info.status = ModelStatus::Available;
                model_info.path = file_path.clone();
            }
        }

        {
            let mut active = self.active_downloads.write().await;
            active.remove(model_name);
        }

        Ok(())
    }

    async fn validate_gguf_file(&self, path: &PathBuf) -> Result<()> {
        let mut file = fs::File::open(path).await?;

        use tokio::io::AsyncReadExt;
        let mut magic = [0u8; 4];
        file.read_exact(&mut magic).await?;

        if &magic == b"GGUF" {
            Ok(())
        } else if &magic == b"ggjt" || &magic == b"ggla" || &magic == b"ggml" {

            Ok(())
        } else {
            Err(anyhow!(
                "Invalid model file: magic number {:?} doesn't match GGUF/GGML",
                magic
            ))
        }
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

        let file_path = self.models_dir.join(&model_def.gguf_file);

        if file_path.exists() {
            fs::remove_file(&file_path).await?;
            log::info!("Deleted model file: {}", file_path.display());
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
