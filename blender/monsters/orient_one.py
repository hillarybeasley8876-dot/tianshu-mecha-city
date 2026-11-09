"""Render extra orientation views of one monster input (monster-assets).

    tools/blender.sh run blender/monsters/orient_one.py -- --type=harrier --views=top,pY

Camera presets: mY (at -Y), pY (at +Y), pX (at +X), top (above, +Y is screen up).
"""
import argparse
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")
OUT = os.path.join(ROOT, "tmp", "monster-assets")
DIRS = {"mY": Vector((0, -1, 0.12)), "pY": Vector((0, 1, 0.12)), "pX": Vector((1, 0, 0.12)),
        "top": Vector((0, 0.001, 1)), "mX": Vector((-1, 0, 0.12))}


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--type", required=True)
    p.add_argument("--file", default="model.glb")
    p.add_argument("--views", default="mY,pY,pX,top")
    args = p.parse_args(argv)
    os.makedirs(OUT, exist_ok=True)
    common.reset()
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "art", "tripo", "mon_%s" % args.type, args.file))
    for o in list(bpy.data.objects):
        if o.type == "MESH" and not o.data.materials:
            bpy.data.objects.remove(o, do_unlink=True)
    pts = [o.matrix_world @ Vector(c) for o in bpy.data.objects if o.type == "MESH" for c in o.bound_box]
    lo = Vector((min(q.x for q in pts), min(q.y for q in pts), min(q.z for q in pts)))
    hi = Vector((max(q.x for q in pts), max(q.y for q in pts), max(q.z for q in pts)))
    c = (lo + hi) * 0.5
    r = max((hi - lo).length * 0.62, 0.1)
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.05, 0.06, 0.08, 1.0)
    bg.inputs[1].default_value = 1.2
    bpy.context.scene.world = world
    for li, loc in enumerate([(2, -3, 3), (-3, 1, 2), (0.5, 2, 1)]):
        ld = bpy.data.lights.new("L%d" % li, "SUN")
        ld.energy = 3.0
        ob = bpy.data.objects.new("L%d" % li, ld)
        ob.location = c + Vector(loc).normalized() * r * 4
        ob.rotation_euler = (c - ob.location).to_track_quat("-Z", "Y").to_euler()
        common.link(ob)
    cam_data = bpy.data.cameras.new("C")
    cam_data.lens = 70
    cam = bpy.data.objects.new("C", cam_data)
    common.link(cam)
    scene = bpy.context.scene
    scene.camera = cam
    scene.render.resolution_x = scene.render.resolution_y = 560
    scene.render.image_settings.file_format = "PNG"
    for v in args.views.split(","):
        cam.location = c + DIRS[v].normalized() * r * 3.2
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(OUT, "one_%s_%s.png" % (args.type, v))
        bpy.ops.render.render(write_still=True)
        print("VIEW %s %s" % (args.type, v))


main()
