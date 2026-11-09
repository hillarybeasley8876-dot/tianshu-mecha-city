"""Dump one foot's height and root-space forward offset over a clip (monster-assets).

    tools/blender.sh run blender/monsters/diag_stride.py -- --type=mantis --clip=run --bone=L_ToeBase

The stride estimate is only as good as its reading of the gait, so this prints the raw trace the
estimator sees: `z` is the foot bone's height, `y` its forward offset from the pelvis (+Y is the
model's forward), and `dy` that offset's per-frame change in m/s.
"""
import argparse
import os
import sys

import bpy

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

from monsters import mon_lib, mon_stride, mon_types  # noqa: E402


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--type", required=True)
    p.add_argument("--clip", default="walk")
    p.add_argument("--bone", default="")
    args = p.parse_args(argv)
    common.reset()
    objs = mon_lib.load_glb(os.path.join(mon_lib.OUT_DIR, args.type, "%s.glb" % args.type))
    arm = mon_lib.only_armature(objs, args.type)
    action = next((a for a in bpy.data.actions if a.name == args.clip), None)
    if action is None:
        print("no clip %s in %s" % (args.clip, args.type))
        return
    bone = args.bone or mon_types.FOOT_BONES[args.type][0]
    root = mon_stride.root_bone(arm).name
    body = next(o for o in objs if o.type == "MESH" and o.name.startswith("Body"))
    ground = mon_lib.mesh_bounds(body)[0].z
    pts = mon_stride.sample(arm, action, sorted({bone, root}))
    rel = pts[bone] - pts[root]
    fps = mon_stride.FPS
    print("TRACE %s/%s bone %s vs %s  (y = forward offset from the pelvis, dy in m/s)"
          % (args.type, args.clip, bone, root))
    print("  %5s %8s %8s %8s %8s" % ("frame", "world_z", "y_rel", "dy", "hip_z"))
    for i in range(len(rel)):
        j = (i + 1) % len(rel)
        print("  %5d %8.2f %8.2f %8.2f %8.2f"
              % (i, pts[bone][i][2] - ground, rel[i][1], -(rel[j][1] - rel[i][1]) * fps,
                 pts[root][i][2] - ground))


main()
