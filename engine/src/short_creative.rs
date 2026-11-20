use std::fmt::Write;
use std::path::Path;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use tokio::process::Command;

use crate::short_plan::Accent;
use crate::sound_forge::{SoundForge, SAMPLE_RATE};
use crate::types::TranscribedSegment;

const SAMPLE_FPS: f64 = 5.0;
const FRAME_SIZE: usize = 36 * 48;

#[derive(Debug, Copy, Clone, PartialEq, Eq, Default, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Style {
    #[default]
    Clean,
    Auto,
    Story,
    Reaction,
    Kinetic,
}

impl Style {
    pub fn resolve(
        self,
        suggested: Option<Self>,
        content: &str,
        speech: bool,
        brief: &str,
    ) -> Self {
        if self != Self::Auto {
            return self;
        }
        let brief = brief.to_lowercase();
        if ["رد فعل", "مقلب", "reaction", "pov"]
            .iter()
            .any(|tag| brief.contains(tag))
        {
            return Self::Reaction;
        }
        if ["مونتاج سريع", "على البيت", "kinetic", "beat edit"]
            .iter()
            .any(|tag| brief.contains(tag))
        {
            return Self::Kinetic;
        }
        if ["حكاية", "storytime", "سينمائي", "cinematic"]
            .iter()
            .any(|tag| brief.contains(tag))
        {
            return Self::Story;
        }
        if let Some(style @ (Self::Story | Self::Reaction | Self::Kinetic)) = suggested {
            return style;
        }
        match content {
            "comedy" => Self::Reaction,
            "gaming" | "motivation" => Self::Kinetic,
            _ if speech => Self::Story,
            _ => Self::Reaction,
        }
    }

    fn bpm(self) -> f64 {
        match self {
            Self::Story => 88.0,
            Self::Reaction => 104.0,
            _ => 126.0,
        }
    }

    // ASS uses BGR channel order.
    fn colors(self) -> (&'static str, &'static str) {
        match self {
            Self::Story => ("56D9BD", "222419"),
            Self::Reaction => ("54DBFF", "25202E"),
            _ => ("F6A687", "281928"),
        }
    }
}

#[derive(Default)]
pub struct Options {
    pub style: Style,
    pub title: String,
    pub music: bool,
    pub effects: bool,
    pub brief: String,
    pub focus_source_sec: Option<f64>,
    pub directed: Option<DirectedDesign>,
}

#[derive(Default)]
pub struct DirectedDesign {
    pub focus_source_secs: Vec<f64>,
    pub sound_cues: Vec<(f64, Accent)>,
    pub slow_source_sec: Option<f64>,
}

#[derive(Default)]
pub struct CreativeEdit {
    pub style: Style,
    pub title: String,
    pub beats: Vec<f64>,
    pub music: bool,
    pub effects: bool,
    pub slow_motion: bool,
    timed_sounds: Option<Vec<(f64, Accent)>>,
    slow_target: Option<f64>,
}

#[derive(Clone, Copy)]
pub struct Span {
    pub start: f64,
    pub end: f64,
    pub speed: f64,
}

impl Span {
    pub fn duration(self) -> f64 {
        (self.end - self.start) / self.speed
    }
}

