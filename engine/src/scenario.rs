use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::LazyLock;

pub const DEFAULT_TYPE: &str = "podcast";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ScenarioProfile {
    #[serde(rename = "name_ar")]
    pub name_ar: String,
    pub name_en: String,
    pub hook_strategy: String,
    pub caption_theme: String,
    pub zoom_style: String,
    pub color_grade: String,
    pub sfx_mood: String,
    #[serde(rename = "pacing")]
    pub pacing_cuts_per_min: f64,
    pub min_clip_sec: f64,
    pub max_clip_sec: f64,
    pub broll_density: f64,
    #[serde(rename = "emphasis_words_boost")]
    pub emphasis_boost: f64,
}

pub static BUILTIN_PODCAST: LazyLock<ScenarioProfile> = LazyLock::new(|| ScenarioProfile {
    name_ar: "بودكاست".to_string(),
    name_en: "podcast".to_string(),
    hook_strategy: "Find the single most compelling calm sentence from this transcript that would stop someone mid-scroll."
        .to_string(),
    caption_theme: "Minimalist Clean".to_string(),
    zoom_style: "gentle".to_string(),
    color_grade: "none".to_string(),
    sfx_mood: "soft_chill".to_string(),
    pacing_cuts_per_min: 4.0,
    min_clip_sec: 25.0,
    max_clip_sec: 60.0,
    broll_density: 0.15,
    emphasis_boost: 1.2,
});

pub fn builtin_podcast() -> ScenarioProfile {
    BUILTIN_PODCAST.clone()
}

fn scenarios_dir() -> PathBuf {
    match std::env::var_os("CLIPPIFY_SCENARIOS_DIR") {
        Some(dir) if !dir.is_empty() => PathBuf::from(dir),
        _ => PathBuf::from("scenarios"),
    }
}

fn normalize_content_type(content_type: &str) -> String {
    let mut ct = content_type.trim().to_lowercase();
    for ext in [".yaml", ".yml"] {
        if ct.ends_with(ext) {
            ct.truncate(ct.len() - ext.len());
            break;
        }
    }
    ct
}

fn load_profile_file(path: &Path) -> Option<ScenarioProfile> {
    let text = std::fs::read_to_string(path).ok()?;
    serde_yaml::from_str(&text).ok()
}

fn load_profile(dir: &Path, content_type: &str) -> Option<ScenarioProfile> {
    for ext in ["yaml", "yml"] {
        let path = dir.join(format!("{content_type}.{ext}"));
        if let Some(profile) = load_profile_file(&path) {
            return Some(profile);
        }
    }
    None
}

pub fn get_profile(content_type: &str) -> ScenarioProfile {
    let mut ct = normalize_content_type(content_type);
    if ct.is_empty() {
        ct = DEFAULT_TYPE.to_string();
    }

    if let Some(profile) = load_profile(&scenarios_dir(), &ct) {
        return profile;
    }

    if ct != DEFAULT_TYPE {
        return get_profile(DEFAULT_TYPE);
    }
    builtin_podcast()
}

pub fn load_profiles() -> HashMap<String, ScenarioProfile> {
    let mut map = HashMap::new();
    let entries = match std::fs::read_dir(scenarios_dir()) {
        Ok(entries) => entries,
        Err(_) => return map,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let ext = path
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.to_lowercase());
        let stem = path.file_stem().and_then(|s| s.to_str()).map(String::from);
        let (Some(ext), Some(stem)) = (ext, stem) else {
            continue;
        };
        if stem.is_empty() || (ext != "yaml" && ext != "yml") {
            continue;
        }
        if let Some(profile) = load_profile_file(&path) {
            map.insert(stem, profile);
        }
    }
    map
}

pub fn list_profiles() -> Vec<String> {
    let mut ids: Vec<String> = load_profiles().into_keys().collect();
    ids.sort();
    ids
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_content_type() {
        assert_eq!(normalize_content_type("  Comedy.YAML "), "comedy");
        assert_eq!(normalize_content_type("vlog.yml"), "vlog");
        assert!(normalize_content_type("   ").is_empty());
    }

    #[test]
    fn get_profile_falls_back_to_builtin_podcast() {
        let profile = get_profile("definitely_not_a_real_type");
        assert_eq!(profile.name_en, "podcast");
        assert_eq!(
            profile,
            ScenarioProfile {
                pacing_cuts_per_min: 4.0,
                min_clip_sec: 25.0,
                max_clip_sec: 60.0,
                broll_density: 0.15,
                emphasis_boost: 1.2,
                ..get_profile("")
            }
        );
    }

    #[test]
    fn empty_content_type_uses_default() {
        assert_eq!(
            get_profile("").name_ar,
            builtin_podcast().name_ar,
        );
    }

    #[test]
    fn parses_yaml_with_renamed_fields() {
        let yaml = r#"
name_ar: "كوميديا"
name_en: comedy
hook_strategy: open with a punchline
caption_theme: Bold Pop
zoom_style: punchy
color_grade: warm
sfx_mood: playful
pacing: 8
min_clip_sec: 15
max_clip_sec: 45
broll_density: 0.3
emphasis_words_boost: 1.5
"#;
        let profile: ScenarioProfile = serde_yaml::from_str(yaml).unwrap();
        assert_eq!(profile.pacing_cuts_per_min, 8.0);
        assert_eq!(profile.emphasis_boost, 1.5);
    }

    #[test]
    fn incomplete_yaml_is_rejected() {
        let yaml = "name_en: broken\n";
        let parsed: Result<ScenarioProfile, _> = serde_yaml::from_str(yaml);
        assert!(parsed.is_err());
    }
}
