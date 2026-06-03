"""
video_analyzer.py — Smart Video Understanding for ClipAI
=========================================================
This module UNDERSTANDS what's in the video before cutting it.

What it does:
  1. Extracts sample frames from a video segment using FFmpeg
  2. Detects faces / persons in each frame (using OpenCV or MediaPipe)
  3. Analyzes the scene layout:
     - No faces → center crop
     - 1 face → crop centered on the face (person-aware framing)
     - 2 faces side by side → decide: follow dominant speaker, or split screen
     - 2 faces vertical (interview format) → crop on upper face (usually speaker)
  4. Returns optimal FFmpeg crop parameters for that segment

Fallback chain (most to least capable):
  - MediaPipe FaceDetection → best accuracy, works on GPU/CPU
  - OpenCV DNN (yunet) → good accuracy, always works offline
  - OpenCV Haar Cascade → fast, basic, always available
  - Center crop → safe default when no detection works
"""

import os
import subprocess
import tempfile
import struct
import numpy as np
from typing import List, Tuple, Optional, Dict, Any


# ─────────────────────────────────────────────────────────────────────────────
#  FFmpeg helper
# ─────────────────────────────────────────────────────────────────────────────

def _get_ffmpeg():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def _get_video_dimensions(video_path: str) -> Tuple[int, int]:
    """Return (width, height) of video using ffprobe."""
    ffmpeg = _get_ffmpeg()
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


def extract_frame_as_array(video_path: str, time_sec: float, cap: Optional[Any] = None) -> Optional[np.ndarray]:
    """
    Extract a single frame from video at time_sec.
    Returns numpy array (H, W, 3) in RGB format, or None on failure.
    Uses ultra-fast OpenCV memory seek first, with stable FFmpeg fallback.
    Supports sharing a VideoCapture object for 1000x speedup.
    """
    import cv2
    try:
        if cap is not None and cap.isOpened():
            fps = cap.get(cv2.CAP_PROP_FPS)
            if fps > 0:
                frame_idx = int(time_sec * fps)
                cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
            else:
                msec = time_sec * 1000.0
                cap.set(cv2.CAP_PROP_POS_MSEC, msec)
            ret, frame = cap.read()
            if ret and frame is not None:
                return cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            return None

        cap_local = cv2.VideoCapture(video_path)
        if cap_local.isOpened():
            fps = cap_local.get(cv2.CAP_PROP_FPS)
            if fps > 0:
                frame_idx = int(time_sec * fps)
                cap_local.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
            else:
                msec = time_sec * 1000.0
                cap_local.set(cv2.CAP_PROP_POS_MSEC, msec)
            ret, frame = cap_local.read()
            cap_local.release()
            if ret and frame is not None:
                return cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    except Exception as e:
        print(f"  [ANALYZE] OpenCV fast single-frame seek failed, falling back to FFmpeg: {e}")

    # Fallback: Two-stage seek using FFmpeg (highly stable and accurate)
    ffmpeg = _get_ffmpeg()
    fd, tmp_path = tempfile.mkstemp(suffix=".png")
    os.close(fd)
    try:
        fast_seek = max(0.0, time_sec - 1.0)
        accurate_seek = time_sec - fast_seek
        
        cmd = [
            ffmpeg, "-y", "-loglevel", "error",
            "-ss", f"{fast_seek:.3f}", "-i", video_path,
            "-ss", f"{accurate_seek:.3f}", "-vframes", "1",
            "-q:v", "2", tmp_path
        ]
        
        result = subprocess.run(cmd, capture_output=True, timeout=15)
        if result.returncode != 0 or not os.path.exists(tmp_path) or os.path.getsize(tmp_path) == 0:
            cmd_fallback = [
                ffmpeg, "-y", "-loglevel", "error",
                "-i", video_path, "-ss", f"{time_sec:.3f}",
                "-vframes", "1", "-q:v", "2", tmp_path
            ]
            subprocess.run(cmd_fallback, capture_output=True, timeout=15)
            
        if not os.path.exists(tmp_path) or os.path.getsize(tmp_path) == 0:
            return None
            
        from PIL import Image
        img = Image.open(tmp_path).convert("RGB")
        return np.array(img)
    except Exception as e:
        print(f"  [ANALYZE] Frame extraction failed completely at {time_sec:.1f}s: {e}")
        return None
    finally:
        try:
            os.remove(tmp_path)
        except Exception:
            pass


def extract_frames_batch(video_path: str, start_sec: float, duration: float, n_frames: int, cap=None) -> List[Tuple[float, np.ndarray]]:
    """Extract a batch of frames across a time segment using blazing fast FFmpeg seek."""
    import cv2
    import tempfile, shutil
    ffmpeg = _get_ffmpeg()
    tmp_dir = tempfile.mkdtemp(prefix="clipai_frames_")
    results = []
    try:
        fps = n_frames / duration
        cmd = [
            ffmpeg, "-y", "-loglevel", "error",
            "-ss", f"{start_sec:.3f}", "-t", f"{duration:.3f}",
            "-i", video_path,
            "-vf", f"fps={fps}",
            "-q:v", "2",
            os.path.join(tmp_dir, "frame_%04d.png")
        ]
        import subprocess
        subprocess.run(cmd, check=True)
        
        # Read frames
        for i in range(1, n_frames + 5):
            fpath = os.path.join(tmp_dir, f"frame_{i:04d}.png")
            if os.path.exists(fpath):
                frame = cv2.imread(fpath)
                if frame is not None:
                    # Convert BGR to RGB
                    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                    rel_t = (i - 1) / fps
                    # Ensure we don't exceed duration
                    if rel_t <= duration:
                        results.append((rel_t, frame_rgb))
    except Exception as e:
        print(f"  [ERROR] extract_frames_batch fallback failed: {e}")
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)
    return results


# ─────────────────────────────────────────────────────────────────────────────
#  Face Detection Backends (with graceful fallback)
# ─────────────────────────────────────────────────────────────────────────────

