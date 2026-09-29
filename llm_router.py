"""
Zero-bill LLM brain — BYOK-first cascade over free providers.

    from llm_router import ask, ask_json, RouterExhausted
    r = ask("summarize: ...")            # → {text, provider, latency_ms}
    data = ask_json("return {..} json")  # parsed dict/list

Cascade (dedup per provider per request):
    prefer="auto" : BYOK keys first → ollama → gemini → groq
    prefer="local": ollama first    → BYOK keys  → gemini → groq

Each hop skips providers that are cooling down or out of daily budget
(providers.ledger). HTTP 429 / quota errors set a cooldown until UTC
midnight and fall through to the next hop; success counts one usage.
All hops fail → RouterExhausted(reasons=[{provider, reason}, ...]).

requests-only (no SDK), 60s timeouts, single retry on 5xx.
`_transport` is injectable for offline tests.
"""

import base64
import json
import os
import time
from datetime import datetime, timedelta, timezone

from providers import ledger, store

TIMEOUT = 60
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434")
# Gemini models come from llm_config.MODEL_CHAIN (single source of truth,
# docs/CONTRACTS.md); groq has no entry there yet so it lives here only.
try:
    from llm_config import MODEL_CHAIN as _GEMINI_CHAIN
except ImportError:  # pragma: no cover - llm_config is in-repo, guarded anyway
    _GEMINI_CHAIN = ["gemini-2.0-flash"]

GEMINI_MODELS = list(_GEMINI_CHAIN)
GROQ_MODEL = "llama-3.3-70b-versatile"
# Preferred LOCAL models (researched picks — see docs/HF_MODELS.md).
# Vision: Qwen3-VL 4B ≈5GB VRAM beats GPT-4o-mini; SmolVLM2-500M runs video on CPU.
# Text:   tiny instructables fine for JSON planning when cloud is capped.
OLLAMA_VISION_PREFS = ("qwen3-vl:4b", "qwen3-vl:2b", "qwen3-vl", "smolvlm2", "qwen2.5vl")
OLLAMA_TEXT_PREFS = ("qwen3:4b", "qwen3:2b", "llama3.2:3b", "llama3.2", "gemma3:4b", "qwen2.5")


def _pick_preferring(models, prefs):
    for pref in prefs:
        for m in models:
            if m.startswith(pref):
                return m
    return None


class RouterExhausted(Exception):
    """Every provider hop failed or was skipped."""

    def __init__(self, reasons):
        self.reasons = reasons
        super().__init__("all providers exhausted: " + "; ".join(r["reason"] for r in reasons))


class _Skip(Exception):
    """Hop-level failure carrying a reason string."""


def _default_transport(method, url, *, headers=None, json_body=None, timeout=TIMEOUT):
    import requests

    resp = requests.request(method, url, headers=headers, json=json_body, timeout=timeout)
    return resp.status_code, resp.text


# Injectable seam — tests monkeypatch this.
_transport = _default_transport


def _call_with_retry(provider, method, url, **kw):
    """One retry on 5xx; classifies failures into quota vs transport errors."""
    last = ""
    for attempt in range(2):
        try:
            status, text = _transport(method, url, headers=kw.get("headers"),
                                      json_body=kw.get("json_body"), timeout=kw.get("timeout", TIMEOUT))
        except Exception as exc:
            last = f"{type(exc).__name__}: {exc}"
            status, text = 0, ""
        if 200 <= status < 300:
            return text
        low = text.lower()
        if status == 429 or "quota" in low or "resource_exhausted" in low:
            raise _Skip(f"quota_exhausted (HTTP {status})")
        if status >= 500 and attempt == 0:
            time.sleep(0.25)
            continue
        last = f"HTTP {status}: {text[:200]}" if status else last or "unreachable"
        break
    raise _Skip(last)


def _utc_midnight_iso() -> str:
    now = datetime.now(timezone.utc)
    return (now + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0).isoformat()


def _ollama_models():
    """Model names from GET /api/tags (1s timeout) or [] when unreachable."""
    try:
        text = _call_with_retry("ollama", "GET", f"{OLLAMA_URL}/api/tags", timeout=1)
    except _Skip:
        return []
    try:
        return [m.get("name", "") for m in json.loads(text).get("models", [])]
    except ValueError:
        return []


def _key_for(provider: str):
    key = store.get_key(provider)
    if key:
        return key
    env = {"gemini": "GEMMA_API_KEY", "groq": "GROQ_API_KEY"}.get(provider, "")
    return os.getenv(env, "") or None