impl CreativeEdit {
    pub async fn analyze(
        executable: &Path,
        source: &Path,
        ranges: &[(f64, f64)],
        transcript: &[TranscribedSegment],
        options: &Options,
    ) -> Self {
        let duration = duration_of(ranges);
        if let Some(directed) = &options.directed {
            let timed_sounds: Vec<_> = directed
                .sound_cues
                .iter()
                .filter_map(|&(at, sound)| output_time(at, ranges).map(|time| (time, sound)))
                .collect();
            return Self {
                style: options.style,
                title: clean_title(&options.title).unwrap_or_default(),
                beats: directed
                    .focus_source_secs
                    .iter()
                    .filter_map(|&at| output_time(at, ranges))
                    .collect(),
                music: options.music && !music_muted(&options.brief),
                effects: options.effects && !sounds_muted(&options.brief),
                timed_sounds: Some(timed_sounds),
                slow_target: directed
                    .slow_source_sec
                    .and_then(|at| output_time(at, ranges)),
                ..Self::default()
            };
        }
        if options.style == Style::Clean || duration < 2.0 {
            return Self::default();
        }
        let first = ranges[0].0;
        let last = ranges.last().unwrap().1;
        let title = clean_title(&options.title)
            .or_else(|| {
                (options.style == Style::Story)
                    .then(|| {
                        transcript
                            .iter()
                            .find(|line| (first..first + 1.8).contains(&line.start))
                    })
                    .flatten()
                    .and_then(|line| clean_title(&line.text))
            })
            .unwrap_or_default();
        let mut beats = if options.style == Style::Story {
            let mut times = Vec::new();
            for segment in transcript
                .iter()
                .filter(|line| line.text.chars().count() >= 12)
            {
                if let Some(time) = output_time(segment.start, ranges) {
                    if time >= 2.3
                        && time < duration - 1.2
                        && times.last().is_none_or(|previous| time - previous > 4.0)
                    {
                        times.push(time);
                    }
                }
                if times.len() == 2 {
                    break;
                }
            }
            times
        } else {
            let cues = visual_beats(executable, source, first, last).await;
            select_beats(
                cues.into_iter()
                    .filter_map(|(time, strength)| {
                        let time = output_time(time, ranges)?;
                        (time >= 2.6 && time < duration - 1.1).then_some((time, strength))
                    })
                    .collect(),
                if options.style == Style::Reaction {
                    2
                } else {
                    3
                },
            )
        };
        if let Some(focus) = options
            .focus_source_sec
            .and_then(|time| output_time(time, ranges))
        {
            if (2.0..duration - 1.0).contains(&focus) {
                beats.retain(|near| (near - focus).abs() >= 3.0);
                beats.truncate(if options.style == Style::Kinetic {
                    2
                } else {
                    1
                });
                beats.push(focus);
                beats.sort_by(f64::total_cmp);
            }
        }
        Self {
            style: options.style,
            title,
            beats,
            music: options.music && !music_muted(&options.brief),
            effects: options.effects && !sounds_muted(&options.brief),
            ..Self::default()
        }
    }

    pub fn timeline(&mut self, ranges: &[(f64, f64)], dialogue: bool, brief: &str) -> Vec<Span> {
        let mut timeline: Vec<_> = ranges
            .iter()
            .map(|&(start, end)| Span {
                start,
                end,
                speed: 1.0,
            })
            .collect();
        let duration = duration_of(ranges);
        let brief = brief.to_lowercase();
        if self.style != Style::Reaction
            || dialogue
            || duration > 59.65
            || duration < 6.0
            || ["no slow motion", "بدون تبطيء", "من غير تبطيء", "من غير سلو"]
                .iter()
                .any(|phrase| brief.contains(phrase))
        {
            return timeline;
        }
        let targets = if self.timed_sounds.is_some() {
            self.slow_target.as_slice()
        } else {
            self.beats.as_slice()
        };
        let mut elapsed = 0.0;
        let mut chosen = None;
        for (index, span) in timeline.iter().enumerate() {
            for &beat in targets {
                if (elapsed + 1.1..elapsed + span.duration() - 1.2).contains(&beat) {
                    let distance = (beat - duration * 0.58).abs();
                    if chosen.is_none_or(|(_, _, best)| distance < best) {
                        chosen = Some((index, beat - elapsed, distance));
                    }
                }
            }
            elapsed += span.duration();
        }
        if let Some((index, beat, _)) = chosen {
            let span = timeline[index];
            let left = span.start + beat - 0.34;
            let right = left + 0.82;
            const SPEED: f64 = 0.74;
            let output_start = output_time(left, ranges).unwrap();
            for beat in &mut self.beats {
                *beat += (*beat - output_start).clamp(0.0, right - left) * (1.0 / SPEED - 1.0);
            }
            if let Some(sounds) = &mut self.timed_sounds {
                for (time, _) in sounds {
                    *time += (*time - output_start).clamp(0.0, right - left) * (1.0 / SPEED - 1.0);
                }
            }
            self.slow_motion = true;
            timeline.splice(
                index..=index,
                [
                    Span { end: left, ..span },
                    Span {
                        start: left,
                        end: right,
                        speed: SPEED,
                    },
                    Span {
                        start: right,
                        ..span
                    },
                ],
            );
        }
        timeline
    }

