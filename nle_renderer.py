"""
nle_renderer.py — The Complex Render Engine for ClipAI NLE
Translates the JSON TimelineState into a single massive FFmpeg `filter_complex` command.
"""

import os
import subprocess
import copy
from typing import Dict, Any, List
import imageio_ffmpeg
from keyframe_engine import generate_ffmpeg_expression
from editor import generate_ass_file
import shutil
import shutil

def build_ffmpeg_filter_complex(timeline: Dict[str, Any], output_path: str) -> List[str]:
    """
    Parses TimelineState JSON and generates a single FFmpeg command list.
    """
    timeline = copy.deepcopy(timeline)
    settings = timeline.get("settings", {})
    TARGET_W = settings.get("width", 1080)
    TARGET_H = settings.get("height", 1920)
    
    tracks = timeline.get("tracks", {})
    video_tracks = tracks.get("video", [])
    audio_tracks = tracks.get("audio", [])
    subtitle_tracks = tracks.get("subtitles", [])
    
    # Generate ASS subtitles if present
    ass_path = None
    if subtitle_tracks and subtitle_tracks[0].get("clips"):
        ass_path = output_path.replace(".mp4", "_subs.ass")
        generate_ass_file(subtitle_tracks[0].get("clips"), ass_path)

    subtitles_applied = False
    
    # Find the maximum end_time_in_timeline to know the video length
    max_time = 0.0
    for track in video_tracks + audio_tracks:
        for clip in track.get("clips", []):
            end_t = clip.get("end_time_in_timeline", 0)
            if end_t > max_time:
                max_time = end_t
                
    if max_time == 0.0:
        max_time = 10.0 # Default 10 seconds if empty
        
    # 1. Collect inputs
    inputs = []
    input_to_idx = {}
    
    for track in video_tracks + audio_tracks:
        for clip in track.get("clips", []):
            path = clip.get("source_path")
            
            # Pre-process background removal if needed
            ai = clip.get("ai_features", {})
            if ai.get("bg_removed") and ai.get("bg_remove_method") in ["rmbg", "ai"]:
                from bg_remover import create_greenscreen_video
                cache_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cache")
                os.makedirs(cache_dir, exist_ok=True)
                base_name = os.path.basename(path).split('.')[0]
                trim_start = clip.get("source_trim_start", 0)
                trim_end = clip.get("source_trim_end", 0)
                duration = trim_end - trim_start if trim_end > trim_start else clip.get("end_time_in_timeline", 5)
                
                # Create a unique cache filename based on trim
                green_path = os.path.join(cache_dir, f"{base_name}_green_{trim_start:.1f}_{duration:.1f}.mp4")
                if not os.path.exists(green_path):
                    print(f"  [NLE_RENDERER] Generating AI Green Screen for {base_name}...")
                    create_greenscreen_video(path, green_path, trim_start, trim_end)
                
                # Swap the clip path to the greenscreen version and update trim (since the cached video is already trimmed)
                path = green_path
                clip["source_path"] = green_path
                clip["source_trim_start"] = 0
                clip["source_trim_end"] = duration
                
                # Switch method so FFmpeg uses chromakey
                ai["bg_remove_method"] = "chromakey"
                ai["chromakey_color"] = "#00FF00"
                clip["ai_features"] = ai
                
            if path and path not in input_to_idx:
                if not os.path.exists(path):
                    print(f"  [WARN] Source file not found: {path}")
                    continue
                input_to_idx[path] = len(inputs)
                inputs.append(path)
                
    if not inputs:
        raise ValueError("No valid inputs found in the timeline.")
        
    cmd_base = ["ffmpeg", "-y"]
    for path in inputs:
        cmd_base.extend(["-i", path])
        
    filter_complex = []
    
    # 2. Create Base Canvas
    # We create a black background that lasts exactly max_time seconds
    filter_complex.append(f"color=c=black:s={TARGET_W}x{TARGET_H}:d={max_time}[base_canvas]")
    
    current_canvas = "base_canvas"
    
    # Process Video Tracks (Bottom to Top)
    # Reversing track order if we assume lower index = lower layer
    for t_idx, track in enumerate(reversed(video_tracks)):
        for c_idx, clip in enumerate(track.get("clips", [])):
            path = clip.get("source_path")
            if path not in input_to_idx:
                continue
                
            in_idx = input_to_idx[path]
            
            trim_start = clip.get("source_trim_start", 0)
            trim_end = clip.get("source_trim_end", 0)
            if trim_end <= trim_start:
                continue
                
            duration = trim_end - trim_start
            start_tl = clip.get("start_time_in_timeline", 0)
            end_tl = clip.get("end_time_in_timeline", start_tl + duration)
            
            clip_lbl = f"[v_t{t_idx}_c{c_idx}]"
            
            filters = [f"[{in_idx}:v]trim=start={trim_start}:duration={duration},setpts=PTS-STARTPTS"]
            
            # Apply Color Grading
            cg = clip.get("color_grading", {})
            if cg:
                brightness = cg.get("brightness", 0)
                contrast = cg.get("contrast", 1.0)
                saturation = cg.get("saturation", 1.0)
                filters.append(f"eq=brightness={brightness}:contrast={contrast}:saturation={saturation}")
                
            # Apply Scale/Transform
            transform = clip.get("transform", {})
            scale_x = transform.get("scale", {}).get("x", 100) / 100.0
            scale_y = transform.get("scale", {}).get("y", 100) / 100.0
            
            # Avoid scaling to 0 which crashes ffmpeg
            new_w = max(2, int(TARGET_W * scale_x))
            new_h = max(2, int(TARGET_H * scale_y))
            filters.append(f"scale={new_w}:{new_h}")
            
            # Apply AI Chroma Key
            ai = clip.get("ai_features", {})
            if ai.get("bg_removed") and ai.get("bg_remove_method") == "chromakey":
                # TEXT BEHIND OBJECTS: Apply subtitles right before overlaying the chroma-keyed foreground!
                if not subtitles_applied and ass_path:
                    ass_path_unix = ass_path.replace("\\", "/").replace(":", "\\:")
                    next_canvas_sub = f"[canvas_sub_t{t_idx}_c{c_idx}]"
                    filter_complex.append(f"[{current_canvas}]ass='{ass_path_unix}'{next_canvas_sub}")
                    current_canvas = next_canvas_sub.strip("[]")
                    subtitles_applied = True
                    
                color = ai.get("chromakey_color", "#00FF00").replace("#", "0x")
                filters.append(f"colorkey={color}:0.1:0.1")
            
            filter_complex.append(",".join(filters) + clip_lbl)
            
            # Overlay onto canvas
            next_canvas = f"[canvas_t{t_idx}_c{c_idx}]"
            
            keyframes = transform.get("keyframes", [])
            pos_x_base = transform.get("position", {}).get("x", 0)
            pos_y_base = transform.get("position", {}).get("y", 0)
            
            # If we have position keyframes, generate dynamic math expressions
            if keyframes and any(k.get("property") == "position" for k in keyframes):
                # Ensure the time in keyframes is adjusted relative to start_tl
                adjusted_keyframes = []
                for kf in keyframes:
                    if kf.get("property") == "position":
                        akf = kf.copy()
                        # FFmpeg 't' in overlay is the global timeline time. 
                        # The tracking keyframes usually start from 0 for the clip duration.
                        akf["time"] = kf["time"] + start_tl
                        adjusted_keyframes.append(akf)
                        
                expr_x = generate_ffmpeg_expression(adjusted_keyframes, "position", pos_x_base, "x")
                expr_y = generate_ffmpeg_expression(adjusted_keyframes, "position", pos_y_base, "y")
                pos_x = expr_x
                pos_y = expr_y
            else:
                pos_x = str(pos_x_base)
                pos_y = str(pos_y_base)
            
            # Offset pos_x and pos_y to center the scaled image (NLEs usually position relative to center)
            # For simplicity here, we assume top-left positioning if relative, or center. 
            # We'll stick to exact coordinates requested.
            
            overlay_filter = f"[{current_canvas}]{clip_lbl}overlay=x='{pos_x}':y='{pos_y}':enable='between(t,{start_tl},{end_tl})'{next_canvas}"
            filter_complex.append(overlay_filter)
            
            current_canvas = next_canvas.strip("[]")
            
    # If subtitles were not applied (no BG removed object found), apply them on top now
    if not subtitles_applied and ass_path:
        ass_path_unix = ass_path.replace("\\", "/").replace(":", "\\:")
        next_canvas_sub = "[canvas_sub_final]"
        filter_complex.append(f"[{current_canvas}]ass='{ass_path_unix}'{next_canvas_sub}")
        current_canvas = next_canvas_sub.strip("[]")
        
    v_final = f"[{current_canvas}]"
    
    # 3. Process Audio Tracks
    a_voice_outputs = []
    
    # 3a. Extract audio from Video Tracks (Voice)
    for t_idx, track in enumerate(video_tracks):
        for c_idx, clip in enumerate(track.get("clips", [])):
            path = clip.get("source_path")
            if path not in input_to_idx: continue
            in_idx = input_to_idx[path]
            trim_start = clip.get("source_trim_start", 0)
            trim_end = clip.get("source_trim_end", 0)
            if trim_end <= trim_start: continue
            duration = trim_end - trim_start
            start_tl = clip.get("start_time_in_timeline", 0)
            vol = clip.get("volume", 1.0)
            if vol == 0: continue
            clip_lbl = f"[a_v_t{t_idx}_c{c_idx}]"
            delay_ms = int(start_tl * 1000)
            filters = [f"[{in_idx}:a]atrim=start={trim_start}:duration={duration}", "asetpts=PTS-STARTPTS", f"volume={vol}", f"adelay={delay_ms}|{delay_ms}"]
            filter_complex.append(",".join(filters) + clip_lbl)
            a_voice_outputs.append(clip_lbl)

    a_music_outputs = []
    # 3b. Extract audio from Audio Tracks (Track 0 is usually Voice too, Track 1+ is Music)
    for t_idx, track in enumerate(audio_tracks):
        for c_idx, clip in enumerate(track.get("clips", [])):
            path = clip.get("source_path")
            if path not in input_to_idx: continue
            in_idx = input_to_idx[path]
            trim_start = clip.get("source_trim_start", 0)
            trim_end = clip.get("source_trim_end", 0)
            if trim_end <= trim_start: continue
            duration = trim_end - trim_start
            start_tl = clip.get("start_time_in_timeline", 0)
            vol = clip.get("volume", 1.0)
            if vol == 0: continue
            clip_lbl = f"[a_a_t{t_idx}_c{c_idx}]"
            delay_ms = int(start_tl * 1000)
            filters = [f"[{in_idx}:a]atrim=start={trim_start}:duration={duration}", "asetpts=PTS-STARTPTS", f"volume={vol}", f"adelay={delay_ms}|{delay_ms}"]
            filter_complex.append(",".join(filters) + clip_lbl)
            
            if t_idx == 0:
                a_voice_outputs.append(clip_lbl)
            else:
                a_music_outputs.append(clip_lbl)
            
    a_final = "[a_final]"
    
    # Mix voices
    lbl_voice_mix = "[a_voice_mix]"
    if a_voice_outputs:
        if len(a_voice_outputs) > 1:
            filter_complex.append(f"{''.join(a_voice_outputs)}amix=inputs={len(a_voice_outputs)}:duration=longest{lbl_voice_mix}")
        else:
            filter_complex.append(f"{a_voice_outputs[0]}acopy{lbl_voice_mix}")
    else:
        filter_complex.append(f"anullsrc=r=44100:cl=stereo:d={max_time}{lbl_voice_mix}")

    # Mix music
    lbl_music_mix = "[a_music_mix]"
    if a_music_outputs:
        if len(a_music_outputs) > 1:
            filter_complex.append(f"{''.join(a_music_outputs)}amix=inputs={len(a_music_outputs)}:duration=longest{lbl_music_mix}")
        else:
            filter_complex.append(f"{a_music_outputs[0]}acopy{lbl_music_mix}")
            
        # SMART DUCKING: Sidechain compress music against voice
        lbl_voice_split1 = "[a_v_main]"
        lbl_voice_split2 = "[a_v_side]"
        filter_complex.append(f"{lbl_voice_mix}asplit=2{lbl_voice_split1}{lbl_voice_split2}")
        
        lbl_music_ducked = "[a_music_ducked]"
        # Lower music when voice is present
        filter_complex.append(f"{lbl_music_mix}{lbl_voice_split2}sidechaincompress=threshold=0.08:ratio=4:attack=200:release=500{lbl_music_ducked}")
        
        # Mix them back
        filter_complex.append(f"{lbl_voice_split1}{lbl_music_ducked}amix=inputs=2:duration=first{a_final}")
    else:
        filter_complex.append(f"{lbl_voice_mix}acopy{a_final}")

    filter_complex_str = ";".join(filter_complex)
    
    # Replace standard ffmpeg with the bundled one
    ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()
    cmd_base[0] = ffmpeg_exe
    
    cmd_base.extend([
        "-filter_complex", filter_complex_str,
        "-map", v_final,
        "-map", a_final,
        "-t", str(max_time), # Cut exactly at the maximum clip time
        "-c:v", "libx264",
        "-preset", "fast",
        "-pix_fmt", "yuv420p",
        "-color_primaries", "bt709",
        "-color_trc", "bt709",
        "-colorspace", "bt709",
        "-c:a", "aac",
        "-b:a", "128k",
        output_path
    ])
    
    return cmd_base

def render_timeline(timeline: Dict[str, Any], output_path: str):
    """
    Executes the FFmpeg command generated from the NLE TimelineState.
    """
    cmd = build_ffmpeg_filter_complex(timeline, output_path)
    
    print("  [NLE_RENDERER] Starting FFmpeg render...")
    
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    
    # We can read stderr for progress if needed
    _, err = process.communicate()
    
    if process.returncode != 0:
        print(f"  [NLE_RENDERER] FFmpeg render failed:\n{err}")
        raise RuntimeError("FFmpeg render failed. Check console for details.")
    
    print("  [NLE_RENDERER] Render completed successfully!")
    return output_path
