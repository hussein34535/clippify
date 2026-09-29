use crate::llm::LlmBridge;
use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

pub const LIBRARY_DIR: &str = "style_dna_library";
const MAX_PROMPT_WORDS: usize = 400;

const QUESTION_WORDS: &[&str] = &[
    "what", "why", "how", "who", "when", "where", "which", "whose", "do you",
    "did you", "have you", "can you", "could you", "will you", "are you",
    "is it", "is this", "ever wondered",
];
const SHOCK_WORDS: &[&str] = &[
    "insane", "crazy", "shocking", "unbelievable", "nobody", "warning",
    "stop doing", "worst", "never do", "you won't",
];
const STORY_STARTERS: &[&str] = &[
    "so ", "one day", "back when", "story time", "yesterday", "last week",
    "last year", "when i was",
];

const VALID_HOOKS: &[&str] = &["question", "statement", "shock", "story"];
const VALID_CASES: &[&str] = &["upper", "lower", "mixed"];
const VALID_MOODS: &[&str] = &["warm", "cool", "neutral", "high_contrast"];
const VALID_TRANSITIONS: &[&str] = &["cut", "fade", "whip"];

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct StyleDNA {
    pub cut_rhythm: f64,
    pub avg_clip_duration: f64,
    pub hook_style: String,
    pub caption_emoji_density: f64,
    pub caption_case: String,
    pub color_mood: String,
    pub pacing_acceleration: bool,
    pub sfx_density: f64,
    pub broll_ratio: f64,
    pub transition_preference: String,
}

impl Default for StyleDNA {
    fn default() -> Self {
        StyleDNA {
            cut_rhythm: 0.0,
            avg_clip_duration: 0.0,
            hook_style: "statement".into(),
            caption_emoji_density: 0.0,
            caption_case: "mixed".into(),
            color_mood: "neutral".into(),
            pacing_acceleration: false,
            sfx_density: 0.0,
            broll_ratio: 0.0,
            transition_preference: "cut".into(),
        }
    }
}

fn round3(x: f64) -> f64 {
    (x * 1000.0).round() / 1000.0
}

fn round4(x: f64) -> f64 {
    (x * 10000.0).round() / 10000.0
}

fn clamp01(x: f64) -> f64 {
    x.max(0.0).min(1.0)
}

fn is_emoji(c: char) -> bool {
    matches!(c as u32,
        0x1F300..=0x1FAFF
        | 0x1F000..=0x1F0FF
        | 0x2600..=0x27BF
        | 0x2B00..=0x2BFF
        | 0xFE0F)
}

fn clips_of<'a>(meta: &'a Value) -> Vec<&'a Value> {
    match meta {
        Value::Array(items) => items.iter().collect(),
        Value::Object(obj) => match obj.get("clips") {
            Some(Value::Array(items)) => items.iter().collect(),
            _ => Vec::new(),
        },
        _ => Vec::new(),
    }
}

fn clip_field<'a>(clip: &'a Value, names: &[&str]) -> Option<&'a Value> {
    for n in names {
        if let Some(v) = clip.get(*n) {
            if !v.is_null() {
                return Some(v);
            }
        }
    }
    None
}

fn as_f64(v: &Value) -> Option<f64> {
    v.as_f64()
}

fn durations_of(clips: &[&Value]) -> Vec<f64> {
    let mut out = Vec::new();
    for c in clips {
        if let Some(d) = clip_field(c, &["duration"]).and_then(as_f64) {
            if d >= 0.0 {
                out.push(d);
            }
            continue;
        }
        if let (Some(s), Some(e)) =
            (c.get("start").and_then(as_f64), c.get("end").and_then(as_f64))
        {
            if e > s {
                out.push(e - s);
            }
        }
    }
    out
}

fn push_overlay_text(v: &Value, out: &mut Vec<String>) {
    if let Value::String(s) = v {
        let t = s.trim();
        if !t.is_empty() {
            out.push(t.to_string());
        }
    }
}

