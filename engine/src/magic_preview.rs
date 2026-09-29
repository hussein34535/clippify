//! magic_preview.rs — Fast low-res preview clip generation.
//!
//! Renders 480p ultrafast silent previews of candidate clips so the UI can
//! offer scrub-before-render. Previews run in parallel behind a semaphore
//! (one ffmpeg process per core, capped), each followed by a small JPEG
//! thumbnail grabbed at the clip midpoint.

use anyhow::Context;
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::Arc;
use tokio::sync::Semaphore;

use crate::director::ClipCandidate;

/// A rendered low-res preview plus its representative thumbnail.
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct PreviewClip {
    pub path: String,
    pub start_sec: f64,
    pub end_sec: f64,
    /// Empty string when thumbnail extraction failed (non-fatal).
    pub thumbnail_path: String,
}

/// Max concurrent preview encodes (ffmpeg is CPU-hungry even at 480p).
const MAX_PARALLEL: usize = 4;

/// Build ffmpeg arguments for a fast silent 480p preview of `[start, end]`.
///
/// Design goals: instant startup (`-ss` before `-i`), x264 `ultrafast`,
/// CRF 30, baseline profile for broad player support, no audio
/// (`-an`), `+faststart` so the file is web-streamable immediately.
pub fn preview_args(
    _ffmpeg_path: &str,
    video_path: &str,
    start_sec: f64,
    end_sec: f64,
    out_path: &str,
) -> Vec<String> {
    let start = format!("{:.3}", start_sec.max(0.0));
    let end = format!("{:.3}", end_sec.max(start_sec + 0.1));
    vec![
        "-y".into(),
        "-ss".into(),
        start,
        "-to".into(),
        end,
        "-i".into(),
        video_path.into(),
        "-vf".into(),
        "scale=-2:480".into(),
        "-c:v".into(),
        "libx264".into(),
        "-preset".into(),
        "ultrafast".into(),
        "-crf".into(),
        "30".into(),
        "-profile:v".into(),
        "baseline".into(),
        "-an".into(),
        "-movflags".into(),
        "+faststart".into(),
        out_path.into(),
    ]
}

/// Generate previews for every clip candidate in parallel.
///
/// Failures are skipped silently (matching `RenderPipeline` semantics);
/// successful entries keep the input order of `clips`.
pub async fn generate_previews(
    ffmpeg: &str,
    video_path: &str,
    clips: &[ClipCandidate],
    out_dir: &str,
) -> Vec<PreviewClip> {
    if clips.is_empty() {
        return Vec::new();
    }
    tokio::fs::create_dir_all(out_dir)
        .await
        .context("failed to create preview output dir")
        .ok();

    let sem = Arc::new(Semaphore::new(MAX_PARALLEL));
    let mut handles = Vec::with_capacity(clips.len());

    for clip in clips {
        let permit = match sem.clone().acquire_owned().await {
            Ok(p) => p,
            Err(_) => break,
        };
        let ffmpeg = ffmpeg.to_string();
        let video = video_path.to_string();
        let out_dir = out_dir.to_string();
        let clip = clip.clone();

        handles.push(tokio::spawn(async move {
            let _permit = permit;
            let out_path = format!("{}/preview_{:03}.mp4", out_dir, clip.index);

            let args = preview_args(&ffmpeg, &video, clip.start_sec, clip.end_sec, &out_path);
            let status = tokio::process::Command::new(&ffmpeg).args(&args).output().await;
            let ok = matches!(&status, Ok(o) if o.status.success())
                && Path::new(&out_path).exists();
            if !ok {
                return None;
            }

            // Midpoint thumbnail (non-fatal on failure).
            let mid = (clip.start_sec + clip.end_sec) / 2.0;
            let thumb_path = format!("{}/preview_{:03}.jpg", out_dir, clip.index);
            let thumb_ok = tokio::process::Command::new(&ffmpeg)
                .args([
                    "-y",
                    "-ss",
                    &format!("{:.3}", mid),
                    "-i",
                    &video,
                    "-frames:v",
                    "1",
                    "-vf",
                    "scale=160:-2",
                    "-q:v",
                    "5",
                    &thumb_path,
                ])
                .output()
                .await;

            let thumbnail_path = match thumb_ok {
                Ok(o) if o.status.success() && Path::new(&thumb_path).exists() => thumb_path,
                _ => String::new(),
            };

            Some(PreviewClip {
                path: out_path,
                start_sec: clip.start_sec,
                end_sec: clip.end_sec,
                thumbnail_path,
            })
        }));
    }

    let mut results = Vec::new();
    for h in handles {
        if let Ok(Some(clip)) = h.await {
            results.push(clip);
        }
    }
    results
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preview_args_are_fast_and_silent() {
        let args = preview_args("ffmpeg", "in.mp4", 12.5, 42.75, "out.mp4");
        let s: Vec<&str> = args.iter().map(|s| s.as_str()).collect();

        // Fast seek before -i, then -to after? (-to sits before -i as an
        // input option in modern ffmpeg; both positions are accepted.)
        assert_eq!(s[1], "-ss");
        assert_eq!(s[2], "12.500");
        assert!(s.contains(&"ultrafast"));
        assert!(s.contains(&"-an"));
        assert!(s.contains(&"scale=-2:480"));
        assert_eq!(*s.last().unwrap(), "out.mp4");
    }

    #[test]
    fn negative_start_is_clamped() {
        let args = preview_args("ffmpeg", "v.mp4", -3.0, 5.0, "o.mp4");
        assert_eq!(args[2], "0.000");
    }
}
