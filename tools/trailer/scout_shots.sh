#!/bin/bash
# Candidate-stage stills for the combat-stage pick (trailer unit, lead brief trailer-r2 §1).
#
#   tools/trailer/scout_shots.sh            # every stage in tmp/trailer/scout_cams.json
#   tools/trailer/scout_shots.sh A6_garden  # one
#
# Reads the camera specs probe_stage.gd printed (tools/trailer/scout_cams.py builds the json from a
# scout log) and shoots each stage's candidate cameras with the real game, HUD off, pack spawned.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPEC="$ROOT/tmp/trailer/scout_cams.json"
OUT="$ROOT/captures/trailer/scout"
WARM="${SCOUT_WARM:-900}"

[ -f "$SPEC" ] || { echo "scout_shots: $SPEC missing — run tools/trailer/scout_cams.py first"; exit 2; }
mkdir -p "$OUT"

stages=$(python3 -c "
import json,sys
d=json.load(open('$SPEC'))
print('\n'.join(sys.argv[1:]) if len(sys.argv)>1 else '\n'.join(d))
" "$@")

for s in $stages; do
  read -r spawn cams <<<"$(python3 -c "
import json
d=json.load(open('$SPEC'))['$s']
print(d['spawn'] + ',180 ' + d['cams'])
")"
  echo "== $s spawn=$spawn"
  "$ROOT/tools/godot.sh" shot --scene=res://trailer/shot.tscn --out="scout_$s" --outdir="$OUT" \
    --trailer-hud=0 --warm="$WARM" --skip-menu --stub=flow --tod=0.6 \
    --enemies=ripper:3,mantis:1 --spawn="$spawn" --cams="$cams" 2>&1 \
    | grep -E "CAPTURE (errors|scout)" | tail -12
done
