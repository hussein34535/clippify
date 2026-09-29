//! Pre-built FFmpeg motion recipes (zoom, shake, glitch, whip pan, Ken Burns).
//!
//! Ported from `motion_recipes.py`. Every recipe is a parameterized filter
//! template rendered per-clip by [`build_filter`] and chainable via [`compose`].

use anyhow::{anyhow, bail, Result};
use serde::Serialize;
use serde_json::{json, Value};

/// A single motion recipe: template + default params.
#[derive(Debug, Clone, Serialize)]
pub struct MotionRecipe {
    pub name: String,
    pub description_ar: String,
    pub filter_template: String,
    pub params: Value,
}

const DEFAULT_FPS: f64 = 30.0;
const DEFAULT_OUT_W: f64 = 720.0;
const DEFAULT_OUT_H: f64 = 1280.0;

/// All 6 built-in recipes with their default parameters.
pub fn get_recipes() -> Vec<MotionRecipe> {
    vec![
        MotionRecipe {
            name: "zoom_in".into(),
            description_ar: "زوم بطيء من 1.0 إلى 1.15 على مدار المقطع".into(),
            filter_template: "zoompan=z='min(zoom+{zoom_step},{zoom_end})':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s={out_w}x{out_h}:fps={fps}".into(),
            params: json!({"zoom_end": 1.15}),
        },
        MotionRecipe {
            name: "punch_in".into(),
            description_ar: "زوم سريع إلى 1.3 عند 80% من مدة المقطع".into(),
            filter_template: "zoompan=z='if(lt(in,{punch_start_frame}),1.0,min(1.0+({zoom_end}-1.0)*(in-{punch_start_frame})/{punch_ramp_frames},{zoom_end}))':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s={out_w}x{out_h}:fps={fps}".into(),
            params: json!({"zoom_end": 1.3}),
        },
        MotionRecipe {
            name: "shake".into(),
            description_ar: "اهتزاز كاميرا خفيف بإزاحات عشوائية للقص".into(),
            filter_template: "crop=w='iw-{shake_px}':h='ih-{shake_px}':x='random(1)*{shake_px}':y='random(2)*{shake_px}'".into(),
            params: json!({"shake_px": 16}),
        },
        MotionRecipe {
            name: "glitch".into(),
            description_ar: "وميض انفصال قنوات RGB لمدة إطارين عند منتصف المقطع".into(),
            filter_template: "rgbashift=rh={glitch_shift}:bh=-{glitch_shift}:enable='between(t,{glitch_t0},{glitch_t1})'".into(),
            params: json!({"glitch_shift": 6}),
        },
        MotionRecipe {
            name: "whip_pan".into(),
            description_ar: "انتقال تمويه أفقي سريع حول منتصف المقطع".into(),
            filter_template: "avgblur=sizeX={whip_blur}:sizeY=1:enable='between(t,{whip_t0},{whip_t1})'".into(),
            params: json!({"whip_blur": 40}),
        },
        MotionRecipe {
            name: "ken_burns".into(),
            description_ar: "تحريك قطري بطيء مع زوم تدريجي (كين بيرنز)".into(),
            filter_template: "zoompan=z='{kb_zoom_start}+({kb_zoom_end}-{kb_zoom_start})*in/{frames}':x='(iw-iw/zoom)*in/{frames}':y='(ih-ih/zoom)*in/{frames}':d=1:s={out_w}x{out_h}:fps={fps}".into(),
            params: json!({"kb_zoom_start": 1.0, "kb_zoom_end": 1.25}),
        },
    ]
}

/// Render an FFmpeg filter string for one recipe on a specific clip.
/// Unknown recipes or invalid durations yield an empty string; use
/// [`try_build_filter`] for the error detail.
pub fn build_filter(name: &str, duration_sec: f64, params: &Value) -> String {
    try_build_filter(name, duration_sec, params).unwrap_or_default()
}

