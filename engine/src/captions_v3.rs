//! captions_v3.rs — Advanced word-level animated ASS subtitle generator.
//!
//! Produces complete `.ass` subtitle files (header + style + dialogue events)
//! from word-level timings `(start, end, text)`, driven by 10 viral presets
//! (MrBeast-style bold yellow, Hormozi-style clean white, karaoke sweeps,
//! word pops, typewriter reveals, bounce, slide-in, minimal, …).
//!
//! Fonts/colors are designed against a 1080x1920 canvas; when the target
//! resolution differs, sizes are scaled proportionally to the video height.

use serde::{Deserialize, Serialize};

/// Motion style applied to caption cues.
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
pub enum CaptionAnimation {
    /// Static line shown for the whole cue span.
    None,
    /// Classic `\k` sweep: unsung (secondary) color fills to primary per word.
    Karaoke,
    /// Each word pops in with an overshoot scale punch.
    WordPop,
    /// Words appear one-by-one like a terminal reveal.
    Typewriter,
    /// Squash-and-stretch spring on entry.
    Bounce,
    /// Whole cue glides up from below with a fade.
    SlideIn,
}

/// A complete caption look: font, colors, stroke, placement and motion.
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct CaptionPreset {
    pub name: String,
    pub name_ar: String,
    pub font_name: String,
    pub font_size: f32,
    /// Hex color `#RRGGBB` for the active/filled text.
    pub primary_color: String,
    /// Hex color `#RRGGBB` for the stroke/outline.
    pub outline_color: String,
    pub outline_width: f32,
    pub bold: bool,
    pub italic: bool,
    /// Vertical anchor position as % from top (0 = top edge, 100 = bottom edge).
    pub position_y_pct: f32,
    pub animation: CaptionAnimation,
}

const BASE_CANVAS_H: f32 = 1920.0;
const MAX_LINE_CHARS: usize = 28;
const MAX_LINE_WORDS: usize = 6;
const MAX_WORD_GAP_SEC: f64 = 0.8;

/// The 10 built-in caption presets.
pub fn get_presets() -> Vec<CaptionPreset> {
    vec![
        CaptionPreset {
            name: "bold_yellow".into(),
            name_ar: "أصفر جريء (MrBeast)".into(),
            font_name: "Anton".into(),
            font_size: 92.0,
            primary_color: "#FFE600".into(),
            outline_color: "#000000".into(),
            outline_width: 6.0,
            bold: true,
            italic: false,
            position_y_pct: 76.0,
            animation: CaptionAnimation::WordPop,
        },
        CaptionPreset {
            name: "clean_white".into(),
            name_ar: "أبيض نظيف (Hormozi)".into(),
            font_name: "Montserrat ExtraBold".into(),
            font_size: 84.0,
            primary_color: "#FFFFFF".into(),
            outline_color: "#111111".into(),
            outline_width: 5.0,
            bold: true,
            italic: false,
            position_y_pct: 74.0,
            animation: CaptionAnimation::Karaoke,
        },
        CaptionPreset {
            name: "neon_glow".into(),
            name_ar: "توهج نيون".into(),
            font_name: "Orbitron Bold".into(),
            font_size: 80.0,
            primary_color: "#00F0FF".into(),
            outline_color: "#0A003C".into(),
            outline_width: 4.5,
            bold: true,
            italic: false,
            position_y_pct: 72.0,
            animation: CaptionAnimation::WordPop,
        },
        CaptionPreset {
            name: "tiktok_classic".into(),
            name_ar: "كلاسيك تيك توك".into(),
            font_name: "Proxima Nova Black".into(),
            font_size: 78.0,
            primary_color: "#FFFFFF".into(),
            outline_color: "#000000".into(),
            outline_width: 4.0,
            bold: true,
            italic: false,
            position_y_pct: 68.0,
            animation: CaptionAnimation::None,
        },
        CaptionPreset {
            name: "karaoke_highlight".into(),
            name_ar: "تظليل كاريوكي".into(),
            font_name: "Poppins SemiBold".into(),
            font_size: 82.0,
            primary_color: "#FFD700".into(),
            outline_color: "#101010".into(),
            outline_width: 4.0,
            bold: true,
            italic: false,
            position_y_pct: 75.0,
            animation: CaptionAnimation::Karaoke,
        },
        CaptionPreset {
            name: "word_pop".into(),
            name_ar: "قفز الكلمات".into(),
            font_name: "Impact".into(),
            font_size: 88.0,
            primary_color: "#FFFFFF".into(),
            outline_color: "#E02D2D".into(),
            outline_width: 5.0,
            bold: false,
            italic: false,
            position_y_pct: 73.0,
            animation: CaptionAnimation::WordPop,
        },
        CaptionPreset {
            name: "typewriter".into(),
            name_ar: "آلة كاتبة".into(),
            font_name: "Consolas".into(),
            font_size: 66.0,
            primary_color: "#EAEAEA".into(),
            outline_color: "#222222".into(),
            outline_width: 3.0,
            bold: false,
            italic: false,
            position_y_pct: 78.0,
            animation: CaptionAnimation::Typewriter,
        },
        CaptionPreset {
            name: "bounce".into(),
            name_ar: "ارتداد مرن".into(),
            font_name: "Baloo 2".into(),
            font_size: 86.0,
            primary_color: "#7CFC66".into(),
            outline_color: "#123300".into(),
            outline_width: 4.5,
            bold: true,
            italic: false,
            position_y_pct: 71.0,
            animation: CaptionAnimation::Bounce,
        },
        CaptionPreset {
            name: "slide_in".into(),
            name_ar: "انزلاق دخول".into(),
            font_name: "Inter Black".into(),
            font_size: 80.0,
            primary_color: "#FFFFFF".into(),
            outline_color: "#5B2EFF".into(),
            outline_width: 4.0,
            bold: true,
            italic: false,
            position_y_pct: 77.0,
            animation: CaptionAnimation::SlideIn,
        },
        CaptionPreset {
            name: "minimal".into(),
            name_ar: "بسيط هادئ".into(),
            font_name: "Helvetica Neue".into(),
            font_size: 58.0,
            primary_color: "#F5F5F5".into(),
            outline_color: "#333333".into(),
            outline_width: 1.5,
            bold: false,
            italic: false,
            position_y_pct: 84.0,
            animation: CaptionAnimation::None,
        },
    ]
}

