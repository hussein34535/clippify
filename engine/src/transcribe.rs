//! Local transcription using the installed whisper.cpp CLI and model.

use anyhow::{ensure, Context, Result};
use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;
use tokio::io::AsyncReadExt;
use tokio::process::Command;
use tokio::time::{timeout_at, Instant};

use crate::types::TranscribedSegment;

const TRANSCRIPTION_TIMEOUT: Duration = Duration::from_secs(15 * 60);

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
        if let Some(path) = std::env::var_os("CLIPPIFY_WHISPER_EXE").map(PathBuf::from) {
            if path.is_absolute() && path.is_file() {
                return Some(path.to_string_lossy().into_owned());
            }
        }
        let filename = if cfg!(windows) {
            "whisper-cli.exe"
        } else {
            "whisper-cli"
        };
        if let Ok(exe) = std::env::current_exe() {
            if let Some(dir) = exe.parent() {
                let candidate = dir.join(filename);
                if candidate.is_file() {
                    return Some(candidate.to_string_lossy().into_owned());
                }
            }
        }

        let path = std::env::var_os("PATH").unwrap_or_default();
        let current_dir = std::env::current_dir().ok();
        current_dir
            .into_iter()
            .filter(|_| cfg!(windows))
            .chain(std::env::split_paths(&path))
            .map(|dir| dir.join(filename))
            .find(|candidate| candidate.is_file())
            .map(|candidate| candidate.to_string_lossy().into_owned())
    }

    pub fn is_available(&self) -> bool {
        self.whisper_exe.is_some() && self.model_path.is_some()
    }

    /// Transcribe audio or video using the default media engine.
    pub async fn transcribe(&self, media_path: &str) -> Result<Vec<TranscribedSegment>> {
        self.transcribe_local(&crate::media::MediaEngine::new(), media_path, "en")
            .await
    }

    /// Extract mono audio and transcribe it locally with the configured Whisper model.
    pub async fn transcribe_short(
        &self,
        media: &crate::media::MediaEngine,
        path: &str,
    ) -> anyhow::Result<Vec<TranscribedSegment>> {
        self.transcribe_local(media, path, "auto").await
    }

    async fn transcribe_local(
        &self,
        media: &crate::media::MediaEngine,
        path: &str,
        language: &str,
    ) -> Result<Vec<TranscribedSegment>> {
        let exe = self
            .whisper_exe
            .as_deref()
            .context("whisper-cli not found")?;
        let model = self
            .model_path
            .as_deref()
            .context("WHISPER_MODEL_PATH not set")?;

        let temp = TranscriptionDirectory::create()?;
        let wav = temp.0.join("audio.wav");
        let output_prefix = temp.0.join("transcript");
        let deadline = Instant::now() + TRANSCRIPTION_TIMEOUT;

        // MediaEngine's Windows PATH lookup can return multiple matches.
        let ffmpeg = media
            .ffmpeg_path
            .lines()
            .next()
            .unwrap_or(&media.ffmpeg_path);
        let mut extract = Command::new(ffmpeg);
        extract
            .args([
                "-hide_banner",
                "-loglevel",
                "error",
                "-nostdin",
                "-protocol_whitelist",
                "file",
                "-i",
                path,
                "-map",
                "0:a:0",
                "-ac",
                "1",
                "-ar",
                "16000",
                "-c:a",
                "pcm_s16le",
            ])
            .arg(&wav);
        run_transcription_command(&mut extract, "FFmpeg audio extraction", deadline).await?;

        let mut whisper = Command::new(exe);
        whisper.args(["-m", model, "-l", language, "-f"]).arg(&wav);
        let short = language == "auto";
        if short {
            let vad_model = PathBuf::from(model).with_file_name("ggml-silero-v6.2.0.bin");
            if vad_model.is_file() {
                whisper
                    .args(["--vad", "-vm"])
                    .arg(vad_model)
                    .args(["-vt", "0.52", "-vspd", "280", "-vsd", "220", "-vp", "140"]);
            }
            whisper.args(["-mc", "0", "-nf", "-ml", "48", "-sow", "-ojf"]);
        } else {
            whisper.arg("-oj");
        }
        whisper.arg("-of").arg(&output_prefix);
        run_transcription_command(&mut whisper, "whisper-cli", deadline).await?;

        let read_json = tokio::fs::read_to_string(output_prefix.with_extension("json"));
        let json = timeout_at(deadline, read_json)
            .await
            .context("reading whisper-cli JSON output timed out")?
            .context("could not read whisper-cli JSON output")?;
        if short {
            Self::parse_output(&json, true)
        } else {
            Self::parse_whisper_output(&json)
        }
    }

    /// Parse whisper.cpp JSON output into segments.
    pub fn parse_whisper_output(json_str: &str) -> Result<Vec<TranscribedSegment>> {
        Self::parse_output(json_str, false)
    }

    fn parse_output(json_str: &str, short: bool) -> Result<Vec<TranscribedSegment>> {
        let data: serde_json::Value =
            serde_json::from_str(json_str).context("invalid whisper JSON")?;
        let transcription = data["transcription"]
            .as_array()
            .context("whisper JSON is missing a transcription array")?;
        let mut segments = Vec::with_capacity(transcription.len());
        let mut uncertain = 0.0;

        for (index, entry) in transcription.iter().enumerate() {
            let text = entry["text"]
                .as_str()
                .with_context(|| format!("missing text in whisper segment {}", index + 1))?
                .trim();
            if text.is_empty() {
                continue;
            }

            let offsets = &entry["offsets"];
            let timestamps = &entry["timestamps"];
            let (start, end) = offsets["from"]
                .as_u64()
                .zip(offsets["to"].as_u64())
                .filter(|(start, end)| start <= end)
                .map(|(start, end)| (start as f64 / 1000.0, end as f64 / 1000.0))
                .or_else(|| {
                    let start = parse_timestamp(timestamps["from"].as_str()?)?;
                    let end = parse_timestamp(timestamps["to"].as_str()?)?;
                    (start <= end).then_some((start, end))
                })
                .with_context(|| format!("invalid timing in whisper segment {}", index + 1))?;

            if short && !trust_short_caption(entry, end - start) {
                uncertain += end - start;
                continue;
            }
            segments.push(TranscribedSegment {
                text: text.to_string(),
                start,
                end,
                words: Vec::new(),
            });
        }
        if short && uncertain >= 3.0 {
            let trusted: f64 = segments.iter().map(|part| part.end - part.start).sum();
            if trusted < (trusted + uncertain) * 0.55 {
                // Isolated fragments in a mostly unintelligible recording often still score high.
                return Ok(segments
                    .chunk_by(|left, right| right.start - left.end <= 0.65)
                    .filter(|run| run.iter().map(|part| part.end - part.start).sum::<f64>() >= 4.0)
                    .flatten()
                    .cloned()
                    .collect());
            }
        }
        Ok(segments)
    }
}

