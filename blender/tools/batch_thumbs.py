"""One 3/4 lit thumbnail per model (QA contact sheets).

    Blender -b --factory-startup --python blender/tools/batch_thumbs.py -- OUT_DIR SIZE MODEL.glb [MODEL.glb ...]
Writes OUT_DIR/<parent folder name>.png and prints "THUMB name tris dims".
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out_dir, size, models = argv[0], int(argv[1]), argv[2:]
os.makedirs(out_dir, exist_ok=True)
for path in models:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    scene = bpy.context.scene
    meshes = [o for o in scene.objects if o.type == "MESH"]
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    center, ext = (lo + hi) / 2, (hi - lo)
    radius = ext.length / 2
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    scene.camera = cam
    d = Vector((1.0, -1.0, 0.6)).normalized()
    cam.location = center + d * radius * 3.2
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    for i, (energy, rot) in enumerate(((3.0, (0.8, 0.2, 0.7)), (1.0, (1.1, 0.0, -2.3)))):
        light = bpy.data.objects.new("l%d" % i, bpy.data.lights.new("l%d" % i, "SUN"))
        light.data.energy = energy
        light.rotation_euler = rot
        scene.collection.objects.link(light)
    scene.world = bpy.data.worlds.new("w")
    scene.world.color = (0.35, 0.36, 0.38)
    scene.render.resolution_x = scene.render.resolution_y = size
    name = os.path.basename(os.path.dirname(path))
    scene.render.filepath = os.path.join(out_dir, name + ".png")
    bpy.ops.render.render(write_still=True)
    tris = sum(len(p.vertices) - 2 for o in meshes for p in o.data.polygons)
    print("THUMB %s tris=%d dims=%.3f,%.3f,%.3f" % (name, tris, ext.x, ext.y, ext.z))