/// Look up a preset by name (e.g. `"clean_white"`); falls back to `clean_white`.
pub fn preset_by_name(name: &str) -> CaptionPreset {
    get_presets()
        .into_iter()
        .find(|p| p.name == name)
        .unwrap_or_else(|| {
            get_presets()
                .into_iter()
                .find(|p| p.name == "clean_white")
                .expect("built-in presets always contain clean_white")
        })
}

/// Generate a complete ASS subtitle file from word-level timings.
///
/// `words` are `(start_sec, end_sec, text)` triples, typically from whisper
/// output; they may be unsorted (they are sorted here).
pub fn generate_ass_subtitles(
    words: &[(f64, f64, String)],
    preset: &CaptionPreset,
    video_width: u32,
    video_height: u32,
) -> String {
    let mut sorted: Vec<(f64, f64, String)> = words.to_vec();
    sorted.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));

    let h = video_height.max(1) as f32;
    let scale = (h / BASE_CANVAS_H).clamp(0.4, 4.0);
    let font_size = (preset.font_size * scale).round().max(8.0);
    let outline_w = (preset.outline_width * scale).clamp(0.5, 20.0);

    // Bottom-aligned (ASS alignment 2): MarginV = distance from bottom edge.
    let margin_v = (((100.0 - preset.position_y_pct).clamp(0.0, 95.0) / 100.0) * h).round() as u32;
    let margin_v = margin_v.clamp(20, (video_height / 2).max(20));

    let primary = hex_to_ass(&preset.primary_color);
    let secondary = match preset.animation {
        CaptionAnimation::Karaoke => hex_to_ass("#9A9A9A"), // pre-sweep gray fill
        _ => primary.clone(),
    };
    let outline = hex_to_ass(&preset.outline_color);

    let bold_flag = if preset.bold { -1 } else { 0 };
    let italic_flag = if preset.italic { -1 } else { 0 };

    let mut out = String::with_capacity(2048 + words.len() * 48);
    out.push_str("[Script Info]\n");
    out.push_str("Title: Clippify Captions v3\n");
    out.push_str("ScriptType: v4.00+\n");
    out.push_str("WrapStyle: 2\n");
    out.push_str(&format!("PlayResX: {}\n", video_width.max(1)));
    out.push_str(&format!("PlayResY: {}\n", video_height.max(1)));
    out.push_str("ScaledBorderAndShadow: yes\n");
    out.push('\n');

    out.push_str("[V4+ Styles]\n");
    out.push_str(
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, \
BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, \
BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n",
    );
    out.push_str(&format!(
        "Style: Clip,{}, {}, {}, {}, {}, &HA0000000, {}, {}, 0, 0, 100, 100, 0, 0, 1, {:.1}, 2, 2, 60, 60, {}, 1\n",
        preset.font_name,
        font_size,
        primary,
        secondary,
        outline,
        bold_flag,
        italic_flag,
        outline_w,
        margin_v,
    ));
    out.push('\n');

    out.push_str("[Events]\n");
    out.push_str(
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n",
    );

    for cue in group_cues(&sorted) {
        let cue_start = cue.first().map(|w| w.0).unwrap_or(0.0);
        let cue_end = cue.last().map(|w| w.1).unwrap_or(cue_start + 0.5);
        let cue_end = cue_end.max(cue_start + 0.1);

        match preset.animation {
            CaptionAnimation::Karaoke => {
                let mut text = String::new();
                let mut prev_end = cue_start;
                for (i, (ws, we, wt)) in cue.iter().enumerate() {
                    let start = (*ws).max(prev_end);
                    let stop = if i + 1 < cue.len() {
                        cue[i + 1].0.max(start + 0.05)
                    } else {
                        (*we).max(start + 0.05)
                    };
                    let cs = ((stop - start) * 100.0).round().max(1.0) as i64;
                    if i > 0 {
                        text.push(' ');
                    }
                    text.push_str(&format!("{{\\k{}}}{}", cs, escape_text(wt)));
                    prev_end = stop;
                }
                push_dialogue(&mut out, cue_start, cue_end, &text);
            }
            CaptionAnimation::WordPop | CaptionAnimation::Typewriter | CaptionAnimation::Bounce => {
                for (i, (ws, _we, wt)) in cue.iter().enumerate() {
                    let ev_start = *ws;
                    let ev_end = if i + 1 < cue.len() {
                        cue[i + 1].0.max(ev_start + 0.08)
                    } else {
                        cue_end
                    };
                    let tag = match preset.animation {
                        CaptionAnimation::WordPop => {
                            "{\\fscx45\\fscy45\\t(0,110,\\fscx108\\fscy108)\\t(110,240,\\fscx100\\fscy100)}"
                        }
                        CaptionAnimation::Bounce => {
                            "{\\fad(70,60)\\t(0,130,\\fscy116\\fscx94)\\t(130,280,\\fscy97\\fscx103)\\t(280,430,\\fscy100\\fscx100)}"
                        }
                        _ => "",
                    };
                    push_dialogue(&mut out, ev_start, ev_end, &format!("{}{}", tag, escape_text(wt)));
                }
            }
            CaptionAnimation::SlideIn => {
                let cx = video_width.max(1) as f32 / 2.0;
                let cy = (preset.position_y_pct.clamp(0.0, 100.0) / 100.0) * h;
                let line = cue
                    .iter()
                    .map(|(_, _, t)| escape_text(t))
                    .collect::<Vec<_>>()
                    .join(" ");
                let tag = format!(
                    "{{\\an5\\move({:.0},{:.0},{:.0},{:.0},0,240)\\fad(140,0)}}",
                    cx,
                    cy + 90.0,
                    cx,
                    cy
                );
                push_dialogue(&mut out, cue_start, cue_end, &format!("{}{}", tag, line));
            }
            CaptionAnimation::None => {
                let line = cue
                    .iter()
                    .map(|(_, _, t)| escape_text(t))
                    .collect::<Vec<_>>()
                    .join(" ");
                push_dialogue(&mut out, cue_start, cue_end, &line);
            }
        }
    }

    out
}

