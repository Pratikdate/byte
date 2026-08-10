#!/usr/bin/env python3
"""
Generate 100,000+ high-quality training pairs adapting casual_reflective_100k.jsonl to Byte format,
combined with browser/desktop commands and latency-masking thinking connectors.

Schema matches standard Ollama/MLX chat format:
{"messages": [{"role": "user", "content": "CONTEXT: User: ..."}, {"role": "assistant", "content": "[ACTION: ...] [EMOTION: ...] [CMD: ...] <thinking_phrase> <speech>"}]}
"""

import json
import random
import os
import re

# ============================================================
# Enums validated against PetBrain.swift
# ============================================================
VALID_ACTIONS = [
    "idle", "wander", "followCursor", "sleep", "jump", "sit", "spin", "sulk", "dizzy", "tickled",
    "peekWindow", "sitOnTaskbar", "investigate", "stepBack", "dance", "bow", "stretch", "roll",
    "hide", "chaseLaser", "seekTreat", "sitOnCorner", "sitOnMenuBar", "climbWindow", "pushWidget",
    "tapWindow", "sneeze", "backflip", "headbang", "trip", "wave"
]

VALID_EMOTIONS = [
    "happy", "sad", "angry", "curious", "sleepy", "bored", "thinking", "normal", "dizzy",
    "shock", "love", "excited", "embarrassed", "proud"
]

# Actions suitable for casual reflective dialogue
REFLECTIVE_ACTIONS = [
    "sitOnCorner", "sit", "wander", "idle", "stretch", "climbWindow", "peekWindow",
    "investigate", "tapWindow", "bow", "roll", "sitOnMenuBar"
]

# Emotions suitable for casual reflective dialogue
REFLECTIVE_EMOTIONS = [
    "normal", "curious", "thinking", "sleepy", "happy", "love"
]

# ============================================================
# Thinking & Latency-Masking Connectors
# ============================================================
THINKING_PREFIXES_CMD = [
    "Let me check...",
    "Let me check that for you...",
    "Let me think...",
    "Hmm, let me see...",
    "Give me a second...",
    "Right on it! Let me check...",
    "Hold on a sec...",
    "Hmm, let's see...",
    "One second, checking that...",
    "On it! Let me open that...",
    "Just a sec, let me look into that...",
    "Alright, let me check...",
    "Ooh, right away! Let me check...",
    "Give me a moment...",
    "Let me pull that up...",
    "Hold tight, let me check...",
    "Wait a second, let me check...",
    "Starting that up... let me check...",
    "Let me fetch that for you...",
    "Sure thing! Let me check..."
]

THINKING_PREFIXES_TALK = [
    "Let me think...",
    "Hmm, let me think...",
    "Hmm, let me see...",
    "Ooh, let me think about that...",
    "Good question! Let me think...",
    "Hmm, thinking...",
    "Let me see...",
    "That's interesting! Let me think...",
    "Let me think for a sec...",
    "Hmm, let me ponder that...",
    "Give me a sec to think...",
    "Ooh, let me process that...",
    "Ah, let me think...",
    "Hmm...",
    "Mhm, let me see..."
]

USER_PREFIXES = [
    "", "", "", "", "",  # weighted default (no prefix)
    "hey Byte, ", "Byte, ", "yo Byte, ", "hey buddy, ", "please ",
    "could you ", "can you ", "Byte could you ", "Byte please ", "hey can you ",
    "do me a favor and ", "be a pal and ", "quickly ", "when you get a chance, "
]

# Security whitelist verification regexes matching AIEngine.swift
ALLOWED_PATTERNS = [
    r"(?i)^open\s+-a\s+\"?[A-Za-z0-9_ -]+\"?\s*$",
    r"(?i)^open\s+https?://[A-Za-z0-9_./?%&=+-]+\s*$",
    r"(?i)^open\s+-a\s+\"?[A-Za-z0-9_ -]+\"?\s+https?://[A-Za-z0-9_./?%&=+-]+\s*$",
    r"(?i)^open\s+~[A-Za-z0-9_/.-]+\s*$",
    r"(?i)^osascript\s+-e\s+.+$",
    r"(?i)^screencapture\s+[~A-Za-z0-9_./ -]+\s*$",
    r"(?i)^pmset\s+[a-z]+\s*$",
    r"(?i)^top\s+.+$",
    r"(?i)^df\s+.+$"
]
DANGEROUS = [";", "&&", "||", "|", "`", "$(", "\n", "\r"]

