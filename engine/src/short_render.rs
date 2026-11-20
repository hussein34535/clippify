use std::fmt::Write;
use std::path::{Component, Path, PathBuf};
use std::process::Output;
use std::time::Duration;

use anyhow::{bail, ensure, Context, Result};
use tokio::process::Command;
use uuid::Uuid;

use crate::media::MediaEngine;
use crate::short_creative::{self, output_time, CreativeEdit, Span};
use crate::short_plan::{Accent, CaptionMotion, Framing, Grade, Transition, Treatment, Zoom};
use crate::sound_forge::SoundForge;
use crate::types::{RenderRequest, TranscribedSegment};

const FPS: f64 = 30.0;
const OUTPUT_NAME: &str = "clip_000.mp4";
// Use display aspect ratio after FFmpeg's autorotation, including anamorphic inputs.
const FIT_VIDEO: &str = "fps=30:start_time=0,\
    scale=w='max(2,trunc(min(1080,1920*dar)/2)*2)':\
    h='max(2,trunc(min(1920,1080/dar)/2)*2)':flags=lanczos,\
    setsar=1,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=0x101014";
const FILL_VIDEO: &str = "scale=w='max(1080,ceil(1920*dar/2)*2)':h='max(1920,ceil(1080/dar/2)*2)',setsar=1,crop=1080:1920";
const BACKDROP_VIDEO: &str = "split[front][back];[back]scale=270:480:force_original_aspect_ratio=increase,crop=270:480,setsar=1,gblur=sigma=14,eq=brightness=-0.13,scale=1080:1920[bg];[front]scale=w='max(2,trunc(min(1080,1920*dar)/2)*2)':h='max(2,trunc(min(1920,1080/dar)/2)*2)',setsar=1[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2";
const DIALOGUE: &str = "loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000,apad";
const SCORE: &str = "score.wav";
const SCORE_MIX: &str =
    "[1:a:0]aformat=sample_rates=48000:channel_layouts=stereo,volume=0.65,apad[cue];\
    [cue][key]sidechaincompress=threshold=0.022:ratio=6:attack=12:release=170[ducked];\
    [dialogue][ducked]amix=inputs=2:duration=first:normalize=0,\
    alimiter=limit=0.84:level=0:latency=1[audio]";

const ASS_HEADER: &str = "[Script Info]\n\
    ScriptType: v4.00+\n\
    PlayResX: 1080\n\
    PlayResY: 1920\n\
    WrapStyle: 0\n\
    ScaledBorderAndShadow: yes\n\n\
    [V4+ Styles]\n\
    Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n\
    Style: Short,Arial,72,&H00FFFFFF,&H00FFFFFF,&H00101010,&HA0000000,-1,0,0,0,100,100,0,0,1,5,2,2,128,128,384,1\n\n\
    [Events]\n\
    Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n";

/// Render one clip. Caption timestamps are relative to the source video.
pub struct ShortOutput {
    pub path: String,
    pub has_captions: bool,
    pub creative: CreativeEdit,
    pub duration_sec: f64,
}

