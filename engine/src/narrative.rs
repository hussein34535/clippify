use crate::llm::LlmBridge;
use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const PAUSE_BEAT_SEC: f64 = 2.0;
pub const LONG_WORD_SEC: f64 = 0.6;
pub const LONG_WORD_CHARS: usize = 10;
pub const MAX_KEY_MOMENTS: usize = 5;
pub const MAX_PROMPT_WORDS: usize = 600;
pub const TENSION_SAMPLES: usize = 24;

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct StoryBeat {
    pub label: String,
    pub start: f64,
    pub end: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct Joke {
    pub setup_text: String,
    pub punchline_text: String,
    pub punchline_start: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct TensionPoint {
    pub t: f64,
    pub score: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct KeyMoment {
    pub text: String,
    pub start: f64,
    pub score: f64,
    #[serde(default)]
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct Narrative {
    #[serde(default)]
    pub story_beats: Vec<StoryBeat>,
    #[serde(rename = "joke_detection", default)]
    pub jokes: Vec<Joke>,
    #[serde(default)]
    pub tension_curve: Vec<TensionPoint>,
    #[serde(default)]
    pub key_moments: Vec<KeyMoment>,
}

struct Word {
    text: String,
    start: f64,
    end: f64,
}

fn clamp01(x: f64) -> f64 {
    x.max(0.0).min(1.0)
}

fn round3(x: f64) -> f64 {
    (x * 1000.0).round() / 1000.0
}

fn norm_words(transcript_words: &[(f64, f64, String)]) -> Vec<Word> {
    let mut out: Vec<Word> = transcript_words
        .iter()
        .filter_map(|&(start, end, ref text)| {
            let text = text.trim();
            if text.is_empty() {
                return None;
            }
            let start = start.max(0.0);
            Some(Word {
                text: text.to_string(),
                start,
                end: end.max(start),
            })
        })
        .collect();
    out.sort_by(|a, b| a.start.partial_cmp(&b.start).unwrap_or(std::cmp::Ordering::Equal));
    out
}

fn build_prompt(words: &[Word]) -> String {
    let transcript_block: String = words
        .iter()
        .take(MAX_PROMPT_WORDS)
        .map(|w| format!("[{:.2}-{:.2}] {}", w.start, w.end, w.text))
        .collect::<Vec<_>>()
        .join("\n");
    format!(
        "You are a video narrative analyst. Below is a word-level transcript \
(seconds). Analyze its storytelling structure and respond with ONLY valid \
JSON (no markdown, no commentary) shaped exactly like this:\n\
{{\n\
  \"story_beats\": [{{\"label\": \"...\", \"start\": 0.0, \"end\": 0.0}}],\n\
  \"joke_detection\": [{{\"setup_text\": \"...\", \"punchline_text\": \"...\", \"punchline_start\": 0.0}}],\n\
  \"tension_curve\": [{{\"t\": 0.0, \"score\": 0.0}}],\n\
  \"key_moments\": [{{\"text\": \"...\", \"start\": 0.0, \"score\": 0.0, \"reason\": \"...\"}}]\n\
}}\n\
Rules: tension scores are floats in [0,1]; key_moments are the top 5 most \
clip-worthy moments sorted by score; story_beats cover the whole timeline \
in order.\n\nTRANSCRIPT:\n{transcript_block}"
    )
}

fn build_text_prompt(transcript: &str) -> String {
    let mut words: Vec<Word> = transcript
        .split_whitespace()
        .take(MAX_PROMPT_WORDS)
        .map(|text| Word {
            text: text.to_string(),
            start: 0.0,
            end: 0.0,
        })
        .collect();
    for (i, w) in words.iter_mut().enumerate() {
        w.start = i as f64;
        w.end = i as f64;
    }
    build_prompt(&words)
}

fn extract_json(text: &str) -> Result<Value> {
    let mut t = text.trim().to_string();
    if t.starts_with("```") {
        let parts: Vec<&str> = t.split("```").collect();
        if parts.len() > 1 {
            t = parts[1].trim_start().to_string();
            if t.starts_with("json") {
                t = t[4..].to_string();
            }
        }
    }
    let open = [t.find('{'), t.find('[')].into_iter().flatten().min();
    let Some(start) = open else {
        bail!("no JSON found in LLM response");
    };
    let end = t.rfind('}').max(t.rfind(']'));
    let Some(end) = end else {
        bail!("no JSON found in LLM response");
    };
    if end < start {
        bail!("malformed JSON in LLM response");
    }
    Ok(serde_json::from_str(&t[start..=end])?)
}

fn val_f64(v: Option<&Value>) -> Option<f64> {
    match v? {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.trim().parse::<f64>().ok(),
        _ => None,
    }
}

fn val_str(v: Option<&Value>) -> String {
    v.and_then(Value::as_str).unwrap_or_default().trim().to_string()
}

fn normalize(data: Value) -> Result<Narrative> {
    let obj = match data {
        Value::Object(map) => Value::Object(map),
        _ => bail!("LLM returned non-object JSON"),
    };

    let mut narrative = Narrative::default();

    let mut beats: Vec<StoryBeat> = obj
        .get("story_beats")
        .and_then(Value::as_array)
        .map(|arr| arr.iter().filter_map(|b| {
            let start = val_f64(b.get("start"))?;
            let end = val_f64(b.get("end"))?;
            let label = val_str(b.get("label"));
            Some(StoryBeat {
                label: if label.is_empty() { "beat".to_string() } else { label },
                start,
                end: start.max(end),
            })
        }).collect())
        .unwrap_or_default();
    beats.sort_by(|a, b| a.start.partial_cmp(&b.start).unwrap_or(std::cmp::Ordering::Equal));
    narrative.story_beats = beats;

    narrative.jokes = obj
        .get("joke_detection")
        .and_then(Value::as_array)
        .map(|arr| arr.iter().filter_map(|j| {
            let punchline_text = val_str(j.get("punchline_text"));
            if punchline_text.is_empty() {
                return None;
            }
            Some(Joke {
                setup_text: val_str(j.get("setup_text")),
                punchline_text,
                punchline_start: val_f64(j.get("punchline_start")).unwrap_or(0.0),
            })
        }).collect())
        .unwrap_or_default();

    let mut curve: Vec<TensionPoint> = obj
        .get("tension_curve")
        .and_then(Value::as_array)
        .map(|arr| arr.iter().filter_map(|p| {
            Some(TensionPoint {
                t: val_f64(p.get("t"))?,
                score: clamp01(val_f64(p.get("score"))?),
            })
        }).collect())
        .unwrap_or_default();
    curve.sort_by(|a, b| a.t.partial_cmp(&b.t).unwrap_or(std::cmp::Ordering::Equal));
    narrative.tension_curve = curve;

    let mut moments: Vec<KeyMoment> = obj
        .get("key_moments")
        .and_then(Value::as_array)
        .map(|arr| arr.iter().filter_map(|m| {
            let text = val_str(m.get("text"));
            if text.is_empty() {
                return None;
            }
            Some(KeyMoment {
                text,
                start: val_f64(m.get("start"))?,
                score: clamp01(val_f64(m.get("score")).unwrap_or(0.0)),
                reason: val_str(m.get("reason")),
            })
        }).collect())
        .unwrap_or_default();
    moments.sort_by(|a, b| {
        b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal)
            .then(a.start.partial_cmp(&b.start).unwrap_or(std::cmp::Ordering::Equal))
    });
    moments.truncate(MAX_KEY_MOMENTS);
    narrative.key_moments = moments;

    Ok(narrative)
}

async fn analyze(prompt: &str, llm: &LlmBridge) -> Result<Narrative> {
    let raw = llm.ask(prompt, 0.2, true).await?.text;
    normalize(extract_json(&raw)?)
}

pub async fn parse_narrative(transcript: &str, llm: &LlmBridge) -> Result<Narrative> {
    analyze(&build_text_prompt(transcript), llm).await
}

pub async fn parse_narrative_words(
    transcript_words: &[(f64, f64, String)],
    llm: &LlmBridge,
) -> Result<Narrative> {
    analyze(&build_prompt(&norm_words(transcript_words)), llm).await
}

pub fn heuristic_narrative(transcript_words: &[(f64, f64, String)]) -> Narrative {
    let words = norm_words(transcript_words);
    if words.is_empty() {
        return Narrative::default();
    }

    let mut story_beats = Vec::new();
    let mut seg_start_idx = 0usize;
    for i in 1..words.len() {
        if words[i].start - words[i - 1].end > PAUSE_BEAT_SEC {
            push_beat(&words, seg_start_idx, i - 1, &mut story_beats);
            seg_start_idx = i;
        }
    }
    push_beat(&words, seg_start_idx, words.len() - 1, &mut story_beats);

    let duration = words.iter().map(|w| w.end).fold(f64::MIN, f64::max);
    let mut scored: Vec<KeyMoment> = Vec::new();
    for w in &words {
        let span = w.end - w.start;
        let (reason, score) = if span >= LONG_WORD_SEC {
            ("long_word_duration", clamp01(span / 2.0))
        } else if w.text.chars().count() >= LONG_WORD_CHARS {
            ("long_word", clamp01(w.text.chars().count() as f64 / 20.0))
        } else {
            continue;
        };
        scored.push(KeyMoment {
            text: w.text.clone(),
            start: round3(w.start),
            score: round3(score.max(0.3)),
            reason: reason.to_string(),
        });
    }
    scored.sort_by(|a, b| {
        b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal)
            .then(a.start.partial_cmp(&b.start).unwrap_or(std::cmp::Ordering::Equal))
    });
    scored.truncate(MAX_KEY_MOMENTS);

    let total = if duration > 0.0 { duration } else { 1.0 };
    let step = total / TENSION_SAMPLES as f64;
    let mut tension_curve = Vec::with_capacity(TENSION_SAMPLES);
    for k in 0..TENSION_SAMPLES {
        let lo = k as f64 * step;
        let hi = (k + 1) as f64 * step;
        let count = words.iter().filter(|w| lo <= w.start && w.start < hi).count();
        let density = count as f64 / ((hi - lo) * 3.0).max(1e-6);
        let emphasis = scored.iter().filter(|m| lo <= m.start && m.start < hi).count();
        let score = clamp01(density * 0.7 + emphasis as f64 * 0.15);
        tension_curve.push(TensionPoint {
            t: round3(lo),
            score: round3(score),
        });
    }

    Narrative {
        story_beats,
        jokes: Vec::new(),
        tension_curve,
        key_moments: scored,
    }
}

fn push_beat(words: &[Word], a: usize, b: usize, out: &mut Vec<StoryBeat>) {
    let label: String = words[a..=b]
        .iter()
        .take(5)
        .map(|w| w.text.as_str())
        .collect::<Vec<_>>()
        .join(" ");
    out.push(StoryBeat {
        label,
        start: round3(words[a].start),
        end: round3(words[b].end),
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn word(start: f64, end: f64, text: &str) -> (f64, f64, String) {
        (start, end, text.to_string())
    }

    #[test]
    fn empty_input_gives_empty_narrative() {
        let n = heuristic_narrative(&[]);
        assert!(n.story_beats.is_empty());
        assert!(n.jokes.is_empty());
        assert!(n.tension_curve.is_empty());
        assert!(n.key_moments.is_empty());
    }

    #[test]
    fn pauses_split_story_beats() {
        let words = vec![
            word(0.0, 1.0, "hello".into()),
            word(1.2, 2.0, "world".into()),
            word(5.0, 6.0, "after".into()),
        ];
        let n = heuristic_narrative(&words);
        assert_eq!(n.story_beats.len(), 2);
        assert_eq!(n.story_beats[0].label, "hello world");
        assert_eq!(n.story_beats[1].label, "after");
        assert_eq!(n.story_beats[1].start, 5.0);
    }

    #[test]
    fn long_words_become_key_moments() {
        let words = vec![
            word(0.0, 1.4, "extraordinarily".into()),
            word(2.0, 2.3, "incomprehensible".into()),
            word(4.0, 4.3, "hi".into()),
        ];
        let n = heuristic_narrative(&words);
        assert_eq!(n.key_moments.len(), 2);
        assert_eq!(n.key_moments[0].reason, "long_word");
        assert!(n.key_moments[1].score >= 0.3);
        assert_eq!(n.key_moments[1].reason, "long_word_duration");
    }

    #[test]
    fn tension_curve_has_fixed_samples() {
        let words: Vec<(f64, f64, String)> =
            (0..100).map(|i| word(i as f64 * 0.3, i as f64 * 0.3 + 0.25, "w".into())).collect();
        let n = heuristic_narrative(&words);
        assert_eq!(n.tension_curve.len(), TENSION_SAMPLES);
        assert!(n.tension_curve.iter().all(|p| p.score >= 0.0 && p.score <= 1.0));
    }

    #[test]
    fn extract_json_handles_fences_and_prose() {
        let v = extract_json("sure! ```json\n{\"a\": 1}\n``` hope that helps").unwrap();
        assert_eq!(v["a"], 1);
        assert!(extract_json("no json here at all").is_err());
    }

    #[test]
    fn normalize_drops_invalid_entries_and_sorts() {
        let data: Value = serde_json::json!({
            "story_beats": [
                {"label": "late", "start": "8", "end": 9},
                {"label": "", "start": 0.0, "end": 2.0},
                {"bad": true}
            ],
            "joke_detection": [
                {"setup_text": "s", "punchline_text": "p"},
                {"setup_text": "s"}
            ],
            "tension_curve": [{"t": 5, "score": 4.0}, {"t": 1, "score": 0.2}],
            "key_moments": [
                {"text": "low", "start": 10, "score": 0.1, "reason": "r"},
                {"text": "high", "start": 20, "score": 0.9, "reason": "r"}
            ]
        });
        let n = normalize(data).unwrap();
        assert_eq!(n.story_beats.len(), 2);
        assert_eq!(n.story_beats[0].label, "beat");
        assert_eq!(n.story_beats[1].start, 8.0);
        assert_eq!(n.jokes.len(), 1);
        assert_eq!(n.jokes[0].punchline_start, 0.0);
        assert_eq!(n.tension_curve.len(), 2);
        assert_eq!(n.tension_curve[0].t, 1.0);
        assert_eq!(n.tension_curve[1].score, 1.0);
        assert_eq!(n.key_moments[0].text, "high");
        let serialized = serde_json::to_value(&n).unwrap();
        assert!(serialized.get("joke_detection").is_some());
    }
}
