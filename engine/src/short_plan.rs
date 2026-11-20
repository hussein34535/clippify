use serde::{Deserialize, Serialize};

use crate::types::{Silence, TranscribedSegment};

#[derive(Debug, Copy, Clone, PartialEq, Eq, Default, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Grade {
    Original,
    #[default]
    Clean,
    Warm,
    Cool,
    Punchy,
    Mono,
}

#[derive(Debug, Copy, Clone, PartialEq, Eq, Default, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Zoom {
    #[default]
    Off,
    Opening,
    Emphasis,
    SlowPush,
}

#[derive(Debug, Copy, Clone, PartialEq, Eq, Default, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Transition {
    #[default]
    CleanCut,
    Fade,
}

#[derive(Debug, Copy, Clone, PartialEq, Eq, Default, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CaptionMotion {
    Off,
    Static,
    #[default]
    Pop,
}

#[derive(Debug, Copy, Clone, PartialEq, Eq, Default, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Accent {
    #[default]
    Off,
    Whoosh,
    Impact,
    Ding,
}

#[derive(Debug, Copy, Clone, PartialEq, Eq, Default, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Framing {
    Fit,
    #[default]
    Backdrop,
    Fill,
}

#[derive(Debug, Default, Clone, Deserialize, Serialize)]
#[serde(default, deny_unknown_fields)]
pub struct Treatment {
    pub grade: Grade,
    pub zoom: Zoom,
    pub transition: Transition,
    pub captions: CaptionMotion,
    pub sound: Accent,
    pub framing: Framing,
    pub trim_pauses: bool,
}

#[derive(Debug, Copy, Clone, PartialEq, Eq, Default, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ZoomPolicy {
    #[default]
    RequestOnly,
    Allow,
    Off,
}

fn contains_any(text: &str, phrases: &[&str]) -> bool {
    phrases.iter().any(|phrase| text.contains(phrase))
}

fn requests_pause_trimming(brief: &str) -> bool {
    contains_any(
        brief,
        &[
            "trim pauses",
            "cut pauses",
            "قص الصمت",
            "شيل السكتات",
            "قص السكتات",
        ],
    )
}

impl Treatment {
    pub fn local(brief: &str, zoom_policy: ZoomPolicy) -> Self {
        Self {
            zoom: if zoom_policy == ZoomPolicy::Allow {
                Zoom::Emphasis
            } else {
                Zoom::Off
            },
            trim_pauses: true,
            ..Self::default()
        }
        .respect(brief, zoom_policy)
    }

    pub fn respect(mut self, brief: &str, zoom_policy: ZoomPolicy) -> Self {
        let text = brief.to_lowercase();
        let zoom_requested = contains_any(&text, &["zoom", "زوم", "تكبير", "تقريب"]);
        let zoom_denied = contains_any(
            &text,
            &[
                "no zoom",
                "without zoom",
                "بدون زوم",
                "من غير زوم",
                "بلاش زوم",
                "مفيش زوم",
                "متعملش زوم",
                "بدون تكبير",
                "من غير تكبير",
                "بدون تقريب",
                "من غير تقريب",
            ],
        );
        self.zoom = if zoom_denied
            || zoom_policy == ZoomPolicy::Off
            || (zoom_policy == ZoomPolicy::RequestOnly && !zoom_requested)
        {
            Zoom::Off
        } else if zoom_requested
            && contains_any(
                &text,
                &["slow zoom", "زوم هادي", "زوم بطيء", "تقريب تدريجي"],
            )
        {
            Zoom::SlowPush
        } else if zoom_requested && self.zoom == Zoom::Off {
            Zoom::Emphasis
        } else {
            self.zoom
        };
        if contains_any(
            &text,
            &[
                "original color",
                "no color",
                "بدون تلوين",
                "الألوان الأصلية",
                "الوان اصلية",
                "من غير تحسين ألوان",
            ],
        ) {
            self.grade = Grade::Original;
        } else if contains_any(
            &text,
            &["black and white", "monochrome", "أبيض وأسود", "ابيض واسود"],
        ) {
            self.grade = Grade::Mono;
        } else if contains_any(&text, &["warm", "دافي", "دافئ", "دافية"]) {
            self.grade = Grade::Warm;
        } else if contains_any(
            &text,
            &["cool grade", "cool colors", "ألوان باردة", "الوان بارده"],
        ) {
            self.grade = Grade::Cool;
        } else if contains_any(&text, &["punchy", "vibrant", "ألوان قوية", "الوان قوية"])
        {
            self.grade = Grade::Punchy;
        }
        if contains_any(
            &text,
            &[
                "no captions",
                "without captions",
                "من غير كابشن",
                "بدون كابشن",
                "بدون ترجمة",
            ],
        ) {
            self.captions = CaptionMotion::Off;
        } else if contains_any(
            &text,
            &[
                "static captions",
                "كابشن ثابت",
                "بدون أنيميشن",
                "من غير انيميشن",
                "no animation",
            ],
        ) {
            self.captions = CaptionMotion::Static;
        } else if contains_any(
            &text,
            &[
                "animated captions",
                "pop captions",
                "كابشن متحرك",
                "ترجمة متحركة",
            ],
        ) {
            self.captions = CaptionMotion::Pop;
        }
        if contains_any(
            &text,
            &[
                "no sfx",
                "no sound effects",
                "بدون مؤثرات صوتية",
                "من غير مؤثرات صوتية",
            ],
        ) {
            self.sound = Accent::Off;
        } else if contains_any(&text, &["impact", "خبطة"]) {
            self.sound = Accent::Impact;
        } else if contains_any(&text, &["whoosh", "ووش"]) {
            self.sound = Accent::Whoosh;
        }
        if contains_any(&text, &["no fades", "بدون انتقالات", "قص مباشر"]) {
            self.transition = Transition::CleanCut;
        } else if contains_any(&text, &["fade", "تلاشي", "انتقال ناعم"]) {
            self.transition = Transition::Fade;
        }
        if contains_any(
            &text,
            &[
                "no crop",
                "keep full frame",
                "بدون قص الكادر",
                "الكادر كامل",
            ],
        ) {
            self.framing = Framing::Fit;
        } else if contains_any(
            &text,
            &["fill frame", "crop to fill", "املأ الكادر", "املا الكادر"],
        ) {
            self.framing = Framing::Fill;
        }
        if contains_any(
            &text,
            &[
                "keep pauses",
                "no cuts",
                "من غير قص الصمت",
                "بدون قص الصمت",
                "سيب السكتات",
            ],
        ) {
            self.trim_pauses = false;
        } else if requests_pause_trimming(&text) {
            self.trim_pauses = true;
        }
        self
    }
}