    pub fn graphics(&self, duration: f64, timestamp: fn(u64) -> String) -> String {
        if self.style == Style::Clean {
            return String::new();
        }
        let (accent, panel) = self.style.colors();
        let mut output = String::new();
        let mut layer = |level: u8, start: f64, end: f64, text: &str| {
            let _ = writeln!(
                output,
                "Dialogue: {level},{},{},Short,,0,0,0,,{text}",
                timestamp((start * 100.0).round() as u64),
                timestamp((end * 100.0).round() as u64)
            );
        };
        let opener = duration.min(if self.title.is_empty() { 1.15 } else { 2.65 });
        let border = format!(
            r"{{\an7\move(92,258,92,237,0,340)\bord0\shad0\1c&H{accent}&\fscx8\t(0,330,\fscx100)\fad(75,230)\p1}}m 0 0 l 188 0 188 9 0 9"
        );
        if self.timed_sounds.is_none() || !self.title.is_empty() {
            layer(1, 0.0, opener, &border);
        }
        if !self.title.is_empty() {
            let name_size = match self.title.chars().count() {
                0..=17 => 88,
                18..=24 => 76,
                _ => 60,
            };
            let scrim = format!(
                r"{{\an7\move(78,282,78,259,0,340)\bord0\shad0\1c&H{panel}&\1a&H35&\fscx74\t(0,295,\fscx100)\fad(100,255)\p1}}m 0 0 l 798 0 826 28 826 155 30 155 0 125"
            );
            layer(0, 0.0, opener, &scrim);
            let title = format!(
                r"{{\an5\move(491,360,491,336,0,340)\fs{name_size}\bord2\shad0\q2\1c&HFFFFFF&\fscx92\fscy92\t(0,340,\fscx100\fscy100)\fad(110,250)}}{}",
                self.title
            );
            layer(2, 0.0, opener, &title);
        }
        for &beat in &self.beats {
            let pulse = format!(
                r"{{\an7\pos(92,240)\1c&H{accent}&\bord0\shad0\1a&H28&\fscx38\fscy72\t(0,230,\fscx100\fscy100)\fad(35,250)\p1}}m 0 0 l 92 0 92 7 7 7 7 69 0 69"
            );
            layer(1, beat, (beat + 0.59).min(duration), &pulse);
            if self.style != Style::Story {
                let lower = format!(
                    r"{{\an7\pos(814,1430)\1c&H{accent}&\bord0\shad0\1a&H38&\fscx40\t(0,230,\fscx100)\fad(55,250)\p1}}m 84 0 l 91 0 91 66 0 66 0 59 84 59"
                );
                layer(1, beat, (beat + 0.59).min(duration), &lower);
            }
        }
        let close = (duration - 0.5).max(opener);
        if self.timed_sounds.is_none() && close + 0.15 < duration {
            let tail = format!(
                r"{{\an7\pos(92,237)\1c&H{accent}&\bord0\shad0\t(0,350,\fscx18)\fad(95,150)\p1}}m 0 0 l 188 0 188 9 0 9"
            );
            layer(1, close, duration, &tail);
        }
        output
    }

    /// Shape and timing are shared with the motion graphics. All audio is synthesized.
    pub fn soundtrack(&self, duration: f64, accent: Accent) -> Option<Vec<i16>> {
        let opening = accent != Accent::Off
            && duration >= 0.5
            && (self.timed_sounds.is_none() || self.effects);
        let designed_cues =
            self.effects && self.style != Style::Clean && self.timed_sounds.is_none();
        let timed_sounds = if self.effects {
            self.timed_sounds.as_deref().unwrap_or(&[])
        } else {
            &[]
        };
        if !opening && !designed_cues && timed_sounds.is_empty() && !self.music {
            return None;
        }
        let mut mix = vec![0.0_f32; (duration * f64::from(SAMPLE_RATE)).ceil() as usize];
        let mut forge = SoundForge::with_seed(SAMPLE_RATE, 91);
        if self.music {
            add_music(&mut mix, &mut forge, self.style, &self.beats);
        }
        if designed_cues {
            add(&mut mix, &forge.generate("whoosh_up", 0.33), 0.03, 0.25);
            for &beat in &self.beats {
                if self.style == Style::Reaction {
                    add(
                        &mut mix,
                        &forge.generate("riser", 0.40),
                        (beat - 0.42).max(0.0),
                        0.16,
                    );
                }
                let sound = match self.style {
                    Style::Story => "ding",
                    Style::Reaction => "impact",
                    _ => "pop",
                };
                add(&mut mix, &forge.generate(sound, 0.25), beat, 0.35);
            }
            add(
                &mut mix,
                &forge.generate("whoosh_down", 0.28),
                duration - 0.36,
                0.13,
            );
        }
        for &(time, sound) in timed_sounds {
            add(
                &mut mix,
                &forge.generate(accent_name(sound), 0.25),
                time,
                0.35,
            );
        }
        if opening {
            add(
                &mut mix,
                &forge.generate(accent_name(accent), 0.24),
                if designed_cues { 0.45 } else { 0.0 },
                0.35,
            );
        }
        let len = mix.len();
        Some(
            mix.into_iter()
                .enumerate()
                .map(|(i, sample)| {
                    let fade = ((len - i) as f32 / (0.20 * SAMPLE_RATE as f32)).min(1.0);
                    (sample.clamp(-0.9, 0.9) * fade * f32::from(i16::MAX)) as i16
                })
                .collect(),
        )
    }
}

