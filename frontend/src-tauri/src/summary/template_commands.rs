use crate::summary::templates;
use crate::summary::templates::Template;
use serde::{Deserialize, Serialize};
use tauri::Runtime;
use tracing::{info, warn};

/// Translates the known strings of the built-in `standard_meeting` template into
/// the UI locale. The template is authored in Russian (the default), so for
/// `ru` (or any unknown string) it is returned unchanged. Strings that are not
/// part of the built-in template (e.g. user-authored custom templates) are left
/// as-is.
fn localize_template(mut template: Template, locale: &str) -> Template {
    let translate = |ru: &str| -> Option<&'static str> {
        match (locale, ru) {
            ("en", "Стандартные заметки встречи") => Some("Standard meeting notes"),
            ("en", "Стандартный шаблон для обычных встреч с акцентом на ключевые итоги и действия.") =>
                Some("Standard template for regular meetings, focused on key outcomes and action items."),
            ("en", "Краткое содержание") => Some("Summary"),
            ("en", "Ключевые решения") => Some("Key decisions"),
            ("en", "Задачи") => Some("Action items"),
            ("en", "Основные моменты обсуждения") => Some("Discussion highlights"),
            ("zh", "Стандартные заметки встречи") => Some("标准会议纪要"),
            ("zh", "Стандартный шаблон для обычных встреч с акцентом на ключевые итоги и действия.") =>
                Some("适用于常规会议的标准模板，侧重关键结论和行动事项。"),
            ("zh", "Краткое содержание") => Some("摘要"),
            ("zh", "Ключевые решения") => Some("关键决定"),
            ("zh", "Задачи") => Some("任务"),
            ("zh", "Основные моменты обсуждения") => Some("讨论要点"),
            _ => None,
        }
    };

    if let Some(name) = translate(&template.name) {
        template.name = name.to_string();
    }
    if let Some(description) = translate(&template.description) {
        template.description = description.to_string();
    }
    for section in &mut template.sections {
        if let Some(title) = translate(&section.title) {
            section.title = title.to_string();
        }
    }

    template
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TemplateInfo {

    pub id: String,

    pub name: String,

    pub description: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TemplateDetails {

    pub id: String,

    pub name: String,

    pub description: String,

    pub sections: Vec<String>,
}

#[tauri::command]
pub async fn api_list_templates<R: Runtime>(
    _app: tauri::AppHandle<R>,
) -> Result<Vec<TemplateInfo>, String> {
    info!("api_list_templates called");

    let locale = crate::current_locale(&_app);
    let templates = templates::list_templates();

    let template_infos: Vec<TemplateInfo> = templates
        .into_iter()
        .map(|(id, name, description)| {
            let localized = localize_template(
                Template {
                    name,
                    description,
                    sections: Vec::new(),
                },
                &locale,
            );
            TemplateInfo {
                id,
                name: localized.name,
                description: localized.description,
            }
        })
        .collect();

    info!("Found {} available templates", template_infos.len());

    Ok(template_infos)
}

#[tauri::command]
pub async fn api_get_template_details<R: Runtime>(
    _app: tauri::AppHandle<R>,
    template_id: String,
) -> Result<TemplateDetails, String> {
    info!("api_get_template_details called for template_id: {}", template_id);

    let locale = crate::current_locale(&_app);
    let template = localize_template(templates::get_template(&template_id)?, &locale);

    let section_titles: Vec<String> = template
        .sections
        .iter()
        .map(|section| section.title.clone())
        .collect();

    let details = TemplateDetails {
        id: template_id,
        name: template.name,
        description: template.description,
        sections: section_titles,
    };

    info!("Retrieved template details for '{}'", details.name);

    Ok(details)
}

#[tauri::command]
pub async fn api_validate_template<R: Runtime>(
    _app: tauri::AppHandle<R>,
    template_json: String,
) -> Result<String, String> {
    info!("api_validate_template called");

    match templates::validate_and_parse_template(&template_json) {
        Ok(template) => {
            info!("Template '{}' validated successfully", template.name);
            Ok(template.name)
        }
        Err(e) => {
            warn!("Template validation failed: {}", e);
            Err(e)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_list_templates() {

    }

    #[tokio::test]
    async fn test_validate_template_valid() {
        let valid_json = r#"
        {
            "name": "Test Template",
            "description": "A test template",
            "sections": [
                {
                    "title": "Summary",
                    "instruction": "Provide a summary",
                    "format": "paragraph"
                }
            ]
        }"#;

        let result = templates::validate_and_parse_template(valid_json);
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_validate_template_invalid() {
        let invalid_json = "invalid json";

        let result = templates::validate_and_parse_template(invalid_json);
        assert!(result.is_err());
    }
}
