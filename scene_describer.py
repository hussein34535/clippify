"""
scene_describer.py — Video-to-Text Scene Captioning for Clippify
=============================================================
This module converts visual scenes (video frames) into descriptive text captions.
The descriptive text can then be passed to the LLM (Gemma/Gemma) alongside the
audio transcript, giving the AI a complete visual and audio understanding of the video.

Supports:
  1. Offline Local Mode: Uses Salesforce BLIP Image Captioning via Hugging Face `transformers`
     and PyTorch. Runs 100% locally and free.
  2. Online Low-Res Mode: Compresses frames into micro JPEGs and describes them via Gemma API
     without uploading massive video files (instantaneous, high accuracy).
"""

import os
import time
import tempfile
import cv2
import numpy as np
from PIL import Image
from typing import List, Dict, Any, Optional

# Global cache for local BLIP model to avoid reloading on every segment
_LOCAL_PROCESSOR = None
_LOCAL_MODEL = None


def _load_local_blip():
    """Lazily load the Salesforce BLIP model for local offline image captioning."""
    global _LOCAL_PROCESSOR, _LOCAL_MODEL
    if _LOCAL_MODEL is None or _LOCAL_PROCESSOR is None:
        print("  [SceneDescriber] Loading local BLIP model (Salesforce/blip-image-captioning-base)...")
        try:
            from transformers import BlipProcessor, BlipForConditionalGeneration  # type: ignore
            import torch  # type: ignore
            
            # Select GPU if available, else CPU
            device = "cuda" if torch.cuda.is_available() else "cpu"
            print(f"  [SceneDescriber] Using device: {device}")
            
            _LOCAL_PROCESSOR = BlipProcessor.from_pretrained("Salesforce/blip-image-captioning-base")
            _LOCAL_MODEL = BlipForConditionalGeneration.from_pretrained(
                "Salesforce/blip-image-captioning-base"
            ).to(device)
            print("  [SceneDescriber] Local BLIP model loaded successfully!")
        except ImportError:
            print("  [SceneDescriber] Dependencies missing! Please run: pip install transformers torch torchvision")
            raise ImportError("Hugging Face transformers and torch must be installed for local mode.")
    return _LOCAL_PROCESSOR, _LOCAL_MODEL


def _get_local_caption(pil_image: Image.Image) -> str:
    """Generate text description for a PIL Image using the local BLIP model."""
    try:
        import torch  # type: ignore
        processor, model = _load_local_blip()
        device = next(model.parameters()).device
        
        # Prepare inputs
        inputs = processor(images=pil_image, return_tensors="pt").to(device)
        
        # Generate caption
        with torch.no_grad():
            outputs = model.generate(**inputs, max_new_tokens=40)
            
        caption = processor.decode(outputs[0], skip_special_tokens=True)
        return caption.strip()
    except Exception as e:
        print(f"  [SceneDescriber] Local BLIP generation failed: {e}")
        return "a video scene"


def _get_gemma_captions_batched(pil_images: List[Image.Image], api_key: str) -> List[str]:
    """Get brief text descriptions for a batch of images using Gemma in ONE single request to bypass Rate Limits."""
    try:
        from google import genai
        from google.genai import types
        import json
        
        client = genai.Client(api_key=api_key)
        
        image_parts = []
        temp_paths = []
        
        for pil_image in pil_images:
            temp_jpeg = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False)
            temp_jpeg_path = temp_jpeg.name
            temp_jpeg.close()
            temp_paths.append(temp_jpeg_path)
            
            # Resize to max 320px width/height and compress
            pil_image.thumbnail((320, 240))
            pil_image.save(temp_jpeg_path, "JPEG", quality=60)
            
            with open(temp_jpeg_path, "rb") as f:
                img_data = f.read()
                
            image_parts.append(
                types.Part.from_bytes(
                    data=img_data,
                    mime_type="image/jpeg"
                )
            )
            
        prompt = f"Here are {len(pil_images)} chronological frames from a video scene. Describe what is happening in each frame in one short, clear sentence. Focus on actors, expressions, setting, and movement. Return ONLY a valid JSON array of {len(pil_images)} strings. No markdown, no backticks."
        contents = [prompt] + image_parts
        
        try:
            # Retry loop with exponential backoff for rate-limiting
            retries = 3
            backoff = 2.0
            for attempt in range(retries):
                try:
                    models_to_try = ["gemma-2-27b-it", "gemini-1.5-flash", "gemini-2.5-flash"]
                    response = None
                    last_err = None
                    for model in models_to_try:
                        try:
                            print(f"  [SceneDescriber] Trying model {model}...")
                            response = client.models.generate_content(
                                model=model,
                                contents=contents,
                                config=types.GenerateContentConfig(
                                    temperature=0.2,
                                    max_output_tokens=800
                                )
                            )
                            break
                        except Exception as e:
                            last_err = e
                            print(f"  [SceneDescriber] Model {model} failed: {e}")
                            
                    if response is None:
                        raise Exception(f"All models failed for scene description. Last error: {last_err}")
                    
                    res_text = response.text.strip()
                    # Clean up markdown blocks if present
                    import re
                    res_text = re.sub(r'```(?:json)?', '', res_text).strip()
                    if res_text.endswith('```'):
                        res_text = res_text[:-3].strip()
                            
                    try:
                        res_json = json.loads(res_text)
                    except json.JSONDecodeError as je:
                        # Attempt to salvage truncated JSON
                        if not res_text.endswith(']'):
                            if res_text.endswith('"'):
                                res_text += ']'
                            else:
                                res_text += '"]'
                        try:
                            res_json = json.loads(res_text)
                        except Exception:
                            raise je
                            
                    if isinstance(res_json, list):
                        if len(res_json) < len(pil_images):
                            res_json.extend(["a video scene"] * (len(pil_images) - len(res_json)))
                        elif len(res_json) > len(pil_images):
                            res_json = res_json[:len(pil_images)]
                        return res_json
                    else:
                        raise ValueError(f"Gemma returned invalid type: {res_text}")
                        
                except Exception as e:
                    err_str = str(e).lower()
                    if "429" in err_str or "exhausted" in err_str or "rate" in err_str:
                        if attempt < retries - 1:
                            print(f"  [SceneDescriber] Gemma rate limit hit (429). Retrying in {backoff}s... (Attempt {attempt+1}/{retries})")
                            time.sleep(backoff)
                            backoff *= 2.0
                        else:
                            raise e
                    else:
                        raise e
        finally:
            for path in temp_paths:
                if os.path.exists(path):
                    os.remove(path)
    except Exception as e:
        print(f"  [SceneDescriber] Batched Gemma visual description failed: {e}")
        return ["a video scene"] * len(pil_images)


