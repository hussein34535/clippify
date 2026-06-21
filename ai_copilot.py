"""
ai_copilot.py — AI Copilot with Function-Calling (Phase 0.2)
============================================================
Takes natural language (Arabic/English) commands from the user,
uses Gemma to decide which tools from TOOL_REGISTRY to invoke,
and returns a structured action plan that the frontend can confirm + execute.

Flow:
  1. User types prompt (e.g. "احذف الكليب المحدد")
  2. ai_copilot processes -> calls Gemma with function-calling specs
  3. Gemma returns JSON list of tool calls
  4. We validate each tool against TOOL_REGISTRY
  5. We split into: auto-execute (trusted) + needs-confirmation (destructive)
  6. Frontend shows confirmation dialog, user approves/rejects
  7. Frontend sends approved actions to /api/ai/execute
  8. ai_orchestrator.py executes them
"""

import os
import json
import re
from typing import List, Dict, Any, Optional, Tuple
from tool_registry import (
    TOOL_REGISTRY,
    TOOL_CATEGORIES,
    get_function_calling_specs,
    get_tool,
    get_tool_summary_for_llm,
)
from orchestrator import _API_KEY, _llm_ask
from gemma_multimodal import upload_and_analyze_video, GENAI_AVAILABLE


# ─────────────────────────────────────────────────────────────────────────────
# Whitelist / Confirmation Policy
# ─────────────────────────────────────────────────────────────────────────────

# Tools that ALWAYS require confirmation before execution
# (destructive actions, file operations, anything that can't be undone easily)
ALWAYS_CONFIRM_PATTERNS = [
    "timeline.ripple_delete",
    "timeline.delete_clip",
    "timeline.replace_clip",
    "timeline.lift_clip",
    "timeline.extract_clip",
    "export.*",  # ALL exports need confirmation
    "ai.transcribe",  # expensive operation
    "ai.background_remove",  # expensive
    "ai.style_imitate",  # expensive
    "ai.voice_clone",  # irreversible
    "ai.vocal_isolate",  # expensive
]

# Tools that can be auto-executed (no confirmation needed)
# Empty list = default to "ask if destructive=True in tool schema"
AUTO_EXECUTE_PATTERNS: List[str] = []


def _pattern_matches(name: str, patterns: List[str]) -> bool:
    for p in patterns:
        if p.endswith(".*"):
            if name.startswith(p[:-2]):
                return True
        elif p == name:
            return True
    return False


def requires_confirmation(tool_name: str) -> bool:
    """Determine if a tool call requires user confirmation."""
    # Check explicit always-confirm list
    if _pattern_matches(tool_name, ALWAYS_CONFIRM_PATTERNS):
        return True
    # Check tool schema
    tool = get_tool(tool_name)
    if not tool:
        return True  # unknown tool -> require confirmation
    # Check tool's own flag
    if tool.get("requires_confirmation", False):
        return True
    if tool.get("destructive", False):
        return True
    return False


def can_auto_execute(tool_name: str) -> bool:
    """Determine if a tool can be auto-executed without user confirmation."""
    if requires_confirmation(tool_name):
        return False
    if _pattern_matches(tool_name, AUTO_EXECUTE_PATTERNS):
        return True
    return True  # default: trusted


# ─────────────────────────────────────────────────────────────────────────────
# Tool Call Parsing
# ─────────────────────────────────────────────────────────────────────────────

