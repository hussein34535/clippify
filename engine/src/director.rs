/// director.rs — Squad-R2 agentic editing brain (port of director_agent.py).
///
/// Turns a transcript summary into a DirectorPlan: ordered ClipCandidates
/// plus reasoning. LLM-driven via LlmBridge with a pure-Rust heuristic
/// fallback that segments sentences and ranks windows by hook-keyword density.
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::llm::LlmBridge;

pub const APPROVAL_THRESHOLD: f64 = 0.6;
pub const MAX_ITERATIONS: usize = 3;
pub const DEFAULT_N_CLIPS: usize = 5;
pub const DEFAULT_DURATION_SEC: f64 = 60.0;
pub const MIN_CLIP_SEC: f64 = 15.0;
pub const MAX_CLIP_SEC: f64 = 90.0;
pub const TRANSCRIPT_PROMPT_CHARS: usize = 6000;
const SEC_PER_WORD: f64 = 0.45;

pub const TOOLS: [&str; 5] = [
    "cut_at",
    "add_zoom",
    "add_sfx",
    "add_broll",
    "set_caption_theme",
];
const ZOOM_CYCLE: [&str; 4] = ["gentle", "dynamic", "punch_in", "slow"];

const HOOK_KEYWORDS: [&str; 33] = [
    "secret",
    "never",
    "always",
    "money",
    "free",
    "mistake",
    "worst",
    "best",
    "shocking",
    "truth",
    "why",
    "how",
    "stop",
    "nobody",
    "everyone",
    "warning",
    "proof",
    "insane",
    "crazy",
    "hack",
    "trick",
    "fail",
    "win",
    "love",
    "hate",
    "fear",
    "rich",
    "poor",
    "fast",
    "easy",
    "million",
    "algorithm",
    "retention",
];

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ClipCandidate {
    pub index: usize,
    pub start_sec: f64,
    pub end_sec: f64,
    #[serde(default)]
    pub hook_text: String,
    #[serde(default)]
    pub caption_theme: String,
    #[serde(default = "default_zoom")]
    pub zoom_style: String,
    #[serde(default)]
    pub sfx_queries: Vec<String>,
    #[serde(default)]
    pub broll_query: String,
    #[serde(default = "default_half")]
    pub viral_score: f64,
    #[serde(default = "default_half")]
    pub confidence: f64,
}

fn default_zoom() -> String {
    "gentle".to_string()
}