def describe_video_segment(
    video_path: str,
    start_sec: float,
    end_sec: float,
    n_frames: int = 4,
    use_local: bool = True,
    api_key: Optional[str] = None
) -> List[Dict[str, Any]]:
    """
    Extract keyframes from a video segment and convert them into text scene descriptions (Scene-to-Text).
    
    Args:
        video_path: Path to the video file.
        start_sec: Start time of the segment in seconds.
        end_sec: End time of the segment in seconds.
        n_frames: Number of keyframes to extract and describe.
        use_local: If True, uses local BLIP model (offline). Otherwise uses Gemma API (online).
        api_key: Gemma API Key (required if use_local=False).
        
    Returns:
        A list of dictionaries containing time offset and text description.
    """
    results = []
    duration = end_sec - start_sec
    if duration <= 0:
        return results

    # 1. Extract sample frames using OpenCV
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"  [SceneDescriber] Could not open video: {video_path}")
        return results

    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0:
        fps = 30.0

    sample_interval = duration / n_frames
    sample_frames = []

    try:
        for i in range(n_frames):
            rel_t = i * sample_interval + (sample_interval / 2)
            abs_t = start_sec + rel_t
            
            # Fast seek by frame index
            frame_idx = int(abs_t * fps)
            cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
            ret, frame = cap.read()
            
            if ret and frame is not None:
                # Convert BGR (OpenCV) to RGB
                frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                pil_img = Image.fromarray(frame_rgb)
                sample_frames.append((abs_t, pil_img))
    except Exception as e:
        print(f"  [SceneDescriber] Frame extraction failed: {e}")
    finally:
        cap.release()

    if not sample_frames:
        return results

    # 2. Describe each frame
    print(f"  [SceneDescriber] Describing {len(sample_frames)} scenes (mode={'local' if use_local else 'online'})...")
    
    if use_local:
        try:
            _load_local_blip()
        except ImportError:
            print("  [SceneDescriber] Local BLIP imports failed, falling back to online Gemma...")
            use_local = False
            # CRITICAL FIX: If falling back to online API, prevent 429 quota exhaustion
            # by capping the maximum frames to 8 (Free tier allows ~15 RPM).
            if len(sample_frames) > 8:
                print(f"  [SceneDescriber] Downsampling {len(sample_frames)} frames to 8 to protect Gemma API quota...")
                import numpy as np
                indices = np.linspace(0, len(sample_frames) - 1, 8, dtype=int)
                sample_frames = [sample_frames[i] for i in indices]

    t0 = time.time()
    
    if use_local or not api_key:
        for idx, (abs_t, pil_img) in enumerate(sample_frames):
            if use_local:
                desc = _get_local_caption(pil_img)
            else:
                print("  [SceneDescriber] Gemma API Key is missing for online mode! Skipping.")
                desc = "a video scene"
            
            results.append({
                "timestamp_sec": round(abs_t, 2),
                "description": desc
            })
            print(f"    -> [{abs_t:.1f}s]: {desc}")
    else:
        # Online Batched Mode (Blazing Fast)
        print(f"  [SceneDescriber] Sending batched request of {len(sample_frames)} frames to Gemma...")
        pil_images = [img for _, img in sample_frames]
        batched_descs = _get_gemma_captions_batched(pil_images, api_key)
        
        for idx, (abs_t, pil_img) in enumerate(sample_frames):
            desc = batched_descs[idx] if idx < len(batched_descs) else "a video scene"
            results.append({
                "timestamp_sec": round(abs_t, 2),
                "description": desc
            })
            print(f"    -> [{abs_t:.1f}s]: {desc}")
        
    elapsed = time.time() - t0
    print(f"  [SceneDescriber] Scene captioning completed in {elapsed:.2f} seconds!")
    return results
