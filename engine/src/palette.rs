//! Palette engine — dominant-color extraction + mood-driven palette generation.
//!
//! Ported from `palette_engine.py`. Frames are dumped through the FFmpeg
//! binary as raw RGB24 piped to stdout (no image decoding needed), then
//! quantized into 4096 buckets (4 bits per channel) and merged into
//! dominant colors. All color math (HSL manipulation) is local.

use anyhow::{anyhow, bail, Context, Result};
use regex::Regex;
use std::path::Path;
use std::process::{Command, Stdio};

/// Moods supported by [`generate_palette`].
pub const MOODS: [&str; 4] = ["energetic", "calm", "dark", "warm"];

const TOP_K: usize = 6;
const MERGE_DISTANCE: f64 = 42.0;
const BUCKETS: usize = 4096; // 4-bit per channel
const SCALE_WIDTH: i64 = 160;

/// Full palette derived from dominant colors plus a mood.
#[derive(Debug, Clone, serde::Serialize)]
pub struct PaletteResult {
    pub primary: String,
    pub secondary: String,
    pub accent: String,
    pub text_fg: String,
    pub text_bg: String,
    pub overlay_tint: String,
}

// ---------------------------------------------------------------------------
// Frame dumping (ffmpeg subprocess -> raw RGB24 on stdout)
// ---------------------------------------------------------------------------

/// Extract dominant colors from a video as `(#RRGGBB, percentage%)` pairs,
/// sorted by descending coverage. Returns an empty vector on any failure;
/// use [`try_extract_dominant_colors`] for the error detail.
pub fn extract_dominant_colors(
    ffmpeg_path: &str,
    video_path: &str,
    n_frames: usize,
) -> Vec<(String, f64)> {
    try_extract_dominant_colors(ffmpeg_path, video_path, n_frames).unwrap_or_default()
}

