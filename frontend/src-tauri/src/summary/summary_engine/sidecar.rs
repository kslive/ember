

use std::path::PathBuf;
use std::process::Stdio;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{anyhow, Context, Result};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, ChildStderr, ChildStdin, ChildStdout};
use tokio::sync::{Mutex, RwLock};

#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;

use super::models;

pub struct SidecarManager {

    child_process: Arc<Mutex<Option<Child>>>,

    stdin_writer: Arc<Mutex<Option<ChildStdin>>>,

    stdout_reader: Arc<Mutex<Option<BufReader<ChildStdout>>>>,

    last_activity: Arc<RwLock<Instant>>,

    is_healthy: Arc<AtomicBool>,

    should_shutdown: Arc<AtomicBool>,

    active_request_count: Arc<AtomicUsize>,

    helper_binary_path: PathBuf,

    current_model_path: Arc<RwLock<Option<PathBuf>>>,

    idle_timeout_secs: u64,
}

struct RequestGuard {
    counter: Arc<AtomicUsize>,
}

impl RequestGuard {
    fn new(counter: Arc<AtomicUsize>) -> Self {
        counter.fetch_add(1, Ordering::SeqCst);
        Self { counter }
    }
}

impl Drop for RequestGuard {
    fn drop(&mut self) {
        self.counter.fetch_sub(1, Ordering::SeqCst);
    }
}

impl SidecarManager {

    pub fn new(_app_data_dir: PathBuf) -> Result<Self> {
        let helper_binary_path = Self::resolve_helper_binary()?;

        let idle_timeout_secs = std::env::var("EMBER_MLX_IDLE_TIMEOUT")
            .ok()
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(models::DEFAULT_IDLE_TIMEOUT_SECS);

        log::info!(
            "SidecarManager initialized with idle timeout: {}s",
            idle_timeout_secs
        );
        log::info!("Helper binary path: {}", helper_binary_path.display());

        Ok(Self {
            child_process: Arc::new(Mutex::new(None)),
            stdin_writer: Arc::new(Mutex::new(None)),
            stdout_reader: Arc::new(Mutex::new(None)),
            last_activity: Arc::new(RwLock::new(Instant::now())),
            is_healthy: Arc::new(AtomicBool::new(false)),
            should_shutdown: Arc::new(AtomicBool::new(false)),
            active_request_count: Arc::new(AtomicUsize::new(0)),
            helper_binary_path,
            current_model_path: Arc::new(RwLock::new(None)),
            idle_timeout_secs,
        })
    }