def is_cmd_valid(cmd):
    if cmd == "none":
        return True
    for d in DANGEROUS:
        if d in cmd:
            return False
    for p in ALLOWED_PATTERNS:
        if re.search(p, cmd):
            return True
    return False

def make_sample(user_query, action, emotion, cmd, speech):
    assert action in VALID_ACTIONS, f"Invalid action: {action}"
    assert emotion in VALID_EMOTIONS, f"Invalid emotion: {emotion}"
    assert is_cmd_valid(cmd), f"Invalid CMD security check: {cmd}"
    
    return {
        "messages": [
            {"role": "user", "content": f"CONTEXT: User: {user_query}"},
            {"role": "assistant", "content": f"[ACTION: {action}] [EMOTION: {emotion}] [CMD: {cmd}] {speech}"}
        ]
    }

# ============================================================
# Generator 1: Process casual_reflective_100k.jsonl -> Byte Format (~100,000 samples)
# ============================================================
def load_casual_reflective_dataset(root_dir, max_samples=100000):
    reflective_file = os.path.join(root_dir, "casual_reflective_100k.jsonl")
    if not os.path.exists(reflective_file):
        print(f"⚠️ {reflective_file} not found, skipping casual reflective dataset.")
        return []
    
    print(f"📖 Processing casual reflective dataset from {reflective_file}...")
    samples = []
    
    with open(reflective_file, 'r', encoding='utf-8') as f:
        for i, line in enumerate(f):
            if len(samples) >= max_samples:
                break
            if not line.strip():
                continue
            data = json.loads(line)
            turns = data.get("turns", [])
            
            # Extract user utterance and assistant response pairs
            for t_idx in range(0, len(turns) - 1, 2):
                if turns[t_idx]["role"] == "user" and turns[t_idx+1]["role"] == "assistant":
                    u_text = turns[t_idx]["content"].strip()
                    a_text = turns[t_idx+1]["content"].strip()
                    
                    if not u_text or not a_text:
                        continue
                        
                    act = random.choice(REFLECTIVE_ACTIONS)
                    emo = random.choice(REFLECTIVE_EMOTIONS)
                    cmd = "none"
                    
                    # Inject thinking connectors to 60% of responses
                    if random.random() < 0.6:
                        think = random.choice(THINKING_PREFIXES_TALK)
                        speech = f"{think} {a_text}"
                    else:
                        speech = a_text
                        
                    samples.append(make_sample(u_text, act, emo, cmd, speech))
                    if len(samples) >= max_samples:
                        break
                        
    print(f"✅ Loaded and converted {len(samples)} high-quality reflective Byte samples!")
    return samples

# ============================================================
# Generator 2: Web Browsing & Search Commands (~25,000 samples)
# ============================================================
WEBSITES = [
    ("YouTube", "https://youtube.com", ["youtube", "yt", "videos", "watch videos"]),
    ("Google", "https://google.com", ["google", "google search", "search web", "the internet"]),
    ("GitHub", "https://github.com", ["github", "gh", "git repos", "code repositories"]),
    ("Reddit", "https://reddit.com", ["reddit", "subreddit", "reddit posts"]),
    ("Twitter", "https://x.com", ["twitter", "x.com", "x", "tweets"]),
    ("Wikipedia", "https://wikipedia.org", ["wikipedia", "wiki", "encyclopedia"]),
    ("StackOverflow", "https://stackoverflow.com", ["stackoverflow", "stack overflow", "coding errors"]),
    ("ChatGPT", "https://chatgpt.com", ["chatgpt", "openai chat", "gpt"]),
    ("Claude", "https://claude.ai", ["claude", "claude ai", "anthropic"]),
    ("Netflix", "https://netflix.com", ["netflix", "movies", "shows"]),
    ("Twitch", "https://twitch.tv", ["twitch", "streams", "live streams"]),
    ("Spotify Web", "https://open.spotify.com", ["web spotify", "spotify web", "music player web"]),
    ("Amazon", "https://amazon.com", ["amazon", "shopping", "amazon store"]),
    ("Hacker News", "https://news.ycombinator.com", ["hacker news", "hn", "ycombinator"]),
    ("Arxiv", "https://arxiv.org", ["arxiv", "paper preprints", "ai research papers"]),
    ("MDN Web Docs", "https://developer.mozilla.org", ["mdn", "mdn docs", "javascript docs"]),
    ("Apple", "https://apple.com", ["apple site", "apple.com", "mac site"]),
    ("Google Maps", "https://maps.google.com", ["google maps", "maps web", "directions"]),
    ("Weather Channel", "https://weather.com", ["weather web", "weather forecast site"]),
    ("News", "https://news.google.com", ["google news", "daily news", "news online"]),
    ("Gmail", "https://mail.google.com", ["gmail", "google mail", "webmail"]),
    ("Tailwind Docs", "https://tailwindcss.com", ["tailwind css", "tailwind docs"]),
    ("Python Docs", "https://docs.python.org", ["python docs", "python documentation"]),
    ("Swift Docs", "https://developer.apple.com/documentation/swift", ["swift documentation", "swift docs"])
]

