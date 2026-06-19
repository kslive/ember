

pub mod client;
pub mod commands;
pub mod model_manager;
pub mod models;
pub mod sidecar;

pub use client::{generate_with_builtin, is_sidecar_healthy, shutdown_sidecar_gracefully, force_shutdown_sidecar};

pub use commands::*;
pub use model_manager::{ModelInfo, ModelStatus};
pub use models::{get_available_models, get_default_model, get_model_by_name, ModelDef};
