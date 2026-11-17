"""Word-level karaoke ASS captions for viral clips.

Usage: python make_viral_ass.py <words.json> <out.ass> [--offset SEC] [--start SEC] [--end SEC]

Reads the transcribe.py words.json format: {"words": [{"word": str, "start": float, "end": float}]}
Keeps words whose midpoint falls in [start, end) and shifts them so `start` maps to 0
(or by --offset). Groups 1-3 words per line, active word highlighted amber, rest white.
Style: Noto Sans Condensed Black, white bold + black outline, bottom-center above the
Reels/Shorts UI safe zone.
"""
import json
import os
import sys

W, H = 1080, 1920
FONT = "Noto Sans Condensed Black"
FONT_SIZE = 72
MARGIN_H = 60
MARGIN_V = int(os.environ.get("MARGIN_V", "420"))
ACCENT = "&H0000D4FF"   # yellow #FFD400 highlight (ASS colours are BGR)
KEYWORD = "&H00FFE500"  # cyan #00E5FF for numbers/prices/names
BASE = "&H00FFFFFF"
MAX_WORDS = 3
MAX_GAP = 0.7


def is_keyword(word):
    w = word.strip(",.!?\"'").upper()
    if any(c.isdigit() or c == "$" for c in word):
        return True
    return w in {"GTA", "VI", "KAI", "CENAT", "ADIN", "ROSS", "ASMONGOLD",
                 "BLIZZARD", "OLYMPUS", "ISHOWSPEED", "SPEED", "PROWLER",
                 "MILES", "MORALES", "SAN", "ANDREAS", "WARCRAFT", "MILLION",
                 "JYNXZI", "CASEOH", "PEANUT"}


def esc(text):
    return text.replace("\\", "\\\\").replace("{", "(").replace("}", ")")


def ts(sec):
    if sec < 0:
        sec = 0.0
    h, rem = divmod(sec, 3600)
    m, s = divmod(rem, 60)
    return f"{int(h):d}:{int(m):02d}:{s:05.2f}"


def main():
    words_path, out_path = sys.argv[1], sys.argv[2]
    offset = 0.0
    start = None
    end = None
    i = 3
    while i < len(sys.argv):
        if sys.argv[i] == "--offset":
            offset = float(sys.argv[i + 1]); i += 2
        elif sys.argv[i] == "--start":
            start = float(sys.argv[i + 1]); i += 2
        elif sys.argv[i] == "--end":
            end = float(sys.argv[i + 1]); i += 2
        else:
            i += 1

    with open(words_path, encoding="utf-8") as f:
        data = json.load(f)
    raw = data.get("words", [])
    words = []
    for w in raw:
        mid = (w["start"] + w["end"]) / 2
        if start is not None and mid < start:
            continue
        if end is not None and mid >= end:
            continue
        base = (start if start is not None else 0.0)
        words.append({
            "w": w["word"].strip(),
            "s": round(w["start"] - base + offset, 3),
            "e": round(w["end"] - base + offset, 3),
        })
    words = [w for w in words if w["w"]]

    lines, cur = [], []
    for w in words:
        if cur and (len(cur) >= MAX_WORDS or w["s"] - cur[-1]["e"] > MAX_GAP):
            lines.append(cur); cur = []
        cur.append(w)
    if cur:
        lines.append(cur)

    header = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {W}
PlayResY: {H}
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Cap,{FONT},{FONT_SIZE},{BASE},{BASE},&H00181818,&H90000000,-1,0,0,0,100,100,1,0,1,6,2,2,{MARGIN_H},{MARGIN_H},{MARGIN_V},1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""

    events = []
    for li, line in enumerate(lines):
        next_start = lines[li + 1][0]["s"] if li + 1 < len(lines) else None
        for j, active in enumerate(line):
            parts = []
            for k, w in enumerate(line):
                if k == j:
                    colour = KEYWORD if is_keyword(w["w"]) else ACCENT
                    scale = r"\fscx115\fscy115"
                else:
                    colour = BASE
                    scale = ""
                parts.append(rf"{{\c{colour}{scale}}}{esc(w['w'])}")
            s = active["s"]
            if j + 1 < len(line):
                e = line[j + 1]["s"]
            else:
                e = active["e"] + 0.35
                if next_start is not None:
                    e = min(e, next_start - 0.02)
            if e - s < 0.08:
                e = s + 0.08
            events.append([s, e, " ".join(parts)])

    events.sort(key=lambda e: e[0])
    for a, b in zip(events, events[1:]):
        if a[1] > b[0]:
            a[1] = b[0]

    out = [f"Dialogue: 0,{ts(s)},{ts(e)},Cap,,0,0,0,,{t}" for s, e, t in events if e > s]
    with open(out_path, "w", encoding="utf-8-sig") as f:
        f.write(header)
        f.write("\n".join(out) + "\n")
    print(f"OK: {len(out)} events, {len(words)} words -> {out_path}")


if __name__ == "__main__":
    main()