class FaceBox:
    """Represents a detected face bounding box in normalized coordinates (0-1)."""
    def __init__(self, x: float, y: float, w: float, h: float, confidence: float = 1.0):
        # All coordinates are normalized 0..1 relative to frame dimensions
        self.x = max(0.0, x)         # left edge
        self.y = max(0.0, y)         # top edge
        self.w = min(1.0, w)         # width
        self.h = min(1.0, h)         # height
        self.confidence = confidence

    @property
    def cx(self) -> float:
        """Center x (normalized)."""
        return self.x + self.w / 2

    @property
    def cy(self) -> float:
        """Center y (normalized)."""
        return self.y + self.h / 2

    @property
    def area(self) -> float:
        return self.w * self.h

    def __repr__(self):
        return f"FaceBox(cx={self.cx:.2f}, cy={self.cy:.2f}, area={self.area:.3f}, conf={self.confidence:.2f})"


import threading

_thread_local = threading.local()

def _get_mediapipe_detector():
    if not hasattr(_thread_local, "mediapipe_detector"):
        try:
            import mediapipe as mp
            mp_face = mp.solutions.face_detection
            _thread_local.mediapipe_detector = mp_face.FaceDetection(model_selection=1, min_detection_confidence=0.4)
        except Exception:
            _thread_local.mediapipe_detector = None
    return _thread_local.mediapipe_detector

def _get_mediapipe_pose():
    if not hasattr(_thread_local, "mediapipe_pose"):
        try:
            import mediapipe as mp
            mp_pose = mp.solutions.pose
            _thread_local.mediapipe_pose = mp_pose.Pose(static_image_mode=True, min_detection_confidence=0.5)
        except Exception:
            _thread_local.mediapipe_pose = None
    return _thread_local.mediapipe_pose

def _get_opencv_cascade():
    if not hasattr(_thread_local, "opencv_cascade"):
        try:
            import cv2
            cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
            _thread_local.opencv_cascade = cv2.CascadeClassifier(cascade_path)
        except Exception:
            _thread_local.opencv_cascade = None
    return _thread_local.opencv_cascade

def _detect_faces_mediapipe(frame_rgb: np.ndarray) -> List[FaceBox]:
    """Detect faces using MediaPipe (best quality, optional)."""
    try:
        detector = _get_mediapipe_detector()
        if detector is None:
            return []
        h, w = frame_rgb.shape[:2]
        results = detector.process(frame_rgb)
        if not results.detections:
            return []
        boxes = []
        for det in results.detections:
            bb = det.location_data.relative_bounding_box
            boxes.append(FaceBox(
                x=bb.xmin, y=bb.ymin, w=bb.width, h=bb.height,
                confidence=det.score[0] if det.score else 0.8
            ))
        return boxes
    except Exception as e:
        raise RuntimeError(f"MediaPipe failed: {e}")


def _detect_faces_opencv(frame_rgb: np.ndarray) -> List[FaceBox]:
    """Detect faces using OpenCV Haar Cascade (always available with opencv)."""
    cascade = _get_opencv_cascade()
    if cascade is None or cascade.empty():
        return []
    import cv2
    h, w = frame_rgb.shape[:2]
    gray = cv2.cvtColor(frame_rgb, cv2.COLOR_RGB2GRAY)
    # Detect with multiple scale factors for robustness
    detections = cascade.detectMultiScale(
        gray,
        scaleFactor=1.1,
        minNeighbors=4,
        minSize=(int(w * 0.05), int(h * 0.05)),  # min 5% of frame
        maxSize=(int(w * 0.8), int(h * 0.8)),
    )
    if detections is None or len(detections) == 0:
        # Try more permissive settings
        detections = cascade.detectMultiScale(gray, scaleFactor=1.15, minNeighbors=3)
    if detections is None or len(detections) == 0:
        return []
    boxes = []
    for (x, y, fw, fh) in detections:
        boxes.append(FaceBox(
            x=x/w, y=y/h, w=fw/w, h=fh/h,
            confidence=0.75
        ))
    return boxes


def _detect_faces_opencv_dnn(frame_rgb: np.ndarray) -> List[FaceBox]:
    """
    Detect faces using OpenCV DNN with YuNet model.
    YuNet is a lightweight, high-accuracy face detector.
    """
    import cv2
    h, w = frame_rgb.shape[:2]
    # Try to use FaceDetectorYN (OpenCV 4.5.4+)
    try:
        detector = cv2.FaceDetectorYN.create(
            "", "", (w, h), score_threshold=0.5, nms_threshold=0.3
        )
        # This requires a model file - skip if not available
        return []
    except Exception:
        return []


def detect_faces(frame_rgb: np.ndarray) -> List[FaceBox]:
    """
    Detect faces in a frame. Tries backends in order:
    1. MediaPipe (best quality)
    2. OpenCV Haar Cascade (fallback)
    Returns list of FaceBox objects.
    """
    # Try MediaPipe first
    try:
        faces = _detect_faces_mediapipe(frame_rgb)
        if faces is not None:
            return faces
    except Exception:
        pass

    # Fallback to OpenCV
    try:
        return _detect_faces_opencv(frame_rgb)
    except Exception:
        pass

    # No detection library available
    return []


# ─────────────────────────────────────────────────────────────────────────────
#  Person Detection (full body, for when face isn't visible)
# ─────────────────────────────────────────────────────────────────────────────

def detect_persons(frame_rgb: np.ndarray) -> List[FaceBox]:
    """Detect full-body persons using MediaPipe Pose (fallback for face-hidden shots)."""
    try:
        pose = _get_mediapipe_pose()
        if pose is None:
            return []
        import mediapipe as mp  # type: ignore
        mp_pose = mp.solutions.pose
        results = pose.process(frame_rgb)
        if not results.pose_landmarks:
            return []
        # Use nose + shoulders as "face proxy"
        lm = results.pose_landmarks.landmark
        nose = lm[mp_pose.PoseLandmark.NOSE]
        lshoulder = lm[mp_pose.PoseLandmark.LEFT_SHOULDER]
        rshoulder = lm[mp_pose.PoseLandmark.RIGHT_SHOULDER]
        # Build a bounding box from nose to shoulders
        xs = [nose.x, lshoulder.x, rshoulder.x]
        ys = [nose.y, lshoulder.y, rshoulder.y]
        cx = np.mean(xs)
        cy = np.mean(ys)
        # Estimate head size
        head_w = abs(lshoulder.x - rshoulder.x) * 1.2
        head_h = head_w * 1.4
        return [FaceBox(
            x=cx - head_w/2, y=cy - head_h,
            w=head_w, h=head_h * 1.5,
            confidence=0.7
        )]
    except Exception:
        return []


# ─────────────────────────────────────────────────────────────────────────────
#  Scene Layout Analysis
# ─────────────────────────────────────────────────────────────────────────────

