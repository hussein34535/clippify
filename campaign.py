"""
campaign.py — Campaign Mode data model for ClipAI
Stores UGC campaign rules: captions, handles, platforms, min duration.
"""

import os
import json
from dataclasses import dataclass, field, asdict
from typing import List
from dotenv import load_dotenv

load_dotenv()

APP_DIR       = os.path.dirname(os.path.abspath(__file__))
CAMPAIGN_FILE = os.path.join(APP_DIR, "campaign.json")

# ── Default caption packs per content type ──────────────────────────────────
DEFAULT_CAPTIONS = {
    "YouTube": [
        "قالوا هذا الكلام أمام الكاميرا وكان لازم أقتصه 👀",
        "هذا هو الجزء اللي كل الناس محتاجة تسمعه",
        "أعدت هذا المقطع 3 مرات لأستوعبه 😮",
        "محدش بيتكلم في الموضوع ده بالشكل ده",
        "هذه النصيحة غيرت طريقة تفكيري فعلاً",
    ],
    "Podcast": [
        "البودكاست ده قال اللي كلنا كنا بنفكر فيه 💣",
        "المقطع ده من البودكاست مستحيل أنساه",
        "كلام قوي جداً في الحلقة دي",
        "النصيحة دي مش عادية أبداً 👀",
        "وقفت البودكاست عشان أستوعب اللي اتقال",
    ],
    "Interview": [
        "الإجابة اللي محدش توقعها 👀",
        "لما قال الجملة دي كان لازم أقصها فوراً",
        "أكثر لحظة صريحة شفتها في لقاء",
        "شفت المقطع ده 5 مرات لحد دلوقتي",
        "الخلاصة الحقيقية بتبدأ من هنا",
    ],
    "Gaming": [
        "مستحيل اللي حصل ده بجد 😱",
        "أقوى لقطة في السنة 🔥",
        "عشان كده بتابع كل بثوثه",
        "رد الفعل بيشرح كل حاجة 💀",
        "أنا وأنا بعيد المقطع ده 10 مرات",
    ],
    "Custom": [
        "ركزوا كويس في المقطع ده 👀",
        "اللقطة دي بالذات 🔥",
        "كان لازم أشارك المقطع ده فوراً",
        "لازم تشوفوا اللي حصل هنا",
        "مش هتصدقوا اللي حصل",
    ],
}


# ═══════════════════════════════════════════════════════════════════════════
#  Campaign dataclass
# ═══════════════════════════════════════════════════════════════════════════
@dataclass
class Campaign:
    name:              str        = "حملتي الإعلانية"
    handle:            str        = "@المنشن"
    platforms:         List[str]  = field(default_factory=lambda: ["TikTok", "Instagram Reels", "YouTube Shorts"])
    min_duration:      int        = 10
    content_type:      str        = "YouTube"     # YouTube | Podcast | Interview | Gaming | Custom
    caption_templates: List[str]  = field(default_factory=list)
    custom_tag:        str        = ""
    # ── New fields for Phase 15/UGC automation ────────────────────────────────
    allow_bg_music:      bool       = True
    allow_broll:         bool       = True
    translate_to_arabic: bool       = False
    ftc_disclosure:      str        = ""
    mandatory_keywords:  List[str]  = field(default_factory=list)

    def __post_init__(self):
        # If no custom captions, load defaults for content_type
        if not self.caption_templates:
            self.caption_templates = list(
                DEFAULT_CAPTIONS.get(self.content_type, DEFAULT_CAPTIONS["Custom"])
            )

    def set_content_type(self, ctype: str):
        """Switch content type and reset captions to defaults for that type."""
        self.content_type      = ctype
        self.caption_templates = list(
            DEFAULT_CAPTIONS.get(ctype, DEFAULT_CAPTIONS["Custom"])
        )

    def get_platforms_str(self) -> str:
        return " · ".join(self.platforms) if self.platforms else "—"

    def compliance_ok(self, duration_sec: float) -> tuple[bool, str]:
        """
        Returns (True, "") if clip duration passes campaign minimum,
        otherwise (False, reason_string).
        """
        if duration_sec < self.min_duration:
            return False, (
                f"Campaign requires minimum {self.min_duration}s clips. "
                f"Current: {int(duration_sec)}s"
            )
        return True, ""


