"""QA render for one processed kit asset: 4 lit angles + top, for the captures/kit/<id>.jpg sheet.

  tools/citykit/qa.sh t01            -> captures/kit/t01.jpg (+ prints mesh stats)

Deliberately neutral studio light: this gate judges MESH INTEGRITY (fused geometry, holes, floating
junk, baked-in ground, blurry textures), not the dusk look — that is judged in-engine later. Assets
are framed at their true relative scale by the separate lineup pass.
"""
from __future__ import annotations

import math
import os
import sys
from typing import List, Tuple

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/citykit"))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import tripo_import  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")
OUT = os.path.join(ROOT, "captures", "kit")
# name: (azimuth deg round the up axis from -Y, elevation deg, framing zoom)
VIEWS = {"a_front34": (35.0, 12.0, 1.0), "b_rear34": (145.0, 14.0, 1.0), "c_side": (90.0, 4.0, 1.0),
         "d_front": (0.0, 6.0, 1.0), "e_top": (0.0, 86.0, 1.6)}
SIZE = 700


def args() -> str:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    if not argv:
        raise SystemExit("qa.py needs an asset id")
    return argv[0]


def bounds() -> Tuple[Vector, Vector]:
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH":
            continue
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def area(name: str, loc: Vector, target: Vector, energy: float, size: float) -> None:
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.size = energy, size
    ob = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (target - loc).to_track_quat("-Z", "Y").to_euler()


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
    world = bpy.data.worlds.new("qa") if scene.world is None else scene.world
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.30, 0.31, 0.34, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    d = radius * 3.0
    area("key", centre + Vector((d, -d, d * 1.2)), centre, 4.0 * radius * radius, radius * 2.0)
    area("fill", centre + Vector((-d, -d * 0.4, d * 0.3)), centre, 1.2 * radius * radius, radius * 3.0)
    area("rim", centre + Vector((d * 0.3, d, d * 0.9)), centre, 2.0 * radius * radius, radius * 2.0)


def camera(scene, centre: Vector, radius: float, az: float, el: float, zoom: float) -> None:
    cam = bpy.data.cameras.new("cam")
    cam.lens = 55.0  # 36.2 deg horizontal on a 36 mm sensor -> half-angle tan 0.327
    ob = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(ob)
    # Frame the bounding sphere: half-height visible = dist * tan(half_fov), with a 15 % margin.
    dist = radius * 1.15 / (0.327 * max(zoom, 0.05))
    a, e = math.radians(az), math.radians(el)
    ob.location = centre + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist
    ob.rotation_euler = (centre - ob.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = ob


def stats() -> str:
    tris = mats = 0
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH":
            continue
        tris += sum(len(p.vertices) - 2 for p in ob.data.polygons)
        mats += len(ob.data.materials)
    tex = [(i.name, i.size[0]) for i in bpy.data.images if i.size[0] > 0 and not i.packed_file]
    return "tris=%d meshes=%d mats=%d textures=%s" % (
        tris, len([o for o in bpy.context.scene.objects if o.type == "MESH"]), mats, tex or "packed")


def flatten() -> None:
    """`QA_FLAT=1`: replace every material with one flat mid-grey.

    The lead's r8 probe used the same rung in-engine to separate a geometry artefact from a texture
    one. Here it answers the studio question the same way: if the dark creases across k07's tank are
    still there with no maps at all, they are the mesh, not the bake.
    """
    mat = bpy.data.materials.new("qa_flat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.55, 0.55, 0.56, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.6
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH":
            ob.data.materials.clear()
            ob.data.materials.append(mat)


def isolate(what: str) -> None:
    """`QA_ONLY=albedo|normal|shading`: strip maps so one layer is judged on its own.

    The lead's r8 probe used the same idea in-engine. Here it answers the studio question: k07's flat
    tank panels carry soft dark diagonal creases that a FLAT material does not have, so they are in
    the maps — this says which one.
    """
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            continue
        if what in ("albedo", "flat"):
            for node in [n for n in nt.nodes if n.type == "NORMAL_MAP"]:
                for out in node.outputs:
                    for link in list(out.links):
                        nt.links.remove(link)
            bsdf.inputs["Roughness"].default_value = 0.6
            bsdf.inputs["Metallic"].default_value = 0.0
        if what in ("normal", "flat"):
            for inp in ("Base Color",):
                for link in list(bsdf.inputs[inp].links):
                    nt.links.remove(link)
            bsdf.inputs["Base Color"].default_value = (0.55, 0.55, 0.56, 1.0)


def main() -> None:
    aid = args()
    glb = os.path.join(ROOT, "game", "world", "kit", aid, aid + ".glb")
    if not os.path.exists(glb):
        raise SystemExit("no processed glb for %s" % aid)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tripo_import.import_glb(glb)
    if os.environ.get("QA_FLAT"):
        flatten()
    if os.environ.get("QA_ONLY"):
        isolate(os.environ["QA_ONLY"])
    lo, hi = bounds()
    centre, radius = (lo + hi) * 0.5, max((hi - lo).length * 0.5, 0.1)
    scene = bpy.context.scene
    setup(scene, centre, radius)
    os.makedirs(OUT, exist_ok=True)
    for name, (az, el, zoom) in VIEWS.items():
        camera(scene, centre, radius, az, el, zoom)
        scene.render.filepath = os.path.join(OUT, "%s_%s.png" % (aid, name))
        bpy.ops.render.render(write_still=True)
    print("QA %s size=[%.2f %.2f %.2f] %s" % (aid, *(hi - lo), stats()))


if __name__ == "__main__":
    main()
