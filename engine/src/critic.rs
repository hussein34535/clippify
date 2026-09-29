/// critic.rs — Squad-R2 plan reviewer (port of critic.py).
///
/// Scores a DirectorPlan the way a top short-form editor would, using five
/// structural checks (each 0-1, averaged into the total): hook_strength,
/// pacing (15-90s), zoom variety, overlap and timeline coverage. With an
/// LlmBridge available a subjective editor score is blended 50/50; any LLM
/// failure is tolerated and the structural verdict stands.
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::director::{extract_json_value, ClipCandidate, DirectorPlan};
use crate::llm::LlmBridge;

pub const MIN_CLIP_SEC: f64 = 15.0;
pub const MAX_CLIP_SEC: f64 = 90.0;
pub const HOOK_WINDOW_SEC: f64 = 2.0;

const BOLD_MARKERS: [&str; 19] = [
    "never",
    "always",
    "stop",
    "secret",
    "nobody",
    "everyone",
    "truth",
    "million",
    "%",
    "percent",
    "most",
    "worst",
    "best",
    "proven",
    "shocking",
    "warning",
    "mistake",
    "hack",
    "proof",
];

const QUESTION_WORDS: [&str; 12] = [
    "what",
    "why",
    "how",
    "who",
    "when",
    "which",
    "should",
    "could",
    "would",
    "is it",
    "do you",
    "did you",
];

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct CriticResult {
    pub score: f64,
    pub feedback: String,
    pub issues: Vec<String>,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct SubScores {
    pub hook_strength: f64,
    pub pacing: f64,
    pub variety: f64,
    pub overlap: f64,
    pub coverage: f64,
}

impl SubScores {
    pub fn average(&self) -> f64 {
        round3(
            (self.hook_strength
                + self.pacing
                + self.variety
                + self.overlap
                + self.coverage)
                / 5.0,
        )
    }
}

fn round3(v: f64) -> f64 {
    (v * 1000.0).round() / 1000.0
}

fn clamp01(v: f64, default: f64) -> f64 {
    if !v.is_finite() {
        return default;
    }
    v.max(0.0).min(1.0)
}

fn clip_seconds(c: &ClipCandidate) -> f64 {
    (c.end_sec - c.start_sec).max(0.0)
}

pub fn is_strong_hook(text: &str) -> bool {
    let low = text.trim().to_lowercase();
    if low.is_empty() {
        return false;
    }
    if text.contains('?') {
        return true;
    }
    if BOLD_MARKERS.iter().any(|m| low.contains(m)) {
        return true;
    }
    QUESTION_WORDS.iter().any(|qw| low.starts_with(qw))
}

fn dedupe(items: Vec<String>) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    items
        .into_iter()
        .filter(|i| !i.is_empty() && seen.insert(i.clone()))
        .collect()
}

// ── pure-Rust review ─────────────────────────────────────────────────────────