pub async fn render_short(
    media: &MediaEngine,
    req: &RenderRequest,
    captions: &[TranscribedSegment],
    treatment: &Treatment,
    ranges: &[(f64, f64)],
    options: &short_creative::Options,
) -> Result<ShortOutput> {
    let [clip] = req.clips.as_slice() else {
        bail!("Short Auto requires exactly one clip");
    };
    let duration: f64 = ranges.iter().map(|(start, end)| end - start).sum();
    ensure!(
        clip.start_sec.is_finite()
            && clip.start_sec >= 0.0
            && clip.end_sec.is_finite()
            && duration >= 1.0 / FPS,
        "Short Auto clip range must be finite, nonnegative and at least one frame long"
    );
    let mut previous = clip.start_sec;
    ensure!(
        !ranges.is_empty()
            && ranges.len() <= 9
            && ranges.iter().all(|&(start, end)| {
                let valid = start.is_finite()
                    && end.is_finite()
                    && start >= previous
                    && end <= clip.end_sec
                    && end - start >= 1.0 / FPS;
                previous = end;
                valid
            }),
        "Invalid Short Auto timeline"
    );

    let cwd = std::env::current_dir().context("resolve Short Auto working directory")?;
    let session = output_session(&cwd, Path::new(&req.output_dir))?;
    let source = std::path::absolute(&req.video_path).context("resolve Short Auto source path")?;
    ensure!(
        tokio::fs::metadata(&source)
            .await
            .context("open Short Auto source file")?
            .is_file(),
        "Short Auto source must be a local media file"
    );

    // MediaEngine's Windows PATH lookup can return one line per installation.
    let executable = media.ffmpeg_path.lines().next().unwrap_or_default();
    ensure!(!executable.is_empty(), "Short Auto FFmpeg path is empty");
    let executable = PathBuf::from(executable);
    let executable = if executable.components().count() > 1 {
        std::path::absolute(executable).context("resolve Short Auto FFmpeg path")?
    } else {
        executable
    };
    let has_audio = source_has_audio(&executable, &source).await?;

    let output_root = create_output_dir(&cwd, "output").await?;
    let output_dir = create_output_dir(&output_root, session).await?;
    let staging_dir = output_dir.join(format!(".short-{}", Uuid::new_v4()));
    std::fs::create_dir(&staging_dir).context("create Short Auto staging directory")?;
    let temp = RenderTemp(staging_dir);

    let mut creative = CreativeEdit::analyze(&executable, &source, ranges, captions, options).await;
    let timeline = creative.timeline(ranges, !captions.is_empty(), &options.brief);
    let duration = timeline.iter().map(|span| span.duration()).sum::<f64>();
    let mut ass = caption_script(captions, ranges, treatment.captions);
    let has_captions = ass.is_some();
    let graphics = creative.graphics(duration, ass_time);
    if !graphics.is_empty() {
        ass.get_or_insert_with(|| ASS_HEADER.to_owned())
            .push_str(&graphics);
    }
    let has_overlays = ass.is_some();
    if let Some(ass) = ass {
        tokio::fs::write(temp.0.join("captions.ass"), ass)
            .await
            .context("write Short Auto captions")?;
    }
    let zoom_peak = captions
        .iter()
        .filter(|segment| segment.start > clip.start_sec + 1.0)
        .find_map(|segment| output_time(segment.start, ranges))
        .filter(|time| *time < duration - 0.6)
        .unwrap_or(duration * 0.35);
    let requested_accent = if options.effects || options.style == short_creative::Style::Clean {
        treatment.sound
    } else {
        Accent::Off
    };
    let soundtrack = creative.soundtrack(duration, requested_accent);
    let use_score = soundtrack.is_some();
    let correction = if treatment.grade == Grade::Original {
        None
    } else {
        let (left, right) = ranges[0];
        sample_grade(&executable, &source, left + (right - left) * 0.35).await
    };
    let filters = filter_graph(
        &timeline,
        clip.start_sec,
        duration,
        has_audio,
        use_score,
        treatment,
        has_overlays,
        zoom_peak,
        correction,
        &creative,
    );

    let mut render = ffmpeg(&executable);
    render
        .current_dir(&temp.0)
        .args([
            "-v",
            "error",
            "-xerror",
            "-progress",
            "pipe:1",
            "-nostats",
            "-filter_complex_threads",
            "2",
        ])
        .args(["-ss", &format!("{:.6}", clip.start_sec)])
        .args(["-protocol_whitelist", "file", "-i"])
        .arg(&source);
    if let Some(samples) = soundtrack {
        let cue_path = temp.0.join(SCORE);
        SoundForge::save_wav(
            cue_path.to_str().context("score path must be Unicode")?,
            &samples,
        )
        .context("write Short Auto score")?;
        render.args(["-protocol_whitelist", "file", "-i", SCORE]);
    }
    if !has_audio && !use_score {
        render.args(["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"]);
    }
    let rendered = render
        .args([
            "-filter_complex",
            &filters,
            "-map",
            "[video]",
            "-map",
            if has_audio || use_score {
                "[audio]"
            } else {
                "1:a:0"
            },
        ])
        .args(["-t", &format!("{duration:.6}")])
        .args([
            "-map_metadata",
            "-1",
            "-map_chapters",
            "-1",
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-crf",
            "20",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-b:a",
            "160k",
            "-ar",
            "48000",
            "-movflags",
            "+faststart",
            "-f",
            "mp4",
            OUTPUT_NAME,
        ])
        .output()
        .await
        .context("start Short Auto FFmpeg render")?;
    check_status(&rendered, "Short Auto FFmpeg render")?;
    check_frame_count(&String::from_utf8_lossy(&rendered.stdout), duration)?;
    verify_output(&executable, &temp.0).await?;

    tokio::fs::rename(temp.0.join(OUTPUT_NAME), output_dir.join(OUTPUT_NAME))
        .await
        .context("publish verified Short Auto clip")?;
    Ok(ShortOutput {
        path: format!("output/{session}/{OUTPUT_NAME}"),
        has_captions,
        creative,
        duration_sec: duration,
    })
}

