//! sound_forge.rs — Procedural SFX synthesizer (port of sound_forge.py).
//!
//! Pure-Rust DSP, no external audio crates: filtered-noise sweeps,
//! multi-harmonic risers, layered impacts, a synthesized drum kit,
//! evolving pads, bit-crushed zaps, vinyl textures and simple transients.
//! Renders are peak-normalized to -3 dBFS with anti-click edge fades and
//! can be written as 44.1 kHz mono 16-bit WAV with a stdlib-only writer.

use anyhow::Result;
use rand::{rngs::StdRng, Rng, SeedableRng};
use std::time::{SystemTime, UNIX_EPOCH};

pub const SAMPLE_RATE: i32 = 44_100;
const TWO_PI: f64 = core::f64::consts::TAU;
const PI: f64 = core::f64::consts::PI;
/// Target linear peak: -3 dBFS (= 10^(-3/20)).
const PEAK_LIN: f64 = 0.707_945_784_384_137_9;
const FADE_MS: f64 = 10.0;

pub struct SoundForge {
    pub sample_rate: i32,
    rng: StdRng,
}

impl Default for SoundForge {
    fn default() -> Self {
        Self::new()
    }
}

impl SoundForge {
    /// Entropy-seeded forge at 44.1 kHz.
    pub fn new() -> Self {
        Self::with_seed(SAMPLE_RATE, entropy_seed())
    }

    pub fn with_sample_rate(sample_rate: i32) -> Self {
        Self::with_seed(sample_rate, entropy_seed())
    }

    /// Deterministic forge: same seed ⇒ identical renders.
    pub fn with_seed(sample_rate: i32, seed: u64) -> Self {
        Self {
            sample_rate,
            rng: StdRng::seed_from_u64(seed),
        }
    }

    /// Render `sound_type` for `dur` seconds (`dur <= 0` picks a sane
    /// default per type). Unknown types yield an empty vector.
    ///
    /// Supported: `whoosh` / `whoosh_up` / `whoosh_down` / `whoosh_through`,
    /// `riser`, `impact`, `brainzap`, `kick` / `drum_hit`, `snare`, `hihat`,
    /// `pad` / `ambient_pad`, `vinyl_crackle`, `ding`, `pop`, `click`, `tick`.
    pub fn generate(&mut self, sound_type: &str, dur: f64) -> Vec<i16> {
        let dur = if dur > 0.0 { dur } else { default_duration(sound_type) };
        if dur <= 0.0 {
            return Vec::new();
        }
        let sr = self.sample_rate as f64;
        if sr <= 0.0 {
            return Vec::new();
        }
        let n = ((dur * sr) as usize).max(1);

        let rendered = match sound_type {
            "whoosh" | "whoosh_up" => self.gen_whoosh(n, "up", sr),
            "whoosh_down" => self.gen_whoosh(n, "down", sr),
            "whoosh_through" => self.gen_whoosh(n, "through", sr),
            "riser" => self.gen_riser(n, dur, sr),
            "impact" => self.gen_impact(n, sr),
            "brainzap" => self.gen_brainzap(n, dur, sr),
            "kick" | "drum_hit" => self.gen_kick(n, sr),
            "snare" => self.gen_snare(n, sr),
            "hihat" => self.gen_hihat(n, sr),
            "pad" | "ambient_pad" => self.gen_ambient_pad(n, dur, sr),
            "vinyl_crackle" => self.gen_vinyl_crackle(n, dur, sr),
            "ding" => self.gen_ding(n, sr),
            "pop" => self.gen_pop(n, sr),
            "click" => self.gen_click(n, sr),
            "tick" => self.gen_tick(n, sr),
            _ => return Vec::new(),
        };

        to_i16(&master(rendered, sr))
    }

