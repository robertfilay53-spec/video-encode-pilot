# video-encode-pilot

One-clip pilot: run the production viral-clip encode pipeline on GitHub
Actions and compare the result against the local build for consistency
and quality.

## The clip

`bulk4-viral-adin-2k.mp4` — "Gorlock went down", Adin Ross Fat Camp
(26.3 s, 1080x1920, 30 fps, senior review PASS v2, already scheduled on
Facebook). Local final SHA256:
`3532f1423862e7dff707b0c43241ffcf577603e4c3019599359878cd11535dc3`,
loudness -14.81 LUFS / TP -1.29.

Build inputs (all in `inputs/`): the 22.6 s source Short
(608x1080), Chip VO intro/outro mp3s + word-timing jsons, moment words
json. Windows: intro `0:5.4`, moment `11.47:22.59`, outro
`12.77:19.69,15.75:18.718`. Hook `GORLOCK WENT DOWN`, credit
`Clip: Adin Ross`, karaoke MarginV 1550 (this clip only).

## The pipeline (complete, not a subset)

`build_fix_clip.sh` is the live fix-rebuild script that produced this
clip (evolved from `build_viral_clip_v3.sh`; only file paths were
adapted to repo-relative ones, encode logic untouched):

- Grade chain on every segment: `hqdn3d + eq(contrast 1.08 / saturation
  1.18 / brightness 0.01) + unsharp`, lanczos scale to 1080x1920
- Karaoke captions spec v3 (`make_viral_ass_v3.py`): 72 pt Noto Sans
  Condensed Black, yellow #FFD400 active word at 115%, cyan #00E5FF
  keywords, outline 6, MarginV 1550 for this clip
- Hook drawtext in Anton 72 pt yellow (first 2.5 s), credit drawtext
  bottom-right
- libx264 preset medium CRF 20, 1080x1920 30 fps, AAC 192k
- Loudnorm to -14 LUFS / TP -1.5 (live recipe), with the automatic
  second pass when more than 0.8 LU off, then audio trimmed to video
  duration
- faststart, metadata stripped (`-map_metadata -1`, `+bitexact`)

## ffmpeg: ours, pinned, never the runner's

The workflow downloads a pinned BtbN static build and verifies its
SHA256 before use:

- Release tag: `autobuild-2026-11-17-12-40`
- Asset: `ffmpeg-n8.1.3-35-gf1acb0a266-linux64-gpl-8.1.tar.xz`
- SHA256: `4f88dca1e0e3079b0e8ba59a74a5bbdb8c89086a1508630616df76a56b0e0e55`
- Version that runs: ffmpeg n8.1.3 (local build is 8.1.2; 8.1.3 is the
  closest pinned static build available)

Before the build, the workflow prints the installed ffmpeg version and
checks the needed pieces exist: `subtitles`/`ass` (libass), `libx264`,
`loudnorm`, `drawtext`, `hqdn3d`, `unsharp`, `concat`. The bundled
fonts (OFL: Noto Sans Condensed Black, Anton) are installed into
fontconfig so the ASS renderer resolves them by name.

## Status

Pilot only. Nothing in this repo publishes, schedules, or posts
anything.