// ── internals ───────────────────────────────────────────────────────────────

type Word = (f64, f64, String);

/// Split words into displayable cues: bounded by length, word count,
/// inter-word gaps and sentence punctuation.
fn group_cues(words: &[Word]) -> Vec<Vec<Word>> {
    let mut cues: Vec<Vec<Word>> = Vec::new();
    let mut cur: Vec<Word> = Vec::new();
    let mut chars = 0usize;

    for w in words {
        let text = w.2.trim();
        if text.is_empty() {
            continue;
        }
        let gap_break = match cur.last() {
            Some(prev) => w.0 - prev.1 > MAX_WORD_GAP_SEC,
            None => false,
        };
        let punct_break = matches!(
            cur.last().map(|p: &Word| p.2.as_str()),
            Some(t) if t.ends_with('.') || t.ends_with('!') || t.ends_with('?')
        );
        let full = chars + text.chars().count() > MAX_LINE_CHARS || cur.len() >= MAX_LINE_WORDS;

        if !cur.is_empty() && (gap_break || punct_break || full) {
            cues.push(std::mem::take(&mut cur));
            chars = 0;
        }
        chars += text.chars().count() + 1;
        cur.push((w.0, w.1, text.to_string()));
    }
    if !cur.is_empty() {
        cues.push(cur);
    }
    cues
}

fn push_dialogue(out: &mut String, start: f64, end: f64, text: &str) {
    out.push_str(&format!(
        "Dialogue: 0,{}, {},Clip,,0,0,0,,{}\n",
        ass_time(start),
        ass_time(end),
        text
    ));
}

