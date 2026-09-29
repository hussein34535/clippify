/// Segment-parallel render pipeline â€” splits timeline into segments,
/// renders concurrently with hardware acceleration, then concatenates.
use anyhow::{Context, Result};
use std::path::Path;
use tokio::sync::Semaphore;

use crate::media::MediaEngine;
use crate::types::RenderRequest;

pub struct RenderPipeline {
    pub media: MediaEngine,
    pub max_workers: usize,
}

impl RenderPipeline {
    pub fn new() -> Self {
        let max_workers = std::thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(4);
        RenderPipeline {
            media: MediaEngine::new(),
            max_workers,
        }
    }

    /// Detect hardware acceleration: nvenc > qsv > vaapi > x264
    pub async fn detect_accel(&self) -> String {
        let encoders = tokio::process::Command::new(&self.media.ffmpeg_path)
            .args(["-hide_banner", "-encoders"])
            .output()
            .await;
        if let Ok(out) = encoders {
            let blob = String::from_utf8_lossy(&out.stdout);
            if blob.contains("h264_nvenc") {
                return "h264_nvenc".into();
            }
            if blob.contains("h264_qsv") {
                return "h264_qsv".into();
            }
            if blob.contains("h264_vaapi") {
                return "h264_vaapi".into();
            }
        }
        "libx264".into()
    }

    pub async fn render(&self, req: &RenderRequest) -> Result<Vec<String>> {
        tokio::fs::create_dir_all(&req.output_dir).await?;
        let codec = self.detect_accel().await;
        let crf_args: Vec<&str> = if codec == "libx264" {
            vec!["-crf", "23", "-preset", "veryfast"]
        } else {
            vec!["-cq", "23"]
        };

        let sem = std::sync::Arc::new(Semaphore::new(self.max_workers));
        let mut handles = Vec::new();

        for clip in &req.clips {
            let permit = sem.clone().acquire_owned().await?;
            let codec = codec.clone();
            let crf_args = crf_args.clone();
            let ffmpeg = self.media.ffmpeg_path.clone();
            let video = req.video_path.clone();
            let out_dir = req.output_dir.clone();
            let clip_index = clip.index;
            let clip_start = clip.start_sec;
            let clip_end = clip.end_sec;

            let handle = tokio::spawn(async move {
                let _permit = permit;
                let out_path = format!(
                    "{}/clip_{:03}_{}.mp4",
                    out_dir,
                    clip_index,
                    codec.replace("h264_", "")
                );
                let ss = format!("{:.3}", clip_start);
                let to = format!("{:.3}", clip_end);
                let scale = format!("scale=1080:-2");

                let status = tokio::process::Command::new(&ffmpeg)
                    .args([
                        "-y", "-ss", &ss, "-to", &to, "-i", &video,
                        "-vf", &scale,
                        "-c:v", &codec,
                    ])
                    .args(&crf_args)
                    .args(["-c:a", "aac", "-b:a", "128k"])
                    .arg(&out_path)
                    .output()
                    .await;

                if let Ok(o) = status {
                    if o.status.success() && Path::new(&out_path).exists() {
                        return Some(out_path);
                    }
                }
                None
            });
            handles.push(handle);
        }

        let mut results = Vec::new();
        for h in handles {
            if let Ok(Some(path)) = h.await {
                results.push(path);
            }
        }
        Ok(results)
    }

    /// Concatenate rendered clips into one file.
    pub async fn compile(&self, clip_paths: &[String], output_path: &str) -> Result<String> {
        if clip_paths.is_empty() {
            return Err(anyhow::anyhow!("no clips to compile"));
        }
        let list_file = Path::new(output_path)
            .parent()
            .unwrap_or(Path::new("."))
            .join("concat_list.txt");
        let mut content = String::new();
        for p in clip_paths {
            content.push_str(&format!("file '{}'\n", p.replace('\'', "'\\''")));
        }
        tokio::fs::write(&list_file, &content).await?;

        let status = tokio::process::Command::new(&self.media.ffmpeg_path)
            .args([
                "-y", "-f", "concat", "-safe", "0", "-i",
                list_file.to_str().unwrap(),
                "-c", "copy", output_path,
            ])
            .output()
            .await
            .context("concat failed")?;

        if !status.status.success() {
            return Err(anyhow::anyhow!(
                "concat error: {}",
                String::from_utf8_lossy(&status.stderr)
            ));
        }
        Ok(output_path.to_string())
    }
}


