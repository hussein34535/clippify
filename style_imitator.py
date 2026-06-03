"""
style_imitator.py - Smart Style Mimicry & Rendering Engine for ClipAI
===================================================================
Applies reference JSON profiles to target videos, syncing cuts,
typography, music ducking, and transitions locally.
"""

import os
import sys
import json
import logging
import subprocess
from typing import Dict, Any, List, Tuple

logging.basicConfig(level=logging.INFO, format="[%(asctime)s] %(levelname)s: %(message)s")

class StyleImitator:
    def __init__(self, target_video_path: str, profile_path: str):
        self.target_path = target_video_path
        self.profile_path = profile_path
        
        if not os.path.exists(target_video_path):
            raise FileNotFoundError(f"Target video file not found at: {target_video_path}")
        if not os.path.exists(profile_path):
            raise FileNotFoundError(f"Style profile JSON not found at: {profile_path}")
            
        with open(profile_path, "r", encoding="utf-8") as f:
            self.profile = json.load(f)
            
        logging.info(f"Initialized StyleImitator. Target: {target_video_path}, Profile: {profile_path}")

    def generate_ass_subtitles(self, words: List[Dict[str, Any]], subtitle_path: str, screen_w: int, screen_h: int):
        """
        Compiles ASS subtitle files mimicking typography extracted from the reference video.
        Uses advanced tags to render pop-up scale transitions.
        """
        logging.info(f"Compiling ASS subtitles to: {subtitle_path}")
        sub_style = self.profile.get("typography", {}).get("subtitles", {})
        
        font_size = int(screen_h * sub_style.get("font_size_ratio", 0.07))
        # Convert hex '#RRGGBB' to ASS style BGR hex '&H00BBGGRR&'
        fill_hex = sub_style.get("fill_color", "#FFFFFF").replace("#", "")
        if len(fill_hex) == 6:
            ass_primary = f"&H00{fill_hex[4:6]}{fill_hex[2:4]}{fill_hex[0:2]}&"
        else:
            ass_primary = "&H00FFFFFF&"
            
        # Stroke/Outline color
        stroke_hex = sub_style.get("stroke_color", "#000000").replace("#", "")
        if len(stroke_hex) == 6:
            ass_outline = f"&H00{stroke_hex[4:6]}{stroke_hex[2:4]}{stroke_hex[0:2]}&"
        else:
            ass_outline = "&H00000000&"
            
        stroke_width = sub_style.get("stroke_width", 3.0)
        has_shadow = sub_style.get("has_shadow", True)
        shadow_val = 1.5 if has_shadow else 0.0
        
        # Calculate Y alignment margin (ASS counts from bottom)
        margin_v = int(screen_h * (1.0 - sub_style.get("position_y_ratio", 0.83)))
        
        # Write ASS File header
        header = f"""[Script Info]
Title: Style Mimic subtitles
ScriptType: v4.00+
WrapStyle: 0
PlayResX: {screen_w}
PlayResY: {screen_h}

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,{font_size},{ass_primary},&H0000FFFF&,{ass_outline},&H00000000&,1,0,0,0,100,100,0,0,1,{stroke_width},{shadow_val},2,10,10,{margin_v},1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
        
        def format_time(sec: float) -> str:
            h = int(sec // 3600)
            m = int((sec % 3600) // 60)
            s = int(sec % 60)
            ms = int((sec % 1) * 100)
            return f"{h}:{m:02d}:{s:02d}.{ms:02d}"

        events = []
        # Group words into blocks of max 3 words or 1.5 seconds gap
        current_block = []
        
        for idx, w in enumerate(words):
            current_block.append(w)
            is_last = (idx == len(words) - 1)
            time_gap = 0.0
            if not is_last:
                time_gap = words[idx+1]["start"] - w["end"]
                
            if len(current_block) >= 3 or time_gap > 0.4 or is_last:
                start_t = format_time(current_block[0]["start"])
                end_t = format_time(current_block[-1]["end"])
                
                text_parts = []
                for word_idx, bw in enumerate(current_block):
                    clean_txt = bw["text"].strip()
                    # Apply a brief scale pop animation to the word
                    text_parts.append(f"{{\\t(0, 60, \\fscx112\\fscy112)}}{{\\t(60, 150, \\fscx100\\fscy100)}}{clean_txt}")
                    
                full_text = " ".join(text_parts)
                events.append(f"Dialogue: 0,{start_t},{end_t},Default,,0,0,0,,{full_text}")
                current_block = []
                
        with open(subtitle_path, "w", encoding="utf-8") as f:
            f.write(header)
            f.write("\n".join(events))
            
        logging.info("ASS Subtitle generation complete.")

    def compile_ffmpeg_filters(self, cuts: List[Tuple[float, float]], zoom_events: List[Dict[str, Any]], ass_sub_path: str, output_path: str) -> List[str]:
        """
        Compiles a complete FFMPEG complex filtergraph CLI command string.
        """
        logging.info("Compiling FFMPEG render command...")
        
        # Absolute path cleanups for ffmpeg
        clean_sub_path = ass_sub_path.replace("\\", "/").replace(":", "\\:")
        
        filter_parts = []
        video_links = []
        
        # Get target video dimensions for scaling
        import cv2
        cap = cv2.VideoCapture(self.target_path)
        w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)) or 1080
        h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)) or 1920
        cap.release()
        
        for idx, (start, end) in enumerate(cuts):
            # Check if this clip segment contains a zoom punch event
            has_zoom = False
            for z in zoom_events:
                if start <= z["start_sec"] <= end:
                    has_zoom = True
                    break
            
            # Video trim filters
            filter_parts.append(f"[0:v]trim=start={start:.3f}:end={end:.3f},setpts=PTS-STARTPTS[v{idx}]")
            
            if has_zoom:
                # Apply digital crop to zoom
                filter_parts.append(f"[v{idx}]crop=w=in_w/1.2:h=in_h/1.2:x=(in_w-out_w)/2:y=(in_h-out_h)/2,scale=w={w}:h={h}[v{idx}_z]")
                video_links.append(f"[v{idx}_z]")
            else:
                filter_parts.append(f"[v{idx}]scale=w={w}:h={h}[v{idx}_s]")
                video_links.append(f"[v{idx}_s]")
                
        # Concat video parts
        n_clips = len(cuts)
        concat_videos = "".join(video_links)
        filter_parts.append(f"{concat_videos}concat=n={n_clips}:v=1:a=0[v_concat]")
        
        # Apply Subtitles filter and color correction adjustments
        col = self.profile.get("visual_effects", {}).get("color_grade", {})
        contrast = col.get("contrast_multiplier", 1.05)
        saturation = col.get("saturation_multiplier", 1.1)
        
        filter_parts.append(
            f"[v_concat]eq=contrast={contrast}:saturation={saturation},subtitles='{clean_sub_path}'[v_final]"
        )
        
        filter_complex = ";".join(filter_parts)
        
        cmd = [
            "ffmpeg", "-y", "-loglevel", "warning",
            "-i", self.target_path,
            "-filter_complex", filter_complex,
            "-map", "[v_final]",
            "-map", "0:a", # Map original audio straight
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "22",
            "-c:a", "aac", "-b:a", "192k",
            output_path
        ]
        
        return cmd

    def generate_mimicry_edit(self, output_path: str, transcript_words: List[Dict[str, Any]]):
        """
        Orchestrates subtitle creation, cut matching, and launches FFMPEG for rendering.
        """
        logging.info("Starting Style Imitation Edit Compilation...")
        
        # Determine paths
        temp_dir = "./temp"
        os.makedirs(temp_dir, exist_ok=True)
        sub_file = os.path.abspath(os.path.join(temp_dir, "temp_subs.ass"))
        
        # Get dimensions from target video
        import cv2
        cap = cv2.VideoCapture(self.target_path)
        w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)) or 1080
        h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)) or 1920
        fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        frame_count = cap.get(cv2.CAP_PROP_FRAME_COUNT)
        dur = frame_count / fps if fps > 0 else 10.0
        cap.release()
        
        # 1. Compile Subtitles
        self.generate_ass_subtitles(transcript_words, sub_file, w, h)
        
        # 2. Map cuts pacing based on average shot duration of reference
        ref_avg_shot = self.profile.get("pacing", {}).get("average_shot_duration_sec", 1.8)
        
        cuts = []
        last_cut = 0.0
        
        for i, word in enumerate(transcript_words):
            gap = 0.0
            if i < len(transcript_words) - 1:
                gap = transcript_words[i+1]["start"] - word["end"]
                
            current_shot_len = word["end"] - last_cut
            
            # Cut logic: Make a split if there is a gap, or if current shot exceeds reference length limit
            if gap > 0.35 or current_shot_len >= ref_avg_shot * 1.6:
                cuts.append((last_cut, word["end"]))
                last_cut = word["end"]
                
        if last_cut < dur:
            cuts.append((last_cut, dur))
            
        logging.info(f"Pacing mapper decided on {len(cuts)} cuts from raw target timeline.")
        
        # Get zoom events from reference style profile
        zoom_events = self.profile.get("motion_and_camera", {}).get("zoom_events", [])
        
        # 3. Compile and execute FFMPEG
        cmd = self.compile_ffmpeg_filters(cuts, zoom_events, sub_file, output_path)
        
        logging.info(f"Running FFMPEG system command: {' '.join(cmd)}")
        try:
            result = subprocess.run(cmd, capture_output=True, check=True, text=True)
            logging.info("FFMPEG execution succeeded.")
        except subprocess.CalledProcessError as e:
            logging.error(f"FFMPEG execution failed code {e.returncode}. Error details:\n{e.stderr}")
            raise RuntimeError(f"FFMPEG Render failed: {e.stderr}")
            
        # Clean up temporary ASS file
        try:
            os.remove(sub_file)
        except Exception:
            pass

    def export_as_resolve_xml(self, xml_output_path: str, transcript_words: List[Dict[str, Any]]):
        """
        Creates a DaVinci Resolve-compatible FCP XML.
        """
        logging.info(f"Exporting Resolve timeline XML to: {xml_output_path}")
        # Resolve XML timeline exporting stub
        pass
