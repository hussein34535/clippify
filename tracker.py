# tracker.py
# Local Face Tracking & Auto-Framing using OpenCV Haar Cascades

import os
import cv2
from typing import List, Dict, Any

def track_faces_in_video(video_path: str, start_sec: float, end_sec: float) -> List[Dict[str, Any]]:
    """
    Reads the video file between start_sec and end_sec, detects faces using OpenCV,
    and generates timeline transform position keyframes to keep the face centered.
    """
    if not os.path.exists(video_path):
        return []

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return []

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    width = cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 1920.0
    height = cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 1080.0
    
    # Load OpenCV Face Detector cascade
    cascade_path = cv2.data.haarcascades + 'haarcascade_frontalface_default.xml'
    face_cascade = cv2.CascadeClassifier(cascade_path)
    if face_cascade.empty():
        # Fallback if XML not loaded
        cap.release()
        return []

    # Target aspect ratio is 9:16 (vertical crop)
    # The active width of a 9:16 crop in a 16:9 1080p frame is height * (9/16)
    target_crop_width = height * (9.0 / 16.0)
    center_x_original = width / 2.0

    keyframes = []
    
    # Fast-forward to start_sec
    start_frame = int(start_sec * fps)
    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
    
    current_frame = start_frame
    end_frame = int(end_sec * fps)
    
    raw_positions = []
    
    # Sample every 5 frames for speed and stability
    sample_step = 5
    
    while current_frame < end_frame:
        ret, frame = cap.read()
        if not ret:
            break
            
        if (current_frame - start_frame) % sample_step == 0:
            time_offset = (current_frame - start_frame) / fps
            
            # Grayscale frame for cascade detector
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            # Detect faces (downscale for speed)
            gray_small = cv2.resize(gray, (0, 0), fx=0.5, fy=0.5)
            faces = face_cascade.detectMultiScale(gray_small, scaleFactor=1.2, minNeighbors=3, minSize=(30, 30))
            
            if len(faces) > 0:
                # Get the largest face
                largest_face = max(faces, key=lambda f: f[2] * f[3])
                # Scale coordinates back to original frame size
                fx, fy, fw, fh = [coord * 2 for coord in largest_face]
                
                # Face center
                face_center_x = fx + fw / 2.0
                
                # Calculate required delta offset from center to keep face centered
                # offset_x = center_x_original - face_center_x
                # Max constraint: crop box must not exceed video left/right edges
                max_offset = (width - target_crop_width) / 2.0
                offset_x = center_x_original - face_center_x
                offset_x = max(-max_offset, min(max_offset, offset_x))
                
                raw_positions.append((time_offset, offset_x))
                
        current_frame += 1

    cap.release()

    if not raw_positions:
        return []

    # Smooth the offsets using rolling average to avoid camera jitters
    smoothed_positions = []
    window_size = 5
    n = len(raw_positions)
    
    for i in range(n):
        t, _ = raw_positions[i]
        start_idx = max(0, i - window_size // 2)
        end_idx = min(n, i + window_size // 2 + 1)
        
        avg_offset = sum(raw_positions[j][1] for j in range(start_idx, end_idx)) / (end_idx - start_idx)
        
        # Add keyframe
        keyframes.append({
            "time": round(t, 2),
            "property": "position",
            "value": {"x": round(avg_offset, 1), "y": 0.0},
            "easing": "ease-in-out"
        })
        
    return keyframes