fn trust_short_caption(entry: &serde_json::Value, duration: f64) -> bool {
    if !(0.24..=6.0).contains(&duration) {
        return false;
    }
    let Some(tokens) = entry["tokens"].as_array() else {
        return false;
    };
    let probabilities = tokens.iter().filter_map(|token| {
        let text = token["text"].as_str()?.trim();
        if text.starts_with("[_") || !text.chars().any(char::is_alphanumeric) {
            return None;
        }
        token["p"].as_f64().filter(|p| (0.0..=1.0).contains(p))
    });
    let (count, sum) = probabilities.fold((0, 0.0), |(count, sum), p| (count + 1, sum + p));
    count > 0 && sum >= 0.62 * f64::from(count)
}

fn parse_timestamp(timestamp: &str) -> Option<f64> {
    let (hours, rest) = timestamp.split_once(':')?;
    let (minutes, rest) = rest.split_once(':')?;
    let (seconds, millis) = rest.split_once([',', '.'])?;
    if millis.len() != 3 || !millis.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    let hours: u64 = hours.parse().ok()?;
    let minutes: u32 = minutes.parse().ok()?;
    let seconds: u32 = seconds.parse().ok()?;
    let millis: u32 = millis.parse().ok()?;
    (minutes < 60 && seconds < 60).then(|| {
        hours as f64 * 3600.0 + f64::from(minutes * 60 + seconds) + f64::from(millis) / 1000.0
    })
}

async fn run_transcription_command(
    command: &mut Command,
    stage: &str,
    deadline: Instant,
) -> Result<()> {
    let mut child = command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .with_context(|| format!("could not start {stage}"))?;
    let mut stderr = child.stderr.take().expect("stderr is piped");
    let mut diagnostics = Vec::new();
    let result = timeout_at(deadline, async {
        tokio::try_join!(child.wait(), stderr.read_to_end(&mut diagnostics))
    })
    .await;
    let (status, _) = match result {
        Ok(Ok(output)) => output,
        failure => {
            // Wait for termination before deleting output files, which can be locked on Windows.
            let _ = child.kill().await;
            failure
                .with_context(|| format!("{stage} timed out"))?
                .with_context(|| format!("could not wait for {stage}"))?
        }
    };
    ensure!(
        status.success(),
        "{stage} exited with {status}: {}",
        String::from_utf8_lossy(&diagnostics).trim()
    );
    Ok(())
}

struct TranscriptionDirectory(PathBuf);

impl TranscriptionDirectory {
    fn create() -> Result<Self> {
        let path =
            std::env::temp_dir().join(format!("clippify-transcribe-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir(&path).context("could not create transcription temporary directory")?;
        Ok(Self(path))
    }
}

impl Drop for TranscriptionDirectory {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn short_discards_low_confidence_and_implausibly_long_caption_spans() {
        let result = Transcriber::parse_output(r#"{
            "transcription": [
                {"text":"افتح الباب", "offsets":{"from":0,"to":4100}, "tokens":[{"text":"افتح", "p":0.91},{"text":"الباب", "p":0.85}]},
                {"text":"كلام غير واضح", "offsets":{"from":4200,"to":5750}, "tokens":[{"text":"كلام", "p":0.42},{"text":"[_TT_010]", "p":0.99}]},
                {"text":"جملة طويلة بدون توقيت موثوق", "offsets":{"from":5800,"to":16500}, "tokens":[{"text":"جملة", "p":0.95}]}
            ]
        }"#, true).unwrap();
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].text, "افتح الباب");
    }

