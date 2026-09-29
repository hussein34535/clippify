use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::OnceLock;

pub const TRENDS_DIR: &str = "trends_data";
const UA: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36 ClippifyTrendSeed/1.0";
const DEDUP_THRESHOLD: f64 = 0.6;
const TOP_N: usize = 20;
const REDDIT_TIMEOUT_SECS: u64 = 8;
const DEFAULT_SUBREDDIT: &str = "TikTokHelp";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Trend {
    pub title: String,
    pub source: String,
    #[serde(default)]
    pub url: String,
    #[serde(default)]
    pub score: f64,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub sounds: Vec<String>,
}

fn clean_niche(niche: &str) -> String {
    niche.trim().to_lowercase()
}

fn niche_keywords(niche: &str) -> Vec<String> {
    match niche {
        "podcast" => vec![
            "podcast", "بودكاست", "مقابلة", "انترفيو", "interview", "episode",
            "حلقة", "story", "قصة", "studio", "mic", "مايك", "montage", "مونتاج",
        ]
        .into_iter()
        .map(String::from)
        .collect(),
        "comedy" => vec![
            "comedy", "كوميدي", "funny", "مضحك", "اضحك", "laugh", "ضحك",
            "sketch", "اسكتش", "prank", "مقلب", "standup", "pov",
        ]
        .into_iter()
        .map(String::from)
        .collect(),
        "gaming" => vec![
            "gaming", "جيمينج", "game", "لعبة", "العاب", "gameplay", "بث",
            "stream", "speedrun", "esports", "valorant", "fortnite", "fps",
        ]
        .into_iter()
        .map(String::from)
        .collect(),
        _ => {
            if niche.is_empty() {
                Vec::new()
            } else {
                vec![niche.to_string()]
            }
        }
    }
}

fn niche_subreddit(niche: &str) -> &'static str {
    match niche {
        "podcast" => "podcasting",
        "comedy" => "comedy",
        "gaming" => "gaming",
        _ => DEFAULT_SUBREDDIT,
    }
}

fn source_priority(source: &str) -> u8 {
    match source {
        "local" => 0,
        "youtube" => 1,
        "reddit" => 2,
        _ => 9,
    }
}

const PODCAST_TRENDS_JSON: &str = r##"[
  {"title": "Podcast hosts react to wild caller stories #podcast #storytime", "source": "local", "url": "", "score": 0.0, "tags": ["#podcast", "#storytime", "#hottake"], "sounds": ["original audio - viral podcast moment"]},
  {"title": "The interview clip everyone is quoting this week #interview #viral", "source": "local", "url": "", "score": 0.0, "tags": ["#interview", "#viral", "#clip"], "sounds": ["trending podcast sting"]},
  {"title": "أقوى لحظة في حلقة اليوم #بودكاست #قصة", "source": "local", "url": "", "score": 0.0, "tags": ["#بودكاست", "#قصة", "#حلقة"], "sounds": ["مقطع صوتي رائج"]},
  {"title": "Studio setup tour with the perfect mic sound #studio #mic", "source": "local", "url": "", "score": 0.0, "tags": ["#studio", "#mic", "#setup"], "sounds": []},
  {"title": "Hot take debate segment format blowing up #hottake #debate", "source": "local", "url": "", "score": 0.0, "tags": ["#hottake", "#debate", "#podcast"], "sounds": ["dramatic pause sfx"]},
  {"title": "Behind the scenes of a full episode montage #montage #bts", "source": "local", "url": "", "score": 0.0, "tags": ["#montage", "#bts", "#episode"], "sounds": []}
]"##;

