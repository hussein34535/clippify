"""
style_analyzer.py - Local Reference Video Analyzer for ClipAI
============================================================
Analyzes video visuals, audio dynamics, typography and editing cuts locally.
Zero API cost. Saves result as a Reference Style Profile JSON.
"""

import os
import sys
import json
import numpy as np
import cv2
import logging
from typing import Dict, Any, List, Tuple

logging.basicConfig(level=logging.INFO, format="[%(asctime)s] %(levelname)s: %(message)s")

class StyleAnalyzer:
    def __init__(self, video_path: str):
        self.video_path = video_path
        if not os.path.exists(video_path):
            raise FileNotFoundError(f"Reference video file not found at: {video_path}")
            
        self.cap = cv2.VideoCapture(video_path)
        if not self.cap.isOpened():
            raise IOError(f"Could not open video file: {video_path}")
            
        self.width = int(self.cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        self.height = int(self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        self.fps = self.cap.get(cv2.CAP_PROP_FPS)
        if self.fps is None or self.fps <= 0:
            self.fps = 30.0
        self.total_frames = int(self.cap.get(cv2.CAP_PROP_FRAME_COUNT))
        self.duration = self.total_frames / self.fps
        
        logging.info(f"Loaded reference video. Dim: {self.width}x{self.height}, FPS: {self.fps}, Duration: {self.duration:.2f}s")

    def analyze_pacing_and_cuts(self) -> Dict[str, Any]:
        """
        Detect scene changes and calculate pacing metrics locally using PySceneDetect.
        Also calculates average shot lengths and cut density timeline.
        """
        logging.info("Starting Cut and Pacing Analysis...")
        scene_list = []
        try:
            from scenedetect import detect, ContentDetector
            scene_list = detect(self.video_path, ContentDetector(threshold=27.0))
        except Exception as e:
            logging.error(f"PySceneDetect failed or not installed: {e}. Falling back to default spacing.")
            # Fallback: create artificial cuts every 3 seconds
            scene_list = []
            current_t = 0.0
            while current_t < self.duration:
                class MockTimecode:
                    def __init__(self, sec): self.sec = sec
                    def get_seconds(self): return self.sec
                scene_list.append((MockTimecode(current_t), MockTimecode(min(current_t + 3.0, self.duration))))
                current_t += 3.0

        cuts = []
        shot_durations = []
        
        for i, scene in enumerate(scene_list):
            start_sec = scene[0].get_seconds()
            end_sec = scene[1].get_seconds()
            shot_durations.append(end_sec - start_sec)
            
            cuts.append({
                "time_sec": round(start_sec, 3),
                "type": "hard_cut" if i > 0 else "start"
            })
            
        avg_shot = float(np.mean(shot_durations)) if shot_durations else 2.0
        min_shot = float(np.min(shot_durations)) if shot_durations else 0.5
        max_shot = float(np.max(shot_durations)) if shot_durations else 5.0
        
        logging.info(f"Cuts detected: {len(cuts)}. Average shot duration: {avg_shot:.2f} seconds.")
        
        return {
            "average_shot_duration_sec": round(avg_shot, 2),
            "min_shot_duration_sec": round(min_shot, 2),
            "max_shot_duration_sec": round(max_shot, 2),
            "total_cuts": len(cuts),
            "cuts_distribution": cuts
        }

    def analyze_audio_and_beats(self) -> Dict[str, Any]:
        """
        Extract audio features, BPM, and ducking profiles locally using Librosa.
        Tracks RMS energy peaks to detect where impact effects should be placed.
        """
        logging.info("Starting Audio & Beat Tracking Analysis...")
        
        # Default mock output in case librosa fails or is not installed
        default_audio = {
            "bpm": 120.0,
            "ducking_depth_db": -14.0,
            "music_volume_ratio": 0.25,
            "sfx_triggers": [
                {"time_sec": 1.5, "sfx_category": "whoosh_transition", "volume": 0.5},
                {"time_sec": 4.5, "sfx_category": "impact_hit", "volume": 0.7}
            ]
        }
        
        try:
            import librosa
            # Load audio locally at standard 22050Hz mono
            y, sr = librosa.load(self.video_path, sr=22050)
            
            # 1. Beat tracking (BPM)
            try:
                tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr)
                beat_times = librosa.frames_to_time(beat_frames, sr=sr)
                tempo_val = float(tempo)
            except Exception as e:
                logging.error(f"Beat tracking failed: {e}. Defaulting BPM to 120.")
                tempo_val = 120.0
                beat_times = np.array([])

            # 2. RMS Energy Envelope calculation
            rms = librosa.feature.rms(y=y)[0]
            rms_times = librosa.frames_to_time(range(len(rms)), sr=sr)
            mean_rms = np.mean(rms)
            max_rms = np.max(rms) if len(rms) > 0 else 1.0
            
            # 3. Detect sudden peaks in energy (transient onsets) for sound FX timing
            onset_env = librosa.onset.onset_strength(y=y, sr=sr)
            peaks = librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr)
            peak_times = librosa.frames_to_time(peaks, sr=sr)
            
            sfx_triggers = []
            for pk in peak_times:
                # Search nearest RMS time block
                idx = np.searchsorted(rms_times, pk)
                if idx < len(rms) and rms[idx] > mean_rms * 1.8:
                    sfx_triggers.append({
                        "time_sec": round(float(pk), 3),
                        "sfx_category": "impact_hit" if rms[idx] > mean_rms * 2.5 else "whoosh_transition",
                        "volume": round(float(rms[idx] / max_rms), 2)
                    })
                    
            # Limit triggers to the most meaningful transients (max 15) to prevent auditory clutter
            sfx_triggers = sorted(sfx_triggers, key=lambda x: x["volume"], reverse=True)[:15]
            sfx_triggers = sorted(sfx_triggers, key=lambda x: x["time_sec"])
            
            logging.info(f"BPM extracted: {tempo_val:.1f}. SFX trigger points: {len(sfx_triggers)}")
            
            return {
                "bpm": round(tempo_val, 1),
                "ducking_depth_db": -14.0, # Standard vlog ducking depth in dB
                "music_volume_ratio": 0.25,
                "sfx_triggers": sfx_triggers
            }
            
        except Exception as e:
            logging.error(f"Librosa failed or not installed: {e}. Using default audio profile.")
            return default_audio

    def analyze_motion_and_camera(self) -> Dict[str, Any]:
        """
        Estimate camera zoom, pans, and shakiness using Farneback Optical Flow.
        Analyzes vector directions to map dynamic jump-cuts or zooms.
        """
        logging.info("Starting Optical Flow Motion Analysis...")
        # Step value dictates temporal downsampling for performance (sample every 15 frames)
        step = max(5, int(self.fps * 0.5))
        zoom_events = []
        shake_amplitudes = []
        pans = []
        
        prev_gray = None
        frame_idx = 0
        
        while frame_idx < self.total_frames - step:
            self.cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
            ret, frame = self.cap.read()
            if not ret or frame is None:
                break
                
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            # Resize frame locally to 320x180 to speed up Optical Flow math 10x
            gray_small = cv2.resize(gray, (320, 180))
            
            if prev_gray is not None:
                flow = cv2.calcOpticalFlowFarneback(
                    prev_gray, gray_small, None, 
                    pyr_scale=0.5, levels=3, winsize=15, 
                    iterations=3, poly_n=5, poly_sigma=1.2, flags=0
                )
                
                flow_x = flow[..., 0]
                flow_y = flow[..., 1]
                
                # Shakiness coefficient (magnitude of velocity vectors)
                magnitude = np.sqrt(flow_x**2 + flow_y**2)
                mean_mag = np.mean(magnitude)
                shake_amplitudes.append(float(mean_mag))
                
                # Math checks for zoom (radial vector convergence/divergence)
                h, w = flow_x.shape
                y_indices, x_indices = np.indices((h, w))
                cx_idx, cy_idx = w // 2, h // 2
                
                # Vector relative distances from screen center
                rx = x_indices - cx_idx
                ry = y_indices - cy_idx
                
                # Radial dot product
                dot_prod = flow_x * rx + flow_y * ry
                radial_sum = np.sum(dot_prod)
                
                time_sec = frame_idx / self.fps
                
                # Threshold for zoom detection based on frame size resolution
                zoom_threshold = 95000.0
                if radial_sum > zoom_threshold:
                    zoom_events.append({
                        "start_sec": round(time_sec, 2),
                        "end_sec": round(time_sec + 0.7, 2),
                        "type": "jump_zoom",
                        "scale_multiplier": 1.25,
                        "focus_point": {"x": 0.5, "y": 0.5}
                    })
                elif radial_sum < -zoom_threshold:
                    zoom_events.append({
                        "start_sec": round(time_sec, 2),
                        "end_sec": round(time_sec + 0.7, 2),
                        "type": "slow_zoom_out",
                        "scale_multiplier": 0.85,
                        "focus_point": {"x": 0.5, "y": 0.5}
                    })
                    
                # Detect side pans (large consistent horizontal flows)
                mean_flow_x = np.mean(flow_x)
                if abs(mean_flow_x) > 2.0:
                    pans.append({
                        "start_sec": round(time_sec, 2),
                        "end_sec": round(time_sec + 0.5, 2),
                        "direction": "left_to_right" if mean_flow_x > 0 else "right_to_left",
                        "speed": "fast" if abs(mean_flow_x) > 5.0 else "medium"
                    })
                    
            prev_gray = gray_small
            frame_idx += step
            
        avg_shake = float(np.mean(shake_amplitudes)) if shake_amplitudes else 0.01
        
        # Merge consecutive zoom events to prevent rapid oscillating jumps
        merged_zooms = []
        for z in sorted(zoom_events, key=lambda x: x["start_sec"]):
            if not merged_zooms or z["start_sec"] > merged_zooms[-1]["end_sec"] + 1.2:
                merged_zooms.append(z)
                
        # Merge consecutive pan events
        merged_pans = []
        for p in sorted(pans, key=lambda x: x["start_sec"]):
            if not merged_pans or p["start_sec"] > merged_pans[-1]["end_sec"] + 1.0:
                merged_pans.append(p)
                
        logging.info(f"Average shakiness: {avg_shake:.3f}. Zooms detected: {len(merged_zooms)}. Pans: {len(merged_pans)}")
        
        return {
            "average_shake_amplitude": round(avg_shake, 3),
            "zoom_events": merged_zooms,
            "pans_and_tilts": merged_pans
        }

    def analyze_subtitle_style_ocr(self) -> Dict[str, Any]:
        """
        Scan video frames to detect subtitles using a local OCR engine.
        Identifies text positions, sizes, and guesses main text coloring heuristics.
        """
        logging.info("Starting Local Subtitle OCR Analysis...")
        
        # Initial defaults
        fallback_style = {
            "font_size_ratio": 0.07,
            "position_y_ratio": 0.83,
            "fill_color": "#FFFFFF",
            "stroke_color": "#000000",
            "stroke_width": 3.0,
            "has_shadow": True
        }
        
        try:
            import easyocr
            # Load EasyOCR for Arabic/English without download prompt
            reader = easyocr.Reader(['ar', 'en'], gpu=False, verbose=False)
        except Exception as e:
            logging.warning(f"EasyOCR not available ({e}). Subtitle analyzer using style defaults.")
            return fallback_style
            
        # Scan 20 evenly spread frames in the video
        frame_spots = np.linspace(self.total_frames * 0.05, self.total_frames * 0.95, 20, dtype=int)
        detected_configs = []
        
        for f_idx in frame_spots:
            self.cap.set(cv2.CAP_PROP_POS_FRAMES, f_idx)
            ret, frame = self.cap.read()
            if not ret or frame is None:
                continue
                
            h, w = frame.shape[:2]
            # Subtitle zone: Crop bottom 35% of the frame
            ymin, ymax = int(h * 0.65), int(h * 0.98)
            subtitle_crop = frame[ymin:ymax, :]
            
            try:
                results = reader.readtext(subtitle_crop)
            except Exception as e:
                logging.error(f"OCR frame read failed: {e}")
                continue
                
            for (bbox, text, confidence) in results:
                if confidence > 0.5 and len(text.strip()) > 1:
                    # Translate bbox back to full-frame y-coordinates
                    box_top = bbox[0][1] + ymin
                    box_bot = bbox[2][1] + ymin
                    box_left = bbox[0][0]
                    box_right = bbox[1][0]
                    
                    center_y = (box_top + box_bot) / 2.0
                    height_px = box_bot - box_top
                    
                    font_ratio = height_px / h
                    y_ratio = center_y / h
                    
                    # Extract dominant color from the text bounding box (RGB)
                    sub_region = subtitle_crop[int(bbox[0][1]):int(bbox[2][1]), int(bbox[0][0]):int(bbox[1][0])]
                    if sub_region.size > 0:
                        # Reshape to list of pixels (BGR format from cv2)
                        pixels = sub_region.reshape(-1, 3)
                        bright_pixels = pixels[np.mean(pixels, axis=1) > 130]
                        if len(bright_pixels) > 0:
                            mean_bgr = np.mean(bright_pixels, axis=0)
                        else:
                            mean_bgr = np.mean(pixels, axis=0)
                            
                        hex_color = f"#{int(mean_bgr[2]):02X}{int(mean_bgr[1]):02X}{int(mean_bgr[0]):02X}"
                    else:
                        hex_color = "#FFFFFF"
                        
                    detected_configs.append({
                        "font_size_ratio": font_ratio,
                        "position_y_ratio": y_ratio,
                        "fill_color": hex_color
                    })
                    
        if not detected_configs:
            logging.info("No subtitle texts detected via OCR. Reverting to default profiles.")
            return fallback_style
            
        sizes = [x["font_size_ratio"] for x in detected_configs]
        y_pos = [x["position_y_ratio"] for x in detected_configs]
        colors = [x["fill_color"] for x in detected_configs]
        
        dominant_color = max(set(colors), key=colors.count)
        
        final_style = {
            "font_size_ratio": round(float(np.median(sizes)), 3),
            "position_y_ratio": round(float(np.median(y_pos)), 3),
            "fill_color": dominant_color,
            "stroke_color": "#000000",
            "stroke_width": 3.0,
            "has_shadow": True
        }
        
        logging.info(f"Subtitles extracted: Font ratio={final_style['font_size_ratio']:.3f}, Y ratio={final_style['position_y_ratio']:.3f}, Color={final_style['fill_color']}")
        return final_style

    def generate_style_profile(self, output_profile_path: str) -> Dict[str, Any]:
        """
        Main runner: aggregates all features and saves profile.
        Safely releases CV resource handles at completion.
        """
        logging.info(f"Assembling Reference Style Profile for {self.video_path}...")
        try:
            pacing = self.analyze_pacing_and_cuts()
            audio = self.analyze_audio_and_beats()
            motion = self.analyze_motion_and_camera()
            subtitles = self.analyze_subtitle_style_ocr()
            
            profile = {
                "style_profile_version": "1.0",
                "meta": {
                    "reference_video_name": os.path.basename(self.video_path),
                    "duration_sec": round(self.duration, 2),
                    "detected_fps": round(self.fps, 2),
                    "resolution": {"width": self.width, "height": self.height}
                },
                "pacing": pacing,
                "motion_and_camera": motion,
                "typography": {
                    "subtitles": subtitles
                },
                "audio_behavior": {
                    "music_ducking": {
                        "ducking_depth_db": audio["ducking_depth_db"],
                        "attack_ms": 150,
                        "release_ms": 300
                    },
                    "sfx_triggers": audio["sfx_triggers"],
                    "background_music_genre": "hype_hiphop"
                },
                "visual_effects": {
                    "color_grade": {
                        "contrast_multiplier": 1.08,
                        "saturation_multiplier": 1.15,
                        "color_temp_offset": 60
                    }
                }
            }
            
            # Write to disk
            with open(output_profile_path, "w", encoding="utf-8") as f:
                json.dump(profile, f, indent=2, ensure_ascii=False)
                
            logging.info(f"Style profile generated successfully at: {output_profile_path}")
            return profile
            
        finally:
            self.cap.release()
            logging.info("OpenCV capture handle released.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python style_analyzer.py <input_video> <output_json>")
    else:
        analyzer = StyleAnalyzer(sys.argv[1])
        analyzer.generate_style_profile(sys.argv[2])
