"""Merge per-segment karaoke ASS files for a bulk4 fix rebuild into captions-v3.ass.

Usage (run from the clip workdir):
  python3 merge_fix_ass.py [--no-moment-captions]

Reads ass-intro-v3.ass, ass-moment-seg*.ass (in segment order, unless
--no-moment-captions), and ass-outro-v3.ass; concatenates Dialogue events,
sorts by start, clamps overlaps, writes captions-v3.ass using the intro
file's header (which carries the per-clip MarginV style).
"""
import glob
import os
import re
import sys


def parse(t):
    h, m, s = t.split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)


def fmt(x):
    h = int(x // 3600)
    m = int((x % 3600) // 60)
    s = x % 60
    return f"{h}:{m:02d}:{s:05.2f}"


def main():
    flist = ["ass-intro-v3.ass"]
    if "--no-moment-captions" not in sys.argv:
        segs = sorted(glob.glob("ass-moment-seg*.ass"),
                      key=lambda p: int(re.search(r"seg(\d+)", p).group(1)))
        flist.extend(segs)
        if not segs and os.path.exists("ass-moment-v3.ass"):
            flist.append("ass-moment-v3.ass")
    flist.append("ass-outro-v3.ass")
    parts = []
    for f in flist:
        lines = open(f, encoding="utf-8-sig").read().splitlines()
        parts.extend([l for l in lines if l.startswith("Dialogue:")])
    ev = []
    for line in parts:
        fields = line.split(",", 9)
        ev.append([parse(fields[1]), parse(fields[2]), line])
    ev.sort(key=lambda e: e[0])
    fixed = 0
    for a, b in zip(ev, ev[1:]):
        if a[1] > b[0]:
            a[1] = b[0]
            fixed += 1
    out_lines = []
    for s, e, line in ev:
        if e <= s:
            continue
        fields = line.split(",", 9)
        fields[1] = fmt(s)
        fields[2] = fmt(e)
        out_lines.append(",".join(fields))
    header = open("ass-intro-v3.ass", encoding="utf-8-sig").read().split("[Events]")[0]
    with open("captions-v3.ass", "w", encoding="utf-8-sig") as out:
        out.write(header + "[Events]\n")
        out.write("Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n")
        out.write("\n".join(out_lines) + "\n")
    print(f"merged events: {len(out_lines)} seam overlaps fixed: {fixed} from {flist}")


if __name__ == "__main__":
    main()
