#!/bin/bash
# city-build: solve the lead's vista cameras against the built city (lead r2).
#   tools/city/vistas.sh            solve -> data/vistas.proposed.json
#   tools/city/vistas.sh --shots    ... and capture captures/city_<id>_proposed.jpg
# The GDScript lives under res:// (game/world/city/tools/vista_solver.gd) because tools/godot.sh
# only accepts res:// paths; this wrapper is the command the brief names.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
"$ROOT/tools/godot.sh" test res://world/city/tools/vista_solver.gd --timeout=900 || exit 1
[ "${1:-}" = "--shots" ] || exit 0
cams=$(python3 - "$ROOT/data/vistas.proposed.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
out = []
for v in d["vistas"]:
    p = ",".join(str(int(round(float(c)))) for c in v["pos_godot"])
    l = ",".join(str(int(round(float(c)))) for c in v["look_godot"])
    out.append("%s_proposed:%s:%s:%g" % (v["id"], p, l, float(v["fov"])))
print(";".join(out))
PY
)
[ -n "$cams" ] || exit 1
exec "$ROOT/tools/godot.sh" shot --scene=res://main.tscn --out=city --warm=90 --env-only \
  --skip-menu --stub=player,camera,enemies,flow --cams="$cams"