BROWSERS = [
    ("", "open"),
    ("Google Chrome", 'open -a "Google Chrome"'),
    ("Safari", 'open -a Safari'),
    ("Firefox", 'open -a Firefox'),
    ("Arc", 'open -a Arc'),
    ("Brave", 'open -a "Brave Browser"')
]

SEARCH_TOPICS = [
    ("llama 3.2 fine tuning", "https://google.com/search?q=llama+3.2+fine+tuning"),
    ("swiftui window management", "https://google.com/search?q=swiftui+window+management"),
    ("python asyncio tutorial", "https://google.com/search?q=python+asyncio+tutorial"),
    ("macos metal performance", "https://google.com/search?q=macos+metal+performance"),
    ("rust vs C++ 2026", "https://google.com/search?q=rust+vs+c%2B%2B+2026"),
    ("best developer tools mac", "https://google.com/search?q=best+developer+tools+mac"),
    ("kokoro tts PyTorch installation", "https://google.com/search?q=kokoro+tts+pytorch"),
    ("apple silicon lora training", "https://google.com/search?q=apple+silicon+lora+training"),
    ("how to fix git merge conflicts", "https://google.com/search?q=how+to+fix+git+merge+conflicts"),
    ("nextjs app router best practices", "https://google.com/search?q=nextjs+app+router+best+practices")
]

def generate_browser_samples(count=25000):
    samples = []
    actions = ["tapWindow", "jump", "spin", "climbWindow", "pushWidget", "wave", "investigate", "peekWindow"]
    emotions = ["happy", "curious", "excited", "normal", "proud"]
    
    phrasings = [
        "open {site}", "launch {site}", "take me to {site}", "go to {site}",
        "can you open {site}", "open up {site}", "fire up {site}",
        "navigate to {site}", "pull up {site}", "open {site} in browser",
        "open {site} for me", "show me {site}", "browse {site}"
    ]
    
    for _ in range(count):
        pfx = random.choice(USER_PREFIXES)
        think = random.choice(THINKING_PREFIXES_CMD)
        act = random.choice(actions)
        emo = random.choice(emotions)
        
        if random.random() < 0.7:
            name, url, aliases = random.choice(WEBSITES)
            alias = random.choice(aliases)
            phrase = random.choice(phrasings).format(site=alias)
            user_text = f"{pfx}{phrase}"
            
            browser_name, cmd_pfx = random.choice(BROWSERS)
            if browser_name:
                cmd = f"{cmd_pfx} {url}"
                speech = f"{think} Opening {name} in {browser_name}!"
            else:
                cmd = f"open {url}"
                speech = f"{think} Opening {name} for you!"
        else:
            query, search_url = random.choice(SEARCH_TOPICS)
            user_text = f"{pfx}search for {query}"
            browser_name, cmd_pfx = random.choice(BROWSERS)
            if browser_name:
                cmd = f"{cmd_pfx} {search_url}"
                speech = f"{think} Searching for '{query}' in {browser_name}!"
            else:
                cmd = f"open {search_url}"
                speech = f"{think} Looking up '{query}' online!"
                
        samples.append(make_sample(user_text, act, emo, cmd, speech))
    return samples

