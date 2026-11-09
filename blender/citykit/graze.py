"""The grazing-light gate for the planar pass (lead r4 MUST-FIX 1).

    tools/blender.sh run blender/citykit/graze.py -- --ids t01,b01,o01,s04,k02,k06

The lead's test: a lit studio render at a GRAZING key (sun 6-20 degrees elevation, raking along the
wall) with a FLAT GREY material. No texture, no windows, no normal map. A wall that is really one
plane must read as one flat value; if the render still shows bright curved bands, the surface is
still a wobbly height field and the ORM was never the cause.

Each sheet is the same model twice in one frame under one light: LEFT is the r3 export (custom
normals cleared, smooth-by-angle 40, no planar pass, no weighted normals), RIGHT is the r5 export
(collapse, planar passes, smooth-by-angle 30 + area-weighted normals). Same camera, same sun, so any
difference in banding is the geometry.

`--lod` renders the model's own `_lod.glb` on the right instead, because that is the mesh the cover
pieces are placed from (lead r4 MUST-FIX 2) and a gate that only measures the detail mesh measures
something the player never stands next to.

Output: captures/kit/graze_<id>.png (or graze_<id>_lod.png) and captures/kit/_graze.jpg.
"""
from __future__ import annotations

import math
import os
import sys
from typing import List, Tuple

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/citykit"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/tools/citykit"))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import clean  # noqa: E402
import planar  # noqa: E402
import process  # noqa: E402
import tripo_import  # noqa: E402
from assets import BY_ID  # noqa: E402
from lib import common  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")
SRC = os.path.join(ROOT, "art", "tripo")
OUT = os.path.join(ROOT, "captures", "kit")
SIZE = 900
#: Sun elevation and azimuth. 12 degrees is inside the lead's 6-20 band; 78 degrees of azimuth puts
#: the light almost parallel to a wall that faces -Y, which is what makes a 10 cm wobble visible.
SUN_EL, SUN_AZ = 12.0, 78.0
#: The gate's flat grey: 0.30 linear, roughness 0.6 — the lead's "flat grey albedo + no windows" row.
GREY, ROUGH = 0.30, 0.60


def args() -> Tuple[List[str], bool]:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ids, lod = "t01,b01,o01,s04,k02,k06", False
    for i, a in enumerate(argv):
        if a == "--ids" and i + 1 < len(argv):
            ids = argv[i + 1]
        elif a.startswith("--ids="):
            ids = a.split("=", 1)[1]
        elif a == "--lod":
            lod = True
    return ids.split(","), lod


