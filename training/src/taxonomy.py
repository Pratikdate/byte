"""
Centralized Taxonomy Constants & Security Patterns for Byte Desktop Pet
"""

# 3D Desktop Pet Movements & Animations
VALID_ACTIONS = [
    "idle", "wander", "sleep", "jump", "sit", "spin", "dance", "sitOnCorner",
    "sitOnMenuBar", "climbWindow", "pushWidget", "tapWindow", "sneeze", "backflip",
    "headbang", "wave", "stretch", "roll", "sulk"
]

# Pet Personality & Emotional States
VALID_EMOTIONS = [
    "happy", "sad", "curious", "angry", "sleepy", "bored", "shock", "love",
    "normal", "proud", "excited", "embarrassed", "cozy", "empathetic", "calm",
    "quiet", "dj", "working", "cold", "batteryLow", "coffee", "thinking"
]

# Security Regexes for Approved System & Web Commands
ALLOWED_CMD_PATTERNS = [
    r"(?i)^none$",
    r"(?i)^open\s+-a\s+['\"]?[A-Za-z0-9_ -]+['\"]?\s*$",
    r"(?i)^open\s+['\"]?https?://[A-Za-z0-9_./?%&=+~#!:;@,*()'\-]+['\"]?\s*$",
    r"(?i)^open\s+-a\s+['\"]?[A-Za-z0-9_ -]+['\"]?\s+['\"]?https?://[A-Za-z0-9_./?%&=+~#!:;@,*()'\-]+['\"]?\s*$",
    r"(?i)^open\s+[~/[A-Za-z0-9_/.-]+\s*$",
    r"(?i)^osascript\s+-e\s+.+$",
    r"(?i)^screencapture\s+[~A-Za-z0-9_./ -]+\s*$",
    r"(?i)^pmset\s+[A-Za-z0-9_ -]+\s*$",
    r"(?i)^top\s+.+$",
    r"(?i)^df\s+.+$"
]
