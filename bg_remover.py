# bg_remover.py
# Fast AI Background Removal using MediaPipe Selfie Segmentation

import cv2
import numpy as np

def create_greenscreen_video(input_path: str, output_path: str, trim_start: float = 0, trim_end: float = 0):
    """
    Processes a video, extracts the person using AI, and replaces the background with solid green.
    """
    try:
        import mediapipe as mp
    except ImportError:
        raise ImportError("Please install mediapipe: pip install mediapipe")

    mp_selfie_segmentation = mp.solutions.selfie_segmentation
    
    cap = cv2.VideoCapture(input_path)
    if not cap.isOpened():
        raise RuntimeError(f"Could not open video {input_path}")
        
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(output_path, fourcc, fps, (width, height))
    
    start_frame = int(trim_start * fps)
    
    # Total frames fallback
    total_frames = cap.get(cv2.CAP_PROP_FRAME_COUNT)
    if total_frames <= 0:
        total_frames = 1000000
        
    end_frame = int(trim_end * fps) if trim_end > trim_start else int(total_frames)
    
    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
    current_frame = start_frame
    
    bg_color = (0, 255, 0) # Green in BGR
    bg_image = np.zeros((height, width, 3), dtype=np.uint8)
    bg_image[:] = bg_color
    
    # model_selection=1 is the fast landscape model, model_selection=0 is general
    with mp_selfie_segmentation.SelfieSegmentation(model_selection=1) as selfie_segmentation:
        while current_frame < end_frame:
            ret, frame = cap.read()
            if not ret:
                break
                
            frame.flags.writeable = False
            frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = selfie_segmentation.process(frame_rgb)
            
            frame.flags.writeable = True
            
            # The condition is a mask: > 0.1 is foreground
            # Mask is float32 [0.0, 1.0]
            condition = np.stack((results.segmentation_mask,) * 3, axis=-1) > 0.1
            
            # Combine frame with green screen
            output_image = np.where(condition, frame, bg_image)
            
            out.write(output_image)
            current_frame += 1
            
            if current_frame % 30 == 0:
                print(f"  [BG_REMOVER] Processed frame {current_frame} / {end_frame}")
            
    cap.release()
    out.release()
    print(f"  [BG_REMOVER] Saved greenscreen video to: {output_path}")
