

pub const STANDARD_MEETING: &str = include_str!("../../../templates/standard_meeting.json");

pub fn get_builtin_templates() -> Vec<(&'static str, &'static str)> {
    vec![("standard_meeting", STANDARD_MEETING)]
}

pub fn get_builtin_template(id: &str) -> Option<&'static str> {
    match id {

        _ => Some(STANDARD_MEETING),
    }
}

pub fn list_builtin_template_ids() -> Vec<&'static str> {
    vec!["standard_meeting"]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_builtin_templates_valid_json() {
        for (id, content) in get_builtin_templates() {
            let result = serde_json::from_str::<serde_json::Value>(content);
            assert!(
                result.is_ok(),
                "Built-in template '{}' contains invalid JSON: {:?}",
                id,
                result.err()
            );
        }
    }

    #[test]
    fn test_get_builtin_template() {
        assert!(get_builtin_template("standard_meeting").is_some());
    }
}