fn default_half() -> f64 {
    0.5
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct DirectorPlan {
    #[serde(default)]
    pub clips: Vec<ClipCandidate>,
    #[serde(default)]
    pub reasoning: String,
}

// ── profile / value helpers ──────────────────────────────────────────────────

fn clamp01(value: f64, default: f64) -> f64 {
    if !value.is_finite() {
        return default;
    }
    value.max(0.0).min(1.0)
}

fn round2(v: f64) -> f64 {
    (v * 100.0).round() / 100.0
}

fn round3(v: f64) -> f64 {
    (v * 1000.0).round() / 1000.0
}

fn pstr(value: &Value, key: &str) -> Option<String> {
    match value.get(key) {
        Some(Value::String(s)) => Some(s.clone()),
        Some(Value::Number(n)) => Some(n.to_string()),
        _ => None,
    }
    .filter(|s| !s.trim().is_empty())
}

fn pf64(value: &Value, keys: &[&str], default: f64) -> f64 {
    for k in keys {
        if let Some(v) = value.get(*k) {
            if let Some(f) = v.as_f64() {
                return f;
            }
            if let Some(s) = v.as_str() {
                if let Ok(f) = s.parse::<f64>() {
                    return f;
                }
            }
        }
    }
    default
}

fn jstr(data: &Value, keys: &[&str]) -> Option<String> {
    for k in keys {
        if let Some(s) = data.get(*k).and_then(Value::as_str) {
            return Some(s.to_string());
        }
    }
    None
}

fn jnum(data: &Value, keys: &[&str]) -> Option<f64> {
    for k in keys {
        if let Some(v) = data.get(*k) {
            if let Some(f) = v.as_f64() {
                return Some(f);
            }
            if let Some(s) = v.as_str() {
                if let Ok(f) = s.parse::<f64>() {
                    return Some(f);
                }
            }
        }
    }
    None
}

fn jclamp(data: &Value, keys: &[&str], default: f64) -> f64 {
    jnum(data, keys).map(|v| clamp01(v, default)).unwrap_or(default)
}

/// Tolerant JSON extraction: strips markdown fences, slices to the outermost
/// braces/brackets, then parses.
pub(crate) fn extract_json_value(raw: &str) -> Result<Value> {
    let mut text = raw.trim();
    if text.starts_with("```") {
        let inner = text.split("```").nth(1).unwrap_or(text);
        let inner = inner.strip_prefix("json").unwrap_or(inner);
        text = inner.trim();
    }
    let start = [text.find('{'), text.find('[')]
        .into_iter()
        .flatten()
        .min()
        .context("no JSON found in LLM response")?;
    let end = [text.rfind('}'), text.rfind(']')]
        .into_iter()
        .flatten()
        .max()
        .context("no JSON found in LLM response")?;
    if end < start {
        anyhow::bail!("malformed JSON payload from LLM");
    }
    serde_json::from_str(&text[start..=end]).context("invalid JSON payload")
}

fn truncate_chars(text: &str, max_chars: usize) -> String {
    text.chars().take(max_chars).collect()
}

// ── prompt building ──────────────────────────────────────────────────────────

pub fn build_prompt(
    transcript_summary: &str,
    profile: &Value,
    n_clips: usize,
    feedback: Option<&str>,
) -> String {
    let n = n_clips.clamp(1, 12);
    let duration = pf64(
        profile,
        &["clip_duration_sec", "default_duration"],
        DEFAULT_DURATION_SEC,
    )
    .clamp(5.0, 180.0);
    let theme = pstr(profile, "caption_theme").unwrap_or_else(|| "auto (match content type)".into());
    let zoom = pstr(profile, "zoom_style").unwrap_or_else(|| "gentle".into());
    let content_type = pstr(profile, "content_type").unwrap_or_else(|| "podcast".into());

    let mut parts = vec![
        "You are the Director of a short-form clipping studio.".to_string(),
        format!(
            "Content type: {content_type} | Target clips: {n} | \
             Duration per clip: ~{duration:.0}s | Caption theme: {theme} | Default zoom: {zoom}"
        ),
        format!("Available tools: {}", TOOLS.join(", ")),
        "Timestamped transcript:".to_string(),
        truncate_chars(transcript_summary, TRANSCRIPT_PROMPT_CHARS),
        "Return ONLY JSON in this exact shape:".to_string(),
        "{\"clips\": [{\"start_sec\": 0.0, \"end_sec\": 30.0, \"hook_text\": \"...\", \
         \"caption_theme\": \"...\", \"zoom_style\": \"none|gentle|dynamic|punch_in\", \
         \"sfx_queries\": [\"...\"], \"broll_query\": \"...\", \"viral_score\": 0.0-1.0, \
         \"confidence\": 0.0-1.0}], \"reasoning\": \"...\"}"
            .to_string(),
        "Rules: clips must NOT overlap; each clip 15-90s; the first 2s must open with a \
         question or a bold statement; vary zoom_style across clips; cover different \
         regions of the video."
            .to_string(),
    ];
    if let Some(fb) = feedback {
        parts.push(format!(
            "The critic rejected the previous attempt — fix these issues: {fb}"
        ));
    }
    parts.join("\n")
}

// ── LLM plan parsing ─────────────────────────────────────────────────────────

fn candidate_from_value(data: &Value, profile: &Value) -> ClipCandidate {
    let mut start = jnum(data, &["start_sec", "start"]).unwrap_or(0.0);
    let mut end = jnum(data, &["end_sec", "end"]).unwrap_or(start);
    if end < start {
        std::mem::swap(&mut start, &mut end);
    }
    let sfx: Vec<String> = match data.get("sfx_queries") {
        Some(Value::Array(a)) => a
            .iter()
            .filter_map(|s| s.as_str().map(str::to_string))
            .collect(),
        Some(Value::String(s)) => vec![s.clone()],
        _ => vec![],
    };
    ClipCandidate {
        index: 0,
        start_sec: round2(start),
        end_sec: round2(end),
        hook_text: jstr(data, &["hook_text", "hook"]).unwrap_or_default(),
        caption_theme: jstr(data, &["caption_theme"])
            .or_else(|| pstr(profile, "caption_theme"))
            .unwrap_or_default(),
        zoom_style: jstr(data, &["zoom_style"])
            .or_else(|| pstr(profile, "zoom_style"))
            .unwrap_or_else(|| "gentle".to_string()),
        sfx_queries: sfx,
        broll_query: jstr(data, &["broll_query", "broll"]).unwrap_or_default(),
        viral_score: jclamp(data, &["viral_score"], 0.5),
        confidence: jclamp(data, &["confidence"], 0.5),
    }
}

pub fn plan_from_llm(raw: &str, profile: &Value) -> Result<DirectorPlan> {
    let mut data = extract_json_value(raw)?;
    if data.is_array() {
        data = json!({ "clips": data });
    }
    let clips_raw = data
        .get("clips")
        .and_then(Value::as_array)
        .context("LLM plan JSON missing 'clips'")?;
    let mut clips: Vec<ClipCandidate> = clips_raw
        .iter()
        .filter(|c| c.is_object())
        .map(|c| candidate_from_value(c, profile))
        .collect();
    if clips.is_empty() {
        anyhow::bail!("LLM plan produced zero valid clips");
    }
    for (i, c) in clips.iter_mut().enumerate() {
        c.index = i;
    }
    let reasoning = data
        .get("reasoning")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    Ok(DirectorPlan { clips, reasoning })
}

pub fn infer_tool_calls(clips: &[ClipCandidate]) -> Vec<String> {
    let mut found = vec![false; TOOLS.len()];
    for c in clips {
        found[0] = true; // cut_at
        if !c.zoom_style.is_empty() && c.zoom_style != "none" {
            found[1] = true; // add_zoom
        }
        if !c.sfx_queries.is_empty() {
            found[2] = true; // add_sfx
        }
        if !c.broll_query.is_empty() {
            found[3] = true; // add_broll
        }
        if !c.caption_theme.is_empty() {
            found[4] = true; // set_caption_theme
        }
    }
    TOOLS
        .iter()
        .zip(found.iter())
        .filter(|(_, f)| **f)
        .map(|(t, _)| t.to_string())
        .collect()
}

// ── main entry point ─────────────────────────────────────────────────────────

pub async fn direct(
    transcript_summary: &str,
    profile: &Value,
    llm: &LlmBridge,
    n_clips: usize,
) -> Result<DirectorPlan> {
    let n_clips = n_clips.clamp(1, 12);
    if transcript_summary.trim().is_empty() {
        return Ok(DirectorPlan {
            clips: vec![],
            reasoning: "empty transcript; nothing to direct".to_string(),
        });
    }
    let prompt = build_prompt(transcript_summary, profile, n_clips, None);
    let resp = llm.ask(&prompt, 0.6, true).await?;
    match plan_from_llm(&resp.text, profile) {
        Ok(mut plan) => {
            plan.reasoning = format!(
                "{} | tools: {}",
                plan.reasoning,
                infer_tool_calls(&plan.clips).join(",")
            );
            Ok(plan)
        }
        Err(err) => {
            let mut fallback = heuristic_direct(transcript_summary, n_clips);
            fallback.reasoning = format!("{} (llm parse failed: {err})", fallback.reasoning);
            Ok(fallback)
        }
    }
}

// ── heuristic fallback (no LLM) ──────────────────────────────────────────────

fn split_sentences(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let chars: Vec<char> = line.chars().collect();
        let mut cur = String::new();
        for (i, ch) in chars.iter().enumerate() {
            cur.push(*ch);
            let terminal =
                *ch == '.' || *ch == '!' || *ch == '?';
            let boundary =
                i + 1 == chars.len() || chars[i + 1].is_whitespace();
            if terminal && boundary {
                let t = cur.trim();
                if !t.is_empty() {
                    out.push(t.to_string());
                }
                cur.clear();
            }
        }
        let t = cur.trim();
        if !t.is_empty() {
            out.push(t.to_string());
        }
    }
    out
}

