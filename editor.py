"""
editor.py — Video cutting + 9:16 crop + captions
ClipAI — Local Video Clipper (no AI, no cloud)
Compatible with moviepy 2.x
"""

import os
import struct
import wave
import numpy as np

_NVENC_AVAILABLE = None

def _has_nvenc():
    global _NVENC_AVAILABLE
    if _NVENC_AVAILABLE is not None:
        return _NVENC_AVAILABLE
    try:
        import imageio_ffmpeg
        ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()
        import subprocess
        # Run a quick dummy encode using nvenc
        cmd = [ffmpeg_exe, "-y", "-f", "lavfi", "-i", "nullsrc=s=128x128:d=0.1", "-c:v", "h264_nvenc", "-f", "null", "-"]
        res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        _NVENC_AVAILABLE = (res.returncode == 0)
    except Exception:
        _NVENC_AVAILABLE = False
    return _NVENC_AVAILABLE


def detect_beats(audio_path: str, bpm_range: tuple = (80, 160)) -> list:
    """Detect beat timestamps in an audio file using onset energy + autocorrelation.
    Returns list of beat times in seconds."""
    from pydub import AudioSegment
    import numpy as np
    try:
        audio = AudioSegment.from_file(audio_path)
        if audio.channels > 1:
            audio = audio.set_channels(1)
        samples = np.array(audio.get_array_of_samples()).astype(np.float32)
        sr = audio.frame_rate
    except Exception:
        return []

    # Compute onset energy envelope
    hop = int(sr * 0.02)  # 20ms windows
    envelope = []
    for i in range(0, len(samples) - hop, hop):
        chunk = samples[i:i+hop]
        envelope.append(np.sqrt(np.mean(chunk**2)))
    envelope = np.array(envelope)
    if len(envelope) < 10:
        return []

    # Find dominant BPM via autocorrelation
    env = envelope - np.mean(envelope)
    corr = np.correlate(env, env, mode='full')
    corr = corr[len(corr)//2:]
    min_lag = int(60.0 / bpm_range[1] / 0.02)
    max_lag = int(60.0 / bpm_range[0] / 0.02)
    if max_lag >= len(corr):
        max_lag = len(corr) - 1
    if min_lag >= max_lag:
        return []
    peak_lag = np.argmax(corr[min_lag:max_lag]) + min_lag
    bpm = 60.0 / (peak_lag * 0.02)

    # Generate beat timestamps
    beat_interval = 60.0 / bpm
    total_sec = len(samples) / sr
    beats = []
    t = 0.0
    while t < total_sec:
        beats.append(t)
        t += beat_interval
    return beats


def get_nearest_beat(beats: list, time_sec: float) -> float:
    """Snap a time to the nearest beat."""
    if not beats:
        return time_sec
    idx = np.searchsorted(beats, time_sec)
    if idx == 0:
        return beats[0]
    if idx >= len(beats):
        return beats[-1]
    prev = beats[idx - 1]
    nxt = beats[idx]
    return prev if (time_sec - prev) < (nxt - time_sec) else nxt


def _make_caption_overlay(clip_w: int, clip_h: int,
                          clip_index: int, duration_sec: float,
                          duration: float):
    """
    Build a semi-transparent black bar + white text overlay.
    Returns a list of clips to layer on top, or [] on failure.
    """
    try:
        bar_h = int(clip_h * 0.15)   # 15% of frame height

        # Semi-transparent black rectangle via numpy RGBA array
        bar_array = np.zeros((bar_h, clip_w, 4), dtype=np.uint8)
        bar_array[:, :, 3] = 160     # alpha ≈ 63%

        bar_clip = (
            ImageClip(bar_array, is_mask=False)
            .with_duration(duration)
            .with_position(("center", clip_h - bar_h))
        )

        label = f"Clip {clip_index}  •  {int(duration_sec)}s"
        txt = (
            TextClip(
                font="Arial",
                text=label,
                font_size=40,
                color="white",
                method="label",
            )
            .with_duration(duration)
            .with_position(("center", clip_h - bar_h + 8))
        )

        return [bar_clip, txt]

    except Exception as exc:
        # TextClip can fail on some Windows setups — degrade gracefully
        print(f"  [WARN] Caption skipped ({exc})")
        return []


import subprocess
import imageio_ffmpeg

def _get_video_dimensions(video_path: str):
    """Return (width, height) of video using ffprobe."""
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    ffprobe = ffmpeg.replace("ffmpeg", "ffprobe")
    if not os.path.isfile(ffprobe):
        ffprobe = "ffprobe"
    try:
        result = subprocess.run(
            [ffprobe, "-v", "error", "-select_streams", "v:0",
             "-show_entries", "stream=width,height",
             "-of", "csv=p=0", video_path],
            capture_output=True, text=True, timeout=10
        )
        parts = result.stdout.strip().split(",")
        if len(parts) >= 2:
            return int(parts[0]), int(parts[1])
    except Exception:
        pass
    return 1920, 1080  # fallback assumption

def export(video_path: str, start_sec: float, end_sec: float,
           output_path: str, clip_index: int = 1, ass_path: str = None,
           words: list = None, trim_silence: bool = False,
           scale_punches: bool = False, music_path: str = None,
           ending_cta: str = None,
           theme: str = "TikTok", auto_director: bool = False,
           emphasis_timestamps: list = None,
           audio_ducking: bool = True,
           color_grade: str = "none",
           speed_ramping: bool = True,
           sound_fx: bool = True,
           add_hook_teaser: bool = True,
           sfx_queries: list = None,
           # ── NEW: Content Type System ──────────────────────────────
           content_type: str = "podcast",
           # ── NEW: Custom Overlay Text ──────────────────────────────
           overlay_text: str = "",
           overlay_position: str = "center",   # top | center | bottom
           overlay_time_start: float = 0.0,
           overlay_time_end: float = 0.0,
           # ── NEW: Hook Sentence Sequence ───────────────────────────
           hook_sentence: str = "",
           hook_start_sec: float = 0.0,
           hook_end_sec: float = 3.0,
           # ── NEW: Cinematic Outro ──────────────────────────────────
           outro_enabled: bool = True,
           # ── NEW: Smart Crop (from video_analyzer) ─────────────────
           # FFmpeg crop expression e.g. "crop=608:1080:200:0"
           # None = fallback to safe center crop
           smart_crop_filter: str = None,
           # ── NEW: Export Quality ───────────────────────────────────
           export_quality: str = "High",
           # ── NEW: Custom Logo / Watermark ──────────────────────────
           logo_path: str = None,
           # ── NEW: B-Roll Video Overlays (Pexels) ───────────────────
           brolls: list = None,
           # ── NEW: SFX density mode ─────────────────────────────────
           sfx_mode: str = "normal",
           # ── NEW: AI-Driven Zoom ───────────────────────────────────
           zoom_style: str = "none",
           # ── Phase 8: Dynamic Pacing & Retiming ────────────────────
           slow_motion_start: float = 0.0,
           slow_motion_end: float = 0.0,
           slow_motion_speed: float = 1.0,
           # ── Phase 11: Semantic Multi-Clip Narrative ───────────────
           narrative_acts: list = None):
    """
    Cut → 9:16 crop → caption burn → dynamic zoom punches → lo-fi music mix → ending CTA card → export.
    Supports auto-silence trimming by analyzing word gaps.
    Supports Studio vocal mastering and dynamic emotion-based zoom cuts.
    """
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)

    src_w, src_h = _get_video_dimensions(video_path)
    if smart_crop_filter == "no_crop":
        TARGET_W, TARGET_H = src_w, src_h
    else:
        TARGET_W, TARGET_H = 1080, 1920

    ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()

    # Detect beats from music for sync
    beat_interval = None
    if music_path and os.path.exists(music_path) and auto_director:
        beats = detect_beats(music_path)
        if len(beats) > 2:
            beat_interval = beats[1] - beats[0]

    # 1. Determine active segments (trim silence / narrative acts)
    segments = []
    if narrative_acts:
        print(f"  [NARRATIVE STITCH] Rendering 3-act narrative: {len(narrative_acts)} acts.")
        for act in narrative_acts:
            segments.append((act["start_sec"], act["end_sec"]))
    elif trim_silence and words:
        from silence_trimmer import compute_active_segments
        segments = compute_active_segments(
            words=words,
            start_sec=start_sec,
            end_sec=end_sec,
            content_type=content_type,
            trim_mode="auto"
        )
    else:
        segments.append((start_sec, end_sec))
        
    # Ensure we have at least one segment
    if not segments:
        segments.append((start_sec, end_sec))
        
    # Calculate actual concatenated clip duration
    total_duration = sum(s_end - s_start for s_start, s_end in segments)
    if total_duration <= 0.0:
        total_duration = end_sec - start_sec
        
    has_logo = bool(logo_path and os.path.isfile(logo_path))
    v_final_label = "[v_final]"
    a_final_label = "[a_final]"
    teaser_duration_sped = 0.0

    if add_hook_teaser and auto_director:
        if hook_end_sec > hook_start_sec:
            # Primary: hook sentence timestamps from AI (natural duration)
            teaser_local_start = hook_start_sec
            # Cut exactly and automatically at the natural end of the sentence
            teaser_local_end = min(total_duration, hook_end_sec)
            print(f"  [TEASER] Auto duration from hook sentence: {hook_end_sec - hook_start_sec:.1f}s")
        elif emphasis_timestamps:
            # Fallback 1: use first emphasis timestamp region, extend naturally
            teaser_local_start = emphasis_timestamps[0][0]
            # Estimate duration based on number of words spoken if available
            # Use 5s as a reasonable fallback for one sentence
            teaser_local_end = min(total_duration, teaser_local_start + 5.0)
            print(f"  [TEASER] Fallback duration (emphasis-based): {teaser_local_end - teaser_local_start:.1f}s")
        else:
            # Fallback 2: no data, use first 5 seconds max
            teaser_local_start = 0.0
            teaser_local_end = min(total_duration, 5.0)
            print(f"  [TEASER] Fallback duration (default): {teaser_local_end - teaser_local_start:.1f}s")

        if teaser_local_end > teaser_local_start + 0.1:
            teaser_dur = teaser_local_end - teaser_local_start
            # Keep the hook at calm, natural, normal speed (no speed up!)
            teaser_duration_sped = teaser_dur
            v_final_label = "[v_main_final]"
            a_final_label = "[a_main_final]"

    # 2. Build FFmpeg Filter Complex
    filter_complex = []
    concat_inputs = []
    
    # Concatenate active segments (already trimmed via input seeking)
    # Phase 10: Smooth Audio Transitions (prevent digital clicks or sudden vocal cuts)
    for idx, (s_start, s_end) in enumerate(segments):
        seg_dur = s_end - s_start
        filter_complex.append(f"[{idx}:v]setpts=PTS-STARTPTS[v{idx}]")
        if seg_dur > 0.1:
            filter_complex.append(f"[{idx}:a]asetpts=PTS-STARTPTS,afade=t=in:d=0.05,afade=t=out:d=0.05:start_time={seg_dur - 0.05:.3f}[a{idx}]")
        else:
            filter_complex.append(f"[{idx}:a]asetpts=PTS-STARTPTS[a{idx}]")
        concat_inputs.append(f"[v{idx}][a{idx}]")
        
    # Apply concatenation
    filter_complex.append(f"{''.join(concat_inputs)}concat=n={len(segments)}:v=1:a=1[v_cut][a_cut]")

    # ── Phase 8: Dynamic Pacing & Retiming (Slow-mo / Speed-up) ──
    pacing_speed = 1.0
    if words and total_duration > 0.0:
        clip_words = [w for w in words if w['end'] >= start_sec and w['start'] <= end_sec]
        if clip_words:
            words_per_sec = len(clip_words) / total_duration
            if words_per_sec < 2.0:
                print(f"  [PACING] Slow speech rate detected ({words_per_sec:.2f} w/s). Applying gentle 1.1x speedup.")
                pacing_speed = 1.1

    v_src = "v_cut"
    a_src = "a_cut"

    if pacing_speed != 1.0:
        filter_complex.append(f"[{v_src}]setpts={1.0/pacing_speed:.5f}*PTS[v_paced]")
        filter_complex.append(f"[{a_src}]atempo={pacing_speed:.3f}[a_paced]")
        v_src = "v_paced"
        a_src = "a_paced"
        total_duration = total_duration / pacing_speed

    # Dynamic Retiming (Slow-motion for emotional highlights)
    if slow_motion_speed < 1.0 and slow_motion_end > slow_motion_start + 0.1:
        s2 = max(0.0, slow_motion_start)
        s3 = min(total_duration, slow_motion_end)
        s1 = 0.0
        s4 = total_duration

        if s3 > s2 + 0.1:
            v_parts = []
            a_parts = []
            part_idx = 0

            # Part 1: before slow-mo
            if s2 > 0.1:
                part_idx += 1
                filter_complex.append(f"[{v_src}]trim=start={s1}:end={s2},setpts=PTS-STARTPTS[vp{part_idx}]")
                filter_complex.append(f"[{a_src}]atrim=start={s1}:end={s2},asetpts=PTS-STARTPTS[ap{part_idx}]")
                v_parts.append(f"[vp{part_idx}]")
                a_parts.append(f"[ap{part_idx}]")

            # Part 2: slow-mo
            pts_factor = 1.0 / slow_motion_speed
            part_idx += 1
            filter_complex.append(f"[{v_src}]trim=start={s2}:end={s3},setpts={pts_factor:.3f}*(PTS-STARTPTS)[vp{part_idx}]")
            filter_complex.append(f"[{a_src}]atrim=start={s2}:end={s3},asetpts=PTS-STARTPTS,atempo={slow_motion_speed:.3f}[ap{part_idx}]")
            v_parts.append(f"[vp{part_idx}]")
            a_parts.append(f"[ap{part_idx}]")

            # Part 3: after slow-mo
            if s3 < s4 - 0.1:
                part_idx += 1
                filter_complex.append(f"[{v_src}]trim=start={s3}:end={s4},setpts=PTS-STARTPTS[vp{part_idx}]")
                filter_complex.append(f"[{a_src}]atrim=start={s3}:end={s4},asetpts=PTS-STARTPTS[ap{part_idx}]")
                v_parts.append(f"[vp{part_idx}]")
                a_parts.append(f"[ap{part_idx}]")

            # Concat
            concat_in = "".join(v_parts[i] + a_parts[i] for i in range(len(v_parts)))
            filter_complex.append(f"{concat_in}concat=n={len(v_parts)}:v=1:a=1[v_retimed][a_retimed]")
            v_src = "v_retimed"
            a_src = "a_retimed"

            # Recalculate duration
            new_part2_dur = (s3 - s2) * pts_factor
            total_duration = s2 + new_part2_dur + (s4 - s3)
            print(f"  [PACING] Applied slow-motion ({slow_motion_speed}x) from {s2:.1f}s to {s3:.1f}s. New total duration: {total_duration:.1f}s")

    # ── SMART CROP (face-aware framing) ──────────────────────────────────────
    _crop_expr = smart_crop_filter if (smart_crop_filter and smart_crop_filter != "no_crop") else "crop=ih*9/16:ih:(iw-ih*9/16)/2:0"
    if smart_crop_filter == "no_crop":
        filter_complex.append(f"[{v_src}]null[v_cropped_raw]")
    else:
        filter_complex.append(f"[{v_src}]{_crop_expr}[v_cropped_raw]")
    

    # ── AI-Driven Dynamic Zoom / Jump Cut ──────────────────────────────────────
    if zoom_style == "punch":
        filter_complex.append(f"[v_cropped_raw]scale=iw*1.15:ih*1.15,crop=iw/1.15:ih/1.15:(iw-iw/1.15)/2:(ih-ih/1.15)/2,scale={TARGET_W}:{TARGET_H}[v_cropped]")
    elif zoom_style == "gentle":
        filter_complex.append(f"[v_cropped_raw]scale=iw*1.05:ih*1.05,crop=iw/1.05:ih/1.05:(iw-iw/1.05)/2:(ih-ih/1.05)/2,scale={TARGET_W}:{TARGET_H}[v_cropped]")
    elif zoom_style in ["slow_push", "dynamic"]:
        filter_complex.append(f"[v_cropped_raw]scale=iw*1.10:ih*1.10,crop=iw/1.10:ih/1.10:(iw-iw/1.10)/2:(ih-ih/1.10)/2,scale={TARGET_W}:{TARGET_H}[v_cropped]")
    else:
        filter_complex.append(f"[v_cropped_raw]scale={TARGET_W}:{TARGET_H}[v_cropped]")
    
    # Calculate broll starting input index
    num_video_inputs = len(segments)
    if teaser_duration_sped > 0:
        num_video_inputs += 1
    broll_start_idx = num_video_inputs
    if music_path and os.path.exists(music_path):
        broll_start_idx += 1
    if has_logo:
        broll_start_idx += 1

    # ── B-ROLL OVERLAYS (Pexels Integration - Phase 8) ──────────────────────
    v_broll_out = "v_cropped"
    if brolls:
        valid_broll_count = 0
        for idx, br in enumerate(brolls):
            br_path = br.get("local_path")
            if br_path and os.path.exists(br_path):
                br_input_idx = broll_start_idx + valid_broll_count
                valid_broll_count += 1
                
                t_start = br.get("start_offset", 0.0)
                t_dur = br.get("duration", 3.0)
                t_end = t_start + t_dur
                
                # Scale & crop B-roll to TARGET_W x TARGET_H to fit layout perfectly
                filter_complex.append(
                    f"[{br_input_idx}:v]scale={TARGET_W}:{TARGET_H}:force_original_aspect_ratio=increase,"
                    f"crop={TARGET_W}:{TARGET_H},setpts=PTS-STARTPTS[br_scaled_{idx}]"
                )
                # Overlay it onto the main cropped video stream
                next_out = f"v_broll_{idx}"
                filter_complex.append(
                    f"[{v_broll_out}][br_scaled_{idx}]overlay=0:0:enable='between(t,{t_start},{t_end})'[{next_out}]"
                )
                v_broll_out = next_out

    def append_filter(base: str, filt: str) -> str:
        if base.endswith("]"):
            return base + filt
        return base + "," + filt

    video_filter = f"[{v_broll_out}]"

    if ass_path and os.path.exists(ass_path):
        ass_path_unix = ass_path.replace("\\", "/")
        ass_path_unix = ass_path_unix.replace(":", "\\:")
        video_filter = append_filter(video_filter, f"ass='{ass_path_unix}'")
        
    # ── Removed erratic auto-zooming to keep framing stable ──
        
    # ── Smart Ending CTA Card overlay (during the last 2 seconds of the video)
    if ending_cta and ending_cta.strip():
        escaped_cta = ending_cta.strip().replace("'", "\\'").upper()
        # Draw semi-transparent background box card at the center of the video
        video_filter = append_filter(video_filter, f"drawbox=x=50:y='ih/2-90':w='iw-100':h=180:color=black@0.75:t=fill:enable='gt(t,{total_duration - 2.0})'")
        # Draw CTA text centered inside the box
        video_filter = append_filter(video_filter, f"drawtext=text='{escaped_cta}':fontcolor=yellow:fontsize=42:fontfile=Impact:x='(w-text_w)/2':y='h/2-22':enable='gt(t,{total_duration - 2.0})'")
        
    # ── Professional Color Grading (content-type aware) ──────────────────
    _GRADES = {
        "cinematic_warm": "colorbalance=rs=0.1:gs=-0.05:bs=-0.1,eq=saturation=0.85:contrast=1.1",
        "cinematic_cool": "colorbalance=rs=-0.05:gs=0.0:bs=0.08,eq=saturation=0.75:contrast=1.05",
        "vibrant":        "eq=saturation=1.4:contrast=1.2:brightness=0.05",
        "vintage":        "colorbalance=rs=0.08:gs=0.03:bs=-0.08,eq=saturation=0.6:contrast=0.9",
        "dramatic":       "eq=contrast=1.3:saturation=0.7:brightness=-0.05,colorbalance=rs=-0.05:gs=0:bs=0.05",
        "warm_natural":   "colorbalance=rs=0.05:gs=0.02:bs=-0.04,eq=saturation=1.05:contrast=1.05",
    }
    # Auto-select grade from content type if not explicitly set
    if (not color_grade or color_grade == "none") and content_type:
        _CT_GRADE = {
            "awareness":   "dramatic",
            "motivation":  "cinematic_warm",
            "comedy":      "vibrant",
            "interview":   "warm_natural",
        }
        color_grade = _CT_GRADE.get(content_type, "none")
    if color_grade and color_grade in _GRADES:
        video_filter = append_filter(video_filter, _GRADES[color_grade])

    # ── Custom Overlay Text (from custom_instructions) ──────────────────────
    if overlay_text and overlay_text.strip() and overlay_time_end > overlay_time_start:
        esc_text = overlay_text.strip().replace("'", "\\'").replace('"', '\\"')
        # Mathematically align box and text so they are perfectly centered relative to each other
        _OVL_Y_box = {"top": "ih*0.08-40", "center": "ih/2-40", "bottom": "ih*0.78-40"}
        _OVL_Y_txt = {"top": "h*0.08-text_h/2", "center": "h/2-text_h/2", "bottom": "h*0.78-text_h/2"}
        y_expr_box = _OVL_Y_box.get(overlay_position, "ih/2-40")
        y_expr_txt = _OVL_Y_txt.get(overlay_position, "h/2-text_h/2")
        t_start = overlay_time_start
        t_end   = overlay_time_end
        # Draw a semi-transparent background box centered at the position
        video_filter = append_filter(video_filter, (
            f"drawbox=x=60:y='{y_expr_box}':w='iw-120':h=80"
            f":color=black@0.7:t=fill"
            f":enable='between(t,{t_start},{t_end})'"
        ))
        # Draw the text perfectly centered inside the box
        video_filter = append_filter(video_filter, (
            f"drawtext=text='{esc_text}':fontcolor=white:fontsize=46"
            f":fontfile=Arial:x='(w-text_w)/2':y='{y_expr_txt}'"
            f":enable='between(t,{t_start},{t_end})'"
        ))

    teaser_input_idx = None
    if teaser_duration_sped > 0:
        teaser_input_idx = len(segments)
        # Teaser video filter: starts from the separate teaser input stream
        teaser_crop_expr = "null" if smart_crop_filter == "no_crop" else (_crop_expr if _crop_expr else "crop=ih*9/16:ih:(iw-ih*9/16)/2:0")
        teaser_v_filter = (
            f"[{teaser_input_idx}:v]{teaser_crop_expr},scale={TARGET_W}:{TARGET_H}:flags=bicubic,setsar=1,"
            f"hue=s=0,eq=brightness=-0.05:contrast=1.1,vignette,tpad=stop_mode=clone:stop_duration=1.2[v_teaser_final]"
        )
        filter_complex.append(teaser_v_filter)
        
        filter_complex.append(
            f"[{teaser_input_idx}:a]aresample=44100,asetpts=PTS-STARTPTS,apad=pad_dur=1.2[a_teaser_final]"
        )
        
        # Apply main video filters and output to [v_main_final]
        video_filter = append_filter(video_filter, f"scale={TARGET_W}:{TARGET_H}:flags=bicubic,setsar=1{v_final_label}")
        filter_complex.append(video_filter)
    else:
        out_lbl = "[v_before_logo]" if has_logo else v_final_label
        video_filter = append_filter(video_filter, f"scale={TARGET_W}:{TARGET_H}:flags=bicubic,setsar=1{out_lbl}")
        filter_complex.append(video_filter)
    
    # ── STUDIO VOCAL MASTERING & AUDIO EFFECTS ────────────────────────────────
    # A. Vocal processing chain (Gentle Normalization to avoid robotic distortion)
    if auto_director:
        filter_complex.append(
            f"[{a_src}]aresample=44100,"
            f"highpass=f=80,lowpass=f=12000,"
            f"afftdn=nf=-36,"  # Professional noise reduction
            f"equalizer=f=3000:width_type=h:width=1500:g=3,"  # Presence boost for vocal clarity
            f"loudnorm=I=-16:TP=-1.5:LRA=11[a_voice]"
        )
    else:
        filter_complex.append(f"[{a_src}]aresample=44100,volume=1.0[a_voice]")

    # B. Dynamic background music with sidechain audio ducking
    music_input_idx = len(segments)
    if teaser_duration_sped > 0:
        music_input_idx += 1
        
    if music_path and os.path.exists(music_path):
        # Phase 10: Swell Outro Music Volume (L-Cut)
        if total_duration > 5.0:
            vol_expr = f"volume='if(gte(t,{total_duration - 1.2:.3f}), 0.06 + ((t - {total_duration - 1.2:.3f}) / 1.2) * 0.12, 0.06)':eval=frame"
            filter_complex.append(f"[{music_input_idx}:a]{vol_expr}[a_music_raw]")
        else:
            filter_complex.append(f"[{music_input_idx}:a]volume=0.06[a_music_raw]")
        if audio_ducking and auto_director:
            # Split voice: one copy goes to final mix, one acts as sidechain control
            filter_complex.append(f"[a_voice]asplit=2[a_dry][a_sidechain]")
            # Sidechain compressor: lowers music gently when voice is present
            filter_complex.append(
                "[a_music_raw][a_sidechain]sidechaincompress="
                "threshold=0.08:ratio=4:attack=200:release=500[a_music_ducked]"
            )
            # Mix compressed music with dry voice
            filter_complex.append(f"[a_dry][a_music_ducked]amix=inputs=2:duration=first{a_final_label}")
        else:
            filter_complex.append(f"[a_voice][a_music_raw]amix=inputs=2:duration=first{a_final_label}")
    else:
        filter_complex.append(f"[a_voice]volume=1.0{a_final_label}")

    if teaser_duration_sped > 0:
        # Concatenate teaser and main with a smooth fadeblack (black screen) transition
        # We pad the hook with 1.2s of frozen frame and silence, and start the transition perfectly
        # at the end of the spoken words. This ensures the sentence fully finishes before the black screen.
        trans_offset = teaser_duration_sped
        if trans_offset < 0: trans_offset = 0
        
        # xfade requires constant frame rate, so we apply fps=30 to both inputs before fading
        out_lbl = "[v_before_logo]" if has_logo else "[v_final]"
        filter_complex.append(
            f"[v_teaser_final]fps=30[vt_fps];{v_final_label}fps=30[vm_fps];[vt_fps][vm_fps]xfade=transition=fadeblack:duration=1.2:offset={trans_offset:.3f}{out_lbl}"
        )
        filter_complex.append(
            f"[a_teaser_final][a_main_final]acrossfade=d=1.2[a_final]"
        )
        
    # Apply logo overlay if enabled
    if has_logo:
        logo_input_idx = len(segments)
        if teaser_duration_sped > 0:
            logo_input_idx += 1
        if music_path and os.path.exists(music_path):
            logo_input_idx += 1
        filter_complex.append(f"[{logo_input_idx}:v]scale=180:-1[logo_scaled]")
        filter_complex.append(f"[v_before_logo][logo_scaled]overlay=main_w-overlay_w-40:40[v_final]")

    # Combine filter complex
    filter_complex_str = ";".join(filter_complex)
    
    # 3. Formulate FFmpeg Command
    cmd_base = [ffmpeg_exe, "-y", "-loglevel", "error"]
    
    # Fast Input Seeking for each segment
    for s_start, s_end in segments:
        cmd_base.extend(["-ss", f"{s_start:.3f}", "-to", f"{s_end:.3f}", "-i", video_path])
        
    if teaser_duration_sped > 0:
        teaser_global_start = segments[0][0] + teaser_local_start
        teaser_global_end = segments[0][0] + teaser_local_end
        cmd_base.extend(["-ss", f"{teaser_global_start:.3f}", "-to", f"{teaser_global_end:.3f}", "-i", video_path])
    
    # Background music input if provided
    if music_path and os.path.exists(music_path):
        cmd_base.extend(["-stream_loop", "-1", "-i", music_path])
        
    # Custom logo input if provided
    if has_logo:
        cmd_base.extend(["-i", logo_path])
        
    # B-roll inputs (Phase 8)
    if brolls:
        for br in brolls:
            br_path = br.get("local_path")
            if br_path and os.path.exists(br_path):
                # Loop stock videos to ensure they cover planned overlay duration
                cmd_base.extend(["-stream_loop", "-1", "-i", br_path])
        
    cmd_base.extend([
        "-filter_complex", filter_complex_str,
        "-map", "[v_final]",
        "-map", "[a_final]"
    ])
    _Q_MAP = {"Low": "28", "Medium": "23", "High": "18"}
    val = _Q_MAP.get(export_quality, "22")

    use_nvenc = _has_nvenc()
    
    for attempt in [1, 2]:
        cmd = list(cmd_base)
        if use_nvenc:
            print(f"  [FFMPEG] Attempt {attempt}: Running GPU-accelerated NVENC render...")
            cmd.extend([
                "-c:v", "h264_nvenc",
                "-pix_fmt", "yuv420p",
                "-preset", "p1",  # fastest preset for nvenc
                "-tune", "hq",
                "-b:v", "0",
                "-c:a", "aac",
                "-b:a", "128k",
                output_path
            ])
        else:
            print(f"  [FFMPEG] Attempt {attempt}: Running stable CPU libx264 software render...")
            cmd.extend([
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                "-preset", "superfast",
                "-crf", val,
                "-c:a", "aac",
                "-b:a", "128k",
                output_path
            ])
        
        print(f"  [FFMPEG] Running dynamic render command for clip {clip_index}...")
        process = subprocess.Popen(cmd, stderr=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
        
        import re
        time_regex = re.compile(r"time=(\d+):(\d+):(\d+\.\d+)")
        
        clip_dur = sum(s_end - s_start for s_start, s_end in segments) + teaser_duration_sped
        if clip_dur <= 0.0:
            clip_dur = end_sec - start_sec + teaser_duration_sped
            
        stderr_lines = []
        while True:
            line = process.stderr.readline()
            if not line:
                break
            stderr_lines.append(line)
            
            # Parse time=HH:MM:SS.cs
            match = time_regex.search(line)
            if match:
                h, m, s = match.groups()
                elapsed_sec = int(h) * 3600 + int(m) * 60 + float(s)
                pct = min(100, int((elapsed_sec / clip_dur) * 100))
                print(f"[FFMPEG PROGRESS] clip {clip_index}: {pct}%", flush=True)
                
        process.wait()
        if process.returncode == 0:
            print(f"  [FFMPEG] Attempt {attempt} succeeded!")
            break
        else:
            err = "".join(stderr_lines).strip() or "(no stderr)"
            print(f"  [FFMPEG ERROR] Attempt {attempt} failed (rc={process.returncode})")
            print(f"  [FFMPEG ERROR] {err[:1000]}")
            if use_nvenc:
                print("  [FFMPEG] NVIDIA NVENC GPU encoder failed (VRAM/Session limits reached). Falling back to software libx264 on Attempt 2...")
                use_nvenc = False
            else:
                raise RuntimeError(
                    f"FFmpeg clip {clip_index} failed on all attempts (rc={process.returncode}):\n{err}"
                )

    # ── Post-process: Sound FX mix (whoosh + impact) ───────────────────
    if sound_fx and auto_director and emphasis_timestamps and os.path.exists(output_path):
        try:
            from sounds import build_sfx_mix
            total_ms = int((total_duration + teaser_duration_sped) * 1000)
            
            emph_ms = []
            for s, e in emphasis_timestamps:
                emph_ms.append((
                    int((s + teaser_duration_sped) * 1000),
                    int((e + teaser_duration_sped) * 1000)
                ))
                
            if teaser_duration_sped > 0:
                teaser_trans_ms = int(teaser_duration_sped * 1000)
                emph_ms.append((teaser_trans_ms - 200, teaser_trans_ms + 200))
                if sfx_queries:
                    sfx_queries.append("swoosh transition")
                
            slow_motion_start_ms = 0
            if slow_motion_speed < 1.0 and slow_motion_end > slow_motion_start + 0.1:
                slow_motion_start_ms = int((slow_motion_start + teaser_duration_sped) * 1000)

            sfx_path = build_sfx_mix(
                total_ms,
                emph_ms,
                add_whoosh=True,
                context_queries=sfx_queries,
                content_type=content_type,
                hook_end_ms=int(teaser_duration_sped * 1000) if teaser_duration_sped > 0 else (int(hook_end_sec * 1000) if hook_end_sec > 0.0 else 0),
                sfx_mode=sfx_mode,
                slow_motion_start_ms=slow_motion_start_ms
            )
            if os.path.exists(sfx_path):
                temp_out = output_path.replace(".mp4", "_sfx_temp.mp4")
                sfx_cmd = [
                    ffmpeg_exe, "-y", "-loglevel", "error",
                    "-i", output_path,
                    "-i", sfx_path,
                    "-filter_complex", "[1:a]volume=2.0[sfx];[0:a][sfx]amix=inputs=2:duration=first:dropout_transition=0,volume=1.5[a_mix]",
                    "-map", "0:v", "-map", "[a_mix]",
                    "-c:v", "copy", "-c:a", "aac", "-b:a", "128k",
                    temp_out,
                ]
                result = subprocess.run(sfx_cmd, capture_output=True, text=True)
                if result.returncode != 0:
                    raise RuntimeError(f"SFX mix failed: {result.stderr.strip()}")
                import time
                replaced = False
                for retry in range(6):
                    try:
                        os.replace(temp_out, output_path)
                        replaced = True
                        break
                    except PermissionError:
                        time.sleep(0.5)
                if not replaced:
                    os.replace(temp_out, output_path)  # raise exception on final failure
                
                try:
                    os.remove(sfx_path)
                except Exception:
                    pass
        except Exception as e:
            print(f"  [SFX] Skipped ({e})")


_TRANSITION_MAP = {
    "crossfade": "fade",
    "slide_left": "slideleft",
    "slide_up": "slideup",
    "zoom_in": "zoomin",
    "flash": "fadewhite",
    "fade": "fade",
    "slideleft": "slideleft",
    "slideup": "slideup",
    "zoomin": "zoomin",
    "fadewhite": "fadewhite",
    "dissolve": "dissolve",
    "radial": "radial",
}


def _get_duration(path: str) -> float:
    """Return video duration in seconds using ffprobe."""
    import subprocess
    # Check local bin/ first
    local_bin = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bin")
    ffmpeg = os.path.join(local_bin, "ffmpeg.exe" if os.name == "nt" else "ffmpeg")
    if not os.path.exists(ffmpeg):
        try:
            import imageio_ffmpeg
            ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
        except ImportError:
            ffmpeg = "ffmpeg"
            
    ffprobe = ffmpeg.replace("ffmpeg", "ffprobe")
    if not os.path.isfile(ffprobe):
        ffprobe = "ffprobe"
        
    try:
        result = subprocess.run(
            [ffprobe, "-v", "error", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", path],
            capture_output=True, text=True, timeout=10
        )
        return float(result.stdout.strip())
    except Exception:
        return 0.0


def compile_clips(clip_paths: list, output_path: str,
                  transitions: list = None,
                  transition_duration: float = 0.4,
                  jl_cut: str = "none",
                  export_quality: str = "High"):
    """Concatenate clips with professional transitions (xfade) using FFmpeg.
    jl_cut: "none", "j" (audio leads video), "l" (video leads audio)"""
    import shutil
    if len(clip_paths) == 1:
        shutil.copy2(clip_paths[0], output_path)
        return

    ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()
    for cp in clip_paths:
        if not os.path.exists(cp):
            raise Exception(f"Missing clip: {cp}")

    n = len(clip_paths)
    durations = [_get_duration(p) for p in clip_paths]
    td = max(0.1, min(1.0, transition_duration))

    # Build transition names
    trans_names = []
    for i in range(n - 1):
        raw = (transitions[i] if transitions and i < len(transitions) and transitions[i] else "fade")
        trans_names.append(_TRANSITION_MAP.get(raw, "fade"))

    # xfade offset: offset_i = sum(durations[0..i]) - td * (i+1)
    offsets = []
    running = 0.0
    for i in range(n - 1):
        running += durations[i]
        offsets.append(running - td)

    # Scale all inputs to common dimensions before xfade (fixes size mismatch)
    TARGET_W, TARGET_H = _get_video_dimensions(clip_paths[0])
    scaled = [f"s{i}" for i in range(n)]
    scale_filters = [
        f"[{i}:v]scale={TARGET_W}:{TARGET_H}:flags=bicubic,fps=30,settb=AVTB,setsar=1[{scaled[i]}]"
        for i in range(n)
    ]

    # Video xfade chain on scaled streams
    prev = scaled[0]
    for i in range(1, n):
        out = "outv" if i == n - 1 else f"v{i}"
        scale_filters.append(
            f"[{prev}][{scaled[i]}]xfade=transition={trans_names[i-1]}:duration={td}:offset={offsets[i-1]:.3f}[{out}]"
        )
        prev = out

    filters = scale_filters

    # Audio acrossfade chain: [0:a][1:a]acrossfade=d=td[a1]; [a1][2:a]acrossfade=d=td[outa]
    prev_a = "0:a"
    for i in range(1, n):
        out_a = "outa" if i == n - 1 else f"a{i}"
        filters.append(
            f"[{prev_a}][{i}:a]acrossfade=d={td}[{out_a}]"
        )
        prev_a = out_a

    cmd_base = [ffmpeg_exe, "-y", "-loglevel", "error"]
    for cp in clip_paths:
        cmd_base.extend(["-i", cp])
    cmd_base.extend([
        "-filter_complex", ";".join(filters),
        "-map", "[outv]", "-map", "[outa]"
    ])
    _Q_MAP = {"Low": "28", "Medium": "23", "High": "18"}
    val = _Q_MAP.get(export_quality, "20")

    use_nvenc = _has_nvenc()
    for attempt in [1, 2]:
        cmd = list(cmd_base)
        if use_nvenc:
            print(f"  [FFMPEG] Compile Attempt {attempt}: Running GPU-accelerated NVENC render...")
            cmd.extend([
                "-c:v", "h264_nvenc",
                "-pix_fmt", "yuv420p",
                "-preset", "p1", "-cq", val, "-b:v", "0",
                "-c:a", "aac", "-b:a", "128k",
                output_path,
            ])
        else:
            print(f"  [FFMPEG] Compile Attempt {attempt}: Running stable CPU libx264 software render...")
            cmd.extend([
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                "-preset", "ultrafast", "-crf", val,
                "-c:a", "aac", "-b:a", "128k",
                output_path,
            ])
            
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            print(f"  [FFMPEG] Compile Attempt {attempt} succeeded!")
            break
        else:
            err = result.stderr.strip() or "(no stderr)"
            print(f"  [FFMPEG ERROR] Compile Attempt {attempt} failed (rc={result.returncode})")
            print(f"  [FFMPEG ERROR] {err[:1000]}")
            if use_nvenc:
                print("  [FFMPEG] NVENC failed during compile. Falling back to software libx264 on Attempt 2...")
                use_nvenc = False
            else:
                raise RuntimeError(f"FFmpeg compile failed on all attempts (rc={result.returncode}):\n{err}")


def render_timeline_to_video(timeline: dict, output_path: str, export_quality: str = "High"):
    """
    Renders the TimelineState JSON to a final video file using a dynamic FFmpeg filter complex.
    Supports multi-track layout, positioning, scaling, color grading, keyframes, subtitles, and audio mixing.
    """
    import subprocess
    import imageio_ffmpeg
    from keyframe_engine import generate_ffmpeg_expression

    ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()
    
    # 1. Extract settings
    settings = timeline.get("settings", {})
    width = settings.get("width", 1080)
    height = settings.get("height", 1920)
    fps = settings.get("fps", 30)
    
    tracks = timeline.get("tracks", {})
    video_tracks = tracks.get("video", [])
    audio_tracks = tracks.get("audio", [])
    overlay_tracks = tracks.get("overlays", [])
    subtitle_tracks = tracks.get("subtitles", [])
    
    # Calculate total timeline duration
    duration = 0.0
    for track in video_tracks:
        for clip in track.get("clips", []):
            duration = max(duration, clip.get("end_time_in_timeline", 0.0))
    for track in overlay_tracks:
        for clip in track.get("clips", []):
            duration = max(duration, clip.get("end_time_in_timeline", 0.0))
    
    if duration <= 0:
        duration = 10.0 # fallback

    # Collect unique input media files to map them to FFmpeg input indices
    inputs = []
    def add_input(path):
        if not path:
            return -1
        if path not in inputs:
            inputs.append(path)
        return inputs.index(path)

    # 2. Build FFmpeg Command Base
    cmd_base = [ffmpeg_exe, "-y", "-loglevel", "error"]
    
    # Add input files
    for track in video_tracks:
        for clip in track.get("clips", []):
            add_input(clip.get("source_path"))
    for track in overlay_tracks:
        for clip in track.get("clips", []):
            add_input(clip.get("source_path"))
    for track in audio_tracks:
        for clip in track.get("clips", []):
            add_input(clip.get("source_path"))

    for path in inputs:
        cmd_base.extend(["-i", path])

    filter_complex = []
    
    # Create black background canvas
    filter_complex.append(f"color=c=black:s={width}x{height}:d={duration}:r={fps}[bg_canvas]")
    
    # Process Video Tracks
    canvas_lbl = "[bg_canvas]"
    clip_counter = 0
    
    for track in video_tracks:
        for clip in track.get("clips", []):
            in_idx = add_input(clip.get("source_path"))
            t_start = clip.get("start_time_in_timeline", 0.0)
            t_end = clip.get("end_time_in_timeline", 5.0)
            trim_start = clip.get("source_trim_start", 0.0)
            clip_dur = t_end - t_start
            
            # Trim clip
            lbl_trimmed = f"[v_trim_{clip_counter}]"
            filter_complex.append(f"[{in_idx}:v]trim=start={trim_start}:duration={clip_dur},setpts=PTS-STARTPTS{lbl_trimmed}")
            
            # Color Grading Filter
            lbl_graded = f"[v_grade_{clip_counter}]"
            grade = clip.get("color_grading", {})
            b = grade.get("brightness", 0.0)
            c = grade.get("contrast", 1.0)
            s = grade.get("saturation", 1.0)
            filter_complex.append(f"{lbl_trimmed}eq=brightness={b}:contrast={c}:saturation={s}{lbl_graded}")
            
            # Transform: Scale, position, rotation
            transform = clip.get("transform", {})
            keyframes = transform.get("keyframes", [])
            
            lbl_transformed = f"[v_trans_{clip_counter}]"
            rot_val = transform.get("rotation", 0.0)
            rot_rad = rot_val * 3.14159 / 180.0
            
            scale_x_expr = generate_ffmpeg_expression(keyframes, "scale", transform.get("scale", {}).get("x", 100.0), "x")
            scale_y_expr = generate_ffmpeg_expression(keyframes, "scale", transform.get("scale", {}).get("y", 100.0), "y")
            
            filter_complex.append(
                f"{lbl_graded}scale=w='iw*({scale_x_expr})/100':h='ih*({scale_y_expr})/100',rotate={rot_rad}:ow='rotw({rot_rad})':oh='roth({rot_rad})'{lbl_transformed}"
            )
            
            # Position & Overlay onto current canvas
            pos_x_expr = generate_ffmpeg_expression(keyframes, "position", transform.get("position", {}).get("x", 0.0), "x")
            pos_y_expr = generate_ffmpeg_expression(keyframes, "position", transform.get("position", {}).get("y", 0.0), "y")
            
            next_canvas = f"[bg_v_{clip_counter}]"
            filter_complex.append(
                f"{canvas_lbl}{lbl_transformed}overlay=x='(main_w-overlay_w)/2 + {pos_x_expr}':y='(main_h-overlay_h)/2 + {pos_y_expr}':enable='between(t,{t_start},{t_end})'{next_canvas}"
            )
            canvas_lbl = next_canvas
            clip_counter += 1

    # Process Overlays (B-rolls, image, sticker)
    overlay_counter = 0
    for track in overlay_tracks:
        for clip in track.get("clips", []):
            in_idx = add_input(clip.get("source_path"))
            t_start = clip.get("start_time_in_timeline", 0.0)
            t_end = clip.get("end_time_in_timeline", 5.0)
            trim_start = clip.get("source_trim_start", 0.0)
            clip_dur = t_end - t_start
            
            lbl_trim_ovl = f"[v_trim_ovl_{overlay_counter}]"
            filter_complex.append(f"[{in_idx}:v]trim=start={trim_start}:duration={clip_dur},setpts=PTS-STARTPTS{lbl_trim_ovl}")
            
            lbl_scaled_ovl = f"[v_scale_ovl_{overlay_counter}]"
            transform = clip.get("transform", {})
            scale_x = transform.get("scale", {}).get("x", 100.0)
            scale_y = transform.get("scale", {}).get("y", 100.0)
            filter_complex.append(f"{lbl_trim_ovl}scale=w='iw*{scale_x}/100':h='ih*{scale_y}/100'{lbl_scaled_ovl}")
            
            pos_x = transform.get("position", {}).get("x", 0.0)
            pos_y = transform.get("position", {}).get("y", 0.0)
            
            next_canvas = f"[bg_ovl_{overlay_counter}]"
            filter_complex.append(
                f"{canvas_lbl}{lbl_scaled_ovl}overlay=x='(main_w-overlay_w)/2 + {pos_x}':y='(main_h-overlay_h)/2 + {pos_y}':enable='between(t,{t_start},{t_end})'{next_canvas}"
            )
            canvas_lbl = next_canvas
            overlay_counter += 1

    # Burn subtitles if subtitle clips exist
    ass_path = None
    if subtitle_tracks and subtitle_tracks[0].get("clips"):
        ass_path = output_path.replace(".mp4", "_subs.ass")
        generate_ass_file(subtitle_tracks[0].get("clips"), ass_path)
        
        lbl_subs = "[v_subbed]"
        ass_path_unix = ass_path.replace("\\", "/").replace(":", "\\:")
        filter_complex.append(f"{canvas_lbl}ass='{ass_path_unix}'{lbl_subs}")
        v_final_lbl = lbl_subs
    else:
        v_final_lbl = canvas_lbl

    # Process Audio Tracks & mix
    audio_lbls = []
    
    # 1. Extract voice audio from main video clips
    voice_audio_counter = 0
    for track in video_tracks:
        for clip in track.get("clips", []):
            in_idx = add_input(clip.get("source_path"))
            t_start = clip.get("start_time_in_timeline", 0.0)
            t_end = clip.get("end_time_in_timeline", 5.0)
            trim_start = clip.get("source_trim_start", 0.0)
            clip_dur = t_end - t_start
            
            lbl_voice_a = f"[a_voice_{voice_audio_counter}]"
            filter_complex.append(f"[{in_idx}:a]atrim=start={trim_start}:duration={clip_dur},asetpts=PTS-STARTPTS,adelay={int(t_start*1000)}|{int(t_start*1000)}{lbl_voice_a}")
            audio_lbls.append(lbl_voice_a)
            voice_audio_counter += 1

    # 2. Extract external audio clips
    ext_audio_counter = 0
    for track in audio_tracks:
        for clip in track.get("clips", []):
            in_idx = add_input(clip.get("source_path"))
            t_start = clip.get("start_time_in_timeline", 0.0)
            t_end = clip.get("end_time_in_timeline", 5.0)
            trim_start = clip.get("source_trim_start", 0.0)
            clip_dur = t_end - t_start
            
            lbl_ext_a = f"[a_ext_{ext_audio_counter}]"
            filter_complex.append(f"[{in_idx}:a]atrim=start={trim_start}:duration={clip_dur},asetpts=PTS-STARTPTS,volume={clip.get('volume', 1.0)},adelay={int(t_start*1000)}|{int(t_start*1000)}{lbl_ext_a}")
            audio_lbls.append(lbl_ext_a)
            ext_audio_counter += 1

    # Mix all audio inputs together
    if audio_lbls:
        if len(audio_lbls) == 1:
            filter_complex.append(f"{audio_lbls[0]}volume=1.0[a_final]")
        else:
            inputs_str = "".join(audio_lbls)
            filter_complex.append(f"{inputs_str}amix=inputs={len(audio_lbls)}:duration=longest[a_final]")
    else:
        filter_complex.append(f"anullsrc=r=44100:cl=stereo:d={duration}[a_final]")

    # Append filter complex to command
    cmd_base.extend([
        "-filter_complex", ";".join(filter_complex),
        "-map", v_final_lbl,
        "-map", "[a_final]"
    ])

    _Q_MAP = {"Low": "28", "Medium": "23", "High": "18"}
    val = _Q_MAP.get(export_quality, "20")

    use_nvenc = _has_nvenc()
    cmd = list(cmd_base)
    if use_nvenc:
        cmd.extend([
            "-c:v", "h264_nvenc", "-pix_fmt", "yuv420p", "-preset", "p1", "-cq", val, "-b:v", "0",
            "-c:a", "aac", "-b:a", "128k", output_path
        ])
    else:
        cmd.extend([
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "ultrafast", "-crf", val,
            "-c:a", "aac", "-b:a", "128k", output_path
        ])

    print(f"  [FFMPEG NLE] Running timeline render...")
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    # Clean up ASS file
    if ass_path and os.path.exists(ass_path):
        try:
            os.remove(ass_path)
        except Exception:
            pass

    if result.returncode != 0:
        raise RuntimeError(f"Timeline FFmpeg render failed: {result.stderr.strip()}")
    print("  [FFMPEG NLE] Render completed successfully!")


def generate_ass_file(clips: list, output_path: str):
    """Generates an ASS subtitle file from SubtitleClips list."""
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("[Script Info]\nTitle: ClipAI Pro NLE Subs\nScriptType: v4.00+\nPlayResX: 1080\nPlayResY: 1920\n\n")
        f.write("[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n")
        f.write("Style: Default,Impact,48,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,1,0,0,0,100,100,0,0,1,2,0,2,10,10,150,1\n\n")
        f.write("[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n")
        
        def format_ass_time(secs):
            h = int(secs // 3600)
            m = int((secs % 3600) // 60)
            s = int(secs % 60)
            cs = int((secs % 1) * 100)
            return f"{h}:{m:02d}:{s:02d}.{cs:02d}"

        for clip in clips:
            s_val = clip.get("start_time", 0.0)
            e_val = clip.get("end_time", 0.0)
            duration = e_val - s_val
            
            start = format_ass_time(s_val)
            end = format_ass_time(e_val)
            text = clip.get("text", "")
            
            # Context-Aware Subtitles animation & color based on length
            if duration > 0.6:
                color_tag = "{\\c&H24BFFB&}" # Amber (BGR: fbbf24)
            elif duration < 0.15:
                color_tag = "{\\c&HB8A394&}" # Slate (BGR: 94a3b8)
            else:
                color_tag = "{\\c&HFFFFFF&}"
            
            # Pop-in animation (starts at 120% scale, shrinks to 100% in 150ms)
            anim_tag = "{\\fscx130\\fscy130\\t(0,150,\\fscx100\\fscy100)}"
            
            f.write(f"Dialogue: 0,{start},{end},Default,,0,0,0,,{anim_tag}{color_tag}{text}\n")
