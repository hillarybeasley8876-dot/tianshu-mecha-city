"""The kit lineup at true relative scale: every processed model in one orthographic frame.

  tools/blender.sh run blender/citykit/lineup.py

Each model is placed at its native metres (no per-asset framing), sorted tall to short, standing on
z = 0 with a gap between footprints. The point of the sheet is exactly what per-asset QA cannot show:
a 1.4 m guardrail next to a 210 m diagrid tower, and whether the whole set shares a scale language.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/citykit"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/tools/citykit"))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

from assets import ASSETS  # noqa: E402
import tripo_import  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")
KIT = os.path.join(ROOT, "game", "world", "kit")
OUT = os.path.join(ROOT, "captures", "kit", "_lineup")
GAP = 14.0
WIDTH, HEIGHT = 3000, 760


def bounds(objs) -> tuple:
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for ob in objs:
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    placed = []
    for a in ASSETS:
        glb = os.path.join(KIT, a.id, a.id + ".glb")
        if not os.path.exists(glb):
            continue
        before = set(bpy.data.objects)
        tripo_import.import_glb(glb)
        new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
        if new:
            placed.append((a.id, new))
    # Tall to short: the eye reads the scale ramp left to right.
    sizes = []
    for aid, objs in placed:
        lo, hi = bounds(objs)
        sizes.append((hi.z - lo.z, aid, objs, lo, hi))
    sizes.sort(key=lambda t: -t[0])

    x = 0.0
    for height, aid, objs, lo, hi in sizes:
        dx = -(lo.x + hi.x) * 0.5 - x
        for ob in objs:
            ob.location.x += dx
            ob.location.z -= lo.z
        x += (hi.x - lo.x) + GAP
        print("%-4s h=%7.1f  placed at x=%8.1f" % (aid, height, x))

    bpy.context.view_layer.update()   # bound_box is local; matrix_world is stale until the depsgraph runs
    lo, hi = bounds([o for _, _, objs, _, _ in sizes for o in objs])
    centre = (lo + hi) * 0.5
    scene = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = eng
            break
        except TypeError:
            continue
    scene.render.resolution_x, scene.render.resolution_y = WIDTH, HEIGHT
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("lineup")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.30, 0.31, 0.34, 1.0)

    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 3.2
    sun = bpy.data.objects.new("sun", sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (0.95, 0.15, -0.7)

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    span = max(hi.x - lo.x, 1.0)
    cam_data.ortho_scale = span * 1.04
    cam_data.clip_start = 1.0
    cam_data.clip_end = span * 3.0   # Blender's default 100 m clips a 1.8 km lineup to nothing
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (centre.x, lo.y - span * 0.9, centre.z)
    cam.rotation_euler = (1.5707963, 0.0, 0.0)
    scene.camera = cam
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    scene.render.filepath = OUT + ".png"
    bpy.ops.render.render(write_still=True)
    print("LINEUP %d models, span %.0f m -> %s.png" % (len(sizes), span, OUT))


if __name__ == "__main__":
    main()
