use std::process::{Command, Child, Stdio};
use std::sync::Mutex;
use tauri::Manager;

struct BackendProcess(Mutex<Option<Child>>);

fn find_api_path() -> Option<std::path::PathBuf> {
    let cargo_dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let dev_path = cargo_dir.join("../../api.py");
    if dev_path.exists() {
        return Some(dev_path.canonicalize().unwrap_or(dev_path));
    }
    if let Ok(exe) = std::env::current_exe() {
        let prod_path = exe.parent()?.join("api.py");
        if prod_path.exists() {
            return Some(prod_path);
        }
    }
    None
}

// Returns true if port is FREE (nobody listening on it)
fn is_port_free(port: u16) -> bool {
    std::net::TcpStream::connect(format!("127.0.0.1:{}", port)).is_err()
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
                if let Some(api_path) = find_api_path() {
                    let child = Command::new("python")
                        .arg(&api_path)
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .spawn()
                        .expect("Failed to start Python backend");
                    let state = app.state::<BackendProcess>();
                    *state.0.lock().unwrap() = Some(child);
                    log::info!("Python backend started from: {:?}", api_path);
                    // Give the backend a moment to initialize before the UI loads
                    std::thread::sleep(std::time::Duration::from_secs(2));
                } else {
                    log::warn!("api.py not found! Backend will not start.");
                }
            } else {
                log::info!("Port 8000 already in use — skipping backend launch");
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
