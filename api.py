import os
import sys
import uuid
import json
import threading
import concurrent.futures
from typing import List, Dict, Any, Optional
from dotenv import load_dotenv

load_dotenv()

from fastapi import FastAPI, BackgroundTasks, Header, HTTPException, Query, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel

# Add current folder to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

PREFS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ui_prefs.json")

def load_ui_prefs() -> dict:
    if os.path.exists(PREFS_FILE):
        try:
            with open(PREFS_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}

def save_ui_prefs(prefs: dict) -> bool:
    try:
        with open(PREFS_FILE, "w", encoding="utf-8") as f:
            json.dump(prefs, f, indent=2, ensure_ascii=False)
        return True
    except Exception:
        return False

from audio import extract
from detector import find_clips
from downloader import download_youtube_video
from orchestrator import (
    generate_subtitles,
    _select_clips_with_ai,
    _plan_effects_with_ai,
    run_editing_plan
)
from models import EditingPlan, ClipSpec
from campaign import load_campaign
from audio_intelligence import separate_audio_tracks, apply_auto_ducking

app = FastAPI(title="ClipAI Local API Server", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "http://localhost:5174",
        "tauri://localhost",
        "http://tauri.localhost"
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

import sqlite3
DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sessions.db")

def init_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS sessions (
            session_id TEXT PRIMARY KEY,
            progress REAL,
            status TEXT,
            results TEXT,
            errors TEXT
        )
    """)
    conn.commit()
    conn.close()

# Initialize immediately
init_db()

def set_session(session_id: str, progress: float, status: str, results: list = None, errors: list = None):
    # Fetch existing to preserve or merge if we don't pass them
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT results, errors FROM sessions WHERE session_id = ?", (session_id,))
    row = cursor.fetchone()
    
    existing_results = []
    existing_errors = []
    if row:
        if row[0]:
            try: existing_results = json.loads(row[0])
            except: pass
        if row[1]:
            try: existing_errors = json.loads(row[1])
            except: pass
            
    final_results = results if results is not None else existing_results
    final_errors = errors if errors is not None else existing_errors
    
    results_json = json.dumps(final_results)
    errors_json = json.dumps(final_errors)
    
    cursor.execute("""
        INSERT INTO sessions (session_id, progress, status, results, errors)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(session_id) DO UPDATE SET
            progress=excluded.progress,
            status=excluded.status,
            results=excluded.results,
            errors=excluded.errors
    """, (session_id, progress, status, results_json, errors_json))
    conn.commit()
    conn.close()

def get_session(session_id: str) -> dict:
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT progress, status, results, errors FROM sessions WHERE session_id = ?", (session_id,))
    row = cursor.fetchone()
    conn.close()
    if row:
        return {
            "progress": row[0],
            "status": row[1],
            "results": json.loads(row[2]) if row[2] else [],
            "errors": json.loads(row[3]) if row[3] else []
        }
    return None

_download_pool = concurrent.futures.ThreadPoolExecutor(max_workers=5)
_render_pool = concurrent.futures.ThreadPoolExecutor(max_workers=1) # FIFO queue for CPU-heavy rendering/analysis tasks

class SettingsModel(BaseModel):
    n_clips: int = 5
    duration: int = 60
    subtitle_style: str = "TikTok Yellow"
    font_name: str = "Impact"
    export_quality: str = "High"
    sfx_mode: str = "normal"
    translate_to_arabic: bool = False
    auto_broll: bool = False
    gemma_multimodal: bool = False
    pexels_api_key: str = ""
    pixabay_api_key: str = ""
    output_dir: str = "./output"
    export_mode: str = "ffmpeg"
    framing_strategy: Optional[str] = "speaker_tracking"
    whisper_model: str = "tiny"

class AnalyzeRequest(BaseModel):
    video_path: str
    content_type: str = "podcast"

class GeneratePlanRequest(BaseModel):
    video_path: str
    words: List[Dict[str, Any]]
    content_type: str = "podcast"
    n_clips: int = 5
    duration_sec: float = 60.0
    custom_instructions: str = ""

class ClipRenderModel(BaseModel):
    index: int
    start_sec: float
    end_sec: float
    hook: str
    reason: str
    caption_theme: str
    zoom_style: str
    color_grade: str
    emphasis_words: List[str] = []
    sfx_queries: List[str] = []
    planned_brolls: List[Dict[str, Any]] = []
    slow_motion_start: float = 0.0
    slow_motion_end: float = 0.0
    slow_motion_speed: float = 1.0

class RenderPlanRequest(BaseModel):
    video_path: str
    clips: List[ClipRenderModel]
    content_type: str = "podcast"
    output_dir: str = "./output"
    sfx_mode: str = "normal"
    compile_clips: bool = True
    translate_to_arabic: bool = False
    font_name: str = "Impact"
    export_quality: str = "High"
    auto_broll: bool = False
    gemma_multimodal: bool = False
    pexels_api_key: str = ""
    pixabay_api_key: str = ""
    export_mode: str = "ffmpeg"
    logo_path: str = ""  # Optional watermark/logo overlay path


@app.get("/api/settings")
def get_settings():
    return load_ui_prefs()

@app.post("/api/clear-cache")
def clear_cache():
    import shutil
    cache_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cache")
    count = 0
    if os.path.exists(cache_dir):
        for f in os.listdir(cache_dir):
            try:
                os.remove(os.path.join(cache_dir, f))
                count += 1
            except:
                pass
    return {"status": "success", "message": f"تم تنظيف {count} ملف مؤقت بنجاح."}

@app.post("/api/settings")
def post_settings(settings: SettingsModel):
    if save_ui_prefs(settings.dict()):
        return {"status": "success", "message": "Settings saved successfully"}
    raise HTTPException(status_code=500, detail="Failed to save settings")



@app.get("/api/video-stream")
def stream_video_endpoint(path: str, range: Optional[str] = Header(None)):
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail=f"File not found: {path}")
    
    file_size = os.path.getsize(path)
    start, end = 0, file_size - 1
    
    if range:
        try:
            ranges = range.replace("bytes=", "").split("-")
            if ranges[0]:
                start = int(ranges[0])
            if ranges[1]:
                end = int(ranges[1])
        except ValueError:
            pass
            
    # Clip parameters
    end = min(end, file_size - 1)
    chunk_size = 1024 * 1024  # 1MB chunk size
    
    headers = {
        "Content-Range": f"bytes {start}-{end}/{file_size}",
        "Accept-Ranges": "bytes",
        "Content-Length": str(end - start + 1),
        "Content-Type": "video/mp4",
        "Access-Control-Allow-Origin": "*",
    }
    
    def file_iterator():
        with open(path, "rb") as f:
            f.seek(start)
            remaining = end - start + 1
            while remaining > 0:
                to_read = min(chunk_size, remaining)
                chunk = f.read(to_read)
                if not chunk:
                    break
                remaining -= len(chunk)
                yield chunk
                
    return StreamingResponse(file_iterator(), status_code=206, headers=headers)

@app.post("/api/download-youtube")
def download_yt(url: str = Body(..., embed=True)):
    session_id = str(uuid.uuid4())
    set_session(session_id, 0.0, "Starting download...", [], [])
    
    def run_download():
        try:
            set_session(session_id, 0.2, "Downloading YouTube Video...")
            
            # Use ClipAI's existing YouTube downloader
            out_folder = "./temp"
            os.makedirs(out_folder, exist_ok=True)
            
            # Download
            def api_progress(pct, status):
                set_session(session_id, 0.2 + (pct / 100.0) * 0.7, status)

            video_path = download_youtube_video(url, out_folder, progress_callback=api_progress)
            if video_path and os.path.exists(video_path):
                set_session(session_id, 1.0, "Done", results=[video_path])
            else:
                raise Exception("Downloaded file not found.")
        except Exception as e:
            set_session(session_id, 0.0, "Failed", errors=[str(e)])
            
    _download_pool.submit(run_download)
    return {"session_id": session_id}

@app.post("/api/transcribe")
def transcribe_endpoint(video_path: str = Body(..., embed=True)):
    if not os.path.exists(video_path):
        raise HTTPException(status_code=404, detail=f"File not found: {video_path}")
    try:
        words = generate_subtitles(video_path)
        return {"status": "success", "words": words}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class DetectSilenceRequest(BaseModel):
    video_path: str
    min_silence_duration_ms: int = 500
    threshold: float = 0.5

@app.post("/api/detect-silence")
def detect_silence_endpoint(req: DetectSilenceRequest):
    if not os.path.exists(req.video_path):
        raise HTTPException(status_code=404, detail=f"File not found: {req.video_path}")
    try:
        from faster_whisper import decode_audio
        from faster_whisper.vad import get_speech_timestamps, VadOptions
        
        # 1. Decode audio
        audio = decode_audio(req.video_path, sampling_rate=16000)
        
        # 2. Run VAD
        options = VadOptions(
            threshold=req.threshold,
            min_speech_duration_ms=250,
            min_silence_duration_ms=req.min_silence_duration_ms,
            speech_pad_ms=100
        )
        speech_segments = get_speech_timestamps(audio, options, sampling_rate=16000)
        
        # 3. Compute silent segments
        silences = []
        total_duration = len(audio) / 16000.0
        
        last_end = 0.0
        for seg in speech_segments:
            start_sec = seg["start"] / 16000.0
            end_sec = seg["end"] / 16000.0
            if start_sec > last_end:
                silences.append({
                    "start": last_end,
                    "end": start_sec,
                    "duration": start_sec - last_end
                })
            last_end = end_sec
            
        if last_end < total_duration:
            silences.append({
                "start": last_end,
                "end": total_duration,
                "duration": total_duration - last_end
            })
            
        return {"status": "success", "silences": silences, "total_duration": total_duration}
    except Exception as e:
        import traceback
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=str(e))

class CopilotChatRequest(BaseModel):
    prompt: str
    transcript: List[Dict[str, Any]]
    timeline_state: Dict[str, Any]

@app.post("/api/copilot/chat")
def copilot_chat_endpoint(req: CopilotChatRequest):
    try:
        from campaign import GEMMA_API_KEY
        from google import genai
        from google.genai import types
        
        if not GEMMA_API_KEY:
            raise HTTPException(status_code=500, detail="GEMMA_API_KEY is missing")
            
        client = genai.Client(api_key=GEMMA_API_KEY)
        
        system_instruction = """
You are ClipAI's video editor co-pilot (المساعد الذكي), an expert AI assistant designed to help creators edit videos through natural language.
The user will give you commands (in Arabic or English) to modify the video timeline.
You have access to the current timeline state and the video transcript.

Current Timeline Schema:
- project_name: str
- settings: { width, height, fps, aspect_ratio }
- tracks: { video: [{ clips: [...] }], subtitles: [{ clips: [...] }], overlays: [{ clips: [...] }], audio: [{ clips: [...] }] }

VideoClip Schema:
- id: str
- source_path: str
- start_time_in_timeline: float
- end_time_in_timeline: float
- source_trim_start: float
- source_trim_end: float
- speed: float
- volume: float
- color_grading: { brightness, contrast, saturation, temperature, lut_path }
- ai_features: { face_tracking, bg_removed, bg_remove_method, chromakey_color }

Your response MUST be a JSON object containing:
1. "response_message": A friendly, natural Arabic response (2-3 sentences) explaining what changes you decided to make and why, or offering guidance if the request is not related to video editing.
2. "actions": A list of modifications to apply to the timeline. If no modifications are needed, return an empty list [].

Possible action types:
- {"type": "select_clips", "clips": [{"start_sec": float, "end_sec": float}]} -> Clears the current clips and creates new clips in the timeline at these time ranges.
- {"type": "delete_clip", "clip_id": string} -> Deletes a specific clip from the timeline.
- {"type": "update_clip", "clip_id": string, "fields": {...}} -> Updates properties of a clip (e.g. speed, volume, color_grading, ai_features).
- {"type": "update_subtitle_style", "fields": {...}} -> Updates subtitle styles.
- {"type": "update_settings", "fields": {...}} -> Updates timeline settings (e.g. aspect_ratio).

IMPORTANT RULES:
- Speak in friendly Arabic.
- If the user wants to center the speaker or follow face, update the target clip's `ai_features.face_tracking` to `true`.
- If the user wants to remove background, set `ai_features.bg_removed` to `true` and optionally set `bg_remove_method` (e.g. 'rmbg', 'chromakey', 'sam').
- Output ONLY the raw JSON object. Do not include markdown code block backticks (```json or ```), and do not add conversational preamble.
"""
        
        user_prompt = f"""
Timeline State:
{json.dumps(req.timeline_state, ensure_ascii=False)}

Transcript (first 300 words):
{json.dumps(req.transcript[:300], ensure_ascii=False)}

User Command:
{req.prompt}
"""
        
        response = None
        models_to_try = ["gemma-4-31b-it", "gemma-2-27b-it", "gemini-1.5-flash"]
        last_error = None
        
        for model in models_to_try:
            try:
                print(f"  [Copilot] Querying model {model}...")
                response = client.models.generate_content(
                    model=model,
                    contents=[user_prompt],
                    config=types.GenerateContentConfig(
                        system_instruction=system_instruction,
                        temperature=0.3,
                        response_mime_type="application/json"
                    )
                )
                if response and response.text:
                    print(f"  [Copilot] Success with {model}")
                    break
            except Exception as model_err:
                print(f"  [Copilot] Model {model} failed: {model_err}")
                last_error = model_err
                
        if not response or not response.text:
            raise Exception(f"All generative models failed. Last error: {last_error}")
            
        resp_text = response.text.strip()
        
        if "```" in resp_text:
            parts = resp_text.split("```")
            for part in parts:
                part = part.strip()
                if part.startswith("json"):
                    part = part[4:].strip()
                if part.startswith("{") and part.endswith("}"):
                    resp_text = part
                    break
                    
        parsed = json.loads(resp_text)
        return parsed
    except Exception as e:
        import traceback
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/analyze-video")
def analyze_video(req: AnalyzeRequest):
    video_path = req.video_path
    if not os.path.exists(video_path):
        raise HTTPException(status_code=404, detail="Local video file not found")
        
    session_id = str(uuid.uuid4())
    set_session(session_id, 0.0, "Extracting audio and transcribing...", [], [])
    
    def run_analysis():
        try:
            # 1. Transcribe audio using faster-whisper
            set_session(session_id, 0.1, "Transcribing audio...")
            words = generate_subtitles(video_path)
            
            if not words:
                raise Exception("Could not extract speech from this video.")
                
            # 2. Extract DNA
            set_session(session_id, 0.6, "Extracting Content DNA...")
            
            from content_dna import extract_content_dna
            # Mock or minimal LLM helper for offline usage
            def local_llm_dummy(prompt):
                return '{"tone": "conversational", "speakers_type": "single-speaker", "target_pacing": "normal"}'
                
            content_dna = extract_content_dna(words, llm_fn=local_llm_dummy)
            
            # 3. Viral Scorer Timeline
            set_session(session_id, 0.8, "Computing viral engagement score...")
            
            viral_timeline = {}
            try:
                from viral_scorer import get_viral_timeline
                viral_timeline = get_viral_timeline(video_path, words)
            except Exception as e:
                print(f"Viral Scorer skipped: {e}")
                
            set_session(session_id, 1.0, "Done", results={
                "words": words,
                "content_dna": content_dna,
                "viral_timeline": viral_timeline,
                "video_path": video_path
            })
        except Exception as e:
            set_session(session_id, 0.0, "Failed", errors=[str(e)])
            
    _render_pool.submit(run_analysis)
    return {"session_id": session_id}

@app.post("/api/generate-plan")
def generate_plan(req: GeneratePlanRequest):
    # Generates semantic moments list and planning parameters for the editor
    try:
        # Get viral context
        viral_context = ""
        # Local Gemma 4 or offline solver logic
        semantic_clips = _select_clips_with_ai(
            req.words, req.n_clips, req.duration_sec,
            req.content_type, viral_context=viral_context,
            custom_instructions=req.custom_instructions
        )
        
        # Now run effect planning
        clip_texts = []
        clip_words_list = []
        for c in semantic_clips:
            cw = [w for w in req.words if c['start_sec'] <= w['start'] <= c['end_sec']]
            clip_texts.append(" ".join(w['text'] for w in cw)[:200])
            clip_words_list.append(cw)
            
        effects = _plan_effects_with_ai(
            clip_texts, req.content_type,
            auto_broll=True, clip_words_list=clip_words_list
        )
        
        # Merge effects back into clips
        clips_final = []
        for idx, c in enumerate(semantic_clips):
            eff = next((e for e in effects if e.get("index") == c.get("index")), {})
            clips_final.append({
                "index": c.get("index"),
                "start_sec": c.get("start_sec"),
                "end_sec": c.get("end_sec"),
                "hook": c.get("hook_options", [""])[0],
                "reason": c.get("reason", ""),
                "caption_theme": eff.get("caption_theme", "TikTok"),
                "zoom_style": eff.get("zoom_style", "none"),
                "color_grade": eff.get("color_grade", "original"),
                "emphasis_words": eff.get("emphasis_words", []),
                "sfx_queries": eff.get("sfx_queries", []),
                "planned_brolls": eff.get("brolls", []),
                "hook_options": c.get("hook_options", []),
                "slow_motion_start": eff.get("slow_motion_start", 0.0),
                "slow_motion_end": eff.get("slow_motion_end", 0.0),
                "slow_motion_speed": eff.get("slow_motion_speed", 1.0)
            })
            
        return {"status": "success", "clips": clips_final}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/render-plan")
def render_plan(req: RenderPlanRequest):
    session_id = str(uuid.uuid4())
    set_session(session_id, 0.0, "Initializing render process...", [], [])
    
    def run_rendering():
        try:
            # Build EditingPlan object
            # Convert request clips to ClipSpec list
            specs = []
            for c in req.clips:
                spec = ClipSpec(
                    index=c.index,
                    start_sec=c.start_sec,
                    end_sec=c.end_sec,
                    hook=c.hook,
                    reason=c.reason,
                    caption_theme=c.caption_theme,
                    zoom_style=c.zoom_style,
                    color_grade=c.color_grade,
                    emphasis_words=c.emphasis_words,
                    sfx_queries=c.sfx_queries,
                    hook_options=[]
                )
                spec.planned_brolls = c.planned_brolls
                spec.slow_motion_start = c.slow_motion_start
                spec.slow_motion_end = c.slow_motion_end
                spec.slow_motion_speed = c.slow_motion_speed
                specs.append(spec)
                
            plan = EditingPlan(
                video_path=req.video_path,
                n_clips=len(req.clips),
                duration_sec=req.clips[0].end_sec - req.clips[0].start_sec if req.clips else 60.0,
                music_path="",
                compile_clips=req.compile_clips,
                global_music=False,
                global_ending_cta="",
                content_type=req.content_type,
                custom_instructions="",
                hook_mode=True,
                outro_enabled=True,
                framing_strategy="speaker_tracking",
                font_name=req.font_name,
                export_quality=req.export_quality,
                logo_path=req.logo_path,
                translate_to_arabic=req.translate_to_arabic,
                caption_animation_mode="auto",
                gemma_multimodal=req.gemma_multimodal,
                auto_broll=req.auto_broll,
                pexels_api_key=req.pexels_api_key,
                pixabay_api_key=req.pixabay_api_key,
                api_key="",
                sfx_mode=req.sfx_mode,
                use_scene_captioning=False,
                use_local_captioning=True,
                export_mode=req.export_mode,
                plan_review_callback=None
            )
            plan.clips = specs
            
            def status_update(msg):
                import re
                # Parse progress percent like (52%)
                m = re.search(r'\((\d+)%\)', msg)
                pct = 0.0
                if m:
                    pct = int(m.group(1)) / 100.0
                set_session(session_id, pct, msg)
                
            clip_paths = run_editing_plan(plan, status_callback=status_update, sound_fx=True)
            
            # Copy to output_dir
            import shutil
            os.makedirs(req.output_dir, exist_ok=True)
            final_files = []
            for cp in clip_paths:
                dest = os.path.join(req.output_dir, os.path.basename(cp))
                shutil.copy2(cp, dest)
                final_files.append(os.path.abspath(dest))
                
            set_session(session_id, 1.0, f"Done! {len(final_files)} clips exported.", results=final_files)
        except Exception as e:
            set_session(session_id, 0.0, "Failed", errors=[str(e)])
            
    _render_pool.submit(run_rendering)
    return {"session_id": session_id}

@app.get("/api/status")
def get_status(session_id: str):
    sess = get_session(session_id)
    if not sess:
        raise HTTPException(status_code=404, detail="Session not found")
    return sess

# ── Reference Video Style Mimicry Endpoints ───────────────────────────────

class AnalyzeReferenceRequest(BaseModel):
    reference_path: str
    profile_name: str

class ImitateRequest(BaseModel):
    target_path: str
    profile_path: str
    output_name: str
    words: List[Dict[str, Any]]

@app.post("/api/style/analyze-reference")
def analyze_reference(req: AnalyzeReferenceRequest):
    if not os.path.exists(req.reference_path):
        raise HTTPException(status_code=404, detail=f"Reference video file not found: {req.reference_path}")
        
    profile_dir = "./profiles"
    os.makedirs(profile_dir, exist_ok=True)
    profile_out_path = os.path.join(profile_dir, f"{req.profile_name}.json")
    
    try:
        from style_analyzer import StyleAnalyzer
        analyzer = StyleAnalyzer(req.reference_path)
        profile = analyzer.generate_style_profile(profile_out_path)
        return {
            "status": "success", 
            "profile": profile, 
            "profile_path": os.path.abspath(profile_out_path)
        }
    except Exception as e:
        import traceback
        print(f"Reference video analysis failed: {traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"Analysis engine failed: {str(e)}")

@app.post("/api/style/imitate")
def imitate_style(req: ImitateRequest):
    if not os.path.exists(req.target_path):
        raise HTTPException(status_code=404, detail=f"Target raw video not found: {req.target_path}")
        
    real_profile_path = req.profile_path
    if not os.path.isabs(real_profile_path):
        real_profile_path = os.path.abspath(os.path.join(".", real_profile_path))
        
    if not os.path.exists(real_profile_path):
        fallback_path = os.path.join("./profiles", os.path.basename(real_profile_path))
        if os.path.exists(fallback_path):
            real_profile_path = fallback_path
        else:
            raise HTTPException(status_code=404, detail=f"Style profile JSON not found at: {real_profile_path}")
         
    output_dir = "./output"
    os.makedirs(output_dir, exist_ok=True)
    output_video_path = os.path.join(output_dir, f"{req.output_name}.mp4")
    
    try:
        from style_imitator import StyleImitator
        imitator = StyleImitator(req.target_path, real_profile_path)
        
        session_id = str(uuid.uuid4())
        set_session(session_id, 0.1, "Starting rendering with Style Imitator...", [], [])
        
        def run_rendering():
            try:
                print(f"Rendering job started in background thread for output: {output_video_path}")
                imitator.generate_mimicry_edit(output_video_path, req.words)
                set_session(session_id, 1.0, "Done", results=[os.path.abspath(output_video_path)])
                print("Rendering job finished successfully.")
            except Exception as ex:
                import traceback
                print(f"Render engine error: {traceback.format_exc()}")
                set_session(session_id, 0.0, "Failed", errors=[str(ex)])
                
        _render_pool.submit(run_rendering)
        return {"status": "success", "session_id": session_id}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Initiation failed: {str(e)}")

@app.get("/api/style/profiles")
def list_profiles():
    profile_dir = "./profiles"
    os.makedirs(profile_dir, exist_ok=True)
    profiles = []
    for f in os.listdir(profile_dir):
        if f.endswith(".json"):
            try:
                p_path = os.path.join(profile_dir, f)
                with open(p_path, "r", encoding="utf-8") as file:
                    data = json.load(file)
                    profiles.append({
                        "name": f.replace(".json", ""),
                        "meta": data.get("meta", {}),
                        "pacing": data.get("pacing", {}),
                        "path": os.path.abspath(p_path)
                    })
            except Exception:
                pass
    return profiles


class AutoCutRequest(BaseModel):
    video_path: str
    words: List[Dict[str, Any]]

class AutoFramingRequest(BaseModel):
    timeline: Dict[str, Any]
    clip_id: str

@app.post("/api/project/ai/autocut")
def ai_autocut(req: AutoCutRequest):

    import time
    from silence_trimmer import compute_active_segments
    from timeline_models import TimelineState, Tracks, VideoTrack, VideoClip, TransformState, ColorGradingState, AIFeatures, TimelineSettings
    
    if not req.words:
        raise HTTPException(status_code=400, detail="Words list is required for auto-cut")
        
    duration = req.words[-1]["end"] if req.words else 10.0
    active_segs = compute_active_segments(req.words, 0.0, duration, content_type="podcast", trim_mode="natural")
    
    video_clips = []
    for idx, (start, end) in enumerate(active_segs):
        video_clips.append(VideoClip(
            id=f"clip_v_autocut_{idx}",
            source_path=req.video_path,
            start_time_in_timeline=start,
            end_time_in_timeline=end,
            source_trim_start=start,
            source_trim_end=end,
            speed=1.0,
            volume=1.0,
            transform=TransformState(),
            color_grading=ColorGradingState(),
            ai_features=AIFeatures()
        ))
        
    # Convert word list to SubtitleClips
    from timeline_models import SubtitleTrack, SubtitleClip, SubtitleClipStyle
    subtitle_clips = []
    for i in range(0, len(req.words), 5):
        chunk = req.words[i:i+5]
        subtitle_clips.append(SubtitleClip(
            id=f"sub_autocut_{i}",
            text=" ".join([w["text"] for w in chunk]),
            start_time=chunk[0]["start"],
            end_time=chunk[-1]["end"],
            style=SubtitleClipStyle()
        ))
        
    timeline = TimelineState(
        project_id=f"proj_autocut_{int(time.time())}",
        project_name="Auto-Cut Project",
        settings=TimelineSettings(width=1080, height=1920, fps=30, aspect_ratio="9:16"),
        tracks=Tracks(
            video=[VideoTrack(id="v_track_main", name="Main Video Track", clips=video_clips)],
            audio=[],
            subtitles=[SubtitleTrack(id="sub_track_main", clips=subtitle_clips)],
            overlays=[]
        )
    )
    
    return {"timeline": timeline.dict()}

@app.post("/api/project/ai/autoframing")
def ai_autoframing(req: AutoFramingRequest):
    from tracker import track_faces_in_video
    
    timeline = req.timeline
    clip_id = req.clip_id
    
    target_clip = None
    target_track_idx = -1
    target_clip_idx = -1
    
    for t_idx, track in enumerate(timeline.get("tracks", {}).get("video", [])):
        for c_idx, clip in enumerate(track.get("clips", [])):
            if clip.get("id") == clip_id:
                target_clip = clip
                target_track_idx = t_idx
                target_clip_idx = c_idx
                break
        if target_clip:
            break
            
    if not target_clip:
        raise HTTPException(status_code=404, detail="Clip not found in timeline")
        
    video_path = target_clip.get("source_path")
    start = target_clip.get("start_time_in_timeline", 0.0)
    end = target_clip.get("end_time_in_timeline", 5.0)
    
    keyframes = track_faces_in_video(video_path, start, end)
    
    timeline["tracks"]["video"][target_track_idx]["clips"][target_clip_idx]["transform"]["keyframes"] = keyframes
    timeline["tracks"]["video"][target_track_idx]["clips"][target_clip_idx]["ai_features"]["face_tracking"] = True
    
    return {"timeline": timeline}

class SeparateAudioRequest(BaseModel):
    video_path: str

class DuckingRequest(BaseModel):
    vocals_path: str
    background_path: str
    output_path: str
    duck_factor: float = 0.2
    words: Optional[List[Dict[str, Any]]] = None

@app.post("/api/audio/separate")
def api_separate_audio(req: SeparateAudioRequest):
    try:
        res = separate_audio_tracks(req.video_path)
        return {"status": "success", "vocals": res["vocals"], "background": res["background"]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/audio/ducking")
def api_audio_ducking(req: DuckingRequest):
    try:
        res_path = apply_auto_ducking(
            req.vocals_path,
            req.background_path,
            req.output_path,
            req.duck_factor,
            req.words
        )
        return {"status": "success", "output_path": res_path}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class ViralRecommendationsRequest(BaseModel):
    words: List[Dict[str, Any]]
    dna: Dict[str, Any]
    viral_timeline: Dict[str, float]

@app.post("/api/viral/recommendations")
def api_viral_recommendations(req: ViralRecommendationsRequest):
    try:
        from viral_recommendations import generate_viral_recommendations
        timeline = {float(k): v for k, v in req.viral_timeline.items()}
        recs = generate_viral_recommendations(req.dna, timeline, req.words)
        return {"status": "success", "recommendations": recs}
    except Exception as e:
        import traceback
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=str(e))

class NleRenderRequest(BaseModel):
    timeline: Dict[str, Any]
    output_filename: str = "nle_export.mp4"

@app.post("/api/project/render/timeline")
def api_render_timeline(req: NleRenderRequest):
    try:
        from nle_renderer import render_timeline
        output_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "exports", req.output_filename)
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        render_timeline(req.timeline, output_path)
        return {"status": "success", "output_path": output_path}
    except Exception as e:
        import traceback
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=str(e))

class XmlExportRequest(BaseModel):
    timeline: Dict[str, Any]
    output_path: str = ""
    format: str = "davinci"   # "davinci" | "premiere"

@app.post("/api/project/export/xml")
def api_export_xml(req: XmlExportRequest):
    try:
        from resolve_exporter import export_timeline_to_fcp_xml
        exports_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "exports")
        os.makedirs(exports_dir, exist_ok=True)
        out = req.output_path or os.path.join(exports_dir, f"project_{int(__import__('time').time())}.xml")
        result_path = export_timeline_to_fcp_xml(req.timeline, out)
        return {"status": "success", "output_path": result_path}
    except Exception as e:
        import traceback
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/browse-file")
async def browse_file():
    """Open a native Windows file dialog to pick video files."""
    try:
        import ctypes
        from ctypes import wintypes

        OFN_FILEMUSTEXIST = 0x00001000
        OFN_PATHMUSTEXIST = 0x00000800
        OFN_NOCHANGEDIR = 0x00000008
        OFN_ALLOWMULTISELECT = 0x00000200

        class OPENFILENAME(ctypes.Structure):
            _fields_ = [
                ("lStructSize", wintypes.DWORD),
                ("hwndOwner", wintypes.HWND),
                ("hInstance", wintypes.HINSTANCE),
                ("lpstrFilter", wintypes.LPCWSTR),
                ("lpstrCustomFilter", wintypes.LPWSTR),
                ("nMaxCustFilter", wintypes.DWORD),
                ("nFilterIndex", wintypes.DWORD),
                ("lpstrFile", wintypes.LPWSTR),
                ("nMaxFile", wintypes.DWORD),
                ("lpstrFileTitle", wintypes.LPWSTR),
                ("nMaxFileTitle", wintypes.DWORD),
                ("lpstrInitialDir", wintypes.LPCWSTR),
                ("lpstrTitle", wintypes.LPCWSTR),
                ("Flags", wintypes.DWORD),
                ("nFileOffset", wintypes.WORD),
                ("nFileExtension", wintypes.WORD),
                ("lpstrDefExt", wintypes.LPCWSTR),
                ("lCustData", wintypes.LPARAM),
                ("lpfnHook", wintypes.LPVOID),
                ("lpTemplateName", wintypes.LPCWSTR),
            ]

        buf = ctypes.create_unicode_buffer(65536)
        buf[0] = '\0'
        ofn = OPENFILENAME(
            lStructSize=ctypes.sizeof(OPENFILENAME),
            hwndOwner=None,
            lpstrFilter="Video Files\0*.mp4;*.mov;*.avi;*.mkv;*.webm;*.flv\0All Files\0*.*\0",
            lpstrFile=buf,
            nMaxFile=len(buf),
            lpstrTitle="اختر فيديو",
            Flags=OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR | OFN_ALLOWMULTISELECT,
        )
        ctypes.windll.comdlg32.GetOpenFileNameW(ctypes.byref(ofn))
        result = buf.value
        if result:
            # Multi-select returns: "path\0file1\0file2\0\0"
            parts = [p for p in buf.split('\0') if p]
            if len(parts) > 1:
                dir_path = parts[0]
                files = [os.path.join(dir_path, f) for f in parts[1:]]
            else:
                files = [result]
            return {"file_paths": list(dict.fromkeys(f for f in files if os.path.exists(f)))}
    except Exception as e:
        # Fallback: tkinter
        try:
            import tkinter as tk
            from tkinter import filedialog
            root = tk.Tk()
            root.withdraw()
            root.attributes('-topmost', True)
            root.update()
            files = filedialog.askopenfilenames(
                title="اختر ملف فيديو",
                filetypes=[("Video files", "*.mp4 *.mov *.avi *.mkv *.webm *.flv")]
            )
            root.destroy()
            if files:
                return {"file_paths": list(files)}
        except:
            pass
        print(f"[browse-file] Failed: {e}")
    return {"file_paths": []}

@app.get("/api/health")
def health_check():
    return {"status": "ok", "app_dir": os.path.dirname(os.path.abspath(__file__))}

class SaveProjectRequest(BaseModel):
    timeline: Dict[str, Any]
    output_path: Optional[str] = None

@app.post("/api/project/save")
def api_save_project(req: SaveProjectRequest):
    try:
        timeline = req.timeline
        project_id = timeline.get("project_id", f"proj_{int(__import__('time').time())}")
        project_name = timeline.get("project_name", "Untitled Project")
        
        projects_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "projects")
        os.makedirs(projects_dir, exist_ok=True)
        
        file_path = req.output_path or os.path.join(projects_dir, f"{project_id}.clipai")
        
        with open(file_path, "w", encoding="utf-8") as f:
            json.dump(timeline, f, ensure_ascii=False, indent=2)
            
        recents_path = os.path.join(projects_dir, "recent_projects.json")
        recents = []
        if os.path.exists(recents_path):
            try:
                with open(recents_path, "r", encoding="utf-8") as f:
                    recents = json.load(f)
            except Exception:
                recents = []
                
        recents = [r for r in recents if r.get("path") != file_path]
        recents.insert(0, {
            "project_id": project_id,
            "project_name": project_name,
            "path": file_path,
            "last_modified": __import__('time').time()
        })
        
        recents = recents[:10]
        
        with open(recents_path, "w", encoding="utf-8") as f:
            json.dump(recents, f, ensure_ascii=False, indent=2)
            
        return {"status": "success", "file_path": file_path}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/project/load")
def api_load_project(path: str):
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail=f"Project file not found: {path}")
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return {"status": "success", "timeline": data}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/project/recent")
def api_recent_projects():
    projects_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "projects")
    recents_path = os.path.join(projects_dir, "recent_projects.json")
    if not os.path.exists(recents_path):
        return []
    try:
        with open(recents_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return []


class BrollSearchRequest(BaseModel):
    query: str
    pexels_api_key: Optional[str] = ""
    pixabay_api_key: Optional[str] = ""
    engine: Optional[str] = "both"  # "pexels" | "pixabay" | "both"

class BrollDownloadRequest(BaseModel):
    download_url: str
    keyword: str

@app.post("/api/broll/search")
def api_broll_search(req: BrollSearchRequest):
    try:
        results = []
        if req.engine in ("pexels", "both"):
            from broll_manager import search_pexels_videos
            results.extend(search_pexels_videos(req.query, req.pexels_api_key))
        if req.engine in ("pixabay", "both"):
            from broll_manager import search_pixabay_videos
            results.extend(search_pixabay_videos(req.query, req.pixabay_api_key))
        return {"status": "success", "results": results}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/broll/download")
def api_broll_download(req: BrollDownloadRequest):
    try:
        import requests
        from broll_manager import clean_filename
        
        temp_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "temp")
        os.makedirs(temp_dir, exist_ok=True)
        
        filename = f"broll_{clean_filename(req.keyword)}_{int(__import__('time').time())}.mp4"
        dest_path = os.path.join(temp_dir, filename)
        
        print(f"Downloading B-roll from {req.download_url} to {dest_path}...")
        resp = requests.get(req.download_url, stream=True, timeout=30)
        if resp.status_code == 200:
            with open(dest_path, "wb") as f:
                for chunk in resp.iter_content(chunk_size=1024 * 1024):
                    if chunk:
                        f.write(chunk)
            return {"status": "success", "video_path": os.path.abspath(dest_path)}
        else:
            raise HTTPException(status_code=resp.status_code, detail="Failed to download B-roll file.")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class BeatAnalyzeRequest(BaseModel):
    audio_path: str

@app.post("/api/analyze-beats")
def analyze_beats(req: BeatAnalyzeRequest):
    try:
        import librosa
        import numpy as np
        if not os.path.exists(req.audio_path):
            raise HTTPException(status_code=404, detail="Audio file not found")

        print(f"  [BEAT SYNC] Analyzing beats for: {req.audio_path}")
        y, sr = librosa.load(req.audio_path)
        tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr)
        beat_times = librosa.frames_to_time(beat_frames, sr=sr)

        return {
            "status": "success",
            "tempo": float(tempo[0]) if isinstance(tempo, np.ndarray) else float(tempo),
            "beats": beat_times.tolist()
        }
    except Exception as e:
        print(f"Error analyzing beats: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ════════════════════════════════════════════════════════════════════════
# AI COPILOT — Phase 0: Function-Calling with TOOL_REGISTRY
# ════════════════════════════════════════════════════════════════════════

class AICopilotRequest(BaseModel):
    prompt: str
    timeline_state: Optional[Dict[str, Any]] = None
    words: Optional[List[Dict[str, Any]]] = None
    history: Optional[List[Dict[str, str]]] = None
    video_path: Optional[str] = None


class AIExecuteRequest(BaseModel):
    actions: List[Dict[str, Any]]
    timeline_state: Dict[str, Any]


@app.post("/api/ai/copilot")
def ai_copilot_endpoint(req: AICopilotRequest):
    """
    Main AI Copilot endpoint using TOOL_REGISTRY (219 tools).
    Returns:
    - actions: validated tool calls
    - response_message: Arabic explanation
    - confirmation_groups: {trusted: [...], destructive: [...]}
    """
    try:
        from ai_copilot import copilot_chat
        result = copilot_chat(
            prompt=req.prompt,
            timeline_state=req.timeline_state,
            words=req.words,
            history=req.history,
            video_path=req.video_path,
        )
        return {"status": "success", **result}
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"AI Copilot error: {str(e)[:300]}")


@app.post("/api/ai/execute")
def ai_execute_endpoint(req: AIExecuteRequest):
    """
    Execute an approved action plan against the timeline state.
    Returns the new state + per-action results.
    """
    try:
        from ai_orchestrator import execute_action_plan
        result = execute_action_plan(req.actions, req.timeline_state)
        return {"status": "success", **result}
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"AI execute error: {str(e)[:300]}")


@app.get("/api/ai/tools")
def ai_list_tools():
    """List all available AI tools (grouped by category)."""
    try:
        from ai_copilot import get_all_tools_grouped
        grouped = get_all_tools_grouped()
        return {
            "status": "success",
            "tools": grouped,
            "total": sum(len(v) for v in grouped.values()),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/ai/validate")
def ai_validate_actions(req: AIExecuteRequest):
    """Validate + categorize actions (trusted vs destructive) without executing."""
    try:
        from ai_orchestrator import needs_user_approval, get_destructive_actions, get_safe_actions
        return {
            "status": "success",
            "needs_approval": needs_user_approval(req.actions),
            "destructive": get_destructive_actions(req.actions),
            "safe": get_safe_actions(req.actions),
            "total": len(req.actions),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
