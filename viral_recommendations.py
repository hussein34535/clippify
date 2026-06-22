"""
viral_recommendations.py — AI-powered Viral Editing Recommendations
Uses Gemma 4 to analyze Content DNA and Viral Timeline to suggest editing moves.
"""

import json
from typing import List, Dict, Any

def generate_viral_recommendations(dna: Dict[str, Any], viral_timeline: Dict[float, float], words: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Calls Gemma 4 to generate a list of actionable editing recommendations 
    based on the video's DNA and its viral energy timeline.
    
    Returns a list of dicts:
    [
        {"time_sec": 5.0, "type": "zoom", "description": "Add a zoom effect here to emphasize the hook.", "reason": "High energy moment."},
        {"time_sec": 12.0, "type": "sfx", "description": "Add a swoosh or impact sound.", "reason": "Information density is high but energy drops."}
    ]
    """
    try:
        from campaign import GEMMA_API_KEY
        from google import genai
        from google.genai import types
        
        if not GEMMA_API_KEY:
            print("  [ViralRecs] No GEMMA_API_KEY found. Returning default recommendations.")
            return _get_fallback_recommendations(viral_timeline)
            
        client = genai.Client(api_key=GEMMA_API_KEY)
        
        # Limit to the first 200 words to save tokens
        sample_words = words[:200]
        text_sample = " ".join([w["text"] for w in sample_words])
        
        # Summarize the timeline (top 3 peaks, bottom 3 valleys)
        peaks = sorted(viral_timeline.items(), key=lambda x: x[1], reverse=True)[:3]
        valleys = sorted(viral_timeline.items(), key=lambda x: x[1])[:3]
        
        timeline_summary = {
            "high_energy_moments_sec": [p[0] for p in peaks],
            "low_energy_moments_sec": [v[0] for v in valleys]
        }
        
        prompt = f"""You are an elite Video Editor and Viral Growth Hacker.
Analyze the following Content DNA, transcript sample, and energy timeline of a video clip to provide EXACTLY 3 editing recommendations to make this video go viral.

Content DNA:
{json.dumps(dna, ensure_ascii=False)}

Energy Timeline Peaks/Valleys:
{json.dumps(timeline_summary, ensure_ascii=False)}

Transcript Sample (first 200 words):
{text_sample}

Provide exactly 3 actionable recommendations. 
For "type", use one of: ["zoom", "sfx", "broll", "text_highlight", "speed_up"].
Return ONLY a valid JSON array of objects, with no markdown code blocks.

Format:
[
  {{"time_sec": 0.0, "type": "zoom", "description": "Quick zoom in on the speaker's face to strengthen the hook.", "reason": "The first 3 seconds are critical for retention."}},
  {{"time_sec": 15.2, "type": "broll", "description": "Add engaging B-roll here to maintain attention.", "reason": "Energy drops at this moment, visual pattern interrupt needed."}}
]
"""
        
        models_to_try = ["gemma-2-27b-it", "gemini-1.5-flash", "gemini-2.5-flash"]
        response = None
        last_err = None
        for model in models_to_try:
            try:
                print(f"  [ViralRecs] Trying model {model}...")
                response = client.models.generate_content(
                    model=model,
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        temperature=0.4,
                        response_mime_type="application/json"
                    )
                )
                break
            except Exception as e:
                last_err = e
                print(f"  [ViralRecs] Model {model} failed: {e}")
                
        if response is None:
            raise Exception(f"All models failed for viral recommendations. Last error: {last_err}")
        
        resp_text = response.text.strip()
        
        # Strip markdown if present
        if "```" in resp_text:
            parts = resp_text.split("```")
            for part in parts:
                part = part.strip()
                if part.startswith("json"):
                    part = part[4:].strip()
                if part.startswith("[") and part.endswith("]"):
                    resp_text = part
                    break
                    
        parsed = json.loads(resp_text)
        if isinstance(parsed, list):
            return parsed
        else:
            print("  [ViralRecs] LLM did not return a list.")
            return _get_fallback_recommendations(viral_timeline)
            
    except Exception as e:
        import traceback
        print(f"  [ViralRecs] Error generating recommendations: {e}")
        traceback.print_exc()
        return _get_fallback_recommendations(viral_timeline)

def _get_fallback_recommendations(timeline: Dict[float, float]) -> List[Dict[str, Any]]:
    """Heuristic fallback if LLM fails."""
    recs = []
    if not timeline:
        return recs
        
    # Hook recommendation
    recs.append({
        "time_sec": 0.0,
        "type": "zoom",
        "description": "Add a quick zoom-in to catch the viewer's attention instantly.",
        "reason": "Strengthen the initial hook."
    })
    
    # Find lowest energy moment after 5s
    valleys = sorted([t for t in timeline.items() if t[0] > 5.0], key=lambda x: x[1])
    if valleys:
        recs.append({
            "time_sec": valleys[0][0],
            "type": "broll",
            "description": "Add a B-roll or visual change here.",
            "reason": "Energy is low, requires pattern interrupt."
        })
        
    return recs
