"""
broll_manager.py — Pexels API B-Roll Search and Downloader (Phase 8)
===================================================================
Handles searching, downloading, and caching of copyright-free stock video clips
from Pexels to serve as B-roll overlays in Clippify final renders.
"""

import os
import re
import requests
from typing import List, Dict, Any, Optional

from dotenv import load_dotenv
load_dotenv()

# Standard trial/free Pexels API key (if user doesn't provide one)
DEFAULT_PEXELS_KEY = os.getenv("PEXELS_API_KEY", "")
# Default Pixabay API Key (a public default key, or user-supplied)
DEFAULT_PIXABAY_KEY = os.getenv("PIXABAY_API_KEY", "")

def search_pexels_videos(keyword: str, pexels_api_key: str = "") -> List[Dict[str, Any]]:
    key = pexels_api_key or DEFAULT_PEXELS_KEY
    if not key:
        return []
    headers = {"Authorization": key}
    search_url = f"https://api.pexels.com/videos/search?query={keyword}&orientation=portrait&per_page=12"
    try:
        resp = requests.get(search_url, headers=headers, timeout=10)
        if resp.status_code == 200:
            data = resp.json()
            results = []
            for video in data.get("videos", []):
                video_files = video.get("video_files", [])
                hd_files = [f for f in video_files if f.get("quality") == "hd"]
                selected_link = hd_files[0]["link"] if hd_files else (video_files[0]["link"] if video_files else "")
                
                results.append({
                    "id": video.get("id"),
                    "url": video.get("url"),
                    "image": video.get("image"),
                    "duration": video.get("duration"),
                    "download_url": selected_link,
                    "width": video.get("width"),
                    "height": video.get("height"),
                    "source": "pexels"
                })
            return results
    except Exception as e:
        print(f"Error searching Pexels: {e}")
    return []

def search_pixabay_videos(keyword: str, pixabay_api_key: str = "") -> List[Dict[str, Any]]:
    key = pixabay_api_key or DEFAULT_PIXABAY_KEY
    if not key:
        return []
    # Pixabay video API endpoint
    search_url = f"https://pixabay.com/api/videos/?key={key}&q={keyword}&orientation=vertical&per_page=12"
    try:
        resp = requests.get(search_url, timeout=10)
        if resp.status_code == 200:
            data = resp.json()
            results = []
            for video in data.get("hits", []):
                videos_data = video.get("videos", {})
                # Try medium or tiny
                selected_video = videos_data.get("medium") or videos_data.get("small") or videos_data.get("tiny") or videos_data.get("large")
                if not selected_video:
                    continue
                selected_link = selected_video.get("url")
                
                # Fetch preview image (Pixabay gives a picture_id to construct thumbnail)
                picture_id = video.get("picture_id", "")
                image_url = f"https://i.vimeocdn.com/video/{picture_id}_295x166.jpg" if picture_id else ""
                
                results.append({
                    "id": video.get("id"),
                    "url": video.get("pageURL"),
                    "image": image_url,
                    "duration": video.get("duration"),
                    "download_url": selected_link,
                    "width": selected_video.get("width"),
                    "height": selected_video.get("height"),
                    "source": "pixabay"
                })
            return results
    except Exception as e:
        print(f"Error searching Pixabay: {e}")
    return []

def clean_filename(name: str) -> str:
    """Sanitize keyword to be used as a safe filename."""
    return re.sub(r'[^a-zA-Z0-9_\-]', '', name.replace(' ', '_')).lower()


