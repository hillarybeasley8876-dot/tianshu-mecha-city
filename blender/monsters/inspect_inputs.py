"""Inspect the Tripo monster inputs (monster-assets): bones, clips, tri counts, bounds, materials.

    tools/blender.sh run blender/monsters/inspect_inputs.py -- [--type=ripper,...]

Prints one block per input file so the build scripts can be written against the real skeleton names.
"""
import argparse
import json
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")
TYPES = ["ripper", "mantis", "spitter", "harrier", "juggernaut", "titan", "hive"]


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--type", default="")
    p.add_argument("--bones", action="store_true", help="print every bone name")
    return p.parse_args(argv)


def bounds(obj) -> tuple:
    mw = obj.matrix_world
    pts = [mw @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def action_fcurves(a) -> list:
    """Blender 5 slotted actions: fcurves live in a channelbag, not on the action."""
    try:
        return list(a.fcurves)
    except AttributeError:
        out = []
        for layer in a.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    out.extend(bag.fcurves)
        return out


def describe(path: str, want_bones: bool) -> None:
    common.reset()
    if not os.path.exists(path):
        print("MISSING %s" % path)
        return
    print("\n===== %s (%.1f MB)" % (path, os.path.getsize(path) / 1e6))
    bpy.ops.import_scene.gltf(filepath=path)
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            lo, hi = bounds(obj)
            tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
            mats = [m.name if m else "<none>" for m in obj.data.materials]
            vg = len(obj.vertex_groups)
            print("  MESH %-22s tris %8d verts %8d vgroups %3d mods %s" % (
                obj.name, tris, len(obj.data.vertices), vg, [m.type for m in obj.modifiers]))
            print("       bounds Z(blender) %.2f..%.2f  X %.2f..%.2f  Y %.2f..%.2f  mats %s" % (
                lo.z, hi.z, lo.x, hi.x, lo.y, hi.y, mats))
            for m in obj.data.materials:
                if m is None:
                    continue
                imgs = [n.image.name + "(%dx%d)" % (n.image.size[0], n.image.size[1])
                        for n in (m.node_tree.nodes if m.use_nodes else []) if n.type == "TEX_IMAGE"]
                print("       mat %-24s images %s" % (m.name, imgs))
        elif obj.type == "ARMATURE":
            bones = [b.name for b in obj.data.bones]
            print("  ARM  %-22s bones %d" % (obj.name, len(bones)))
            if want_bones:
                print("       " + json.dumps(bones))
            else:
                print("       " + json.dumps(bones[:14]))
    acts = sorted(bpy.data.actions, key=lambda a: a.name)
    print("  ACTIONS %d" % len(acts))
    for a in acts:
        rng = a.frame_range
        ch = len(action_fcurves(a))
        print("     %-28s frames %6.1f..%-7.1f dur %5.2fs curves %d" % (
            a.name, rng[0], rng[1], (rng[1] - rng[0]) / 24.0, ch))
    for obj in bpy.data.objects:
        ad = obj.animation_data
        if ad and ad.action:
            print("  active action on %s: %s" % (obj.name, ad.action.name))
        if ad and ad.nla_tracks:
            print("  nla %s: %s" % (obj.name, [[s.name for s in t.strips] for t in ad.nla_tracks]))


def main() -> None:
    args = parse_args()
    types = args.type.split(",") if args.type else TYPES
    for t in types:
        for name in ("model.glb", "rigged.glb"):
            p = os.path.join(ROOT, "art", "tripo", "mon_%s" % t, name)
            if os.path.exists(p):
                describe(p, args.bones)


main()