def shade_r3(obj: bpy.types.Object) -> None:
    """The r3 export's shading, for the A side: cleared custom normals, smooth 40, no weighted pass."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    if getattr(obj.data, "has_custom_normals", False):
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    common.smooth(obj, angle_deg=40.0)


def shade_r5(obj: bpy.types.Object, a) -> dict:
    """The r5 export's shading, for the B side — the same order `process.py` uses, so the gate
    measures the shipped pipeline and not a variant of it."""
    process.decimate(obj, a.tris)
    stats: dict = {}
    for _ in range(process.FLATTEN_PASSES):
        stats = planar.flatten(obj)
    process.fit_native(obj, a.native_h)
    tripo_import.shade(obj)
    return stats


def build(aid: str, lod: bool = False) -> Tuple[bpy.types.Object, bpy.types.Object, dict]:
    """Import the RAW Tripo model once and derive both variants from the same pre-shading mesh.

    With `lod`, both sides are collapsed to the model's LOD budget instead of its detail budget, and
    the difference between them is exactly MUST-FIX 2: the left shades BEFORE the collapse (so it
    ships the collapse's averaged normals, which is what r4 shipped) and the right shades after it.
    """
    a = BY_ID[aid]
    common.reset()
    tripo_import.import_glb(os.path.join(SRC, "kit_" + aid, "model.glb"))
    process.drop_bone_shapes()
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    obj = common.join(meshes, aid) if len(meshes) > 1 else meshes[0]
    obj.name = aid
    process.fix_up(obj, a)
    process.fit_native(obj, a.native_h)
    process.decimate(obj, a.tris * 3)
    obj, _, _ = clean.clean(obj, common.join)
    process.fit_native(obj, a.native_h)

    right = obj.copy()
    right.data = obj.data.copy()
    right.name = aid + "_r5"
    bpy.context.scene.collection.objects.link(right)
    if lod:
        # Left: r4's order — detail budget, shade, then collapse to the LOD budget.
        process.decimate(obj, a.tris)
        process.fit_native(obj, a.native_h)
        tripo_import.shade(obj)
        process.decimate(obj, a.lod_tris)
        obj.name = aid + "_r4lod"
        # Right: r5's order — collapse first, planar passes, then shade.
        process.decimate(right, a.tris)
        stats: dict = {}
        for _ in range(process.FLATTEN_PASSES):
            stats = planar.flatten(right)
        process.fit_native(right, a.native_h)
        process.decimate(right, a.lod_tris)
        tripo_import.shade(right)
        return obj, right, stats
    process.decimate(obj, a.tris)
    process.fit_native(obj, a.native_h)
    shade_r3(obj)
    obj.name = aid + "_r3"
    stats = shade_r5(right, a)
    return obj, right, stats


def grey_material() -> bpy.types.Material:
    mat = bpy.data.materials.new("graze_grey")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (GREY, GREY, GREY, 1.0)
    bsdf.inputs["Roughness"].default_value = ROUGH
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def setup(scene, centre: Vector, radius: float) -> None:
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = eng
            break
        except TypeError:
            continue
    scene.render.resolution_x = scene.render.resolution_y = SIZE
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("graze") if scene.world is None else scene.world
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.05, 0.055, 0.065, 1.0)
    bg.inputs[1].default_value = 1.0
    sun = bpy.data.lights.new("key", "SUN")
    sun.energy, sun.angle = 6.0, math.radians(1.5)
    ob = bpy.data.objects.new("key", sun)
    scene.collection.objects.link(ob)
    el, az = math.radians(SUN_EL), math.radians(SUN_AZ)
    d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    ob.location = centre + d * radius * 6.0
    ob.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()


def camera(scene, centre: Vector, radius: float, az: float, el: float) -> None:
    cam = bpy.data.cameras.new("cam")
    cam.lens = 55.0
    ob = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(ob)
    dist = radius * 1.12 / 0.327
    a, e = math.radians(az), math.radians(el)
    ob.location = centre + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e),
                                   math.sin(e))) * dist
    ob.rotation_euler = (centre - ob.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = ob


def render(aid: str, lod: bool = False) -> str:
    left, right, stats = build(aid, lod)
    lo, hi = process.bounds(left)
    span = max(hi.x - lo.x, hi.y - lo.y, 1.0)
    gap = span * 1.35
    left.location.x -= gap * 0.5
    right.location.x += gap * 0.5
    bpy.context.view_layer.update()   # bounds() reads matrix_world, which is stale until this
    mat = grey_material()
    for ob in (left, right):
        ob.data.materials.clear()
        ob.data.materials.append(mat)
    lo2, hi2 = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for ob in (left, right):
        a, b = process.bounds(ob)
        lo2 = Vector(map(min, lo2, a))
        hi2 = Vector(map(max, hi2, b))
    centre, radius = (lo2 + hi2) * 0.5, max((hi2 - lo2).length * 0.5, 0.1)
    scene = bpy.context.scene
    setup(scene, centre, radius)
    camera(scene, centre, radius, 0.0, 8.0)
    os.makedirs(OUT, exist_ok=True)
    png = os.path.join(OUT, "graze_%s%s.png" % (aid, "_lod" if lod else ""))
    scene.render.filepath = png
    bpy.ops.render.render(write_still=True)
    print("GRAZE %-4s%s planar %.1f%% over %d planes  tris left=%d right=%d  -> %s"
          % (aid, " LOD" if lod else "", stats.get("planar_pct", 0.0), stats.get("regions", 0),
             common.tri_count(left), common.tri_count(right), png))
    return png


def main() -> None:
    ids, lod = args()
    for aid in ids:
        if not os.path.exists(os.path.join(SRC, "kit_" + aid, "model.glb")):
            print("GRAZE SKIP %s (no raw model)" % aid)
            continue
        if lod and not BY_ID[aid].lod_tris:
            print("GRAZE SKIP %s (no LOD budget)" % aid)
            continue
        render(aid, lod)


if __name__ == "__main__":
    main()
