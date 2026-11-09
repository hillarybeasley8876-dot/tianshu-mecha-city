"""Render monster pose strips and turntables for review (monster-assets).

    tools/blender.sh run blender/monsters/render_models.py -- --type=ripper --clips=run,leap --frames=6

Imports the built GLB, drops importer helper objects, and renders `--frames` evenly spaced poses of
each clip from a 3/4 view (or `--view=front|side|top|rear`). One PNG per (clip, frame) in
tmp/monster-assets/, tiled into a contact sheet afterwards. Prints the measured bounds so the size
check does not depend on the preview tool.
"""
import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

from monsters import mon_lib  # noqa: E402

VIEWS = {"front34": Vector((1.0, -1.0, 0.42)), "rear34": Vector((-1.0, 1.0, 0.42)),
         "side": Vector((1.0, 0.0, 0.10)), "front": Vector((0.0, -1.0, 0.10)),
         "rear": Vector((0.0, 1.0, 0.10)), "top": Vector((0.0, 0.001, 1.0))}


def scene_lights(centre: Vector, radius: float) -> None:
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.06, 0.07, 0.09, 1.0)
    bg.inputs[1].default_value = 1.0
    bpy.context.scene.world = world
    for i, (loc, energy) in enumerate([((2, -3, 2.4), 4.0), ((-3, 1.5, 1.6), 2.2),
                                       ((0.4, 2.5, 3.0), 2.6)]):
        light = bpy.data.lights.new("L%d" % i, "SUN")
        light.energy = energy
        obj = bpy.data.objects.new("L%d" % i, light)
        obj.location = centre + Vector(loc).normalized() * radius * 4
        obj.rotation_euler = (centre - obj.location).to_track_quat("-Z", "Y").to_euler()
        common.link(obj)


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--type", required=True)
    p.add_argument("--file", default="")
    p.add_argument("--clips", default="")
    p.add_argument("--frames", type=int, default=6)
    p.add_argument("--view", default="front34")
    p.add_argument("--size", default="560")
    p.add_argument("--prefix", default="")
    args = p.parse_args(argv)
    out = os.path.join(mon_lib.TMP, "render")
    os.makedirs(out, exist_ok=True)
    common.reset()
    path = args.file or os.path.join(mon_lib.OUT_DIR, args.type, "%s.glb" % args.type)
    bpy.ops.import_scene.gltf(filepath=path)
    for obj in list(bpy.data.objects):
        # the Blender 5 glTF importer leaves an untextured helper sphere behind
        if obj.type == "MESH" and not obj.data.materials:
            bpy.data.objects.remove(obj, do_unlink=True)
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.data.materials]
    los, his = zip(*(mon_lib.mesh_bounds(o) for o in meshes))
    lo = Vector((min(v.x for v in los), min(v.y for v in los), min(v.z for v in los)))
    hi = Vector((max(v.x for v in his), max(v.y for v in his), max(v.z for v in his)))
    print("BOUNDS %-11s x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f  (h %.2f)"
          % (args.type, lo.x, hi.x, lo.y, hi.y, lo.z, hi.z, hi.z - lo.z))
    centre = (lo + hi) * 0.5
    radius = max((hi - lo).length * 0.6, 0.2)
    scene_lights(centre, radius)
    cam_data = bpy.data.cameras.new("C")
    cam_data.lens = 80
    cam = bpy.data.objects.new("C", cam_data)
    common.link(cam)
    cam.location = centre + VIEWS[args.view].normalized() * radius * 3.4
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene = bpy.context.scene
    scene.camera = cam
    px = int(args.size)
    scene.render.resolution_x = px
    scene.render.resolution_y = px
    scene.render.image_settings.file_format = "PNG"
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    clips = [c for c in args.clips.split(",") if c] or sorted(a.name for a in bpy.data.actions)
    prefix = args.prefix or args.type
    for clip_id in clips:
        action = bpy.data.actions.get(clip_id)
        if action is None or arm is None:
            print("RENDER skip %s" % clip_id)
            continue
        arm.animation_data_create().action = action
        if hasattr(action, "slots") and len(action.slots):
            arm.animation_data.action_slot = action.slots[0]
        start, end = action.frame_range
        for i in range(args.frames):
            t = start + (end - start) * (i / max(args.frames - 1, 1))
            scene.frame_set(int(round(t)))
            scene.render.filepath = os.path.join(out, "%s_%s_%d.png" % (prefix, clip_id, i))
            bpy.ops.render.render(write_still=True)
        print("RENDER %s %s %.2fs" % (args.type, clip_id,
                                          (end - start) / float(bpy.context.scene.render.fps)))


main()
