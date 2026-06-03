import json
from dataclasses import dataclass, field
from typing import List, Tuple, Dict, Any, Optional

@dataclass
class EditingDecisions:
    zoom_style: str = "none"          # "none" | "gentle" | "punch" | "dynamic" | "slow_push"
    zoom_timestamps: List[dict] = field(default_factory=list)  # [{"start": s, "end": e, "scale": scale}]
    speed_ramps: List[dict] = field(default_factory=list)      # [{"start": s, "end": e, "factor": f}]
    silence_mode: str = "auto"        # "word" | "sentence" | "paragraph" | "natural" | "aggressive"
    sfx_plan: List[dict] = field(default_factory=list)         # [{"timestamp": t, "type": "sfx_name", "volume": v}]
    music_energy: str = "moderate"    # "ambient" | "moderate" | "high"
    caption_emoji_map: Dict[str, str] = field(default_factory=dict) # {"كلمة": "emoji"}
    framing: str = "speaker_tracking" # "speaker_tracking" | "split_screen" | "no_crop"
    outro_style: str = "circle_fade"  # "circle_fade" | "black_fade" | "freeze_zoom" | "epic_fade"
    cta_text: str = ""

def generate_director_decisions(
    clip_index: int,
    start_sec: float,
    end_sec: float,
    content_dna: Dict[str, Any],
    scene_data: Dict[str, Any],
    words: List[Dict[str, Any]],
    llm_fn=None
) -> EditingDecisions:
    """
    Autonomous Director Brain: Plans zoom cuts, SFX events, and pacing ramps
    specifically tailored to the content DNA and visual scene.
    """
    clip_words = [w for w in words if w["start"] >= start_sec and w["end"] <= end_sec]
    clip_text = " ".join([w["text"] for w in clip_words])
    
    # 1. Base heuristics from Content DNA & Scene Data
    tone = content_dna.get("tone", "educational").lower()
    speakers_type = content_dna.get("speakers_type", "monologue").lower()
    visual_vibe = content_dna.get("visual_vibe", "Minimalist Clean")
    target_pacing = content_dna.get("target_pacing", "natural")
    speech_rate = content_dna.get("speech_rate", 140.0)

    # Map content characteristics to editing profiles
    decisions = EditingDecisions()
    
    # Zoom Style Mapping
    if "humorous" in tone or "comedy" in tone:
        decisions.zoom_style = "punch"
        decisions.outro_style = "freeze_zoom"
        decisions.music_energy = "high"
    elif "motivation" in tone or "inspirational" in tone:
        decisions.zoom_style = "slow_push"
        decisions.outro_style = "epic_fade"
        decisions.music_energy = "high"
    elif "educational" in tone:
        decisions.zoom_style = "gentle"
        decisions.outro_style = "circle_fade"
        decisions.music_energy = "ambient"
    else:
        decisions.zoom_style = "gentle"
        decisions.outro_style = "circle_fade"
        decisions.music_energy = "moderate"

    # Framing Mapping
    scene_type = scene_data.get("scene_type", "studio")
    persons = scene_data.get("n_persons", 1)
    if persons > 1 or speakers_type == "dialogue" or speakers_type == "multi-speaker":
        decisions.framing = "split_screen"
    else:
        decisions.framing = "speaker_tracking"

    # Silence cut Mode
    if "comedy" in tone:
        decisions.silence_mode = "aggressive"
    elif "awareness" in tone:
        decisions.silence_mode = "sentence"
    else:
        decisions.silence_mode = "natural"

    # 2. Advanced: Query LLM to plan precise moments (Pacing, SFX, Emoji Map, Zooms)
    if llm_fn:
        sample_words_json = []
        for i, w in enumerate(clip_words[:30]): # Limit to first 30 words for performance/token limit
            sample_words_json.append({"text": w["text"], "time": round(w["start"] - start_sec, 2)})

        prompt = f"""You are the AI Director for a premium short-form video.
Plan the exact editing events for the first 10-15 seconds of this clip.
Clip text: "{clip_text[:300]}"
Words with local timestamps:
{json.dumps(sample_words_json, ensure_ascii=False)}

Return a raw JSON mapping containing:
1. "sfx_plan": List of dictionaries with keys "time" (float relative to clip start), "type" (choose from: "whoosh", "boom", "ding", "swoosh", "pop"), and "volume" (0.1 to 1.0). Limit to 2-3 essential highlights.
2. "zoom_timestamps": List of dictionaries with "start" and "end" times (relative to clip start) and "scale" (1.1 to 1.35) for dramatic highlights. Limit to 1-2 zooms.
3. "caption_emoji_map": Dict mapping 3-5 keywords from the clip to corresponding single emojis (e.g. {{"مستحيل": "😱", "gold": "💰"}}).
4. "speed_ramps": List of dicts with keys "start", "end", and "factor" (factor < 1 means slow-mo, > 1 means fast-forward) for pacing effects. (Optional, return empty list if not needed).

Return ONLY the raw JSON block without markdown formatting or code backticks."""

        try:
            resp_text = llm_fn(prompt, temperature=0.3).strip()
            if resp_text.startswith("```json"):
                resp_text = resp_text.split("```json")[1].split("```")[0].strip()
            elif resp_text.startswith("```"):
                resp_text = resp_text.split("```")[1].split("```")[0].strip()
            
            parsed = json.loads(resp_text)
            
            if "sfx_plan" in parsed:
                decisions.sfx_plan = parsed["sfx_plan"]
            if "zoom_timestamps" in parsed:
                decisions.zoom_timestamps = parsed["zoom_timestamps"]
            if "caption_emoji_map" in parsed:
                decisions.caption_emoji_map = parsed["caption_emoji_map"]
            if "speed_ramps" in parsed:
                decisions.speed_ramps = parsed["speed_ramps"]
                
        except Exception as e:
            print(f"  [AIDirector] LLM precise planning failed ({e}). Using standard defaults.")

    # 3. Fallbacks and Heuristic generation if LLM did not fill lists
    if not decisions.caption_emoji_map:
        # standard fallback emojis
        emoji_rules = {
            "مستحيل": "😱", "تخيل": "💡", "والله": "🔥", "رائع": "🤯", "فلوس": "💰",
            "حب": "❤️", "صدمة": "😳", "ضحك": "😂", "هههه": "🤣", "لعبة": "🎮",
            "شاهد": "👀", "مهم": "⚠️", "نجاح": "🏆", "قوة": "⚡", "سر": "🔑"
        }
        for kw, emo in emoji_rules.items():
            if kw in clip_text.lower():
                decisions.caption_emoji_map[kw] = emo

    if not decisions.sfx_plan:
        # Place a ding or whoosh sound at the beginning
        decisions.sfx_plan.append({"time": 0.5, "type": "swoosh", "volume": 0.6})
        
    return decisions