struct Window {
    start: f64,
    end: f64,
    text: String,
    words: usize,
}

fn window_metrics(win: &Window) -> (f64, usize, f64) {
    let low = win.text.to_lowercase();
    let mut hits: usize = HOOK_KEYWORDS
        .iter()
        .filter(|k| low.contains(**k))
        .count();
    hits += low.matches('?').count();
    let dur = (win.end - win.start).max(0.1);
    let density = ((win.words as f64 / dur) / 2.5).min(1.0);
    let kw_score = (hits as f64 / 4.0).min(1.0);
    (0.65 * kw_score + 0.35 * density, hits, density)
}

fn extract_hook(text: &str) -> String {
    let mut phrase: Vec<&str> = Vec::new();
    for word in text.split_whitespace() {
        phrase.push(word);
        if (word.ends_with('?') || word.ends_with('!')) && phrase.len() >= 3 {
            break;
        }
        if phrase.len() >= 8 {
            break;
        }
    }
    phrase.join(" ")
}

pub fn heuristic_direct(transcript_summary: &str, n_clips: usize) -> DirectorPlan {
    let n_clips = n_clips.clamp(1, 12);
    let sentences = split_sentences(transcript_summary);
    if sentences.is_empty() {
        return DirectorPlan {
            clips: vec![],
            reasoning: "empty transcript; nothing to direct".to_string(),
        };
    }

    // Synthetic timeline: ~0.45s per spoken word.
    let mut cursor = 0.0f64;
    let timed: Vec<(String, f64, f64)> = sentences
        .into_iter()
        .map(|s| {
            let words = s.split_whitespace().count() as f64;
            let dur = (words * SEC_PER_WORD).max(0.6);
            let start = cursor;
            cursor += dur;
            (s, start, cursor)
        })
        .collect();

    // Group sentences into windows near the target duration.
    let mut windows: Vec<Window> = Vec::new();
    let mut buf_start = 0.0f64;
    let mut buf_end = 0.0f64;
    let mut buf_text = String::new();
    let mut buf_words = 0usize;
    let mut open = false;
    for (text, st, en) in timed {
        if !open {
            buf_start = st;
            open = true;
        }
        if !buf_text.is_empty() {
            buf_text.push(' ');
        }
        buf_text.push_str(&text);
        buf_words += text.split_whitespace().count();
        buf_end = en;
        if buf_end - buf_start >= DEFAULT_DURATION_SEC {
            windows.push(Window {
                start: buf_start,
                end: buf_end,
                text: std::mem::take(&mut buf_text),
                words: buf_words,
            });
            buf_words = 0;
            open = false;
        }
    }
    if open && buf_words > 0 {
        windows.push(Window {
            start: buf_start,
            end: buf_end,
            text: buf_text,
            words: buf_words,
        });
    }

    let metrics: Vec<(f64, usize, f64)> =
        windows.iter().map(window_metrics).collect();
    let mut order: Vec<usize> = (0..windows.len()).collect();
    order.sort_by(|&a, &b| {
        metrics[b]
            .0
            .partial_cmp(&metrics[a].0)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(windows[a]
                .start
                .partial_cmp(&windows[b].start)
                .unwrap_or(std::cmp::Ordering::Equal))
    });

    let mut taken: Vec<usize> = Vec::new();
    for &idx in &order {
        let (s, e) = (windows[idx].start, windows[idx].end);
        if taken.iter().any(|&j| windows[j].start < e && s < windows[j].end) {
            continue;
        }
        taken.push(idx);
        if taken.len() >= n_clips {
            break;
        }
    }
    taken.sort_by(|&a, &b| {
        windows[a]
            .start
            .partial_cmp(&windows[b].start)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let clips: Vec<ClipCandidate> = taken
        .iter()
        .enumerate()
        .map(|(pos, &idx)| {
            let (score, hits, density) = metrics[idx];
            let win = &windows[idx];
            let mut confidence = 0.5f64;
            if hits > 0 {
                confidence += 0.15;
            }
            if hits >= 3 {
                confidence += 0.15;
            }
            if density > 0.5 {
                confidence += 0.1;
            }
            ClipCandidate {
                index: pos,
                start_sec: round2(win.start),
                end_sec: round2(win.end.min(win.start + MAX_CLIP_SEC)),
                hook_text: extract_hook(&win.text),
                caption_theme: "TikTok Yellow".to_string(),
                zoom_style: ZOOM_CYCLE[pos % ZOOM_CYCLE.len()].to_string(),
                sfx_queries: if hits >= 2 {
                    vec!["whoosh".to_string()]
                } else {
                    vec![]
                },
                broll_query: String::new(),
                viral_score: round3(score.min(1.0)),
                confidence: round2(confidence.min(0.9)),
            }
        })
        .collect();

    let reasoning = format!(
        "heuristic fallback: {} sentence windows scored by hook-keyword density; \
         selected top {}",
        windows.len(),
        clips.len()
    );
    DirectorPlan { clips, reasoning }
}
