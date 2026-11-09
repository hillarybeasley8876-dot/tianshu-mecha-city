"""The lead's r6 MUST-FIX 1 gate, as a picture: the SHIPPED glb, its own textures, a grazing sun, 30 m.

    tools/blender.sh run blender/citykit/wallgate.py -- --ids t01,m01,o01,c03

`graze.py` renders a FLAT GREY model, which is the right test for "is this surface a plane" and the
wrong one for r6: the lead's complaint is that a near wall reads as a blank, faceted sheet, which is a
statement about the ALBEDO (no storeys, no panels) as much as about the normals (triangle wedges). So
this renders the exported glb exactly as the game loads it — same material, same textures — from
30 m at eye height, under a sun raking along the wall.

Two things are judged from each frame:

* **wedges** — neighbouring triangles of one flat wall shaded as visibly different light and dark
  patches. `tools/citykit/normalqa.py` measures the same thing numerically on the same file.
* **blank planes** — a large area with no storey bands, no mullions and no panel variation.

The camera looks at the face with the largest area that the sun rakes across, chosen from the mesh
itself, so the frame is the same wall every run and a model cannot be shown from its good side.
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

from lib import common  # noqa: E402
from assets import BY_ID  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")
KIT = os.path.join(ROOT, "game", "world", "kit")
OUT = os.path.join(ROOT, "captures", "kit")
SIZE = (1280, 960)
#: Sun elevation, in degrees. 11 is inside the lead's 6-20 grazing band.
SUN_EL = 11.0
#: How far the camera stands from the wall, in metres — the lead's play distance.
DIST = 30.0


def args() -> List[str]:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    for i, a in enumerate(argv):
        if a == "--ids" and i + 1 < len(argv):
            return argv[i + 1].split(",")
        if a.startswith("--ids="):
            return a.split("=", 1)[1].split(",")
    return ["t01", "m01", "o01", "c03"]


def pick_wall(obj) -> Tuple[Vector, Vector, float]:
    """(centre, normal, area) of the model's largest wall — one orientation bucket, not one face.

    Bucketing by quantised normal (the same rule `wallgroup` uses) rather than taking the single
    largest face matters: on a 40 000-triangle tower the biggest FACE is about 1 m^2, so a camera put
    30 m from it sees a postage stamp magnified across the whole frame and every judgement made from
    that frame is about the atlas's UV stretch, not about the wall.
    """
    buckets: dict = {}
    for poly in obj.data.polygons:
        if abs(poly.normal.z) > 0.30:
            continue
        n = poly.normal
        key = (round(n.x * 4), round(n.y * 4), round(n.z * 4))
        c, a, nn = buckets.get(key, (Vector((0, 0, 0)), 0.0, Vector((0, 0, 0))))
        buckets[key] = (c + poly.center * poly.area, a + poly.area, nn + n * poly.area)
    if not buckets:
        return Vector((0.0, 0.0, obj.dimensions.z * 0.5)), Vector((0.0, -1.0, 0.0)), 1.0
    centre, area, normal = max(buckets.values(), key=lambda v: v[1])
    return centre / area, normal.normalized(), area


def scene(obj, centre: Vector, normal: Vector, dist: float) -> None:
    """A camera `dist` from the wall looking square at it, and a sun raking along it."""
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 35.0
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = centre + normal * dist
    # A Blender camera looks down its own -Z; `to_track_quat` aims that axis at the wall.
    cam.rotation_euler = (-normal).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam

    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 3.4
    sun_data.angle = math.radians(1.5)
    sun_data.color = (1.0, 0.86, 0.72)
    sun = bpy.data.objects.new("sun", sun_data)
    bpy.context.scene.collection.objects.link(sun)
    # Rake: the sun travels mostly ALONG the wall (85 degrees off its normal) and 11 degrees up, which
    # is the geometry that turns a 2 degree normal error into a visible band.
    along = Vector((-normal.y, normal.x, 0.0))
    if along.length < 1e-6:
        along = Vector((1.0, 0.0, 0.0))
    along.normalize()
    d = (along * math.cos(math.radians(SUN_EL))
         + Vector((0.0, 0.0, 1.0)) * math.sin(math.radians(SUN_EL)) - normal * 0.12).normalized()
    sun.location = centre - d * 200.0
    sun.rotation_euler = d.to_track_quat("Z", "Y").to_euler()

    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.16, 0.19, 0.26, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.7
    bpy.context.scene.world = world


def albedo_pass(obj) -> None:
    """Replace the material with an UNLIT emission of its own base colour.

    A render of the albedo with no lighting at all: it separates "the texture is blank / too pale" from
    "the lighting is doing that", which is the whole argument of MUST-FIX 1's second half. Written next
    to the lit frame as `wall_<id>_alb.png`.
    """
    for mat in obj.data.materials:
        if mat is None or not mat.use_nodes:
            continue
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None)
        if bsdf is None or out is None or not bsdf.inputs["Base Color"].is_linked:
            continue
        tex = bsdf.inputs["Base Color"].links[0].from_node
        emit = nt.nodes.new("ShaderNodeEmission")
        emit.location = (bsdf.location.x, bsdf.location.y - 200)
        nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
        nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])


def render(aid: str) -> str:
    common.reset()
    path = os.path.join(KIT, aid, aid + ".glb")
    if not os.path.exists(path):
        print("GATE SKIP %s (no glb)" % aid)
        return ""
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    obj = meshes[0]
    centre, normal, area = pick_wall(obj)
    # Frame the whole wall: a square-ish patch of `area` m^2 needs about sqrt(area) * 1.1 of standoff
    # at 35 mm to fill the frame, and never less than the lead's 30 m play distance.
    dist = max(DIST, math.sqrt(max(area, 1.0)) * 1.1)
    scene(obj, centre, normal, dist)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = SIZE
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, "wall_%s.png" % aid)
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)
    albedo_pass(obj)
    sc.render.filepath = os.path.join(OUT, "wall_%s_alb.png" % aid)
    bpy.ops.render.render(write_still=True)
    print("GATE %-5s wall %.0f m2 at (%.1f, %.1f, %.1f) normal (%.2f, %.2f, %.2f) cam %.0f m -> %s"
          % (aid, area, centre.x, centre.y, centre.z, normal.x, normal.y, normal.z, dist, out))
    return out


def main() -> None:
    for aid in args():
        if aid in BY_ID:
            render(aid)
        else:
            print("GATE SKIP %s (not in the asset table)" % aid)


if __name__ == "__main__":
    main()