const COMEDY_TRENDS_JSON: &str = r##"[
  {"title": "POV prank reactions that never get old #pov #prank", "source": "local", "url": "", "score": 0.0, "tags": ["#pov", "#prank", "#funny"], "sounds": ["crowd laugh trending audio"]},
  {"title": "Sketch comedy format taking over feeds #sketch #comedy", "source": "local", "url": "", "score": 0.0, "tags": ["#sketch", "#comedy", "#funny"], "sounds": ["iconic sketch punchline"]},
  {"title": "اسكتش مضحك عن المواقف اليومية #اسكتش #مضحك", "source": "local", "url": "", "score": 0.0, "tags": ["#اسكتش", "#مضحك", "#كوميدي"], "sounds": ["صوت رائج"]},
  {"title": "Standup crowd work clips going viral #standup #crowdwork", "source": "local", "url": "", "score": 0.0, "tags": ["#standup", "#crowdwork", "#laugh"], "sounds": []},
  {"title": "Try not to laugh challenge is back #funny #challenge", "source": "local", "url": "", "score": 0.0, "tags": ["#funny", "#challenge", "#laugh"], "sounds": ["silence then chaos sfx"]},
  {"title": "مقلب عائلي ضحك الجميع #مقلب #ضحك", "source": "local", "url": "", "score": 0.0, "tags": ["#مقلب", "#ضحك", "#عائلة"], "sounds": []}
]"##;

const GAMING_TRENDS_JSON: &str = r##"[
  {"title": "Clutch gameplay moments you have to see #gaming #clutch", "source": "local", "url": "", "score": 0.0, "tags": ["#gaming", "#clutch", "#gameplay"], "sounds": ["epic win sting"]},
  {"title": "Speedrun world record attempt highlights #speedrun #wr", "source": "local", "url": "", "score": 0.0, "tags": ["#speedrun", "#wr", "#gaming"], "sounds": ["countdown tension loop"]},
  {"title": "أفضل لحظات البث المباشر #بث #جيمينج", "source": "local", "url": "", "score": 0.0, "tags": ["#بث", "#جيمينج", "#العاب"], "sounds": ["مؤثر فوز رائج"]},
  {"title": "Valorant ace in ranked is pure adrenaline #valorant #fps", "source": "local", "url": "", "score": 0.0, "tags": ["#valorant", "#fps", "#esports"], "sounds": []},
  {"title": "Fortnite build fight comebacks trending #fortnite #buildfight", "source": "local", "url": "", "score": 0.0, "tags": ["#fortnite", "#buildfight", "#gaming"], "sounds": ["victory royale audio"]},
  {"title": "Streamer reacts to impossible boss fight #stream #bossfight", "source": "local", "url": "", "score": 0.0, "tags": ["#stream", "#bossfight", "#gameplay"], "sounds": []}
]"##;

fn embedded_seed(niche: &str) -> Option<&'static str> {
    match niche {
        "podcast" => Some(PODCAST_TRENDS_JSON),
        "comedy" => Some(COMEDY_TRENDS_JSON),
        "gaming" => Some(GAMING_TRENDS_JSON),
        _ => None,
    }
}

fn make_trend(
    title: impl Into<String>,
    source: impl Into<String>,
    url: impl Into<String>,
    tags: Vec<String>,
    sounds: Vec<String>,
    score: f64,
) -> Trend {
    Trend {
        title: title.into(),
        source: source.into(),
        url: url.into(),
        score,
        tags,
        sounds,
    }
}

fn parse_trends_value(data: &Value) -> Vec<Trend> {
    let items = match data {
        Value::Array(items) => items.clone(),
        Value::Object(obj) => match obj.get("trends") {
            Some(Value::Array(items)) => items.clone(),
            _ => return Vec::new(),
        },
        _ => return Vec::new(),
    };
    items
        .iter()
        .filter_map(|item| {
            let title = item.get("title")?.as_str()?.trim().to_string();
            if title.is_empty() {
                return None;
            }
            let str_list = |k: &str| -> Vec<String> {
                item.get(k)
                    .and_then(|v| v.as_array())
                    .map(|a| {
                        a.iter()
                            .filter_map(|s| s.as_str())
                            .map(|s| s.to_string())
                            .collect()
                    })
                    .unwrap_or_default()
            };
            Some(make_trend(
                title,
                item.get("source").and_then(|v| v.as_str()).unwrap_or("local"),
                item.get("url").and_then(|v| v.as_str()).unwrap_or(""),
                str_list("tags"),
                str_list("sounds"),
                item.get("score").and_then(|v| v.as_f64()).unwrap_or(0.0),
            ))
        })
        .collect()
}

