"""
ai_orchestrator.py — Tool Execution Engine (Phase 0.3)
======================================================
Receives a list of validated tool calls from the AI Copilot and
executes them against the timeline state, returning the new state.
"""

import os
import json
import uuid
import re
from typing import List, Dict, Any, Optional, Tuple
from tool_registry import get_tool


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def get_clip_by_id(tracks: List[Dict[str, Any]], clip_id: str) -> Optional[Dict[str, Any]]:
    for track in tracks:
        for clip in track.get("clips", []):
            if clip.get("id") == clip_id:
                return clip
    return None


def get_track_by_id(tracks: List[Dict[str, Any]], track_id: str) -> Optional[Dict[str, Any]]:
    for track in tracks:
        if track.get("id") == track_id:
            return track
    return None


def _remove_clip(tracks: List[Dict[str, Any]], clip_id: str) -> bool:
    for track in tracks:
        clips = track.get("clips", [])
        for i, c in enumerate(clips):
            if c.get("id") == clip_id:
                clips.pop(i)
                return True
    return False


def _find_track_of_clip(tracks: List[Dict[str, Any]], clip_id: str) -> Optional[Dict[str, Any]]:
    for t in tracks:
        for c in t.get("clips", []):
            if c.get("id") == clip_id:
                return t
    return None


# ─────────────────────────────────────────────────────────────────────────────
# Timeline handlers (40 tools)
# ─────────────────────────────────────────────────────────────────────────────

