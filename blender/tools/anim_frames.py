"""Render frames of one animation of a rigged GLB (headless EEVEE) for motion review.

    Blender -b --factory-startup --python blender/tools/anim_frames.py -- IN.glb OUT_DIR ANIM_SUBSTR t1,t2,... [--size 640] [--azimuth 35]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
src, out_dir, anim_sub, times = argv[0], argv[1], argv[2], [float(t) for t in argv[3].split(",")]
size = int(argv[argv.index("--size") + 1]) if "--size" in argv else 640
azimuth = float(argv[argv.index("--azimuth") + 1]) if "--azimuth" in argv else 35.0
os.makedirs(out_dir, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
scene = bpy.context.scene
arm = next(o for o in scene.objects if o.type == "ARMATURE")
action = next((a for a in bpy.data.actions if anim_sub.lower() in a.name.lower()), None)
if action is None:
    raise SystemExit("no action containing %r: %s" % (anim_sub, [a.name for a in bpy.data.actions]))
arm.animation_data_create()
arm.animation_data.action = action
fps = scene.render.fps
meshes = [o for o in scene.objects if o.type == "MESH"]
pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
center, extent = (lo + hi) / 2, max(hi - lo) * 1.6
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scene.collection.objects.link(cam)
scene.camera = cam
a = math.radians(azimuth - 90.0)
cam.location = center + Vector((math.cos(a), math.sin(a), 0.35)).normalized() * extent * 1.6
cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
for i, (kind, rot) in enumerate((("SUN", (0.9, 0.2, 0.6)), ("SUN", (1.2, -0.4, -2.4)))):
    light = bpy.data.objects.new("l%d" % i, bpy.data.lights.new("l%d" % i, kind))
    light.data.energy = 3.0 if i == 0 else 1.2
    light.rotation_euler = rot
    scene.collection.objects.link(light)
scene.world = bpy.data.worlds.new("w")
scene.world.color = (0.18, 0.19, 0.21)
scene.render.resolution_x = scene.render.resolution_y = size
for t in times:
    scene.frame_set(int(round(t * fps)) + int(action.frame_range[0]))
    scene.render.filepath = os.path.join(out_dir, "%s_%05.2f.png" % (anim_sub[:12].replace(" ", "_"), t))
    bpy.ops.render.render(write_still=True)
print("FRAMES", out_dir, action.name, action.frame_range[:])
