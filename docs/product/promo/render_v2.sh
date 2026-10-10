#!/bin/sh
# Renders quote_desk_promo_v2.mp4: frames from promo_v2.html, voiceover from vo_v2.py, music from music_v2.py.
# Usage: sh render_v2.sh <frames dir outside the repo>
set -e
cd "$(dirname "$0")"
F="${1:?frames dir}"
[ -f "$F/f0899.jpg" ] && [ -z "$RERENDER" ] || node capture_v2.js frames "$F"   # set RERENDER=1 to redraw frames
# voice starts (seconds) match LINES in vo_v2.py
ffmpeg -y -v error -i audio/music_v2.wav \
  -i audio/vo1_v2.wav -i audio/vo2_v2.wav -i audio/vo3_v2.wav -i audio/vo4_v2.wav -i audio/vo6_v2.wav -i audio/vo9_v2.wav \
  -filter_complex "\
[1]adelay=150|150[a1];[2]adelay=3050|3050[a2];[3]adelay=5600|5600[a3];[4]adelay=12550|12550[a4];[5]adelay=18550|18550[a5];[6]adelay=25550|25550[a6];\
[a1][a2][a3][a4][a5][a6]amix=inputs=6:normalize=0,aformat=channel_layouts=stereo,asplit[vo][vokey];\
[0]volume=0.42[m];[m][vokey]sidechaincompress=threshold=0.03:ratio=5:attack=20:release=350[md];\
[vo][md]amix=inputs=2:normalize=0,volume=5dB,alimiter=limit=0.95,atrim=0:30[out]" \
  -map "[out]" -ar 48000 audio/mix_v2.wav
ffmpeg -y -v error -framerate 30 -i "$F/f%04d.jpg" -i audio/mix_v2.wav \
  -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -c:a aac -b:a 192k -t 30 -movflags +faststart quote_desk_promo_v2.mp4
ffprobe -v error -show_entries format=duration,size -of default=nw=1 quote_desk_promo_v2.mp4
