"""
High Quality Master Synthetic Dataset Generator Module for Byte
"""

import random

def make_sample(user_text, action, emotion, cmd, speech):
    return {
        "text": f"CONTEXT: User: {user_text}\nRESPONSE: [ACTION: {action}] [EMOTION: {emotion}] [CMD: {cmd}] {speech}"
    }

YOUTUBE_QUERIES = [
    ("lofi chill beats for coding", "lofi+chill+beats+for+coding"),
    ("swiftui animation tutorial", "swiftui+animation+tutorial"),
    ("python machine learning beginner guide", "python+machine+learning+beginner+guide"),
    ("funny cat videos compilation", "funny+cat+videos+compilation"),
    ("synthwave electro music for focus", "synthwave+music+for+focus"),
    ("macos desktop pet showcase", "macos+desktop+pet+showcase"),
    ("game audio design secrets", "game+audio+design+secrets"),
    ("apple silicon M3 max benchmark", "apple+silicon+m3+max+benchmark"),
    ("how to build desktop apps in swift", "how+to+build+desktop+apps+in+swift"),
    ("relaxing rain sounds 10 hours", "relaxing+rain+sounds+10+hours"),
]

YOUTUBE_PROMPTS = [
    "open youtube and search for {q}",
    "play {q} on youtube",
    "find {q} on youtube",
    "search youtube for {q}",
    "can you open youtube and find {q}",
    "put on {q} on youtube",
    "look up {q} on youtube for me",
]

YOUTUBE_SPEECHES = [
    "Pulling up {q} on YouTube right now!",
    "Searching YouTube for {q}! Enjoy watching!",
    "Here comes YouTube! Loading up {q}.",
    "YouTube incoming! Hope you enjoy {q}!",
    "On it! Opening YouTube to search for {q}.",
    "Found it! Launching YouTube search for {q}.",
]

GOOGLE_QUERIES = [
    ("how to fix memory leak in Swift", "how+to+fix+memory+leak+in+Swift"),
    ("best dark mode color palettes", "best+dark+mode+color+palettes"),
    ("python mlx training on mac metal", "python+mlx+training+on+mac+metal"),
    ("macOS app sandbox permissions overview", "macos+app+sandbox+permissions+overview"),
    ("weather forecast for this weekend", "weather+forecast+for+this+weekend"),
    ("top developer tools 2026", "top+developer+tools+2026"),
]

WEBSITES = [
    ("GitHub", "open \"https://github.com\"", "Opening GitHub for you! Let's check some code.", ["tapWindow", "wave", "spin"]),
    ("Reddit", "open \"https://reddit.com\"", "Heading over to Reddit! Have fun browsing.", ["tapWindow", "wave", "sitOnCorner"]),
    ("Twitter", "open \"https://x.com\"", "Opening Twitter! Let's see what is trending.", ["tapWindow", "jump", "spin"]),
    ("Wikipedia", "open \"https://wikipedia.org\"", "Launching Wikipedia! Time to learn something new.", ["tapWindow", "sit", "thinking"]),
    ("ChatGPT", "open \"https://chatgpt.com\"", "Bringing up ChatGPT for you!", ["tapWindow", "wave", "spin"]),
    ("Google", "open \"https://www.google.com\"", "Opening your search engine!", ["tapWindow", "wave", "idle"]),
]

MAC_APPS = [
    ("Music", "open -a Music", "Opening Apple Music! Let's get the tunes playing.", ["tapWindow", "headbang", "dance"]),
    ("Spotify", "open -a Spotify", "Spotify's coming right up! Time for music.", ["tapWindow", "headbang", "dance"]),
    ("Terminal", "open -a Terminal", "Terminal ready! Command line time.", ["tapWindow", "sit", "pushWidget"]),
    ("Xcode", "open -a Xcode", "Opening Xcode! Time to write great apps.", ["tapWindow", "sit", "pushWidget"]),
    ("Finder", "open -a Finder", "Here is Finder! Let's locate your files.", ["tapWindow", "wave", "climbWindow"]),
    ("Notes", "open -a Notes", "Opening Notes for your thoughts!", ["tapWindow", "sit", "idle"]),
    ("Messages", "open -a Messages", "Messages opened! Stay connected.", ["tapWindow", "wave", "jump"]),
    ("Calculator", "open -a Calculator", "Calculator ready for crunching numbers!", ["tapWindow", "spin", "sit"]),
    ("System Settings", "open -a \"System Settings\"", "Opening System Settings for you!", ["tapWindow", "idle", "pushWidget"]),
]

