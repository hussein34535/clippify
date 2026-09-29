/// System API — hardware probe + performance tier verdict + ffmpeg resolver.
use axum::{routing::get, Json, Router};
use serde_json::{json, Value};

use crate::media::MediaEngine;

pub fn router() -> Router {
    Router::new()
        .route("/tier", get(tier))
        .route("/ffmpeg", get(ffmpeg))
}

static CACHED: tokio::sync::OnceCell<Value> = tokio::sync::OnceCell::const_new();

async fn tier() -> Json<Value> {
    Json(CACHED.get_or_init(collect).await.clone())
}

async fn ffmpeg() -> Json<Value> {
    let engine = MediaEngine::new();
    let path = engine.ffmpeg_path.clone();
    let found = tokio::process::Command::new(&path)
        .arg("-version")
        .output()
        .await
        .map(|o| o.status.success())
        .unwrap_or(false);
    Json(json!({"path": path, "found": found}))
}

async fn collect() -> Value {
    let threads = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(0);

    let ram_gb = probe_ram_gb();
    let nvidia_smi_ok = nvidia_smi_reachable().await;
    let (gpus, nvidia_vram_gb) = probe_gpus().await;
    let accel = probe_accel(nvidia_smi_ok).await;
    let engine = MediaEngine::new();
    let ffmpeg_found = ffmpeg_exists(&engine.ffmpeg_path);

    let mut payload = json!({
        "cpu": {"cores": threads, "threads": threads},
        "ram_gb": ram_gb,
        "gpus": gpus,
        "nvidia_vram_gb": nvidia_vram_gb,
        "accel": accel,
        "ffmpeg_path": if ffmpeg_found { Some(engine.ffmpeg_path.clone()) } else { None },
    });
    let verdict = decide_tier(
        accel["nvenc"].as_bool().unwrap_or(false),
        accel["qsv"].as_bool().unwrap_or(false),
        accel["cuda"].as_bool().unwrap_or(false),
        ram_gb,
        threads,
        nvidia_vram_gb,
    );
    if let Some(obj) = payload.as_object_mut() {
        for (k, v) in verdict.as_object().expect("verdict object") {
            obj.insert(k.clone(), v.clone());
        }
    }
    payload
}

#[cfg(windows)]
fn probe_ram_gb() -> f64 {
    #[repr(C)]
    struct MemoryStatusEx {
        dw_length: u32,
        dw_memory_load: u32,
        ull_total_phys: u64,
        ull_avail_phys: u64,
        ull_total_page_file: u64,
        ull_avail_page_file: u64,
        ull_total_virtual: u64,
        ull_avail_virtual: u64,
        ull_avail_extended_virtual: u64,
    }
    extern "system" {
        #[link_name = "GlobalMemoryStatusEx"]
        fn global_memory_status_ex(lp_buffer: *mut MemoryStatusEx) -> i32;
    }
    let mut ms = MemoryStatusEx {
        dw_length: std::mem::size_of::<MemoryStatusEx>() as u32,
        dw_memory_load: 0,
        ull_total_phys: 0,
        ull_avail_phys: 0,
        ull_total_page_file: 0,
        ull_avail_page_file: 0,
        ull_total_virtual: 0,
        ull_avail_virtual: 0,
        ull_avail_extended_virtual: 0,
    };
    let ok = unsafe { global_memory_status_ex(&mut ms) };
    if ok != 0 {
        round2(ms.ull_total_phys as f64 / 1024.0 / 1024.0 / 1024.0)
    } else {
        0.0
    }
}

#[cfg(not(windows))]
fn probe_ram_gb() -> f64 {
    if let Ok(meminfo) = std::fs::read_to_string("/proc/meminfo") {
        for line in meminfo.lines() {
            if let Some(rest) = line.strip_prefix("MemTotal:") {
                let kb: f64 = rest
                    .trim()
                    .trim_end_matches("kB")
                    .trim()
                    .parse()
                    .unwrap_or(0.0);
                return round2(kb / 1024.0 / 1024.0);
            }
        }
    }
    0.0
}

/// Returns (gpus list, summed NVIDIA VRAM in GB) via nvidia-smi.
async fn probe_gpus() -> (Vec<Value>, f64) {
    let mut gpus = Vec::new();
    let mut total_gb = 0.0f64;
    for candidate in smi_candidates() {
        let out = tokio::process::Command::new(&candidate)
            .args(["--query-gpu=name,memory.total", "--format=csv,noheader,nounits"])
            .output()
            .await;
        if let Ok(out) = out {
            if !out.status.success() {
                continue;
            }
            let text = String::from_utf8_lossy(&out.stdout);
            for line in text.lines() {
                let line = line.trim();
                if line.is_empty() {
                    continue;
                }
                let parts: Vec<&str> = line.split(',').collect();
                if parts.len() < 2 {
                    continue;
                }
                let name = parts[0].trim();
                if name.is_empty() {
                    continue;
                }
                let mib: f64 = parts[1].trim().parse().unwrap_or(0.0);
                let vram_gb = round2(mib / 1024.0);
                total_gb += vram_gb;
                gpus.push(json!({"name": name, "vram_gb": vram_gb}));
            }
            if !gpus.is_empty() {
                return (gpus, round2(total_gb));
            }
        }
    }
    (gpus, round2(total_gb))
}