# ============================================================
# Generator 3: Desktop App Launching & System Controls (~25,000 samples)
# ============================================================
APPS = [
    ("Music", 'open -a Music', ["music", "apple music", "tunes", "songs"]),
    ("Spotify", 'open -a Spotify', ["spotify", "spotify app"]),
    ("Terminal", 'open -a Terminal', ["terminal", "shell", "console", "command line"]),
    ("Finder", 'open -a Finder', ["finder", "files", "file manager", "my files"]),
    ("Safari", 'open -a Safari', ["safari", "safari browser"]),
    ("Google Chrome", 'open -a "Google Chrome"', ["chrome", "google chrome"]),
    ("Xcode", 'open -a Xcode', ["xcode", "ios dev", "swift dev"]),
    ("Visual Studio Code", 'open -a "Visual Studio Code"', ["vscode", "vs code", "code editor", "visual studio code"]),
    ("Notes", 'open -a Notes', ["notes", "apple notes", "notepad"]),
    ("Calendar", 'open -a Calendar', ["calendar", "schedule", "events"]),
    ("Reminders", 'open -a Reminders', ["reminders", "todo list", "tasks"]),
    ("System Settings", 'open -a "System Settings"', ["system settings", "settings", "preferences", "system preferences"]),
    ("Calculator", 'open -a Calculator', ["calculator", "calc", "math app"]),
    ("Slack", 'open -a Slack', ["slack", "work chat"]),
    ("Discord", 'open -a Discord', ["discord", "gaming chat"]),
    ("Activity Monitor", 'open -a "Activity Monitor"', ["activity monitor", "task manager", "cpu monitor"]),
    ("Preview", 'open -a Preview', ["preview", "pdf viewer"]),
    ("Photos", 'open -a Photos', ["photos", "photo library", "pictures"]),
    ("Messages", 'open -a Messages', ["messages", "imessage", "texts", "chats"]),
    ("Mail", 'open -a Mail', ["mail", "email", "apple mail", "inbox"]),
    ("Podcasts", 'open -a Podcasts', ["podcasts", "shows", "podcast player"]),
    ("Books", 'open -a Books', ["books", "ebooks", "apple books"]),
    ("Maps", 'open -a Maps', ["maps", "apple maps", "navigation"]),
    ("Weather", 'open -a Weather', ["weather", "forecast", "temperature"]),
    ("Clock", 'open -a Clock', ["clock", "timer", "stopwatch", "alarm"]),
    ("TextEdit", 'open -a TextEdit', ["textedit", "text editor", "plain text"])
]

SYSTEM_CMDS = [
    ("turn volume to 50%", 'osascript -e "set volume output volume 50"', ["set volume to half", "medium volume", "volume 50"]),
    ("turn volume to 100%", 'osascript -e "set volume output volume 100"', ["max volume", "full volume", "volume 100"]),
    ("mute volume", 'osascript -e "set volume output volume 0"', ["mute sound", "turn off sound", "silence audio", "mute"]),
    ("unmute volume", 'osascript -e "set volume output volume 40"', ["unmute sound", "turn volume back on", "unmute"]),
    ("turn on dark mode", 'osascript -e \'tell app "System Events" to set dark mode of appearance preferences to true\'', ["enable dark mode", "dark theme", "night mode"]),
    ("turn off dark mode", 'osascript -e \'tell app "System Events" to set dark mode of appearance preferences to false\'', ["disable dark mode", "light mode", "bright theme"]),
    ("play pause music", 'osascript -e \'tell application "Music" to playpause\'', ["play music", "pause music", "toggle music play", "pause songs"]),
    ("play pause spotify", 'osascript -e \'tell application "Spotify" to playpause\'', ["play spotify", "pause spotify", "toggle spotify"]),
    ("next song", 'osascript -e \'tell application "Music" to next track\'', ["skip song", "next track", "play next song"]),
    ("next spotify track", 'osascript -e \'tell application "Spotify" to next track\'', ["skip spotify track", "next spotify song"]),
    ("take a screenshot", 'screencapture ~/Desktop/screenshot.png', ["screen capture", "snap screen", "capture desktop", "take picture of screen"]),
    ("put mac to sleep", 'pmset sleepnow', ["sleep mac", "put computer to sleep", "sleep mode"]),
    ("turn off display", 'pmset displaysleepnow', ["lock screen", "display sleep", "turn off screen"]),
    ("start screensaver", 'open -a ScreenSaverEngine', ["start screensaver", "launch screensaver", "screensaver"]),
    ("check top processes", 'top -l 1', ["check cpu usage", "top cpu app", "what is taking cpu", "cpu usage"]),
    ("check disk space", 'df -h /', ["how much disk space left", "check drive storage", "disk usage", "storage left"]),
    ("open downloads folder", 'open ~/Downloads', ["open downloads", "go to downloads", "show downloads"]),
    ("open desktop folder", 'open ~/Desktop', ["open desktop folder", "show desktop files"]),
    ("open documents folder", 'open ~/Documents', ["open documents", "my documents", "documents folder"]),
    ("empty trash", 'osascript -e \'tell application "Finder" to empty trash\'', ["empty trash", "clean trash", "clear bin"])
]

