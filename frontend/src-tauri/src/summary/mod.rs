

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CustomOpenAIConfig {

    pub endpoint: String,

    #[serde(rename = "apiKey")]
    pub api_key: Option<String>,

    pub model: String,

    #[serde(rename = "maxTokens")]
    pub max_tokens: Option<i32>,

    pub temperature: Option<f32>,

    #[serde(rename = "topP")]
    pub top_p: Option<f32>,
}

pub mod commands;
pub mod llm_client;
pub mod processor;
pub mod service;
pub mod summary_engine;
pub mod template_commands;
pub mod templates;

pub use commands::*;
pub use template_commands::*;

pub use llm_client::LLMProvider;
pub use processor::{
    chunk_text, clean_llm_markdown_output, extract_meeting_name_from_markdown,
    generate_meeting_summary, rough_token_count,
};
pub use service::SummaryService;