async fn nvidia_smi_reachable() -> bool {
    for candidate in smi_candidates() {
        if let Ok(out) = tokio::process::Command::new(&candidate).output().await {
            if out.status.success() {
                return true;
            }
        }
    }
    false
}

fn smi_candidates() -> Vec<String> {
    let mut cands = vec!["nvidia-smi".to_string()];
    if let Ok(cuda_path) = std::env::var("CUDA_PATH") {
        if !cuda_path.is_empty() {
            cands.push(format!("{}\\nvidia-smi.exe", cuda_path));
            cands.push(format!("{}\\bin\\nvidia-smi.exe", cuda_path));
        }
    }
    cands.push("C:\\Windows\\System32\\nvidia-smi.exe".to_string());
    cands.retain(|c| c == "nvidia-smi" || std::path::Path::new(c).exists());
    cands
}

async fn probe_accel(nvidia_smi_ok: bool) -> Value {
    let engine = MediaEngine::new();
    let mut nvenc = false;
    let mut qsv = false;
    let mut vaapi = false;
    if let Ok(out) = tokio::process::Command::new(&engine.ffmpeg_path)
        .args(["-hide_banner", "-encoders"])
        .output()
        .await
    {
        let blob = String::from_utf8_lossy(&out.stdout).to_string()
            + &String::from_utf8_lossy(&out.stderr);
        nvenc = blob.contains("_nvenc");
        qsv = blob.contains("_qsv");
        vaapi = blob.contains("_vaapi");
    }
    json!({
        "nvenc": nvenc && nvidia_smi_ok,
        "qsv": qsv,
        "vaapi": vaapi,
        "cuda": nvidia_smi_ok,
    })
}

fn ffmpeg_exists(path: &str) -> bool {
    let p = std::path::Path::new(path);
    path.contains(std::path::MAIN_SEPARATOR) && p.exists()
}

/// Exact port of system_probe/probe.py::decide_tier rules:
///   S  : nvenc AND vram >= 6
///   A+ : ram>=8 AND threads>=8 AND ((nvenc AND vram>=4) OR qsv)
///   A  : ram>=8 AND threads>=8
///   B  : ram >= 4
///   C  : everything else
pub fn decide_tier(
    nvenc: bool,
    qsv: bool,
    cuda: bool,
    ram_gb: f64,
    threads: usize,
    nvidia_vram_gb: f64,
) -> Value {
    let strong_cpu = ram_gb >= 8.0 && threads >= 8;

    let (tier, why_ar);
    if nvenc && nvidia_vram_gb >= 6.0 {
        tier = "S";
        why_ar = format!(
            "NVENC شغال مع {}GB فيديو رام — تشفير عتادي بلا حدود، خليه يولّع.",
            fmt_g(nvidia_vram_gb)
        );
    } else if strong_cpu && ((nvenc && nvidia_vram_gb >= 4.0) || qsv) {
        tier = "A+";
        if nvenc {
            why_ar = format!(
                "NVENC مع {}GB VRAM و{}GB رام — تشفير سريع ومتوازن.",
                fmt_g(nvidia_vram_gb),
                fmt_g(ram_gb)
            );
        } else {
            why_ar = format!("QSV من إنتل يسرّع التشفير عتادياً مع {}GB رام.", fmt_g(ram_gb));
        }
    } else if strong_cpu {
        tier = "A";
        why_ar = format!(
            "{}GB رام و{} ثريد — قلب المونتاج بدون تسريع كروت.",
            fmt_g(ram_gb),
            threads
        );
    } else if ram_gb >= 4.0 {
        tier = "B";
        why_ar = format!("{}GB رام تكفي للمشاريع الخفيفة فقط.", fmt_g(ram_gb));
    } else {
        tier = "C";
        why_ar = format!("{}GB رام بس — سيب المعالجة للسحابة.", fmt_g(ram_gb));
    }

    let labels = match tier {
        "S" => ("🔥 وضع الوحش", "Beast Mode"),
        "A+" => ("⚡ وضع السريع", "Fast Mode"),
        "A" => ("💻 المتوازن", "Balanced Mode"),
        "B" => ("🪶 الخفيف", "Featherweight"),
        _ => ("☁️ السحابي الصرف", "Pure Cloud"),
    };

    let mut flags: Vec<&str> = Vec::new();
    if cuda {
        flags.push("cuda");
    }
    if nvenc {
        flags.push("nvenc");
    }
    if qsv {
        flags.push("qsv");
    }
    let accel_summary = if flags.is_empty() {
        "none".to_string()
    } else {
        flags.join("+")
    };

    json!({
        "tier": tier,
        "label_ar": labels.0,
        "label_en": labels.1,
        "why_ar": why_ar,
        "accel_summary": accel_summary,
        "cuda_available": cuda,
    })
}

fn round2(v: f64) -> f64 {
    (v * 100.0).round() / 100.0
}

/// Python "{value:g}" equivalent — trims trailing zeros/decimal point.
fn fmt_g(v: f64) -> String {
    let s = format!("{:.2}", v);
    let s = s.trim_end_matches('0').trim_end_matches('.');
    if s.is_empty() || s == "-" {
        "0".to_string()
    } else {
        s.to_string()
    }
}