fn overlay_texts_of(clips: &[&Value]) -> Vec<String> {
    let mut out = Vec::new();
    for c in clips {
        let raw = clip_field(
            c,
            &["text_overlays", "text_overlay", "overlays", "caption"],
        );
        if let Some(raw) = raw {
            match raw {
                Value::Array(items) => {
                    for item in items {
                        push_overlay_text(item, &mut out);
                    }
                }
                other => push_overlay_text(other, &mut out),
            }
        }
    }
    out
}

fn classify_hook(opening_text: &str) -> String {
    let t = opening_text.to_lowercase();
    let t = t.trim();
    let head: String = t.chars().take(40).collect();
    if QUESTION_WORDS.iter().any(|w| t.starts_with(w) || head.contains(w)) {
        return "question".into();
    }
    if SHOCK_WORDS.iter().any(|w| head.contains(w)) {
        return "shock".into();
    }
    if STORY_STARTERS.iter().any(|s| t.starts_with(s)) {
        return "story".into();
    }
    "statement".into()
}

pub fn heuristic(transcript: &str, clip_metadata: &Value) -> StyleDNA {
    let clips = clips_of(clip_metadata);
    let words: Vec<&str> = transcript.split_whitespace().collect();
    let durations = durations_of(&clips);
    let overlays = overlay_texts_of(&clips);

    let total_duration: f64 = durations.iter().sum();
    let minutes = total_duration / 60.0;
    let mut dna = StyleDNA::default();

    if minutes > 0.0 {
        dna.cut_rhythm = round3(durations.len() as f64 / minutes);
    }
    if !durations.is_empty() {
        dna.avg_clip_duration = round3(total_duration / durations.len() as f64);
    }

    let mut opening_parts: Vec<String> = Vec::new();
    if let Some(first) = clips.first() {
        opening_parts.extend(overlay_texts_of(&[first]));
    }
    opening_parts.extend(words.iter().take(8).map(|w| w.to_string()));
    if !opening_parts.is_empty() {
        dna.hook_style = classify_hook(&opening_parts.join(" "));
    }

    let joined = overlays.join(" ");
    let letters: String = joined
        .chars()
        .filter(|c| c.is_ascii_alphabetic())
        .collect();
    if !letters.is_empty() {
        if letters.chars().all(|c| c.is_uppercase()) {
            dna.caption_case = "upper".into();
        } else if letters.chars().all(|c| c.is_lowercase()) {
            dna.caption_case = "lower".into();
        } else {
            dna.caption_case = "mixed".into();
        }
        let emojis = joined.chars().filter(|c| is_emoji(*c)).count();
        dna.caption_emoji_density =
            round4(clamp01(emojis as f64 / joined.chars().count().max(1) as f64));
    }

    for c in &clips {
        if let Some(mood) =
            clip_field(c, &["color_mood", "mood"]).and_then(|v| v.as_str())
        {
            let mood = mood.trim().to_lowercase();
            if VALID_MOODS.contains(&mood.as_str()) {
                dna.color_mood = mood;
                break;
            }
        }
    }

    if durations.len() >= 2 {
        let mid = (durations.len() / 2).max(1);
        let early = &durations[..mid];
        let late = &durations[mid..];
        if !late.is_empty() {
            let early_avg = early.iter().sum::<f64>() / early.len() as f64;
            let late_avg = late.iter().sum::<f64>() / late.len() as f64;
            if late_avg < early_avg {
                dna.pacing_acceleration = true;
            }
        }
    }

    let mut sfx_count = 0usize;
    for c in &clips {
        if let Some(sfx) = c.get("sfx") {
            match sfx {
                Value::Array(items) => sfx_count += items.len(),
                Value::String(s) if !s.trim().is_empty() => sfx_count += 1,
                Value::Bool(true) => sfx_count += 1,
                Value::Number(_) => sfx_count += 1,
                _ => {}
            }
        }
    }
    if minutes > 0.0 && sfx_count > 0 {
        dna.sfx_density = round3(sfx_count as f64 / minutes);
    }

    if !clips.is_empty() {
        let flagged = clips
            .iter()
            .filter(|c| matches!(c.get("broll"), Some(Value::Bool(true))))
            .count();
        dna.broll_ratio = round3(clamp01(flagged as f64 / clips.len() as f64));
    }

    let mut counts: Vec<(String, usize)> = Vec::new();
    for c in &clips {
        if let Some(t) = c.get("transition").and_then(|v| v.as_str()) {
            let t = t.trim().to_lowercase();
            if VALID_TRANSITIONS.contains(&t.as_str()) {
                match counts.iter_mut().find(|(k, _)| *k == t) {
                    Some((_, n)) => *n += 1,
                    None => counts.push((t, 1)),
                }
            }
        }
    }
    if let Some((best, _)) = counts.iter().max_by_key(|(_, n)| *n) {
        dna.transition_preference = best.clone();
    }

    dna
}