pub fn keep_ranges(
    start: f64,
    end: f64,
    silences: &[Silence],
    speech: &[TranscribedSegment],
    treatment: &Treatment,
    brief: &str,
) -> Vec<(f64, f64)> {
    if !treatment.trim_pauses || end - start < 3.0 {
        return vec![(start, end)];
    }
    let requested = requests_pause_trimming(&brief.to_lowercase());
    let (handle, min_cut, min_kept, allowed_fraction, max_cuts) = if requested {
        (0.22, 0.48, 0.65, 0.30, 4)
    } else {
        (0.32, 0.88, 2.0, 0.16, 2)
    };
    let mut gaps: Vec<_> = silences
        .iter()
        .filter_map(|silence| {
            let left = silence.start.max(start) + handle;
            let right = silence.end.min(end) - handle;
            (silence.start.is_finite()
                && silence.end.is_finite()
                && left > start + min_kept
                && right < end - min_kept
                && right - left >= min_cut
                && !speech
                    .iter()
                    .any(|part| part.start < right && part.end > left)
                && (requested
                    || (speech
                        .iter()
                        .any(|part| (left - 1.0..=left).contains(&part.end))
                        && speech
                            .iter()
                            .any(|part| (right..=right + 1.0).contains(&part.start)))))
            .then_some((left, right))
        })
        .collect();
    gaps.sort_by(|left, right| left.0.total_cmp(&right.0));
    let mut ranges = Vec::new();
    let mut cursor = start;
    let mut removed = 0.0;
    for (left, right) in gaps {
        if left - cursor < min_kept || removed + right - left > (end - start) * allowed_fraction {
            continue;
        }
        ranges.push((cursor, left));
        cursor = right;
        removed += right - left;
        if ranges.len() == max_cuts {
            break;
        }
    }
    ranges.push((cursor, end));
    ranges
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn explicit_controls_override_ai() {
        let treatment = Treatment {
            zoom: Zoom::Opening,
            ..Treatment::default()
        }
        .respect("من غير زوم وألوان دافية وكابشن ثابت", ZoomPolicy::Allow);
        assert_eq!(treatment.zoom, Zoom::Off);
        assert_eq!(treatment.grade, Grade::Warm);
        assert_eq!(treatment.captions, CaptionMotion::Static);
        assert_eq!(
            Treatment::local("زوم بطيء", ZoomPolicy::RequestOnly).zoom,
            Zoom::SlowPush
        );
        assert_eq!(
            Treatment::local("", ZoomPolicy::RequestOnly).zoom,
            Zoom::Off
        );
        assert_eq!(Treatment::local("", ZoomPolicy::Allow).zoom, Zoom::Emphasis);
        assert_eq!(
            Treatment::local("زوم بطيء", ZoomPolicy::Allow).zoom,
            Zoom::SlowPush
        );
    }

    #[test]
    fn internal_pauses_keep_handles_and_enough_context() {
        let silences = [
            Silence {
                start: 2.0,
                end: 4.0,
            },
            Silence {
                start: 8.0,
                end: 18.0,
            },
        ];
        let requested = "شيل السكتات";
        let treatment = Treatment::local(requested, ZoomPolicy::RequestOnly);
        assert_eq!(
            keep_ranges(0.0, 20.0, &silences, &[], &treatment, requested),
            vec![(0.0, 2.22), (3.78, 20.0)]
        );
        assert_eq!(
            keep_ranges(0.0, 20.0, &silences, &[], &treatment, ""),
            vec![(0.0, 20.0)]
        );
    }
}