    /// Write PCM samples as a 44.1 kHz mono 16-bit WAV (stdlib only).
    pub fn save_wav(path: &str, samples: &[i16]) -> Result<()> {
        let data_len = (samples.len() * 2) as u32;
        let mut buf = Vec::with_capacity(44 + samples.len() * 2);
        buf.extend_from_slice(b"RIFF");
        buf.extend_from_slice(&(36u32 + data_len).to_le_bytes());
        buf.extend_from_slice(b"WAVE");
        buf.extend_from_slice(b"fmt ");
        buf.extend_from_slice(&16u32.to_le_bytes()); // fmt chunk size
        buf.extend_from_slice(&1u16.to_le_bytes()); // PCM
        buf.extend_from_slice(&1u16.to_le_bytes()); // mono
        buf.extend_from_slice(&(SAMPLE_RATE as u32).to_le_bytes());
        buf.extend_from_slice(&((SAMPLE_RATE as u32) * 2).to_le_bytes()); // byte rate
        buf.extend_from_slice(&2u16.to_le_bytes()); // block align
        buf.extend_from_slice(&16u16.to_le_bytes()); // bits per sample
        buf.extend_from_slice(b"data");
        buf.extend_from_slice(&data_len.to_le_bytes());
        for s in samples {
            buf.extend_from_slice(&s.to_le_bytes());
        }

        if let Some(parent) = std::path::Path::new(path).parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent)?;
            }
        }
        std::fs::write(path, &buf)?;
        Ok(())
    }

    // ── generators ───────────────────────────────────────────────────────

    fn uniform(&mut self) -> f64 {
        self.rng.gen_range(-1.0..1.0)
    }

    fn noise_vec(&mut self, n: usize) -> Vec<f64> {
        (0..n).map(|_| self.uniform()).collect()
    }

    /// Band-swept filtered-noise whoosh.
    fn gen_whoosh(&mut self, n: usize, direction: &str, sr: f64) -> Vec<f64> {
        let (f0, f1): (f64, f64) = (200.0, 1200.0);
        let ratio = f1 / f0;
        let noise = self.noise_vec(n);

        let mut cutoffs = Vec::with_capacity(n);
        let mut amp = Vec::with_capacity(n);
        for i in 0..n {
            let p = i as f64 / n as f64;
            match direction {
                "down" => {
                    cutoffs.push(f1 * (1.0 / ratio).powf(p));
                    amp.push((1.0 - p).powf(1.4) * (1.0 - (1.0 - p).powf(5.0)));
                }
                "through" => {
                    let mid = (f0 * f1).sqrt();
                    cutoffs.push(f0 + (mid * 1.6 - f0) * (-((p - 0.45).powi(2)) / 0.08).exp());
                    amp.push((-((p - 0.42).powi(2)) / 0.06).exp());
                }
                _ => {
                    cutoffs.push(f0 * ratio.powf(p));
                    amp.push(p.powf(1.4) * (1.0 - p.powf(5.0)));
                }
            }
        }

        let body = lowpass_sweep(&noise, &cutoffs, sr);
        let core_mult = if direction == "through" { 0.8 } else { 0.55 };

        let mut out = Vec::with_capacity(n);
        let mut ph = 0.0;
        for i in 0..n {
            ph += TWO_PI * cutoffs[i] * core_mult / sr;
            out.push((body[i] * 0.85 + ph.sin() * 0.15) * amp[i]);
        }
        out
    }

    /// Multi-harmonic accelerating rise with tremolo and noise shimmer.
    fn gen_riser(&mut self, n: usize, dur: f64, sr: f64) -> Vec<f64> {
        let (start_freq, end_freq): (f64, f64) = (100.0, 2000.0);
        let harmonics: i32 = 3;
        let ratio = end_freq / start_freq;
        let norm: f64 = (1..=harmonics).map(|h| 1.0 / h as f64).sum();

        let mut out = Vec::with_capacity(n);
        let mut ph = 0.0;
        let mut shimmer_ph = 0.0;
        for i in 0..n {
            let p = i as f64 / n as f64;
            // Super-exponential curve → perceived acceleration.
            let f = start_freq * ratio.powf(p.powf(1.6));
            ph += TWO_PI * f / sr;
            let mut s = 0.0;
            for h in 1..=harmonics {
                s += (ph * h as f64).sin() / h as f64;
            }
            s /= norm;
            let trem = 0.75 + 0.25 * (TWO_PI * (6.0 + 10.0 * p) * p * dur).sin();
            shimmer_ph += TWO_PI * (f * 1.5) / sr;
            let shimmer = 0.06 * p * (self.uniform() + 0.5 * shimmer_ph.sin());
            out.push((s * trem + shimmer) * (0.30 + 0.70 * p));
        }
        out
    }

    /// Layered hit: sub thump + convolved burst + reverb tail.
    fn gen_impact(&mut self, n: usize, sr: f64) -> Vec<f64> {
        let punch = 0.8f64.clamp(0.1, 1.0);
        let sub_freq = 55.0;

        // Layer 1 — pitch-dropping sub thump.
        let mut sub = Vec::with_capacity(n);
        let mut ph = 0.0;
        for i in 0..n {
            let t = i as f64 / sr;
            let p = (t / 0.12).min(1.0);
            let f = sub_freq * (1.6 - 0.6 * p);
            ph += TWO_PI * f / sr;
            sub.push((1.4 * ph.sin()).tanh() * exp_decay(t, 5.0 + 5.0 * punch));
        }

        // Layer 2 — sharp transient smeared by short early-reflection convolution.
        let nb = n.min((0.09 * sr) as usize);
        let burst_raw: Vec<f64> = (0..nb)
            .map(|i| self.uniform() * exp_decay(i as f64 / sr, 45.0 + 30.0 * punch))
            .collect();
        let burst = convolve(&burst_raw, &decay_kernel(sr, 97, 0.004));

        // Layer 3 — dark decaying reverb tail.
        let tail_noise = self.noise_vec(n);
        let tail_cutoffs: Vec<f64> =
            (0..n).map(|i| 1400.0 - 1100.0 * (i as f64 / n as f64)).collect();
        let tail_lp = lowpass_sweep(&tail_noise, &tail_cutoffs, sr);
        let td = 0.025;

        let mut mix = Vec::with_capacity(n);
        for i in 0..n {
            let t = i as f64 / sr;
            let mut v = sub[i] * (0.55 + 0.45 * punch);
            if i < burst.len() {
                v += burst[i] * 0.65;
            }
            let e = if t <= td { 0.0 } else { exp_decay(t - td, 3.2 + 2.0 * punch) };
            v += tail_lp[i] * e * 0.38;
            mix.push(v.clamp(-1.0, 1.0));
        }
        mix
    }

    /// Glitchy bit-crushed zap: swept saw, sample-hold, quantize, glitches.
    fn gen_brainzap(&mut self, n: usize, dur: f64, sr: f64) -> Vec<f64> {
        let mut raw = Vec::with_capacity(n);
        let mut ph = 0.0;
        for i in 0..n {
            let p = i as f64 / n as f64;
            let f = 2600.0 * 0.06f64.powf(p);
            ph += TWO_PI * f / sr;
            let cyc = (ph / TWO_PI) % 1.0;
            let saw = 2.0 * cyc - 1.0;
            let ring = 0.8 + 0.2 * (TWO_PI * 37.0 * i as f64 / sr).sin();
            raw.push(saw * ring * exp_decay(p * dur, 9.0));
        }

        // Bit crush: sample-and-hold decimation + coarse quantization + drive.
        let hold = ((sr / 9000.0) as usize).max(1);
        let levels = 14.0;
        let mut crushed = Vec::with_capacity(n);
        let mut held = 0.0;
        for (i, &r) in raw.iter().enumerate() {
            if i % hold == 0 {
                held = r;
            }
            let v = (held * 3.0).tanh() / 3.0f64.tanh();
            crushed.push(((v * levels).round() / levels).clamp(-1.0, 1.0));
        }

        // Glitch surgery: reverse a few random slices.
        if n >= 8 {
            for _ in 0..4 {
                let start = self.rng.gen_range(0..(n - 2).max(1));
                let lo = 4.min(n - 1 - start).max(1);
                let hi = ((n / 3).max(5)).max(lo + 1);
                let ln = self.rng.gen_range(lo..hi).min(n - start);
                crushed[start..start + ln].reverse();
            }
        }
        crushed
    }

    /// Synthesized kick: pitch-dropping sine body + noise click.
    fn gen_kick(&mut self, n: usize, sr: f64) -> Vec<f64> {
        let pitch = 1.0;
        let mut out = Vec::with_capacity(n);
        let mut ph = 0.0;
        for i in 0..n {
            let t = i as f64 / sr;
            let p = (t / 0.08).min(1.0);
            let f = (160.0 - 112.0 * p) * pitch;
            ph += TWO_PI * f / sr;
            let body = (1.6 * ph.sin()).tanh() * exp_decay(t, 11.0);
            let click = self.uniform() * exp_decay(t, 300.0) * 0.4;
            out.push(body + click);
        }
        out
    }

    /// Synthesized snare: dual-tone body + high-passed noise snap.
    fn gen_snare(&mut self, n: usize, sr: f64) -> Vec<f64> {
        let pitch = 1.0;
        let noise = self.noise_vec(n);
        let snap = highpass(&noise, 1400.0, sr);
        let mut out = Vec::with_capacity(n);
        let mut ph1 = 0.0;
        let mut ph2 = 0.0;
        for i in 0..n {
            let t = i as f64 / sr;
            ph1 += TWO_PI * 190.0 * pitch / sr;
            ph2 += TWO_PI * 335.0 * pitch / sr;
            let body = 0.5 * (ph1.sin() + 0.7 * ph2.sin()) * exp_decay(t, 20.0);
            out.push((body + 0.9 * snap[i] * exp_decay(t, 24.0)).clamp(-1.0, 1.0));
        }
        out
    }

    /// 808-style inharmonic square bank, high-passed, with dust ping.
    fn gen_hihat(&mut self, n: usize, sr: f64) -> Vec<f64> {
        let pitch = 1.0;
        let ratios = [2.0, 3.0, 4.16, 5.43, 6.79, 8.21];
        let base = 40.0 * pitch;
        let metal: Vec<f64> = (0..n)
            .map(|i| {
                let t = i as f64 / sr;
                let bank: f64 = ratios
                    .iter()
                    .map(|r| (TWO_PI * base * r * t).sin().copysign(1.0))
                    .sum();
                bank / ratios.len() as f64 * exp_decay(t, 42.0)
            })
            .collect();
        let bright = highpass(&metal, 7000.0, sr);
        let mut out = Vec::with_capacity(n);
        for (i, &b) in bright.iter().enumerate() {
            let ping = self.uniform() * exp_decay(i as f64 / sr, 250.0) * 0.25;
            out.push((b * 0.9 + ping).clamp(-1.0, 1.0));
        }
        out
    }

    /// Evolving detuned chord pad with per-voice LFO breathing.
    fn gen_ambient_pad(&mut self, n: usize, dur: f64, sr: f64) -> Vec<f64> {
        let chord = [220.0, 277.18, 329.63]; // A3 C#4 E4
        let evo = 0.3f64.clamp(0.0, 1.0);
        let att = (((n as f64) * 0.32) as usize).max(1);
        let rel = (((n as f64) * 0.34) as usize).max(1);

        struct Voice {
            f: f64,
            lfo_hz: f64,
            lfo_ph: f64,
            det_ph: f64,
        }
        let voices: Vec<Voice> = chord
            .iter()
            .map(|&f| Voice {
                f,
                lfo_hz: 0.07 + self.rng.gen_range(0.0..0.22),
                lfo_ph: self.rng.gen_range(0.0..TWO_PI),
                det_ph: self.rng.gen_range(0.0..TWO_PI),
            })
            .collect();

        let mut out = vec![0.0; n];
        for v in &voices {
            let mut ph_l = 0.0;
            let mut ph_r = 0.0;
            for (i, o) in out.iter_mut().enumerate() {
                let p = i as f64 / n as f64;
                let drift = 1.0 + evo * 0.006 * (TWO_PI * 0.11 * p * dur + v.det_ph).sin();
                let fl = v.f * drift * 1.0006;
                let fr = v.f * drift * 0.9994;
                ph_l += TWO_PI * fl / sr;
                ph_r += TWO_PI * fr / sr;
                let lfo = 1.0
                    - (0.05 + 0.18 * evo)
                        * (0.5 + 0.5 * (v.lfo_ph + TWO_PI * v.lfo_hz * p * dur).sin());
                let bright_h = evo * (0.10 + 0.22 * p);
                let tone = 0.5 * (ph_l.sin() + ph_r.sin()) + bright_h * (2.0 * ph_l).sin();
                let env = if i < att {
                    0.5 - 0.5 * (PI * i as f64 / att as f64).cos()
                } else if i > n - rel {
                    0.5 - 0.5 * (PI * (n - i) as f64 / rel as f64).cos()
                } else {
                    1.0
                };
                *o += tone * lfo * env / voices.len() as f64;
            }
        }
        out
    }

    /// Surface-noise floor sprinkled with Poisson-ish dust pops.
    fn gen_vinyl_crackle(&mut self, n: usize, dur: f64, sr: f64) -> Vec<f64> {
        let density = 0.3f64.clamp(0.0, 1.0);
        let hiss_src = self.noise_vec(n);
        let hiss = lowpass(&hiss_src, 2200.0, sr);
        let rumble_src = self.noise_vec(n);
        let rumble = lowpass(&rumble_src, 110.0, sr);
        let mut out: Vec<f64> = (0..n).map(|i| hiss[i] * 0.16 + rumble[i] * 0.28).collect();

        let expected = (density * dur * 90.0) as usize;
        for _ in 0..expected {
            let pos = self.rng.gen_range(0..n);
            let ln = self.rng.gen_range(24..=170);
            let amp = self.rng.gen_range(0.35..1.0) * (0.4 + 0.6 * density);
            let flip = if self.rng.gen_bool(0.5) { 1.0 } else { -1.0 };
            let span = ln.min(n - pos);
            for (j, o) in out[pos..pos + span].iter_mut().enumerate() {
                *o += flip * amp * (PI * j as f64 / ln as f64).cos() * exp_decay(j as f64 / sr, 900.0);
            }
        }
        out
    }

    /// Bright bell strike with long shimmering decay.
    fn gen_ding(&mut self, n: usize, sr: f64) -> Vec<f64> {
        let (f1, f2) = (1318.51, 1318.51 * 2.4); // E6 + inharmonic partial
        let mut ph1 = 0.0;
        let mut ph2 = 0.0;
        let mut det = 0.0;
        let mut out = Vec::with_capacity(n);
        for i in 0..n {
            let t = i as f64 / sr;
            ph1 += TWO_PI * f1 / sr;
            ph2 += TWO_PI * f2 / sr;
            det += TWO_PI * f1 * 1.003 / sr; // slow-beating detune voice
            let strike = if t < 0.004 { self.uniform() * (1.0 - t / 0.004) } else { 0.0 };
            let body = (0.55 * ph1.sin() + 0.2 * ph2.sin() + 0.25 * det.sin()) * exp_decay(t, 4.5);
            out.push(body + strike * 0.35 * exp_decay(t, 120.0));
        }
        out
    }

    /// Short pitch-drop bubble blip.
    fn gen_pop(&mut self, n: usize, sr: f64) -> Vec<f64> {
        let mut ph = 0.0;
        let mut out = Vec::with_capacity(n);
        for i in 0..n {
            let t = i as f64 / sr;
            let p = (t / 0.045).min(1.0);
            let f = 900.0 - 740.0 * p; // 900 → 160 Hz
            ph += TWO_PI * f / sr;
            out.push((1.8 * ph.sin()).tanh() * exp_decay(t, 34.0));
        }
        out
    }

    /// Dry micro noise burst with a tiny metallic ping.
    fn gen_click(&mut self, n: usize, sr: f64) -> Vec<f64> {
        let mut out = Vec::with_capacity(n);
        for i in 0..n {
            let t = i as f64 / sr;
            let burst = self.uniform() * exp_decay(t, 420.0);
            let ping = (TWO_PI * 2000.0 * t).sin() * exp_decay(t, 600.0) * 0.3;
            out.push((burst + ping).clamp(-1.0, 1.0));
        }
        out
    }

    /// Tight high-passed UI tick.
    fn gen_tick(&mut self, n: usize, sr: f64) -> Vec<f64> {
        let src = self.noise_vec(n);
        let hp = highpass(&src, 2500.0, sr);
        let mut out = Vec::with_capacity(n);
        for (i, &h) in hp.iter().enumerate() {
            let t = i as f64 / sr;
            let ping = (TWO_PI * 2100.0 * t).sin() * exp_decay(t, 320.0) * 0.5;
            out.push(h * exp_decay(t, 260.0) * 0.8 + ping);
        }
        out
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DSP helpers
// ─────────────────────────────────────────────────────────────────────────────

fn entropy_seed() -> u64 {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0x5EED);
    nanos ^ (nanos << 21) ^ (nanos >> 17)
}