def generate_genai_broll(
    keyword: str,
    output_dir: str,
    api_key: str,
) -> Optional[str]:
    """
    Generate a high-quality cinematic image using Google Imagen 3 based on the keyword,
    and convert it to a 4-second MP4 video using FFmpeg with a smooth Ken Burns effect (3D Zoom/Pan).
    """
    if not api_key:
        print("  [GenAI B-Roll] No Gemma API key provided for image generation! Skipping...")
        return None

    import io
    import subprocess
    import imageio_ffmpeg
    from google import genai
    from PIL import Image

    os.makedirs(output_dir, exist_ok=True)
    cache_name = clean_filename(keyword) + "_genai.mp4"
    cache_path = os.path.join(output_dir, cache_name)

    # ── Check Local Cache ─────────────────────────────────────────────────────
    if os.path.exists(cache_path) and os.path.getsize(cache_path) > 1024:
        print(f"  [GenAI B-Roll] Cache hit: using already-generated GenAI B-roll for '{keyword}'")
        return cache_path

    temp_image_path = os.path.join(output_dir, clean_filename(keyword) + "_temp.jpg")
    try:
        print(f"  [GenAI B-Roll] Generating image for '{keyword}' using Google Imagen 3...")
        client = genai.Client(api_key=api_key)
        
        # Photorealistic dramatic cinematic visual prompt formulation
        prompt = f"Cinematic, photorealistic high-quality vertical scene depicting: {keyword}. Rich textures, dramatic lighting, detailed composition, 8k resolution, suitable for a documentary overlay."
        
        response = client.models.generate_images(
            model='imagen-3.0-generate-002',
            prompt=prompt,
            config=dict(
                number_of_images=1,
                output_mime_type="image/jpeg",
                aspect_ratio="9:16"
            )
        )
        
        if not response.generated_images:
            print(f"  [GenAI B-Roll] Imagen 3 returned no images for '{keyword}'")
            return None
            
        generated_image = response.generated_images[0]
        image = Image.open(io.BytesIO(generated_image.image.image_bytes))
        image.save(temp_image_path, "JPEG")
        print(f"  [GenAI B-Roll] Temp image saved successfully to {temp_image_path}")

        # Render 4s video with smooth Ken Burns zoompan using scaled-up resolution to prevent pixel jittering
        ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()
        cmd = [
            ffmpeg_exe, "-y",
            "-loop", "1",
            "-i", temp_image_path,
            "-vf", "scale=2160x3840,zoompan=z='min(zoom+0.0006\\,1.15)':x='iw/2-(iw/zoom)/2':y='ih/2-(ih/zoom)/2':d=100:s=1080x1920",
            "-c:v", "libx264",
            "-t", "4",
            "-pix_fmt", "yuv420p",
            cache_path
        ]
        
        print(f"  [GenAI B-Roll] Rendering 4s Ken Burns MP4 video via FFmpeg...")
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if os.path.exists(temp_image_path):
            try:
                os.remove(temp_image_path)
            except Exception as e:
                print(f"  [GenAI B-Roll] Failed to clean up temp image {temp_image_path}: {e}")
                
        if res.returncode == 0 and os.path.exists(cache_path) and os.path.getsize(cache_path) > 1024:
            print(f"  [GenAI B-Roll] GenAI B-Roll generated successfully! Saved to {cache_path} ({os.path.getsize(cache_path)/(1024*1024):.2f} MB)")
            return cache_path
        else:
            print(f"  [GenAI B-Roll] FFmpeg failed with exit code {res.returncode}. Stderr: {res.stderr}")
            return None

    except Exception as e:
        print(f"  [GenAI B-Roll] Exception occurred during GenAI B-roll generation for '{keyword}': {e}")
        if os.path.exists(temp_image_path):
            try:
                os.remove(temp_image_path)
            except OSError:
                pass
        return None