struct GradeCorrection {
    gamma: f64,
    warm_cast: f64,
}

async fn sample_grade(ffmpeg_path: &Path, source: &Path, time: f64) -> Option<GradeCorrection> {
    let mut command = ffmpeg(ffmpeg_path);
    command
        .args([
            "-v",
            "error",
            "-ss",
            &format!("{time:.6}"),
            "-protocol_whitelist",
            "file",
            "-i",
        ])
        .arg(source)
        .args([
            "-map",
            "0:V:0",
            "-frames:v",
            "1",
            "-vf",
            "scale=48:48:flags=area,format=rgb24",
            "-threads:v",
            "1",
            "-f",
            "rawvideo",
            "pipe:1",
        ]);
    match tokio::time::timeout(Duration::from_secs(8), command.output()).await {
        Ok(Ok(output)) if output.status.success() && output.stdout.len() == 48 * 48 * 3 => {
            Some(grade_for_pixels(&output.stdout))
        }
        _ => None,
    }
}

fn grade_for_pixels(pixels: &[u8]) -> GradeCorrection {
    let pixels_count = (pixels.len() / 3) as f64;
    let (mut luma_sum, mut highlights, mut neutral, mut warm, mut cast) = (0.0, 0, 0, 0, 0.0);
    for pixel in pixels.chunks_exact(3) {
        let (r, g, b) = (
            f64::from(pixel[0]),
            f64::from(pixel[1]),
            f64::from(pixel[2]),
        );
        let luma = 0.213 * r + 0.715 * g + 0.072 * b;
        luma_sum += luma;
        highlights += u32::from(luma >= 225.0);
        if (45.0..185.0).contains(&luma) && r.max(g).max(b) - r.min(g).min(b) < 41.0 {
            neutral += 1;
            if r > g + 6.0 && g > b + 6.0 {
                warm += 1;
                cast += r - b;
            }
        }
    }
    let mean = luma_sum / pixels_count;
    let gamma = if mean < 94.0 && f64::from(highlights) / pixels_count < 0.09 {
        1.0 + ((94.0 - mean) / 160.0).min(0.23)
    } else {
        1.0
    };
    let warm_cast =
        if warm > 0 && f64::from(neutral) >= pixels_count * 0.22 && warm * 10 >= neutral * 7 {
            ((cast / f64::from(warm) - 12.0) / 250.0).clamp(0.0, 0.055)
        } else {
            0.0
        };
    GradeCorrection { gamma, warm_cast }
}

