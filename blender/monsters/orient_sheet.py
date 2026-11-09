"""Render an orientation contact sheet for the monster inputs (monster-assets).

    tools/blender.sh run blender/monsters/orient_sheet.py

One row per input, two tiles: [-Y side] then [+X side], camera level with the body, Z up, a ground
plane at the lowest point. Tells us which way each raw Tripo mesh faces so the builders can yaw it to
+Y (= Godot -Z). Output: tmp/monster-assets/orient_<i>.png, tiled by hand afterwards.
"""
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")
OUT = os.path.join(ROOT, "tmp", "monster-assets")
# (type, file) in the order the tiles are written.
INPUTS = [
    ("spitter", "model.glb"), ("harrier", "model.glb"), ("hive", "model.glb"),
    ("juggernaut", "rigged.glb"), ("titan", "rigged.glb"), ("mantis", "rigged.glb"),
]
SIZE = 480


def look_at(cam, target: Vector) -> None:
    d = (cam.location - target)
    cam.rotation_euler = d.to_track_quat("Z", "Y").to_euler()


def shoot(path_out: str, side: str) -> None:
    scene = bpy.context.scene
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = path_out
    bpy.ops.render.render(write_still=True)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for i, (t, fname) in enumerate(INPUTS):
        common.reset()
        bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "art", "tripo", "mon_%s" % t, fname))
        for o in list(bpy.data.objects):
            if o.type == "MESH" and not o.data.materials:
                bpy.data.objects.remove(o, do_unlink=True)
        meshes = [o for o in bpy.data.objects if o.type == "MESH"]
        pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
        lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        c = (lo + hi) * 0.5
        r = max((hi - lo).length * 0.62, 0.1)
        world = bpy.data.worlds.new("W")
        world.use_nodes = True
        world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.06, 0.08, 1.0)
        world.node_tree.nodes["Background"].inputs[1].default_value = 1.2
        bpy.context.scene.world = world
        for li, loc in enumerate([(2, -3, 3), (-3, 1, 2), (0.5, 2, 1)]):
            ld = bpy.data.lights.new("L%d" % li, "SUN")
            ld.energy = 3.0
            ob = bpy.data.objects.new("L%d" % li, ld)
            ob.location = c + Vector(loc).normalized() * r * 4
            look_at(ob, c)
            common.link(ob)
        cam_data = bpy.data.cameras.new("C")
        cam_data.lens = 70
        cam = bpy.data.objects.new("C", cam_data)
        common.link(cam)
        bpy.context.scene.camera = cam
        for j, side in enumerate(["-Y", "+X"]):
            off = Vector((0, -1, 0.12)) if side == "-Y" else Vector((1, 0, 0.12))
            cam.location = c + off.normalized() * r * 3.2
            look_at(cam, c)
            shoot(os.path.join(OUT, "orient_%d_%s.png" % (i, side.replace("+", "p").replace("-", "m"))), side)
        print("ORIENT %s %s lo=%s hi=%s" % (t, fname, tuple(round(v, 2) for v in lo),
                                            tuple(round(v, 2) for v in hi)))


main()
