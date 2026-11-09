#!/bin/bash
# Process every downloaded Tripo kit model into game/world/kit/, three at a time.
#   tools/citykit/process_all.sh            # everything in art/tripo/kit_*
#   tools/citykit/process_all.sh t01 m01    # just these
# Each asset writes its own row.json; kit.json is rebuilt from those at the end, so the three
# parallel Blender runs never race. Uses the machine-wide 'heavy' slots via tools/blender.sh.
set -u
cd "$(cd "$(dirname "$0")/../.." && pwd)" || exit 1
ids=("$@")
if [ ${#ids[@]} -eq 0 ]; then
  ids=()
  while read -r line; do ids+=("$line"); done < <(python3 - <<'PY'
import os, sys
sys.path.insert(0, "tools/citykit")
from assets import ASSETS
src = os.path.join(os.getcwd(), "art", "tripo")
for a in ASSETS:
    if os.path.exists(os.path.join(src, "kit_" + a.id, "model.glb")):
        print(a.id)
PY
)
fi
[ ${#ids[@]} -gt 0 ] || { echo "nothing to process"; exit 0; }
echo "processing ${#ids[@]} assets: ${ids[*]}"
for ((i = 0; i < ${#ids[@]}; i += 3)); do
  for id in "${ids[@]:i:3}"; do
    ( tools/blender.sh run blender/citykit/process.py -- --id "$id" 2>&1 \
        | grep -E "^KIT |GRADE |up axis was|ground-plate|Error|Traceback" | sed "s/^/[$id] /" ) &
  done
  wait
done
python3 - <<'PY'
import json, os
root = os.path.join(os.getcwd(), "game", "world", "kit")
rows = []
for d in sorted(os.listdir(root)):
    p = os.path.join(root, d, "row.json")
    if os.path.isfile(p):
        rows.append((d, json.load(open(p))))
print("rows on disk: %d" % len(rows))
bad = [d for d, r in rows if r["tris"] > r["budget"]]
print("over budget: %s" % (bad or "none"))
tot = sum(r["file_kb"] for _, r in rows)
print("total kit size: %.1f MB, tris %d" % (tot / 1024.0, sum(r["tris"] for _, r in rows)))
PY