fn accent_name(accent: Accent) -> &'static str {
    match accent {
        Accent::Impact => "impact",
        Accent::Ding => "ding",
        _ => "whoosh_through",
    }
}

fn music_muted(brief: &str) -> bool {
    let brief = brief.to_lowercase();
    ["no music", "بدون موسيقى", "من غير موسيقى", "بلاش موسيقى"]
        .iter()
        .any(|phrase| brief.contains(phrase))
}

fn sounds_muted(brief: &str) -> bool {
    let brief = brief.to_lowercase();
    [
        "no sfx",
        "no sound effects",
        "بدون مؤثرات صوتية",
        "من غير مؤثرات صوتية",
        "بلاش مؤثرات صوتية",
    ]
    .iter()
    .any(|phrase| brief.contains(phrase))
}

pub fn duration_of(ranges: &[(f64, f64)]) -> f64 {
    ranges.iter().map(|(start, end)| end - start).sum()
}

pub fn output_time(source_time: f64, ranges: &[(f64, f64)]) -> Option<f64> {
    let mut offset = 0.0;
    for &(start, end) in ranges {
        if (start..end).contains(&source_time) {
            return Some(offset + source_time - start);
        }
        offset += end - start;
    }
    None
}

fn clean_title(title: &str) -> Option<String> {
    let title = title.split_whitespace().collect::<Vec<_>>().join(" ");
    if title.chars().count() > 34 || !title.chars().any(char::is_alphanumeric) {
        return None;
    }
    Some(
        title
            .chars()
            .filter(|ch| !ch.is_control())
            .map(|ch| match ch {
                '{' => '｛',
                '}' => '｝',
                '\\' => '＼',
                _ => ch,
            })
            .collect(),
    )
}

async fn visual_beats(executable: &Path, source: &Path, start: f64, end: f64) -> Vec<(f64, f64)> {
    let mut ffmpeg = Command::new(executable);
    ffmpeg
        .kill_on_drop(true)
        .args([
            "-hide_banner",
            "-nostdin",
            "-v",
            "error",
            "-ss",
            &format!("{start:.4}"),
            "-t",
            &format!("{:.4}", (end - start).min(64.0)),
            "-protocol_whitelist",
            "file",
            "-i",
        ])
        .arg(source)
        .args([
            "-map",
            "0:V:0",
            "-an",
            "-vf",
            "fps=5:start_time=0,scale=36:48:flags=area,format=gray",
            "-threads:v",
            "1",
            "-f",
            "rawvideo",
            "pipe:1",
        ]);
    let Ok(Ok(output)) = tokio::time::timeout(Duration::from_secs(15), ffmpeg.output()).await
    else {
        return Vec::new();
    };
    if !output.status.success() {
        return Vec::new();
    }
    let frames: Vec<_> = output.stdout.chunks_exact(FRAME_SIZE).collect();
    let scores: Vec<_> = frames
        .windows(2)
        .map(|pair| motion_score(pair[0], pair[1]))
        .collect();
    scores
        .windows(5)
        .enumerate()
        .filter_map(|(index, window)| {
            let peak = window[2];
            let neighborhood = (window[0] + window[1] + window[3] + window[4]) / 4.0;
            (peak >= 3.5 && peak > neighborhood * 1.25 && peak >= window[1].max(window[3]))
                .then_some((
                    start + (index + 3) as f64 / SAMPLE_FPS,
                    peak - 0.65 * neighborhood,
                ))
        })
        .collect()
}