# ═══════════════════════════════════════════════════════════════════════════
#  Persistence helpers
# ═══════════════════════════════════════════════════════════════════════════
def save_campaign(c: Campaign) -> None:
    """Save campaign to campaign.json in app directory."""
    with open(CAMPAIGN_FILE, "w", encoding="utf-8") as f:
        json.dump(asdict(c), f, indent=2, ensure_ascii=False)


def load_campaign() -> Campaign | None:
    """Load campaign from campaign.json. Returns None if not found or corrupt."""
    if not os.path.exists(CAMPAIGN_FILE):
        return None
    try:
        with open(CAMPAIGN_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        return Campaign(**data)
    except Exception:
        return None


def clear_campaign() -> None:
    """Delete campaign.json."""
    if os.path.exists(CAMPAIGN_FILE):
        os.remove(CAMPAIGN_FILE)


# ═══════════════════════════════════════════════════════════════════════════
#  Caption file generator
# ═══════════════════════════════════════════════════════════════════════════
def generate_caption_file(
    campaign: Campaign,
    clip_index: int,
    clip_path: str,
    duration_sec: float,
) -> str:
    """
    Write a ready-to-use caption .txt file next to the clip.
    Returns the path to the generated file.
    """
    txt_path = os.path.splitext(clip_path)[0] + "_caption.txt"
    captions  = campaign.caption_templates
    primary   = captions[0] if captions else "(no caption set)"

    lines = [
        "=" * 54,
        f"  ClipAI — تقرير الحملة (Campaign)",
        "=" * 54,
        f"  الحملة : {campaign.name}",
        f"  المنشن : {campaign.handle}",
        f"  النوع  : {campaign.content_type}",
        f"  المنصات: {campaign.get_platforms_str()}",
        f"  المقطع : clip_{clip_index}.mp4",
        f"  المدة  : {int(duration_sec)}ث",
        f"  الحد الأدنى : {campaign.min_duration}ث  "
        + ("✓ مقبول" if duration_sec >= campaign.min_duration else "✗ مرفوض"),
        "=" * 54,
        "",
        "  الوصف المقترح (جاهز للنسخ):",
        "",
        f'{primary}',
        "",
        f"  لا تنسَ إضافة المنشن: {campaign.handle}",
    ]

    if campaign.custom_tag:
        lines.append(f"  هاشتاج: {campaign.custom_tag}")

    lines += [
        "",
        "-" * 54,
        "  كل الخيارات المتاحة:",
        "",
    ]

    for i, cap in enumerate(captions, 1):
        lines.append(f"  {i}. {cap}")

    lines += [
        "",
        "-" * 54,
        "  قائمة المراجعة قبل النشر (Checklist):",
        f"  [ ] تم إضافة منشن {campaign.handle} في الوصف",
        f"  [ ] مدة المقطع >= {campaign.min_duration}ث",
        "  [ ] المقطع سيبقى منشوراً لمدة 30+ يوماً",
        "  [ ] الإعجابات (Likes) ظاهرة وغير مخفية",
        "  [ ] ليس إعلاناً مدفوعاً",
    ]

    for platform in campaign.platforms:
        lines.append(f"  [ ] تم النشر على {platform}")

    lines += ["", "=" * 54]

    with open(txt_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    return txt_path


# ═══════════════════════════════════════════════════════════════════════════
#  Gemma AI Studio Integration
# ═══════════════════════════════════════════════════════════════════════════
from dotenv import load_dotenv
load_dotenv()

GEMMA_API_KEY = os.getenv("GEMMA_API_KEY", "")

def generate_ai_captions(
    video_summary: str,
    campaign_name: str,
    handle: str,
    content_type: str,
    api_key: str,
) -> List[str]:
    """
    Generates 5 highly engaging, platform-native viral captions using gemma-4-31b-it.
    """
    import requests
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemma-4-31b-it:generateContent?key={api_key}"
    headers = {"Content-Type": "application/json"}

    prompt = f"""
You are an expert UGC (User Generated Content) copywriter and viral growth hacker.
Your task is to generate highly engaging, high-conversion viral captions and hooks for a clipping campaign in beautiful, natural Arabic.

Campaign Details:
- Campaign Name: {campaign_name}
- Social handle to tag: {handle}
- Content Category: {content_type}
- Video/Topic Summary: {video_summary}

Please generate exactly 5 distinct, highly engaging caption options in Arabic.
Follow these rules:
1. Include a strong, curiosity-inducing "hook" in the first line in Arabic.
2. Use modern, popular internet formatting (short sentences, tactical spacing, highly relevant emojis).
3. Seamlessly integrate the campaign handle ({handle}) within the caption (e.g. tag them or mention them).
4. Keep the tone natural, energetic, and native to platforms like TikTok, YouTube Shorts, and Instagram Reels in Arabic.
5. Provide a variety of styles (e.g. suspenseful, informational, emotional, curious).

Output ONLY the raw JSON list of strings, with no markdown formatting, no code block backticks (like ```json), no thoughts, and no conversational explanation, so it can be parsed with json.loads.
Example output format:
[
  "خيار كابشن 1",
  "خيار كابشن 2",
  "خيار كابشن 3",
  "خيار كابشن 4",
  "خيار كابشن 5"
]
"""

    payload = {
        "contents": [{
            "parts": [{"text": prompt}]
        }],
        "generationConfig": {
            "temperature": 0.7,
            "maxOutputTokens": 1000
        }
    }

    response = requests.post(url, json=payload, headers=headers)
    if response.status_code != 200:
        raise Exception(f"API Error ({response.status_code}): {response.text}")

    data = response.json()
    candidates = data.get("candidates", [])
    if not candidates:
        raise Exception("No response candidates returned from Gemma API.")

    parts = candidates[0].get("content", {}).get("parts", [])
    text_parts = [p.get("text", "") for p in parts if not p.get("thought")]
    resp_text = "".join(text_parts).strip()

    if resp_text.startswith("```"):
        lines = resp_text.splitlines()
        cleaned_lines = []
        for line in lines:
            if not line.strip().startswith("```"):
                cleaned_lines.append(line)
        resp_text = "\n".join(cleaned_lines).strip()

    try:
        captions = json.loads(resp_text)
        if isinstance(captions, list) and len(captions) > 0:
            return [str(c).strip() for c in captions]
    except Exception:
        lines = [line.strip().strip('"').strip("'").strip(",") for line in resp_text.splitlines() if line.strip()]
        lines = [l for l in lines if l not in ['[', ']', '],', '],'] and len(l) > 3]
        if lines:
            return lines[:5]

    raise Exception(f"Failed to parse Gemma output as captions: {resp_text[:200]}")


def analyze_and_setup_campaign_from_text(requirements_text: str, api_key: str = None) -> Campaign:
    """
    Analyze campaign requirements text using Gemma 2.5 Flash and official google-genai SDK,
    extract rules, and configure the Campaign dataclass automatically.
    """
    if not api_key:
        api_key = GEMMA_API_KEY
        
    from google import genai
    from google.genai import types
    
    print("  [Campaign AI] Initializing Gemma Client...")
    client = genai.Client(api_key=api_key)
    
    prompt = f"""You are an expert campaign automator for social media video agencies.
Analyze this raw UGC/clipping campaign requirements text carefully and extract the precise guidelines, constraints, and rules.

Requirements text:
\"\"\"{requirements_text}\"\"\"

Extract the following variables:
1. name: Name of the campaign
2. handle: Social media handle to tag (e.g. '@callofduty'). If not specified, use empty string.
3. platforms: List of target platforms (e.g. ["TikTok", "Instagram Reels", "YouTube Shorts"])
4. min_duration: Minimum video duration in seconds (usually 10s if stated, or standard 10s fallback)
5. content_type: The closest genre ("YouTube", "Podcast", "Interview", "Gaming", "Custom")
6. allow_bg_music: boolean (False if background music or separate audio is strictly forbidden, else True)
7. allow_broll: boolean (False if external stock B-roll overlays are forbidden/restricted, else True)
8. translate_to_arabic: boolean (True if translation to Arabic is requested/favored, False if English/specific language only is required)
9. ftc_disclosure: FTC disclosure hashtag if REQUIRED (e.g. "#Ad", "#Advertisement", "#Sponsored"). Look carefully at FTC disclosures! If none, empty string.
10. mandatory_keywords: List of mandatory words to include in titles/captions (e.g. ["Modern Warfare 4"])
11. caption_templates: Generate exactly 5 viral, high-conversion caption options in Arabic that:
    - Follow the exact campaign tag rules (tagging {{{{handle}}}})
    - Place the exact FTC disclosure ({{{{ftc_disclosure}}}}) on its own separate line right after the text (CRITICAL!).
    - Include the mandatory keywords naturally.

Return ONLY a valid JSON object matching this exact format:
{{
  "name": "Campaign Name",
  "handle": "@callofduty",
  "platforms": ["TikTok", "Instagram Reels", "YouTube Shorts"],
  "min_duration": 10,
  "content_type": "Gaming",
  "allow_bg_music": false,
  "allow_broll": false,
  "translate_to_arabic": false,
  "ftc_disclosure": "#Ad",
  "mandatory_keywords": ["Modern Warfare 4"],
  "caption_templates": [
    "النسخة الجديدة تبدو واقعية للغاية لدرجة الجنون! المواجهة القوية في العرض الجديد لا تُصدق 🔥\\n\\n#Ad\\n\\n@callofduty",
    "خيار كابشن 2...\\n\\n#Ad\\n\\n@callofduty",
    "خيار كابشن 3...\\n\\n#Ad\\n\\n@callofduty",
    "خيار كابشن 4...\\n\\n#Ad\\n\\n@callofduty",
    "خيار كابشن 5...\\n\\n#Ad\\n\\n@callofduty"
  ]
}}
"""

    response = client.models.generate_content(
        model="gemma-4-31b-it",
        contents=prompt,
        config=types.GenerateContentConfig(
            temperature=0.2,
            response_mime_type="application/json"
        )
    )
    
    resp_text = response.text.strip()
    if resp_text.startswith("```"):
        lines = resp_text.splitlines()
        cleaned_lines = []
        for line in lines:
            if not line.strip().startswith("```"):
                cleaned_lines.append(line)
        resp_text = "\n".join(cleaned_lines).strip()
        
    try:
        parsed = json.loads(resp_text)
        c = Campaign(
            name=parsed.get("name", "Campaign Name"),
            handle=parsed.get("handle", "@handle"),
            platforms=parsed.get("platforms", ["TikTok", "Instagram Reels", "YouTube Shorts"]),
            min_duration=parsed.get("min_duration", 10),
            content_type=parsed.get("content_type", "Custom"),
            caption_templates=parsed.get("caption_templates", []),
            custom_tag=parsed.get("ftc_disclosure", ""),
            allow_bg_music=parsed.get("allow_bg_music", True),
            allow_broll=parsed.get("allow_broll", True),
            translate_to_arabic=parsed.get("translate_to_arabic", False),
            ftc_disclosure=parsed.get("ftc_disclosure", ""),
            mandatory_keywords=parsed.get("mandatory_keywords", [])
        )
        save_campaign(c)
        return c
    except Exception as e:
        raise Exception(f"Failed to parse campaign rules JSON: {e}. Raw text: {resp_text[:300]}")