def download_pexels_broll(
    keyword: str,
    output_dir: str,
    pexels_api_key: str = "",
    gemma_api_key: str = "",
    pixabay_api_key: str = "",
) -> Optional[str]:
    """
    Search Pexels API for a vertical video matching the keyword, download it,
    and save it in output_dir. Returns the local file path of the downloaded video,
    or None on failure/no match.
    
    Implements a local caching mechanism so the same keyword isn't downloaded twice.
    Falls back to Pixabay search and then Google Imagen 3 GenAI image generation + Ken Burns video synthesis 
    if Pexels search fails or is unavailable.
    """
    pexels_key = pexels_api_key or DEFAULT_PEXELS_KEY
    pixabay_key = pixabay_api_key or DEFAULT_PIXABAY_KEY
    os.makedirs(output_dir, exist_ok=True)
    
    # ── Check Local Cache (Pexels / Pixabay / GenAI) ──────────────────────────
    cache_path = None
    for f in os.listdir(output_dir):
        if f.startswith(clean_filename(keyword) + "_") and f.endswith(".mp4") and not f.endswith("_genai.mp4") and not f.endswith("_temp.mp4"):
            potential_path = os.path.join(output_dir, f)
            if os.path.getsize(potential_path) > 1024:
                cache_path = potential_path
                break
                
    if cache_path:
        print(f"  [B-Roll] Cache hit: using already-downloaded B-roll for '{keyword}' ({os.path.basename(cache_path)})")
        return cache_path

    genai_cache_name = clean_filename(keyword) + "_genai.mp4"
    genai_cache_path = os.path.join(output_dir, genai_cache_name)
    if os.path.exists(genai_cache_path) and os.path.getsize(genai_cache_path) > 1024:
        print(f"  [B-Roll] Cache hit: using already-generated GenAI B-roll for '{keyword}'")
        return genai_cache_path

    # ── Query Pexels API ──────────────────────────────────────────────────────
    if pexels_key:
        print(f"  [B-Roll] Searching Pexels for keyword: '{keyword}'...")
        headers = {"Authorization": pexels_key}
        search_url = f"https://api.pexels.com/videos/search?query={keyword}&orientation=portrait&per_page=3"
        
        try:
            resp = requests.get(search_url, headers=headers, timeout=15)
            if resp.status_code == 200:
                data = resp.json()
                videos = data.get("videos", [])
                if not videos:
                    print(f"  [B-Roll] No portrait video found for '{keyword}', trying general orientation...")
                    search_url_any = f"https://api.pexels.com/videos/search?query={keyword}&per_page=3"
                    resp = requests.get(search_url_any, headers=headers, timeout=15)
                    if resp.status_code == 200:
                        videos = resp.json().get("videos", [])
                        
                if videos:
                    video = videos[0]
                    video_files = video.get("video_files", [])
                    selected_file = None
                    portrait_files = [f for f in video_files if f.get("width", 1920) < f.get("height", 1080)]
                    
                    if portrait_files:
                        hd_portraits = [f for f in portrait_files if f.get("quality") == "hd"]
                        selected_file = hd_portraits[0] if hd_portraits else portrait_files[0]
                    elif video_files:
                        hd_files = [f for f in video_files if f.get("quality") == "hd"]
                        selected_file = hd_files[0] if hd_files else video_files[0]
            
                    if selected_file:
                        download_url = selected_file["link"]
                        video_id = video.get("id", "unknown")
                        dest_cache_name = f"{clean_filename(keyword)}_{video_id}.mp4"
                        dest_cache_path = os.path.join(output_dir, dest_cache_name)
                        print(f"  [B-Roll] Found Pexels video (ID={video_id}). Downloading to {dest_cache_path}...")
                        v_resp = requests.get(download_url, stream=True, timeout=30)
                        if v_resp.status_code == 200:
                            with open(dest_cache_path, "wb") as f:
                                for chunk in v_resp.iter_content(chunk_size=1024 * 1024):
                                    if chunk:
                                        f.write(chunk)
                            print(f"  [B-Roll] Pexels B-roll downloaded successfully: {dest_cache_path}")
                            return dest_cache_path
            else:
                print(f"  [B-Roll] Pexels API returned error status {resp.status_code}")
        except Exception as e:
            print(f"  [B-Roll] Exception occurred during Pexels B-roll fetch for '{keyword}': {e}")

    # ── Fallback to Pixabay API ───────────────────────────────────────────────
    if pixabay_key:
        print(f"  [B-Roll] Pexels failed. Searching Pixabay for keyword: '{keyword}'...")
        try:
            pixabay_results = search_pixabay_videos(keyword, pixabay_key)
            if pixabay_results:
                best_video = pixabay_results[0]
                download_url = best_video["download_url"]
                if download_url:
                    video_id = best_video.get("id", "unknown")
                    dest_cache_name = f"{clean_filename(keyword)}_{video_id}.mp4"
                    dest_cache_path = os.path.join(output_dir, dest_cache_name)
                    print(f"  [B-Roll] Found Pixabay video (ID={video_id}). Downloading to {dest_cache_path}...")
                    v_resp = requests.get(download_url, stream=True, timeout=30)
                    if v_resp.status_code == 200:
                        with open(dest_cache_path, "wb") as f:
                            for chunk in v_resp.iter_content(chunk_size=1024 * 1024):
                                if chunk:
                                    f.write(chunk)
                        print(f"  [B-Roll] Pixabay B-roll downloaded successfully: {dest_cache_path}")
                        return dest_cache_path
        except Exception as e:
            print(f"  [B-Roll] Exception occurred during Pixabay B-roll fetch for '{keyword}': {e}")

    # ── Fallback to Google Imagen 3 GenAI B-Roll ──────────────────────────────
    if gemma_api_key:
        print(f"  [B-Roll] Falling back to GenAI B-Roll generation for keyword: '{keyword}'...")
        genai_path = generate_genai_broll(keyword, output_dir, gemma_api_key)
        if genai_path:
            return genai_path

    print(f"  [B-Roll] Failed to obtain B-roll for '{keyword}' (Pexels & Pixabay failed, no GenAI API key or GenAI failed)")
    return None