fn build_prompt(transcript: &str, clip_metadata: &Value) -> String {
    let words: Vec<&str> = transcript.split_whitespace().take(MAX_PROMPT_WORDS).collect();
    let keep_keys = [
        "duration", "start", "end", "gap", "text_overlay", "text_overlays",
        "overlays", "sfx", "broll", "transition", "color_mood", "mood",
    ];
    let compact_clips: Vec<Value> = clips_of(clip_metadata)
        .iter()
        .filter_map(|c| c.as_object())
        .map(|obj| {
            let mut m = Map::new();
            for k in keep_keys {
                if let Some(v) = obj.get(k) {
                    m.insert(k.to_string(), v.clone());
                }
            }
            Value::Object(m)
        })
        .collect();
    let meta_block = serde_json::to_string(&compact_clips).unwrap_or_default();
    let schema = "{\n\
          \"cut_rhythm\": 0.0,\n\
          \"avg_clip_duration\": 0.0,\n\
          \"hook_style\": \"question|statement|shock|story\",\n\
          \"caption_emoji_density\": 0.0,\n\
          \"caption_case\": \"upper|lower|mixed\",\n\
          \"color_mood\": \"warm|cool|neutral|high_contrast\",\n\
          \"pacing_acceleration\": false,\n\
          \"sfx_density\": 0.0,\n\
          \"broll_ratio\": 0.0,\n\
          \"transition_preference\": \"cut|fade|whip\"\n\
        }\n";
    format!(
        "You are a senior video editor analyzing another creator's editing \
         style fingerprint. Below are a word-level transcript (seconds) and \
         the resulting clip metadata (durations, gaps, text overlays, sfx, \
         b-roll flags, transitions). Infer their editing DNA and respond with \
         ONLY valid JSON (no markdown, no commentary) shaped exactly like \
         this:\n{schema}Rules: cut_rhythm = cuts per minute; \
         avg_clip_duration in seconds; caption_emoji_density and broll_ratio \
         are floats in [0,1]; pacing_acceleration is true when clips get \
         shorter toward the end.\n\nCLIP METADATA:\n{meta_block}\n\n\
         TRANSCRIPT:\n{}",
        words.join("\n")
    )
}

fn extract_json(text: &str) -> Result<Value> {
    let mut t = text.trim();
    if t.starts_with("```") {
        if let Some(pos) = t.find("```").map(|p| p + 3) {
            let rest = &t[pos..];
            let rest = rest.strip_prefix("json").unwrap_or(rest);
            let end = rest.find("```").unwrap_or(rest.len());
            t = rest[..end].trim();
        }
    }
    let start = [t.find('{'), t.find('[')]
        .into_iter()
        .flatten()
        .min()
        .context("no JSON found in LLM response")?;
    let end = t.rfind('}').max(t.rfind(']')).context("no JSON found in LLM response")?;
    if end < start {
        bail!("no JSON found in LLM response");
    }
    Ok(serde_json::from_str(&t[start..=end])?)
}