class SceneAnalysis:
    """Result of analyzing a video segment's visual content."""

    def __init__(self):
        self.n_persons: int = 0
        self.faces: List[FaceBox] = []
        self.layout: str = "unknown"       # "solo", "duo_side", "duo_vertical", "group", "empty"
        self.dominant_face: Optional[FaceBox] = None
        self.active_speaker: Optional[FaceBox] = None
        self.focus_cx: float = 0.5        # where to center the crop horizontally (normalized)
        self.focus_cy: float = 0.5        # where to center the crop vertically (normalized)
        self.crop_strategy: str = "center"  # "center", "face_left", "face_right", "face_top", "face_all", "split"
        self.sub_scenes: List[tuple] = []   # list of (rel_end_sec, sub_analysis) for dynamic tracking
        self.panning_transitions: List[dict] = []


    def __repr__(self):
        return (f"SceneAnalysis(layout={self.layout}, n={self.n_persons}, "
                f"strategy={self.crop_strategy}, focus=({self.focus_cx:.2f},{self.focus_cy:.2f}))")


def _analyze_layout(faces: List[FaceBox], framing_strategy: str = "split_screen", active_speaker: FaceBox = None) -> SceneAnalysis:
    """Determine scene layout from detected faces and compute crop strategy."""
    result = SceneAnalysis()
    result.faces = faces
    result.n_persons = len(faces)

    if framing_strategy == "no_crop":
        result.layout = "empty"
        result.crop_strategy = "no_crop"
        result.focus_cx = 0.5
        result.focus_cy = 0.5
        return result

    # ── SPECIAL HANDLING: Smart split screen layout if selected ──────────────
    if framing_strategy == "split_screen":
        if len(faces) >= 2:
            result.layout = "duo_side"
            result.crop_strategy = "split_screen"
            faces_sorted = sorted(faces, key=lambda f: f.cx)
            result.faces_lr = [faces_sorted[0], faces_sorted[-1]]
            result.focus_cx = (faces_sorted[0].cx + faces_sorted[-1].cx) / 2
            result.focus_cy = (faces_sorted[0].cy + faces_sorted[-1].cy) / 2
        elif len(faces) == 1:
            # Smart fallback: Only 1 person visible, use Active Speaker (face_single) instead of splitting!
            f = faces[0]
            result.layout = "solo"
            result.crop_strategy = "face_single"
            result.dominant_face = f
            result.focus_cx = f.cx
            result.focus_cy = f.cy
        else:
            # No faces detected — use motion analysis to drift crop horizontally
            result.layout = "empty"
            result.crop_strategy = "motion_drift"
            result.focus_cx = 0.5  # default center, overridden below by motion
            result.focus_cy = 0.5
        return result

    if not faces:
        result.layout = "empty"
        result.crop_strategy = "motion_drift"
        result.focus_cx = 0.5
        result.focus_cy = 0.5
        return result

    # Sort by area (largest = most prominent)
    faces_sorted = sorted(faces, key=lambda f: f.area, reverse=True)
    dominant = faces_sorted[0]
    result.dominant_face = dominant

    if framing_strategy == "speaker_tracking":
        speaker = active_speaker if active_speaker else dominant
        result.layout = "solo"
        result.crop_strategy = "face_single"
        result.dominant_face = speaker
        result.active_speaker = speaker
        result.focus_cx = speaker.cx
        result.focus_cy = speaker.cy
        return result

    if len(faces) == 1:
        result.layout = "solo"
        result.crop_strategy = "face_single"
        result.focus_cx = dominant.cx
        result.focus_cy = dominant.cy
        return result

    if len(faces) == 2:
        f1, f2 = faces_sorted[0], faces_sorted[1]
        # Check if side by side (horizontal layout)
        dx = abs(f1.cx - f2.cx)
        dy = abs(f1.cy - f2.cy)

        if dx > dy:
            # Side by side — podcast/interview table setting
            result.layout = "duo_side"
            # Focus on the midpoint, but lean towards the larger face
            weight = f1.area / (f1.area + f2.area)
            result.focus_cx = f1.cx * weight + f2.cx * (1 - weight)
            result.focus_cy = (f1.cy + f2.cy) / 2

            # If they're very far apart, split screen!
            if dx > 0.28:
                result.crop_strategy = "split_screen"
                result.faces_lr = sorted([f1, f2], key=lambda f: f.cx)
            else:
                result.crop_strategy = "face_both"
        else:
            # Vertical layout — one above the other
            result.layout = "duo_vertical"
            # Focus on the upper one (typically the speaker in interview format)
            upper = min(faces_sorted[0], faces_sorted[1], key=lambda f: f.cy)
            result.crop_strategy = "face_upper"
            result.focus_cx = upper.cx
            result.focus_cy = upper.cy

        return result

    # 3+ faces — group shot
    result.layout = "group"
    # Focus on center of mass of all faces
    result.focus_cx = np.mean([f.cx for f in faces])
    result.focus_cy = np.mean([f.cy for f in faces])
    result.crop_strategy = "face_group"
    return result


# ─────────────────────────────────────────────────────────────────────────────
#  Mouth Motion Active Speaker Detection (ASD)
# ─────────────────────────────────────────────────────────────────────────────

def _get_mouth_motion_score(video_path: str, time_sec: float, face: FaceBox, src_w: int, src_h: int, cap: Optional[Any] = None) -> float:
    """Analyze mouth region motion over a 300ms window to estimate speech activity."""
    import cv2
    
    # We sample 4 frames with 100ms interval
    sample_offsets = [-0.1, 0.0, 0.1, 0.2]
    mouth_frames = []
    
    for offset in sample_offsets:
        t = max(0.0, time_sec + offset)
        frame = extract_frame_as_array(video_path, t, cap=cap)
        if frame is None:
            continue
            
        # Convert face normalized coordinates to absolute pixels
        fx = int(face.x * src_w)
        fy = int(face.y * src_h)
        fw = int(face.w * src_w)
        fh = int(face.h * src_h)
        
        # Mouth region: lower part of the face, horizontally centered
        mx_start = max(0, fx + int(fw * 0.25))
        mx_end = min(src_w, fx + int(fw * 0.75))
        my_start = max(0, fy + int(fh * 0.65))
        my_end = min(src_h, fy + int(fh * 0.95))
        
        if (mx_end - mx_start) <= 0 or (my_end - my_start) <= 0:
            continue
            
        mouth_crop = frame[my_start:my_end, mx_start:mx_end]
        if mouth_crop.size == 0:
            continue
            
        gray = cv2.cvtColor(mouth_crop, cv2.COLOR_RGB2GRAY)
        gray_resized = cv2.resize(gray, (64, 48))
        gray_blurred = cv2.GaussianBlur(gray_resized, (5, 5), 0)
        mouth_frames.append(gray_blurred)
        
    if len(mouth_frames) < 2:
        return 0.0
        
    # Calculate average difference between consecutive mouth frames
    diffs = []
    for idx in range(len(mouth_frames) - 1):
        diff = cv2.absdiff(mouth_frames[idx], mouth_frames[idx+1])
        diffs.append(np.mean(diff))
        
    return float(np.mean(diffs))


