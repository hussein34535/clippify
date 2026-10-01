/// رفع ملفات من العملاء (موبايل) + تقديم المخرجات عبر HTTP.
///
/// لماذا: الـ auto-edit يستقبل `video_path` محليًا على السيرفر — هاتف لا
/// يستطيع إعطاء مسار يقرأه السيرفر. التدفق: POST /api/upload (multipart)
/// → `{path}` نسبي → يُمرَّر لـ /api/auto-edit → النواتج تُجلب من
/// /api/files/output/* (تُركَّب في main.rs عبر ServeDir).
use axum::{
    extract::Multipart,
    response::Json,
    routing::post,
};
use serde_json::{json, Value};
use tokio::io::AsyncWriteExt;

const MAX_UPLOAD_BYTES: u64 = 2 * 1024 * 1024 * 1024;

const ALLOWED_EXT: &[&str] = &[
    "mp4", "mov", "mkv", "webm", "m4a", "mp3", "wav", "aac", "ogg", "flac",
];

pub fn router() -> axum::Router {
    axum::Router::new().route("/upload", post(upload))
}

fn safe_ext(name: &str) -> Option<String> {
    let ext = name.rsplit('.').next()?.to_lowercase();
    if ext == name.to_lowercase() {
        return None;
    }
    if ALLOWED_EXT.contains(&ext.as_str()) {
        Some(ext)
    } else {
        None
    }
}

async fn upload(mut multipart: Multipart) -> Json<Value> {
    let save = async {
        tokio::fs::create_dir_all("uploads").await.ok()?;
        while let Ok(Some(mut field)) = multipart.next_field().await {
            let fname = field.file_name().unwrap_or("video.mp4").to_string();
            let ext = safe_ext(&fname)?;
            let id = uuid::Uuid::new_v4().to_string();
            let rel = format!("uploads/{id}.{ext}");
            let mut out = tokio::fs::File::create(&rel).await.ok()?;
            let mut written: u64 = 0;
            let mut stream_ok = true;
            while let Ok(Some(chunk)) = field.chunk().await {
                written += chunk.len() as u64;
                if written > MAX_UPLOAD_BYTES {
                    stream_ok = false;
                    break;
                }
                if out.write_all(&chunk).await.is_err() {
                    stream_ok = false;
                    break;
                }
            }
            if !stream_ok {
                let _ = tokio::fs::remove_file(&rel).await;
                return None;
            }
            return Some(rel);
        }
        None
    };
    match save.await {
        Some(path) => Json(json!({"status": "ok", "path": path})),
        None => Json(json!({"status": "error", "error": "upload failed: need a media file field"})),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allows_media_extensions_only() {
        assert_eq!(safe_ext("clip.mp4"), Some("mp4".to_string()));
        assert_eq!(safe_ext("A.MOV"), Some("mov".to_string()));
        assert_eq!(safe_ext("song.flac"), Some("flac".to_string()));
        assert_eq!(safe_ext("evil.exe"), None);
        assert_eq!(safe_ext("noext"), None);
        assert_eq!(safe_ext("x.mp4.exe"), None);
        // traversal stays inside uploads/: only the extension is reused,
        // the stored name is always a fresh uuid.
        assert_eq!(safe_ext("../../etc/passwd.mp4"), Some("mp4".to_string()));
    }
}