    fn resolve_helper_binary() -> Result<PathBuf> {

        if let Ok(env_path) = std::env::var("EMBER_MLX_HELPER") {
            if !env_path.is_empty() {
                let path = PathBuf::from(env_path);
                if path.exists() {
                    log::info!("Using mlx-helper from EMBER_MLX_HELPER: {}", path.display());
                    return Ok(path);
                }
            }
        }

        if let Ok(exe_path) = std::env::current_exe() {
            if let Some(exe_dir) = exe_path.parent() {
                log::info!("Searching for mlx-helper relative to executable: {}", exe_dir.display());

                let target_triple = std::env::var("TARGET")
                    .unwrap_or_else(|_| {
                        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
                        { "x86_64-unknown-linux-gnu".to_string() }
                        #[cfg(all(target_os = "linux", target_arch = "aarch64"))]
                        { "aarch64-unknown-linux-gnu".to_string() }
                        #[cfg(all(target_os = "macos", target_arch = "x86_64"))]
                        { "x86_64-apple-darwin".to_string() }
                        #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
                        { "aarch64-apple-darwin".to_string() }
                        #[cfg(all(target_os = "windows", target_arch = "x86_64"))]
                        { "x86_64-pc-windows-msvc".to_string() }
                        #[cfg(all(target_os = "windows", target_arch = "aarch64"))]
                        { "aarch64-pc-windows-msvc".to_string() }
                        #[cfg(not(any(
                            all(target_os = "linux", any(target_arch = "x86_64", target_arch = "aarch64")),
                            all(target_os = "macos", any(target_arch = "x86_64", target_arch = "aarch64")),
                            all(target_os = "windows", any(target_arch = "x86_64", target_arch = "aarch64"))
                        )))]
                        { "unknown".to_string() }
                    });

                let binary_name = if cfg!(windows) {
                    format!("mlx-helper-{}.exe", target_triple)
                } else {
                    format!("mlx-helper-{}", target_triple)
                };

                let bundled = exe_dir.join(&binary_name);
                if bundled.exists() {
                    log::info!("Found exact match next to executable: {}", bundled.display());
                    return Ok(bundled);
                }

                log::info!("Attempting fuzzy match in exe dir: {}", exe_dir.display());
                if let Ok(entries) = std::fs::read_dir(exe_dir) {
                    for entry in entries.flatten() {
                        let path = entry.path();
                        if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                            if name.starts_with("mlx-helper") && !name.ends_with(".d") {
                                log::info!("Found fuzzy match next to executable: {}", path.display());
                                return Ok(path);
                            }
                        }
                    }
                }
            }
        }

        if let Ok(resource_dir) = std::env::var("RESOURCE_DIR") {
            log::info!("Searching for mlx-helper in RESOURCE_DIR: {}", resource_dir);
            let resource_path = PathBuf::from(&resource_dir);

            let target_triple = std::env::var("TARGET")
                .unwrap_or_else(|_| {
                     #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
                    { "x86_64-unknown-linux-gnu".to_string() }

                     #[cfg(all(target_os = "linux", target_arch = "aarch64"))]
                    { "aarch64-unknown-linux-gnu".to_string() }
                    #[cfg(all(target_os = "macos", target_arch = "x86_64"))]
                    { "x86_64-apple-darwin".to_string() }
                    #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
                    { "aarch64-apple-darwin".to_string() }
                    #[cfg(all(target_os = "windows", target_arch = "x86_64"))]
                    { "x86_64-pc-windows-msvc".to_string() }
                    #[cfg(all(target_os = "windows", target_arch = "aarch64"))]
                    { "aarch64-pc-windows-msvc".to_string() }
                    #[cfg(not(any(
                        all(target_os = "linux", any(target_arch = "x86_64", target_arch = "aarch64")),
                        all(target_os = "macos", any(target_arch = "x86_64", target_arch = "aarch64")),
                        all(target_os = "windows", any(target_arch = "x86_64", target_arch = "aarch64"))
                    )))]
                    { "unknown".to_string() }
                });

            let binary_name = if cfg!(windows) {
                format!("mlx-helper-{}.exe", target_triple)
            } else {
                format!("mlx-helper-{}", target_triple)
            };

            let bundled = resource_path.join(&binary_name);
            if bundled.exists() {
                log::info!("Found exact match in RESOURCE_DIR: {}", bundled.display());
                return Ok(bundled);
            }

            if let Ok(entries) = std::fs::read_dir(&resource_path) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                        if name.starts_with("mlx-helper") && !name.ends_with(".d") {
                            log::info!("Found fuzzy match in RESOURCE_DIR: {}", path.display());
                            return Ok(path);
                        }
                    }
                }
            }
        } else {
            log::warn!("RESOURCE_DIR environment variable not set");
        }

        if let Ok(manifest_dir) = std::env::var("CARGO_MANIFEST_DIR") {
            let project_root = PathBuf::from(&manifest_dir)
                .parent()
                .and_then(|p| p.parent())
                .ok_or_else(|| anyhow!("Failed to determine project root"))?
                .to_path_buf();

            let candidates = vec![
                project_root.join("frontend/src-tauri/binaries/mlx-helper-aarch64-apple-darwin"),
                project_root.join("target/release/mlx-helper"),
                project_root.join("target/debug/mlx-helper"),
                project_root.join("target/release/mlx-helper.exe"),
                project_root.join("target/debug/mlx-helper.exe"),
            ];

            for candidate in candidates {
                if candidate.exists() {
                    log::info!("Using dev mlx-helper: {}", candidate.display());
                    return Ok(candidate);
                }
            }
        }

        Err(anyhow!(
            "mlx-helper binary not found. Build with 'scripts/build-mlx-helper.sh' or set EMBER_MLX_HELPER env var."
        ))
    }

    pub async fn ensure_running(&self, model_path: PathBuf) -> Result<()> {

        let cached_ok = {
            let current_model = self.current_model_path.read().await;
            current_model.as_ref() == Some(&model_path) && self.is_healthy()
        };
        if cached_ok && self.is_process_alive().await {
            log::debug!("Sidecar already running with correct model");
            self.update_activity().await;
            return Ok(());
        }
        if cached_ok {
            log::warn!("Sidecar marked healthy but process is gone — respawning");
            self.is_healthy.store(false, Ordering::SeqCst);
        }

        self.spawn(model_path).await
    }

    async fn is_process_alive(&self) -> bool {
        let mut child_lock = self.child_process.lock().await;
        if let Some(child) = child_lock.as_mut() {
            match child.try_wait() {
                Ok(None) => true,
                Ok(Some(status)) => {
                    log::warn!("Sidecar exited unexpectedly with status: {}", status);
                    false
                }
                Err(e) => {
                    log::warn!("try_wait() on sidecar failed: {} — assuming dead", e);
                    false
                }
            }
        } else {
            false
        }
    }

    fn spawn_stderr_drainer(stderr: ChildStderr) {
        tokio::spawn(async move {
            let mut reader = BufReader::new(stderr).lines();
            loop {
                match reader.next_line().await {
                    Ok(Some(line)) => {

                        log::debug!("mlx-helper: {}", line);
                    }
                    Ok(None) => {
                        log::debug!("mlx-helper stderr closed");
                        break;
                    }
                    Err(e) => {
                        log::debug!("mlx-helper stderr read error: {}", e);
                        break;
                    }
                }
            }
        });
    }

    async fn spawn(&self, model_path: PathBuf) -> Result<()> {

        self.shutdown().await?;

        log::info!("Spawning mlx-helper sidecar");
        log::info!("Model path: {}", model_path.display());

        #[cfg(unix)]
        let mut command = tokio::process::Command::new("nice");

        #[cfg(not(unix))]
        let mut command = tokio::process::Command::new(&self.helper_binary_path);

        #[cfg(unix)]
        command.arg("-n").arg("10").arg(&self.helper_binary_path);

        command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .env("EMBER_MLX_IDLE_TIMEOUT", self.idle_timeout_secs.to_string());

        #[cfg(target_os = "windows")]
        {
            const CREATE_NO_WINDOW: u32 = 0x08000000;
            const BELOW_NORMAL_PRIORITY_CLASS: u32 = 0x00004000;

            command.creation_flags(CREATE_NO_WINDOW | BELOW_NORMAL_PRIORITY_CLASS);
        }

        let mut child = command
            .spawn()
            .with_context(|| format!("Failed to spawn mlx-helper at {:?}", self.helper_binary_path))?;

        let stdin = child.stdin.take().ok_or_else(|| anyhow!("Failed to get stdin"))?;
        let stdout = child.stdout.take().ok_or_else(|| anyhow!("Failed to get stdout"))?;
        let stderr = child.stderr.take().ok_or_else(|| anyhow!("Failed to get stderr"))?;

        Self::spawn_stderr_drainer(stderr);

        {
            let mut child_lock = self.child_process.lock().await;
            *child_lock = Some(child);
        }

        {
            let mut stdin_lock = self.stdin_writer.lock().await;
            *stdin_lock = Some(stdin);
        }

        {
            let mut stdout_lock = self.stdout_reader.lock().await;
            *stdout_lock = Some(BufReader::new(stdout));
        }

        {
            let mut current_model = self.current_model_path.write().await;
            *current_model = Some(model_path);
        }

        self.is_healthy.store(true, Ordering::SeqCst);
        self.should_shutdown.store(false, Ordering::SeqCst);
        self.update_activity().await;

        log::info!("Sidecar spawned successfully");

        self.start_health_check_loop();
        self.start_idle_check_loop();

        Ok(())
    }

    pub async fn send_request(&self, request_json: String, timeout: Duration) -> Result<String> {
        match self.send_request_once(request_json.clone(), timeout).await {
            Ok(resp) => Ok(resp),
            Err(e) if Self::looks_like_dead_sidecar(&e) => {
                log::warn!(
                    "Sidecar request failed — looks like dead pipe ({}). Respawning and retrying once.",
                    e
                );
                self.is_healthy.store(false, Ordering::SeqCst);

                let model_path = {
                    let cur = self.current_model_path.read().await;
                    cur.clone()
                };
                if let Some(path) = model_path {

                    if let Err(spawn_err) = self.spawn(path).await {
                        return Err(anyhow!(
                            "Sidecar died and respawn failed: {} (original error: {})",
                            spawn_err,
                            e
                        ));
                    }
                    self.send_request_once(request_json, timeout).await
                } else {

                    Err(e)
                }
            }
            Err(e) => Err(e),
        }
    }

    fn looks_like_dead_sidecar(e: &anyhow::Error) -> bool {
        let s = format!("{:#}", e).to_lowercase();
        s.contains("sidecar closed stdout")
            || s.contains("sidecar not running")
            || s.contains("broken pipe")
            || s.contains("connection reset")
    }

    async fn send_request_once(&self, request_json: String, timeout: Duration) -> Result<String> {

        let _guard = RequestGuard::new(self.active_request_count.clone());

        if !self.is_process_alive().await {
            return Err(anyhow!("Sidecar not running"));
        }

        {
            let mut stdin_lock = self.stdin_writer.lock().await;
            let stdin = stdin_lock
                .as_mut()
                .ok_or_else(|| anyhow!("Sidecar not running"))?;

            stdin
                .write_all(request_json.as_bytes())
                .await
                .context("Failed to write request to stdin")?;
            stdin
                .write_all(b"\n")
                .await
                .context("Failed to write newline")?;
            stdin.flush().await.context("Failed to flush stdin")?;
        }

        match tokio::time::timeout(timeout, self.read_response()).await {
            Ok(Ok(response)) => {
                self.update_activity().await;
                Ok(response)
            }
            Ok(Err(e)) => Err(e),
            Err(_) => {

                log::error!("Request timeout after {:?}, shutting down sidecar", timeout);
                if let Err(shutdown_err) = self.shutdown().await {
                    log::error!("Failed to shutdown sidecar after timeout: {}", shutdown_err);
                }
                Err(anyhow!("Request timed out after {:?}", timeout))
            }
        }
    }

    async fn read_response(&self) -> Result<String> {
        let mut stdout_lock = self.stdout_reader.lock().await;
        let reader = stdout_lock
            .as_mut()
            .ok_or_else(|| anyhow!("Sidecar not running"))?;

        let mut line = String::new();
        reader
            .read_line(&mut line)
            .await
            .context("Failed to read response from stdout")?;

        if line.is_empty() {
            return Err(anyhow!("Sidecar closed stdout (process may have crashed)"));
        }

        Ok(line.trim().to_string())
    }

    async fn send_ping(&self) -> Result<()> {
        let request = serde_json::json!({"type": "ping"}).to_string();
        let timeout = Duration::from_secs(5);

        {
            let mut stdin_lock = self.stdin_writer.lock().await;
            if let Some(stdin) = stdin_lock.as_mut() {
                stdin.write_all(request.as_bytes()).await?;
                stdin.write_all(b"\n").await?;
                stdin.flush().await?;
            } else {
                return Err(anyhow!("Sidecar not running"));
            }
        }

        let response = tokio::time::timeout(timeout, self.read_response()).await??;

        let resp: serde_json::Value = serde_json::from_str(&response)?;
        if resp.get("type").and_then(|t| t.as_str()) == Some("pong") {
            Ok(())
        } else {
            Err(anyhow!("Unexpected ping response: {}", response))
        }
    }

    pub async fn shutdown_gracefully(&self) -> Result<()> {
        log::info!("Initiating graceful shutdown of sidecar");

        self.should_shutdown.store(true, Ordering::SeqCst);

        let start = Instant::now();
        let max_wait = Duration::from_secs(600);

        loop {
            let count = self.active_request_count.load(Ordering::SeqCst);
            if count == 0 {
                log::info!("No active requests, proceeding with shutdown");
                break;
            }

            if start.elapsed() > max_wait {
                log::warn!("Timed out waiting for active requests ({} active), forcing shutdown", count);
                break;
            }

            log::debug!("Waiting for {} active requests to complete...", count);
            tokio::time::sleep(Duration::from_millis(500)).await;
        }

        self.shutdown().await
    }

    pub async fn shutdown(&self) -> Result<()> {

        self.should_shutdown.store(true, Ordering::SeqCst);

        if self.is_healthy() {
            let request = serde_json::json!({"type": "shutdown"}).to_string();
            let _timeout = Duration::from_secs(5);

            let _ = async {
                let mut stdin_lock = self.stdin_writer.lock().await;
                if let Some(stdin) = stdin_lock.as_mut() {
                    stdin.write_all(request.as_bytes()).await?;
                    stdin.write_all(b"\n").await?;
                    stdin.flush().await?;
                }
                Ok::<(), anyhow::Error>(())
            }.await;
        }

        {
            let mut child_lock = self.child_process.lock().await;
            if let Some(mut child) = child_lock.take() {
                match tokio::time::timeout(Duration::from_secs(3), child.wait()).await {
                    Ok(Ok(status)) => {
                        log::info!("Sidecar exited with status: {}", status);
                    }
                    Ok(Err(e)) => {
                        log::error!("Failed to wait for sidecar: {}", e);
                    }
                    Err(_) => {
                        log::warn!("Sidecar didn't exit gracefully, killing");
                        let _ = child.kill().await;
                    }
                }
            }
        }

        {
            let mut stdin_lock = self.stdin_writer.lock().await;
            *stdin_lock = None;
        }

        {
            let mut stdout_lock = self.stdout_reader.lock().await;
            *stdout_lock = None;
        }

        {
            let mut current_model = self.current_model_path.write().await;
            *current_model = None;
        }

        self.is_healthy.store(false, Ordering::SeqCst);

        log::info!("Sidecar shutdown complete");
        Ok(())
    }

    pub fn is_healthy(&self) -> bool {
        self.is_healthy.load(Ordering::SeqCst)
    }

    async fn update_activity(&self) {
        let mut last_activity = self.last_activity.write().await;
        *last_activity = Instant::now();
    }

    async fn seconds_since_activity(&self) -> u64 {
        let last_activity = self.last_activity.read().await;
        last_activity.elapsed().as_secs()
    }

    fn start_health_check_loop(&self) {
        let manager = Self {
            child_process: self.child_process.clone(),
            stdin_writer: self.stdin_writer.clone(),
            stdout_reader: self.stdout_reader.clone(),
            last_activity: self.last_activity.clone(),
            is_healthy: self.is_healthy.clone(),
            should_shutdown: self.should_shutdown.clone(),
            active_request_count: self.active_request_count.clone(),
            helper_binary_path: self.helper_binary_path.clone(),
            current_model_path: self.current_model_path.clone(),
            idle_timeout_secs: self.idle_timeout_secs,
        };

        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(30));
            interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

            loop {
                interval.tick().await;

                if manager.should_shutdown.load(Ordering::SeqCst) {
                    log::debug!("Health check loop: shutdown flag set, exiting");
                    break;
                }

                if !manager.is_healthy() {
                    log::debug!("Health check loop: sidecar unhealthy, skipping ping");
                    continue;
                }

                if manager.active_request_count.load(Ordering::SeqCst) > 0 {
                    continue;
                }

                log::debug!("Health check: sending ping");
                if let Err(e) = manager.send_ping().await {
                    log::warn!("Health check failed: {}", e);
                    manager.is_healthy.store(false, Ordering::SeqCst);
                }
            }

            log::debug!("Health check loop exited");
        });
    }

    fn start_idle_check_loop(&self) {
        let manager = Self {
            child_process: self.child_process.clone(),
            stdin_writer: self.stdin_writer.clone(),
            stdout_reader: self.stdout_reader.clone(),
            last_activity: self.last_activity.clone(),
            is_healthy: self.is_healthy.clone(),
            should_shutdown: self.should_shutdown.clone(),
            active_request_count: self.active_request_count.clone(),
            helper_binary_path: self.helper_binary_path.clone(),
            current_model_path: self.current_model_path.clone(),
            idle_timeout_secs: self.idle_timeout_secs,
        };

        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(60));
            interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

            loop {
                interval.tick().await;

                if manager.should_shutdown.load(Ordering::SeqCst) {
                    log::debug!("Idle check loop: shutdown flag set, exiting");
                    break;
                }

                if manager.active_request_count.load(Ordering::SeqCst) > 0 {

                    manager.update_activity().await;
                    continue;
                }

                let idle_secs = manager.seconds_since_activity().await;
                log::debug!("Idle check: {}s since last activity", idle_secs);

                if idle_secs > manager.idle_timeout_secs {
                    log::info!(
                        "Sidecar idle for {}s (timeout: {}s), shutting down",
                        idle_secs,
                        manager.idle_timeout_secs
                    );

                    if let Err(e) = manager.shutdown().await {
                        log::error!("Failed to shutdown idle sidecar: {}", e);
                    }

                    break;
                }
            }

            log::debug!("Idle check loop exited");
        });
    }
}

impl Drop for SidecarManager {
    fn drop(&mut self) {

        self.should_shutdown.store(true, Ordering::SeqCst);

        log::debug!("SidecarManager dropped");
    }
}