def handle_timeline(name: str, args: Dict[str, Any], state: Dict[str, Any]) -> Tuple[bool, str, Dict[str, Any]]:
    tracks = state.get("tracks", [])
    patch: Dict[str, Any] = {}
    ct = state.get("currentTime", 0.0)

    if name == "timeline.split_clip":
        clip_id = args.get("clip_id")
        t = float(args.get("time", ct))
        clip = get_clip_by_id(tracks, clip_id)
        if not clip: return False, f"Clip not found: {clip_id}", patch
        s, e = clip.get("start_time_in_timeline", 0), clip.get("end_time_in_timeline", 0)
        if t <= s or t >= e:
            return False, f"Split time {t:.1f}s outside clip {s:.1f}-{e:.1f}s", patch
        new_clip = {**clip, "id": str(uuid.uuid4()), "start_time_in_timeline": t, "end_time_in_timeline": e}
        clip["end_time_in_timeline"] = t
        for track in tracks:
            if any(c.get("id") == clip_id for c in track.get("clips", [])):
                track.setdefault("clips", []).append(new_clip)
                break
        patch["tracks"] = tracks
        return True, f"✂️ Split at {t:.1f}s", patch

    if name == "timeline.delete_clip":
        if _remove_clip(tracks, args.get("clip_id")):
            patch["tracks"] = tracks
            return True, "🗑️ Deleted clip", patch
        return False, "Clip not found", patch

    if name == "timeline.ripple_delete":
        cid = args.get("clip_id")
        clip = get_clip_by_id(tracks, cid)
        if not clip: return False, "Clip not found", patch
        s, e = clip.get("start_time_in_timeline", 0), clip.get("end_time_in_timeline", 0)
        dur = e - s
        track = _find_track_of_clip(tracks, cid)
        if _remove_clip(tracks, cid):
            if track:
                for c in track.get("clips", []):
                    if c.get("start_time_in_timeline", 0) >= s:
                        c["start_time_in_timeline"] -= dur
                        c["end_time_in_timeline"] -= dur
            patch["tracks"] = tracks
            return True, "🗑️ Ripple delete (gap closed)", patch
        return False, "Clip not found", patch

    if name == "timeline.lift_clip":
        if _remove_clip(tracks, args.get("clip_id")):
            patch["tracks"] = tracks
            return True, "⬆️ Lifted clip (gap remains)", patch
        return False, "Clip not found", patch

    if name == "timeline.extract_clip":
        return handle_timeline("timeline.ripple_delete", args, state)

    if name == "timeline.razor_at_playhead":
        cnt = 0
        for track in tracks:
            for clip in list(track.get("clips", [])):
                s, e = clip.get("start_time_in_timeline", 0), clip.get("end_time_in_timeline", 0)
                if s < ct < e:
                    new_clip = {**clip, "id": str(uuid.uuid4()), "start_time_in_timeline": ct, "end_time_in_timeline": e}
                    clip["end_time_in_timeline"] = ct
                    track.setdefault("clips", []).append(new_clip)
                    cnt += 1
        patch["tracks"] = tracks
        return True, f"✂️ Razor: cut {cnt} clips at {ct:.1f}s", patch

    if name == "timeline.set_zoom_level":
        p = max(5.0, min(120.0, float(args.get("pixels_per_second", 50))))
        patch["zoomLevel"] = p
        return True, f"🔍 Zoom: {p:.0f}px/s", patch

    if name == "timeline.zoom_to_fit":
        max_end = max((c.get("end_time_in_timeline", 0) for t in tracks for c in t.get("clips", [])), default=0)
        patch["zoomLevel"] = 50.0
        return True, f"🔍 Fit zoom (duration {max_end:.1f}s)", patch

    if name == "timeline.set_in_point":
        patch["inPoint"] = float(args.get("time", ct))
        return True, f"⬅️ In: {patch['inPoint']:.1f}s", patch

    if name == "timeline.set_out_point":
        patch["outPoint"] = float(args.get("time", ct))
        return True, f"➡️ Out: {patch['outPoint']:.1f}s", patch

    if name == "timeline.mark_in_out":
        patch["inPoint"] = float(args.get("in_time", ct))
        patch["outPoint"] = float(args.get("out_time", ct + 5))
        return True, "📍 In/Out marked", patch

    if name == "timeline.toggle_magnetic":
        patch["magneticEnabled"] = bool(args.get("enabled", True))
        return True, f"🧲 Magnetic: {patch['magneticEnabled']}", patch

    if name == "timeline.set_snap_mode":
        mode = str(args.get("mode", "off"))
        if mode not in ("off", "playhead", "clips", "grid"):
            return False, f"Unknown snap mode: {mode}", patch
        patch["snapMode"] = mode
        return True, f"🧲 Snap: {mode}", patch

    if name == "timeline.lock_track":
        t = get_track_by_id(tracks, args.get("track_id"))
        if not t: return False, "Track not found", patch
        t["locked"] = bool(args.get("locked", True))
        return True, f"🔒 Track locked: {t.get('locked')}", patch

    if name == "timeline.hide_track":
        t = get_track_by_id(tracks, args.get("track_id"))
        if not t: return False, "Track not found", patch
        t["hidden"] = bool(args.get("hidden", True))
        return True, f"👁️ Track hidden: {t.get('hidden')}", patch

    if name == "timeline.solo_track":
        sid = args.get("track_id")
        solo = bool(args.get("enabled", args.get("soloed", True)))
        for t in tracks:
            t["solo"] = (t.get("id") == sid and solo)
        patch["tracks"] = tracks
        return True, f"🎯 Solo: {sid}", patch

    if name == "timeline.rename_track":
        t = get_track_by_id(tracks, args.get("track_id"))
        if not t: return False, "Track not found", patch
        t["name"] = str(args.get("name", ""))
        return True, f"✏️ Renamed track", patch

    if name == "timeline.reorder_tracks":
        tid = args.get("track_id")
        ni = int(args.get("new_index", 0))
        t = get_track_by_id(tracks, tid)
        if not t: return False, "Track not found", patch
        tracks.remove(t)
        ni = max(0, min(ni, len(tracks)))
        tracks.insert(ni, t)
        patch["tracks"] = tracks
        return True, f"↕️ Reordered to {ni}", patch

    if name == "timeline.replace_clip":
        cid = args.get("clip_id")
        np = str(args.get("new_source_path", ""))
        clip = get_clip_by_id(tracks, cid)
        if not clip: return False, "Clip not found", patch
        clip["path"] = np
        clip["source_path"] = np
        return True, "🔄 Replaced source", patch

    if name == "timeline.slip_clip":
        cid = args.get("clip_id")
        d = float(args.get("delta_seconds", 0))
        clip = get_clip_by_id(tracks, cid)
        if not clip: return False, "Clip not found", patch
        clip["source_in"] = clip.get("source_in", 0) + d
        return True, f"↔️ Slip {d:+.1f}s", patch

    if name == "timeline.slide_clip":
        cid = args.get("clip_id")
        d = float(args.get("delta_seconds", 0))
        clip = get_clip_by_id(tracks, cid)
        if not clip: return False, "Clip not found", patch
        clip["start_time_in_timeline"] = clip.get("start_time_in_timeline", 0) + d
        clip["end_time_in_timeline"] = clip.get("end_time_in_timeline", 0) + d
        return True, f"↔️ Slide {d:+.1f}s", patch

    if name == "timeline.freeze_frame":
        t = float(args.get("time", ct))
        dur = float(args.get("duration", args.get("duration_seconds", 3.0)))
        new_clip = {
            "id": str(uuid.uuid4()),
            "name": f"Freeze {t:.1f}s",
            "start_time_in_timeline": t,
            "end_time_in_timeline": t + dur,
            "type": "freeze_frame",
        }
        for track in tracks:
            if "v" in track.get("id", "").lower() or track.get("type") == "video":
                track.setdefault("clips", []).append(new_clip)
                patch["tracks"] = tracks
                return True, f"❄️ Freeze frame @ {t:.1f}s ({dur}s)", patch
        return False, "No video track", patch

    if name == "timeline.reverse_clip":
        cid = args.get("clip_id")
        clip = get_clip_by_id(tracks, cid)
        if not clip: return False, "Clip not found", patch
        clip["reversed"] = not clip.get("reversed", False)
        return True, f"🔁 Reversed: {clip['reversed']}", patch

    if name == "timeline.top_and_tail":
        cid = args.get("clip_id")
        head = float(args.get("head_seconds", 0))
        tail = float(args.get("tail_seconds", 0))
        clip = get_clip_by_id(tracks, cid)
        if not clip: return False, "Clip not found", patch
        clip["start_time_in_timeline"] = clip.get("start_time_in_timeline", 0) + head
        clip["end_time_in_timeline"] = clip.get("end_time_in_timeline", 0) - tail
        return True, f"✂️ Top&tail ({head}s, {tail}s)", patch

    if name == "timeline.group_clips":
        cids = args.get("clip_ids", [])
        gid = args.get("group_id", str(uuid.uuid4()))
        for track in tracks:
            for clip in track.get("clips", []):
                if clip.get("id") in cids:
                    clip["group_id"] = gid
        patch["tracks"] = tracks
        return True, f"📦 Grouped {len(cids)} clips", patch

    if name == "timeline.ungroup_clips":
        gid = args.get("group_id")
        for track in tracks:
            for clip in track.get("clips", []):
                if clip.get("group_id") == gid:
                    clip.pop("group_id", None)
        patch["tracks"] = tracks
        return True, "📤 Ungrouped", patch

    if name == "timeline.add_marker":
        markers = state.get("markers", [])
        markers.append({
            "id": str(uuid.uuid4()),
            "time": float(args.get("time", ct)),
            "color": str(args.get("color", "yellow")),
            "name": str(args.get("name", "Marker")),
            "comment": str(args.get("comment", "")),
        })
        patch["markers"] = markers
        return True, "🚩 Marker added", patch

    if name == "timeline.add_chapter_marker":
        markers = state.get("markers", [])
        markers.append({
            "id": str(uuid.uuid4()),
            "time": float(args.get("time", ct)),
            "color": "blue",
            "name": str(args.get("chapter_name", args.get("name", "Chapter"))),
            "type": "chapter",
        })
        patch["markers"] = markers
        return True, "📑 Chapter marker added", patch

    if name == "timeline.set_region_of_interest":
        patch["roi"] = {
            "start": float(args.get("start", 0)),
            "end": float(args.get("end", 10)),
            "color": str(args.get("color", "yellow")),
        }
        return True, "🔍 ROI set", patch

    if name == "timeline.take_snapshot":
        return True, "📸 Snapshot", patch

    if name == "timeline.three_point_edit":
        in_t = float(args.get("in_time", 0))
        out_t = float(args.get("out_time", 5))
        target = get_track_by_id(tracks, args.get("target_track_id"))
        if not target:
            for t in tracks:
                if "v" in t.get("id", "").lower():
                    target = t
                    break
        if not target: return False, "No target track", patch
        new_clip = {
            "id": str(uuid.uuid4()),
            "name": f"3pt {in_t:.1f}-{out_t:.1f}s",
            "start_time_in_timeline": ct,
            "end_time_in_timeline": ct + (out_t - in_t),
            "source_in": in_t,
            "source_out": out_t,
        }
        target.setdefault("clips", []).append(new_clip)
        patch["tracks"] = tracks
        return True, f"3-point edit placed @ {ct:.1f}s", patch

    if name == "timeline.create_nested_sequence":
        nm = str(args.get("name", "Nested"))
        cids = args.get("clip_ids", [])
        sid = str(uuid.uuid4())
        for track in tracks:
            for clip in track.get("clips", []):
                if clip.get("id") in cids:
                    clip["nested_sequence_id"] = sid
        seqs = state.get("nested_sequences", [])
        seqs.append({"id": sid, "name": nm, "clip_ids": cids})
        patch["nested_sequences"] = seqs
        patch["tracks"] = tracks
        return True, f"📁 Nested sequence '{nm}'", patch

    if name == "timeline.add_adjustment_layer":
        t = get_track_by_id(tracks, args.get("track_id"))
        if not t: return False, "Track not found", patch
        t["adjustment_layer"] = True
        return True, "🎚️ Adjustment layer added", patch

    if name == "timeline.sync_lock":
        t = get_track_by_id(tracks, args.get("track_id"))
        if not t: return False, "Track not found", patch
        t["sync_lock"] = bool(args.get("enabled", True))
        return True, f"🔗 Sync lock: {t['sync_lock']}", patch

    if name == "timeline.linked_selection":
        patch["linkedSelection"] = bool(args.get("enabled", True))
        return True, f"🔗 Linked selection: {patch['linkedSelection']}", patch

    if name == "timeline.fix_audio_drift":
        return True, "🔧 Audio drift fix requested", patch

    if name == "timeline.time_remap":
        cid = args.get("clip_id")
        kf = args.get("keyframes", [])
        clip = get_clip_by_id(tracks, cid)
        if not clip: return False, "Clip not found", patch
        clip["time_remap"] = kf
        return True, f"⏱️ Time remap: {len(kf)} keyframes", patch

    if name == "timeline.insert_edit":
        patch["editMode"] = "insert"
        return True, "↪️ Insert mode", patch

    if name == "timeline.overwrite_edit":
        patch["editMode"] = "overwrite"
        return True, "↩️ Overwrite mode", patch

    if name == "timeline.render_preview_region":
        return True, "🎞️ Preview render requested", patch

    return False, f"Unknown timeline tool: {name}", patch


