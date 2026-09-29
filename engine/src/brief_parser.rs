use anyhow::{Context, Result};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::director::extract_json_value;
use crate::llm::LlmBridge;

pub const MAX_CLIPS: usize = 12;
pub const MIN_DURATION_SEC: f64 = 5.0;
pub const MAX_DURATION_SEC: f64 = 180.0;
pub const BRIEF_PROMPT_CHARS: usize = 3000;
pub const DEFAULT_N_CLIPS: usize = 5;
pub const DEFAULT_CLIP_DURATION_SEC: f64 = 60.0;

const NUM_CLIPS_RE: &str =
    r"(?i)(\d{1,2})\s*(?:clips?|videos?|reels?|shorts?|مقاطع|فيديوهات?|قطع)";
const MAKE_NUM_RE: &str =
    r"(?i)(?:make|create|give|need|want|اعمل|اصنع|أريد|اريد|هات)\s+(\d{1,2})";
const DUR_SEC_RE: &str = r"(?i)(\d{1,3})\s*(?:-\s*)?(?:seconds?|secs?|sec|ثانية|ثواني|ثوان)";
const DUR_MIN_RE: &str = r"(?i)(\d{1,2})\s*(?:minutes?|mins?|min|دقيقة|دقائق)";
const HASHTAG_RE: &str = r"#([\p{L}\p{N}_]{2,30})";
const KEYWORDS_LINE_RE: &str = r"(?i)keywords?\s*[:：]\s*([^\n]{2,200})";
const CTA_QUOTED_RE: &str =
    r#"(?i)(?:c\.?t\.?a\.?|call\s+to\s+action)\s*[:：]\s*["“]([^"”\n]{2,120})["”]"#;
const CTA_PLAIN_RE: &str =
    r"(?i)(?:c\.?t\.?a\.?|call\s+to\s+action|الدعوة|دعوة)\s*[:：\-]\s*([^\n]{3,120})";

const CONTENT_HINTS: [(&str, &str); 21] = [
    ("podcast", "podcast"),
    ("بودكاست", "podcast"),
    ("interview", "interview"),
    ("مقابلة", "interview"),
    ("vlog", "vlog"),
    ("فلوق", "vlog"),
    ("tutorial", "tutorial"),
    ("شرح", "tutorial"),
    ("تعليم", "tutorial"),
    ("review", "review"),
    ("مراجعة", "review"),
    ("news", "news"),
    ("أخبار", "news"),
    ("اخبار", "news"),
    ("sport", "sports"),
    ("رياض", "sports"),
    ("comed", "comedy"),
    ("كوميدي", "comedy"),
    ("sketch", "comedy"),
    ("خطبة", "lecture"),
    ("محاضرة", "lecture"),
];

const PLATFORM_HINTS: [(&str, &str); 8] = [
    ("tiktok", "tiktok"),
    ("تيك", "tiktok"),
    ("shorts", "youtube_shorts"),
    ("يوتيوب", "youtube_shorts"),
    ("youtube", "youtube_shorts"),
    ("reel", "instagram_reels"),
    ("انستغرام", "instagram_reels"),
    ("instagram", "instagram_reels"),
];

const THEME_HINTS: [(&str, &str); 10] = [
    ("yellow", "TikTok Yellow"),
    ("اصفر", "TikTok Yellow"),
    ("أصفر", "TikTok Yellow"),
    ("karaoke", "Karaoke Pop"),
    ("كاريوكي", "Karaoke Pop"),
    ("neon", "Neon Glow"),
    ("نيون", "Neon Glow"),
    ("minimal", "Minimal White"),
    ("bold", "Bold Red"),
    ("هادي", "Minimal White"),
];

const TONE_HINTS: [(&str, &str); 12] = [
    ("حماس", "energetic"),
    ("حماسي", "energetic"),
    ("energetic", "energetic"),
    ("hype", "energetic"),
    ("هادئ", "calm"),
    ("هادي", "calm"),
    ("calm", "calm"),
    ("chill", "calm"),
    ("فكاهي", "funny"),
    ("كوميدي", "funny"),
    ("funny", "funny"),
    ("احترافي", "professional"),
];

const MUSIC_NONE_HINTS: [&str; 3] = ["بدون موسيقى", "no music", "without music"];
const MUSIC_HINTS: [(&str, &str); 5] = [
    ("lo-fi", "lofi chill"),
    ("lofi", "lofi chill"),
    ("trap", "trap beat"),
    ("epic", "epic cinematic"),
    ("phonk", "phonk"),
];

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(default)]
pub struct BriefSettings {
    pub content_type: String,
    pub platform: String,
    pub n_clips: usize,
    pub clip_duration_sec: f64,
    pub caption_theme: String,
    pub music: String,
    pub broll: String,
    pub translate_arabic: bool,
    pub keywords: Vec<String>,
    pub tone: String,
    pub cta_text: String,
}