def generate_desktop_samples(count=25000):
    samples = []
    actions = ["pushWidget", "tapWindow", "jump", "spin", "wave", "sit", "climbWindow", "sitOnCorner"]
    emotions = ["happy", "normal", "curious", "excited", "proud"]
    
    app_phrasings = [
        "open {app}", "launch {app}", "start {app}", "fire up {app}",
        "can you open {app}", "please start {app}", "activate {app}",
        "bring up {app}", "load {app}", "open up {app}"
    ]
    
    for _ in range(count):
        pfx = random.choice(USER_PREFIXES)
        think = random.choice(THINKING_PREFIXES_CMD)
        act = random.choice(actions)
        emo = random.choice(emotions)
        
        if random.random() < 0.7:
            app_name, cmd, aliases = random.choice(APPS)
            alias = random.choice(aliases)
            phrase = random.choice(app_phrasings).format(app=alias)
            user_text = f"{pfx}{phrase}"
            speech = f"{think} Opening {app_name} right away!"
        else:
            name, cmd, aliases = random.choice(SYSTEM_CMDS)
            alias = random.choice(aliases)
            user_text = f"{pfx}{alias}"
            speech = f"{think} Executing system command for '{name}'!"
            
        samples.append(make_sample(user_text, act, emo, cmd, speech))
    return samples

# ============================================================
# Generator 4: Pet Tricks & Animations (~15,000 samples)
# ============================================================
TRICKS = [
    ("do a backflip", "backflip", "proud", "Watch this flip! Nailed the landing!"),
    ("spin around", "spin", "excited", "Wheee! Spinning around on your desktop!"),
    ("do a dance", "dance", "happy", "Grooving to the desktop rhythm! Let's go!"),
    ("sit on my menu bar", "sitOnMenuBar", "normal", "Perched right up on your menu bar, keeping watch!"),
    ("climb the window", "climbWindow", "curious", "Climbing up your window frame! Great view up here."),
    ("push widget", "pushWidget", "normal", "Nudging your desktop widget into place!"),
    ("tap on window", "tapWindow", "curious", "Tap tap tap! Hello there!"),
    ("stretch", "stretch", "sleepy", "Stretching tall! Ahhh, that feels so good."),
    ("roll over", "roll", "happy", "Rolling right over on your screen!"),
    ("sneeze", "sneeze", "embarrassed", "Achoo! Hehe, excuse me!"),
    ("headbang", "headbang", "excited", "Headbanging to the beat! Hell yeah!"),
    ("wave to me", "wave", "happy", "Waving hello! Always happy to see you!"),
    ("chase the laser", "chaseLaser", "excited", "Pouncing after that laser pointer! Got it!"),
    ("hide", "hide", "curious", "Peek-a-boo! Hiding behind your active window!"),
    ("bow", "bow", "proud", "Taking a deep bow for my favorite user!")
]