fn filter_graph(
    ranges: &[Span],
    start: f64,
    duration: f64,
    has_audio: bool,
    use_score: bool,
    treatment: &Treatment,
    has_overlays: bool,
    zoom_peak: f64,
    correction: Option<GradeCorrection>,
    creative: &CreativeEdit,
) -> String {
    let mut graph = String::new();
    let split = ranges.len() > 1;
    if split {
        let _ = write!(graph, "[0:V:0]split={}", ranges.len());
        for index in 0..ranges.len() {
            let _ = write!(graph, "[vs{index}]");
        }
        graph.push(';');
        if has_audio {
            let _ = write!(graph, "[0:a:0]asplit={}", ranges.len());
            for index in 0..ranges.len() {
                let _ = write!(graph, "[as{index}]");
            }
            graph.push(';');
        }
    }
    for (index, span) in ranges.iter().enumerate() {
        let video = if split {
            format!("[vs{index}]")
        } else {
            "[0:V:0]".into()
        };
        let audio = if split {
            format!("[as{index}]")
        } else {
            "[0:a:0]".into()
        };
        let left = span.start - start;
        let right = span.end - start;
        let speed = span.speed;
        let _ = write!(
            graph,
            "{video}trim=start={left:.6}:end={right:.6},setpts=(PTS-STARTPTS)/{speed:.3}[v{index}];"
        );
        if has_audio {
            let length = span.duration();
            let _ = write!(
                graph,
                "{audio}atrim=start={left:.6}:end={right:.6},asetpts=PTS-STARTPTS,aresample=48000"
            );
            if speed != 1.0 {
                let _ = write!(graph, ",atempo={speed:.3}");
            }
            let _ = write!(
                graph,
                ",apad=whole_dur={length:.6},atrim=duration={length:.6}"
            );
            if index > 0 && ranges[index - 1].end < span.start {
                graph.push_str(",afade=t=in:d=0.016");
            }
            if index + 1 < ranges.len() && span.end < ranges[index + 1].start {
                let _ = write!(graph, ",afade=t=out:st={:.6}:d=0.016", length - 0.016);
            }
            let _ = write!(graph, "[a{index}];");
        }
    }
    let audio_input = if split {
        for index in 0..ranges.len() {
            let _ = write!(graph, "[v{index}]");
            if has_audio {
                let _ = write!(graph, "[a{index}]");
            }
        }
        let _ = write!(
            graph,
            "concat=n={}:v=1:a={}[cut]",
            ranges.len(),
            u8::from(has_audio)
        );
        if has_audio {
            graph.push_str("[cut_audio]");
        }
        graph.push_str(";[cut]");
        "[cut_audio]"
    } else {
        graph.push_str("[v0]");
        "[a0]"
    };
    match treatment.framing {
        Framing::Fit => graph.push_str(FIT_VIDEO),
        Framing::Fill => {
            let _ = write!(graph, "fps=30:start_time=0,{FILL_VIDEO}");
        }
        Framing::Backdrop => {
            let _ = write!(graph, "fps=30:start_time=0,{BACKDROP_VIDEO}");
        }
    }
    graph.push_str(match treatment.grade {
        Grade::Original => "",
        Grade::Clean => ",eq=contrast=1.02:brightness=0.006:saturation=1.02",
        Grade::Warm => {
            ",eq=contrast=1.045:saturation=1.10,colorbalance=rs=0.029:bs=-0.021:rm=0.022:bm=-0.019"
        }
        Grade::Cool => {
            ",eq=contrast=1.045:saturation=1.045,colorbalance=rs=-0.025:bs=0.027:rm=-0.018:bm=0.020"
        }
        Grade::Punchy => ",eq=contrast=1.105:brightness=0.01:saturation=1.20:gamma=1.025",
        Grade::Mono => ",hue=s=0,eq=contrast=1.08:brightness=0.008",
    });
    if let Some(GradeCorrection { gamma, warm_cast }) = correction {
        if treatment.grade == Grade::Clean && warm_cast > 0.004 {
            let red = -0.55 * warm_cast;
            let _ = write!(
                graph,
                ",colorbalance=rs={red:.3}:rm={red:.3}:bs={warm_cast:.3}:bm={warm_cast:.3}"
            );
        }
        if gamma > 1.005 {
            let _ = write!(graph, ",eq=gamma={gamma:.3}:gamma_weight=0.75");
        }
    }
    let zoom = match treatment.zoom {
        Zoom::Off => None,
        Zoom::Opening => Some("1+0.11*pow(max(0,1-on/32),2)".to_string()),
        Zoom::Emphasis => {
            let hits = if creative.beats.is_empty() {
                &[zoom_peak][..]
            } else {
                &creative.beats
            };
            let pulses: Vec<String> = hits
                .iter()
                .map(|time| format!("0.12*pow(max(0,1-abs(on-{:.1})/22),2)", time * FPS))
                .collect();
            Some(format!("1+{}", pulses.join("+")))
        }
        Zoom::SlowPush => Some(format!("1+0.14*min(on/{:.1},1)", (duration * FPS).max(1.0))),
    };
    if let Some(zoom) = zoom {
        let _ = write!(
            graph,
            ",zoompan=z='{zoom}':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d=1:s=1080x1920:fps=30"
        );
    }
    if treatment.transition == Transition::Fade && duration > 1.0 {
        let _ = write!(
            graph,
            ",fade=t=in:d=0.24,fade=t=out:st={:.6}:d=0.24",
            duration - 0.24
        );
    }
    if matches!(
        creative.style,
        short_creative::Style::Reaction | short_creative::Style::Kinetic
    ) {
        for &beat in &creative.beats {
            let _ = write!(
                graph,
                ",eq=contrast=1.045:saturation=1.10:enable='between(t,{beat:.3},{:.3})'",
                beat + 0.24
            );
        }
    }
    if has_overlays {
        graph.push_str(",ass=filename=captions.ass:shaping=complex");
    }
    graph.push_str("[video]");
    if has_audio {
        let _ = write!(
            graph,
            ";{audio_input}atrim=duration={duration:.6},{DIALOGUE}"
        );
        if use_score {
            let _ = write!(graph, ",aformat=sample_rates=48000:channel_layouts=stereo,asplit[dialogue][key];{SCORE_MIX}");
        } else {
            graph.push_str(",alimiter=limit=0.84:level=0:latency=1[audio]");
        }
    } else if use_score {
        graph.push_str(
            ";[1:a:0]aformat=sample_rates=48000:channel_layouts=stereo,volume=0.80,apad[audio]",
        );
    }
    graph
}