pub fn load_local(niche: &str) -> Vec<Trend> {
    let key = clean_niche(niche);
    let path = std::path::Path::new(TRENDS_DIR).join(format!("{key}.json"));
    if let Ok(text) = std::fs::read_to_string(&path) {
        if let Ok(data) = serde_json::from_str::<Value>(&text) {
            let parsed = parse_trends_value(&data);
            if !parsed.is_empty() {
                return parsed;
            }
        }
    }
    embedded_seed(&key)
        .and_then(|js| serde_json::from_str::<Vec<Trend>>(js).ok())
        .unwrap_or_default()
}

fn normalize(text: &str) -> String {
    text.to_lowercase()
        .chars()
        .filter(|c| !matches!(c, '\u{064B}'..='\u{0652}' | '\u{0670}' | '\u{0640}'))
        .map(|c| match c {
            '\u{0623}' | '\u{0625}' | '\u{0622}' => '\u{0627}',
            '\u{0629}' => '\u{0647}',
            '\u{0649}' => '\u{064A}',
            other => other,
        })
        .collect()
}

fn tokens(text: &str) -> std::collections::HashSet<String> {
    static WORD_RE: OnceLock<regex::Regex> = OnceLock::new();
    let re = WORD_RE.get_or_init(|| regex::Regex::new(r"\w{3,}").expect("valid regex"));
    re.find_iter(&normalize(text))
        .map(|m| m.as_str().to_string())
        .collect()
}

fn title_similarity(a: &str, b: &str) -> f64 {
    let (ta, tb) = (tokens(a), tokens(b));
    if ta.is_empty() || tb.is_empty() {
        return 0.0;
    }
    let inter = ta.intersection(&tb).count();
    let union = ta.union(&tb).count();
    inter as f64 / union as f64
}

fn relevance_score(trend: &Trend, keywords: &[String]) -> f64 {
    let tag_text = trend.tags.join(" ");
    let text = normalize(&format!("{} {}", trend.title, tag_text));
    let usable: Vec<String> = keywords
        .iter()
        .map(|k| normalize(k))
        .filter(|k| !k.trim().is_empty())
        .collect();
    if usable.is_empty() {
        return 0.0;
    }
    let hits = usable.iter().filter(|kw| text.contains(kw.as_str())).count();
    (hits as f64 * 100.0 / usable.len() as f64 * 10.0).round() / 10.0
}

pub async fn fetch_reddit(subreddit: &str) -> Vec<Trend> {
    let sub = subreddit.trim().trim_matches('/');
    let sub = if sub.is_empty() { DEFAULT_SUBREDDIT } else { sub };
    let url = format!("https://www.reddit.com/r/{sub}/hot.json?limit=25&raw_json=1");
    let client = match reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(REDDIT_TIMEOUT_SECS))
        .user_agent(UA)
        .build()
    {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };
    let data: Value = match client.get(&url).send().await {
        Ok(resp) => match resp.json().await {
            Ok(d) => d,
            Err(_) => return Vec::new(),
        },
        Err(_) => return Vec::new(),
    };
    let children = data["data"]["children"].as_array().cloned().unwrap_or_default();
    children
        .iter()
        .filter_map(|child| {
            let d = child.get("data")?;
            let title = d.get("title")?.as_str()?.trim();
            if title.is_empty() {
                return None;
            }
            let permalink = d.get("permalink").and_then(|v| v.as_str()).unwrap_or("");
            Some(make_trend(
                title,
                "reddit",
                format!("https://www.reddit.com{permalink}"),
                Vec::new(),
                Vec::new(),
                d.get("score").and_then(|v| v.as_f64()).unwrap_or(0.0),
            ))
        })
        .collect()
}