fn merge_llm_into(mut base: StyleDNA, data: &Value) -> StyleDNA {
    let obj = match data.as_object() {
        Some(o) => o,
        None => return base,
    };
    if let Some(f) = obj.get("cut_rhythm").and_then(as_f64).filter(|f| *f >= 0.0) {
        base.cut_rhythm = round3(f);
    }
    if let Some(f) = obj
        .get("avg_clip_duration")
        .and_then(as_f64)
        .filter(|f| *f >= 0.0)
    {
        base.avg_clip_duration = round3(f);
    }
    if let Some(v) = obj
        .get("hook_style")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_lowercase())
    {
        if VALID_HOOKS.contains(&v.as_str()) {
            base.hook_style = v;
        }
    }
    if let Some(v) = obj.get("caption_emoji_density").and_then(as_f64) {
        base.caption_emoji_density = round4(clamp01(v));
    }
    if let Some(v) = obj
        .get("caption_case")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_lowercase())
    {
        if VALID_CASES.contains(&v.as_str()) {
            base.caption_case = v;
        }
    }
    if let Some(v) = obj
        .get("color_mood")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_lowercase())
    {
        if VALID_MOODS.contains(&v.as_str()) {
            base.color_mood = v;
        }
    }
    if let Some(v) = obj.get("pacing_acceleration").and_then(|v| v.as_bool()) {
        base.pacing_acceleration = v;
    }
    if let Some(v) = obj.get("sfx_density").and_then(as_f64).filter(|f| *f >= 0.0) {
        base.sfx_density = round3(v);
    }
    if let Some(v) = obj.get("broll_ratio").and_then(as_f64) {
        base.broll_ratio = round3(clamp01(v));
    }
    if let Some(v) = obj
        .get("transition_preference")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_lowercase())
    {
        if VALID_TRANSITIONS.contains(&v.as_str()) {
            base.transition_preference = v;
        }
    }
    base
}

pub async fn extract(
    transcript: &str,
    clip_metadata: &serde_json::Value,
    llm: &LlmBridge,
) -> Result<StyleDNA> {
    let fallback = heuristic(transcript, clip_metadata);
    let prompt = build_prompt(transcript, clip_metadata);
    let raw = match llm.ask(&prompt, 0.3, true).await {
        Ok(resp) => resp.text,
        Err(_) => return Ok(fallback),
    };
    let data = match extract_json(&raw) {
        Ok(v) => v,
        Err(_) => return Ok(fallback),
    };
    Ok(merge_llm_into(fallback, &data))
}

pub fn to_prompt(dna: &StyleDNA) -> String {
    let accel = if dna.pacing_acceleration {
        "accelerates - cuts get shorter toward the end"
    } else {
        "steady throughout"
    };
    let emoji = if dna.caption_emoji_density <= 0.001 {
        "no emojis in captions".to_string()
    } else if dna.caption_emoji_density < 0.05 {
        format!(
            "sparse emojis in captions (density {})",
            dna.caption_emoji_density
        )
    } else {
        format!(
            "frequent emojis in captions (density {})",
            dna.caption_emoji_density
        )
    };
    let broll_pct = (dna.broll_ratio * 100.0).round() as i64;
    format!(
        "EDITING STYLE DNA - clone this creator's fingerprint:\n\
         - Pacing: {} cuts/min, average clip length {}s; tempo {}.\n\
         - Hook: open with a {}.\n\
         - Captions: {} case, {}.\n\
         - Look: {} color mood.\n\
         - Sound: {} SFX hits per minute.\n\
         - B-roll: use b-roll on ~{}% of clips.\n\
         - Transitions: prefer hard '{}' cuts.",
        dna.cut_rhythm,
        dna.avg_clip_duration,
        accel,
        dna.hook_style,
        dna.caption_case.to_uppercase(),
        emoji,
        dna.color_mood,
        dna.sfx_density,
        broll_pct,
        dna.transition_preference
    )
}

