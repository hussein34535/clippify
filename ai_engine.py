import os
import multiprocessing
import subprocess
import json
import tempfile
import uuid
import hashlib

# ── CUDA DLL paths (from nvidia pip packages) ──
import site
import shutil

# ── Whisper Cache ───────────────────────────────────────────────────────────
_CACHE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cache", "whisper")

def _whisper_cache_path(audio_path: str) -> str:
    """Return a cache file path based on file path + size + mtime."""
    try:
        stat = os.stat(audio_path)
        raw = f"{os.path.abspath(audio_path)}|{stat.st_size}|{int(stat.st_mtime)}"
    except OSError:
        raw = os.path.abspath(audio_path)
    h = hashlib.sha256(raw.encode()).hexdigest()[:16]
    os.makedirs(_CACHE_DIR, exist_ok=True)
    return os.path.join(_CACHE_DIR, f"{h}.json")

def _load_whisper_cache(audio_path: str) -> list | None:
    """Load cached transcription if it exists, else None."""
    cp = _whisper_cache_path(audio_path)
    if os.path.isfile(cp):
        try:
            with open(cp, "r", encoding="utf-8") as f:
                data = json.load(f)
            print(f"  [CACHE] Loaded transcription from cache ({len(data)} words)")
            return data
        except Exception as e:
            print(f"  [CACHE] Failed to load cache ({e}), re-transcribing...")
    return None

def _save_whisper_cache(audio_path: str, words: list):
    """Save transcription to cache."""
    try:
        cp = _whisper_cache_path(audio_path)
        with open(cp, "w", encoding="utf-8") as f:
            json.dump(words, f, ensure_ascii=False)
        print(f"  [CACHE] Saved transcription to cache ({len(words)} words)")
    except Exception as e:
        print(f"  [CACHE] Failed to save cache ({e})")

_sp = site.getsitepackages()[0]
_ct2_dir = os.path.join(_sp, "ctranslate2")

# Copy CUDA DLLs next to ctranslate2's .pyd (fix for LoadLibrary)
_cuda_dlls = [
    ("cublas", "cublas64_12.dll"),
    ("cublas", "cublasLt64_12.dll"),
    ("cuda_runtime", "cudart64_12.dll"),
    ("cudnn", "cudnn64_9.dll"),
]
for _pkg, _dll in _cuda_dlls:
    _src = os.path.join(_sp, "nvidia", _pkg, "bin", _dll)
    _dst = os.path.join(_ct2_dir, _dll)
    if os.path.isfile(_src) and not os.path.isfile(_dst):
        try:
            shutil.copy2(_src, _dst)
        except Exception:
            pass

from faster_whisper import WhisperModel
from pydub import AudioSegment

_MODEL = None
_LOADED_MODEL_SIZE = None
_CPU_COUNT = max(1, os.cpu_count() or 4)
_THREADS = _CPU_COUNT
_CHUNK_SEC = 60  # seconds per chunk for parallel transcription

# Resolve ffmpeg/ffprobe path for audio duration
_FFPROBE = "ffprobe"
try:
    import imageio_ffmpeg
    _ff = imageio_ffmpeg.get_ffmpeg_exe()
    _dir = os.path.dirname(_ff)
    _name = os.path.basename(_ff).replace("ffmpeg", "ffprobe")
    _FFPROBE = os.path.join(_dir, _name)
    if not os.path.isfile(_FFPROBE):
        _FFPROBE = "ffprobe"
except Exception:
    pass

