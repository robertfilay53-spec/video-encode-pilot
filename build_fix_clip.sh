#!/bin/bash
# build_fix_clip.sh — bulk4 viral fix rebuilds (Nov 17 2026)
# Generalizes build_viral_clip_bulk4.sh: each of intro / moment / outro may be
# a COMMA-SEPARATED list of source windows (start:end), concatenated in order.
# Same grade chain, codec, faststart, metadata strip, loudnorm recipe
# (dynamic loudnorm I=-14 / TP=-1.5) and karaoke ASS v3 generator as the v1
# build. Differences are per-clip deviations passed in env vars:
#   MARGIN_V      karaoke MarginV (default 420; spec v3 default)
#   CREDIT_X/Y    credit drawtext position (defaults: bottom-right, as v1)
#   NO_MOMENT_CAPTIONS=1  skip moment captions (Kai wakes up, music-only)
#   RAW_OUT       intermediate raw path (defaults to <OUT>-raw.mp4); fix
#                 rebuilds write it into the workdir so ready/*-raw.mp4
#                 v1 intermediates are never touched.
# Usage: build_fix_clip.sh <WD> <SRC> <VOIN> <WOIN> <VOOUT> <WOOUT> <MWORDS>
#   <INTRO_SEGS> <MOMENT_SEGS> <OUTRO_SEGS> <HOOK> <CREDIT> <OUT> [ASPECT]
# Durations: sum(INTRO_SEGS) must equal VO intro duration; sum(OUTRO_SEGS)
# must equal VO outro duration; moment video/audio use the same windows.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WD="$1"; SRC="$2"; VOIN="$3"; WOIN="$4"; VOOUT="$5"; WOOUT="$6"
MWORDS="$7"; INTRO_SEGS="$8"; MOMENT_SEGS="$9"; OUTRO_SEGS="${10}"
HOOK="${11}"; CREDIT="${12}"; OUT="${13}"; ASPECT="${14:-16x9}"
cd "$WD"
FONT="$SCRIPT_DIR/fonts/NotoSans-CondensedBlack.ttf"
HOOK_FONT="$SCRIPT_DIR/fonts/Anton-Regular.ttf"
PY="$SCRIPT_DIR/make_viral_ass_v3.py"
MERGE_PY="$SCRIPT_DIR/merge_fix_ass.py"
GRADE="hqdn3d=1.5:1.5:6:6,eq=contrast=1.08:saturation=1.18:brightness=0.01,unsharp=5:5:0.8:5:5:0.0"
if [ "$ASPECT" = "16x9" ]; then
  VSCALE="crop=608:1080:${CROP_X:-656}:0,scale=1080:1920:flags=lanczos"
else
  VSCALE="scale=1080:1920:flags=lanczos"
fi
export MARGIN_V="${MARGIN_V:-420}"
CREDIT_X="${CREDIT_X:-w-text_w-30}"
CREDIT_Y="${CREDIT_Y:-h-90}"
RAW_OUT="${RAW_OUT:-${OUT%.mp4}-raw.mp4}"

