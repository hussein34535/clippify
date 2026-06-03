# keyframe_engine.py
# Engine to handle keyframe calculation, easing, and FFmpeg expression generation

import math
from typing import List, Dict, Any, Union

def interpolate_value(t: float, keyframes: List[Dict[str, Any]], prop: str, default_value: Any) -> Any:
    """
    Interpolates the value of a property at time 't' based on a list of keyframes.
    Supports linear, ease-in, ease-out, and ease-in-out interpolation.
    """
    filtered = [kf for kf in keyframes if kf.get("property") == prop]
    if not filtered:
        return default_value

    # Sort keyframes by time
    filtered.sort(key=lambda x: x["time"])

    # If t is before the first keyframe
    if t <= filtered[0]["time"]:
        return filtered[0]["value"]

    # If t is after the last keyframe
    if t >= filtered[-1]["time"]:
        return filtered[-1]["value"]

    # Find the two keyframes surrounding t
    for i in range(len(filtered) - 1):
        kf1 = filtered[i]
        kf2 = filtered[i + 1]
        t1, v1 = kf1["time"], kf1["value"]
        t2, v2 = kf2["time"], kf2["value"]

        if t1 <= t <= t2:
            duration = t2 - t1
            if duration == 0:
                return v2

            ratio = (t - t1) / duration
            easing = kf1.get("easing", "linear")

            # Apply easing math
            if easing == "ease-in-out":
                ratio = (1.0 - math.cos(ratio * math.pi)) / 2.0
            elif easing == "ease-in":
                ratio = ratio * ratio
            elif easing == "ease-out":
                ratio = ratio * (2.0 - ratio)

            # Interpolate scalar or vector objects
            if isinstance(default_value, dict) or (isinstance(v1, dict) and isinstance(v2, dict)):
                # Vector2D case
                x1 = v1.get("x", 0.0) if isinstance(v1, dict) else v1
                y1 = v1.get("y", 0.0) if isinstance(v1, dict) else v1
                x2 = v2.get("x", 0.0) if isinstance(v2, dict) else v2
                y2 = v2.get("y", 0.0) if isinstance(v2, dict) else v2
                return {
                    "x": x1 + ratio * (x2 - x1),
                    "y": y1 + ratio * (y2 - y1)
                }
            
            # Scalar case
            return v1 + ratio * (v2 - v1)

    return default_value

def generate_ffmpeg_expression(keyframes: List[Dict[str, Any]], prop: str, default_value: float, is_vector_axis: str = None) -> str:
    """
    Generates a nested FFmpeg math expression (in terms of variable 't') representing
    the animated property value across all keyframes.
    
    If it's a Vector2D property, specify is_vector_axis as 'x' or 'y'.
    """
    filtered = [kf for kf in keyframes if kf.get("property") == prop]
    if not filtered:
        return str(default_value)

    # Sort keyframes by time
    filtered.sort(key=lambda x: x["time"])

    # Extract scalar value from keyframe value (in case it is dict/Vector2D)
    def get_val(v):
        if isinstance(v, dict):
            return v.get(is_vector_axis or "x", 0.0)
        return float(v)

    # If only one keyframe
    if len(filtered) == 1:
        return str(get_val(filtered[0]["value"]))

    # We build the expression backwards (nested if-else)
    # FFmpeg if syntax: if(cond, then, else)
    # For a keyframe segment i from t_i to t_i+1:
    # expr = if(lt(t, t_i+1), v_i + (v_i+1 - v_i) * (t - t_i) / (t_i+1 - t_i), next_nested_if)
    
    last_val = get_val(filtered[-1]["value"])
    expr = str(last_val)

    for i in range(len(filtered) - 2, -1, -1):
        kf1 = filtered[i]
        kf2 = filtered[i + 1]
        t1, v1 = kf1["time"], get_val(kf1["value"])
        t2, v2 = kf2["time"], get_val(kf2["value"])
        duration = t2 - t1
        
        if duration == 0:
            segment_expr = str(v2)
        else:
            # Linear transition: v1 + (v2 - v1) * (t - t1) / duration
            diff = v2 - v1
            segment_expr = f"({v1} + ({diff}) * (t - {t1}) / {duration})"

        expr = f"if(lt(t,{t2}),{segment_expr},{expr})"

    # Handle t < t0
    t0 = filtered[0]["time"]
    v0 = get_val(filtered[0]["value"])
    expr = f"if(lt(t,{t0}),{v0},{expr})"

    return expr