# ─────────────────────────────────────────────────────────────────────────────
# Playback handlers (25 tools)
# ─────────────────────────────────────────────────────────────────────────────

def handle_playback(name: str, args: Dict[str, Any], state: Dict[str, Any]) -> Tuple[bool, str, Dict[str, Any]]:
    patch: Dict[str, Any] = {}
    ct = state.get("currentTime", 0.0)
    fps = state.get("fps", 30)

    if name == "playback.play":
        patch["isPlaying"] = True
        return True, "▶️ Play", patch
    if name == "playback.pause":
        patch["isPlaying"] = False
        return True, "⏸️ Pause", patch
    if name == "playback.toggle_play":
        patch["isPlaying"] = not state.get("isPlaying", False)
        return True, f"{'▶️' if patch['isPlaying'] else '⏸️'} Toggled", patch
    if name == "playback.seek":
        t = max(0.0, float(args.get("time", 0)))
        patch["currentTime"] = t
        return True, f"⏩ Seek to {t:.1f}s", patch
    if name == "playback.frame_step_forward":
        patch["currentTime"] = ct + 1.0 / fps
        return True, "➡️ +1 frame", patch
    if name == "playback.frame_step_backward":
        patch["currentTime"] = max(0.0, ct - 1.0 / fps)
        return True, "⬅️ -1 frame", patch
    if name == "playback.skip_forward_5s":
        patch["currentTime"] = ct + 5.0
        return True, "⏩ +5s", patch
    if name == "playback.skip_backward_5s":
        patch["currentTime"] = max(0.0, ct - 5.0)
        return True, "⏪ -5s", patch
    if name == "playback.toggle_loop":
        patch["loop"] = not state.get("loop", False)
        return True, f"🔁 Loop: {patch['loop']}", patch
    if name == "playback.set_aspect_ratio":
        ratio = str(args.get("ratio", "16:9"))
        if ratio not in ("9:16", "16:9", "1:1", "4:5", "2.39:1", "21:9"):
            return False, f"Aspect ratio not supported: {ratio}", patch
        patch["aspectRatio"] = ratio
        return True, f"📐 Aspect: {ratio}", patch
    if name == "playback.set_fit_mode":
        mode = str(args.get("mode", "fit"))
        if mode not in ("fit", "fill"):
            return False, f"Unknown fit mode: {mode}", patch
        patch["fitMode"] = mode
        return True, f"🖼️ Fit: {mode}", patch
    if name == "playback.toggle_fullscreen":
        patch["fullscreen"] = not state.get("fullscreen", False)
        return True, f"⛶ Fullscreen: {patch['fullscreen']}", patch
    if name == "playback.toggle_mute":
        patch["muted"] = not state.get("muted", False)
        return True, f"🔇 Muted: {patch['muted']}", patch
    if name == "playback.set_volume":
        v = max(0.0, min(100.0, float(args.get("volume", 100))))
        patch["volume"] = v
        return True, f"🔊 Volume: {v:.0f}%", patch
    if name == "playback.toggle_safe_area":
        patch["safeArea"] = not state.get("safeArea", False)
        return True, f"📏 Safe area: {patch['safeArea']}", patch
    if name == "playback.toggle_grid_overlay":
        patch["gridOverlay"] = not state.get("gridOverlay", False)
        return True, f"▦ Grid: {patch['gridOverlay']}", patch
    if name == "playback.set_timecode_format":
        patch["timecodeFormat"] = str(args.get("format", "ndf"))
        patch["fps"] = int(args.get("fps", 30))
        return True, f"⏱️ TC: {patch['timecodeFormat']} {patch['fps']}fps", patch
    if name == "playback.toggle_waveform_overlay":
        patch["waveformOverlay"] = not state.get("waveformOverlay", False)
        return True, f"📊 Waveform: {patch['waveformOverlay']}", patch
    if name == "playback.toggle_zebra":
        patch["zebra"] = not state.get("zebra", False)
        return True, f"🦓 Zebra: {patch['zebra']}", patch
    if name == "playback.toggle_focus_peaking":
        patch["focusPeaking"] = not state.get("focusPeaking", False)
        return True, f"🎯 Focus peaking: {patch['focusPeaking']}", patch
    if name == "playback.toggle_false_color":
        patch["falseColor"] = not state.get("falseColor", False)
        return True, f"🌈 False color: {patch['falseColor']}", patch
    if name == "playback.zoom_canvas":
        z = max(1.0, min(10.0, float(args.get("zoom", 1.0))))
        patch["canvasZoom"] = z
        return True, f"🔍 Canvas zoom: {z:.1f}x", patch
    if name == "playback.eyedropper":
        return True, "💧 Eyedropper activated", patch
    if name == "playback.jog_mode":
        patch["jogMode"] = True
        return True, "🎚️ Jog mode", patch
    if name == "playback.ab_compare":
        patch["abCompare"] = {"clip_a": args.get("clip_a"), "clip_b": args.get("clip_b")}
        return True, "🔀 A/B compare", patch

    return False, f"Unknown playback tool: {name}", patch


# ─────────────────────────────────────────────────────────────────────────────
# Effects handlers (35 tools)
# ─────────────────────────────────────────────────────────────────────────────