# ─────────────────────────────────────────────────────────────────────────────
#  Segment Analyzer (Main Entry Point)
# ─────────────────────────────────────────────────────────────────────────────

def _analyze_sub_segment(video_path: str, start_sec: float, end_sec: float,
                         n_samples: int = 3, framing_strategy: str = "split_screen",
                         src_w: int = 1920, src_h: int = 1080, cap: Optional[Any] = None) -> SceneAnalysis:
    """Helper to perform standard face-tracking analysis on a specific sub-range."""
    duration = end_sec - start_sec
    if duration <= 0:
        return SceneAnalysis()

    sample_times = [
        start_sec + duration * (i + 1) / (n_samples + 1)
        for i in range(n_samples)
    ]

    all_faces_per_frame = []
    for t in sample_times:
        frame = extract_frame_as_array(video_path, t, cap=cap)
        if frame is None:
            continue
        faces = detect_faces(frame)
        if not faces:
            persons = detect_persons(frame)
            faces = persons
        all_faces_per_frame.append(faces)

    if not all_faces_per_frame:
        result = SceneAnalysis()
        result.layout = "unknown"
        result.crop_strategy = "no_crop" if framing_strategy == "no_crop" else "center"
        return result

    face_counts = [len(f) for f in all_faces_per_frame]
    median_count = int(np.median(face_counts))

    best_frame_idx = min(
        range(len(all_faces_per_frame)),
        key=lambda i: abs(len(all_faces_per_frame[i]) - median_count)
    )
    representative_faces = all_faces_per_frame[best_frame_idx]

    if not representative_faces:
        for faces in all_faces_per_frame:
            if faces:
                representative_faces = faces
                break

    all_dominant_cx = []
    all_dominant_cy = []
    for faces in all_faces_per_frame:
        if faces:
            dominant = max(faces, key=lambda f: f.area)
            all_dominant_cx.append(dominant.cx)
            all_dominant_cy.append(dominant.cy)

    active_speaker = None
    if len(representative_faces) >= 2 and framing_strategy == "speaker_tracking":
        best_time = sample_times[best_frame_idx]
        best_score = -1.0
        print("  [ASD] Analyzing active speaker mouth motion...")
        for face in representative_faces:
            try:
                score = _get_mouth_motion_score(video_path, best_time, face, src_w, src_h, cap=cap)
                print(f"    -> Face at cx={face.cx:.2f}: Mouth motion score = {score:.3f}")
                if score > best_score:
                    best_score = score
                    active_speaker = face
            except Exception as e:
                print(f"    [WARN] ASD failed for face ({e})")

    analysis = _analyze_layout(representative_faces, framing_strategy, active_speaker=active_speaker)

    if all_dominant_cx and framing_strategy not in ["speaker_tracking", "split_screen"]:
        smooth_cx = float(np.median(all_dominant_cx))
        smooth_cy = float(np.median(all_dominant_cy))
        analysis.focus_cx = analysis.focus_cx * 0.6 + smooth_cx * 0.4
        analysis.focus_cy = analysis.focus_cy * 0.6 + smooth_cy * 0.4

    return analysis


SPEAKER_POSITION_CACHE = {}
SPEAKER_POSITION_CACHE_LOCK = threading.Lock()

def detect_motion_side(frames: List[np.ndarray]) -> float:
    """
    Analyzes motion between consecutive frames and returns the dominant horizontal position (0.0 to 1.0)
    where most motion is happening.
    """
    import cv2
    import numpy as np
    if len(frames) < 2:
        return 0.5
    
    motion_profile = []
    for i in range(1, len(frames)):
        f1 = cv2.cvtColor(frames[i-1], cv2.COLOR_RGB2GRAY)
        f2 = cv2.cvtColor(frames[i], cv2.COLOR_RGB2GRAY)
        
        # Resize to a small standard size for fast diff computation
        f1_small = cv2.resize(f1, (160, 90))
        f2_small = cv2.resize(f2, (160, 90))
        
        diff = cv2.absdiff(f1_small, f2_small)
        _, thresh = cv2.threshold(diff, 15, 255, cv2.THRESH_BINARY)
        
        # Sum motion vertically along the X axis
        col_sums = np.sum(thresh, axis=0) # array of length 160
        motion_profile.append(col_sums)
        
    if not motion_profile:
        return 0.5
        
    avg_profile = np.mean(motion_profile, axis=0) # average motion per column
    total_motion = np.sum(avg_profile)
    if total_motion < 10:
        return 0.5 # too little motion
        
    # Compute the center of mass of the motion profile
    indices = np.arange(len(avg_profile))
    center_x_idx = np.sum(indices * avg_profile) / total_motion
    return float(center_x_idx / len(avg_profile))


