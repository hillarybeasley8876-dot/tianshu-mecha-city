#!/bin/zsh
# Sweep the core shrink against the magenta pixel gate (hero-v3).
#   blender/hero3/core_sweep.sh <core_shrink>
#
# Rig-only build (35 s) + 3 views, instead of the 10 min full build + 8 views: this is what made it
# possible to tune CORE_SHRINK empirically rather than by argument.
set -e
cd ~/m/mecha-city
SHRINK=$1
python3 - "$SHRINK" <<'PY'
import re, sys
p = 'blender/hero3/hero3_fit.py'
s = open(p).read()
s = re.sub(r'CORE_SHRINK = [0-9.]+', 'CORE_SHRINK = %s' % sys.argv[1], s)
open(p, 'w').write(s)
PY
tools/blender.sh run blender/hero3/build_hero3.py -- --stop-after=rig > tmp/hero-v3/loop_build.log 2>&1
tools/blender.sh run blender/hero3/core_gate.py -- --src tmp/hero-v3/stage_rig.glb \
    --out tmp/hero-v3/loop_core.glb > tmp/hero-v3/loop_gate.log 2>&1
tools/blender.sh preview tmp/hero-v3/loop_core.glb hero3_loop \
    --views close_front34,front,side --size 620x800 >> tmp/hero-v3/loop_gate.log 2>&1
echo "=== CORE_SHRINK $SHRINK ==="
uv run --with pillow python3 blender/hero3/core_gate.py --count \
    captures/blender/hero3_loop_studio_close_front34.jpg \
    captures/blender/hero3_loop_studio_front.jpg \
    captures/blender/hero3_loop_studio_side.jpg