def handle_effects(name: str, args: Dict[str, Any], state: Dict[str, Any]) -> Tuple[bool, str, Dict[str, Any]]:
    tracks = state.get("tracks", [])
    cid = args.get("clip_id") or state.get("selectedClipId")
    if not cid: return False, "No clip selected", {}
    clip = get_clip_by_id(tracks, cid)
    if not clip: return False, f"Clip not found: {cid}", {}
    effects = clip.setdefault("effects", {})

    # Direct setters
    setter_map = {
        "effects.set_brightness": ("brightness", float),
        "effects.set_contrast": ("contrast", float),
        "effects.set_saturation": ("saturation", float),
        "effects.set_opacity": ("opacity", float),
        "effects.set_exposure": ("exposure", float),
        "effects.set_temperature": ("temperature", float),
    }
    if name in setter_map:
        key, transform = setter_map[name]
        arg_key = name.replace("effects.set_", "")
        try:
            effects[key] = transform(args.get(arg_key, 0))
        except (ValueError, TypeError):
            return False, f"Invalid value for {key}", {}
        return True, f"{key} = {effects[key]}", {}

    if name == "effects.apply_lut":
        effects["lut"] = {
            "path": str(args.get("lut_path", "")),
            "intensity": float(args.get("intensity", 1.0)),
        }
        return True, f"🎨 LUT applied: {os.path.basename(effects['lut']['path'])}", {}

    if name == "effects.remove_lut":
        effects.pop("lut", None)
        return True, "🎨 LUT removed", {}

    if name == "effects.apply_blur":
        effects["blur"] = float(args.get("amount", args.get("radius", 5.0)))
        return True, f"💨 Blur: {effects['blur']}", {}

    if name == "effects.apply_sharpen":
        effects["sharpen"] = float(args.get("amount", 0.5))
        return True, f"🔪 Sharpen: {effects['sharpen']}", {}

    if name == "effects.apply_vignette":
        effects["vignette"] = float(args.get("amount", 0.5))
        return True, f"🌑 Vignette: {effects['vignette']}", {}

    if name == "effects.apply_film_grain":
        effects["grain"] = float(args.get("amount", 0.3))
        return True, f"🎞️ Film grain: {effects['grain']}", {}

    if name == "effects.apply_vhs":
        effects["vhs"] = float(args.get("intensity", 0.5))
        return True, f"📼 VHS effect", {}

    if name == "effects.apply_glow":
        effects["glow"] = float(args.get("intensity", 0.5))
        return True, f"✨ Glow", {}

    if name == "effects.apply_chromatic_aberration":
        effects["chromatic"] = float(args.get("amount", 0.5))
        return True, f"🌈 Chromatic aberration", {}

    if name == "effects.apply_lens_flare":
        effects["lens_flare"] = float(args.get("intensity", 0.5))
        return True, f"💡 Lens flare", {}

    if name == "effects.apply_lens_distortion":
        effects["lens_distortion"] = float(args.get("amount", 0.5))
        return True, f"🔍 Lens distortion", {}

    if name == "effects.apply_motion_blur":
        effects["motion_blur"] = float(args.get("intensity", 0.5))
        return True, f"💨 Motion blur", {}

    if name == "effects.apply_film_burn":
        effects["film_burn"] = float(args.get("intensity", 0.5))
        return True, f"🔥 Film burn", {}

    if name == "effects.apply_light_leak":
        effects["light_leak"] = float(args.get("intensity", 0.5))
        return True, f"💡 Light leak", {}

    if name == "effects.apply_pixelate":
        effects["pixelate"] = int(args.get("size", 10))
        return True, f"🟦 Pixelate: {effects['pixelate']}", {}

    if name == "effects.apply_datamosh":
        effects["datamosh"] = float(args.get("intensity", 0.5))
        return True, f"📺 Datamosh", {}

    if name == "effects.add_mask":
        effects["mask"] = {
            "type": str(args.get("type", "circle")),
            "x": float(args.get("x", 0.5)),
            "y": float(args.get("y", 0.5)),
            "size": float(args.get("size", 0.5)),
        }
        return True, f"🎭 Mask: {effects['mask']['type']}", {}

    if name == "effects.add_opacity_keyframe":
        keyframes = effects.setdefault("opacity_keyframes", [])
        keyframes.append({
            "time": float(args.get("time", state.get("currentTime", 0))),
            "opacity": float(args.get("opacity", 1.0)),
        })
        return True, f"🔑 Opacity keyframe", {}

    if name == "effects.add_transform_keyframe":
        keyframes = effects.setdefault("transform_keyframes", [])
        keyframes.append({
            "time": float(args.get("time", state.get("currentTime", 0))),
            "x": float(args.get("x", 0)),
            "y": float(args.get("y", 0)),
            "scale": float(args.get("scale", 1.0)),
            "rotation": float(args.get("rotation", 0)),
        })
        return True, f"🔑 Transform keyframe", {}

    if name == "effects.set_blend_mode":
        effects["blend_mode"] = str(args.get("mode", "normal"))
        return True, f"🌀 Blend: {effects['blend_mode']}", {}

    if name == "effects.set_crop":
        effects["crop"] = {
            "left": float(args.get("left", 0)),
            "right": float(args.get("right", 0)),
            "top": float(args.get("top", 0)),
            "bottom": float(args.get("bottom", 0)),
        }
        return True, f"✂️ Crop set", {}

    if name == "effects.set_curves":
        effects["curves"] = {
            "points": args.get("points", []),
            "channel": str(args.get("channel", "rgb")),
        }
        return True, "📈 Curves set", {}

    if name == "effects.hsl_qualifier":
        effects["hsl_qualifier"] = {
            "hue": float(args.get("hue", 0)),
            "saturation": float(args.get("saturation", 0.5)),
            "luminance": float(args.get("luminance", 0.5)),
        }
        return True, "🎨 HSL qualifier set", {}

    if name == "effects.set_position_transform":
        effects["transform"] = {
            "x": float(args.get("x", 0)),
            "y": float(args.get("y", 0)),
            "scale": float(args.get("scale", 1.0)),
            "rotation": float(args.get("rotation", 0)),
        }
        return True, "↔️ Transform set", {}

    if name == "effects.reset_color":
        for k in ("brightness", "contrast", "saturation", "exposure", "temperature", "lut", "curves", "hsl_qualifier"):
            effects.pop(k, None)
        return True, "🎨 Color reset", {}

    if name == "effects.reset_transform":
        for k in ("transform", "position", "scale", "rotation", "opacity", "opacity_keyframes", "transform_keyframes"):
            effects.pop(k, None)
        return True, "↔️ Transform reset", {}

    if name == "effects.copy_effects":
        target = get_clip_by_id(tracks, args.get("target_clip_id") or args.get("to_clip_id"))
        if target:
            target["effects"] = json.loads(json.dumps(effects))
            return True, "📋 Effects copied", {}
        return False, "Target clip not found", {}

    if name == "effects.auto_color_match":
        effects["auto_match"] = True
        return True, "🎨 Auto color match", {}

    if name == "effects.warp_stabilize":
        effects["stabilized"] = float(args.get("smoothness", 0.5))
        return True, "🎯 Stabilized", {}

    return False, f"Unknown effects tool: {name}", {}


# ─────────────────────────────────────────────────────────────────────────────
# Audio handlers (25 tools)
# ─────────────────────────────────────────────────────────────────────────────