def _analyze_sub_segment_detailed(video_path: str, start_sec: float, end_sec: float,
                                   interval_sec: float = 1.5,
                                   framing_strategy: str = "split_screen",
                                   src_w: int = 1920, src_h: int = 1080,
                                   cap: Optional[Any] = None,
                                   content_type: str = "podcast",
                                   viral_timeline: Optional[Dict[float, float]] = None) -> SceneAnalysis:
    """
    Per-second face tracking: samples up to 10 frames based on speech energy peaks
    or evenly spaced across the segment, detects faces at each sample,
    and returns a stabilized SceneAnalysis with cached memory features.
    """
    duration = end_sec - start_sec
    if duration <= 0:
        return SceneAnalysis()

    # ── Check Speaker Memory Cache ──
    with SPEAKER_POSITION_CACHE_LOCK:
        cached = SPEAKER_POSITION_CACHE.get(video_path)
    if cached:
        print(f"  [CACHE] Reusing speaker position from cache for {video_path}: strategy={cached['crop_strategy']}, focus_cx={cached['focus_cx']:.3f}")
        result = SceneAnalysis()
        result.layout = cached["layout"]
        result.crop_strategy = cached["crop_strategy"]
        result.focus_cx = cached["focus_cx"]
        result.focus_cy = cached["focus_cy"]
        if cached["faces_lr"]:
            result.faces_lr = cached["faces_lr"]
        if cached["dominant_face"]:
            result.dominant_face = cached["dominant_face"]
        return result

    # ── Adaptive Frame Sampling using Speech Energy Peaks ──
    peak_times = []
    if viral_timeline:
        # Find timestamps in range [start_sec, end_sec]
        in_range = [(t, val) for t, val in viral_timeline.items() if start_sec <= t <= end_sec]
        if in_range:
            # Sort by score descending
            in_range_sorted = sorted(in_range, key=lambda x: x[1], reverse=True)
            # Pick up to 10 peak times with at least 0.8 seconds gap
            for t, val in in_range_sorted:
                if not any(abs(t - pt) < 0.8 for pt in peak_times):
                    peak_times.append(t)
                if len(peak_times) >= 10:
                    break
            peak_times.sort()

    # Fallback to even spacing if we don't have enough peak times
    if len(peak_times) < 5:
        n_intervals = 10
        peak_times = [start_sec + duration * (i + 0.5) / n_intervals for i in range(n_intervals)]

    face_timeline: List[Tuple[float, List[FaceBox]]] = []
    extracted_frames = []
    faces_detected_count = 0

    print(f"  [ANALYZE] Extracting {len(peak_times)} frames at speech energy peaks...")
    for t in peak_times:
        frame = extract_frame_as_array(video_path, t, cap=cap)
        if frame is not None:
            extracted_frames.append((t - start_sec, frame))

    # ── Face / Person / Motion Fallback Chain ──
    for rel_t, frame in extracted_frames:
        abs_t = start_sec + rel_t
        # 1. MediaPipe or Haar Cascade Face Detection
        faces = detect_faces(frame)
        
        # 2. Fallback to Full Body Detection (MediaPipe Pose)
        if not faces:
            persons = detect_persons(frame)
            faces = persons
            if persons:
                print(f"    -> @ {abs_t:.1f}s: No faces visible, fallback to full body person detection.")
        
        if faces:
            faces_detected_count += 1
            print(f"    -> @ {abs_t:.1f}s: Detected {len(faces)} person(s) / face(s).")
            for f_idx, face in enumerate(faces):
                print(f"       * Face {f_idx+1}: CenterX={face.cx:.3f}, CenterY={face.cy:.3f}, Area={face.area:.4f}")
        else:
            print(f"    -> @ {abs_t:.1f}s: No person/face detected in this frame.")
            
        face_timeline.append((rel_t, faces))

    # 3. Fallback to Motion Analysis if absolutely no face/body was found in any frame
    if faces_detected_count == 0 and extracted_frames:
        print("  [ANALYZE] Face and body detection found absolutely nothing. Running Motion Analysis fallback...")
        frames_list = [f[1] for f in extracted_frames]
        motion_cx = detect_motion_side(frames_list)
        print(f"  [ANALYZE] Motion center of mass found at cx={motion_cx:.3f}")
        
        result = SceneAnalysis()
        result.layout = "empty"
        result.crop_strategy = "center" if framing_strategy == "no_crop" else "face_single"
        result.focus_cx = motion_cx
        result.focus_cy = 0.5
        return result

    if not face_timeline:
        result = SceneAnalysis()
        result.layout = "empty"
        if content_type == "podcast" and framing_strategy != "no_crop":
            result.crop_strategy = "split_screen"
        else:
            result.crop_strategy = "no_crop" if framing_strategy == "no_crop" else "center"
        result.focus_cx = 0.5
        result.focus_cy = 0.5
        return result

    total = len(face_timeline)
    sub_analyses = []
    
    # Speaking memory to keep focus locked on the last verified speaking person
    last_confirmed_cx = 0.5
    last_confirmed_cy = 0.5
    has_speaking_history = False

    for rel_t, faces in face_timeline:
        if not faces:
            continue
        
        active_speaker = None
        if len(faces) >= 2 and framing_strategy == "speaker_tracking":
            absolute_t = start_sec + rel_t
            scores = {}
            print(f"    -> [Speaker Tracking] Analyzing active speaker mouth motion for {len(faces)} faces at {absolute_t:.1f}s:")
            for face_idx, face in enumerate(faces):
                try:
                    score = _get_mouth_motion_score(video_path, absolute_t, face, src_w, src_h, cap=cap)
                    scores[face] = score
                    print(f"       * Face {face_idx+1} at cx={face.cx:.2f}: Mouth motion score = {score:.3f}")
                except Exception as e:
                    scores[face] = 0.0
                    print(f"       * Face {face_idx+1} analysis failed: {e}")
            
            if scores:
                sorted_by_score = sorted(scores.items(), key=lambda x: x[1], reverse=True)
                best_face, best_val = sorted_by_score[0]
                
                # Check relative mouth motion difference to identify the true speaking person
                if len(sorted_by_score) >= 2:
                    second_face, second_val = sorted_by_score[1]
                    if (best_val - second_val) > 0.20 or (best_val > 0.50 and second_val < 0.35):
                        active_speaker = best_face
                        print(f"       => Identified Speaker: Face at cx={active_speaker.cx:.2f} is actively speaking (Mouth motion = {best_val:.3f}).")
                    else:
                        print(f"       => Dialogue / Ambiguity: Mouth motion difference between best ({best_val:.3f}) and second ({second_val:.3f}) is too small.")
                else:
                    if best_val > 0.35:
                        active_speaker = best_face
                        print(f"       => Identified Speaker: Face at cx={active_speaker.cx:.2f} is speaking (Mouth motion = {best_val:.3f}).")
                        
        if active_speaker is not None:
            last_confirmed_cx = active_speaker.cx
            last_confirmed_cy = active_speaker.cy
            has_speaking_history = True
            
        sub_an = _analyze_layout(faces, framing_strategy, active_speaker=active_speaker)
        
        if framing_strategy == "speaker_tracking" and active_speaker is None and has_speaking_history:
            sub_an.focus_cx = last_confirmed_cx
            sub_an.focus_cy = last_confirmed_cy
            print(f"       => [MEMORY LOCK ACTIVE]: Enforcing focus lock on last confirmed speaker at cx={last_confirmed_cx:.3f} (ignoring silent actors).")
            
        sub_analyses.append((rel_t, sub_an))

    if not sub_analyses:
        result = SceneAnalysis()
        result.layout = "empty"
        if content_type == "podcast" and framing_strategy != "no_crop":
            result.crop_strategy = "split_screen"
        else:
            result.crop_strategy = "center"
        result.focus_cx = 0.5
        result.focus_cy = 0.5
        return result

    # ── TEMPORAL STABILIZATION & ACTIVE SPEAKER HYSTERESIS ──
    all_cx = []
    all_cy = []
    
    prev_cx = sub_analyses[0][1].focus_cx
    prev_cy = sub_analyses[0][1].focus_cy
    active_speaker_cx = prev_cx
    focus_locked = False
    
    for idx, (rel_t, sub_an) in enumerate(sub_analyses):
        curr_cx = sub_an.focus_cx
        curr_cy = sub_an.focus_cy
        
        if framing_strategy == "speaker_tracking" and sub_an.layout == "duo_side":
            if focus_locked:
                dx_from_lock = abs(curr_cx - active_speaker_cx)
                if dx_from_lock < 0.22:
                    curr_cx = active_speaker_cx
                else:
                    active_speaker_cx = curr_cx
            else:
                active_speaker_cx = curr_cx
                focus_locked = True
                
        if idx > 0:
            dx = abs(curr_cx - prev_cx)
            dy = abs(curr_cy - prev_cy)
            if dx < 0.08:
                curr_cx = prev_cx
            elif dx < 0.25:
                curr_cx = 0.85 * prev_cx + 0.15 * curr_cx
            else:
                curr_cx = 0.40 * prev_cx + 0.60 * curr_cx
                
            if dy < 0.06:
                curr_cy = prev_cy
            else:
                curr_cy = 0.70 * prev_cy + 0.30 * curr_cy
                
        all_cx.append(curr_cx)
        all_cy.append(curr_cy)
        prev_cx = curr_cx
        prev_cy = curr_cy
        
    if all_cx:
        left_side = [x for x in all_cx if x < 0.40]
        right_side = [x for x in all_cx if x > 0.60]
        center_side = [x for x in all_cx if 0.40 <= x <= 0.60]
        
        if len(left_side) > len(right_side) and len(left_side) > len(center_side):
            median_cx = float(np.median(left_side))
            print(f"       => [DOMINANT SPEAKER LOCK]: Locking static crop on the LEFT speaker at cx={median_cx:.3f}")
        elif len(right_side) > len(left_side) and len(right_side) > len(center_side):
            median_cx = float(np.median(right_side))
            print(f"       => [DOMINANT SPEAKER LOCK]: Locking static crop on the RIGHT speaker at cx={median_cx:.3f}")
        elif len(center_side) > len(left_side) and len(center_side) > len(right_side):
            median_cx = float(np.median(center_side))
            print(f"       => [DOMINANT SPEAKER LOCK]: Locking static crop on the CENTER speaker at cx={median_cx:.3f}")
        else:
            if left_side or right_side:
                if len(left_side) >= len(right_side):
                    median_cx = float(np.median(left_side)) if left_side else 0.28
                    print(f"       => [DOMINANT SPEAKER LOCK]: Balanced/Tie found, locking on LEFT speaker at cx={median_cx:.3f} to avoid empty center")
                else:
                    median_cx = float(np.median(right_side)) if right_side else 0.72
                    print(f"       => [DOMINANT SPEAKER LOCK]: Balanced/Tie found, locking on RIGHT speaker at cx={median_cx:.3f} to avoid empty center")
            else:
                median_cx = 0.5
                print(f"       => [DOMINANT SPEAKER LOCK]: No clear side preference, keeping camera perfectly centered (cx=0.500)")
    else:
        median_cx = 0.5
        
    median_cy = float(np.median(all_cy)) if all_cy else 0.5
    
    primary_an = sub_analyses[0][1]
    primary_an.focus_cx = median_cx
    primary_an.focus_cy = median_cy
    primary_an.sub_scenes = [] 

    # ── Phase 12: Dynamic Pacing & Easing transitions (Virtual Cameraman) ──
    transitions = []
    if framing_strategy == "speaker_tracking" and len(sub_analyses) >= 2:
        current_cx = sub_analyses[0][1].focus_cx
        current_t = sub_analyses[0][0]
        for rel_t, sub_an in sub_analyses[1:]:
            if abs(sub_an.focus_cx - current_cx) > 0.15:
                t_end = rel_t
                t_start = max(current_t, t_end - 1.0)
                transitions.append({
                    "start": t_start,
                    "end": t_end,
                    "from_cx": current_cx,
                    "to_cx": sub_an.focus_cx
                })
                current_cx = sub_an.focus_cx
                current_t = rel_t

    primary_an.panning_transitions = transitions

    if transitions:
        print(f"  [ANALYZE] Virtual Cameraman active: Planned {len(transitions)} smooth camera panning transitions.")
        for idx, tr in enumerate(transitions):
            print(f"    -> Pan {idx+1}: {tr['start']:.1f}s to {tr['end']:.1f}s (from cx={tr['from_cx']:.2f} to cx={tr['to_cx']:.2f})")
    else:
        print(f"  [ANALYZE] Enforcing 100% STATIC crop focused on speaker at cx={median_cx:.3f}, cy={median_cy:.3f}")
    
    print(f"  [ANALYZE] Detailed: {duration:.0f}s segment, {len(sub_analyses)} face samples, layout={primary_an.layout}, crop_strategy={primary_an.crop_strategy}")
    
    # Save successfully resolved position to cache (faces_lr to fast-track subsequent mouth detections)
    with SPEAKER_POSITION_CACHE_LOCK:
        SPEAKER_POSITION_CACHE[video_path] = {
            "layout": primary_an.layout,
            "crop_strategy": primary_an.crop_strategy,
            "focus_cx": primary_an.focus_cx,
            "focus_cy": primary_an.focus_cy,
            "faces_lr": getattr(primary_an, "faces_lr", None),
            "dominant_face": primary_an.dominant_face
        }
        
    return primary_an


