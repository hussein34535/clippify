use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::director::extract_json_value;
use crate::llm::LlmBridge;

pub const AB_STORE_PATH: &str = "ab_tests.json";
pub const HOOK_MAX_CHARS: usize = 90;
const SEGMENT_CHARS: usize = 900;
const MAX_VARIANTS: usize = 8;
const STYLES: [&str; 4] = ["question", "shock", "story", "statistic"];
const POWER_WORDS: [&str; 16] = [
    "secret",
    "never",
    "stop",
    "why",
    "how",
    "insane",
    "truth",
    "free",
    "mistake",
    "warning",
    "سر",
    "لماذا",
    "لا تفعل",
    "خطير",
    "صادم",
    "مجانا",
];

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct HookVariant {
    pub id: String,
    pub text: String,
    pub style: String,
    pub predicted_score: f64,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct ABMetrics {
    pub views: u64,
    pub likes: u64,
    pub shares: u64,
    pub retention_pct: f64,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct ABTest {
    pub variant_a: HookVariant,
    pub variant_b: HookVariant,
    pub winner: Option<String>,
    pub metrics_a: Option<ABMetrics>,
    pub metrics_b: Option<ABMetrics>,
}

impl ABTest {
    pub fn resolve_winner(&mut self) -> Option<String> {
        match (&self.metrics_a, &self.metrics_b) {
            (Some(a), Some(b)) => {
                let w = declare_winner(a, b);
                self.winner = Some(w.clone());
                Some(w)
            }
            _ => None,
        }
    }
}

pub async fn generate_variants(
    transcript_segment: &str,
    count: usize,
    llm: &LlmBridge,
) -> Result<Vec<HookVariant>> {
    let count = count.clamp(1, MAX_VARIANTS);
    let seg: String = transcript_segment.chars().take(SEGMENT_CHARS).collect();
    let styles_list: Vec<&str> = STYLES.iter().cycle().take(count).copied().collect();
    let prompt = build_hook_prompt(&seg, count, HOOK_MAX_CHARS, &styles_list);

    let mut variants: Vec<HookVariant> = Vec::new();
    if let Ok(resp) = llm.ask(&prompt, 0.7, true).await {
        if let Ok(v) = extract_json_value(&resp.text) {
            collect_llm_hooks(&v, &mut variants);
        }
    }
    while variants.len() < count {
        variants.push(fallback_variant(&seg, variants.len()));
    }
    variants.truncate(count);
    Ok(variants)
}

fn build_hook_prompt(seg: &str, count: usize, max_chars: usize, styles_list: &[&str]) -> String {
    let schema = r#"{"hooks": [{"style": "question", "text": "..."}]}"#;
    let parts = vec![
        "You are a viral hook writer for short-form vertical video.".to_string(),
        format!("Transcript segment:\n\"\"\"{seg}\"\"\""),
        format!(
            "Write {count} different scroll-stopping hook lines (each max {max_chars} chars), \
             one per style, strictly in this order: {}. Match the language of the segment.",
            styles_list.join(", ")
        ),
        "Return ONLY JSON exactly in this shape:".to_string(),
        schema.to_string(),
    ];
    parts.join("\n")
}

fn collect_llm_hooks(v: &Value, out: &mut Vec<HookVariant>) {
    let hooks_val = v.get("hooks").cloned().unwrap_or_else(|| v.clone());
    let Some(arr) = hooks_val.as_array() else {
        return;
    };
    for (i, item) in arr.iter().enumerate() {
        let text = item
            .get("text")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim()
            .to_string();
        if text.is_empty() {
            continue;
        }
        let style = item
            .get("style")
            .and_then(Value::as_str)
            .map(|s| s.trim().to_lowercase())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| STYLES[i % STYLES.len()].to_string());
        out.push(HookVariant {
            id: format!("h{}", out.len() + 1),
            text: truncate_chars(&text, 160),
            style,
            predicted_score: score_hook(&text),
        });
    }
}

fn fallback_variant(segment: &str, slot: usize) -> HookVariant {
    let style = STYLES[slot % STYLES.len()];
    let key = key_phrase(segment, 7);
    let text = match style {
        "question" => {
            if slot % 8 < 4 {
                format!("Why does {key} actually work?")
            } else {
                format!("What if everything you know about {key} is wrong?")
            }
        }
        "shock" => {
            if slot % 8 < 4 {
                format!("{key} — nobody warns you about this")
            } else {
                format!("Stop scrolling: {key} changes everything")
            }
        }
        "story" => {
            if slot % 8 < 4 {
                format!("I tested {key} for 30 days")
            } else {
                format!("This {key} story sounds fake but is real")
            }
        }
        _ => {
            if slot % 8 < 4 {
                format!("97% get {key} wrong")
            } else {
                format!("{key} in 3 numbers")
            }
        }
    };
    HookVariant {
        id: format!("h{}", slot + 1),
        text: truncate_chars(&text, 140),
        style: style.to_string(),
        predicted_score: score_hook(&text),
    }
}

fn key_phrase(segment: &str, max_words: usize) -> String {
    let phrase: String = segment
        .split_whitespace()
        .take(max_words)
        .collect::<Vec<_>>()
        .join(" ");
    let trimmed = phrase
        .trim_end_matches(|c: char| matches!(c, '.' | ',' | '!' | '؟' | '?' | '،'))
        .trim()
        .to_lowercase();
    if trimmed.is_empty() {
        "this".to_string()
    } else {
        trimmed
    }
}

pub fn score_hook(text: &str) -> f64 {
    let low = text.to_lowercase();
    let mut s = 0.35f64;
    let len = text.chars().count();
    if (20..=60).contains(&len) {
        s += 0.15;
    } else if len <= HOOK_MAX_CHARS {
        s += 0.08;
    }
    if low.contains('?') || low.contains('؟') {
        s += 0.10;
    }
    let starts_digit = text.trim_start().chars().next().is_some_and(|c| c.is_ascii_digit());
    if low.contains('%') || starts_digit {
        s += 0.10;
    }
    if POWER_WORDS.iter().any(|w| low.contains(w)) {
        s += 0.15;
    }
    if text.trim_end().ends_with('!') {
        s += 0.05;
    }
    round3(s.min(0.95))
}

pub fn declare_winner(a: &ABMetrics, b: &ABMetrics) -> String {
    let score = |m: &ABMetrics| -> f64 {
        let views = m.views.max(1) as f64;
        let engagement = (m.likes as f64 + 2.0 * m.shares as f64) / views;
        engagement * 600.0 + m.retention_pct.clamp(0.0, 100.0) * 0.4
    };
    let sa = score(a);
    let sb = score(b);
    if (sa - sb).abs() < 1e-9 {
        "tie".to_string()
    } else if sa > sb {
        "a".to_string()
    } else {
        "b".to_string()
    }
}

pub fn save_ab_test(test: &ABTest) -> Result<()> {
    let mut all = load_ab_tests();
    all.retain(|t| {
        !(t.variant_a.id == test.variant_a.id && t.variant_b.id == test.variant_b.id)
    });
    all.push(test.clone());
    let data = serde_json::to_string_pretty(&all).context("serializing ab tests")?;
    std::fs::write(AB_STORE_PATH, data).with_context(|| format!("writing {AB_STORE_PATH}"))
}

pub fn load_ab_tests() -> Vec<ABTest> {
    std::fs::read_to_string(AB_STORE_PATH)
        .ok()
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default()
}

fn truncate_chars(text: &str, max_chars: usize) -> String {
    text.chars().take(max_chars).collect()
}

fn round3(v: f64) -> f64 {
    (v * 1000.0).round() / 1000.0
}