/// Seconds → ASS `h:mm:ss.cc` (centisecond precision).
fn ass_time(sec: f64) -> String {
    let total_cs = (sec.max(0.0) * 100.0).round() as i64;
    let h = total_cs / 360_000;
    let m = (total_cs % 360_000) / 6_000;
    let s = (total_cs % 6_000) / 100;
    let cs = total_cs % 100;
    format!("{}:{:02}:{:02}.{:02}", h, m, s, cs)
}

/// `#RRGGBB` (or `#RGB`) → ASS `&HAABB GGRR` opaque color.
fn hex_to_ass(hex: &str) -> String {
    let raw = hex.trim().trim_start_matches('#');
    let (r, g, b) = match raw.len() {
        6 => (
            u8::from_str_radix(&raw[0..2], 16),
            u8::from_str_radix(&raw[2..4], 16),
            u8::from_str_radix(&raw[4..6], 16),
        ),
        3 => {
            let exp = |c: &str| format!("{}{}", c, c);
            (
                u8::from_str_radix(&exp(&raw[0..1]), 16),
                u8::from_str_radix(&exp(&raw[1..2]), 16),
                u8::from_str_radix(&exp(&raw[2..3]), 16),
            )
        }
        _ => (Ok(255), Ok(255), Ok(255)),
    };
    let (r, g, b) = (r.unwrap_or(255), g.unwrap_or(255), b.unwrap_or(255));
    format!("&H00{:02X}{:02X}{:02X}", b, g, r)
}

/// Strip characters that would break ASS override parsing.
fn escape_text(text: &str) -> String {
    text.replace(['{', '}', '\\'], "")
        .replace('\r', "")
        .replace('\n', " ")
        .trim()
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_words() -> Vec<(f64, f64, String)> {
        vec![
            (0.0, 0.30, "THIS".into()),
            (0.30, 0.62, "CHANGED".into()),
            (0.62, 1.10, "EVERYTHING!".into()),
            (1.60, 2.00, "Really.".into()),
        ]
    }

    #[test]
    fn ten_unique_presets() {
        let presets = get_presets();
        assert_eq!(presets.len(), 10);
        let mut names: Vec<&str> = presets.iter().map(|p| p.name.as_str()).collect();
        names.sort_unstable();
        names.dedup();
        assert_eq!(names.len(), 10);
        assert!(presets.iter().all(|p| !p.name_ar.is_empty()));
    }

    #[test]
    fn ass_time_formats_centiseconds() {
        assert_eq!(ass_time(0.0), "0:00:00.00");
        assert_eq!(ass_time(65.456), "0:01:05.46");
        assert_eq!(ass_time(-3.0), "0:00:00.00");
        assert_eq!(ass_time(3661.5), "1:01:01.50");
    }

    #[test]
    fn generates_valid_header_and_events() {
        let preset = preset_by_name("clean_white");
        let ass = generate_ass_subtitles(&sample_words(), &preset, 1080, 1920);
        assert!(ass.contains("[Script Info]"));
        assert!(ass.contains("PlayResX: 1080"));
        assert!(ass.contains("PlayResY: 1920"));
        assert!(ass.contains("[V4+ Styles]"));
        assert!(ass.contains("Style: Clip,Montserrat ExtraBold"));
        assert!(ass.contains("[Events]"));
        assert_eq!(ass.matches("Dialogue:").count(), 2); // 2 cues (punctuation split)
        assert!(ass.contains("\\k")); // karaoke tags present
        assert!(!ass.contains('{') || ass.matches("\\k").count() >= 3);
    }

    #[test]
    fn word_pop_emits_per_word_events() {
        let preset = preset_by_name("word_pop");
        let ass = generate_ass_subtitles(&sample_words(), &preset, 1080, 1920);
        assert_eq!(ass.matches("Dialogue:").count(), 4);
        assert!(ass.contains("\\fscx45\\fscy45"));
    }

    #[test]
    fn slide_in_uses_move_tag() {
        let preset = preset_by_name("slide_in");
        let ass = generate_ass_subtitles(&sample_words(), &preset, 1080, 1920);
        assert!(ass.contains("\\move(540,"));
        assert!(ass.contains("\\fad(140,0)"));
    }

    #[test]
    fn colors_convert_to_ass_bgr() {
        assert_eq!(hex_to_ass("#FF0000"), "&H000000FF"); // red → BGR
        assert_eq!(hex_to_ass("#0F0"), "&H0000FF00"); // green
        assert_eq!(hex_to_ass("nope"), "&H00FFFFFF"); // fallback white
    }

    #[test]
    fn braces_are_stripped_from_words() {
        let words = vec![(0.0, 0.5, "{weird}\\tag".into())];
        let preset = preset_by_name("minimal");
        let ass = generate_ass_subtitles(&words, &preset, 720, 1280);
        assert!(ass.contains("weirdtag"));
        assert!(!ass.contains("{weird}"));
    }
}