def _hop_ollama(prompt, temperature, json_mode, vision_frames, models):
    if not models:
        raise _Skip("ollama unreachable")
    model = _pick_preferring(models, OLLAMA_VISION_PREFS)
    if vision_frames:
        # Vision needs a VL model (Qwen3-VL / SmolVLM2 / Qwen2.5-VL).
        if model is None:
            raise _Skip("no vision model (qwen*-vl/smolvlm*) on ollama")
    else:
        if model is None:
            model = _pick_preferring(models, OLLAMA_TEXT_PREFS) or (
                models[0] if models else None
            )
        if not model:
            raise _Skip("ollama has no models")
    message = {"role": "user", "content": prompt}
    if vision_frames:
        message["images"] = list(vision_frames)
    body = {
        "model": model,
        "messages": [message],
        "stream": False,
        "options": {"temperature": temperature},
    }
    text = _call_with_retry("ollama", "POST", f"{OLLAMA_URL}/api/chat",
                            json_body=body)
    content = json.loads(text).get("message", {}).get("content", "")
    if not content:
        raise _Skip("empty ollama response")
    return content


def _hop_gemini(key, model, prompt, temperature, json_mode, vision_frames):
    parts = [{"text": prompt}]
    for frame in vision_frames or []:
        parts.append({"inline_data": {"mime_type": "image/jpeg", "data": frame}})
    generation = {
        "contents": [{"parts": parts}],
        "generationConfig": {"temperature": temperature},
    }
    if json_mode:
        generation["generationConfig"]["responseMimeType"] = "application/json"
    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model}:generateContent?key={key}"
    )
    text = _call_with_retry("gemini", "POST", url,
                            headers={"Content-Type": "application/json"},
                            json_body=generation)
    data = json.loads(text)
    cands = data.get("candidates") or []
    content = "".join(
        p.get("text", "") for p in (cands[0].get("content", {}).get("parts") or [])
    )
    if not content:
        raise _Skip(f"empty gemini response ({model})")
    return content


def _hop_groq(key, prompt, temperature, json_mode, vision_frames):
    if vision_frames:
        raise _Skip("groq does not support vision")
    body = {
        "model": GROQ_MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": temperature,
    }
    if json_mode:
        body["response_format"] = {"type": "json_object"}
    text = _call_with_retry(
        "groq", "POST", "https://api.groq.com/openai/v1/chat/completions",
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        json_body=body,
    )
    content = (json.loads(text).get("choices") or [{}])[0].get("message", {}).get("content", "")
    if not content:
        raise _Skip("empty groq response")
    return content


def ask(prompt: str, *, temperature: float = 0.5, json_mode: bool = False,
        vision_frames=None, prefer: str = "auto") -> dict:
    """
    Run the cascade and return {text, provider, latency_ms}.
    Raises RouterExhausted (with .reasons) when nothing works.
    """
    byok = [p for p in store.list() if p != "ollama"]
    if prefer == "local":
        order = ["ollama"] + byok + ["gemini", "groq"]
    else:
        order = byok + ["ollama", "gemini", "groq"]
    # One attempt per provider per request (BYOK and shared share cooldown/budget).
    seen, plan = set(), []
    for p in order:
        if p not in seen:
            seen.add(p)
            plan.append(p)

    ollama_models = _ollama_models() if "ollama" in plan else []
    reasons = []
    for provider in plan:
        until = ledger.cooldown_until(provider)
        if until:
            reasons.append({"provider": provider, "reason": f"cooldown_until:{until}"})
            continue
        if ledger.available(provider) <= 0:
            reasons.append({"provider": provider, "reason": "daily_cap_reached"})
            continue
        started = time.perf_counter()
        try:
            if provider == "ollama":
                text = _hop_ollama(prompt, temperature, json_mode, vision_frames, ollama_models)
            else:
                key = _key_for(provider)
                if not key:
                    raise _Skip("no_api_key")
                if provider == "gemini":
                    text = None
                    last = None
                    for model in GEMINI_MODELS:
                        try:
                            text = _hop_gemini(key, model, prompt, temperature, json_mode, vision_frames)
                            break
                        except _Skip as skip:
                            last = skip
                    if text is None:
                        raise last or _Skip("gemini chain empty")
                elif provider == "groq":
                    text = _hop_groq(key, prompt, temperature, json_mode, vision_frames)
                else:
                    raise _Skip("unknown_provider")
        except _Skip as skip:
            reason = str(skip)
            if "quota" in reason:
                ledger.set_cooldown(provider, _utc_midnight_iso())
            reasons.append({"provider": provider, "reason": reason})
            continue
        ledger.add_used(provider)
        return {
            "text": text,
            "provider": provider,
            "latency_ms": int((time.perf_counter() - started) * 1000),
        }
    raise RouterExhausted(reasons)


def ask_json(prompt: str, **kwargs):
    """ask() + tolerant JSON extraction (llm_config.extract_json, local fallback)."""
    result = ask(prompt, **kwargs)
    try:
        from llm_config import extract_json
    except ImportError:
        def extract_json(text):
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
    return extract_json(result["text"])
