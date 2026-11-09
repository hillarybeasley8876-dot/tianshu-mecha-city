"""Print bone world positions of the rigged Tripo monsters so the builders can orient them.

    tools/blender.sh run blender/monsters/probe_bones.py -- --type=ripper
"""
import argparse
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")
TYPES = ["ripper", "mantis", "harrier", "juggernaut", "titan"]


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--type", default="")
    args = p.parse_args(argv)
    for t in (args.type.split(",") if args.type else TYPES):
        path = os.path.join(ROOT, "art", "tripo", "mon_%s" % t, "rigged.glb")
        if not os.path.exists(path):
            continue
        common.reset()
        bpy.ops.import_scene.gltf(filepath=path)
        arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
        print("\n===== %s" % t)
        if arm is None:
            print("  no armature")
            continue
        bpy.context.view_layer.objects.active = arm
        mw = arm.matrix_world
        for b in arm.data.bones:
            h = mw @ b.head_local
            tl = mw @ b.tail_local
            print("  %-26s head (%6.3f %6.3f %6.3f) tail (%6.3f %6.3f %6.3f) parent %s" % (
                b.name, h.x, h.y, h.z, tl.x, tl.y, tl.z, b.parent.name if b.parent else "-"))
        mesh = next((o for o in bpy.data.objects if o.type == "MESH" and o.data.materials), None)
        if mesh is not None:
            pts = [mw @ mesh.matrix_world @ Vector(c) for c in mesh.bound_box]
            print("  mesh world X %.3f..%.3f Y %.3f..%.3f Z %.3f..%.3f" % (
                min(q.x for q in pts), max(q.x for q in pts),
                min(q.y for q in pts), max(q.y for q in pts),
                min(q.z for q in pts), max(q.z for q in pts)))


main()