/// Fallible variant of [`build_filter`] mirroring `motion_recipes.py`.
///
/// `params` overrides recipe defaults; recognized keys include `fps`,
/// `out_w`, `out_h`, `zoom_end`, `punch_at`, `punch_ramp`, `shake_px`,
/// `glitch_shift`, `whip_blur`, `whip_span`, `kb_zoom_start`, `kb_zoom_end`.
pub fn try_build_filter(name: &str, duration_sec: f64, params: &Value) -> Result<String> {
    let recipes = get_recipes();
    let recipe = recipes
        .iter()
        .find(|r| r.name == name)
        .ok_or_else(|| {
            let known: Vec<&str> = recipes.iter().map(|r| r.name.as_str()).collect();
            anyhow!("unknown recipe {name:?}; known: {}", known.join(", "))
        })?;
    if !duration_sec.is_finite() || duration_sec <= 0.0 {
        bail!("duration_sec must be a positive number, got {duration_sec}");
    }

    let user = params;
    let defaults = &recipe.params;
    let num = |key: &str, fallback: f64| -> f64 {
        user.get(key)
            .and_then(Value::as_f64)
            .or_else(|| defaults.get(key).and_then(Value::as_f64))
            .unwrap_or(fallback)
    };

    let fps = num("fps", DEFAULT_FPS);
    let fps_i = fps.max(1.0) as i64;
    let out_w = num("out_w", DEFAULT_OUT_W) as i64;
    let out_h = num("out_h", DEFAULT_OUT_H) as i64;

    let frames = ((duration_sec * fps as f64).round() as i64).max(1);
    let zoom_end = num("zoom_end", 1.0);
    let zoom_step = (zoom_end - 1.0) / frames as f64;
    let punch_at = num("punch_at", 0.80);
    let punch_start_frame = (((frames as f64) * punch_at).round() as i64).max(1);
    let punch_ramp = num("punch_ramp", 0.06);
    let punch_ramp_frames = (((frames as f64) * punch_ramp).round() as i64).max(1);

    let mid_t = round_n(duration_sec * 0.5, 4);
    let two_frames = round_n(2.0 / fps.max(1.0), 4);
    let whip_span = num("whip_span", 0.10);
    let glitch_shift = num("glitch_shift", 6.0);
    let whip_blur = num("whip_blur", 40.0);
    let shake_px = num("shake_px", 16.0);
    let kb_zoom_start = num("kb_zoom_start", 1.0);
    let kb_zoom_end = num("kb_zoom_end", 1.25);

    let replacements: Vec<(&str, String)> = vec![
        ("{fps}", fmt_num(fps_i as f64, 0)),
        ("{out_w}", out_w.to_string()),
        ("{out_h}", out_h.to_string()),
        ("{frames}", frames.to_string()),
        ("{duration}", fmt_num(round_n(duration_sec, 4), 4)),
        ("{zoom_step}", fmt_num(round_n(zoom_step, 6), 6)),
        ("{zoom_end}", fmt_num(zoom_end, 6)),
        ("{punch_start_frame}", punch_start_frame.to_string()),
        ("{punch_ramp_frames}", punch_ramp_frames.to_string()),
        ("{glitch_shift}", fmt_num(glitch_shift, 0)),
        ("{glitch_t0}", fmt_num(mid_t, 4)),
        ("{glitch_t1}", fmt_num(round_n(mid_t + two_frames, 4), 4)),
        ("{whip_blur}", fmt_num(whip_blur, 0)),
        ("{whip_t0}", fmt_num(round_n(mid_t - whip_span / 2.0, 4), 4)),
        ("{whip_t1}", fmt_num(round_n(mid_t + whip_span / 2.0, 4), 4)),
        ("{shake_px}", fmt_num(shake_px, 0)),
        ("{kb_zoom_start}", fmt_num(kb_zoom_start, 6)),
        ("{kb_zoom_end}", fmt_num(kb_zoom_end, 6)),
    ];

    let mut out = recipe.filter_template.clone();
    for (token, value) in replacements {
        out = out.replace(token, &value);
    }
    Ok(out)
}

/// Chain multiple recipes into a single comma-joined `-vf` string.
pub fn compose(names: &[&str], duration_sec: f64) -> String {
    names
        .iter()
        .map(|name| build_filter(name, duration_sec, &Value::Null))
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join(",")
}

fn round_n(v: f64, n: u32) -> f64 {
    let m = 10f64.powi(n as i32);
    (v * m).round() / m
}

/// Format like Python's `round()` repr: trims trailing zeros (`2.50` → `2.5`).
fn fmt_num(v: f64, precision: usize) -> String {
    if precision == 0 {
        return format!("{}", v.round() as i64);
    }
    let s = format!("{:.prec$}", v, prec = precision);
    let s = s.trim_end_matches('0').trim_end_matches('.');
    s.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn six_recipes_present() {
        let names: Vec<String> = get_recipes().into_iter().map(|r| r.name).collect();
        assert_eq!(
            names,
            vec!["zoom_in", "punch_in", "shake", "glitch", "whip_pan", "ken_burns"]
        );
    }

    #[test]
    fn zoom_in_renders_defaults() {
        let f = build_filter("zoom_in", 10.0, &Value::Null);
        assert!(f.starts_with("zoompan="));
        assert!(f.contains("min(zoom+"));
        assert!(f.contains("s=720x1280"));
        assert!(f.contains("fps=30"));
    }

    #[test]
    fn param_overrides_apply() {
        let p = json!({"fps": 60, "out_w": 1080, "out_h": 1920});
        let f = build_filter("ken_burns", 8.0, &p);
        assert!(f.contains("fps=60"));
        assert!(f.contains("s=1080x1920"));
        assert!(f.contains("*in/480")); // frames = 8*60
    }

    #[test]
    fn punch_and_glitch_timings() {
        let punch = build_filter("punch_in", 10.0, &Value::Null);
        assert!(punch.contains("if(lt(in,240)")); // 300 frames * 0.80
        let glitch = build_filter("glitch", 10.0, &json!({"glitch_shift": 9}));
        assert!(glitch.contains("rh=9"));
        assert!(glitch.contains("bh=-9"));
        assert!(glitch.contains("between(t,5,"));
    }

    #[test]
    fn unknown_recipe_empty() {
        assert_eq!(build_filter("nope", 5.0, &Value::Null), "");
        assert_eq!(build_filter("zoom_in", -1.0, &Value::Null), "");
        assert_eq!(build_filter("zoom_in", 0.0, &Value::Null), "");
    }

    #[test]
    fn compose_joins_with_commas() {
        let s = compose(&["zoom_in", "shake"], 6.0);
        assert!(s.starts_with("zoompan="));
        assert!(s.contains(",crop=w='iw-16'"));
        assert!(s.ends_with("random(2)*16'"));
        // unknown names are silently skipped
        assert_eq!(compose(&["nope", "shake"], 6.0), build_filter("shake", 6.0, &Value::Null));
    }
}