def handle_audio(name: str, args: Dict[str, Any], state: Dict[str, Any]) -> Tuple[bool, str, Dict[str, Any]]:
    tracks = state.get("tracks", [])
    audio_settings = state.setdefault("audio_settings", {})

    if name == "audio.adjust_volume":
        v = max(0.0, min(2.0, float(args.get("volume", 1.0))))
        track_id = args.get("track_id")
        if track_id:
            t = get_track_by_id(tracks, track_id)
            if t:
                t["volume"] = v
                return True, f"🔊 Track volume: {v}", {"tracks": tracks}
            return False, "Track not found", {}
        audio_settings["volume"] = v
        return True, f"🔊 Volume: {v}", {"audio_settings": audio_settings}

    if name == "audio.apply_eq":
        audio_settings["eq"] = {
            "low": float(args.get("low", 0)),
            "mid": float(args.get("mid", 0)),
            "high": float(args.get("high", 0)),
        }
        return True, "🎚️ EQ applied", {"audio_settings": audio_settings}

    if name == "audio.apply_compressor":
        audio_settings["compressor"] = {
            "threshold": float(args.get("threshold", -20)),
            "ratio": float(args.get("ratio", 4)),
            "attack": float(args.get("attack", 0.01)),
            "release": float(args.get("release", 0.1)),
        }
        return True, "🎛️ Compressor", {"audio_settings": audio_settings}

    if name == "audio.apply_limiter":
        audio_settings["limiter"] = {
            "ceiling": float(args.get("ceiling", -1)),
            "release": float(args.get("release", 0.05)),
        }
        return True, "🔊 Limiter", {"audio_settings": audio_settings}

    if name == "audio.apply_reverb":
        audio_settings["reverb"] = {
            "amount": float(args.get("amount", 0.3)),
            "size": float(args.get("size", 0.5)),
        }
        return True, "🌊 Reverb", {"audio_settings": audio_settings}

    if name == "audio.apply_delay":
        audio_settings["delay"] = {
            "time": float(args.get("time", 0.25)),
            "feedback": float(args.get("feedback", 0.3)),
        }
        return True, "🔁 Delay", {"audio_settings": audio_settings}

    if name == "audio.apply_de_esser":
        audio_settings["de_esser"] = {
            "frequency": float(args.get("frequency", 6000)),
            "amount": float(args.get("amount", 0.5)),
        }
        return True, "🎙️ De-esser", {"audio_settings": audio_settings}

    if name == "audio.normalize_loudness":
        audio_settings["normalized"] = True
        audio_settings["target_lufs"] = float(args.get("target_lufs", -14))
        return True, "🔊 Normalized", {"audio_settings": audio_settings}

    if name == "audio.noise_reduction":
        audio_settings["noise_reduction"] = {
            "amount": float(args.get("amount", 0.5)),
            "profile": str(args.get("profile", "broadband")),
        }
        return True, "🔇 Noise reduced", {"audio_settings": audio_settings}

    if name == "audio.ducking":
        audio_settings["ducking"] = {
            "amount": float(args.get("amount", 0.5)),
            "target": str(args.get("target", "music")),
        }
        return True, "🎚️ Ducking", {"audio_settings": audio_settings}

    if name == "audio.set_fade_in":
        cid = args.get("clip_id")
        dur = float(args.get("duration", 1.0))
        if cid:
            clip = get_clip_by_id(tracks, cid)
            if clip: clip["fade_in"] = dur
        audio_settings["fade_in"] = dur
        return True, f"🔊 Fade in: {dur}s", {"audio_settings": audio_settings}

    if name == "audio.set_fade_out":
        cid = args.get("clip_id")
        dur = float(args.get("duration", 1.0))
        if cid:
            clip = get_clip_by_id(tracks, cid)
            if clip: clip["fade_out"] = dur
        audio_settings["fade_out"] = dur
        return True, f"🔊 Fade out: {dur}s", {"audio_settings": audio_settings}

    if name == "audio.apply_crossfade":
        audio_settings["crossfade"] = float(args.get("duration", 0.5))
        return True, f"🔀 Crossfade: {audio_settings['crossfade']}s", {"audio_settings": audio_settings}

    if name == "audio.pitch_shift":
        audio_settings["pitch"] = float(args.get("semitones", 0))
        return True, f"🎵 Pitch: {audio_settings['pitch']} semitones", {"audio_settings": audio_settings}

    if name == "audio.time_stretch":
        audio_settings["time_stretch"] = float(args.get("factor", 1.0))
        return True, f"⏱️ Time stretch: {audio_settings['time_stretch']}x", {"audio_settings": audio_settings}

    if name == "audio.detect_beats":
        patch = {"audioJob": {"type": "detect_beats"}}
        return True, "🥁 Detect beats", patch

    if name == "audio.detect_key":
        patch = {"audioJob": {"type": "detect_key"}}
        return True, "🎵 Detect key", patch

    if name == "audio.separate_stems":
        patch = {"audioJob": {"type": "separate_stems"}}
        return True, "🎚️ Separate stems", patch

    if name == "audio.voice_isolation":
        patch = {"audioJob": {"type": "voice_isolation"}}
        return True, "🎤 Voice isolation", patch

    if name == "audio.vocal_clone":
        patch = {"audioJob": {"type": "vocal_clone"}}
        return True, "🎙️ Vocal clone", patch

    if name == "audio.auto_gain":
        audio_settings["auto_gain"] = True
        return True, "🔊 Auto gain", {"audio_settings": audio_settings}

    if name == "audio.de_clip":
        audio_settings["de_clip"] = True
        return True, "🔧 De-clip", {"audio_settings": audio_settings}

    if name == "audio.phase_invert":
        audio_settings["phase_invert"] = True
        return True, "🔄 Phase invert", {"audio_settings": audio_settings}

    if name == "audio.mono_merge":
        audio_settings["mono"] = True
        return True, "🔀 Mono merge", {"audio_settings": audio_settings}

    if name == "audio.stereo_width":
        audio_settings["stereo_width"] = float(args.get("width", 1.0))
        return True, f"📐 Stereo width: {audio_settings['stereo_width']}", {"audio_settings": audio_settings}

    return False, f"Unknown audio tool: {name}", {}


# ─────────────────────────────────────────────────────────────────────────────
# Subtitles handlers (22 tools)
# ─────────────────────────────────────────────────────────────────────────────

