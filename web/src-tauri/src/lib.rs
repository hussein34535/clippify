use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use tauri::Manager;

struct BackendProcess(Mutex<Option<Child>>);

/// Find the sidecar executable. Tauri copies it next to the main exe in production.
fn find_sidecar_path() -> Option<std::path::PathBuf> {
    // 1. Production: sidecar is next to the main exe (Tauri convention)
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            let sidecar = dir.join("clipai-backend-x86_64-pc-windows-msvc.exe");
            if sidecar.exists() {
                return Some(sidecar);
            }
        }
    }
    // 2. Dev: sidecar is in ../dist/
    let dev_path = std::path::PathBuf::from("../dist/clipai-backend.exe");
    if dev_path.exists() {
        return Some(dev_path.canonicalize().unwrap_or(dev_path));
    }
    // 3. Dev: relative to CARGO_MANIFEST_DIR
    if let Ok(manifest) = std::env::var("CARGO_MANIFEST_DIR") {
        let p = std::path::PathBuf::from(manifest).join("../../dist/clipai-backend.exe");
        if p.exists() {
            return p.canonicalize().ok().or(Some(p));
        }
    }
    None
}

/// Returns true if port 8000 is FREE (nobody listening on it)
fn is_port_free(port: u16) -> bool {
    std::net::TcpStream::connect(format!("127.0.0.1:{}", port)).is_err()
}

/// Walk up from the current working directory to find a directory containing api.py
fn find_api_py_dir() -> Option<std::path::PathBuf> {
    let cwd = std::env::current_dir().ok()?;
    let candidates = [
        cwd.clone(),
        cwd.join(".."),
        cwd.join("../.."),
        cwd.join("../../.."),
    ];
    for candidate in &candidates {
        if candidate.join("api.py").exists() {
            return Some(candidate.clone());
        }
    }
    None
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(BackendProcess(Mutex::new(None)))
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }

            // Only launch backend if port 8000 is free (not already running)
            if is_port_free(8000) {
                // Try sidecar first, fall back to system Python in dev
                let (program, args): (String, Vec<String>) = if let Some(sidecar) = find_sidecar_path() {
                    log::info!("Using bundled sidecar: {:?}", sidecar);
                    (sidecar.to_string_lossy().to_string(), vec![])
                } else if cfg!(debug_assertions) {
                    log::warn!("Sidecar not found, falling back to system Python (dev only)");
                    ("python".to_string(), vec!["api.py".to_string()])
                } else {
                    log::error!("Sidecar not found in production! Backend will not start.");
                    return Ok(());
                };

                let mut cmd = Command::new(&program);
                cmd.args(&args)
                    .stdout(Stdio::null())
                    .stderr(Stdio::null());

                // In dev, set cwd to project root so api.py finds its data files
                if cfg!(debug_assertions) {
                    if let Some(cwd) = find_api_py_dir() {
                        log::info!("Backend cwd: {:?}", cwd);
                        cmd.current_dir(&cwd);
                    }
                }

                match cmd.spawn() {
                    Ok(child) => {
                        let state = app.state::<BackendProcess>();
                        *state.0.lock().unwrap() = Some(child);
                        log::info!("Backend started successfully");
                        // Give the backend a moment to initialize before the UI loads
                        std::thread::sleep(std::time::Duration::from_secs(2));
                    }
                    Err(e) => {
                        log::error!("Failed to start backend: {}", e);
                    }
                }
            } else {
                log::info!("Port 8000 already in use - skipping backend launch");
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { .. } = event {
                if let Some(state) = window.try_state::<BackendProcess>() {
                    if let Ok(mut guard) = state.0.lock() {
                        if let Some(ref mut child) = *guard {
                            let _ = child.kill();
                            let _ = child.wait();
                        }
                    }
                }
                std::process::exit(0);
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
