/// LLM cascade — Gemini free → Groq free → Ollama local. Zero-bill brain.
use anyhow::{Context, Result};
use serde_json::json;

use crate::types::LlmResponse;

pub struct LlmBridge {
    pub http: reqwest::Client,
    pub gemini_key: String,
    pub groq_key: String,
    pub ollama_url: String,
    pub gemini_daily_used: std::sync::atomic::AtomicUsize,
    pub gemini_daily_cap: usize,
}

impl LlmBridge {
    pub fn new() -> Self {
        // بناء العميل قد يفشل نظريًا (تهيئة TLS) — السقوط هنا كان يوقّع
        // السيرفر كله عند الإقلاع (يُستدعى في main). تراجع متدرج بدل panic.
        let http = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(60))
            .build()
            .unwrap_or_else(|e| {
                eprintln!("[llm] http client build failed ({e}); using defaults");
                reqwest::Client::new()
            });
        LlmBridge {
            http,
            gemini_key: std::env::var("GEMMA_API_KEY").unwrap_or_default(),
            groq_key: std::env::var("GROQ_API_KEY").unwrap_or_default(),
            ollama_url: std::env::var("OLLAMA_URL")
                .unwrap_or_else(|_| "http://localhost:11434".to_string()),
            gemini_daily_used: std::sync::atomic::AtomicUsize::new(0),
            gemini_daily_cap: std::env::var("GEMINI_CAP")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(1500),
        }
    }

    pub async fn ask(
        &self,
        prompt: &str,
        temperature: f64,
        json_mode: bool,
    ) -> Result<LlmResponse> {
        let start = std::time::Instant::now();

        // 1) Ollama (local, zero cost)
        if let Ok(resp) = self.try_ollama(prompt, temperature).await {
            return Ok(LlmResponse {
                text: resp,
                provider: "ollama".into(),
                latency_ms: start.elapsed().as_millis(),
            });
        }

        // 2) Gemini free tier
        if !self.gemini_key.is_empty() {
            let used = self
                .gemini_daily_used
                .load(std::sync::atomic::Ordering::Relaxed);
            if used < self.gemini_daily_cap {
                if let Ok(resp) = self.try_gemini(prompt, temperature, json_mode).await {
                    self.gemini_daily_used
                        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    return Ok(LlmResponse {
                        text: resp,
                        provider: "gemini".into(),
                        latency_ms: start.elapsed().as_millis(),
                    });
                }
            }
        }

        // 3) Groq free tier
        if !self.groq_key.is_empty() {
            if let Ok(resp) = self.try_groq(prompt, temperature, json_mode).await {
                return Ok(LlmResponse {
                    text: resp,
                    provider: "groq".into(),
                    latency_ms: start.elapsed().as_millis(),
                });
            }
        }

        Err(anyhow::anyhow!("all LLM providers exhausted"))
    }

    async fn try_ollama(&self, prompt: &str, temperature: f64) -> Result<String> {
        let body = json!({
            "model": "qwen3:4b",
            "messages": [{"role": "user", "content": prompt}],
            "options": {"temperature": temperature},
            "stream": false
        });
        let resp = self
            .http
            .post(format!("{}/api/chat", self.ollama_url))
            .json(&body)
            .send()
            .await
            .context("ollama unreachable")?;
        let data: serde_json::Value = resp.json().await?;
        let text = data["message"]["content"]
            .as_str()
            .context("no content")?
            .to_string();
        Ok(text)
    }

    async fn try_gemini(&self, prompt: &str, temperature: f64, json_mode: bool) -> Result<String> {
        let model = "gemini-2.0-flash";
        let mut body = json!({
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"temperature": temperature}
        });
        if json_mode {
            body["generationConfig"]["responseMimeType"] = json!("application/json");
        }
        let url = format!(
            "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent?key={}",
            model, self.gemini_key
        );
        let resp = self.http.post(&url).json(&body).send().await?;
        let data: serde_json::Value = resp.json().await?;
        let text = data["candidates"][0]["content"]["parts"][0]["text"]
            .as_str()
            .context("no gemini text")?
            .to_string();
        Ok(text)
    }

    async fn try_groq(&self, prompt: &str, temperature: f64, json_mode: bool) -> Result<String> {
        let mut body = json!({
            "model": "llama-3.3-70b-versatile",
            "messages": [{"role": "user", "content": prompt}],
            "temperature": temperature,
        });
        if json_mode {
            body["response_format"] = json!({"type": "json_object"});
        }
        let resp = self
            .http
            .post("https://api.groq.com/openai/v1/chat/completions")
            .header("Authorization", format!("Bearer {}", self.groq_key))
            .json(&body)
            .send()
            .await?;
        let data: serde_json::Value = resp.json().await?;
        let text = data["choices"][0]["message"]["content"]
            .as_str()
            .context("no groq text")?
            .to_string();
        Ok(text)
    }

    pub async fn status(&self) -> Vec<serde_json::Value> {
        let ollama_ok = self
            .http
            .get(format!("{}/api/tags", self.ollama_url))
            .timeout(std::time::Duration::from_secs(1))
            .send()
            .await
            .is_ok();
        vec![
            json!({"provider": "ollama", "mode": if ollama_ok {"free"} else {"off"}}),
            json!({"provider": "gemini", "mode": if self.gemini_key.is_empty() {"off"} else {"free"},
                   "used": self.gemini_daily_used.load(std::sync::atomic::Ordering::Relaxed),
                   "cap": self.gemini_daily_cap}),
            json!({"provider": "groq", "mode": if self.groq_key.is_empty() {"off"} else {"free"}}),
        ]
    }
}