def handle_subtitles(name: str, args: Dict[str, Any], state: Dict[str, Any]) -> Tuple[bool, str, Dict[str, Any]]:
    ss = state.setdefault("subtitle_settings", {})

    if name == "subtitles.set_animation":
        ss["animation"] = str(args.get("type", args.get("animation", "fade")))
        return True, f"📝 Animation: {ss['animation']}", {"subtitle_settings": ss}

    if name == "subtitles.set_alignment":
        ss["alignment"] = str(args.get("alignment", "center"))
        return True, f"📐 Align: {ss['alignment']}", {"subtitle_settings": ss}

    if name == "subtitles.apply_template":
        ss["template"] = str(args.get("template_name", "default"))
        return True, f"🎨 Template: {ss['template']}", {"subtitle_settings": ss}

    if name == "subtitles.apply_style":
        ss["style"] = {
            "fontFamily": str(args.get("font_family", "Impact")),
            "fontSize": int(args.get("font_size", 48)),
            "color": str(args.get("color", "#FFFFFF")),
            "outlineColor": str(args.get("outline_color", "#000000")),
            "outlineWidth": int(args.get("outline_width", 2)),
        }
        return True, "🎨 Style applied", {"subtitle_settings": ss}

    if name == "subtitles.add_subtitle":
        subs = state.setdefault("subtitles", [])
        subs.append({
            "id": str(uuid.uuid4()),
            "start": float(args.get("start", 0)),
            "end": float(args.get("end", 2)),
            "text": str(args.get("text", "")),
        })
        return True, "➕ Subtitle added", {"subtitles": subs}

    if name == "subtitles.delete_subtitle":
        sid = args.get("subtitle_id") or args.get("id")
        subs = state.get("subtitles", [])
        subs = [s for s in subs if s.get("id") != sid]
        return True, "🗑️ Subtitle deleted", {"subtitles": subs}

    if name == "subtitles.update_text":
        sid = args.get("subtitle_id") or args.get("id")
        subs = state.get("subtitles", [])
        for s in subs:
            if s.get("id") == sid:
                s["text"] = str(args.get("text", ""))
                break
        return True, "✏️ Text updated", {"subtitles": subs}

    if name == "subtitles.update_timing":
        sid = args.get("subtitle_id") or args.get("id")
        subs = state.get("subtitles", [])
        for s in subs:
            if s.get("id") == sid:
                if "start" in args: s["start"] = float(args["start"])
                if "end" in args: s["end"] = float(args["end"])
                break
        return True, "⏱️ Timing updated", {"subtitles": subs}

    if name == "subtitles.nudge_timing":
        sid = args.get("subtitle_id") or args.get("id")
        delta = float(args.get("delta", 0.1))
        subs = state.get("subtitles", [])
        for s in subs:
            if s.get("id") == sid:
                s["start"] = s.get("start", 0) + delta
                s["end"] = s.get("end", 0) + delta
                break
        return True, f"⏱️ Nudged {delta:+.2f}s", {"subtitles": subs}

    if name == "subtitles.search_replace":
        find = str(args.get("find", ""))
        repl = str(args.get("replace", ""))
        cnt = 0
        for w in state.get("words", []):
            if find in w.get("text", ""):
                w["text"] = w["text"].replace(find, repl)
                cnt += 1
        return True, f"🔍 Replaced {cnt} occurrences", {"words": state.get("words", [])}

    if name == "subtitles.toggle_burn_in":
        ss["burn_in"] = bool(args.get("enabled", True))
        return True, f"🔥 Burn-in: {ss['burn_in']}", {"subtitle_settings": ss}

    if name == "subtitles.toggle_karaoke":
        ss["karaoke"] = bool(args.get("enabled", True))
        return True, f"🎤 Karaoke: {ss['karaoke']}", {"subtitle_settings": ss}

    if name == "subtitles.translate":
        ss["translate_to"] = str(args.get("target_language", "ar"))
        return True, f"🌐 Translate to: {ss['translate_to']}", {"subtitle_settings": ss}

    if name == "subtitles.diarize_speakers":
        patch = {"aiJob": {"type": "speaker_diarization"}}
        return True, "👥 Diarize speakers", patch

    if name == "subtitles.live_caption":
        ss["live_caption"] = bool(args.get("enabled", True))
        return True, f"📡 Live caption: {ss['live_caption']}", {"subtitle_settings": ss}

    if name == "subtitles.auto_punctuate":
        patch = {"aiJob": {"type": "auto_punctuate"}}
        return True, "📝 Auto-punctuate", patch

    if name == "subtitles.censor_profanity":
        ss["censor"] = bool(args.get("enabled", True))
        return True, f"🔒 Censor: {ss['censor']}", {"subtitle_settings": ss}

    if name == "subtitles.auto_line_break":
        ss["max_chars_per_line"] = int(args.get("max_chars", 30))
        return True, f"↩️ Max chars/line: {ss['max_chars_per_line']}", {"subtitle_settings": ss}

    if name == "subtitles.generate_from_audio":
        patch = {"aiJob": {"type": "transcribe"}}
        return True, "🎙️ Generate from audio", patch

    if name == "subtitles.export_srt":
        return True, "📄 SRT export", {}

    if name == "subtitles.import_srt":
        patch = {"aiJob": {"type": "import_srt"}}
        return True, "📥 SRT import", patch

    if name == "subtitles.import_vtt":
        patch = {"aiJob": {"type": "import_vtt"}}
        return True, "📥 VTT import", patch

    return False, f"Unknown subtitles tool: {name}", {}


# ─────────────────────────────────────────────────────────────────────────────
# AI handlers (46 tools)
# ─────────────────────────────────────────────────────────────────────────────

def _llm_ask(prompt: str, temperature: float = 0.5) -> str:
    import os
    import requests
    api_key = os.getenv("GEMMA_API_KEY")
    if not api_key:
        return ""
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemma-2-27b-it:generateContent?key={api_key}"
    headers = {"Content-Type": "application/json"}
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": temperature,
            "maxOutputTokens": 1000,
        },
    }
    try:
        resp = requests.post(url, json=payload, headers=headers, timeout=30)
        if resp.status_code == 200:
            data = resp.json()
            candidates = data.get("candidates", [])
            if candidates:
                parts = candidates[0].get("content", {}).get("parts", [])
                text_parts = [p.get("text", "") for p in parts if not p.get("thought")]
                return "".join(text_parts).strip()
    except Exception:
        pass
    return ""


def _get_transcript_text(state: Dict[str, Any]) -> str:
    sub_track = None
    for track in state.get("tracks", {}).get("subtitles", []):
        if track.get("clips"):
            sub_track = track
            break
    if not sub_track:
        return ""
    texts = []
    for clip in sorted(sub_track.get("clips", []), key=lambda c: c.get("start_time", 0.0)):
        txt = clip.get("text", "").strip()
        if txt:
            texts.append(txt)
    return " ".join(texts)


