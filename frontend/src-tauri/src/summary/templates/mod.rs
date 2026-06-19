

mod defaults;
mod loader;
mod types;

pub use loader::{
    get_template, list_template_ids, list_templates, set_bundled_templates_dir,
    validate_and_parse_template,
};
pub use types::{Template, TemplateSection};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_module_integration() {

        let ids = list_template_ids();
        assert!(!ids.is_empty());

        for id in ids {
            let result = get_template(&id);
            assert!(
                result.is_ok(),
                "Failed to load template '{}': {:?}",
                id,
                result.err()
            );
        }
    }

    #[test]
    fn test_template_metadata() {
        let templates = list_templates();
        assert!(!templates.is_empty());

        for (id, name, description) in templates {
            assert!(!id.is_empty());
            assert!(!name.is_empty());
            assert!(!description.is_empty());
        }
    }
}