fn output_session<'a>(cwd: &Path, output: &'a Path) -> Result<&'a str> {
    let relative = if output.is_absolute() {
        output
            .strip_prefix(cwd)
            .context("Short Auto output must be under the working directory")?
    } else {
        output
    };
    let mut components = relative
        .components()
        .filter(|part| *part != Component::CurDir);
    match (components.next(), components.next(), components.next()) {
        (Some(Component::Normal(root)), Some(Component::Normal(session)), None)
            if root == "output" =>
        {
            session
                .to_str()
                .context("Short Auto session name must be Unicode")
        }
        _ => bail!("Short Auto output directory must be output/<session>"),
    }
}

async fn create_output_dir(parent: &Path, name: &str) -> Result<PathBuf> {
    let dir = parent.join(name);
    match tokio::fs::create_dir(&dir).await {
        Ok(()) => {}
        Err(err) if err.kind() == std::io::ErrorKind::AlreadyExists => {}
        Err(err) => return Err(err).with_context(|| format!("create {}", dir.display())),
    }
    let resolved = tokio::fs::canonicalize(&dir).await?;
    let parent = tokio::fs::canonicalize(parent).await?;
    ensure!(
        resolved.parent() == Some(parent.as_path()) && tokio::fs::metadata(&dir).await?.is_dir(),
        "Short Auto output directory must resolve inside {}",
        parent.display()
    );
    Ok(dir)
}

struct RenderTemp(PathBuf);