fn exp_decay(t: f64, rate: f64) -> f64 {
    (-t * rate).exp()
}

/// Static one-pole lowpass.
fn lowpass(samples: &[f64], cutoff_hz: f64, sr: f64) -> Vec<f64> {
    let a = 1.0 - (-TWO_PI * cutoff_hz / sr).exp();
    let mut y = 0.0;
    samples
        .iter()
        .map(|&x| {
            y += a * (x - y);
            y
        })
        .collect()
}

/// First-order highpass = input − lowpass.
fn highpass(samples: &[f64], cutoff_hz: f64, sr: f64) -> Vec<f64> {
    let lp = lowpass(samples, cutoff_hz, sr);
    samples.iter().zip(lp).map(|(x, l)| x - l).collect()
}

/// Time-varying one-pole lowpass; one cutoff Hz value per sample.
fn lowpass_sweep(samples: &[f64], cutoffs: &[f64], sr: f64) -> Vec<f64> {
    let mut y = 0.0;
    samples
        .iter()
        .zip(cutoffs)
        .map(|(&x, &fc)| {
            let a = 1.0 - (-TWO_PI * fc.max(10.0) / sr).exp();
            y += a * (x - y);
            y
        })
        .collect()
}

/// Direct O(n*k) convolution — kept to small kernels on purpose.
fn convolve(signal: &[f64], kernel: &[f64]) -> Vec<f64> {
    if signal.is_empty() || kernel.is_empty() {
        return Vec::new();
    }
    let k = kernel.len();
    let mut out = vec![0.0; signal.len() + k - 1];
    for (i, &s) in signal.iter().enumerate() {
        if s == 0.0 {
            continue;
        }
        for (j, &kj) in kernel.iter().enumerate() {
            out[i + j] += s * kj;
        }
    }
    out.truncate(signal.len());
    out
}