fn library_path(name: &str) -> Result<std::path::PathBuf> {
    let raw = name.trim();
    if raw.is_empty() || raw.starts_with('.') || raw.contains('/') || raw.contains('\\') {
        bail!("style DNA name must be a bare filename fragment");
    }
    let safe: String = raw
        .chars()
        .filter(|c| c.is_alphanumeric() || *c == '-' || *c == '_' || *c == ' ')
        .collect();
    let safe = safe.trim().replace(' ', "_");
    if safe.is_empty() {
        bail!("style DNA name must contain word characters");
    }
    Ok(std::path::Path::new(LIBRARY_DIR).join(format!("{safe}.json")))
}

pub fn save(dna: &StyleDNA, name: &str) -> Result<()> {
    let path = library_path(name)?;
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    std::fs::write(path, serde_json::to_string_pretty(dna)?)?;
    Ok(())
}

pub fn load(name: &str) -> Result<StyleDNA> {
    let path = library_path(name)?;
    let text =
        std::fs::read_to_string(&path).with_context(|| format!("style DNA '{name}' not found"))?;
    Ok(serde_json::from_str(&text)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn heuristic_full_pipeline() {
        let meta = json!([
            {"duration": 10.0, "text_overlay": "WHAT IF #fyp", "broll": true, "sfx": ["whoosh"], "transition": "whip"},
            {"start": 0.0, "end": 4.0, "color_mood": "cool"},
            {"duration": 2.0}
        ]);
        let dna = heuristic("what if everything you know is wrong today", &meta);
        assert_eq!(dna.hook_style, "question");
        assert!((dna.cut_rhythm - 11.25).abs() < 0.01);
        assert!((dna.avg_clip_duration - 5.333).abs() < 0.01);
        assert_eq!(dna.caption_case, "mixed");
        assert!(dna.pacing_acceleration);
        assert!((dna.broll_ratio - 0.333).abs() < 0.01);
        assert!(dna.sfx_density > 0.0);
        assert_eq!(dna.color_mood, "cool");
        assert_eq!(dna.transition_preference, "whip");
    }

    #[test]
    fn heuristic_empty_defaults() {
        let dna = heuristic("", &json!([]));
        assert_eq!(dna, StyleDNA::default());
    }

    #[test]
    fn extract_json_handles_fences() {
        let v = extract_json("```json\n{\"cut_rhythm\": 42.0}\n```").unwrap();
        assert_eq!(v["cut_rhythm"], json!(42.0));
        let w = extract_json("junk {\"a\": 1} tail").unwrap();
        assert_eq!(w["a"], json!(1));
    }

    #[test]
    fn merge_rejects_invalid_values() {
        let base = StyleDNA::default();
        let merged = merge_llm_into(
            base,
            &json!({
                "hook_style": "NOPE",
                "cut_rhythm": -5.0,
                "caption_emoji_density": 7.0,
                "broll_ratio": 2.0,
                "pacing_acceleration": true
            }),
        );
        assert_eq!(merged.hook_style, "statement");
        assert_eq!(merged.cut_rhythm, 0.0);
        assert_eq!(merged.caption_emoji_density, 1.0);
        assert_eq!(merged.broll_ratio, 1.0);
        assert!(merged.pacing_acceleration);
    }

    #[test]
    fn to_prompt_renders_fragment() {
        let mut dna = StyleDNA::default();
        dna.pacing_acceleration = true;
        let s = to_prompt(&dna);
        assert!(s.contains("EDITING STYLE DNA"));
        assert!(s.contains("accelerates"));
        assert!(s.contains("statement"));
    }

    #[test]
    fn save_load_roundtrip() {
        let mut dna = StyleDNA::default();
        dna.cut_rhythm = 12.5;
        save(&dna, "unit test dna").unwrap();
        let loaded = load("unit_test_dna").unwrap();
        assert_eq!(loaded, dna);
        let _ = std::fs::remove_file(library_path("unit_test_dna").unwrap());
        assert!(load("unit_test_dna").is_err());
    }
}