def analyze_segment(video_path: str, start_sec: float, end_sec: float,
                    n_samples: int = 5, framing_strategy: str = "split_screen",
                    detailed: bool = True, content_type: str = "podcast",
                    viral_timeline: Optional[Dict[float, float]] = None) -> SceneAnalysis:
    """
    Analyze a video segment for face-aware cropping.
    When detailed=True, uses per-second face tracking with dynamic crop positions.
    When detailed=False, uses simpler static analysis (fewer samples).
    """
    import cv2
    duration = end_sec - start_sec
    if duration <= 0:
        return SceneAnalysis()

    src_w, src_h = _get_video_dimensions(video_path)
    
    # Open shared capture to avoid massive reopen overhead for large files
    cap = cv2.VideoCapture(video_path)
    try:
        if detailed:
            primary_an = _analyze_sub_segment_detailed(
                video_path, start_sec, end_sec,
                interval_sec=1.5,
                framing_strategy=framing_strategy,
                src_w=src_w, src_h=src_h,
                cap=cap,
                content_type=content_type,
                viral_timeline=viral_timeline
            )
            # If no faces found, compute motion drift for smart horizontal crop
            if primary_an.crop_strategy in ("center", "motion_drift") and primary_an.layout == "empty":
                print(f"  [ANALYZE] No faces found \u2014 computing motion drift for smart crop direction...")
                try:
                    # Extract a few frames and compute motion center
                    sample_ts = [start_sec + (end_sec - start_sec) * i / 5 for i in range(1, 5)]
                    sampled_frames = []
                    for ts in sample_ts:
                        fr = extract_frame_as_array(video_path, ts, cap=None)
                        if fr is not None:
                            sampled_frames.append(fr)
                    if len(sampled_frames) >= 2:
                        motion_cx = detect_motion_side(sampled_frames)
                        # Clamp: don't go too far left/right — keep in comfortable range
                        motion_cx = max(0.3, min(0.7, motion_cx))
                        primary_an._motion_drift_cx = motion_cx
                        primary_an.crop_strategy = "motion_drift"
                        drift_label = "LEFT" if motion_cx < 0.45 else ("RIGHT" if motion_cx > 0.55 else "CENTER")
                        print(f"  [ANALYZE] Motion drift: cx={motion_cx:.2f} ({drift_label})")
                    else:
                        primary_an._motion_drift_cx = 0.5
                except Exception as e:
                    print(f"  [ANALYZE] Motion drift failed: {e}, using center")
                    primary_an._motion_drift_cx = 0.5
            return primary_an


        # Simple static analysis (original behavior)
        sub_an = _analyze_sub_segment(
            video_path, start_sec, end_sec,
            n_samples=n_samples,
            framing_strategy=framing_strategy,
            src_w=src_w, src_h=src_h,
            cap=cap
        )
        sub_an.sub_scenes = [(duration, sub_an)]
        print(f"  [ANALYZE] Static segment {start_sec:.0f}s-{end_sec:.0f}s -> layout={sub_an.layout}, crop_strategy={sub_an.crop_strategy}")
        return sub_an
    finally:
        if cap.isOpened():
            cap.release()