/// Normalized exponentially-decaying impulse response (reverb smear).
fn decay_kernel(sr: f64, taps: usize, tau_sec: f64) -> Vec<f64> {
    let kern: Vec<f64> = (0..taps).map(|j| exp_decay(j as f64 / sr, 1.0 / tau_sec)).collect();
    let sum: f64 = kern.iter().sum();
    if sum.abs() < 1e-12 {
        kern
    } else {
        kern.into_iter().map(|v| v / sum).collect()
    }
}

/// Peak-normalize to target linear peak (-3 dBFS).
fn normalize(mut v: Vec<f64>) -> Vec<f64> {
    let m = v.iter().fold(0.0f64, |a, &s| a.max(s.abs()));
    if m >= 1e-9 {
        let k = PEAK_LIN / m;
        for s in v.iter_mut() {
            *s *= k;
        }
    }
    v
}

/// Linear fade-in/out on both edges to kill clicks.
fn fade_edges(mut v: Vec<f64>, sr: f64) -> Vec<f64> {
    if v.is_empty() {
        return v;
    }
    let nf = (sr * FADE_MS / 1000.0).max(1.0);
    let m = (nf as usize).min(v.len());
    for i in 0..m {
        let g = i as f64 / nf;
        v[i] *= g;
        let j = v.len() - 1 - i;
        v[j] *= g;
    }
    v
}

