//! audio_craft.rs — Voice/audio post-processing chain builder for ffmpeg.
//!
//! Builds platform-tuned filter chains: high-pass → de-noise → EQ
//! (bass + presence) → de-ess → loudness normalization, plus ready-to-use
//! ffmpeg argument vectors for the individual stages.
//!
//! Loudness targets (integrated LUFS):
//! - tiktok / instagram / reels: -14 LUFS
//! - youtube: -9 LUFS  (aggressive, per product spec)
//! - anything else falls back to -14 LUFS.

use serde::{Deserialize, Serialize};

/// Per-voice enhancement switches and EQ trims.
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct AudioOptions {
    /// Enable `afftdn` noise reduction.
    #[serde(default)]
    pub de_noise: bool,
    /// Enable `deesser` sibilance taming.
    #[serde(default)]
    pub de_ess: bool,
    /// Low-shelf gain in dB around 120 Hz (0 = off).
    #[serde(default)]
    pub bass_boost_db: f64,
    /// Presence peak boost in dB at ~3.2 kHz (0 = off).
    #[serde(default)]
    pub presence_boost_db: f64,
}

impl Default for AudioOptions {
    fn default() -> Self {
        Self {
            de_noise: true,
            de_ess: true,
            bass_boost_db: 3.0,
            presence_boost_db: 2.0,
        }
    }
}

/// Platform loudness target in integrated LUFS.
pub fn platform_target_lufs(platform: &str) -> f64 {
    match platform.to_ascii_lowercase().as_str() {
        "youtube" | "yt" => -9.0,
        _ => -14.0, // tiktok, instagram, reels, default
    }
}

const DENOISE_FILTER: &str = "afftdn=nr=12:nf=-40:tn=1";
const DEESS_FILTER: &str = "deesser=i=0.15:m=0.5:f=0.5";

/// ffmpeg args that normalize a file to the platform loudness target.
pub fn loudness_normalize_args(platform: &str) -> Vec<String> {
    let lufs = platform_target_lufs(platform);
    vec![
        "-af".into(),
        format!("loudnorm=I={:.1}:TP=-1.5:LRA=11", lufs),
        "-ar".into(),
        "48000".into(),
        "-c:a".into(),
        "aac".into(),
        "-b:a".into(),
        "192k".into(),
    ]
}

/// ffmpeg args for FFT-based denoising (`afftdn`).
pub fn de_noise_args() -> Vec<String> {
    vec!["-af".into(), DENOISE_FILTER.into()]
}

/// ffmpeg args for de-essing (`deesser`).
pub fn de_ess_args() -> Vec<String> {
    vec!["-af".into(), DEESS_FILTER.into()]
}

/// Build the full single-pass `-af` chain:
/// highpass → [de-noise] → EQ (bass/presence) → [de-ess] → loudnorm.
///
/// The chain always ends with `loudnorm` targeting the platform's LUFS.
pub fn build_audio_filter_chain(platform: &str, options: AudioOptions) -> String {
    let mut stages: Vec<String> = Vec::with_capacity(6);

    // 1) Rumble/hum cleanup.
    stages.push("highpass=f=75".into());

    // 2) Broadband noise reduction.
    if options.de_noise {
        stages.push(DENOISE_FILTER.into());
    }

    // 3) Tone shaping.
    if options.bass_boost_db.abs() > f64::EPSILON {
        stages.push(format!(
            "bass=g={:+.1}:f=120:t=q:w=0.7",
            options.bass_boost_db.clamp(-12.0, 12.0)
        ));
    }
    if options.presence_boost_db.abs() > f64::EPSILON {
        stages.push(format!(
            "equalizer=g={:+.1}:f=3200:t=q:w=1.2",
            options.presence_boost_db.clamp(-12.0, 12.0)
        ));
    }

    // 4) Sibilance control.
    if options.de_ess {
        stages.push(DEESS_FILTER.into());
    }

    // 5) Platform loudness normalization.
    stages.push(format!(
        "loudnorm=I={:.1}:TP=-1.5:LRA=11",
        platform_target_lufs(platform)
    ));

    stages.join(",")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loudness_targets_per_platform() {
        assert_eq!(platform_target_lufs("tiktok"), -14.0);
        assert_eq!(platform_target_lufs("instagram"), -14.0);
        assert_eq!(platform_target_lufs("YouTube"), -9.0);
        assert_eq!(platform_target_lufs("unknown"), -14.0);
    }

    #[test]
    fn normalize_args_carry_loudnorm() {
        let args = loudness_normalize_args("tiktok");
        assert!(args.windows(2).any(|w| w[0] == "-af" && w[1].contains("I=-14.0")));
        let yt = loudness_normalize_args("youtube");
        assert!(yt.iter().any(|a| a.contains("I=-9.0")));
    }

    #[test]
    fn stage_arg_vectors_are_flag_value_pairs() {
        assert_eq!(de_noise_args(), vec!["-af", DENOISE_FILTER]);
        assert_eq!(de_ess_args(), vec!["-af", DEESS_FILTER]);
    }

    #[test]
    fn full_chain_order_is_correct() {
        let chain = build_audio_filter_chain(
            "youtube",
            AudioOptions {
                de_noise: true,
                de_ess: true,
                bass_boost_db: 4.0,
                presence_boost_db: 2.5,
            },
        );
        let stages: Vec<&str> = chain.split(',').collect();
        assert_eq!(stages.len(), 6);
        assert_eq!(stages[0], "highpass=f=75");
        assert!(stages[1].starts_with("afftdn"));
        assert!(stages[2].starts_with("bass=g="));
        assert!(stages[2].contains("+4.0"));
        assert!(stages[3].starts_with("equalizer=g="));
        assert!(stages[4].starts_with("deesser"));
        assert!(chain.ends_with("loudnorm=I=-9.0:TP=-1.5:LRA=11"));
    }

    #[test]
    fn disabled_stages_are_omitted() {
        let chain = build_audio_filter_chain(
            "tiktok",
            AudioOptions {
                de_noise: false,
                de_ess: false,
                bass_boost_db: 0.0,
                presence_boost_db: 0.0,
            },
        );
        assert!(!chain.contains("afftdn"));
        assert!(!chain.contains("deesser"));
        assert!(!chain.contains("bass="));
        assert_eq!(chain, "highpass=f=75,loudnorm=I=-14.0:TP=-1.5:LRA=11");
    }
}
