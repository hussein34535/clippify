/// FFmpeg wrapper — all media operations via the bundled/system ffmpeg binary.
use anyhow::{Context, Result};
use std::path::Path;
use std::process::Stdio;

use crate::types::{Silence, Thumb};

pub struct MediaEngine {
    pub ffmpeg_path: String,
}

impl MediaEngine {
    pub fn new() -> Self {
        let ffmpeg_path = Self::resolve();
        MediaEngine { ffmpeg_path }
    }

    fn resolve() -> String {
        // 1) env override
        if let Ok(p) = std::env::var("CLIPPIFY_FFMPEG") {
            if Path::new(&p).exists() {
                return p;
            }
        }
        // 2) next to this binary (bundled distribution)
        if let Ok(exe) = std::env::current_exe() {
            if let Some(dir) = exe.parent() {
                let candidate = dir.join("ffmpeg.exe");
                if candidate.exists() {
                    return candidate.to_string_lossy().to_string();
                }
            }
        }
        // 3) PATH
        if let Ok(output) = std::process::Command::new("where")
            .arg("ffmpeg")
            .output()
        {
            if output.status.success() {
                let p = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !p.is_empty() {
                    return p;
                }
            }
        }
        // 4) imageio fallback (Python site-packages)
        let home = std::env::var("USERPROFILE").unwrap_or_default();
        let sp = format!("{}\\AppData\\Local\\Python", home);
        if let Ok(read) = std::fs::read_dir(&sp) {
            for entry in read.flatten() {
                let probe = entry
                    .path()
                    .join("site-packages\\imageio_ffmpeg\\binaries");
                if let Ok(bins) = std::fs::read_dir(&probe) {
                    for b in bins.flatten() {
                        let name = b.file_name().to_string_lossy().to_string();
                        if name.starts_with("ffmpeg-") && name.ends_with(".exe") {
                            return b.path().to_string_lossy().to_string();
                        }
                    }
                }
            }
        }
        "ffmpeg".to_string()
    }

    pub async fn probe_duration(&self, media_path: &str) -> Result<f64> {
        let output = tokio::process::Command::new(&self.ffmpeg_path)
            .args(["-hide_banner", "-i", media_path, "-f", "null", "-"])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await
            .context("ffmpeg probe failed")?;

        let blob = String::from_utf8_lossy(&output.stderr);
        let re = regex::Regex::new(r"Duration:\s*(\d+):(\d+):(\d+\.?\d*)")?;
        if let Some(cap) = re.captures(&blob) {
            let h: f64 = cap[1].parse()?;
            let m: f64 = cap[2].parse()?;
            let s: f64 = cap[3].parse()?;
            return Ok(h * 3600.0 + m * 60.0 + s);
        }
        // fallback: last time= line
        let re_time = regex::Regex::new(r"time=(\d+):(\d+):(\d+\.?\d*)")?;
        let mut dur = 0.0f64;
        for cap in re_time.captures_iter(&blob) {
            let h: f64 = cap[1].parse()?;
            let m: f64 = cap[2].parse()?;
            let s: f64 = cap[3].parse()?;
            dur = dur.max(h * 3600.0 + m * 60.0 + s);
        }
        if dur > 0.0 {
            Ok(dur)
        } else {
            Err(anyhow::anyhow!("could not determine duration"))
        }
    }

    pub async fn detect_silences(
        &self,
        media_path: &str,
        noise_db: f64,
        min_dur: f64,
    ) -> Result<Vec<Silence>> {
        let filter = format!(
            "silencedetect=noise={}dB:d={:.2}",
            noise_db, min_dur
        );
        let output = tokio::process::Command::new(&self.ffmpeg_path)
            .args(["-hide_banner", "-i", media_path, "-af", &filter, "-f", "null", "-"])
            .output()
            .await
            .context("silencedetect failed")?;

        let blob = String::from_utf8_lossy(&output.stderr);
        let re_start = regex::Regex::new(r"silence_start:\s*(-?[\d.]+)")?;
        let re_end = regex::Regex::new(r"silence_end:\s*([\d.]+)")?;

        let starts: Vec<f64> = re_start
            .captures_iter(&blob)
            .filter_map(|c| c[1].parse().ok())
            .collect();
        let ends: Vec<f64> = re_end
            .captures_iter(&blob)
            .filter_map(|c| c[1].parse().ok())
            .collect();

        let mut silences = Vec::new();
        for (i, &s) in starts.iter().enumerate() {
            let e = ends.get(i).copied().unwrap_or(s);
            if e > s {
                silences.push(Silence {
                    start: if s < 0.0 { 0.0 } else { s },
                    end: e,
                });
            }
        }
        Ok(silences)
    }

    pub async fn extract_thumbnails(
        &self,
        video_path: &str,
        count: usize,
        out_dir: &str,
    ) -> Result<Vec<Thumb>> {
        let dur = self.probe_duration(video_path).await?;
        tokio::fs::create_dir_all(out_dir).await?;
        let count = count.clamp(2, 12);
        let mut thumbs = Vec::new();

        for i in 0..count {
            let ts = dur * (i as f64 + 0.5) / count as f64;
            let ts = ts.min(dur - 0.1).max(0.0);
            let out = format!("{}/{}.jpg", out_dir, i);
            let status = tokio::process::Command::new(&self.ffmpeg_path)
                .args([
                    "-y",
                    "-ss", &format!("{:.2}", ts),
                    "-i", video_path,
                    "-frames:v", "1",
                    "-vf", "scale=160:-2",
                    "-q:v", "5",
                    &out,
                ])
                .output()
                .await;

            if let Ok(o) = status {
                if o.status.success() && Path::new(&out).exists() {
                    thumbs.push(Thumb {
                        index: i,
                        path: out,
                        timestamp_sec: ts,
                    });
                }
            }
        }
        Ok(thumbs)
    }
}

// glob crate shim (avoid adding a dependency just for one call)
mod glob {
    pub struct Paths(Vec<Result<std::path::PathBuf, ()>>);
    pub struct PathsError;

    impl Iterator for Paths {
        type Item = Result<std::path::PathBuf, ()>;
        fn next(&mut self) -> Option<Self::Item> {
            self.0.pop()
        }
    }

    pub fn glob(pattern: &str) -> Result<Paths, ()> {
        let mut results = Vec::new();
        // simple wildcard match for the imageio pattern
        let parts: Vec<&str> = pattern.split('*').collect();
        if parts.len() == 2 {
            let prefix = parts[0];
            let suffix = parts[1];
            let base = std::path::Path::new(prefix);
            if let Some(parent) = base.parent() {
                if let Ok(entries) = std::fs::read_dir(parent) {
                    for entry in entries.flatten() {
                        let path = entry.path().join("binaries");
                        if let Ok(binaries) = std::fs::read_dir(&path) {
                            for b in binaries.flatten() {
                                let name = b.file_name().to_string_lossy().to_string();
                                if name.starts_with("ffmpeg-") && name.ends_with(".exe") {
                                    results.push(Ok(b.path()));
                                }
                            }
                        }
                    }
                }
            }
        }
        Ok(Paths(results))
    }
}