/// Peak-normalize to -3 dBFS, then anti-click edge fades.
fn master(v: Vec<f64>, sr: f64) -> Vec<f64> {
    fade_edges(normalize(v), sr)
}

fn to_i16(v: &[f64]) -> Vec<i16> {
    v.iter()
        .map(|&s| (s.clamp(-1.0, 1.0) * 32767.0).round() as i16)
        .collect()
}

fn default_duration(sound_type: &str) -> f64 {
    match sound_type {
        "whoosh" | "whoosh_up" | "whoosh_down" | "whoosh_through" => 0.8,
        "riser" => 2.0,
        "impact" => 0.5,
        "brainzap" => 0.3,
        "kick" | "drum_hit" => 0.5,
        "snare" => 0.4,
        "hihat" => 0.15,
        "pad" | "ambient_pad" => 3.0,
        "vinyl_crackle" => 2.0,
        "ding" => 0.8,
        "pop" => 0.12,
        "click" => 0.03,
        "tick" => 0.05,
        _ => 0.0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generates_all_types() {
        let mut sf = SoundForge::with_seed(SAMPLE_RATE, 42);
        for t in [
            "whoosh",
            "whoosh_down",
            "whoosh_through",
            "riser",
            "impact",
            "brainzap",
            "kick",
            "snare",
            "hihat",
            "pad",
            "vinyl_crackle",
            "ding",
            "pop",
            "click",
            "tick",
        ] {
            let s = sf.generate(t, 0.05);
            assert!(!s.is_empty(), "{t} produced no samples");
        }
        assert!(sf.generate("bogus", 0.1).is_empty());
    }

    #[test]
    fn deterministic_per_seed() {
        let a = SoundForge::with_seed(SAMPLE_RATE, 7).generate("whoosh", 0.05);
        let b = SoundForge::with_seed(SAMPLE_RATE, 7).generate("whoosh", 0.05);
        assert_eq!(a, b);
    }

    #[test]
    fn wav_header_and_size() {
        let mut sf = SoundForge::with_seed(SAMPLE_RATE, 1);
        let s = sf.generate("pop", 0.02);
        let path = std::env::temp_dir().join("sf_test_header.wav");
        SoundForge::save_wav(path.to_str().unwrap(), &s).unwrap();
        let bytes = std::fs::read(&path).unwrap();
        assert_eq!(bytes.len(), 44 + s.len() * 2);
        assert_eq!(&bytes[0..4], b"RIFF");
        assert_eq!(&bytes[8..12], b"WAVE");
        let _ = std::fs::remove_file(&path);
    }
}