fn motion_score(before: &[u8], after: &[u8]) -> f64 {
    let luma_change = before
        .iter()
        .zip(after)
        .map(|(&a, &b)| f64::from(b) - f64::from(a))
        .sum::<f64>()
        / FRAME_SIZE as f64;
    let mut central = 0.0;
    let mut edges = 0.0;
    let mut changed = 0;
    for (index, (&a, &b)) in before.iter().zip(after).enumerate() {
        let movement = (f64::from(b) - f64::from(a) - luma_change).abs();
        changed += usize::from(movement > 24.0);
        let row = index / 36;
        let column = index % 36;
        if (7..29).contains(&column) && (7..36).contains(&row) {
            central += movement;
        } else {
            edges += movement;
        }
    }
    if changed > FRAME_SIZE * 3 / 5 || luma_change.abs() > 30.0 {
        return 0.0;
    }
    (central / (22.0 * 29.0) - edges / 1090.0 * 0.65).max(0.0)
}

fn select_beats(mut ranked: Vec<(f64, f64)>, limit: usize) -> Vec<f64> {
    ranked.sort_by(|a, b| b.1.total_cmp(&a.1));
    let mut picks: Vec<f64> = Vec::new();
    for (time, _) in ranked {
        if picks.iter().all(|previous| (time - previous).abs() >= 4.0) {
            picks.push(time);
            if picks.len() == limit {
                break;
            }
        }
    }
    picks.sort_by(f64::total_cmp);
    picks
}

fn add(mix: &mut [f32], samples: &[i16], at: f64, gain: f32) {
    let offset = (at.max(0.0) * f64::from(SAMPLE_RATE)).round() as usize;
    for (target, &sample) in mix.iter_mut().skip(offset).zip(samples) {
        *target += f32::from(sample) / f32::from(i16::MAX) * gain;
    }
}

fn add_music(mix: &mut [f32], forge: &mut SoundForge, style: Style, highlights: &[f64]) {
    let beat = 60.0 / style.bpm();
    let kick = forge.generate("kick", 0.20);
    let snare = forge.generate("snare", 0.10);
    let hat = forge.generate("hihat", 0.045);
    let length = mix.len() as f64 / f64::from(SAMPLE_RATE);
    // Phase the grid to the main movement so its accent lands on the downbeat.
    let first_beat = highlights
        .first()
        .copied()
        .unwrap_or(0.0)
        .rem_euclid(beat * 4.0)
        - 4.0 * beat;
    let bass = [55.0, 65.406, 49.0, 58.27];
    for step in 0..=((length - first_beat) / beat).ceil() as usize {
        let time = first_beat + step as f64 * beat;
        if time < 0.0 || time >= length {
            continue;
        }
        let soft = style == Style::Story;
        if step % 4 == 0 || (!soft && step % 4 == 2) {
            add(mix, &kick, time, if soft { 0.082 } else { 0.15 });
        }
        if !soft && step % 2 == 1 {
            add(mix, &snare, time, 0.066);
        }
        if !soft || step % 2 == 0 {
            add(mix, &hat, time + beat * 0.47, 0.038);
        }
        let freq = bass[(step / 4) % bass.len()];
        let offset = (time * f64::from(SAMPLE_RATE)).round() as usize;
        for (i, target) in mix
            .iter_mut()
            .skip(offset)
            .take((beat * f64::from(SAMPLE_RATE) * 0.82) as usize)
            .enumerate()
        {
            let t = i as f64 / f64::from(SAMPLE_RATE);
            let angle = std::f64::consts::TAU * freq * t;
            let shape = (t * 150.0).min(1.0) * (-t * 9.0).exp();
            *target += ((angle.sin() + 0.22 * (angle * 2.0).sin()) * shape * 0.105) as f32;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn effects_use_distinct_peaks_and_title_cannot_inject_ass_tags() {
        assert_eq!(
            select_beats(vec![(4.0, 10.0), (4.6, 12.0), (12.0, 8.0)], 2),
            vec![4.6, 12.0]
        );
        assert_eq!(
            clean_title(r"{\pos(0,0)} test").unwrap(),
            "｛＼pos(0,0)｝ test"
        );
        let flat = vec![32; FRAME_SIZE];
        assert_eq!(motion_score(&flat, &vec![68; FRAME_SIZE]), 0.0);
    }

    #[test]
    fn a_reaction_speed_change_retimes_the_effects_and_keeps_the_source_contiguous() {
        let mut edit = CreativeEdit {
            style: Style::Reaction,
            beats: vec![4.0, 8.0],
            ..CreativeEdit::default()
        };
        let spans = edit.timeline(&[(0.0, 13.0)], false, "");
        assert_eq!(spans.len(), 3);
        assert_eq!(spans[0].end, spans[1].start);
        assert_eq!(spans[1].end, spans[2].start);
        assert!(spans[1].speed < 1.0 && edit.beats[1] > 8.0);
    }
}