def handle_ai(name: str, args: Dict[str, Any], state: Dict[str, Any]) -> Tuple[bool, str, Dict[str, Any]]:
    tracks = state.get("tracks", [])
    patch: Dict[str, Any] = {}

    if name == "ai.auto_cut_silences":
        clip_id = args.get("clip_id") or state.get("selectedClipId")
        target_clip = None
        target_track = None
        
        if clip_id:
            target_clip = get_clip_by_id(tracks, clip_id)
            target_track = _find_track_of_clip(tracks, clip_id)
        else:
            for track in tracks:
                if track.get("clips") and ("v" in track.get("id", "").lower() or track.get("type") == "video"):
                    target_clip = track["clips"][0]
                    target_track = track
                    break
                    
        if not target_clip or not target_track:
            return False, "No video clip found to auto-cut", patch
            
        video_path = target_clip.get("source_path")
        if not video_path or not os.path.exists(video_path):
            return False, f"Source video not found: {video_path}", patch
            
        try:
            from faster_whisper import decode_audio
            from faster_whisper.vad import get_speech_timestamps, VadOptions
            import copy
            
            audio = decode_audio(video_path, sampling_rate=16000)
            options = VadOptions(
                threshold=0.5,
                min_speech_duration_ms=250,
                min_silence_duration_ms=500,
                speech_pad_ms=100
            )
            speech_segments = get_speech_timestamps(audio, options, sampling_rate=16000)
            
            if not speech_segments:
                return True, "No silences detected, clip left unchanged", patch
                
            new_clips = []
            current_timeline_time = target_clip.get("start_time_in_timeline", 0.0)
            
            for idx, seg in enumerate(speech_segments):
                start_sec = seg["start"] / 16000.0
                end_sec = seg["end"] / 16000.0
                duration = end_sec - start_sec
                
                new_clip = copy.deepcopy(target_clip)
                new_clip["id"] = f"{target_clip['id']}_autocut_{idx}_{str(uuid.uuid4())[:8]}"
                new_clip["source_trim_start"] = start_sec
                new_clip["source_trim_end"] = end_sec
                new_clip["start_time_in_timeline"] = current_timeline_time
                new_clip["end_time_in_timeline"] = current_timeline_time + duration
                
                new_clips.append(new_clip)
                current_timeline_time += duration
                
            clips = target_track.get("clips", [])
            for i, c in enumerate(clips):
                if c.get("id") == target_clip["id"]:
                    clips.pop(i)
                    for j, nc in enumerate(new_clips):
                        clips.insert(i + j, nc)
                    break
                    
            patch["tracks"] = tracks
            return True, f"✂️ Auto-cut completed: split into {len(new_clips)} active speech segments", patch
        except Exception as e:
            return False, f"Auto-cut failed: {str(e)}", patch

    if name == "ai.auto_framing":
        try:
            from tracker import track_faces
        except ImportError:
            return False, "Tracker module not found", patch
            
        clip_id = args.get("clip_id") or state.get("selectedClipId")
        if not clip_id:
            return False, "No clip selected for auto framing", patch
        clip = get_clip_by_id(tracks, clip_id)
        if not clip:
            return False, f"Clip {clip_id} not found", patch
        video_path = clip.get("source_path")
        if not video_path or not os.path.exists(video_path):
            return False, f"Source video not found or invalid: {video_path}", patch
        
        try:
            keyframes = track_faces(video_path)
            clip.setdefault("transform", {})["keyframes"] = keyframes
            clip.setdefault("ai_features", {})["face_tracking"] = True
            patch["tracks"] = tracks
            return True, "🎯 Auto-framing completed successfully", patch
        except Exception as e:
            return False, f"Auto-framing failed: {str(e)}", patch

    if name == "ai.remove_background":
        cid = args.get("clip_id") or state.get("selectedClipId")
        if not cid: return False, "No clip selected", patch
        clip = get_clip_by_id(tracks, cid)
        if not clip: return False, "Clip not found", patch
        clip.setdefault("ai_features", {})["bg_removed"] = True
        clip.setdefault("ai_features", {})["bg_remove_method"] = "rmbg"
        patch["tracks"] = tracks
        return True, "🟢 Background removal activated for clip (will process on render)", patch

    if name == "ai.generate_title":
        transcript = _get_transcript_text(state)
        if not transcript:
            return True, "💡 AI Title Suggestion: [No transcript available to summarize]", patch
        
        prompt = f"""You are a professional social media manager.
Analyze this video transcript:
"{transcript}"

Generate 5 highly engaging, clickbaity, and viral video titles.
Format: Return ONLY the 5 titles listed sequentially (one per line) with emojis. No other explanation or headers."""
        
        titles = _llm_ask(prompt)
        if not titles:
            titles = "1. سر خطير لم تسمعه من قبل! 🤫\n2. أكبر خطأ تقع فيه يومياً! ⚠️\n3. كيف تحقق النجاح في ثوانٍ؟ 🚀\n4. نصيحة ذهبية لتغيير حياتك! 💡\n5. شاهد قبل الحذف! 🍿"
        return True, f"💡 AI Suggested Titles:\n{titles}", patch

    if name == "ai.generate_description":
        transcript = _get_transcript_text(state)
        if not transcript:
            return True, "💡 AI Description: [No transcript available to summarize]", patch
        
        prompt = f"""Analyze this video transcript:
"{transcript}"

Generate a short, punchy description for social media (TikTok/Instagram) summarizing this video, with a call to action.
Format: Return ONLY the description text with emojis. No other metadata."""
        
        desc = _llm_ask(prompt)
        if not desc:
            desc = "في هذا الفيديو، نشارك معكم أهم النصائح والحقائق حول الموضوع بطريقة مبسطة وممتعة! شاركونا آراءكم في التعليقات ولا تنسوا المتابعة للمزيد! 🎬🚀"
        return True, f"💡 AI Suggested Description:\n{desc}", patch

    if name == "ai.suggest_hashtags":
        transcript = _get_transcript_text(state)
        if not transcript:
            return True, "💡 AI Suggested Hashtags: #foryou #editing #clippify #viral", patch
        
        prompt = f"""Analyze this video transcript:
"{transcript}"

Generate 8 highly relevant and viral hashtags for TikTok/Reels based on the content.
Format: Return ONLY the hashtags separated by spaces (e.g. #hashtag1 #hashtag2). No explanation."""
        
        tags = _llm_ask(prompt)
        if not tags:
            tags = "#foryou #fyp #viral #editing #clippify #contentcreator #expert #ai"
        return True, f"💡 AI Suggested Hashtags: {tags}", patch

    # Map tool name -> aiJob type
    ai_job_map = {
        "ai.auto_zoom_speech": "auto_zoom",
        "ai.beat_sync": "beat_sync",
        "ai.smart_recut": "smart_recut",
        "ai.remove_filler_words": "filler_removal",
        "ai.remove_object": "remove_object",
        "ai.interpolate_frames": "interpolate_frames",
        "ai.upscale_video": "upscale",
        "ai.denoise_video": "denoise_video",
        "ai.color_match": "color_match",
        "ai.style_transfer": "style_transfer",
        "ai.scene_captioning": "scene_captioning",
        "ai.detect_scenes": "detect_scenes",
        "ai.detect_emotion": "detect_emotion",
        "ai.detect_chapters": "chapters",
        "ai.analyze_pacing": "analyze_pacing",
        "ai.analyze_story_arc": "story_arc",
        "ai.analyze_competitors": "analyze_competitors",
        "ai.score_virality": "viral_score",
        "ai.predict_engagement": "predict_engagement",
        "ai.predict_trend": "predict_trend",
        "ai.content_rating": "content_rating",
        "ai.check_copyright": "check_copyright",
        "ai.match_audience": "match_audience",
        "ai.generate_thumbnail": "thumbnail",
        "ai.generate_hooks_v2": "generate_hooks",
        "ai.generate_highlight_reel": "highlight_reel",
        "ai.generate_narration": "voiceover",
        "ai.generate_voiceover": "voiceover",
        "ai.suggest_posting_time": "posting_time",
        "ai.suggest_sound_design": "sound_design",
        "ai.suggest_transitions": "transitions",
        "ai.suggest_brolls": "brolls",
        "ai.lip_sync_translation": "lip_sync",
        "ai.deepfake_detector": "deepfake_check",
        "ai.macro_record": "macro_record",
        "ai.macro_play": "macro_play",
        "ai.jump_cut_remover": "jump_cut",
        "ai.local_llm_toggle": "local_llm",
        "ai.auto_crop_social": "auto_crop_social",
        "ai.search_stock": "stock_search",
    }

    if name in ai_job_map:
        job_type = ai_job_map[name]
        patch["aiJob"] = {"type": job_type, "args": args}
        return True, f"🤖 AI: {job_type}", patch

    return False, f"Unknown AI tool: {name}", patch


# ─────────────────────────────────────────────────────────────────────────────
# Export handlers (26 tools)
# ─────────────────────────────────────────────────────────────────────────────

