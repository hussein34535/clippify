import sys
import json
import os
import cv2
import numpy as np

def track_point(video_path, init_x, init_y, max_frames=0):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return {"error": "Cannot open video", "keyframes": []}

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if max_frames > 0:
        total_frames = min(total_frames, max_frames)

    ret, frame = cap.read()
    if not ret:
        cap.release()
        return {"error": "Cannot read first frame", "keyframes": []}

    h, w = frame.shape[:2]
    bbox = (int(init_x - 20), int(init_y - 20), 40, 40)
    bbox = (
        max(0, bbox[0]), max(0, bbox[1]),
        min(w - bbox[0], bbox[2]), min(h - bbox[1], bbox[3])
    )

    tracker = cv2.TrackerCSRT_create()
    tracker.init(frame, bbox)

    keyframes = []
    frame_idx = 0

    while frame_idx < total_frames:
        ret, frame = cap.read()
        if not ret:
            break

        success, box = tracker.update(frame)
        if success:
            cx = box[0] + box[2] / 2.0
            cy = box[1] + box[3] / 2.0
            t = frame_idx / fps
            keyframes.append({"time": round(t, 3), "x": round(cx, 1), "y": round(cy, 1)})

        frame_idx += 1

    cap.release()
    return {"keyframes": keyframes, "total_frames": frame_idx}


def track_faces(video_path, max_frames=0):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return {"error": "Cannot open video", "keyframes": []}

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if max_frames > 0:
        total_frames = min(total_frames, max_frames)

    cascade_path = cv2.data.haarcascades + 'haarcascade_frontalface_default.xml'
    face_cascade = cv2.CascadeClassifier(cascade_path)
    if face_cascade.empty():
        cap.release()
        return {"error": "Face cascade not found", "keyframes": []}

    keyframes = []
    frame_idx = 0

    while frame_idx < total_frames:
        ret, frame = cap.read()
        if not ret:
            break

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        faces = face_cascade.detectMultiScale(gray, scaleFactor=1.2, minNeighbors=3, minSize=(30, 30))

        t = frame_idx / fps
        if len(faces) > 0:
            largest = max(faces, key=lambda f: f[2] * f[3])
            fx, fy, fw, fh = [int(v) for v in largest]
            keyframes.append({
                "time": round(t, 3),
                "x": fx, "y": fy, "w": fw, "h": fh,
                "confidence": 1.0
            })
        else:
            keyframes.append({
                "time": round(t, 3),
                "x": 0, "y": 0, "w": 0, "h": 0,
                "confidence": 0.0
            })

        frame_idx += 1

    cap.release()
    return {"keyframes": keyframes, "total_frames": frame_idx}


def track_planar(video_path, rx, ry, rw, rh, max_frames=0):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return {"error": "Cannot open video", "keyframes": []}

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if max_frames > 0:
        total_frames = min(total_frames, max_frames)

    ret, ref_frame = cap.read()
    if not ret:
        cap.release()
        return {"error": "Cannot read first frame", "keyframes": []}

    ref_pts = np.array([
        [rx, ry],
        [rx + rw, ry],
        [rx + rw, ry + rh],
        [rx, ry + rh]
    ], dtype=np.float32)

    ref_gray = cv2.cvtColor(ref_frame, cv2.COLOR_BGR2GRAY)
    ref_mask = np.zeros(ref_gray.shape, dtype=np.uint8)
    cv2.fillPoly(ref_mask, [ref_pts.astype(np.int32)], 255)
    ref_kp, ref_desc = cv2.ORB_create().detectAndCompute(ref_gray, ref_mask)

    bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)

    keyframes = []
    frame_idx = 0

    while frame_idx < total_frames:
        ret, frame = cap.read()
        if not ret:
            break

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        kp, desc = cv2.ORB_create().detectAndCompute(gray, None)

        homography = None
        if ref_desc is not None and desc is not None and len(ref_desc) > 3 and len(desc) > 3:
            matches = bf.match(ref_desc, desc)
            matches = sorted(matches, key=lambda x: x.distance)[:50]

            if len(matches) >= 4:
                src_pts = np.float32([ref_kp[m.queryIdx].pt for m in matches]).reshape(-1, 1, 2)
                dst_pts = np.float32([kp[m.trainIdx].pt for m in matches]).reshape(-1, 1, 2)
                H, mask = cv2.findHomography(src_pts, dst_pts, cv2.RANSAC, 5.0)

                if H is not None:
                    homography = H.tolist()
                    pts = cv2.perspectiveTransform(ref_pts.reshape(-1, 1, 2), H)
                    pts = pts.reshape(-1, 2).tolist()

        t = frame_idx / fps
        keyframes.append({
            "time": round(t, 3),
            "homography": homography,
            "corners": pts if homography else None
        })

        frame_idx += 1

    cap.release()
    return {"keyframes": keyframes, "total_frames": frame_idx}


def main():
    if len(sys.argv) < 3:
        print(json.dumps({"error": "Usage: tracker.py <mode> <video> [args...]"}))
        sys.exit(1)

    mode = sys.argv[1]
    video_path = sys.argv[2]

    if not os.path.exists(video_path):
        print(json.dumps({"error": f"Video not found: {video_path}"}))
        sys.exit(1)

    result = {}

    if mode == "point":
        if len(sys.argv) < 5:
            print(json.dumps({"error": "point mode: tracker.py point <video> <x> <y> [max_frames]"}))
            sys.exit(1)
        x = float(sys.argv[3])
        y = float(sys.argv[4])
        max_frames = int(sys.argv[5]) if len(sys.argv) > 5 else 0
        result = track_point(video_path, x, y, max_frames)

    elif mode == "faces":
        max_frames = int(sys.argv[3]) if len(sys.argv) > 3 else 0
        result = track_faces(video_path, max_frames)

    elif mode == "planar":
        if len(sys.argv) < 7:
            print(json.dumps({"error": "planar mode: tracker.py planar <video> <x> <y> <w> <h> [max_frames]"}))
            sys.exit(1)
        rx = float(sys.argv[3])
        ry = float(sys.argv[4])
        rw = float(sys.argv[5])
        rh = float(sys.argv[6])
        max_frames = int(sys.argv[7]) if len(sys.argv) > 7 else 0
        result = track_planar(video_path, rx, ry, rw, rh, max_frames)

    else:
        print(json.dumps({"error": f"Unknown mode: {mode}. Use: point, faces, planar"}))
        sys.exit(1)

    print(json.dumps(result))


if __name__ == "__main__":
    main()
