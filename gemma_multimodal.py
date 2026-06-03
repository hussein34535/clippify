"""
gemma_multimodal.py — Video Intelligence via Gemma Multimodal API (Phase 7)
==========================================================================
Uploads raw video files directly to Gemma's File API, waits for processing,
and queries Gemma for high-impact viral moments, hook texts, and B-roll queries.
"""

import os
import time
import json
from typing import List, Dict, Any, Optional
from scene_describer import describe_video_segment

# We use the official google-genai library if installed, otherwise raw requests
try:
    from google import genai
    from google.genai import types
    GENAI_AVAILABLE = True
except ImportError:
    GENAI_AVAILABLE = False


def upload_and_analyze_video(
    video_path: str,
    api_key: str,
    n_clips: int = 3,
    duration_sec: float = 20.0,
    content_type: str = "podcast",
    words: Optional[list] = None,
    use_scene_captioning: bool = False,
    use_local_captioning: bool = True,
) -> List[Dict[str, Any]]:
    if not api_key:
        print("  [GemmaVideo] API Key is missing! Falling back...")
        return []

    if not GENAI_AVAILABLE:
        print("  [GemmaVideo] google-genai package is not installed! Run `pip install google-genai`.")
        return []

    print(f"  [GemmaVideo] Initializing Gemma Client...")
    client = genai.Client(api_key=api_key)

    video_size_mb = os.path.getsize(video_path) / (1024 * 1024)
    contents = []
    
    if words:
        print(f"  [GemmaVideo] Bypassing massive video upload ({video_size_mb:.1f} MB) -> Using precise text transcript instead!")
        
        # ── Optional: Extract & Describe visual scenes (Scene-to-Text) ──
        visual_context = ""
        if use_scene_captioning:
            print("  [GemmaVideo] Running Scene-to-Text captioning to enhance AI visual understanding...")
            try:
                # We sample 1 keyframe every 40 seconds across the video to avoid making prompt too large
                total_duration = words[-1]['end'] if words else 300.0
                max_frames = 30 if use_local_captioning else 8
                n_frames_to_sample = max(3, min(int(total_duration / 40.0), max_frames))
                
                scenes = describe_video_segment(
                    video_path=video_path,
                    start_sec=0.0,
                    end_sec=total_duration,
                    n_frames=n_frames_to_sample,
                    use_local=use_local_captioning,
                    api_key=api_key
                )
                
                if scenes:
                    visual_context_lines = []
                    for s in scenes:
                        visual_context_lines.append(f"- [{s['timestamp_sec']:.1f}s]: {s['description']}")
                    visual_context = "\n".join(visual_context_lines)
                    print(f"  [GemmaVideo] Successfully added {len(scenes)} visual scene descriptions to Prompt!")
            except Exception as e:
                print(f"  [GemmaVideo] Scene captioning failed: {e}")

        # Build transcript text
        transcript_lines = []
        for w in words:
            transcript_lines.append(f"[{w['start']:.1f}s] {w['text']}")
        transcript_text = "\n".join(transcript_lines)
        
        visual_desc_prompt = ""
        if visual_context:
            visual_desc_prompt = f"\nVisual Scene Descriptions (What is happening visually in the video at these timestamps):\n{visual_context}\n"
            
        prompt = f"""You are a professional social media video editor specializing in {content_type} content for TikTok, Instagram Reels, and YouTube Shorts.
Analyze this timestamped video transcript AND the visual scene descriptions (if provided) to select exactly {n_clips} highly engaging, self-contained clips of approximately {duration_sec:.0f} seconds each.

For each selected clip, identify the optimal start and end timestamps, a high-converting hook subtitle, and plan visual B-roll overlays to make the video highly engaging.
B-roll queries should be in English (such as 'stress', 'group arguing', 'counting cash', 'fast highway') suitable for searching on royalty-free stock websites.
{visual_desc_prompt}
Transcript:
{transcript_text}

IMPORTANT RULES:
1. Do NOT overlap the selected clips.
2. Select clips that contain high excitement, laughter, intense debate, shocking facts, or strong emotional hooks.
3. Ensure the start_sec and end_sec are precise relative to the transcript timestamps.
4. B-rolls are STRICTLY OPTIONAL. Only include them if the visual context is boring. Return an empty list [] if the speaker's face is more engaging. If you use them, B-roll start_offset must be relative to the START of that clip (e.g., start_offset=2.0 means 2 seconds into the clip), and duration should be 2.0-4.0 seconds.
5. You MUST generate actual, unique Arabic hook titles in "hook_options", do not just copy the placeholders.

Return ONLY a valid JSON list of objects in this exact format with NO markdown wrapping, NO backticks, and NO conversational text:
[
  {{
    "index": 1,
    "start_sec": 14.5,
    "end_sec": 34.5,
    "hook_options": [
      "<Generate Arabic Hook 1>",
      "<Generate Arabic Hook 2>",
      "<Generate Arabic Hook 3>"
    ],
    "reason": "Speaker shows intense regret, high audio volume, and dramatic head shake.",
    "viral_score": 0.95,
    "brolls": [
      {{"keyword": "financial crash", "start_offset": 2.0, "duration": 3.0}}
    ]
  }}
]"""
        contents = [prompt]
    else:
        print(f"  [GemmaVideo] Running FULL Multimodal Video Upload & Analysis ({video_size_mb:.1f} MB)...")
        try:
            uploaded_file = client.files.upload(file=video_path)
            print(f"  [GemmaVideo] Uploaded file successfully. Waiting for Gemma API to process the video...")
            
            # Wait for file to become ACTIVE (Max 5 minutes)
            for _ in range(150):
                uploaded_file = client.files.get(name=uploaded_file.name)
                if uploaded_file.state.name == "ACTIVE":
                    print("  [GemmaVideo] Video file is now ACTIVE and ready for multimodal analysis!")
                    break
                elif uploaded_file.state.name == "FAILED":
                    raise Exception("Gemma video file API processing FAILED.")
                time.sleep(2)
            else:
                raise TimeoutError("Gemma video file API processing timed out.")
                
            prompt = f"""You are a professional social media video editor specializing in {content_type} content.
Analyze this video directly to select exactly {n_clips} highly engaging, self-contained clips of approximately {duration_sec:.0f} seconds each.
Since this is a non-verbal, gaming, sports, action, or highly visual video:
- Identify the absolute peaks of action, excitement, dramatic moments, visual stunts, goals, explosions, or intense combat kills.
- Look at both visual motion dynamics (fast changes) and audio energy spikes.
- Select segments that are visually interesting and have high narrative/action value.

For each selected clip, identify the optimal start and end timestamps, a high-converting hook title, and reason for selection.
You MUST generate actual, unique Arabic hook titles in "hook_options", do not just copy the placeholders.

Return ONLY a valid JSON list of objects in this exact format with NO markdown wrapping, NO backticks, and NO conversational text:
[
  {{
    "index": 1,
    "start_sec": 14.5,
    "end_sec": 34.5,
    "hook_options": [
      "<Generate Arabic Hook 1>",
      "<Generate Arabic Hook 2>",
      "<Generate Arabic Hook 3>"
    ],
    "reason": "Dramatic visual action peak, high movement, intense sound cue.",
    "viral_score": 0.96
  }}
]"""
            contents = [uploaded_file, prompt]
            
        except Exception as e:
            print(f"  [GemmaVideo] Multimodal upload/processing failed: {e}. Falling back to empty.")
            return []

    # ── Query Multimodal Model ─────────────────────────────────────────────
    model_name = "gemma-4-31b-it"
    print(f"  [GemmaVideo] Querying model {model_name}...")

    chosen_clips = []
    try:
        response = client.models.generate_content(
            model=model_name,
            contents=contents,
            config=types.GenerateContentConfig(
                temperature=0.4,
                response_mime_type="application/json"
            )
        )
        
        resp_text = response.text.strip()
        print(f"  [GemmaVideo] Raw response received ({len(resp_text)} chars)")
        
        if "```" in resp_text:
            resp_text = resp_text.split("```")[1]
            if resp_text.startswith("json"):
                resp_text = resp_text[4:]
        resp_text = resp_text.strip()
        
        import json
        chosen_clips = json.loads(resp_text)
        if isinstance(chosen_clips, list):
            print(f"  [GemmaVideo] Successfully parsed {len(chosen_clips)} clips from Gemma!")
        else:
            print("  [GemmaVideo] Parsed result is not a list.")
            chosen_clips = []
            
    except Exception as e:
        print(f"  [GemmaVideo] Query or JSON parsing failed: {e}")
        chosen_clips = []
    finally:
        if 'uploaded_file' in locals() and uploaded_file:
            try:
                print("  [GemmaVideo] Cleaning up uploaded file from Gemma API storage...")
                client.files.delete(name=uploaded_file.name)
            except Exception as ex:
                print(f"  [GemmaVideo] Cleanup warning: {ex}")

    return chosen_clips