/// Fallible variant of [`extract_dominant_colors`].
pub fn try_extract_dominant_colors(
    ffmpeg_path: &str,
    video_path: &str,
    n_frames: usize,
) -> Result<Vec<(String, f64)>> {
    if video_path.is_empty() {
        bail!("video_path must be a non-empty string");
    }
    if !Path::new(video_path).is_file() {
        bail!("video not found: {video_path}");
    }
    let n_frames = n_frames.max(1);

    let duration = probe_duration(ffmpeg_path, video_path).unwrap_or(0.0);
    let vf = if duration > 0.1 {
        format!("fps={:.6},scale={SCALE_WIDTH}:-2", n_frames as f64 / duration)
    } else {
        format!("scale={SCALE_WIDTH}:-2")
    };

    let out = Command::new(ffmpeg_path)
        .args([
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            video_path,
            "-vf",
            &vf,
            "-frames:v",
            &n_frames.to_string(),
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-",
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .with_context(|| format!("ffmpeg frame dump failed for {video_path}"))?;

    if out.stdout.is_empty() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        let tail: Vec<&str> = stderr.trim().lines().rev().take(3).collect();
        return Err(anyhow!(
            "ffmpeg produced no frames for {video_path}: {}",
            tail.into_iter().rev().collect::<Vec<_>>().join(" | ")
        ));
    }

    let mut ranked = merge_clusters(dominant_from_buckets(&out.stdout));
    ranked.sort_by(|a, b| b.1.total_cmp(&a.1));
    ranked.truncate(TOP_K);

    let kept_total: f64 = ranked.iter().map(|(_, w)| *w).sum::<f64>().max(1.0);
    Ok(ranked
        .into_iter()
        .map(|(color, w)| (rgb_to_hex(color.0, color.1, color.2), round2(w / kept_total * 100.0)))
        .collect())
}

/// Best-effort duration probe via the ffmpeg binary itself (no ffprobe).
fn probe_duration(ffmpeg_path: &str, video_path: &str) -> Result<f64> {
    let out = Command::new(ffmpeg_path)
        .args(["-hide_banner", "-i", video_path])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .context("ffmpeg -i probe failed")?;
    let blob = String::from_utf8_lossy(&out.stderr);
    let re = Regex::new(r"Duration:\s*(\d+):(\d+):(\d+\.?\d*)")?;
    let cap = re
        .captures(&blob)
        .ok_or_else(|| anyhow!("no Duration line in ffmpeg output"))?;
    let h: f64 = cap[1].parse()?;
    let m: f64 = cap[2].parse()?;
    let s: f64 = cap[3].parse()?;
    Ok(h * 3600.0 + m * 60.0 + s)
}

// ---------------------------------------------------------------------------
// Quantization — 4096-bucket histogram + greedy cluster merge
// ---------------------------------------------------------------------------

fn dominant_from_buckets(pixels: &[u8]) -> Vec<((u8, u8, u8), f64)> {
    // buckets[key] = [count, sum_r, sum_g, sum_b]
    let mut buckets = vec!([0.0f64; 4]; BUCKETS);
    for px in pixels.chunks_exact(3) {
        let key = (((px[0] >> 4) as usize) << 8)
            | (((px[1] >> 4) as usize) << 4)
            | ((px[2] >> 4) as usize);
        let b = &mut buckets[key];
        b[0] += 1.0;
        b[1] += px[0] as f64;
        b[2] += px[1] as f64;
        b[3] += px[2] as f64;
    }

    let mut filled: Vec<(usize, [f64; 4])> = buckets
        .into_iter()
        .enumerate()
        .filter(|(_, b)| b[0] > 0.0)
        .collect();
    filled.sort_by(|a, b| b.1[0].total_cmp(&a.1[0]));

    filled[..filled.len().min(TOP_K)]
        .iter()
        .map(|(_, b)| {
            (
                (
                    (b[1] / b[0]).round().clamp(0.0, 255.0) as u8,
                    (b[2] / b[0]).round().clamp(0.0, 255.0) as u8,
                    (b[3] / b[0]).round().clamp(0.0, 255.0) as u8,
                ),
                b[0],
            )
        })
        .collect()
}

/// Greedy merge of near-identical cluster representatives (distance <= 42).
fn merge_clusters(weighted: Vec<((u8, u8, u8), f64)>) -> Vec<((u8, u8, u8), f64)> {
    let mut clusters: Vec<((u8, u8, u8), f64)> = Vec::new();
    for (color, weight) in weighted {
        let mut merged = false;
        for cluster in clusters.iter_mut() {
            let dr = cluster.0 .0 as f64 - color.0 as f64;
            let dg = cluster.0 .1 as f64 - color.1 as f64;
            let db = cluster.0 .2 as f64 - color.2 as f64;
            let dist = (dr * dr + dg * dg + db * db).sqrt();
            if dist <= MERGE_DISTANCE {
                let total = cluster.1 + weight;
                let mix = |a: u8, wa: f64, c: u8, wc: f64| -> u8 {
                    ((a as f64 * wa + c as f64 * wc) / total).round().clamp(0.0, 255.0) as u8
                };
                *cluster = (
                    (
                        mix(cluster.0 .0, cluster.1, color.0, weight),
                        mix(cluster.0 .1, cluster.1, color.1, weight),
                        mix(cluster.0 .2, cluster.1, color.2, weight),
                    ),
                    total,
                );
                merged = true;
                break;
            }
        }
        if !merged {
            clusters.push((color, weight));
        }
    }
    clusters
}

// ---------------------------------------------------------------------------
// Color math (pure)
// ---------------------------------------------------------------------------

pub fn clamp(value: f64, lo: f64, hi: f64) -> f64 {
    if value < lo {
        lo
    } else if value > hi {
        hi
    } else {
        value
    }
}

pub fn hex_to_rgb(hex_color: &str) -> Result<(u8, u8, u8)> {
    let mut hex = hex_color.trim().trim_start_matches('#').to_string();
    if hex.len() == 3 {
        hex = hex
            .chars()
            .flat_map(|c| [c, c])
            .collect::<String>();
    }
    if hex.len() != 6 && hex.len() != 8 {
        return Err(anyhow!("invalid hex color: {hex_color:?}"));
    }
    let hex = &hex[hex.len() - 6..];
    let r = u8::from_str_radix(&hex[0..2], 16)?;
    let g = u8::from_str_radix(&hex[2..4], 16)?;
    let b = u8::from_str_radix(&hex[4..6], 16)?;
    Ok((r, g, b))
}

pub fn rgb_to_hex(r: u8, g: u8, b: u8) -> String {
    format!("#{r:02X}{g:02X}{b:02X}")
}

pub fn rgb_to_hsl(r: u8, g: u8, b: u8) -> (f64, f64, f64) {
    let (rf, gf, bf) = (r as f64 / 255.0, g as f64 / 255.0, b as f64 / 255.0);
    let c_max = rf.max(gf).max(bf);
    let c_min = rf.min(gf).min(bf);
    let delta = c_max - c_min;
    let lightness = (c_max + c_min) / 2.0;
    if delta <= 0.0 {
        return (0.0, 0.0, lightness);
    }
    let hue = if c_max == rf {
        ((gf - bf) / delta).rem_euclid(6.0)
    } else if c_max == gf {
        (bf - rf) / delta + 2.0
    } else {
        (rf - gf) / delta + 4.0
    } * 60.0;
    let denom = 1.0 - (2.0 * lightness - 1.0).abs();
    let saturation = if denom > 0.0 { delta / denom } else { 0.0 };
    (hue.rem_euclid(360.0), saturation, lightness)
}

pub fn hsl_to_rgb(h: f64, s: f64, l: f64) -> (u8, u8, u8) {
    let h = h.rem_euclid(360.0);
    let s = clamp(s, 0.0, 1.0);
    let l = clamp(l, 0.0, 1.0);
    let c = (1.0 - (2.0 * l - 1.0).abs()) * s;
    let x = c * (1.0 - ((h / 60.0) % 2.0 - 1.0).abs());
    let m = l - c / 2.0;
    let (rp, gp, bp) = if h < 60.0 {
        (c, x, 0.0)
    } else if h < 120.0 {
        (x, c, 0.0)
    } else if h < 180.0 {
        (0.0, c, x)
    } else if h < 240.0 {
        (0.0, x, c)
    } else if h < 300.0 {
        (x, 0.0, c)
    } else {
        (c, 0.0, x)
    };
    let ch = |v: f64| ((v + m) * 255.0).round().clamp(0.0, 255.0) as u8;
    (ch(rp), ch(gp), ch(bp))
}

pub fn relative_luminance(rgb: (u8, u8, u8)) -> f64 {
    (0.2126 * rgb.0 as f64 + 0.7152 * rgb.1 as f64 + 0.0722 * rgb.2 as f64) / 255.0
}

fn round2(v: f64) -> f64 {
    (v * 100.0).round() / 100.0
}

// ---------------------------------------------------------------------------
// Palette generation
// ---------------------------------------------------------------------------

fn overlay_hue_shift(mood: &str) -> f64 {
    match mood {
        "energetic" => 15.0,
        "calm" => 210.0,
        "dark" => 0.0,
        _ => 40.0, // warm
    }
}

fn apply_mood(mood: &str, hue: f64, sat: f64, lig: f64) -> Result<(f64, f64, f64)> {
    Ok(match mood {
        "energetic" => (hue, clamp(sat * 1.35 + 0.10, 0.55, 1.0), clamp(lig, 0.42, 0.58)),
        "calm" => (hue, clamp(sat * 0.55, 0.10, 0.45), clamp(lig, 0.46, 0.64)),
        "dark" => (hue, clamp(sat * 0.90, 0.15, 0.85), clamp(lig, 0.16, 0.30)),
        "warm" => (hue % 72.0, clamp(sat * 1.10 + 0.05, 0.35, 1.0), clamp(lig, 0.40, 0.60)),
        other => return Err(anyhow!(
            "unknown mood {other:?}; expected one of {:?}",
            MOODS
        )),
    })
}

fn pick_primary(dominant: &[(String, f64)]) -> Result<String> {
    let mut candidates: Vec<&(String, f64)> = dominant.iter().collect();
    candidates.sort_by(|a, b| b.1.total_cmp(&a.1));
    candidates
        .iter()
        .find(|(hex, _)| !hex.is_empty())
        .map(|(hex, _)| hex.clone())
        .ok_or_else(|| anyhow!("dominant colors must contain at least one entry"))
}

/// Build a full palette from dominant colors and a mood.
///
/// Unknown moods fall back to "energetic"; an empty `dominant` list falls
/// back to a neutral gray primary. See [`try_generate_palette`] for errors.
pub fn generate_palette(dominant: &[(String, f64)], mood: &str) -> PaletteResult {
    let mood = if MOODS.contains(&mood) { mood } else { "energetic" };
    try_generate_palette(dominant, mood)
        .or_else(|_| try_generate_palette(&[(NEUTRAL_PRIMARY.to_string(), 100.0)], mood))
        .expect("default palette always builds")
}

const NEUTRAL_PRIMARY: &str = "#7A7A7A";

/// Fallible variant of [`generate_palette`] mirroring `palette_engine.py`.
pub fn try_generate_palette(dominant: &[(String, f64)], mood: &str) -> Result<PaletteResult> {
    if !MOODS.contains(&mood) {
        bail!("unknown mood {mood:?}; expected one of {MOODS:?}");
    }

    let primary_hex = pick_primary(dominant)?;
    let (hue, sat, lig) = rgb_to_hsl_tuple(hex_to_rgb(&primary_hex)?);
    let (hue, sat, lig) = apply_mood(mood, hue, sat, lig)?;

    let secondary_lig = clamp(lig + 0.06, 0.0, 0.92);
    let accent_sat = clamp(sat * 1.25 + 0.15, 0.55, 1.0);
    let accent_lig = clamp(lig, 0.42, 0.58);
    let overlay_lig = if mood == "dark" { 0.35 } else { 0.50 };

    let text_bg_rgb = hsl_to_rgb(hue, sat * 0.75, if mood == "dark" { 0.07 } else { 0.09 });
    let text_fg = if relative_luminance(text_bg_rgb) < 0.35 {
        "#FAFAFA"
    } else {
        "#161616"
    };

    Ok(PaletteResult {
        primary: rgb_to_hex_tuple(hsl_to_rgb(hue, sat, lig)),
        secondary: rgb_to_hex_tuple(hsl_to_rgb(
            (hue + 30.0) % 360.0,
            sat * 0.85,
            secondary_lig,
        )),
        accent: rgb_to_hex_tuple(hsl_to_rgb((hue + 180.0) % 360.0, accent_sat, accent_lig)),
        text_fg: text_fg.to_string(),
        text_bg: rgb_to_hex_tuple(text_bg_rgb),
        overlay_tint: rgb_to_hex_tuple(hsl_to_rgb(
            (hue + overlay_hue_shift(mood)) % 360.0,
            0.55,
            overlay_lig,
        )),
    })
}

fn rgb_to_hsl_tuple(rgb: (u8, u8, u8)) -> (f64, f64, f64) {
    rgb_to_hsl(rgb.0, rgb.1, rgb.2)
}

fn rgb_to_hex_tuple(rgb: (u8, u8, u8)) -> String {
    rgb_to_hex(rgb.0, rgb.1, rgb.2)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hsl_round_trip_primaries() {
        assert_eq!(rgb_to_hsl(255, 0, 0), (0.0, 1.0, 0.5));
        assert_eq!(rgb_to_hsl(0, 0, 0), (0.0, 0.0, 0.0));
        assert_eq!(hsl_to_rgb(120.0, 1.0, 0.5), (0, 255, 0));
        assert_eq!(hsl_to_rgb(240.0, 1.0, 0.5), (0, 0, 255));
    }

    #[test]
    fn hex_parsing_variants() {
        assert_eq!(hex_to_rgb("#FF8000").unwrap(), (255, 128, 0));
        assert_eq!(hex_to_rgb("#f80").unwrap(), (255, 136, 0));
        assert_eq!(hex_to_rgb("FF8000").unwrap(), (255, 128, 0));
        assert!(hex_to_rgb("#XYZ").is_err());
    }

    #[test]
    fn palette_complementary_and_analogous() {
        let p = generate_palette(
            &[("#0000FF".to_string(), 80.0), ("#FFFFFF".to_string(), 20.0)],
            "energetic",
        );
        assert!(p.primary.starts_with('#'));
        assert_ne!(p.primary, p.accent);
        assert_ne!(p.secondary, p.accent);
        assert!(MOODS.contains(&"energetic"));
    }

    #[test]
    fn unknown_mood_falls_back_not_panics() {
        let p = generate_palette(&[("#336699".to_string(), 100.0)], "nope");
        assert_eq!(p.text_fg.len(), 7);
    }

    #[test]
    fn empty_dominant_yields_neutral() {
        let p = generate_palette(&[], "calm");
        let p2 = generate_palette(&[], "calm");
        // gray primary gets the calm saturation floor applied — deterministic
        assert_eq!(p.primary, p2.primary);
        assert_eq!(p.primary, rgb_to_hex_tuple(hsl_to_rgb(
            rgb_to_hsl(122, 122, 122).0, 0.10,
            clamp(rgb_to_hsl(122, 122, 122).2, 0.46, 0.64),
        )));
    }

    #[test]
    fn uniform_pixels_single_dominant() {
        let mut px = Vec::new();
        for _ in 0..1000 {
            px.extend_from_slice(&[200, 40, 40]);
        }
        let mut clusters = merge_clusters(dominant_from_buckets(&px));
        assert_eq!(clusters.len(), 1);
        let c = clusters.pop().unwrap();
        assert_eq!(c.0, (200, 40, 40));
        assert!((c.1 - 1000.0).abs() < f64::EPSILON);
    }
}