def parse_tool_calls(llm_response: str) -> List[Dict[str, Any]]:
    """
    Parse LLM response into a list of tool calls.

    Supports multiple formats:
    1. JSON array of tool calls: [{"name": "x", "args": {...}}, ...]
    2. JSON object with "actions" key
    3. Markdown code blocks
    4. Function-calling native format
    """
    if not llm_response:
        return []

    text = llm_response.strip()

    # Strip markdown code fences
    if "```" in text:
        parts = text.split("```")
        for p in parts:
            p = p.strip()
            if p.startswith("json"):
                text = p[4:].strip()
                break
            elif p.startswith("{") or p.startswith("["):
                text = p
                break

    # Try to find JSON array
    array_match = re.search(r"\[.*?\]", text, re.DOTALL)
    if array_match:
        try:
            data = json.loads(array_match.group(0))
            if isinstance(data, list):
                return _normalize_tool_calls(data)
        except json.JSONDecodeError:
            pass

    # Try to find JSON object
    obj_match = re.search(r"\{.*?\}", text, re.DOTALL)
    if obj_match:
        try:
            data = json.loads(obj_match.group(0))
            if isinstance(data, dict):
                # Look for "actions", "tools", or "tool_calls" key
                for key in ("actions", "tools", "tool_calls", "function_calls"):
                    if key in data and isinstance(data[key], list):
                        return _normalize_tool_calls(data[key])
                # Single tool call
                if "name" in data and "args" in data:
                    return _normalize_tool_calls([data])
        except json.JSONDecodeError:
            pass

    return []


def _normalize_tool_calls(raw_calls: List[Any]) -> List[Dict[str, Any]]:
    """Normalize various tool call formats into {name, args} dicts."""
    normalized = []
    for call in raw_calls:
        if not isinstance(call, dict):
            continue

        # Format 1: {"name": "x", "args": {...}}
        if "name" in call and "args" in call:
            normalized.append({
                "name": str(call["name"]),
                "args": call["args"] if isinstance(call["args"], dict) else {}
            })
        # Format 2: {"name": "x", "parameters": {...}}
        elif "name" in call and "parameters" in call:
            normalized.append({
                "name": str(call["name"]),
                "args": call["parameters"] if isinstance(call["parameters"], dict) else {}
            })
        # Format 3: function-calling native: {"function": {"name": "x", "arguments": "..."}}
        elif "function" in call and isinstance(call["function"], dict):
            func = call["function"]
            args = func.get("arguments", "{}")
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except json.JSONDecodeError:
                    args = {}
            normalized.append({
                "name": str(func.get("name", "")),
                "args": args if isinstance(args, dict) else {}
            })

    return normalized


# ─────────────────────────────────────────────────────────────────────────────
# Main Copilot Function
# ─────────────────────────────────────────────────────────────────────────────

COPILOT_SYSTEM_PROMPT = """أنت Clippify Copilot، مساعد مونتاج فيديو ذكي يفهم العربية والإنجليزية.

مهمتك: تحويل أوامر المستخدم إلى استدعاءات أدوات (tool calls) من القائمة المتاحة.

قواعد مهمة:
1. اقرأ طلب المستخدم بعناية
2. اختر الأداة/الأدوات المناسبة من القائمة
3. استخرج القيم للمعاملات من السياق (currentTime, selectedClip, etc.)
4. إذا كان الطلب غامضاً، اسأل المستخدم بدلاً من التخمين
5. الأوامر المدمجة (مثل "احذف ثم أضف") تتحول لعدة tool calls بالترتيب
6. لا تخترع أدوات غير موجودة في القائمة

أجب دائماً بـ JSON صالح بهذا الشكل:
{{
  "actions": [
    {{"name": "tool.name", "args": {{"param1": "value1"}}}}
  ],
  "response_message": "رد قصير بالعربية للمستخدم يوضح ما تم (مثال: 'تم حذف الكليب المحدد')"
}}

إذا لم تفهم الأمر، أرجع:
{{
  "actions": [],
  "response_message": "ممكن توضح أكتر إيه اللي عايز أعمله؟"
}}
"""