    #[test]
    fn short_rejects_isolated_fragments_when_most_of_the_speech_is_unreliable() {
        let result = Transcriber::parse_output(r#"{
            "transcription": [
                {"text":"unclear sound", "offsets":{"from":0,"to":4000}, "tokens":[{"text":"unclear", "p":0.4}]},
                {"text":"isolated high score", "offsets":{"from":4400,"to":6000}, "tokens":[{"text":"isolated", "p":0.91}]}
            ]
        }"#, true).unwrap();
        assert!(result.is_empty());
    }

    #[test]
    fn parses_each_segment_from_its_own_millisecond_offsets() {
        let segments = Transcriber::parse_whisper_output(
            r#"{
                "transcription": [
                    {"offsets": {"from": 1250, "to": 2500}, "text": " First phrase"},
                    {"offsets": {"from": 3500, "to": 4500}, "text": " second phrase! "}
                ]
            }"#,
        )
        .unwrap();

        assert_eq!(segments.len(), 2);
        assert_eq!(segments[0].text, "First phrase");
        assert_eq!((segments[0].start, segments[0].end), (1.25, 2.5));
        assert_eq!(segments[1].text, "second phrase!");
        assert_eq!((segments[1].start, segments[1].end), (3.5, 4.5));
        assert!(segments.iter().all(|segment| segment.words.is_empty()));
    }

    #[test]
    fn falls_back_to_clock_timestamps_without_mixing_sources() {
        let segments = Transcriber::parse_whisper_output(
            r#"{
                "transcription": [{
                    "offsets": {"from": 0},
                    "timestamps": {"from": "01:02:03,250", "to": "01:02:04.500"},
                    "text": " Hour mark"
                }]
            }"#,
        )
        .unwrap();

        assert_eq!(segments.len(), 1);
        assert_eq!((segments[0].start, segments[0].end), (3723.25, 3724.5));
    }

    #[test]
    fn accepts_an_empty_transcription_and_skips_blank_segments() {
        for json in [
            r#"{"transcription": []}"#,
            r#"{"transcription": [{"text": "   "}]}"#,
        ] {
            assert!(Transcriber::parse_whisper_output(json).unwrap().is_empty());
        }
    }

    #[test]
    fn rejects_invalid_transcriptions_and_timing() {
        for json in [
            "not JSON",
            "{}",
            r#"{"transcription": [{"text": "Missing timing"}]}"#,
            r#"{"transcription": [{"text": "Reversed", "offsets": {"from": 3, "to": 2}}]}"#,
            r#"{"transcription": [{"text": "Negative", "offsets": {"from": -1, "to": 2}}]}"#,
            r#"{"transcription": [{"text": "Bad clock", "timestamps": {"from": "00:00:60,000", "to": "00:01:01,000"}}]}"#,
        ] {
            assert!(Transcriber::parse_whisper_output(json).is_err(), "{json}");
        }
    }

    #[test]
    fn isolates_and_cleans_temporary_outputs() {
        let first = TranscriptionDirectory::create().unwrap();
        let second = TranscriptionDirectory::create().unwrap();
        let first_path = first.0.clone();
        assert_ne!(first_path, second.0);
        std::fs::write(first_path.join("audio.wav"), b"partial audio").unwrap();
        std::fs::write(first_path.join("transcript.json"), b"partial JSON").unwrap();

        drop(first);

        assert!(!first_path.exists());
        assert!(second.0.is_dir());
    }

    #[cfg(any(unix, windows))]
    #[tokio::test]
    async fn reports_nonzero_exit_with_diagnostics() {
        #[cfg(windows)]
        let mut command = Command::new("powershell.exe");
        #[cfg(windows)]
        command.args([
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "[Console]::Error.WriteLine('fixture error'); exit 7",
        ]);
        #[cfg(unix)]
        let mut command = Command::new("sh");
        #[cfg(unix)]
        command.args(["-c", "echo 'fixture error' >&2; exit 7"]);

        let error = run_transcription_command(
            &mut command,
            "test process",
            Instant::now() + Duration::from_secs(10),
        )
        .await
        .unwrap_err()
        .to_string();

        assert!(error.contains("test process exited"), "{error}");
        assert!(error.contains("fixture error"), "{error}");
    }

    #[cfg(any(unix, windows))]
    #[tokio::test]
    async fn stops_a_process_that_exceeds_the_deadline() {
        #[cfg(windows)]
        let mut command = Command::new("powershell.exe");
        #[cfg(windows)]
        command.args([
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "Start-Sleep -Seconds 30",
        ]);
        #[cfg(unix)]
        let mut command = Command::new("sleep");
        #[cfg(unix)]
        command.arg("30");

        let error = run_transcription_command(
            &mut command,
            "test process",
            Instant::now() + Duration::from_millis(50),
        )
        .await
        .unwrap_err();

        assert_eq!(error.to_string(), "test process timed out");
    }
}
