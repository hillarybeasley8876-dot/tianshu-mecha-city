#!/bin/bash
# Re-cut TIANSHU_trailer_v2 with the lead's r3 fixes (trailer unit).
#
#   MC_WINDOW_OK=1 tools/trailer/recut_v2.sh
#
# The 14 takes the lead accepted are cloned out of its r2b worktree into captures/trailer/shots_v3
# (APFS clone, no extra disk); the four takes its review failed -- c_melee (no enemy 4.37 s),
# c_dash / c_ram (the hero behind a facade) and s08_boss (blocked 28.41 s) -- are re-recorded here
# with the re-rigged cameras, into the same directory. Then the edit is rebuilt from that directory.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPEC="$ROOT/game/trailer/shots.json"
V3="$ROOT/captures/trailer/shots_v3"
LEAD="$HOME/m/trailer-r2b/captures/trailer/shots"
REDO="c_melee,c_dash,c_ram,s08_boss"

mkdir -p "$V3"
if [ -d "$LEAD" ]; then
  for f in "$LEAD"/*.avi; do
    b="$(basename "$f")"
    case ",$REDO," in *",${b%.avi},"*) continue ;; esac
    [ -e "$V3/$b" ] || cp -c "$f" "$V3/$b" 2>/dev/null || cp "$f" "$V3/$b"
  done
fi

if [ "${MC_WINDOW_OK:-0}" != "1" ]; then
  echo "recut_v2: re-recording needs MC_WINDOW_OK=1"; exit 3
fi
"$ROOT/tools/trailer/render_all.py" --spec "$SPEC" --only "$REDO" --force --outdir "$V3" || exit 1
"$ROOT/tools/trailer/cut.py" --spec "$SPEC" --takes captures/trailer/shots_v3 \
    --out "$ROOT/captures/trailer/TIANSHU_trailer_v2.mp4" || exit 1
"$ROOT/tools/trailer/sheet.py" --spec "$SPEC" -o "$ROOT/captures/trailer/sheets/TIANSHU_trailer_v2_shots.jpg" --cols 4
"$ROOT/tools/trailer/sheet.py" "$ROOT/captures/trailer/TIANSHU_trailer_v2.mp4" \
    -o "$ROOT/captures/trailer/sheets/TIANSHU_trailer_v2_2s.jpg" --every 2.0 --cols 6
python3 "$ROOT/tools/trailer/framing_report.py" --spec "$SPEC" "$ROOT/captures/trailer/logs"/*.csv
"$ROOT/tools/trailer/defects.py" "$ROOT/captures/trailer/TIANSHU_trailer_v2.mp4"
