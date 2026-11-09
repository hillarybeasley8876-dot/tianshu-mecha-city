"""Silhouette gate for the far tier (lead r2 item 2, step 2): does the far mesh have holes?

  tools/blender.sh run blender/citykit/fargate.py -- --all

Renders each `<id>_far.glb` against a flat magenta world from four angles and counts the magenta
pixels that are ENCLOSED by the silhouette — a flood fill from the image border reaches the outside,
so anything magenta it cannot reach is daylight showing through the building. Writes
`far.gate = {"holes": <worst enclosed fraction>, "views": [...]}` into the asset's row.json.

Open-edge counting (farlod.py) already catches a torn weld, but it cannot see a hole that a clean
collapse opened in the middle of a face, and it says nothing about what the player actually sees.
This is the gate the rows are gated on.

The measurement is far-vs-DETAIL, not far-vs-zero: m04 is the megablock with a rail tunnel punched
through it and b01 has open balcony galleries, so "background enclosed by the silhouette" is a real
number for both. The gate is that the far mesh shows no MORE daylight than the building it stands
for — `holes <= max(GATE, detail * 1.5 + 0.005)`.
"""
from __future__ import annotations

import json
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
import tripo_import  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")
KIT = os.path.join(ROOT, "game", "world", "kit")
SIZE = 256
BG = (1.0, 0.0, 1.0)
#: The far mesh is 450-1600 m away and a few hundred pixels tall; above this fraction of enclosed
#: background the silhouette stops reading as a building.
GATE = 0.02
SCRATCH = os.path.join(ROOT, "tmp", "city-kit", "gate")
VIEWS = ((35.0, 12.0), (145.0, 14.0), (90.0, 4.0), (0.0, 6.0))


def enclosed_fraction(path: str) -> float:
    """Fraction of the frame that is background enclosed by the silhouette."""
    img = bpy.data.images.load(path)
    px = list(img.pixels)          # RGBA float, bottom-up
    w, h = img.size
    bg = [i for i in range(w * h)
          if px[i * 4] > 0.6 and px[i * 4 + 1] < 0.35 and px[i * 4 + 2] > 0.6]
    if not bg:
        bpy.data.images.remove(img)
        return 0.0
    outside = set()
    stack = []
    for i in bg:
        x, y = i % w, i // w
        if x in (0, w - 1) or y in (0, h - 1):
            stack.append(i)
            outside.add(i)
    bset = set(bg)
    while stack:
        i = stack.pop()
        x, y = i % w, i // w
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if not (0 <= nx < w and 0 <= ny < h):
                continue
            j = ny * w + nx
            if j in bset and j not in outside:
                outside.add(j)
                stack.append(j)
    bpy.data.images.remove(img)
    return (len(bg) - len(outside)) / float(w * h)


def flat_material() -> bpy.types.Material:
    """A flat mid-grey emission, so the silhouette test never depends on the model's own textures.

    The world is pure magenta AND lights the model, so a pale model rendered against it comes back
    magenta itself and the `g < 0.35` background test counts the BUILDING as sky. That is not
    hypothetical: the r3 palette grade darkened the kit and l01's measured holes fell from 7.8 % to
    0.35 % with no change to its geometry at all. Overriding the material takes the model's look out
    of the measurement, which is the only thing that makes far-vs-detail comparable.
    """
    mat = bpy.data.materials.new("gate_flat")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (0.35, 0.36, 0.38, 1.0)
    nt.links.new(em.outputs[0], out.inputs[0])
    return mat


def shoot(obj, azimuth: float, elevation: float, out: str) -> float:
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for c in obj.bound_box:
        p = obj.matrix_world @ Vector(c)
        lo = Vector((min(lo[i], p[i]) for i in range(3)))
        hi = Vector((max(hi[i], p[i]) for i in range(3)))
    r = max((hi - lo).length, 1.0)
    mid = (lo + hi) * 0.5
    cam_d = bpy.data.cameras.new("g")
    cam = bpy.data.objects.new("g", cam_d)
    bpy.context.scene.collection.objects.link(cam)
    a, e = azimuth * 0.0174533, elevation * 0.0174533
    cam.location = mid + Vector((r * 1.4 * math.sin(a) * math.cos(e),
                                 -r * 1.4 * math.cos(a) * math.cos(e),
                                 r * 1.4 * math.sin(e)))
    cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam_d.lens = 60.0
    obj.data.materials.clear()
    obj.data.materials.append(flat_material())
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = False
    sc.render.resolution_x = sc.render.resolution_y = SIZE
    sc.render.filepath = out
    sc.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    return enclosed_fraction(out + ".png" if not out.endswith(".png") else out)


def gate(aid: str) -> dict:
    src = os.path.join(KIT, aid, aid + "_far.glb")
    row_path = os.path.join(KIT, aid, "row.json")
    if not os.path.exists(src) or not os.path.exists(row_path):
        print("GATE SKIP %s" % aid)
        return {}
    os.makedirs(SCRATCH, exist_ok=True)
    common.reset()
    tripo_import.import_glb(src)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        print("GATE FAIL %s (no mesh)" % aid)
        return {}
    obj = meshes[0]
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (*BG, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    bpy.context.scene.world = world
    views = [round(shoot(obj, az, el, os.path.join(SCRATCH, "gate_%s_%d" % (aid, i))), 5)
             for i, (az, el) in enumerate(VIEWS)]
    worst = max(views)
    detail = detail_holes(aid)
    limit = max(GATE, detail * 1.5 + 0.005)
    with open(row_path) as fh:
        row = json.load(fh)
    row.setdefault("far", {})["gate"] = {"holes": worst, "views": views, "detail": detail,
                                         "limit": round(limit, 5), "pass": worst <= limit}
    with open(row_path, "w") as fh:
        json.dump(row, fh, indent=1)
    print("GATE %-4s holes=%.4f detail=%.4f limit=%.4f %s"
          % (aid, worst, detail, limit, "PASS" if worst <= limit else "FAIL"))
    return row["far"]["gate"]


def detail_holes(aid: str) -> float:
    """The same measurement on the detail mesh: what daylight the real building lets through."""
    src = os.path.join(KIT, aid, aid + ".glb")
    if not os.path.exists(src):
        return 0.0
    common.reset()
    tripo_import.import_glb(src)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        return 0.0
    world = bpy.data.worlds.new("wd")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (*BG, 1.0)
    bpy.context.scene.world = world
    return max(shoot(meshes[0], az, el, os.path.join(SCRATCH, "det_%s_%d" % (aid, i)))
               for i, (az, el) in enumerate(VIEWS))


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ids = sorted(d for d in os.listdir(KIT)
                 if os.path.isdir(os.path.join(KIT, d))
                 and os.path.exists(os.path.join(KIT, d, d + "_far.glb"))) \
        if "--all" in argv else [a for a in argv if not a.startswith("--")]
    bad: List[str] = []
    for aid in ids:
        got = gate(aid)
        if got and not got.get("pass", True):
            bad.append(aid)
    print("gate: %d models, %d over %.0f%%: %s" % (len(ids), len(bad), 100 * GATE,
                                                   ",".join(bad) or "none"))


main()
