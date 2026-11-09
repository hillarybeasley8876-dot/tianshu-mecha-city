#!/bin/bash
# Trailer v2 end to end (trailer unit, lead brief trailer-r5 §2): re-record EVERY take on the current
# build, cut the edit, and produce the evidence the lead reviews.
#
#   MC_WINDOW_OK=1 tools/trailer/v2.sh            # record what is missing, then cut + sheets + gates
#   MC_WINDOW_OK=1 tools/trailer/v2.sh --force    # re-record every take first
#   tools/trailer/v2.sh --cut-only                # just the edit + the evidence
#
# The takes live in captures/trailer/shots_v3 — the spec's own `dir`, and the directory the accepted v2
# was cut from — so the edit and the r3 evidence stay comparable. Windowed runs need MC_WINDOW_OK=1;
# the cut is pure ffmpeg.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPEC="$ROOT/game/trailer/shots.json"
TAKES="$ROOT/captures/trailer/shots_v3"
OUT="$ROOT/captures/trailer/TIANSHU_trailer_v2.mp4"
SHEETS="$ROOT/captures/trailer/sheets"
force=""
record=1
for a in "$@"; do
  case "$a" in
    --force) force="--force" ;;
    --cut-only) record=0 ;;
    *) echo "v2: unknown option $a"; exit 2 ;;
  esac
done

if [ $record -eq 1 ]; then
  if [ "${MC_WINDOW_OK:-0}" != "1" ]; then
    echo "v2: recording needs MC_WINDOW_OK=1 (a windowed run takes over the screen)"; exit 3
  fi
  "$ROOT/tools/trailer/render_all.py" --spec "$SPEC" $force || exit 1
fi

mkdir -p "$TAKES" "$SHEETS"
"$ROOT/tools/trailer/cut.py" --spec "$SPEC" --out "$OUT" || exit 1
"$ROOT/tools/trailer/sheet.py" --spec "$SPEC" -o "$SHEETS/TIANSHU_trailer_v2_shots.jpg" --cols 4
"$ROOT/tools/trailer/sheet.py" "$OUT" -o "$SHEETS/TIANSHU_trailer_v2_2s.jpg" --every 2.0 --cols 6

echo "--- framing"
python3 "$ROOT/tools/trailer/framing_report.py" --spec "$SPEC" "$ROOT"/captures/trailer/logs/*.csv
echo "--- defects"
"$ROOT/tools/trailer/defects.py" "$OUT"
