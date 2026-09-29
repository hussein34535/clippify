use serde::{Deserialize, Serialize};

pub const BIN_SEC: f64 = 0.5;
const FULL_SPEECH_WPS: f64 = 2.5;
const NOVELTY_SEC: f64 = 3.0;
const BASE_NOVELTY: f64 = 0.85;
const BASE_NEUTRAL: f64 = 0.55;
const PAUSE_TRIGGER_SEC: f64 = 1.0;
const SPIKE_DECAY_BINS: usize = 5;

const EMOTION_EN: [&str; 18] = [
    "love",
    "hate",
    "insane",
    "crazy",
    "shocking",
    "shocked",
    "amazing",
    "terrible",
    "worst",
    "best",
    "fear",
    "scary",
    "angry",
    "happy",
    "sad",
    "wild",
    "unbelievable",
    "secret",
];
const EMOTION_AR: [&str; 12] = [
    "رعب", "حب", "كره", "صادم", "مذهل", "خطير", "غضب", "مؤلم", "جميل", "فشل", "نجاح", "جنون",
];

#[derive(Serialize, Deserialize, Debug, Clone, Default)]
pub struct AttentionCurve {
    pub points: Vec<(f64, f64)>,
    pub avg_score: f64,
    pub peak_score: f64,
    pub drop_offs: Vec<(f64, f64)>,
}

struct Pause {
    t: f64,
}

pub fn predict_attention(
    transcript_words: &[(f64, f64, String)],
    video_duration: f64,
) -> AttentionCurve {
    let dur = if video_duration.is_finite() && video_duration > 0.0 {
        video_duration
    } else {
        1.0
    };

    let mut words: Vec<(f64, f64, &String)> = transcript_words
        .iter()
        .filter(|(s, e, _)| e >= s)
        .map(|(s, e, t)| (*s, *e, t))
        .collect();
    words.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));

    let n_bins = ((dur / BIN_SEC).ceil() as usize).max(1);

    let mut density = vec![0.0f64; n_bins];
    for (s, e, _) in &words {
        let mid = (s + e) / 2.0;
        let idx = ((mid / BIN_SEC).floor() as usize).min(n_bins - 1);
        density[idx] += 1.0;
    }
    for d in density.iter_mut() {
        *d = (*d / BIN_SEC / FULL_SPEECH_WPS).min(1.0);
    }

    let mut spikes = vec![0.0f64; n_bins];
    for (s, e, text) in &words {
        let low = text.to_lowercase();
        let mid = (s + e) / 2.0;
        if low.contains('?') || low.contains('؟') {
            add_spike(&mut spikes, mid, 0.28);
        }
        let numeric = low.contains('%')
            || low
                .chars()
                .any(|c| c.is_ascii_digit() || matches!(c, '\u{0660}'..='\u{0669}'));
        if numeric {
            add_spike(&mut spikes, mid, 0.18);
        }
        if is_emotional(&low) {
            add_spike(&mut spikes, mid, 0.22);
        }
    }

    let mut pauses: Vec<Pause> = Vec::new();
    for pair in words.windows(2) {
        let gap = pair[1].0 - pair[0].1;
        if gap > PAUSE_TRIGGER_SEC {
            let penalty = (0.12 * gap).min(0.35);
            add_spike(&mut spikes, pair[0].1, -penalty);
            pauses.push(Pause { t: pair[0].1 });
        }
    }

    let mut points = Vec::with_capacity(n_bins);
    for (i, d) in density.iter().enumerate() {
        let t = i as f64 * BIN_SEC;
        let base = if t < NOVELTY_SEC {
            BASE_NOVELTY
        } else {
            BASE_NEUTRAL
        };
        let score = (0.45 * d + 0.55 * base + spikes[i]).clamp(0.05, 1.0);
        points.push((round2(t), round3(score)));
    }

    let sum: f64 = points.iter().map(|p| p.1).sum();
    let avg = if points.is_empty() {
        0.0
    } else {
        sum / points.len() as f64
    };
    let peak = points.iter().map(|p| p.1).fold(0.0f64, f64::max);

    let mut drop_offs: Vec<(f64, f64)> = Vec::new();
    for p in &pauses {
        let before = window_mean(&points, p.t - 1.0, p.t, avg);
        let after = window_mean(&points, p.t + 0.5, p.t + 1.5, avg);
        let delta = before - after;
        if delta > 0.03 {
            drop_offs.push((round2(p.t), round3(delta)));
        }
    }
    drop_offs.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    drop_offs.truncate(10);

    AttentionCurve {
        points,
        avg_score: round3(avg),
        peak_score: round3(peak),
        drop_offs,
    }
}