impl Default for BriefSettings {
    fn default() -> Self {
        BriefSettings {
            content_type: "general".to_string(),
            platform: "tiktok".to_string(),
            n_clips: DEFAULT_N_CLIPS,
            clip_duration_sec: DEFAULT_CLIP_DURATION_SEC,
            caption_theme: "auto".to_string(),
            music: String::new(),
            broll: String::new(),
            translate_arabic: false,
            keywords: Vec::new(),
            tone: "energetic".to_string(),
            cta_text: String::new(),
        }
    }
}

pub async fn parse_brief(brief_text: &str, llm: &LlmBridge) -> Result<BriefSettings> {
    let fallback = heuristic_parse(brief_text);
    let prompt = build_prompt(brief_text, &fallback);
    let resp = llm
        .ask(&prompt, 0.3, true)
        .await
        .context("brief parsing LLM call failed")?;
    match settings_from_llm(&resp.text, &fallback) {
        Ok(settings) => Ok(settings),
        Err(_) => Ok(fallback),
    }
}

pub fn heuristic_parse(brief_text: &str) -> BriefSettings {
    let mut s = BriefSettings::default();
    let low = brief_text.to_lowercase();

    if let Some(n) = first_number(&low, &[NUM_CLIPS_RE, MAKE_NUM_RE]) {
        s.n_clips = (n.round() as usize).clamp(1, MAX_CLIPS);
    }
    if let Some(sec) = first_number(&low, &[DUR_SEC_RE]) {
        s.clip_duration_sec = sec.clamp(MIN_DURATION_SEC, MAX_DURATION_SEC);
    } else if let Some(min) = first_number(&low, &[DUR_MIN_RE]) {
        s.clip_duration_sec = (min * 60.0).clamp(MIN_DURATION_SEC, MAX_DURATION_SEC);
    }

    for (needle, label) in PLATFORM_HINTS {
        if low.contains(needle) {
            s.platform = label.to_string();
            break;
        }
    }
    if low.contains("game") || low.contains("جيم") || low.contains("ألعاب") || low.contains("العاب")
    {
        s.content_type = "gaming".to_string();
    } else {
        for (needle, label) in CONTENT_HINTS {
            if low.contains(needle) {
                s.content_type = label.to_string();
                break;
            }
        }
    }

    s.translate_arabic = ["عرب", "ترجم", "arabic", "translate"]
        .iter()
        .any(|w| low.contains(w));

    for (needle, theme) in THEME_HINTS {
        if low.contains(needle) {
            s.caption_theme = theme.to_string();
            break;
        }
    }

    if MUSIC_NONE_HINTS.iter().any(|w| low.contains(w)) {
        s.music = "none".to_string();
    } else {
        for (needle, track) in MUSIC_HINTS {
            if low.contains(needle) {
                s.music = track.to_string();
                break;
            }
        }
    }

    if ["no broll", "no b-roll", "بدون برو"]
        .iter()
        .any(|w| low.contains(w))
    {
        s.broll = "none".to_string();
    } else if ["b-roll", "broll", "b roll", "برول"]
        .iter()
        .any(|w| low.contains(w))
    {
        s.broll = "auto".to_string();
    }

    for (needle, tone) in TONE_HINTS {
        if low.contains(needle) {
            s.tone = tone.to_string();
            break;
        }
    }

    s.cta_text = extract_cta(&low);

    let mut keywords: Vec<String> = Vec::new();
    if let Some(re) = Regex::new(HASHTAG_RE).ok().as_ref() {
        for cap in re.captures_iter(brief_text) {
            push_unique(&mut keywords, &cap[1]);
        }
    }
    if let Some(re) = Regex::new(KEYWORDS_LINE_RE).ok().as_ref() {
        if let Some(cap) = re.captures(&low) {
            for kw in cap[1].split([',', '،']) {
                push_unique(&mut keywords, kw);
            }
        }
    }
    keywords.truncate(12);
    s.keywords = keywords;

    s
}

fn build_prompt(brief_text: &str, hint: &BriefSettings) -> String {
    let brief: String = brief_text.chars().take(BRIEF_PROMPT_CHARS).collect();
    let schema = r#"{"content_type": "podcast|gaming|interview|tutorial|review|vlog|news|sports|comedy|general", "platform": "tiktok|youtube_shorts|instagram_reels", "n_clips": 3, "clip_duration_sec": 45, "caption_theme": "...", "music": "track name or genre", "broll": "query or none", "translate_arabic": false, "keywords": ["..."], "tone": "energetic|calm|funny|professional|dramatic", "cta_text": "..."}"#;
    let parts = vec![
        "You are the settings extractor of a short-form clipping studio.".to_string(),
        format!("Campaign brief:\n{brief}"),
        format!(
            "Heuristic pre-scan (override when the brief clearly says otherwise): \
             content_type={} platform={} n_clips={} duration={}s tone={}",
            hint.content_type, hint.platform, hint.n_clips, hint.clip_duration_sec, hint.tone
        ),
        "Return ONLY JSON with exactly these keys:".to_string(),
        schema.to_string(),
        "Rules: n_clips integer 1-12; clip_duration_sec 5-180; keep cta_text short; \
         keywords lowercase."
            .to_string(),
    ];
    parts.join("\n")
}