EMOJI_DICT = {
    "money": "💰", "cash": "💰", "dollar": "💵", "rich": "🤑", "wealth": "💸",
    "secret": "🤫", "mystery": "🕵️", "hidden": "🔒",
    "fast": "🚀", "speed": "⚡", "quick": "🏃",
    "fire": "🔥", "hot": "🔥", "burn": "🔥",
    "shock": "😱", "crazy": "🤪", "insane": "🤯", "mindblown": "🤯",
    "warning": "⚠️", "danger": "🚨", "alert": "🚨",
    "love": "❤️", "heart": "💖", "happy": "😊",
    "dead": "💀", "skull": "💀", "end": "🛑",
    "success": "🏆", "win": "👑", "champion": "🥇",
    "ai": "🤖", "robot": "🤖", "tech": "💻", "computer": "🖥️",
    "time": "⏰", "clock": "⏳", "future": "🔮",
    "فلوس": "💰", "مال": "💰", "دولار": "💵", "غني": "🤑", "ثروة": "💸",
    "سر": "🤫", "أسرار": "🤫", "خفي": "🔒", "مخفي": "🔒",
    "سريع": "🚀", "سرعة": "⚡", "صاروخ": "🚀",
    "نار": "🔥", "حماس": "🔥", "حار": "🔥",
    "صدمة": "😱", "مصدوم": "😱", "مجنون": "🤪", "رهيب": "🤯", "خرافي": "🤯",
    "تحذير": "⚠️", "خطر": "🚨", "تنبيه": "🚨",
    "حب": "❤️", "قلب": "💖", "سعيد": "😊", "فرح": "😊",
    "موت": "💀", "ميت": "💀", "نهاية": "🛑",
    "نجاح": "🏆", "فوز": "👑", "بطل": "🥇",
    "ذكاء": "🤖", "روبوت": "🤖", "تكنولوجيا": "💻", "كمبيوتر": "🖥️",
    "وقت": "⏰", "ساعة": "⏳", "مستقبل": "🔮"
}


def _transcribe_chunk(args):
    """Transcribe a single audio chunk (runs in its own process)."""
    chunk_path, start_offset = args
    model = WhisperModel("tiny", device="cpu", compute_type="int8",
                         cpu_threads=2, num_workers=1)
    segs, _ = model.transcribe(
        chunk_path, word_timestamps=True,
        beam_size=1, best_of=1, condition_on_previous_text=False,
        vad_filter=True,
        vad_parameters=dict(threshold=0.5, min_speech_duration_ms=250, min_silence_duration_ms=500),
    )
    words = []
    for s in segs:
        for w in s.words:
            words.append({
                "start": w.start + start_offset,
                "end": w.end + start_offset,
                "text": w.word.strip(),
            })
    # cleanup temp file
    try:
        os.remove(chunk_path)
    except OSError:
        pass
    return words


def _get_model(gpu_ok=True):
    global _MODEL, _LOADED_MODEL_SIZE
    try:
        from gui_state import load_ui_prefs
        prefs = load_ui_prefs()
        model_size = prefs.get("whisper_model", "tiny")
    except Exception:
        model_size = "tiny"

    if _MODEL is not None and _LOADED_MODEL_SIZE != model_size:
        print(f"Whisper model size changed from {_LOADED_MODEL_SIZE} to {model_size}. Re-loading...")
        _MODEL = None

    if _MODEL is None:
        _LOADED_MODEL_SIZE = model_size
        if gpu_ok:
            print(f"Loading AI Model ({model_size}, trying GPU)...")
            try:
                _MODEL = WhisperModel(model_size, device="auto", compute_type="default",
                                      cpu_threads=_THREADS, num_workers=_THREADS)
                print("✅ Loaded on GPU!")
            except Exception as e:
                print(f"GPU failed ({e}). Falling back to CPU ({_THREADS} threads)...")
                _MODEL = WhisperModel(model_size, device="cpu", compute_type="int8",
                                      cpu_threads=_THREADS, num_workers=_THREADS)
        else:
            print(f"Loading AI Model ({model_size} CPU, {_THREADS} threads)...")
            _MODEL = WhisperModel(model_size, device="cpu", compute_type="int8",
                                  cpu_threads=_THREADS, num_workers=_THREADS)
    return _MODEL


def _reset_model():
    """Force CPU-only model (used when GPU crashes during transcribe)."""
    global _MODEL
    _MODEL = None
    return _get_model(gpu_ok=False)


