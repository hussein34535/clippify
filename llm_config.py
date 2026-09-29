"""Unified LLM configuration — single source of truth for model names."""
import os

# P0 fix: keep the chain pointing at LIVE models only. Verified against the
# API on 2026-08-30: gemini-1.5-* and gemini-2.0-flash are retired (404
# "no longer available"), gemini-2.5-flash is live but free-tier quota is
# bursty (429), and the API itself recommends gemini-3.6-flash /
# gemini-3.5-flash-lite. Order = newest recommended, then proven fallback.
MODEL_CHAIN = ["gemini-3.6-flash", "gemini-3.5-flash-lite", "gemini-2.5-flash"]

GEMMA_API_KEY = os.getenv("GEMMA_API_KEY", "")

_LLM_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"


def llm_url(model: str) -> str:
    return _LLM_URL.format(model=model, key=GEMMA_API_KEY)


def ask_llm(prompt: str, temperature: float = 0.5, json_mode: bool = False, max_retries: int = 2) -> str:
    """Ask the first working model in MODEL_CHAIN via REST. Raises on total failure."""
    import requests
    import time
    api_key = GEMMA_API_KEY
    if not api_key:
        raise RuntimeError("GEMMA_API_KEY is not set")
    headers = {"Content-Type": "application/json"}
    last_err = None
    for model in MODEL_CHAIN:
        # P0: gemini-2.5.* think by default and can burn the output budget —
        # disable thinking so structured answers always complete.
        gen_cfg = {"temperature": temperature}
        if model.startswith("gemini-2.5"):
            gen_cfg["thinkingConfig"] = {"thinkingBudget": 0}
        generation = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": gen_cfg,
        }
        if json_mode:
            generation["generationConfig"]["responseMimeType"] = "application/json"

        for attempt in range(max_retries):
            try:
                resp = requests.post(
                    llm_url(model), headers=headers, json=generation, timeout=60
                )
                if resp.status_code == 200:
                    data = resp.json()
                    return data["candidates"][0]["content"]["parts"][0]["text"]
                last_err = f"{model}: HTTP {resp.status_code}: {resp.text[:200]}"
            except Exception as e:
                last_err = f"{model}: {e}"
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"All LLM models failed. Last error: {last_err}")


def extract_json(text: str):
    """Parse JSON from an LLM response, tolerating markdown fences."""
    import json
    t = text.strip()
    if t.startswith("```"):
        t = t.split("```")[1]
        if t.startswith("json"):
            t = t[4:]
    start = min([i for i in (t.find("{"), t.find("[")) if i != -1], default=-1)
    if start == -1:
        raise ValueError("No JSON found in LLM response")
    end = max(t.rfind("}"), t.rfind("]"))
    return json.loads(t[start:end + 1])