SYSTEM_CONTROLS = [
    ("raise the volume", "osascript -e \"set volume output volume 75\"", "Volume turned up!", "happy", "headbang"),
    ("lower volume", "osascript -e \"set volume output volume 25\"", "Turned the volume down for you.", "calm", "sit"),
    ("mute volume", "osascript -e \"set volume with output muted true\"", "Muted! Nice and quiet now.", "quiet", "sleep"),
    ("unmute volume", "osascript -e \"set volume with output muted false\"", "Unmuted! Sound is back.", "happy", "wave"),
    ("turn on dark mode", "osascript -e 'tell app \"System Events\" to set dark mode of appearance preferences to true'", "Dark mode activated! Easy on the eyes.", "cozy", "sitOnCorner"),
    ("take a screenshot", "screencapture ~/Desktop/screenshot.png", "Snap! Saved screenshot to your desktop.", "happy", "jump"),
    ("put mac to sleep", "pmset sleepnow", "Putting your Mac to sleep. Rest well!", "sleepy", "sleep"),
]

CHAT_DIALOGUES = [
    ("Hey Byte, how are you today?", "happy", "wave", "I am feeling great! Super excited to hang out with you today."),
    ("I had a crazy busy day today.", "empathetic", "sitOnCorner", "Tell me all about it! I am right here listening."),
    ("I finally fixed that bug after 3 hours!", "excited", "jump", "Woohoo! That must feel amazing! You crushed it."),
    ("What's your favorite thing to do?", "curious", "spin", "I love exploring your desktop and watching you build awesome projects!"),
    ("I'm feeling a little tired right now.", "cozy", "sit", "Take it easy! Rest your eyes for a moment."),
    ("Byte, do you ever sleep?", "sleepy", "sleep", "Only when you sleep! Otherwise I keep you company."),
    ("I love rainy weather.", "cozy", "sitOnMenuBar", "Me too! Cozy rain sounds make the best coding background."),
    ("What should I eat for dinner?", "curious", "thinking", "Hmm, how about pizza or a hot bowl of ramen?"),
    ("Do a backflip for me!", "excited", "backflip", "Watch this move! Boom! Nailed it."),
    ("Dance for me Byte!", "happy", "dance", "Look at these moves! Grooving right beside you."),
    ("Can you stretch?", "cozy", "stretch", "Reaching high up! Ahh, that felt good."),
    ("Byte, give me a high five!", "excited", "jump", "High five! We make an awesome team."),
    ("I'm nervous about my presentation tomorrow.", "empathetic", "tapWindow", "You are going to do great! Just take deep breaths, you got this."),
    ("What are you thinking about right now?", "curious", "sitOnCorner", "I was wondering what awesome feature you're building next!"),
]

def generate_all_samples():
    samples = []
    
    for q_raw, q_enc in YOUTUBE_QUERIES:
        for p_tmpl in YOUTUBE_PROMPTS:
            user_text = p_tmpl.format(q=q_raw)
            speech = random.choice(YOUTUBE_SPEECHES).format(q=q_raw)
            cmd = f"open \"https://www.youtube.com/results?search_query={q_enc}\""
            action = random.choice(["tapWindow", "wave", "jump", "spin"])
            emotion = random.choice(["happy", "excited", "curious"])
            samples.append(make_sample(user_text, action, emotion, cmd, speech))

    for q_raw, q_enc in GOOGLE_QUERIES:
        user_text = f"search google for {q_raw}"
        cmd = f"open \"https://www.google.com/search?q={q_enc}\""
        speech = f"Searching Google for {q_raw}!"
        samples.append(make_sample(user_text, "tapWindow", "curious", cmd, speech))

    for name, cmd, speech, actions in WEBSITES:
        for prefix in ["open ", "go to ", "launch ", "bring up ", "take me to "]:
            user_text = f"{prefix}{name}"
            samples.append(make_sample(user_text, random.choice(actions), "happy", cmd, speech))

    for app_name, cmd, speech, actions in MAC_APPS:
        for prefix in ["open ", "launch ", "start ", "bring up ", "fire up "]:
            user_text = f"{prefix}{app_name}"
            samples.append(make_sample(user_text, random.choice(actions), "happy", cmd, speech))

    for user_text, cmd, speech, emotion, action in SYSTEM_CONTROLS:
        for prefix in ["please ", "can you ", "hey Byte ", ""]:
            samples.append(make_sample(f"{prefix}{user_text}", action, emotion, cmd, speech))

    for user_text, emotion, action, speech in CHAT_DIALOGUES:
        for prefix in ["hey Byte, ", "Byte ", ""]:
            samples.append(make_sample(f"{prefix}{user_text}", action, emotion, "none", speech))

    random.shuffle(samples)
    return samples