def generate_subtitles(audio_path: str, use_vad: bool = True):
    # ── Check cache first ──
    cached = _load_whisper_cache(audio_path)
    if cached is not None:
        return cached

    # Get total duration using ffprobe
    total_dur = 0
    try:
        probe = subprocess.run(
            [_FFPROBE, "-v", "quiet", "-print_format", "json", "-show_format", audio_path],
            capture_output=True, text=True, timeout=120,
        )
        info = json.loads(probe.stdout)
        total_dur = float(info.get("format", {}).get("duration", 0))
    except Exception as e:
        print(f"Could not get audio duration ({e}), using single-process transcription...")
        return _transcribe_single(audio_path, use_vad)
    
    # ── Blazing Fast GPU Check ──
    # If the model is loaded on GPU (CUDA), running it in a single pass on GPU is 10x faster than splitting on CPU!
    model = _get_model()
    is_gpu = False
    try:
        is_gpu = getattr(model, "device", "cpu") == "cuda" or (hasattr(model, "model") and getattr(model.model, "device", "cpu") == "cuda")
    except Exception:
        pass

    if is_gpu:
        print(f"🚀 Blazing Fast GPU (CUDA) detected! Running single-pass transcription on GPU for {total_dur:.0f}s audio...")
        return _transcribe_single(audio_path, use_vad)
    
    if total_dur <= 300 or _CPU_COUNT <= 2:
        # Short audio: single-process (no overhead)
        return _transcribe_single(audio_path, use_vad)

    # Long audio: split into chunks per core
    n_chunks = min(_CPU_COUNT, max(4, int(total_dur // _CHUNK_SEC) + 1))
    dur_per_chunk = total_dur / n_chunks
    print(f"Parallel transcribe: splitting {total_dur:.0f}s into {n_chunks} chunks ({dur_per_chunk:.0f}s each)...")

    audio = AudioSegment.from_file(audio_path)
    chunks = []
    tmpdir = tempfile.mkdtemp()
    for i in range(n_chunks):
        start_ms = int(i * dur_per_chunk * 1000)
        end_ms = int(min((i + 1) * dur_per_chunk, total_dur) * 1000)
        chunk = audio[start_ms:end_ms]
        chunk_path = os.path.join(tmpdir, f"chunk_{i}_{uuid.uuid4().hex[:8]}.wav")
        chunk.export(chunk_path, format="wav")
        chunks.append((chunk_path, i * dur_per_chunk))

    # Process in parallel
    total_words = []
    try:
        with multiprocessing.Pool(n_chunks) as pool:
            results = pool.map(_transcribe_chunk, chunks)
            for r in results:
                total_words.extend(r)
    except Exception as e:
        print(f"Parallel transcribe failed ({e}), falling back to single-process...")
        return _transcribe_single(audio_path, use_vad)

    # Sort by start time
    total_words.sort(key=lambda w: w["start"])
    print(f"Parallel transcribe done: {len(total_words)} words from {total_dur:.0f}s audio")
    _save_whisper_cache(audio_path, total_words)
    return total_words


def _transcribe_single(audio_path: str, use_vad: bool = True):
    """Single-process transcription (for short audio)."""
    model = _get_model()
    common = dict(
        word_timestamps=True,
        beam_size=1, best_of=1,
        condition_on_previous_text=False,
    )
    try:
        if use_vad:
            print("Transcribing audio (VAD + all CPU cores)...")
            segments, info = model.transcribe(
                audio_path, vad_filter=True,
                vad_parameters=dict(threshold=0.5, min_speech_duration_ms=250, min_silence_duration_ms=500),
                **common,
            )
        else:
            print("Transcribing audio (fast mode, no VAD)...")
            segments, info = model.transcribe(audio_path, **common)
    except Exception as e:
        if "cublas" in str(e).lower() or "cuda" in str(e).lower():
            print(f"GPU error during transcribe ({e}), switching to CPU...")
            model = _reset_model()
            return _transcribe_single(audio_path, use_vad)
        raise
    total_duration = info.duration if info else 1.0
    words = []
    for segment in segments:
        if info and total_duration > 0.0:
            seg_progress = min(1.0, segment.end / total_duration)
            pct = int(seg_progress * 100)
            print(f"[WHISPER PROGRESS] {pct}%", flush=True)
            
        for word in segment.words:
            words.append({"start": word.start, "end": word.end, "text": word.word.strip()})
    print(f"Transcribed {len(words)} words.")
    _save_whisper_cache(audio_path, words)
    return words


def _transcribe_full(audio_path: str) -> list:
    return generate_subtitles(audio_path, use_vad=False)


def get_words_in_range(words: list, start_sec: float, end_sec: float) -> list:
    return [w for w in words if w['end'] >= start_sec and w['start'] <= end_sec]


def translate_chunks_to_arabic(chunks_texts: list) -> list:
    """Translate a list of subtitle phrases to Arabic in small batches using deep-translator (completely free) with AI fallback if needed."""
    if not chunks_texts:
        return []

    # 1. Try deep-translator first (free, no API key required)
    try:
        from deep_translator import GoogleTranslator
        translator = GoogleTranslator(source='auto', target='ar')
        batch_size = 25
        translated_all = []
        
        for i in range(0, len(chunks_texts), batch_size):
            batch = chunks_texts[i:i + batch_size]
            print(f"  [TRANSLATION] Translating batch {i // batch_size + 1} ({len(batch)} phrases) using deep-translator (Free)...")
            translated = translator.translate_batch(batch)
            if isinstance(translated, list) and len(translated) == len(batch):
                translated_all.extend([str(item).strip() for item in translated])
            else:
                raise ValueError(f"Batch length mismatch: got {len(translated) if isinstance(translated, list) else 'non-list'}, expected {len(batch)}")
            
        print("  [TRANSLATION] Completed successfully using deep-translator (Free)!")
        return translated_all
        
    except Exception as e:
        print(f"  [TRANSLATION WARNING] deep-translator failed: {e}. Falling back to AI model...")

    # 2. AI Fallback (Gemma/Gemma API)
    import requests
    from campaign import GEMMA_API_KEY
    import json
    import time
        
    model = "gemma-4-31b-it"
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={GEMMA_API_KEY}"
    headers = {"Content-Type": "application/json"}
    
    # Split chunks into smaller batches to prevent LLM timeouts
    batch_size = 25
    translated_all = []
    
    for i in range(0, len(chunks_texts), batch_size):
        batch = chunks_texts[i:i + batch_size]
        print(f"  [TRANSLATION] Translating batch {i // batch_size + 1} ({len(batch)} phrases) using {model}...")
        
        prompt = f"""
You are an expert translator. Translate this JSON list of English subtitle phrases into a parallel list of natural, engaging, and accurate Arabic subtitle phrases.
Keep the exact same order and number of items (exactly {len(batch)} items).
Keep the translations short and punchy suitable for TikTok/Reels subtitles.

Input JSON list:
{json.dumps(batch, ensure_ascii=False)}

Output ONLY the raw JSON list of translated Arabic strings, with no markdown formatting, no code block backticks (like ```json), no thoughts, and no explanation.
Example output format:
[
  "العبارة الأولى",
  "العبارة الثانية"
]
"""
        payload = {
            "contents": [{
                "parts": [{"text": prompt}]
            }],
            "generationConfig": {
                "temperature": 0.3,
                "maxOutputTokens": 2000
            }
        }
        
        batch_translated = None
        # Try up to 3 times for this batch
        for attempt in range(1, 4):
            try:
                response = requests.post(url, json=payload, headers=headers, timeout=120)
                if response.status_code == 200:
                    data = response.json()
                    candidates = data.get("candidates", [])
                    if candidates:
                        parts = candidates[0].get("content", {}).get("parts", [])
                        text_parts = [p.get("text", "") for p in parts if not p.get("thought")]
                        resp_text = "".join(text_parts).strip()
                        
                        # Clean markdown if present
                        if resp_text.startswith("```"):
                            lines = resp_text.splitlines()
                            cleaned_lines = []
                            for line in lines:
                                if not line.strip().startswith("```"):
                                    cleaned_lines.append(line)
                            resp_text = "\n".join(cleaned_lines).strip()
                            
                        translated = json.loads(resp_text)
                        if isinstance(translated, list) and len(translated) == len(batch):
                            batch_translated = [str(item).strip() for item in translated]
                            print(f"  [TRANSLATION] Batch {i // batch_size + 1} translated successfully!")
                            break
                        else:
                            print(f"  [TRANSLATION] Batch {i // batch_size + 1} length mismatch: got {len(translated)}, expected {len(batch)}")
                else:
                    print(f"  [TRANSLATION] Model {model} returned status {response.status_code}: {response.text[:200]}")
            except Exception as e:
                print(f"  [TRANSLATION] Error during batch {i // batch_size + 1} (attempt {attempt}): {e}")
                
            time.sleep(2)
            
        if batch_translated is not None:
            translated_all.extend(batch_translated)
        else:
            print(f"  [TRANSLATION] Batch {i // batch_size + 1} failed after 3 attempts. Falling back to English for this batch.")
            translated_all.extend(batch) # Fallback for this batch specifically
            
    return translated_all


def generate_ass_for_clip(
    words: list,
    start_sec: float,
    end_sec: float,
    output_ass_path: str,
    theme: str = "TikTok",
    font_name: str = None,
    translate_to_arabic: bool = False,
    animation_mode: str = "auto",
    content_type: str = "podcast",
    emphasis_words: list = None,
    hook_start_sec: float = 0.0,
    hook_end_sec: float = 0.0,
    res_x: int = 1080,
    res_y: int = 1920,
    pacing_speed: float = 1.0,
    slow_motion_start: float = 0.0,
    slow_motion_end: float = 0.0,
    slow_motion_speed: float = 1.0,
    narrative_acts: list = None,
    emoji_map: dict = None,
):
    """Generate an ASS subtitle file for a clip.

    When animation_mode is 'classic', uses the original _build_ass_file logic.
    Otherwise uses caption_animator for advanced word animations.
    """
    normalized_words = []
    
    if narrative_acts:
        cum_duration = 0.0
        for act in narrative_acts:
            act_start = act["start_sec"]
            act_end = act["end_sec"]
            act_words = get_words_in_range(words, act_start, act_end)
            for w in act_words:
                nw = w.copy()
                t_start = max(0.0, w['start'] - act_start) + cum_duration
                t_end = max(0.0, w['end'] - act_start) + cum_duration

                # 1. Apply pacing speedup
                t_start = t_start / pacing_speed
                t_end = t_end / pacing_speed

                # 2. Apply slow motion
                if slow_motion_speed < 1.0 and slow_motion_end > slow_motion_start + 0.1:
                    # Scale start time
                    if t_start > slow_motion_start:
                        if t_start <= slow_motion_end:
                            t_start = slow_motion_start + (t_start - slow_motion_start) / slow_motion_speed
                        else:
                            t_start = slow_motion_start + (slow_motion_end - slow_motion_start) / slow_motion_speed + (t_start - slow_motion_end)
                    # Scale end time
                    if t_end > slow_motion_start:
                        if t_end <= slow_motion_end:
                            t_end = slow_motion_start + (t_end - slow_motion_start) / slow_motion_speed
                        else:
                            t_end = slow_motion_start + (slow_motion_end - slow_motion_start) / slow_motion_speed + (t_end - slow_motion_end)

                nw['start'] = t_start
                nw['end'] = t_end
                normalized_words.append(nw)
            cum_duration += (act_end - act_start)
    else:
        clip_words = get_words_in_range(words, start_sec, end_sec)
        for w in clip_words:
            nw = w.copy()
            t_start = max(0.0, w['start'] - start_sec)
            t_end = max(0.0, w['end'] - start_sec)

            # 1. Apply pacing speedup
            t_start = t_start / pacing_speed
            t_end = t_end / pacing_speed

            # 2. Apply slow motion
            if slow_motion_speed < 1.0 and slow_motion_end > slow_motion_start + 0.1:
                # Scale start time
                if t_start > slow_motion_start:
                    if t_start <= slow_motion_end:
                        t_start = slow_motion_start + (t_start - slow_motion_start) / slow_motion_speed
                    else:
                        t_start = slow_motion_start + (slow_motion_end - slow_motion_start) / slow_motion_speed + (t_start - slow_motion_end)
                # Scale end time
                if t_end > slow_motion_start:
                    if t_end <= slow_motion_end:
                        t_end = slow_motion_start + (t_end - slow_motion_start) / slow_motion_speed
                    else:
                        t_end = slow_motion_start + (slow_motion_end - slow_motion_start) / slow_motion_speed + (t_end - slow_motion_end)

            nw['start'] = t_start
            nw['end'] = t_end
            normalized_words.append(nw)

    # ── Use new caption_animator (all modes except 'classic') ──────────────
    if animation_mode != "classic":
        try:
            from caption_animator import generate_animated_ass
            generate_animated_ass(
                words=normalized_words,
                output_path=output_ass_path,
                mode=animation_mode,
                font_name=font_name or "Impact",
                content_type=content_type,
                emphasis_words=emphasis_words,
                translate_to_arabic=translate_to_arabic,
                hook_start_sec=hook_start_sec,
                hook_end_sec=hook_end_sec,
                res_x=res_x,
                res_y=res_y,
                emoji_map=emoji_map,
            )
            return
        except Exception as e:
            print(f"  [CaptionAnimator] fallback to classic: {e}")

    # ── Fallback: original classic ASS ────────────────────────────────────
    ass_content = _build_ass_file(
        normalized_words,
        theme=theme,
        font_name=font_name,
        translate_to_arabic=translate_to_arabic,
        hook_start_sec=hook_start_sec,
        hook_end_sec=hook_end_sec,
    )
    with open(output_ass_path, "w", encoding="utf-8") as f:
        f.write(ass_content)


def format_ass_time(seconds: float) -> str:
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    cs = int((seconds - int(seconds)) * 100)
    return f"{h}:{m:02d}:{s:02d}.{cs:02d}"


def _build_ass_file(words: list, theme: str = "TikTok", font_name: str = None,
                     translate_to_arabic: bool = False,
                     hook_start_sec: float = 0.0, hook_end_sec: float = 0.0) -> str:
    ass = []
    ass.append("[Script Info]")
    ass.append("ScriptType: v4.00+")
    ass.append("PlayResX: 1080")
    ass.append("PlayResY: 1920")
    ass.append("WrapStyle: 1")
    ass.append("")
    ass.append("[V4+ Styles]")
    ass.append("Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding")

    # Determine standard and fallback font names
    f_name = font_name if font_name else ("Arial" if theme in ["Cyberpunk", "Minimalist"] else "Impact")

    if theme == "Cyberpunk":
        ass.append(f"Style: TikTok,{f_name},95,&H00FFFFFF,&H00FF00FF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,6,3,2,10,10,300,1")
        ass.append(f"Style: Hook,{f_name},110,&H0000FFFF,&H00000000,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,8,4,2,10,10,300,1")
        highlight_color = "{\\c&HFF00FF&}"
        hook_color = "{\\c&H0000FF&}" # Red highlight for hook
    elif theme == "Minimalist":
        ass.append(f"Style: TikTok,{f_name},80,&H00FFFFFF,&H0000FF00,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,3,1,2,10,10,300,1")
        ass.append(f"Style: Hook,{f_name},95,&H0000FFFF,&H00000000,&H00000000,&H80000000,1,0,0,0,100,100,0,0,1,5,2,2,10,10,300,1")
        highlight_color = "{\\c&H00FF00&}"
        hook_color = "{\\c&H0000FF&}"
    else:
        ass.append(f"Style: TikTok,{f_name},95,&H00FFFFFF,&H0000FFFF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,6,3,2,10,10,300,1")
        ass.append(f"Style: Hook,{f_name},115,&H0000FFFF,&H00000000,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,8,4,2,10,10,300,1")
        highlight_color = "{\\c&H0000FFFF&}"
        hook_color = "{\\c&H0000FF&}"

    ass.append("")
    ass.append("[Events]")
    ass.append("Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text")

    chunks = []
    i = 0
    while i < len(words):
        chunk = [words[i]]
        if i + 1 < len(words) and words[i+1]['start'] - words[i]['end'] < 0.5:
            chunk.append(words[i+1])
            i += 1
        chunks.append(chunk)
        i += 1

    translated_texts = []
    if translate_to_arabic:
        chunks_texts = []
        for chunk in chunks:
            chunk_text = " ".join(w['text'] for w in chunk)
            chunks_texts.append(chunk_text)
        translated_texts = translate_chunks_to_arabic(chunks_texts)

    for chunk_idx, chunk in enumerate(chunks):
        display_words = []
        
        # If translation to Arabic is enabled, we use the translated phrase instead
        if translate_to_arabic and chunk_idx < len(translated_texts):
            arabic_phrase = translated_texts[chunk_idx]
            
            # Find emoji for any word in the chunk
            emoji = ""
            for w in chunk:
                clean = w['text'].strip(".,!?;:()\"'").lower()
                if clean in EMOJI_DICT:
                    emoji = EMOJI_DICT[clean]
                    break
            
            display_text = f"{arabic_phrase} {emoji}".strip() if emoji else arabic_phrase
            # In Arabic, we show the full phrase and highlight/scale the whole phrase when active,
            # since word-by-word coloring doesn't align with English word orders.
            for active_word in chunk:
                start_str = format_ass_time(active_word['start'])
                end_str = format_ass_time(active_word['end'])
                
                is_hook = False
                if hook_start_sec is not None and hook_end_sec is not None and hook_end_sec > hook_start_sec:
                    is_hook = (hook_start_sec - 0.05 <= active_word['start'] <= hook_end_sec + 0.05)
                
                c = hook_color if is_hook else highlight_color
                # We color the entire Arabic phrase with a beautiful pop effect
                styled_text = f"{{\\fscx114\\fscy114\\t(0,80,\\fscx100\\fscy100)}}{c}{display_text}"
                style_name = "Hook" if is_hook else "TikTok"
                ass.append(f"Dialogue: 0,{start_str},{end_str},{style_name},,0,0,0,,{styled_text}")
            continue

        # Original English word-by-word logic
        for w in chunk:
            raw_text = w['text']
            clean = raw_text.strip(".,!?;:()\"'").lower()
            emoji = EMOJI_DICT.get(clean, "")
            display_text = f"{raw_text} {emoji}".strip() if emoji else raw_text
            display_words.append(display_text.upper())

        for active_idx, active_word in enumerate(chunk):
            start_str = format_ass_time(active_word['start'])
            end_str = format_ass_time(active_word['end'])
            
            is_hook = False
            if hook_start_sec is not None and hook_end_sec is not None and hook_end_sec > hook_start_sec:
                is_hook = (hook_start_sec - 0.05 <= active_word['start'] <= hook_end_sec + 0.05)
            
            formatted_parts = []
            for idx, text in enumerate(display_words):
                if idx == active_idx:
                    c = hook_color if is_hook else highlight_color
                    formatted_parts.append(f"{c}{text}{{\\c&HFFFFFF&}}")
                else:
                    formatted_parts.append(text)
            text_line = " ".join(formatted_parts)
            style_name = "Hook" if is_hook else "TikTok"
            styled_text = f"{{\\fscx115\\fscy115\\t(0,80,\\fscx100\\fscy100)}}{text_line}" if is_hook else f"{{\\fscx112\\fscy112\\t(0,80,\\fscx100\\fscy100)}}{text_line}"
            ass.append(f"Dialogue: 0,{start_str},{end_str},{style_name},,0,0,0,,{styled_text}")

    return "\n".join(ass)


def get_emphasis_timestamps(words: list, start_sec: float, end_sec: float) -> list:
    clip_words = get_words_in_range(words, start_sec, end_sec)
    emphasis = []
    for w in clip_words:
        clean = w['text'].strip(".,!?;:()\"'").lower()
        if clean in EMOJI_DICT:
            s_start = max(0.0, w['start'] - start_sec)
            s_end = max(0.0, w['end'] - start_sec)
            emphasis.append((s_start, s_end))
    return emphasis


def find_semantic_clips(words: list, n_clips: int, duration_sec: float) -> list:
    """Find the most engaging clips using multi-signal engagement scoring.
    
    Signals used:
    1. Speech Rate Variance — excitement = sudden speed changes
    2. Question Detection — rhetorical questions grab attention
    3. Emotional Keywords — Arabic/English trigger words
    4. Pause Patterns — dramatic pauses before key moments
    5. Word Density — baseline content richness
    """
    if not words:
        return []

    video_end = words[-1]['end'] if words else 0

    # ── Emotional trigger words (weighted) ─────────────────────────────
    _EMOTIONAL_TRIGGERS_AR = {
        "صدمة", "مصدوم", "خطير", "كارثة", "سر", "أسرار", "حقيقة", "كذب",
        "خطأ", "غلط", "مشكلة", "حل", "فلوس", "ملايين", "موت", "حياة",
        "حب", "كره", "خوف", "رهيب", "مجنون", "عبقري", "أول", "أخير",
        "أكبر", "أصغر", "أفضل", "أسوأ", "لازم", "ممنوع", "خلاص", "بس",
        "تخيل", "صراحة", "بصراحة", "والله", "يعني", "طبعا", "أبدا",
        "مستحيل", "معقول", "جنون", "عجيب", "غريب", "صادق",
    }
    _EMOTIONAL_TRIGGERS_EN = {
        "secret", "shocking", "dangerous", "truth", "lie", "mistake",
        "problem", "solution", "money", "millions", "death", "life",
        "love", "hate", "fear", "insane", "genius", "first", "last",
        "biggest", "worst", "best", "must", "never", "imagine",
        "honestly", "impossible", "crazy", "weird", "amazing",
        "actually", "literally", "absolutely", "exactly",
    }
    _QUESTION_MARKERS_AR = {"هل", "ليش", "ليه", "كيف", "متى", "وين", "مين", "شو", "ايش", "طيب"}
    _QUESTION_MARKERS_EN = {"why", "how", "what", "when", "where", "who", "really"}

    def _compute_engagement(window_words, all_words):
        """Compute a rich engagement score for a window of words."""
        if not window_words or len(window_words) < 3:
            return 0.0

        # 1. Word Density (baseline) — normalized by duration
        w_start = window_words[0]['start']
        w_end = window_words[-1]['end']
        dur = max(0.1, w_end - w_start)
        density_score = len(window_words) / dur  # words per second

        # 2. Speech Rate Variance — high variance = exciting
        #    Measure local speech rate in 3-second windows within the clip
        local_rates = []
        for t in range(int(w_start), int(w_end) - 2, 2):
            local_words = [w for w in window_words if t <= w['start'] < t + 3]
            if local_words:
                local_rates.append(len(local_words) / 3.0)
        rate_variance = 0.0
        if len(local_rates) >= 2:
            mean_rate = sum(local_rates) / len(local_rates)
            rate_variance = sum((r - mean_rate) ** 2 for r in local_rates) / len(local_rates)
        
        # 3. Question Detection — questions create curiosity gaps
        question_count = 0
        for w in window_words:
            clean = w['text'].strip(".,!?;:()\"'").lower()
            if clean in _QUESTION_MARKERS_AR or clean in _QUESTION_MARKERS_EN:
                question_count += 1
            if w['text'].strip().endswith('?'):
                question_count += 1

        # 4. Emotional Keyword Density
        emotional_hits = 0
        for w in window_words:
            clean = w['text'].strip(".,!?;:()\"'").lower()
            if clean in _EMOTIONAL_TRIGGERS_AR or clean in _EMOTIONAL_TRIGGERS_EN:
                emotional_hits += 1

        # 5. Dramatic Pause Detection — pauses > 0.5s before or after a word
        dramatic_pauses = 0
        for i, w in enumerate(window_words):
            if i > 0:
                gap = w['start'] - window_words[i-1]['end']
                if 0.5 < gap < 2.0:  # Dramatic pause (not dead air)
                    dramatic_pauses += 1

        # 6. Sentence Completeness — prefer windows that start/end at sentence boundaries
        boundary_bonus = 0.0
        first_word_text = window_words[0]['text'].strip()
        last_word_text = window_words[-1]['text'].strip()
        # Check if we start near a sentence boundary
        if first_word_text and first_word_text[0].isupper():
            boundary_bonus += 0.5
        # Check for gap before first word (natural break)
        w_idx = all_words.index(window_words[0]) if window_words[0] in all_words else -1
        if w_idx > 0:
            gap_before = window_words[0]['start'] - all_words[w_idx - 1]['end']
            if gap_before > 0.3:
                boundary_bonus += 0.5
        # Check if we end at a sentence boundary
        if last_word_text and last_word_text[-1] in '.!?':
            boundary_bonus += 0.5

        # ── Weighted combination ──────────────────────────────────────
        score = (
            density_score * 1.0 +          # Baseline word richness
            rate_variance * 3.0 +           # Excitement from tempo changes
            question_count * 2.0 +          # Curiosity from questions
            emotional_hits * 1.5 +          # Emotional trigger words
            dramatic_pauses * 1.0 +         # Dramatic tension from pauses
            boundary_bonus * 1.0            # Clean sentence boundaries
        )
        return round(score, 3)

    # ── Slide windows across the video ─────────────────────────────────
    windows = []
    step = 5.0
    t = 0.0
    while t < video_end - duration_sec:
        end_time = t + duration_sec
        words_in_window = [w for w in words if t <= w['start'] <= end_time]
        if words_in_window and len(words_in_window) >= 5:
            score = _compute_engagement(words_in_window, words)
            actual_start = words_in_window[0]['start']
            actual_end = words_in_window[-1]['end']
            if actual_end - actual_start > duration_sec + 5:
                actual_end = actual_start + duration_sec
            windows.append({
                "start_sec": max(0.0, actual_start - 0.5),
                "end_sec": actual_end + 0.5,
                "score": score
            })
        t += step

    windows.sort(key=lambda x: x['score'], reverse=True)

    # ── Non-overlapping selection ──────────────────────────────────────
    kept = []
    for candidate in windows:
        overlap = False
        for k in kept:
            o_start = max(candidate['start_sec'], k['start_sec'])
            o_end = min(candidate['end_sec'], k['end_sec'])
            if o_end - o_start > 0.3 * (candidate['end_sec'] - candidate['start_sec']):
                overlap = True
                break
        if not overlap:
            kept.append(candidate)
        if len(kept) >= n_clips:
            break

    kept.sort(key=lambda x: x['start_sec'])
    return kept