impl Drop for RenderTemp {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn ffmpeg(executable: &Path) -> Command {
    let mut command = Command::new(executable);
    command
        .args(["-hide_banner", "-nostdin"])
        .kill_on_drop(true);
    command
}

async fn source_has_audio(executable: &Path, source: &Path) -> Result<bool> {
    // Header-only probe works with distributions that ship only FFmpeg.
    let probe = ffmpeg(executable)
        .args(["-loglevel", "info", "-protocol_whitelist", "file", "-i"])
        .arg(source)
        .output()
        .await
        .context("start Short Auto source probe")?;
    let header = String::from_utf8_lossy(&probe.stderr);
    ensure!(
        header.contains("At least one output file must be specified")
            && input_streams(&header)
                .any(|s| s.starts_with("Video: ") && !s.contains("(attached pic)")),
        "Short Auto source has no readable video stream: {}",
        header.trim()
    );
    let has_audio = input_streams(&header).any(|s| s.starts_with("Audio: "));
    Ok(has_audio)
}

fn input_streams(header: &str) -> impl Iterator<Item = &str> {
    header
        .lines()
        .skip_while(|line| !line.starts_with("Input #0,"))
        .take_while(|line| !line.starts_with("Stream mapping:"))
        .filter_map(|line| {
            let (_, details) = line
                .trim_start()
                .strip_prefix("Stream #0:")?
                .split_once(": ")?;
            Some(details)
        })
}

fn check_status(output: &Output, step: &str) -> Result<()> {
    ensure!(
        output.status.success(),
        "{step} failed ({}): {}",
        output.status,
        String::from_utf8_lossy(&output.stderr).trim()
    );
    Ok(())
}

fn check_frame_count(progress: &str, duration: f64) -> Result<()> {
    let frames = progress
        .lines()
        .rev()
        .find_map(|line| line.strip_prefix("frame=")?.trim().parse::<u64>().ok());
    let frames = frames.context("Short Auto render reported no video frame count")?;
    ensure!(
        frames > 0 && (frames as f64 - duration * FPS).abs() <= 1.5,
        "Short Auto render produced {frames} frames for a {duration:.3}s clip"
    );
    Ok(())
}

async fn verify_output(executable: &Path, dir: &Path) -> Result<()> {
    let output = ffmpeg(executable)
        .current_dir(dir)
        .args([
            "-loglevel",
            "info",
            "-xerror",
            "-protocol_whitelist",
            "file",
            "-i",
            OUTPUT_NAME,
            "-map",
            "0:V:0",
            "-map",
            "0:a:0",
            "-t",
            "0.10",
            "-f",
            "null",
            "-",
        ])
        .output()
        .await
        .context("start Short Auto output verification")?;
    check_status(&output, "Short Auto output verification")?;
    let header = String::from_utf8_lossy(&output.stderr);
    ensure!(
        header
            .lines()
            .any(|line| line.starts_with("Input #0, mov,mp4,"))
            && input_streams(&header).any(|stream| {
                stream.starts_with("Video: h264 ")
                    && stream.contains(", 1080x1920 ")
                    && stream.contains(", 30 fps,")
            })
            && input_streams(&header).any(|stream| stream.starts_with("Audio: aac ")),
        "Short Auto output is not a 1080×1920 30 fps H.264/AAC MP4"
    );
    Ok(())
}

fn caption_script(
    segments: &[TranscribedSegment],
    ranges: &[(f64, f64)],
    motion: CaptionMotion,
) -> Option<String> {
    if motion == CaptionMotion::Off {
        return None;
    }
    let mut cues = Vec::new();
    let mut offset = 0.0;
    for &(clip_start, clip_end) in ranges {
        for segment in segments {
            if !segment.start.is_finite() || !segment.end.is_finite() {
                continue;
            }
            let start = segment.start.max(clip_start) - clip_start;
            let end = segment.end.min(segment.start + 4.0).min(clip_end) - clip_start;
            if end <= start {
                continue;
            }

            let text = sanitize_caption(&segment.text);
            let start = ((offset + start) * 100.0).floor() as u64;
            let end = ((offset + end) * 100.0).ceil() as u64;
            if !text.is_empty() && end > start {
                cues.push((start, end, text));
            }
        }
        offset += clip_end - clip_start;
    }
    if cues.is_empty() {
        return None;
    }
    cues.sort_by_key(|cue| cue.0);
    let mut script = ASS_HEADER.to_owned();
    let animation = if motion == CaptionMotion::Pop {
        r"{\fscx94\fscy94\t(0,150,\fscx100\fscy100)\fad(60,70)}"
    } else {
        ""
    };
    for (start, end, text) in cues {
        let _ = writeln!(
            script,
            "Dialogue: 0,{},{},Short,,0,0,0,,{animation}{text}",
            ass_time(start),
            ass_time(end),
        );
    }
    Some(script)
}

fn sanitize_caption(text: &str) -> String {
    // Keep Unicode in logical order for libass. Neutralize ASS override and escape syntax.
    text.split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .chars()
        .filter(|ch| !ch.is_control())
        .map(|ch| match ch {
            '{' => '｛',
            '}' => '｝',
            '\\' => '＼',
            _ => ch,
        })
        .collect()
}

fn ass_time(centiseconds: u64) -> String {
    let seconds = centiseconds / 100;
    format!(
        "{}:{:02}:{:02}.{:02}",
        seconds / 3600,
        seconds / 60 % 60,
        seconds % 60,
        centiseconds % 100,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn segment(start: f64, end: f64, text: &str) -> TranscribedSegment {
        TranscribedSegment {
            start,
            end,
            text: text.into(),
            words: Vec::new(),
        }
    }

    #[test]
    fn captions_are_clipped_rebased_and_sanitized() {
        let script = caption_script(
            &[
                segment(11.25, 14.0, "نهاية"),
                segment(8.0, 10.5, "مرحبًا,\n {\\pos(0,0)} test\\N"),
                segment(7.0, 9.0, "before the clip"),
                segment(12.0, 14.0, "after the clip"),
                segment(f64::NAN, 11.0, "invalid timestamp"),
            ],
            &[(10.0, 12.0)],
            CaptionMotion::Static,
        )
        .unwrap();
        let events: Vec<_> = script
            .lines()
            .filter(|line| line.starts_with("Dialogue:"))
            .collect();
        assert_eq!(
            events,
            [
                "Dialogue: 0,0:00:00.00,0:00:00.50,Short,,0,0,0,,مرحبًا, ｛＼pos(0,0)｝ test＼N",
                "Dialogue: 0,0:00:01.25,0:00:02.00,Short,,0,0,0,,نهاية",
            ]
        );
        assert_eq!(ass_time(372_345), "1:02:03.45");
    }

    #[test]
    fn blank_or_out_of_range_captions_emit_no_script() {
        let segments = [segment(0.0, 1.0, "early"), segment(3.0, 3.5, " \t\r\n")];
        assert!(caption_script(&segments, &[(3.0, 4.0)], CaptionMotion::Static).is_none());
    }

    #[test]
    fn a_caption_cannot_stay_on_screen_for_an_entire_scene() {
        let script = caption_script(
            &[segment(1.0, 32.0, "opening line")],
            &[(0.0, 32.0)],
            CaptionMotion::Static,
        )
        .unwrap();
        assert!(script.contains("0:00:01.00,0:00:05.00,Short"));
    }

    #[test]
    fn animated_captions_follow_the_cut_timeline() {
        let script = caption_script(
            &[segment(4.0, 5.1, "بعد الوقفة")],
            &[(0.0, 2.0), (4.0, 6.0)],
            CaptionMotion::Pop,
        )
        .unwrap();
        assert!(script.contains("0:00:02.00,0:00:03.10,Short"));
        assert!(script.contains(r"\t(0,150,"));
        assert_eq!(output_time(4.25, &[(0.0, 2.0), (4.0, 6.0)]), Some(2.25));
    }

    #[test]
    fn only_a_single_session_inside_output_is_accepted() {
        let cwd = std::env::current_dir().unwrap();
        assert_eq!(
            output_session(&cwd, Path::new("./output//جلسة/")).unwrap(),
            "جلسة"
        );
        assert_eq!(
            output_session(&cwd, &cwd.join("output/session")).unwrap(),
            "session"
        );
        assert!(output_session(&cwd, Path::new("output/../escape")).is_err());
        assert!(output_session(&cwd, Path::new("output/session/nested")).is_err());
    }

    #[test]
    fn frame_count_uses_final_progress_and_rejects_truncation() {
        assert!(
            check_frame_count("frame=3\nprogress=continue\nframe= 30\nprogress=end\n", 1.0).is_ok()
        );
        assert!(check_frame_count("frame=15\nprogress=end\n", 1.0).is_err());
        assert!(check_frame_count("frame=0\nprogress=end\n", 1.0 / FPS).is_err());
    }
}
