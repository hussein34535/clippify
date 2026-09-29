/// Whisper transcription — shells out to whisper.cpp binary if available.
/// Falls back to backend /api/transcribe when whisper-cli is absent.
use anyhow::{Context, Result};

use crate::types::{TranscribedSegment, TranscribedWord};

pub struct Transcriber {
    pub whisper_exe: Option<String>,
    pub model_path: Option<String>,
}

impl Transcriber {
    pub fn new() -> Self {
        let whisper_exe = Self::resolve_whisper();
        let model_path = std::env::var("WHISPER_MODEL_PATH").ok();
        Transcriber {
            whisper_exe,
            model_path,
        }
    }

    fn resolve_whisper() -> Option<String> {
        // 1) next to this binary
        if let Ok(exe) = std::env::current_exe() {
            let dir = exe.parent()?;
            let candidate = dir.join("whisper-cli.exe");
            if candidate.exists() {
                return Some(candidate.to_string_lossy().to_string());
            }
        }
        // 2) PATH
        if let Ok(output) = std::process::Command::new("where")
            .arg("whisper-cli")
            .output()
        {
            if output.status.success() {
                let p = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !p.is_empty() {
                    return Some(p);
                }
            }
        }
        None
    }

    pub fn is_available(&self) -> bool {
        self.whisper_exe.is_some() && self.model_path.is_some()
    }

    /// Transcribe audio/video → segments with word-level timestamps.
    /// Requires whisper.cpp binary + ggml model.
    pub async fn transcribe(&self, media_path: &str) -> Result<Vec<TranscribedSegment>> {
        let exe = self
            .whisper_exe
            .as_ref()
            .context("whisper-cli not found")?;
        let model = self
            .model_path
            .as_ref()
            .context("WHISPER_MODEL_PATH not set")?;

        let output = tokio::process::Command::new(exe)
            .args([
                "-m", model,
                "-f", media_path,
                "--output-json",
                "--print-progress", "false",
            ])
            .output()
            .await
            .context("whisper-cli failed")?;

        let stdout = String::from_utf8_lossy(&output.stdout);
        Self::parse_whisper_output(&stdout)
    }

    /// Parse whisper.cpp JSON output into segments.
    pub fn parse_whisper_output(json_str: &str) -> Result<Vec<TranscribedSegment>> {
        let data: serde_json::Value = serde_json::from_str(json_str)
            .context("invalid whisper JSON")?;
        let mut segments = Vec::new();

        if let Some(toks) = data["transcription"].as_array() {
            let mut current_text = String::new();
            let mut current_start = 0.0;
            let mut current_end = 0.0;
            let mut words = Vec::new();

            for tok in toks {
                let text = tok["text"].as_str().unwrap_or("").to_string();
                let start = tok["offsets"]["from"].as_i64().unwrap_or(0) as f64 / 1000.0;
                let end = tok["offsets"]["to"].as_i64().unwrap_or(0) as f64 / 1000.0;

                words.push(TranscribedWord {
                    text: text.trim().to_string(),
                    start,
                    end,
                });
                current_text.push_str(&text);
                current_end = end;

                // segment break on sentence end
                if text.contains('.') || text.contains('!') || text.contains('?') {
                    if !current_text.trim().is_empty() {
                        segments.push(TranscribedSegment {
                            text: current_text.trim().to_string(),
                            start: current_start,
                            end: current_end,
                            words: std::mem::take(&mut words),
                        });
                    }
                    current_text.clear();
                    current_start = end;
                }
            }
            if !current_text.trim().is_empty() {
                segments.push(TranscribedSegment {
                    text: current_text.trim().to_string(),
                    start: current_start,
                    end: current_end,
                    words,
                });
            }
        }
        Ok(segments)
    }
}
