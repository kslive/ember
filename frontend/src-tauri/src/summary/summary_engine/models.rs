

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

    pub gguf_file: String,

    pub template: String,

    pub download_url: String,

    pub size_mb: u64,

    pub context_size: u32,

    pub layer_count: u32,

    pub sampling: SamplingParams,

    pub description: String,
}

pub fn get_available_models() -> Vec<ModelDef> {
    vec![

        ModelDef {
            name: "gemma3:1b".to_string(),
            display_name: "Gemma 3 1B (Быстрая)".to_string(),
            gguf_file: "gemma-3-1b-it-Q8_0.gguf".to_string(),
            template: "gemma3".to_string(),
            download_url: "https://huggingface.co/bartowski/google_gemma-3-1b-it-GGUF/resolve/main/google_gemma-3-1b-it-Q8_0.gguf".to_string(),
            size_mb: 1019,
            context_size: 16384,
            layer_count: 26,
            sampling: SamplingParams {
                temperature: 1.0,
                top_k: 64,
                top_p: 0.95,
                stop_tokens: vec!["<end_of_turn>".to_string()],
            },
            description: "Самая быстрая. Работает на любом железе (~1GB RAM). Хороша для быстрых конспектов.".to_string(),
        },
        ModelDef {
            name: "gemma3:4b".to_string(),
            display_name: "Gemma 3 4B (Сбалансированная)".to_string(),
            gguf_file: "gemma-3-4b-it-Q4_K_M.gguf".to_string(),
            template: "gemma3".to_string(),
            download_url: "https://huggingface.co/bartowski/google_gemma-3-4b-it-GGUF/resolve/main/google_gemma-3-4b-it-Q4_K_M.gguf".to_string(),
            size_mb: 2374,
            context_size: 16384,
            layer_count: 35,
            sampling: SamplingParams {
                temperature: 1.0,
                top_k: 64,
                top_p: 0.95,
                stop_tokens: vec!["<end_of_turn>".to_string()],
            },
            description: "Баланс качества и скорости. Нужно ~3.5GB RAM.".to_string(),
        },

        ModelDef {
            name: "qwen2.5:7b".to_string(),
            display_name: "Qwen2.5 7B (Умная)".to_string(),
            gguf_file: "Qwen2.5-7B-Instruct-Q4_K_M.gguf".to_string(),
            template: "chatml".to_string(),
            download_url: "https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf".to_string(),
            size_mb: 4683,
            context_size: 16384,
            layer_count: 28,
            sampling: SamplingParams {
                temperature: 0.7,
                top_k: 20,
                top_p: 0.8,
                stop_tokens: vec!["<|im_end|>".to_string(), "<|endoftext|>".to_string()],
            },
            description: "Заметно умнее Gemma 4B: лучше русский и следование инструкциям. Нужно ~6GB RAM.".to_string(),
        },

        ModelDef {
            name: "qwen2.5:14b".to_string(),
            display_name: "Qwen2.5 14B (Максимум)".to_string(),
            gguf_file: "Qwen2.5-14B-Instruct-Q4_K_M.gguf".to_string(),
            template: "chatml".to_string(),
            download_url: "https://huggingface.co/bartowski/Qwen2.5-14B-Instruct-GGUF/resolve/main/Qwen2.5-14B-Instruct-Q4_K_M.gguf".to_string(),
            size_mb: 8988,
            context_size: 16384,
            layer_count: 48,
            sampling: SamplingParams {
                temperature: 0.7,
                top_k: 20,
                top_p: 0.8,
                stop_tokens: vec!["<|im_end|>".to_string(), "<|endoftext|>".to_string()],
            },
            description: "Лучшее качество для 16GB. Медленнее и прожорливее (~10GB RAM), но самые точные саммари.".to_string(),
        },
    ]
}

pub fn get_model_by_name(name: &str) -> Option<ModelDef> {
    get_available_models().into_iter().find(|m| m.name == name)
}

pub fn get_default_model() -> ModelDef {
    get_available_models()
        .into_iter()
        .next()
        .expect("At least one model must be defined")
}

pub fn get_model_path(app_data_dir: &PathBuf, model_name: &str) -> Result<PathBuf> {
    let model = get_model_by_name(model_name)
        .ok_or_else(|| anyhow!("Unknown model: {}", model_name))?;

    let models_dir = get_models_directory(app_data_dir);
    let model_path = models_dir.join(&model.gguf_file);

    Ok(model_path)
}

pub fn get_models_directory(app_data_dir: &PathBuf) -> PathBuf {
    app_data_dir.join("models").join("summary")
}

pub const GEMMA3_TEMPLATE: &str = "\
<start_of_turn>user
{system_prompt}<end_of_turn>
<start_of_turn>user
{user_prompt}<end_of_turn>
<start_of_turn>model
";

pub const CHATML_TEMPLATE: &str = "\
<|im_start|>system
{system_prompt}<|im_end|>
<|im_start|>user
{user_prompt}<|im_end|>
<|im_start|>assistant
";

pub fn format_prompt(
    template_name: &str,
    system_prompt: &str,
    user_prompt: &str,
) -> Result<String> {
    let template = match template_name {
        "gemma3" => GEMMA3_TEMPLATE,
        "chatml" => CHATML_TEMPLATE,
        _ => return Err(anyhow!("Unknown template: {}", template_name)),
    };

    let formatted = template
        .replace("{system_prompt}", system_prompt)
        .replace("{user_prompt}", user_prompt);

    Ok(formatted)
}

pub const DEFAULT_MAX_TOKENS: i32 = 6144;

pub const DEFAULT_IDLE_TIMEOUT_SECS: u64 = 300;

pub const GENERATION_TIMEOUT_SECS: u64 = 900;