def generate_trick_samples(count=15000):
    samples = []
    for _ in range(count):
        pfx = random.choice(USER_PREFIXES)
        think = random.choice(THINKING_PREFIXES_CMD)
        q, act, emo, speech_base = random.choice(TRICKS)
        user_text = f"{pfx}{q}"
        cmd = "none"
        speech = f"{think} {speech_base}"
        samples.append(make_sample(user_text, act, emo, cmd, speech))
    return samples


def main():
    random.seed(42)
    workspace_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    output_dir = os.path.dirname(os.path.abspath(__file__))
    train_path = os.path.join(output_dir, "train.jsonl")
    valid_path = os.path.join(output_dir, "valid.jsonl")
    
    print("🚀 Generating 100k+ Mega Dataset with Casual Reflection Data, Thinking Connectors & Browser/Desktop Commands...")
    
    # 1. Load casual reflective dataset (100,000 samples)
    reflective_samples = load_casual_reflective_dataset(workspace_root, max_samples=100000)
    
    # 2. Generate command & trick samples
    browser_samples = generate_browser_samples(25000)
    desktop_samples = generate_desktop_samples(25000)
    trick_samples = generate_trick_samples(15000)
    
    new_generated = reflective_samples + browser_samples + desktop_samples + trick_samples
    random.shuffle(new_generated)
    
    print(f"Total new/adapted samples ready: {len(new_generated)}!")
    
    # 3. Read baseline dataset (train_backup_20260808.jsonl or train.jsonl)
    backup_train = os.path.join(output_dir, "train_backup_20260808.jsonl")
    read_file = backup_train if os.path.exists(backup_train) else train_path
        
    existing_samples = []
    with open(read_file, 'r', encoding='utf-8') as f:
        for line in f:
            if line.strip():
                data = json.loads(line)
                # Sanitize legacy piped commands if present
                if "messages" in data:
                    c = data["messages"][1]["content"]
                    if "| head" in c or "| grep" in c:
                        c = c.replace("top -l 1 -s 0 | head -n 10", "top -l 1")
                        c = c.replace("top -l 1 -s 0 | head -n 12", "top -l 1")
                        c = c.replace("top -l 1 -s 0 | grep CPU", "top -l 1")
                        data["messages"][1]["content"] = c
                    if "&& pmset" in c:
                        data["messages"][1]["content"] = c.replace("osascript -e 'delay 60' && pmset sleepnow", "pmset sleepnow")
                existing_samples.append(data)
                
    print(f"Loaded {len(existing_samples)} baseline samples from {os.path.basename(read_file)}")
    
    # 4. Master dataset combination
    master_train = existing_samples + new_generated
    random.shuffle(master_train)
    
    print(f"Master training set total size: {len(master_train)} samples!")
    
    # Save train.jsonl
    with open(train_path, 'w', encoding='utf-8') as f:
        for item in master_train:
            f.write(json.dumps(item, ensure_ascii=False) + '\n')
            
    print(f"✅ Saved updated master training dataset to {train_path}")
    
    # Create balanced validation set (3000 samples)
    valid_samples = random.sample(new_generated, 1500) + random.sample(existing_samples, 1500)
    random.shuffle(valid_samples)
    with open(valid_path, 'w', encoding='utf-8') as f:
        for item in valid_samples:
            f.write(json.dumps(item, ensure_ascii=False) + '\n')
            
    print(f"✅ Saved updated validation dataset to {valid_path}")
    
    # Verify statistics
    cmd_real = 0
    thinking_cnt = 0
    for s in master_train:
        content = s["messages"][1]["content"] if "messages" in s else s.get("text", "")
        if "[CMD: none]" not in content and "[CMD:none]" not in content:
            cmd_real += 1
        if any(tp.lower() in content.lower() for tp in ["let me check", "let me think", "hmm, let me see", "give me a second", "right on it"]):
            thinking_cnt += 1
    
    print("\n--- DATASET STATS SUMMARY ---")
    print(f"Total master samples: {len(master_train)}")
    print(f"CMD real samples: {cmd_real} ({cmd_real/len(master_train)*100:.1f}%)")
    print(f"Thinking phrase coverage: {thinking_cnt} ({thinking_cnt/len(master_train)*100:.1f}%)")

if __name__ == "__main__":
    main()
