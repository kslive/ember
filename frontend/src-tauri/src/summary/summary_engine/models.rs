

use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SamplingParams {

    pub temperature: f32,

    pub top_k: i32,

    pub top_p: f32,

    pub stop_tokens: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelDef {

    pub name: String,

    pub display_name: String,

    pub template: String,

    pub model_id: String,

    pub size_mb: u64,

    pub context_size: u32,

    pub sampling: SamplingParams,

    pub description: String,

    pub recommended: bool,
}

pub fn get_available_models() -> Vec<ModelDef> {
    vec![
        ModelDef {
            name: "qwen3:1.7b".to_string(),
            display_name: "Qwen3 1.7B (Быстрая)".to_string(),
            template: "chatml".to_string(),
            model_id: "mlx-community/Qwen3-1.7B-4bit".to_string(),
            size_mb: 1050,
            context_size: 32768,
            sampling: SamplingParams {
                temperature: 0.7,
                top_k: 20,
                top_p: 0.8,
                stop_tokens: vec!["<|im_end|>".to_string(), "<|endoftext|>".to_string()],
            },
            description: "Самая быстрая. Работает на любом железе (~2GB RAM). Хороша для быстрых конспектов.".to_string(),
            recommended: false,
        },
        ModelDef {
            name: "qwen3:4b".to_string(),
            display_name: "Qwen3 4B (Сбалансированная)".to_string(),
            template: "chatml".to_string(),
            model_id: "mlx-community/Qwen3-4B-4bit".to_string(),
            size_mb: 2400,
            context_size: 24576,
            sampling: SamplingParams {
                temperature: 0.7,
                top_k: 20,
                top_p: 0.8,
                stop_tokens: vec!["<|im_end|>".to_string(), "<|endoftext|>".to_string()],
            },
            description: "Баланс качества и скорости. Нужно ~6GB RAM.".to_string(),
            recommended: false,
        },
        ModelDef {
            name: "qwen3:8b".to_string(),
            display_name: "Qwen3 8B (Максимум)".to_string(),
            template: "chatml".to_string(),
            model_id: "mlx-community/Qwen3-8B-4bit".to_string(),
            size_mb: 4700,
            context_size: 16384,
            sampling: SamplingParams {
                temperature: 0.7,
                top_k: 20,
                top_p: 0.8,
                stop_tokens: vec!["<|im_end|>".to_string(), "<|endoftext|>".to_string()],
            },
            description: "Лучшее качество. Нужно ~10GB RAM, но самые точные саммари.".to_string(),
            recommended: true,
        },
    ]
}

pub fn get_model_by_name(name: &str) -> Option<ModelDef> {
    get_available_models().into_iter().find(|m| m.name == name)
}

pub fn get_default_model() -> ModelDef {
    get_model_by_name("qwen3:8b").expect("Default model qwen3:8b must be defined")
}

pub fn get_model_path(app_data_dir: &PathBuf, model_name: &str) -> Result<PathBuf> {
    let model = get_model_by_name(model_name)
        .ok_or_else(|| anyhow!("Unknown model: {}", model_name))?;

    let models_dir = get_models_directory(app_data_dir);
    let model_path = models_dir.join(&model.model_id);

    Ok(model_path)
}

pub fn get_models_directory(app_data_dir: &PathBuf) -> PathBuf {
    app_data_dir.join("models").join("summary")
}

pub fn is_model_dir_valid(model_dir: &PathBuf) -> bool {
    if !model_dir.join("config.json").exists() {
        return false;
    }

    if let Ok(entries) = std::fs::read_dir(model_dir) {
        for entry in entries.flatten() {
            if let Some(name) = entry.file_name().to_str() {
                if name.ends_with(".safetensors") {
                    return true;
                }
            }
        }
    }

    false
}

pub const DEFAULT_MAX_TOKENS: i32 = 6144;

pub const DEFAULT_IDLE_TIMEOUT_SECS: u64 = 300;

pub const GENERATION_TIMEOUT_SECS: u64 = 900;