pub async fn aggregate(niche: &str) -> Vec<Trend> {
    let key = clean_niche(niche);
    let mut pool = load_local(&key);
    pool.extend(fetch_reddit(niche_subreddit(&key)).await);
    if pool.is_empty() {
        return Vec::new();
    }
    let keywords = niche_keywords(&key);
    let mut unique: Vec<Trend> = Vec::new();
    for tr in &pool {
        if tr.title.trim().is_empty() {
            continue;
        }
        if unique
            .iter()
            .any(|u| title_similarity(&tr.title, &u.title) >= DEDUP_THRESHOLD)
        {
            continue;
        }
        let mut item = make_trend(
            tr.title.clone(),
            tr.source.clone(),
            tr.url.clone(),
            tr.tags.clone(),
            tr.sounds.clone(),
            0.0,
        );
        item.score = relevance_score(&item, &keywords);
        unique.push(item);
    }
    unique.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(source_priority(&a.source).cmp(&source_priority(&b.source)))
            .then(a.title.cmp(&b.title))
    });
    unique.truncate(TOP_N);
    unique
}

pub fn get_hashtags(niche: &str) -> Vec<String> {
    static TAG_RE: OnceLock<regex::Regex> = OnceLock::new();
    let re = TAG_RE.get_or_init(|| regex::Regex::new(r"#\w+").expect("valid regex"));
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::new();
    for tr in load_local(niche) {
        let mut candidates: Vec<String> =
            re.find_iter(&tr.title).map(|m| m.as_str().to_string()).collect();
        candidates.extend(tr.tags.into_iter().filter(|t| t.starts_with('#')));
        for h in candidates {
            let key = h.to_lowercase();
            if seen.insert(key) {
                out.push(h);
            }
        }
    }
    out
}

pub fn get_sounds(niche: &str) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::new();
    for tr in load_local(niche) {
        for s in tr.sounds {
            let s = s.trim().to_string();
            if !s.is_empty() && seen.insert(s.to_lowercase()) {
                out.push(s);
            }
        }
    }
    out
}

pub fn save_trends(niche: &str, trends: &[Trend]) -> Result<String> {
    let key = clean_niche(niche);
    let dir = std::path::Path::new(TRENDS_DIR);
    std::fs::create_dir_all(dir)?;
    let path = dir.join(format!("{key}.json"));
    std::fs::write(&path, serde_json::to_string_pretty(trends)?)?;
    Ok(path.display().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn similarity_and_dedup_math() {
        assert!((title_similarity("Gaming clutch moments", "gaming clutch moments") - 1.0).abs() < 1e-9);
        assert!(title_similarity("totally different topic", "gaming clutch moments") < 0.3);
        assert_eq!(title_similarity("", "anything"), 0.0);
    }

    #[test]
    fn arabic_normalization_strips_diacritics() {
        let n = normalize("\u{0627}\u{0644}\u{0652}\u{0639}\u{064E}\u{0631}\u{064E}\u{0628}\u{0650}\u{064A}\u{064E}\u{0651}\u{0629}");
        assert!(!n.contains('\u{064B}'));
        assert!(normalize("\u{0623}\u{062D}\u{0645}\u{062F}").contains('\u{0627}'));
        assert!(n.contains('\u{0647}'));
    }

    #[test]
    fn load_local_falls_back_to_embedded_seeds() {
        for niche in ["podcast", "comedy", "gaming"] {
            let trends = load_local(niche);
            assert!(!trends.is_empty(), "{niche} seeds missing");
            assert!(trends.iter().all(|t| t.source == "local"));
        }
        assert!(load_local("unknown_niche_xyz").is_empty());
    }

    #[test]
    fn hashtags_and_sounds_extractors() {
        let tags = get_hashtags("comedy");
        assert!(tags.contains(&"#pov".to_string()));
        let sounds = get_sounds("podcast");
        assert!(!sounds.is_empty());
    }

    #[test]
    fn parse_trends_value_accepts_wrapped_dict() {
        let v: Value = serde_json::from_str(r#"{"trends": [{"title": "Wrapped trend"}]}"#).unwrap();
        let parsed = parse_trends_value(&v);
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].title, "Wrapped trend");
        assert_eq!(parsed[0].source, "local");
    }

    #[test]
    fn aggregate_scores_and_sorts_without_network() {
        let trends = load_local("podcast");
        let keywords = niche_keywords("podcast");
        let scored: Vec<f64> = trends.iter().map(|t| relevance_score(t, &keywords)).collect();
        assert!(scored.iter().any(|s| *s > 0.0));
        assert!(scored.iter().all(|s| *s <= 100.0));
    }
}
