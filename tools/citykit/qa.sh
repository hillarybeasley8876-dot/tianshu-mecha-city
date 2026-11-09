#!/bin/bash
# QA for city-kit assets: tools/citykit/qa.sh <id>...
#   captures/kit/<id>.jpg     4 lit angles + top, one strip (the per-asset QA gate sheet)
#   captures/kit/_v/<id>_a.jpg, _<id>_b.jpg   the front and rear three-quarter alone, for the grids
# Prints mesh/material/texture stats per asset so a bad import shows without opening the image.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/captures/kit"
mkdir -p "$OUT/_v"
[ $# -gt 0 ] || { echo "usage: qa.sh <id>..."; exit 2; }
for id in "$@"; do
  [ -f "$ROOT/game/world/kit/$id/$id.glb" ] || { echo "SKIP $id (not processed)"; continue; }
  tools/blender.sh run blender/citykit/qa.py -- "$id" 2>&1 | grep -E "^QA |Error|error:" || true
  files=( $(ls "$OUT/${id}"_*.png 2>/dev/null | sort) )
  [ ${#files[@]} -gt 0 ] || { echo "FAIL $id (no renders)"; continue; }
  sips -Z 420 -s format jpeg -s formatOptions 72 "$OUT/${id}_a_front34.png" --out "$OUT/_v/${id}_a.jpg" >/dev/null
  sips -Z 420 -s format jpeg -s formatOptions 72 "$OUT/${id}_b_rear34.png" --out "$OUT/_v/${id}_b.jpg" >/dev/null
  ffmpeg -v error -y -pattern_type glob -i "$OUT/${id}_*.png" \
    -vf "scale=440:-2,tile=5x1:padding=6:color=0x1c1c1e" \
    -frames:v 1 -q:v 4 "$OUT/$id.jpg" || { echo "FAIL $id (ffmpeg)"; continue; }
  rm -f "${files[@]}"
  echo "sheet: $OUT/$id.jpg"
done