def handle_export(name: str, args: Dict[str, Any], state: Dict[str, Any]) -> Tuple[bool, str, Dict[str, Any]]:
    patch: Dict[str, Any] = {}

    if name == "export.render":
        patch["exportJob"] = {
            "type": "render",
            "preset": str(args.get("preset", "1080p")),
            "format": str(args.get("format", "mp4")),
        }
        return True, f"🎬 Render: {patch['exportJob']['preset']}", patch

    if name == "export.render_proxy":
        patch["exportJob"] = {"type": "proxy"}
        return True, "🎬 Proxy render", patch

    if name == "export.background_render":
        patch["exportJob"] = {"type": "background"}
        return True, "🎬 Background render", patch

    if name == "export.batch_render":
        patch["exportJob"] = {"type": "batch"}
        return True, "🎬 Batch render", patch

    if name == "export.cancel_job":
        patch["cancelRender"] = True
        return True, "❌ Cancel render", patch

    if name == "export.export_audio":
        patch["exportJob"] = {"type": "audio", "format": str(args.get("format", "mp3"))}
        return True, "🎵 Export audio", patch

    if name == "export.export_gif":
        patch["exportJob"] = {"type": "gif"}
        return True, "🎞️ Export GIF", patch

    if name == "export.export_h265":
        patch["exportJob"] = {"type": "h265"}
        return True, "📹 Export H.265", patch

    if name == "export.export_hdr":
        patch["exportJob"] = {"type": "hdr"}
        return True, "🌈 Export HDR", patch

    if name == "export.export_prores":
        patch["exportJob"] = {"type": "prores"}
        return True, "🎬 Export ProRes", patch

    if name == "export.export_per_platform":
        patch["exportJob"] = {"type": "per_platform", "platforms": args.get("platforms", ["youtube", "tiktok"])}
        return True, "📱 Per-platform export", patch

    if name == "export.export_xml_final_cut":
        patch["exportJob"] = {"type": "xml", "format": "fcpxml"}
        return True, "📄 FCP XML", patch

    if name == "export.export_xml_premiere":
        patch["exportJob"] = {"type": "xml", "format": "premiere"}
        return True, "📄 Premiere XML", patch

    if name == "export.export_xml_resolve":
        patch["exportJob"] = {"type": "xml", "format": "resolve"}
        return True, "📄 Resolve XML", patch

    if name == "export.export_aaf":
        patch["exportJob"] = {"type": "aaf"}
        return True, "📄 AAF export", patch

    if name == "export.upload_youtube":
        patch["exportJob"] = {"type": "upload", "platform": "youtube"}
        return True, "⬆️ Upload YouTube", patch

    if name == "export.upload_youtube_shorts":
        patch["exportJob"] = {"type": "upload", "platform": "youtube_shorts"}
        return True, "⬆️ Upload YouTube Shorts", patch

    if name == "export.upload_tiktok":
        patch["exportJob"] = {"type": "upload", "platform": "tiktok"}
        return True, "⬆️ Upload TikTok", patch

    if name == "export.upload_instagram":
        patch["exportJob"] = {"type": "upload", "platform": "instagram"}
        return True, "⬆️ Upload Instagram", patch

    if name == "export.share_review_link":
        patch["exportJob"] = {"type": "share_link"}
        return True, "🔗 Share link", patch

    if name == "export.create_share_link":
        patch["exportJob"] = {"type": "share_link"}
        return True, "🔗 Create share link", patch

    if name == "export.queue_add":
        patch["exportJob"] = {"type": "queue_add"}
        return True, "➕ Add to queue", patch

    if name == "export.queue_status":
        patch["exportJob"] = {"type": "queue_status"}
        return True, "📊 Queue status", patch

    if name == "export.embed_metadata":
        patch["exportJob"] = {"type": "embed_meta"}
        return True, "📋 Embed metadata", patch

    if name == "export.apply_watermark":
        patch["exportJob"] = {"type": "watermark"}
        return True, "💧 Apply watermark", patch

    if name == "export.add_chapter_markers":
        patch["exportJob"] = {"type": "chapter_markers"}
        return True, "📑 Add chapter markers", patch

    return False, f"Unknown export tool: {name}", patch


# ─────────────────────────────────────────────────────────────────────────────
# Main Executor
# ─────────────────────────────────────────────────────────────────────────────

HANDLERS = {
    "timeline": handle_timeline,
    "playback": handle_playback,
    "effects": handle_effects,
    "audio": handle_audio,
    "subtitles": handle_subtitles,
    "ai": handle_ai,
    "export": handle_export,
}


def execute_action_plan(actions: List[Dict[str, Any]], initial_state: Dict[str, Any]) -> Dict[str, Any]:
    import copy
    state = copy.deepcopy(initial_state)
    messages: List[str] = []
    errors: List[str] = []
    results: List[Dict[str, Any]] = []

    for action in actions:
        name = action.get("name", "")
        args = action.get("args", {})

        if "." not in name:
            errors.append(f"Invalid tool name: {name}")
            results.append({"name": name, "ok": False, "message": "Invalid name", "patch": {}})
            continue

        category, _ = name.split(".", 1)
        handler = HANDLERS.get(category)
        if not handler:
            errors.append(f"Unknown category: {category}")
            continue

        if not get_tool(name):
            errors.append(f"Tool not found: {name}")
            continue

        try:
            ok, message, patch = handler(name, args, state)
            if ok and patch:
                state.update(patch)
            results.append({"name": name, "ok": ok, "message": message, "patch": patch if ok else {}})
            if ok:
                messages.append(message)
            else:
                errors.append(message)
        except Exception as e:
            err_msg = f"Error executing {name}: {str(e)[:200]}"
            errors.append(err_msg)
            results.append({"name": name, "ok": False, "message": err_msg, "patch": {}})

    return {
        "ok": len(errors) == 0,
        "new_state": state,
        "messages": messages,
        "errors": errors,
        "results": results,
    }


def needs_user_approval(actions: List[Dict[str, Any]]) -> bool:
    for action in actions:
        name = action.get("name", "")
        tool = get_tool(name)
        if not tool:
            return True
        if tool.get("requires_confirmation", False) or tool.get("destructive", False):
            return True
        if name.startswith("export."):
            return True
    return False


def get_destructive_actions(actions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return [a for a in actions if (get_tool(a.get("name", "")) or {}).get("destructive", False) or a.get("name", "").startswith("export.")]


def get_safe_actions(actions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return [a for a in actions if not ((get_tool(a.get("name", "")) or {}).get("destructive", False) or a.get("name", "").startswith("export."))]


if __name__ == "__main__":
    test_state = {
        "tracks": [
            {"id": "v1", "name": "V1", "clips": [
                {"id": "c1", "name": "Intro", "start_time_in_timeline": 0, "end_time_in_timeline": 10, "effects": {}},
            ]},
        ],
        "currentTime": 5.0,
        "selectedClipId": "c1",
    }
    test_actions = [
        {"name": "playback.seek", "args": {"time": 12.5}},
        {"name": "effects.set_brightness", "args": {"clip_id": "c1", "brightness": 0.15}},
        {"name": "audio.adjust_volume", "args": {"volume": 0.8}},
        {"name": "subtitles.set_alignment", "args": {"alignment": "left"}},
        {"name": "timeline.set_zoom_level", "args": {"pixels_per_second": 80}},
        {"name": "ai.auto_cut_silences", "args": {}},
        {"name": "export.render", "args": {"preset": "1080p"}},
    ]
    r = execute_action_plan(test_actions, test_state)
    print(f"OK: {r['ok']}")
    print(f"Messages: {r['messages']}")
    print(f"Errors: {r['errors']}")