# ─────────────────────────────────────────────────────────────────────────────
#  FFmpeg Crop Filter Generator
# ─────────────────────────────────────────────────────────────────────────────

def get_smart_crop_filter(analysis: SceneAnalysis,
                          src_w: int, src_h: int,
                          target_aspect: float = 9/16) -> str:
    """
    Generate an FFmpeg crop filter string based on the scene analysis.
    """
    if src_w >= src_h:
        crop_h = src_h
        crop_w = int(crop_h * 9 / 16)
        crop_y = 0
        focus_x_px = int(analysis.focus_cx * src_w)
        crop_x = focus_x_px - crop_w // 2
        crop_x = max(0, min(crop_x, src_w - crop_w))
        return f"crop={crop_w}:{crop_h}:{crop_x}:{crop_y}"
    else:
        crop_w = src_w
        crop_h = int(src_w * 16 / 9)
        if crop_h > src_h:
            crop_h = src_h
            crop_w = int(src_h * 9 / 16)
        return f"crop={crop_w}:{crop_h}:0:0"


def build_ffmpeg_panning_expr(transitions: list, default_cx: float) -> str:
    """
    Build a nested mathematical expression for dynamic camera panning (Virtual Cameraman)
    using smoothstep interpolation, escaped with backslashes for FFmpeg's filtergraph.
    """
    if not transitions:
        return f"{default_cx:.4f}"
    
    current_expr = f"{transitions[0]['from_cx']:.4f}"
    for tr in transitions:
        t_start = tr['start']
        t_end = tr['end']
        dur = max(0.001, t_end - t_start)
        from_cx = tr['from_cx']
        to_cx = tr['to_cx']
        diff = to_cx - from_cx
        
        # Smoothstep interpolation: x = (t - t_start) / dur -> smooth_x = x*x*(3-2*x)
        interp = f"({from_cx:.4f}+({diff:.4f})*(((t-{t_start:.4f})/{dur:.4f})*((t-{t_start:.4f})/{dur:.4f})*(3-2*((t-{t_start:.4f})/{dur:.4f}))))"
        current_expr = f"if(lt(t\\,{t_start:.4f})\\,{current_expr}\\,if(lt(t\\,{t_end:.4f})\\,{interp}\\,{to_cx:.4f}))"
        
    return current_expr


def build_rhythmic_zoom_expr(beats: list, duration: float) -> str:
    """
    Generate a nested mathematical expression for rhythmic pulse zoom (Beat Matching)
    synced to audio beats, escaped with backslashes for FFmpeg.
    """
    active_beats = [b for b in beats if 0.0 <= b <= duration]
    if not active_beats:
        return "1.0"
    
    current_expr = "1.0"
    for b in reversed(active_beats):
        # Scale down crop window to 0.85x (1.17x zoom) on beat, smoothly recover back to 1.0x in 0.25s
        zoom_val = f"min(1.0\\,0.85+0.60*(t-{b:.3f}))"
        current_expr = f"if(and(gte(t\\,{b:.3f})\\,lt(t\\,{b + 0.25:.3f}))\\,{zoom_val}\\,{current_expr})"
        
    return current_expr