def copilot_chat(
    prompt: str,
    timeline_state: Optional[Dict[str, Any]] = None,
    words: Optional[List[Dict[str, Any]]] = None,
    history: Optional[List[Dict[str, str]]] = None,
    video_path: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Main entry point for the AI Copilot.

    Args:
        prompt: User's natural language command
        timeline_state: Current timeline state from frontend
        words: Transcript words
        history: Previous messages [{role: "user"|"assistant", content: str}]
        video_path: Path to current video (if any)

    Returns:
        {
            "actions": [...tool calls...],
            "response_message": "Arabic response",
            "needs_confirmation": bool,
            "confirmation_groups": {trusted: [...], destructive: [...]}
        }
    """
    if not _API_KEY:
        return {
            "actions": [],
            "response_message": "❌ مفتاح GEMMA_API_KEY مش متظبط. حطه في ملف .env واشغل تاني.",
            "needs_confirmation": False,
            "confirmation_groups": {"trusted": [], "destructive": []}
        }

    # Build context summary
    context_lines = []
    if timeline_state:
        tracks = timeline_state.get("tracks", [])
        clips = []
        for track in tracks:
            for clip in track.get("clips", []):
                clips.append({
                    "id": clip.get("id"),
                    "name": clip.get("name"),
                    "track_id": track.get("id"),
                    "start": clip.get("start_time_in_timeline"),
                    "duration": clip.get("end_time_in_timeline", 0) - clip.get("start_time_in_timeline", 0)
                })
        context_lines.append(f"Timeline: {len(tracks)} tracks, {len(clips)} clips")
        if timeline_state.get("currentTime") is not None:
            context_lines.append(f"Current playhead: {timeline_state['currentTime']:.1f}s")
        if timeline_state.get("selectedClipId"):
            context_lines.append(f"Selected clip: {timeline_state['selectedClipId']}")
        if timeline_state.get("selectedTrackId"):
            context_lines.append(f"Selected track: {timeline_state['selectedTrackId']}")

    if video_path:
        context_lines.append(f"Video: {os.path.basename(video_path)}")

    context_text = "\n".join(context_lines) if context_lines else "No context"

    # Build tools summary
    tools_summary = get_tool_summary_for_llm()

    # Build conversation history
    history_text = ""
    if history:
        for msg in history[-6:]:  # last 6 messages
            role = "User" if msg.get("role") == "user" else "Assistant"
            history_text += f"{role}: {msg.get('content', '')}\n"

    # Build full prompt
    full_prompt = f"""{COPILOT_SYSTEM_PROMPT}

## Current Context
{context_text}

## Recent Conversation
{history_text}

## User's Current Request
{prompt}

## Available Tools
{tools_summary}

## Response (JSON only, no markdown)
"""

    # Call Gemma
    try:
        response_text = _llm_ask(full_prompt, temperature=0.2)
    except Exception as e:
        return {
            "actions": [],
            "response_message": f"❌ خطأ في الاتصال بـ Gemini: {str(e)[:200]}",
            "needs_confirmation": False,
            "confirmation_groups": {"trusted": [], "destructive": []}
        }

    # Parse response
    parsed = _parse_copilot_response(response_text)

    # Validate and categorize tool calls
    validated = []
    for call in parsed.get("actions", []):
        name = call.get("name", "")
        if name in TOOL_REGISTRY:
            # Convert string args to proper types based on schema
            args = _coerce_args(name, call.get("args", {}))
            validated.append({"name": name, "args": args})
        else:
            # Unknown tool - skip
            print(f"  [Copilot] Skipped unknown tool: {name}")

    # Split into trusted vs destructive
    trusted = []
    destructive = []
    for call in validated:
        if requires_confirmation(call["name"]):
            destructive.append(call)
        else:
            trusted.append(call)

    return {
        "actions": validated,
        "response_message": parsed.get("response_message", "تمام!"),
        "needs_confirmation": len(destructive) > 0,
        "confirmation_groups": {
            "trusted": trusted,
            "destructive": destructive
        }
    }


def _parse_copilot_response(response_text: str) -> Dict[str, Any]:
    """Parse the JSON response from Gemma."""
    if not response_text:
        return {"actions": [], "response_message": "مفيش رد من المساعد"}

    text = response_text.strip()

    # Strip markdown
    if "```" in text:
        parts = text.split("```")
        for p in parts:
            p = p.strip()
            if p.startswith("json"):
                text = p[4:].strip()
                break
            elif p.startswith("{"):
                text = p
                break

    # Find JSON object
    obj_match = re.search(r"\{.*\}", text, re.DOTALL)
    if obj_match:
        try:
            data = json.loads(obj_match.group(0))
            if isinstance(data, dict):
                # Normalize: actions could be in "actions", "tools", or "tool_calls"
                if "actions" not in data:
                    for key in ("tools", "tool_calls", "function_calls"):
                        if key in data:
                            data["actions"] = data[key]
                            break
                if "actions" not in data:
                    data["actions"] = []
                return data
        except json.JSONDecodeError:
            pass

    return {
        "actions": [],
        "response_message": text[:300]  # show raw text as fallback
    }


def _coerce_args(tool_name: str, args: Dict[str, Any]) -> Dict[str, Any]:
    """
    Coerce string args to proper types based on tool schema.

    LLMs often return numbers as strings ("5.0" instead of 5.0).
    """
    tool = get_tool(tool_name)
    if not tool:
        return args

    params = tool.get("params", {})
    coerced = {}

    for key, value in args.items():
        if key not in params:
            coerced[key] = value
            continue

        param_type = params[key]
        if isinstance(param_type, str):
            # Old format: "float (0-1)" -> need to parse
            param_type = param_type.split("(")[0].strip()

        try:
            if param_type == "float":
                coerced[key] = float(value)
            elif param_type == "integer" or param_type == "int":
                coerced[key] = int(float(value))
            elif param_type == "boolean" or param_type == "bool":
                if isinstance(value, str):
                    coerced[key] = value.lower() in ("true", "1", "yes")
                else:
                    coerced[key] = bool(value)
            elif param_type == "string":
                coerced[key] = str(value)
            elif param_type.startswith("array"):
                if isinstance(value, str):
                    try:
                        coerced[key] = json.loads(value)
                    except json.JSONDecodeError:
                        coerced[key] = [value]
                else:
                    coerced[key] = value
            else:
                coerced[key] = value
        except (ValueError, TypeError):
            coerced[key] = value

    return coerced


# ─────────────────────────────────────────────────────────────────────────────
# Tool listing for frontend
# ─────────────────────────────────────────────────────────────────────────────

def get_all_tools_grouped() -> Dict[str, List[Dict[str, Any]]]:
    """Get all tools grouped by category, for frontend display."""
    grouped: Dict[str, List[Dict[str, Any]]] = {cat: [] for cat in TOOL_CATEGORIES.keys()}

    for name, tool in TOOL_REGISTRY.items():
        category = tool.get("category", "other")
        grouped.setdefault(category, []).append({
            "name": name,
            "description": tool.get("description", ""),
            "description_ar": tool.get("description_ar", ""),
            "category": category,
            "params": tool.get("params", {}),
            "requires_confirmation": requires_confirmation(name),
            "destructive": tool.get("destructive", False),
        })

    return grouped


if __name__ == "__main__":
    # Quick test
    print(f"Registered tools: {len(TOOL_REGISTRY)}")
    print(f"Tools requiring confirmation: {sum(1 for n in TOOL_REGISTRY if requires_confirmation(n))}")
    print(f"Auto-executable tools: {sum(1 for n in TOOL_REGISTRY if can_auto_execute(n))}")

    # Test parsing
    test_response = """Here's what I'll do:
```json
{
  "actions": [
    {"name": "timeline.delete_clip", "args": {"clip_id": "abc123"}}
  ],
  "response_message": "تم حذف الكليب"
}
```"""
    calls = parse_tool_calls(test_response)
    print(f"Parsed {len(calls)} tool calls from test response")
    for c in calls:
        print(f"  - {c['name']}({c['args']})")
