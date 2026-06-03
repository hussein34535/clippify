import json
from typing import List, Dict, Any, Optional

def analyze_speech_patterns(words: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Computes mathematical speech patterns from the transcription words list.
    """
    if not words:
        return {
            "speech_rate": 130.0,
            "avg_sentence_len": 8,
            "pause_frequency": 0.2,
            "total_duration": 0.0
        }

    total_words = len(words)
    start_time = words[0]["start"]
    end_time = words[-1]["end"]
    duration = max(1.0, end_time - start_time)

    # Speech rate (words per minute)
    speech_rate = (total_words / duration) * 60.0

    # Identify sentences based on pauses (> 0.6 seconds)
    sentence_count = 1
    total_sentence_words = 0
    current_sentence_words = 0

    # Calculate pause statistics
    pauses = 0
    total_pause_duration = 0.0

    for i in range(len(words)):
        current_sentence_words += 1
        if i < len(words) - 1:
            gap = words[i+1]["start"] - words[i]["end"]
            if gap > 0.2:
                pauses += 1
                total_pause_duration += gap
            if gap > 0.6:  # Assume sentence boundary
                sentence_count += 1
                current_sentence_words = 0

    avg_sentence_len = max(3, int(total_words / max(1, sentence_count)))
    pause_frequency = pauses / duration if duration > 0 else 0.0

    return {
        "speech_rate": round(speech_rate, 1),
        "avg_sentence_len": avg_sentence_len,
        "pause_frequency": round(pause_frequency, 2),
        "total_duration": round(duration, 1),
        "pause_ratio": round(total_pause_duration / duration, 2) if duration > 0 else 0.0
    }

def extract_content_dna(words: List[Dict[str, Any]], llm_fn=None) -> Dict[str, Any]:
    """
    Analyzes the transcript to extract a comprehensive Content DNA.
    It combines mathematical parsing with Gemma LLM insights.
    """
    # 1. Get mathematical metrics from first 90 seconds (to be fast and efficient)
    sample_words = [w for w in words if w["start"] < 90.0]
    if not sample_words:
        sample_words = words[:150] # Fallback to first 150 words

    stats = analyze_speech_patterns(sample_words)

    # 2. Get LLM-based linguistic insights
    sample_text = " ".join([w["text"] for w in sample_words])

    prompt = f"""You are an elite video content director analyzing a video's transcript DNA to decide the perfect editing style (pacing, tone, graphics, sounds).
Analyze this transcript segment:
---
"{sample_text}"
---

Provide a raw JSON object detailing the content DNA. Choose from the suggested options or be precise.
Required JSON keys:
1. "tone": One of ["serious", "humorous", "educational", "inspirational", "dynamic"] or highly descriptive tone.
2. "speakers_type": One of ["monologue", "dialogue", "multi-speaker"].
3. "info_density": One of ["dense", "casual", "storytelling"].
4. "language_and_dialect": Detect language (e.g. "Arabic", "English") and specific dialect/accent (e.g. "Egyptian", "Gulf", "US", "UK").
5. "visual_vibe": A premium visual aesthetic name (e.g., "Neon Cyberpunk", "Golden Hour Cinema", "High Contrast Corporate", "Minimalist Clean", "Retro VHS").
6. "target_pacing": One of ["fast-paced", "natural", "slow-paced"].

Return ONLY the raw JSON block without markdown formatting or code block backticks.
Example output:
{{"tone": "humorous", "speakers_type": "dialogue", "info_density": "casual", "language_and_dialect": "Arabic Egyptian", "visual_vibe": "Neon Cyberpunk", "target_pacing": "fast-paced"}}"""

    dna = {
        "tone": "educational",
        "speakers_type": "monologue",
        "info_density": "casual",
        "language_and_dialect": "Arabic",
        "visual_vibe": "Minimalist Clean",
        "target_pacing": "natural"
    }

    if llm_fn:
        try:
            resp_text = llm_fn(prompt, temperature=0.3)
            # Try to strip markdown if LLM returned it
            resp_text = resp_text.strip()
            if resp_text.startswith("```json"):
                resp_text = resp_text.split("```json")[1].split("```")[0].strip()
            elif resp_text.startswith("```"):
                resp_text = resp_text.split("```")[1].split("```")[0].strip()
            
            parsed = json.loads(resp_text)
            for k in dna.keys():
                if k in parsed:
                    dna[k] = parsed[k]
        except Exception as e:
            print(f"  [ContentDNA] LLM analysis failed ({e}). Using heuristic defaults.")
            # Simple heuristic backup
            if any(w in sample_text.lower() for w in ["hallo", "welcome", "today", "learn", "how to", "شرح", "تعلم", "كيف"]):
                dna["tone"] = "educational"
                dna["info_density"] = "dense"
            elif any(w in sample_text.lower() for w in ["هههه", "laugh", "funny", "joke", "ضحك", "مسخرة"]):
                dna["tone"] = "humorous"
                dna["target_pacing"] = "fast-paced"
                dna["visual_vibe"] = "Retro VHS"

    # Merge statistics with LLM insights
    dna.update(stats)
    return dna
