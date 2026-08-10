"""
Validator & Normalizer Module for Byte Fine-Tuning Datasets
"""

import re
from .taxonomy import VALID_ACTIONS, VALID_EMOTIONS, ALLOWED_CMD_PATTERNS

def is_command_allowed(cmd_str: str) -> bool:
    """Checks if a command string passes security whitelist rules."""
    cmd = cmd_str.strip()
    if not cmd or cmd.lower() == "none":
        return True

    # Security check for shell injection metacharacters
    dangerous = [";", "&&", "||", "|", "`", "$(", "\n", "\r"]
    for d in dangerous:
        if d in cmd:
            return False

    for pattern in ALLOWED_CMD_PATTERNS:
        if re.match(pattern, cmd):
            return True
    return False

def parse_and_validate_record(obj: dict) -> dict:
    """
    Parses a raw dataset record dict and returns a clean, standardized MLX format record.
    Returns None if record cannot be parsed.
    """
    user_content = ""
    asst_content = ""

    if "messages" in obj and isinstance(obj["messages"], list):
        for msg in obj["messages"]:
            if isinstance(msg, dict):
                role = msg.get("role")
                content = msg.get("content", "")
                if role == "user":
                    user_content = content
                elif role == "assistant":
                    asst_content = content
    elif "text" in obj and isinstance(obj["text"], str):
        text = obj["text"]
        if "RESPONSE:" in text:
            parts = text.split("RESPONSE:", 1)
            user_content = parts[0].replace("CONTEXT:", "").strip()
            asst_content = parts[1].strip()

    if not user_content or not asst_content:
        return None

    # Standardize user_content prefix
    user_content = user_content.strip()
    if not user_content.startswith("CONTEXT:"):
        if not user_content.startswith("User:"):
            user_content = f"User: {user_content}"
        user_content = f"CONTEXT: {user_content}"

    # Extract tags from assistant_content
    action_match = re.search(r"\[ACTION:\s*([A-Za-z0-9_-]+)\]", asst_content, re.IGNORECASE)
    emotion_match = re.search(r"\[EMOTION:\s*([A-Za-z0-9_-]+)\]", asst_content, re.IGNORECASE)
    cmd_match = re.search(r"\[CMD:\s*([^\]]+)\]", asst_content, re.IGNORECASE)

    action = action_match.group(1) if action_match else "idle"
    emotion = emotion_match.group(1) if emotion_match else "normal"
    cmd = cmd_match.group(1).strip() if cmd_match else "none"

    if action not in VALID_ACTIONS:
        action = "idle"
    if emotion not in VALID_EMOTIONS:
        emotion = "normal"
    if not is_command_allowed(cmd):
        cmd = "none"

    # Clean speech text
    speech = asst_content
    speech = re.sub(r"\[ACTION:\s*[^\]]+\]", "", speech, flags=re.IGNORECASE)
    speech = re.sub(r"\[EMOTION:\s*[^\]]+\]", "", speech, flags=re.IGNORECASE)
    speech = re.sub(r"\[CMD:\s*[^\]]+\]", "", speech, flags=re.IGNORECASE)
    speech = speech.strip()

    clean_asst = f"[ACTION: {action}] [EMOTION: {emotion}] [CMD: {cmd}] {speech}"

    return {
        "messages": [
            {"role": "user", "content": user_content},
            {"role": "assistant", "content": clean_asst}
        ],
        "_meta": {
            "action": action,
            "emotion": emotion,
            "cmd": cmd,
            "has_cmd": cmd.lower() != "none"
        }
    }