sum_segs() { python3 -c "
print(round(sum(float(b)-float(a) for a,b in (s.split(':') for s in '''$1'''.split(','))),3))"; }

DIN=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VOIN")
DOUT=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VOOUT")
IDUR=$(sum_segs "$INTRO_SEGS"); MDUR=$(sum_segs "$MOMENT_SEGS"); ODUR=$(sum_segs "$OUTRO_SEGS")
echo "vo_intro=$DIN intro_segs=$IDUR moment=$MDUR vo_outro=$DOUT outro_segs=$ODUR total=$(python3 -c "print(round(float('$DIN')+float('$MDUR')+float('$DOUT'),3))") MarginV=$MARGIN_V credit_x=$CREDIT_X"
python3 -c "
assert abs(float('$IDUR')-float('$DIN')) < 0.05, 'intro segs != VO intro duration'
assert abs(float('$ODUR')-float('$DOUT')) < 0.05, 'outro segs != VO outro duration'
"

python3 "$PY" "$WOIN" ass-intro-v3.ass
OFF2=$(python3 -c "print(round(float('$DIN')+float('$MDUR'),3))")
rm -f ass-moment-seg*.ass
if [ "${NO_MOMENT_CAPTIONS:-0}" = "1" ]; then
  echo "moment captions skipped (NO_MOMENT_CAPTIONS=1)"
else
  CUM="$DIN"
  K=0
  IFS=',' read -ra MSEGS <<< "$MOMENT_SEGS"
  for SEG in "${MSEGS[@]}"; do
    A="${SEG%%:*}"; B="${SEG##*:}"
    python3 "$PY" "$MWORDS" "ass-moment-seg${K}.ass" --start "$A" --end "$B" --offset "$CUM"
    CUM=$(python3 -c "print(round(float('$CUM')+float('$B')-float('$A'),3))")
    K=$((K+1))
  done
fi
python3 "$PY" "$WOOUT" ass-outro-v3.ass --offset "$OFF2"
if [ "${NO_MOMENT_CAPTIONS:-0}" = "1" ]; then
  python3 "$MERGE_PY" --no-moment-captions
else
  python3 "$MERGE_PY"
fi

HOOK_ESC=$(printf '%s' "$HOOK" | sed 's/:/\\:/g; s/'"'"'/\\'"'"'/g')
CREDIT_ESC=$(printf '%s' "$CREDIT" | sed 's/:/\\:/g')
if [ "${NO_HOOK:-0}" = "1" ]; then
  HOOK_FILTER=""
else
  HOOK_FILTER="drawtext=fontfile=$HOOK_FONT:text='$HOOK_ESC':fontsize=72:fontcolor=0xFFD400:borderw=4:bordercolor=black:x=(w-text_w)/2:y=120:enable='between(t,0,2.5)',"
fi

# Full filter graph, generated in python so segment lists stay in one place.
FC=$(python3 - "$INTRO_SEGS" "$MOMENT_SEGS" "$OUTRO_SEGS" "$VSCALE" "$GRADE" "$HOOK_FILTER" "$FONT" "$CREDIT_ESC" "$CREDIT_X" "$CREDIT_Y" "$DOUT" <<'PYEOF'
import sys
intro, moment, outro, vscale, grade, hookf, font, credit, cx, cy, dout = sys.argv[1:12]
def segs(s):
    return [tuple(map(float, p.split(":"))) for p in s.split(",") if p]
allsegs = [("I", a, b) for a, b in segs(intro)] + [("M", a, b) for a, b in segs(moment)] + [("O", a, b) for a, b in segs(outro)]
parts = []
vlabels = []
for i, (kind, a, b) in enumerate(allsegs):
    parts.append(f"[0:v]trim={a}:{b},setpts=PTS-STARTPTS,{vscale},{grade},setsar=1[v{i}]")
    vlabels.append(f"[v{i}]")
parts.append("".join(vlabels) + f"concat=n={len(allsegs)}:v=1:a=0[vcat]")
parts.append(f"[vcat]{hookf}drawtext=fontfile={font}:text='{credit}':fontsize=36:fontcolor=white:borderw=2:bordercolor=black:x={cx}:y={cy},subtitles=captions-v3.ass[vout]")
alabels = []
for j, (a, b) in enumerate(segs(moment)):
    parts.append(f"[0:a]atrim={a}:{b},asetpts=PTS-STARTPTS[a{j}]")
    alabels.append(f"[a{j}]")
parts.append(f"[2:a]atrim=0:{dout},asetpts=PTS-STARTPTS[aC]")
parts.append("[1:a]" + "".join(alabels) + "[aC]concat=n=" + str(len(alabels) + 2) + ":v=0:a=1[aout]")
print(";\n".join(parts))
PYEOF
)
echo "filter segments: intro=$(echo "$INTRO_SEGS" | tr ',' '\n' | wc -l) moment=$(echo "$MOMENT_SEGS" | tr ',' '\n' | wc -l) outro=$(echo "$OUTRO_SEGS" | tr ',' '\n' | wc -l)"

ffmpeg -y -v error -i "$SRC" -i "$VOIN" -i "$VOOUT" -filter_complex "$FC" \
-map "[vout]" -map "[aout]" -map_metadata -1 -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -r 30 \
-c:a aac -b:a 192k -movflags +faststart "$RAW_OUT"

MEAS=$(ffmpeg -v info -i "$RAW_OUT" -vn -sn -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 | grep -E '"input_i"|"input_tp"|"input_lra"|"input_thresh"|"target_offset"' | sed 's/[",]//g; s/.*: //')
read -r MI MTP MLRA MTHR OFF <<< "$(echo "$MEAS" | tr '\n' ' ')"
echo "measured: I=$MI TP=$MTP LRA=$MLRA thresh=$MTHR offset=$OFF"
ffmpeg -y -v error -i "$RAW_OUT" -af "loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=$MI:measured_TP=$MTP:measured_LRA=$MLRA:measured_thresh=$MTHR:offset=$OFF" -map_metadata -1 -fflags +bitexact -c:v copy -c:a aac -b:a 192k -movflags +faststart "$OUT"
# Loudnorm undershoot check: the stock dynamic recipe lands ~0.7-1.5 LU under
# -14 on quiet raws (CaseOh v2: -15.48 after pass 1, same as v1). If the
# result is more than 0.8 LU off target, run the SAME dynamic recipe once
# more from the current output (empirically converges to ~-14.7, the value
# the senior review calls "on target" for Kai at -14.73). One extra pass max.
# The loudnorm filter also pads audio ~0.04-0.07s per pass, so trim audio
# back to the video duration afterwards.
FIN_I=$(ffmpeg -v info -i "$OUT" -vn -sn -af loudnorm=print_format=json -f null - 2>&1 | grep '"input_i"' | sed 's/[^0-9.-]//g')
echo "after pass 1: I=$FIN_I"
python3 -c "
import sys
i=float('$FIN_I')
sys.exit(0 if abs(i+14.0)>0.8 else 1)
" && {
  echo "loudness $FIN_I is >0.8 LU off -14; running one more dynamic loudnorm pass"
  MEAS2=$(ffmpeg -v info -i "$OUT" -vn -sn -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 | grep -E '"input_i"|"input_tp"|"input_lra"|"input_thresh"|"target_offset"' | sed 's/[",]//g; s/.*: //')
  read -r MI2 MTP2 MLRA2 MTHR2 OFF2 <<< "$(echo "$MEAS2" | tr '\n' ' ')"
  ffmpeg -y -v error -i "$OUT" -af "loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=$MI2:measured_TP=$MTP2:measured_LRA=$MLRA2:measured_thresh=$MTHR2:offset=$OFF2" -map_metadata -1 -fflags +bitexact -c:v copy -c:a aac -b:a 192k -movflags +faststart "${OUT%.mp4}-loud2.mp4"
  mv "${OUT%.mp4}-loud2.mp4" "$OUT"
}
VDUR=$(ffprobe -v error -show_entries stream=duration -of csv=p=0 -select_streams v:0 "$OUT")
ffmpeg -y -v error -i "$OUT" -t "$VDUR" -map_metadata -1 -fflags +bitexact -c:v copy -c:a aac -b:a 192k -movflags +faststart "${OUT%.mp4}-trim.mp4"
mv "${OUT%.mp4}-trim.mp4" "$OUT"
ffmpeg -v info -i "$OUT" -vn -sn -af loudnorm=print_format=json -f null - 2>&1 | grep -E '"input_i"|"input_tp"'
ffprobe -v error -show_entries format=duration,size -show_entries stream=width,height,codec_name,r_frame_rate -of default=noprint_wrappers=1 "$OUT"
sha256sum "$OUT"
echo "--- metadata check (should show no title/comment/artist tags):"
ffprobe -v error -show_entries format_tags -of default=noprint_wrappers=1 "$OUT"