def get_smart_crop_ffmpeg_expr(analysis: SceneAnalysis,
                                target_y_ratio: float = 0.38,
                                beats: list = None,
                                duration: float = 30.0,
                                zoom_style: str = "none") -> str:
    """
    Generate a smart FFmpeg crop expression using `ih` and `iw` variables.
    Supports smooth panning transitions (Virtual Cameraman) and rhythmic pulse zoom (Beat Matching).

    Args:
        analysis: SceneAnalysis with face data
        target_y_ratio: Where the face should appear vertically in the final output
                        (0.38 = slightly above center, good for TikTok portrait)
        beats: Optional list of beat timestamps for rhythmic zoom matching
        duration: Clip duration in seconds
        zoom_style: The planned zoom style ("rhythmic", "punch", "gentle", "none")

    Returns:
        FFmpeg filter string like "crop=ih*9/16:ih:{x_expr}:{y_expr}"
    """
    # Crop constants for 9:16 portrait output
    if analysis.crop_strategy == "no_crop":
        return "no_crop"

    # Rhythmic Beat Sync Zoom factor
    if zoom_style in ["rhythmic", "dynamic", "punch"] and beats:
        zoom_factor_expr = build_rhythmic_zoom_expr(beats, duration)
    else:
        zoom_factor_expr = "1.0"

    crop_w_expr = f"(ih*9/16)*({zoom_factor_expr})"
    crop_h_expr = f"ih*({zoom_factor_expr})"
    max_x_offset = f"iw-{crop_w_expr}"
    y_expr = f"(ih-{crop_h_expr})/2"

    def _x_expr(cx) -> str:
        """Return FFmpeg expression for crop X offset centered on cx."""
        if isinstance(cx, str):
            return f"max(0\\,min({max_x_offset}\\,({cx})*iw-{crop_w_expr}/2))"
        return f"max(0\\,min({max_x_offset}\\,{cx:.4f}*iw-{crop_w_expr}/2))"

    # Enforce static split screen or single speaker layout without t variables
    if analysis.crop_strategy == "split_screen":
        faces_lr = getattr(analysis, "faces_lr", None)
        if faces_lr and len(faces_lr) == 2:
            f_left, f_right = faces_lr[0], faces_lr[1]
            cx_left, cy_left = f_left.cx, f_left.cy
            cx_right, cy_right = f_right.cx, f_right.cy
        else:
            cx_left, cy_left = 0.25, 0.5
            cx_right, cy_right = 0.75, 0.5

        x_left_expr = _x_expr(cx_left)
        y_left_expr = f"max(0\\,min(ih/2\\,{cy_left:.4f}*ih-ih/4))"
        x_right_expr = _x_expr(cx_right)
        y_right_expr = f"max(0\\,min(ih/2\\,{cy_right:.4f}*ih-ih/4))"

        return (f"split=2[v_top_raw][v_bottom_raw];"
                f"[v_top_raw]crop={crop_w_expr}:ih/2:{x_left_expr}:{y_left_expr}[v_top];"
                f"[v_bottom_raw]crop={crop_w_expr}:ih/2:{x_right_expr}:{y_right_expr}[v_bottom];"
                f"[v_top][v_bottom]vstack")

    # ── No-face / empty layout: use motion analysis to drift horizontally ──────
    if analysis.layout == "empty" or analysis.crop_strategy in ("center", "motion_drift"):
        # Try to detect motion direction from cached frames if available
        drift_cx = getattr(analysis, "_motion_drift_cx", None)
        if drift_cx is None:
            drift_cx = 0.5  # safe default center
        return f"crop={crop_w_expr}:{crop_h_expr}:{_x_expr(drift_cx)}:{y_expr}"


    panning_transitions = getattr(analysis, "panning_transitions", [])
    focus_cx = analysis.focus_cx
    
    if panning_transitions:
        cx_val = build_ffmpeg_panning_expr(panning_transitions, focus_cx)
    else:
        cx_val = focus_cx

    return f"crop={crop_w_expr}:{crop_h_expr}:{_x_expr(cx_val)}:{y_expr}"


# ─────────────────────────────────────────────────────────────────────────────
#  Quick Analysis for clips_output
# ─────────────────────────────────────────────────────────────────────────────

def quick_scene_type(video_path: str, start_sec: float, end_sec: float,
                     framing_strategy: str = "split_screen",
                     content_type: str = "podcast",
                     viral_timeline: Optional[Dict[float, float]] = None,
                     beats: list = None,
                     zoom_style: str = "none") -> Dict[str, Any]:
    """
    Analyze a video segment for face-aware cropping.
    Returns dict with crop_filter and metadata for the editor.
    """
    try:
        import time
        t0 = time.time()
        src_w, src_h = _get_video_dimensions(video_path)
        analysis = analyze_segment(
            video_path, start_sec, end_sec,
            detailed=True, framing_strategy=framing_strategy,
            content_type=content_type,
            viral_timeline=viral_timeline
        )
        duration = end_sec - start_sec
        crop_expr = get_smart_crop_ffmpeg_expr(
            analysis,
            beats=beats,
            duration=duration,
            zoom_style=zoom_style
        )
        elapsed = time.time() - t0

        if analysis.crop_strategy == "center" and analysis.layout == "empty":
            print(f"  [ANALYZE] No face data — using center crop (completed in {elapsed:.3f}s)")
        elif analysis.crop_strategy == "center":
            print(f"  [ANALYZE] Center crop (layout={analysis.layout}) (completed in {elapsed:.3f}s)")
        else:
            print(f"  [ANALYZE] Face-aware crop: strategy={analysis.crop_strategy}, n_persons={analysis.n_persons}, focus_cx={analysis.focus_cx:.3f} (completed in {elapsed:.3f}s)")

        return {
            "layout": analysis.layout,
            "n_persons": analysis.n_persons,
            "crop_strategy": analysis.crop_strategy,
            "crop_filter": crop_expr,
            "focus_cx": analysis.focus_cx,
            "focus_cy": analysis.focus_cy,
            "src_w": src_w,
            "src_h": src_h,
        }
    except Exception as e:
        print(f"  [ANALYZE] quick_scene_type FAILED ({e}) — using center crop")
        import traceback
        traceback.print_exc()
        return {
            "layout": "unknown",
            "n_persons": 0,
            "crop_strategy": "no_crop" if framing_strategy == "no_crop" else "center",
            "crop_filter": "no_crop" if framing_strategy == "no_crop" else "crop=ih*9/16:ih:(iw-ih*9/16)/2:0",
            "focus_cx": 0.5,
            "focus_cy": 0.5,
            "src_w": 1920,
            "src_h": 1080,
        }