pub fn sub_scores(plan: &DirectorPlan) -> SubScores {
    let clips = &plan.clips;
    if clips.is_empty() {
        return SubScores::default();
    }
    let n = clips.len() as f64;

    // pacing
    let bad_pace = clips
        .iter()
        .filter(|c| !(MIN_CLIP_SEC..=MAX_CLIP_SEC).contains(&clip_seconds(c)))
        .count();
    let pacing = 1.0 - bad_pace as f64 / n;

    // overlap
    let mut ordered: Vec<&ClipCandidate> = clips.iter().collect();
    ordered.sort_by(|a, b| {
        a.start_sec
            .partial_cmp(&b.start_sec)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    let mut overlaps = 0usize;
    for pair in ordered.windows(2) {
        if pair[1].start_sec < pair[0].end_sec - 1e-6 {
            overlaps += 1;
        }
    }
    let overlap_score = if overlaps == 0 {
        1.0
    } else {
        (1.0 - overlaps as f64 / (n - 1.0).max(1.0)).max(0.0)
    };

    // variety
    let styles: std::collections::HashSet<&str> = clips
        .iter()
        .map(|c| if c.zoom_style.is_empty() { "none" } else { c.zoom_style.as_str() })
        .collect();
    let variety = (styles.len() as f64 / n).min(1.0);

    // hook strength (hook_text stands in for the first ~HOOK_WINDOW_SEC)
    let strong = clips.iter().filter(|c| is_strong_hook(&c.hook_text)).count();
    let hook_strength = strong as f64 / n;

    // coverage
    let video_end = clips.iter().map(|c| c.end_sec).fold(0.0f64, f64::max);
    let total_covered: f64 = clips.iter().map(clip_seconds).sum();
    let span = if video_end > 0.0 {
        (total_covered / video_end).min(1.0)
    } else {
        1.0
    };
    let quarter = (video_end / 4.0).max(1e-6);
    let mut touched: std::collections::HashSet<u8> = std::collections::HashSet::new();
    for c in clips {
        touched.insert(((c.start_sec / quarter) as u8).min(3));
        touched.insert((((c.end_sec - 1e-3) / quarter) as u8).min(3));
    }
    let spread = touched.len() as f64 / 4.0;
    let coverage = 0.7 * span + 0.3 * spread;

    SubScores {
        hook_strength,
        pacing,
        variety,
        overlap: overlap_score,
        coverage,
    }
}

pub fn heuristic_review(plan: &DirectorPlan) -> CriticResult {
    let clips = &plan.clips;
    if clips.is_empty() {
        return CriticResult {
            score: 0.0,
            feedback: "plan has no clips to review".to_string(),
            issues: vec!["no_clips".to_string()],
        };
    }

    let n = clips.len();
    let mut issues: Vec<String> = Vec::new();

    for c in clips {
        let dur = clip_seconds(c);
        if !(MIN_CLIP_SEC..=MAX_CLIP_SEC).contains(&dur) {
            issues.push(format!(
                "pacing:{:.0}-{:.0}s ({:.0}s outside {:.0}-{:.0}s)",
                c.start_sec, c.end_sec, dur, MIN_CLIP_SEC, MAX_CLIP_SEC
            ));
        }
    }

    let mut ordered: Vec<&ClipCandidate> = clips.iter().collect();
    ordered.sort_by(|a, b| {
        a.start_sec
            .partial_cmp(&b.start_sec)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    for i in 0..ordered.len().saturating_sub(1) {
        if ordered[i + 1].start_sec < ordered[i].end_sec - 1e-6 {
            issues.push(format!("overlap:clip{}/clip{}", i, i + 1));
        }
    }

    let styles: std::collections::HashSet<&str> = clips
        .iter()
        .map(|c| if c.zoom_style.is_empty() { "none" } else { c.zoom_style.as_str() })
        .collect();
    if styles.len() < 2 && n > 1 {
        let first = *styles.iter().min().unwrap_or(&"none");
        issues.push(format!(
            "variety:single zoom style '{first}' across {n} clips"
        ));
    }

    for (idx, c) in clips.iter().enumerate() {
        if !is_strong_hook(&c.hook_text) {
            issues.push(format!(
                "weak_hook:clip{idx} first {HOOK_WINDOW_SEC:.0}s lack a question/bold statement"
            ));
        }
    }

    let subs = sub_scores(plan);
    let total_covered: f64 = clips.iter().map(clip_seconds).sum();
    let video_end = clips.iter().map(|c| c.end_sec).fold(0.0f64, f64::max);
    if subs.coverage < 0.5 {
        issues.push(format!(
            "coverage:only {total_covered:.0}s of {video_end:.0}s video covered"
        ));
    }

    let score = subs.average();
    let feedback = if issues.is_empty() {
        "all structural checks passed".to_string()
    } else {
        dedupe(issues.clone()).join(" | ")
    };
    CriticResult {
        score,
        feedback,
        issues: dedupe(issues),
    }
}

// ── LLM-assisted review ──────────────────────────────────────────────────────

fn build_editor_prompt(clips: &[ClipCandidate]) -> String {
    let payload: Vec<Value> = clips
        .iter()
        .map(|c| {
            json!({
                "start_sec": c.start_sec,
                "end_sec": c.end_sec,
                "duration_sec": round3(clip_seconds(c)),
                "hook_text": c.hook_text,
                "zoom_style": c.zoom_style,
            })
        })
        .collect();
    format!(
        "You are a senior short-form editor reviewing a cutting plan.\n\
         Plan: {}\n\
         Would a top editor approve this plan? Reply ONLY JSON: \
         {{\"approve\": true|false, \"score\": 0.0-1.0, \"feedback\": \"...\"}}",
        serde_json::to_string(&payload).unwrap_or_else(|_| "[]".to_string())
    )
}

pub async fn review(plan: &DirectorPlan, llm: &LlmBridge) -> CriticResult {
    let base = heuristic_review(plan);
    if plan.clips.is_empty() {
        return base;
    }

    let prompt = build_editor_prompt(&plan.clips);
    let Ok(resp) = llm.ask(&prompt, 0.3, true).await else {
        return base; // subjective hop is best-effort; structural verdict stands
    };
    let Ok(data) = extract_json_value(&resp.text) else {
        return base;
    };
    if !data.is_object() || data.get("score").is_none() {
        return base;
    }

    let subjective = clamp01(
        data.get("score").and_then(Value::as_f64).unwrap_or(base.score),
        base.score,
    );
    let score = round3((base.score + subjective) / 2.0);
    let editor_fb = data
        .get("feedback")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string();
    let feedback = if editor_fb.is_empty() {
        base.feedback
    } else {
        format!("{editor_fb} | {}", base.feedback)
    };
    CriticResult {
        score,
        feedback,
        issues: base.issues,
    }
}