pub fn overall_score(curve: &AttentionCurve) -> f64 {
    if curve.points.is_empty() {
        return 0.0;
    }
    let peak_time = curve
        .points
        .iter()
        .max_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
        .map(|p| p.0)
        .unwrap_or(0.0);
    let early_bonus = if peak_time <= 10.0 { 0.05 } else { 0.0 };
    round3((0.65 * curve.avg_score + 0.35 * curve.peak_score + early_bonus).clamp(0.0, 1.0))
}

pub fn recommendations(curve: &AttentionCurve) -> Vec<String> {
    let mut recs: Vec<String> = Vec::new();
    if curve.points.is_empty() {
        recs.push("لا يوجد نص كافٍ لتحليل الانتباه؛ شغّل التفريغ الصوتي أولاً.".to_string());
        return recs;
    }

    if curve.avg_score < 0.35 {
        recs.push(
            "متوسط الانتباه منخفض جداً؛ اختصر المقاطع وأضف تغييرات بصرية كل ٣ ثوانٍ.".to_string(),
        );
    }

    let end_t = curve.points.last().map(|p| p.0).unwrap_or(0.0);
    let peak_time = curve
        .points
        .iter()
        .max_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
        .map(|p| p.0)
        .unwrap_or(0.0);
    if end_t > 20.0 && peak_time > end_t * 0.3 {
        recs.push(format!(
            "أقوى ذروة عند الثانية {peak_time:.0}؛ انقلها إلى أول ٥ ثوانٍ لرفع نسبة الإكمال."
        ));
    }

    for (t, d) in curve.drop_offs.iter().take(4) {
        if *d >= 0.12 {
            recs.push(format!(
                "هبوط انتباه عند الثانية {t:.0}؛ أضف قطعاً سريعاً أو مؤثراً صوتياً أو زوم هنا."
            ));
        }
    }

    let tail_start = end_t * 0.8;
    let tail_mean = window_mean(&curve.points, tail_start, end_t + BIN_SEC, curve.avg_score);
    if end_t > 15.0 && tail_mean < 0.35 {
        recs.push("النهاية تُفقد المشاهدين؛ اختم بدعوة واضحة لاتخاذ إجراء.".to_string());
    }

    let weak_share = curve.points.iter().filter(|p| p.1 < 0.3).count() as f64
        / curve.points.len().max(1) as f64;
    if weak_share > 0.4 {
        recs.push(
            "أكثر من ٤٠٪ من المقطع خامل؛ احذف الفقرات البطيئة أو سرّعها.".to_string(),
        );
    }

    recs.truncate(8);
    recs
}

fn add_spike(spikes: &mut [f64], t: f64, amp: f64) {
    let n = spikes.len();
    let start = ((t / BIN_SEC).floor() as i64).clamp(0, n as i64 - 1) as usize;
    for k in 0..SPIKE_DECAY_BINS {
        let i = start + k;
        if i >= n {
            break;
        }
        spikes[i] += amp * 0.55f64.powi(k as i32);
    }
}

fn is_emotional(low_word: &str) -> bool {
    EMOTION_EN.iter().any(|w| low_word == *w)
        || EMOTION_AR.iter().any(|w| low_word.contains(w))
}

fn window_mean(points: &[(f64, f64)], from_t: f64, to_t: f64, fallback: f64) -> f64 {
    let picked: Vec<f64> = points
        .iter()
        .filter(|(t, _)| *t >= from_t && *t < to_t)
        .map(|(_, s)| *s)
        .collect();
    if picked.is_empty() {
        fallback
    } else {
        picked.iter().sum::<f64>() / picked.len() as f64
    }
}

fn round2(v: f64) -> f64 {
    (v * 100.0).round() / 100.0
}

fn round3(v: f64) -> f64 {
    (v * 1000.0).round() / 1000.0
}