fn settings_from_llm(raw: &str, fb: &BriefSettings) -> Result<BriefSettings> {
    let mut v = extract_json_value(raw)?;
    if !v.is_object() {
        anyhow::bail!("brief JSON is not an object");
    }
    if let Some(inner) = v.get("settings") {
        if inner.is_object() {
            v = inner.clone();
        }
    }
    let mut s = fb.clone();
    if let Some(x) = gstr(&v, "content_type") {
        s.content_type = x.to_lowercase();
    }
    if let Some(x) = gstr(&v, "platform") {
        s.platform = normalize_platform(&x);
    }
    if let Some(x) = gusize(&v, "n_clips") {
        s.n_clips = x;
    }
    if let Some(x) = gf64(&v, "clip_duration_sec") {
        s.clip_duration_sec = x.clamp(MIN_DURATION_SEC, MAX_DURATION_SEC);
    }
    if let Some(x) = gstr(&v, "caption_theme") {
        s.caption_theme = x;
    }
    if let Some(x) = gstr(&v, "music") {
        s.music = x;
    }
    if let Some(x) = gstr(&v, "broll") {
        s.broll = x;
    }
    if let Some(x) = gbool(&v, "translate_arabic") {
        s.translate_arabic = x;
    }
    if let Some(kws) = gkeywords(&v, "keywords") {
        if !kws.is_empty() {
            s.keywords = kws;
        }
    }
    if let Some(x) = gstr(&v, "tone") {
        s.tone = x.to_lowercase();
    }
    if let Some(x) = gstr(&v, "cta_text") {
        s.cta_text = x;
    }
    Ok(s)
}

fn gstr(v: &Value, key: &str) -> Option<String> {
    v.get(key)
        .and_then(Value::as_str)
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn gf64(v: &Value, key: &str) -> Option<f64> {
    match v.get(key) {
        Some(Value::Number(n)) => n.as_f64(),
        Some(Value::String(st)) => st.trim().parse().ok(),
        _ => None,
    }
}

fn gusize(v: &Value, key: &str) -> Option<usize> {
    gf64(v, key).map(|f| f.round().clamp(1.0, MAX_CLIPS as f64) as usize)
}

fn gbool(v: &Value, key: &str) -> Option<bool> {
    match v.get(key) {
        Some(Value::Bool(b)) => Some(*b),
        Some(Value::String(st)) => match st.trim().to_lowercase().as_str() {
            "true" | "yes" | "1" => Some(true),
            "false" | "no" | "0" => Some(false),
            _ => None,
        },
        _ => None,
    }
}

fn gkeywords(v: &Value, key: &str) -> Option<Vec<String>> {
    let mut out: Vec<String> = Vec::new();
    match v.get(key) {
        Some(Value::Array(a)) => {
            for item in a {
                if let Some(st) = item.as_str() {
                    push_unique(&mut out, st);
                }
            }
        }
        Some(Value::String(st)) => {
            for part in st.split([',', '،']) {
                push_unique(&mut out, part);
            }
        }
        _ => return None,
    }
    out.truncate(12);
    Some(out)
}

fn normalize_platform(p: &str) -> String {
    let low = p.to_lowercase().replace([' ', '-', '_'], "");
    if low.contains("short") || low.contains("youtube") {
        "youtube_shorts".to_string()
    } else if low.contains("reel") || low.contains("insta") {
        "instagram_reels".to_string()
    } else {
        "tiktok".to_string()
    }
}

fn first_number(text: &str, patterns: &[&str]) -> Option<f64> {
    for pat in patterns {
        if let Some(re) = Regex::new(pat).ok().as_ref() {
            if let Some(cap) = re.captures(text) {
                if let Some(m) = cap.get(1) {
                    if let Ok(n) = m.as_str().parse::<f64>() {
                        return Some(n);
                    }
                }
            }
        }
    }
    None
}

fn extract_cta(low: &str) -> String {
    for pat in [CTA_QUOTED_RE, CTA_PLAIN_RE] {
        if let Some(re) = Regex::new(pat).ok().as_ref() {
            if let Some(cap) = re.captures(low) {
                let cleaned = cap[1]
                    .trim()
                    .trim_matches(|c| matches!(c, '"' | '“' | '”' | '-' | '—' | ':' | '.'))
                    .trim()
                    .to_string();
                if cleaned.len() >= 2 {
                    return cleaned;
                }
            }
        }
    }
    String::new()
}

fn push_unique(out: &mut Vec<String>, raw_kw: &str) {
    let kw = raw_kw.trim().to_lowercase();
    if kw.len() >= 2 && !out.contains(&kw) {
        out.push(kw);
    }
}
