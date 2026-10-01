// Clippify Engine — final wiring (all squads' modules).
mod api;
mod db;
mod llm;
mod media;
mod render;
mod transcribe;
mod types;

// Engine modules consumed by the API layer; some helpers are not yet
// referenced end-to-end, so suppress dead-code noise here.
#[allow(dead_code)]
mod critic;
#[allow(dead_code)]
mod director;
#[allow(dead_code)]
mod fair_queue;
#[allow(dead_code)]
mod motion;
#[allow(dead_code)]
mod narrative;
#[allow(dead_code)]
mod palette;
#[allow(dead_code)]
mod scenario;
#[allow(dead_code)]
mod sound_forge;
#[allow(dead_code)]
mod style_dna;
#[allow(dead_code)]
mod trend;
#[allow(dead_code)]
mod brief_parser;
#[allow(dead_code)]
mod hook_ab;
#[allow(dead_code)]
mod attention_score;
#[allow(dead_code)]
mod captions_v3;
#[allow(dead_code)]
mod audio_craft;
#[allow(dead_code)]
mod magic_preview;

use clap::{Parser, Subcommand};
use serde_json::json;

// No new dependencies: kernel32 link lets the engine (and, by inheritance,
// every ffmpeg child it spawns) fail with an exit code instead of popping a
// Windows "Application Error" dialog on native crashes.
#[cfg(windows)]
#[link(name = "kernel32")]
extern "system" {
    fn SetErrorMode(uMode: u32) -> u32;
}

#[cfg(windows)]
fn suppress_crash_dialogs() {
    // SEM_FAILCRITICALERRORS (0x0001) | SEM_NOGPFAULTERRORBOX (0x0002).
    unsafe {
        SetErrorMode(0x0001 | 0x0002);
    }
}

#[cfg(not(windows))]
fn suppress_crash_dialogs() {}

#[derive(Parser)]
#[command(name = "clippify_engine", about = "Clippify Rust Engine")]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
    #[arg(long, default_value = "8000")]
    port: u16,
}

#[derive(Subcommand)]
enum Commands {
    /// Probe media duration
    Duration { path: String },
    /// Detect silences
    Silences {
        path: String,
        #[arg(long, default_value = "-30")]
        noise_db: f64,
        #[arg(long, default_value = "0.5")]
        min_dur: f64,
    },
    /// Extract thumbnails
    Thumbnails {
        path: String,
        #[arg(long, default_value = "8")]
        count: usize,
        #[arg(long, default_value = "cache/thumbs")]
        out: String,
    },
    /// LLM ask
    Ask {
        prompt: String,
        #[arg(long, default_value = "0.5")]
        temperature: f64,
        #[arg(long, default_value_t = false)]
        json_mode: bool,
    },
    /// LLM status
    Status,
    /// Render clips
    Render {
        #[arg(long)]
        video: String,
        #[arg(long)]
        output: String,
        /// JSON array of clip specs
        #[arg(long)]
        clips: String,
    },
    /// Transcribe (requires whisper.cpp)
    Transcribe { path: String },
    /// Run the HTTP API server
    Serve {
        #[arg(long, default_value_t = 8000)]
        port: u16,
    },
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    suppress_crash_dialogs();
    let cli = Cli::parse();
    let media = media::MediaEngine::new();

    // Default: serve on cli.port when no subcommand given (standalone mode)
    let command = cli.command.unwrap_or(Commands::Serve { port: cli.port });

    match command {
        Commands::Duration { path } => {
            let dur = media.probe_duration(&path).await?;
            println!("{}", json!({"status": "ok", "duration": dur}));
        }
        Commands::Silences {
            path,
            noise_db,
            min_dur,
        } => {
            let silences = media.detect_silences(&path, noise_db, min_dur).await?;
            let speech = speech_segments(&silences);
            println!(
                "{}",
                json!({"status": "ok", "silences": silences, "speech": speech})
            );
        }
        Commands::Thumbnails { path, count, out } => {
            let thumbs = media.extract_thumbnails(&path, count, &out).await?;
            println!("{}", json!({"status": "ok", "thumbs": thumbs}));
        }
        Commands::Ask {
            prompt,
            temperature,
            json_mode,
        } => {
            let bridge = llm::LlmBridge::new();
            let resp = bridge.ask(&prompt, temperature, json_mode).await?;
            println!(
                "{}",
                json!({"status": "ok", "text": resp.text, "provider": resp.provider, "latency_ms": resp.latency_ms})
            );
        }
        Commands::Status => {
            let bridge = llm::LlmBridge::new();
            let providers = bridge.status().await;
            println!("{}", json!({"status": "ok", "providers": providers}));
        }
        Commands::Render {
            video,
            output,
            clips,
        } => {
            let clip_specs: Vec<types::ClipSpec> = serde_json::from_str(&clips)?;
            let req = types::RenderRequest {
                video_path: video,
                output_dir: output,
                clips: clip_specs,
                width: 1080,
                height: 1920,
                fps: 30,
            };
            let pipeline = render::RenderPipeline::new();
            let rendered = pipeline.render(&req).await?;
            let compiled_path = format!("{}/compiled_final.mp4", req.output_dir);
            let compiled = pipeline.compile(&rendered, &compiled_path).await;
            println!(
                "{}",
                json!({
                    "status": "ok",
                    "clips": rendered,
                    "compiled": compiled.ok(),
                })
            );
        }
        Commands::Transcribe { path } => {
            let t = transcribe::Transcriber::new();
            if !t.is_available() {
                println!(
                    "{}",
                    json!({"status": "unavailable", "reason": "whisper-cli or model not found"})
                );
                return Ok(());
            }
            let segments = t.transcribe(&path).await?;
            println!("{}", json!({"status": "ok", "segments": segments}));
        }
        Commands::Serve { port } => {
            // Initialize the global sqlite db (auth/sessions storage).
            let _ = db::global_db();

            // Full API router mounted under /api (auth, auto-edit, settings, ...).
            let api_routes = api::api_router();

            let app = axum::Router::new()
                .nest("/api", api_routes)
                // ملفات الموبايل: مخرجات الجلسات + المرفوعات (للتحميل/المشاركة).
                .nest_service(
                    "/api/files/output",
                    tower_http::services::ServeDir::new("output"),
                )
                .nest_service(
                    "/api/files/uploads",
                    tower_http::services::ServeDir::new("uploads"),
                )
                // حد axum الافتراضي (2MB) كان يقطع اتصال الرفع بلا رد —
                // السقف الحقيقي (2GB) يُفرض أثناء التدفق في files.rs.
                .layer(axum::extract::DefaultBodyLimit::disable())
                .layer(tower_http::cors::CorsLayer::permissive());

            let addr = format!("0.0.0.0:{port}");
            let listener = tokio::net::TcpListener::bind(&addr).await?;
            println!(
                "{}",
                json!({
                    "status": "ok",
                    "listening": addr,
                    "routes": "/api/auth/* /api/auto-edit /api/settings /api/status /api/tier /api/ffmpeg"
                })
            );
            axum::serve(listener, app).await?;
        }
    }
    Ok(())
}

fn speech_segments(silences: &[types::Silence]) -> Vec<serde_json::Value> {
    let mut segs = Vec::new();
    let mut cursor = 0.0f64;
    for s in silences {
        if s.start > cursor + 0.15 {
            segs.push(json!({"start": cursor, "end": s.start}));
        }
        cursor = cursor.max(s.end);
    }
    // tail
    if cursor > 0.0 {
        segs.push(json!({"start": cursor, "end": cursor + 1.0}));
    }
    segs
}
