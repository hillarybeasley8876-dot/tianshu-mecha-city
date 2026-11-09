"""Probe the foot bones of every monster rig (monster-assets).

    tools/blender.sh run blender/monsters/diag_feet.py -- --type=mantis

Prints, for one type's exported rig, every leaf bone with its height band over the walk clip and
its parent chain, so the foot-bone table in mon_types.py is written from evidence rather than from
a guess about which end of a limb is the lowest.
"""
import argparse
import os
import sys

import bpy

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

from monsters import mon_lib, mon_stride  # noqa: E402


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--type", required=True)
    p.add_argument("--clip", default="walk")
    args = p.parse_args(argv)
    common.reset()
    path = os.path.join(mon_lib.OUT_DIR, args.type, "%s.glb" % args.type)
    objs = mon_lib.load_glb(path)
    arm = mon_lib.only_armature(objs, args.type)
    body = next((o for o in objs if o.type == "MESH" and o.name.startswith("Body")), None)
    lo, hi = mon_lib.mesh_bounds(body)
    height = hi.z - lo.z
    action = next((a for a in bpy.data.actions if a.name == args.clip), None)
    print("PROBE %s height %.2f m ground %.2f clip %s" % (args.type, height, lo.z, args.clip))
    leaves = mon_stride.leaf_names(arm)
    if action is None:
        print("  no clip %s; leaves: %s" % (args.clip, leaves))
        return
    pts = mon_stride.sample(arm, action, leaves)
    for name in sorted(leaves, key=lambda n: float(pts[n][:, 2].min())):
        z = pts[name][:, 2]
        chain = []
        bone = arm.data.bones[name]
        while bone is not None and len(chain) < 5:
            chain.append(bone.name)
            bone = bone.parent
        print("  %-22s z %.2f .. %.2f  (ground +%.2f)  <- %s"
              % (name, z.min(), z.max(), z.min() - lo.z, " <- ".join(chain[1:])))


main()
