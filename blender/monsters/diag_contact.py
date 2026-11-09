"""How close a clip's feet come to the floor, frame by frame (monster-assets).

    tools/blender.sh run blender/monsters/diag_contact.py -- --type=ripper --clip=scuttle

A gait that never brings a foot down to the model's own ground plane reads as a hover, whatever its
stride number says. Prints the lowest contact bone per frame against the rest-pose floor.
"""
import argparse
import os
import sys

import bpy

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

from monsters import mon_lib, mon_types  # noqa: E402


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--type", required=True)
    p.add_argument("--clip", required=True)
    args = p.parse_args(argv)
    common.reset()
    path = os.path.join(mon_lib.OUT_DIR, args.type, "%s.glb" % args.type)
    bpy.ops.import_scene.gltf(filepath=path)
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    mesh = next((o for o in bpy.data.objects if o.type == "MESH" and o.data.materials), None)
    action = bpy.data.actions.get(args.clip)
    if arm is None or action is None:
        print("CONTACT skip %s/%s" % (args.type, args.clip))
        return
    lo, _hi = mon_lib.mesh_bounds(mesh)
    arm.animation_data_create().action = action
    if hasattr(action, "slots") and len(action.slots):
        arm.animation_data.action_slot = action.slots[0]
    scene = bpy.context.scene
    start, end = int(action.frame_range[0]), int(action.frame_range[1])
    worst = 1e9
    feet = [b for b in mon_types.FOOT_BONES[args.type] if b in arm.data.bones]
    rest = min((arm.matrix_world @ arm.data.bones[b].head_local).z for b in feet) - lo.z
    print("CONTACT %s/%s  rest floor z %.3f  feet %s  rest foot %.2f m above it"
          % (args.type, args.clip, lo.z, feet, rest))
    for frame in range(start, end + 1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        lows = [(arm.matrix_world @ arm.pose.bones[b].head).z for b in feet]
        worst = min(worst, min(lows) - lo.z)
        body = min((arm.matrix_world @ p.head).z for n, p in arm.pose.bones.items()
                   if n in mon_types.ROOT_PREFERENCE) - lo.z
        print("   f%-3d lowest foot %+.2f m   body %+.2f m above the rest floor"
              % (frame, min(lows) - lo.z, body))
    print("CONTACT %s/%s closest approach %+.2f m" % (args.type, args.clip, worst))


main()
