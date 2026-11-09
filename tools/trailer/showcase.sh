#!/bin/bash
# The showcase reel end to end (trailer unit, lead brief trailer-r3): record every take, cut the
# edit, and produce the evidence the lead reviews.
#
#   tools/trailer/showcase.sh            # record what is missing, then cut + sheets + framing report
#   tools/trailer/showcase.sh --force    # re-record every take first
#   tools/trailer/showcase.sh --cut-only # skip recording
#
# Windowed runs need MC_WINDOW_OK=1 (the recording half only); the cut is pure ffmpeg.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPEC="$ROOT/game/trailer/showcase.json"
OUT="$ROOT/captures/trailer/TIANSHU_showcase.mp4"
SHEETS="$ROOT/captures/trailer/sheets"
LOGS="$ROOT/captures/trailer/logs_showcase"
force=""
record=1
for a in "$@"; do
  case "$a" in
    --force) force="--force" ;;
    --cut-only) record=0 ;;
    *) echo "showcase: unknown option $a"; exit 2 ;;
  esac
done

if [ $record -eq 1 ]; then
  if [ "${MC_WINDOW_OK:-0}" != "1" ]; then
    echo "showcase: recording needs MC_WINDOW_OK=1 (a windowed run takes over the screen)"; exit 3
  fi
  "$ROOT/tools/trailer/render_all.py" --spec "$SPEC" $force || exit 1
fi

"$ROOT/tools/trailer/cut.py" --spec "$SPEC" --out "$OUT" || exit 1

mkdir -p "$SHEETS"
"$ROOT/tools/trailer/sheet.py" --spec "$SPEC" -o "$SHEETS/TIANSHU_showcase_segments.jpg" --cols 4 --at 0.5
"$ROOT/tools/trailer/sheet.py" "$OUT" -o "$SHEETS/TIANSHU_showcase_2s.jpg" --every 2.0 --cols 6

if [ -d "$LOGS" ]; then
  echo "--- framing"
  python3 "$ROOT/tools/trailer/framing_report.py" --spec "$SPEC" "$LOGS"/*.csv
fi
echo "--- defects"
"$ROOT/tools/trailer/defects.py" "$OUT"
