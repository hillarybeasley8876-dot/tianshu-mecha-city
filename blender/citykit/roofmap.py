"""A per-model roof map: where a kit model's real top surface is, on a 2 m grid (city-art r10 ask).

    tools/blender.sh run blender/citykit/roofmap.py -- --all

Both of the rooftop-dressing scatterers — city-art's greeble pass and city-build's `roof_machine`
slots — aim at the DESIGN box top, and a Tripo model only reaches that height over part of its
footprint: it has setbacks, a crown, a sloped roof. Everything aimed at the box top therefore floats
over the real roof, and city-art r10 drops 1 099 of its rooftop units (20 % of the roof dressing)
rather than ship them hanging in the air.

This measures the real thing off the DETAIL glb. On a `CELL_M` grid (or the finest grid that fits
`MAX_CELLS`, for a footprint too big for 2 m cells) over the model's footprint, in
MODEL space, it records for each cell:

* `h` — the height of the top surface, as 8 bits over the model's own height range;
* `flat` — whether that surface is flat enough to stand a machine on (its normal within
  `FLAT_DEG` of up).

Encoding, so a 60 x 60 map costs about 1 kB of JSON rather than 30 kB of numbers: two base64 strings,
one byte per cell, row-major from the footprint's minimum corner, `+x` fastest. A cell the model does
not cover at all is `h = 0` and `flat = 0`; a cell whose highest surface is a 5 m mast is recorded at
the mast's top with `flat = 0`, which is the honest answer — nothing can stand there.

`tools/citykit/test_roofmap.py` is the gate: it samples dressing points from the map, raycasts the
real mesh, and requires the map to be within 0.5 m.
"""
from __future__ import annotations

import base64
import json
import math
import os
import sys
from typing import Dict, List, Tuple

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/citykit"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/tools/citykit"))

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

from assets import ASSETS, BY_ID  # noqa: E402
from lib import common  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")
KIT = os.path.join(ROOT, "game", "world", "kit")
#: Grid pitch, in metres, for a model whose footprint fits it. 2 m is city-art's ask: fine enough
#: that a 6 m machine block lands on one value, coarse enough that a 60 m tower's map is 30 x 30 cells.
CELL_M = 2.0
#: A surface counts as flat if its normal is within this of straight up. 15 degrees is a shallow
#: pitched roof; anything steeper is somewhere a rooftop unit would slide off.
FLAT_DEG = 15.0
#: Cell budget for one map. r9: this used to be a hard SKIP, which left c01 — a 109 x 181 m civic hall
#: whose footprint is 5 005 cells at 2 m — with no roof map at all, and `world/art/tests/test_roof_map.gd`
#: failing on it. It is now a resolution budget: a footprint too big for 2 m cells gets the finest cell
#: that fits (c01 lands on 2.25 m, 49 x 81), so every building model has a map. The row carries the cell
#: it was built with, so a consumer never has to assume 2 m.
MAX_CELLS = 4096


def args() -> List[str]:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    for i, a in enumerate(argv):
        if a == "--all":
            return [x.id for x in ASSETS]
        if a == "--ids" and i + 1 < len(argv):
            return argv[i + 1].split(",")
        if a.startswith("--ids="):
            return a.split("=", 1)[1].split(",")
    return ["t01"]


def _cell_for(w: float, d: float) -> float:
    """The finest grid pitch whose map still fits `MAX_CELLS`.

    Starts from the area the budget allows (`sqrt(area / MAX_CELLS)`) and nudges upward until the
    integer cell counts actually fit — `ceil` on both axes means the area estimate is always a little
    optimistic. Never finer than `CELL_M`.
    """
    cell = max(CELL_M, math.sqrt(max(w * d, 1e-6) / MAX_CELLS))
    while math.ceil(w / cell) * math.ceil(d / cell) > MAX_CELLS:
        cell *= 1.05
    return cell


def _grid(obj) -> Tuple[int, int, float, Vector, Vector]:
    lo = Vector((1e18, 1e18, 1e18))
    hi = Vector((-1e18, -1e18, -1e18))
    for v in obj.data.vertices:
        for i in range(3):
            lo[i] = min(lo[i], v.co[i])
            hi[i] = max(hi[i], v.co[i])
    cell = _cell_for(hi.x - lo.x, hi.y - lo.y)
    nx = max(1, int(math.ceil((hi.x - lo.x) / cell)))
    ny = max(1, int(math.ceil((hi.y - lo.y) / cell)))
    return nx, ny, cell, lo, hi


def build(obj) -> Dict[str, object]:
    """Rasterise the top surface of `obj` into a height + flatness map. Model space, metres.

    Each cell is sampled at its own CENTRE, exactly as a scatterer will sample it: a face contributes
    to a cell only if the cell's centre is inside the face's XY projection, and the height recorded is
    the face's own plane at that point. Rasterising by bounding box instead — the obvious cheap
    version — put a face that merely passes near a cell into it, and the gate then measured 20-180 m
    of error on the towers: the map said "roof" where the raycast found a setback 40 m lower.
    """
    nx, ny, cell, lo, hi = _grid(obj)
    span = max(hi.z - lo.z, 1e-4)
    top = [-1e18] * (nx * ny)
    flat = [0.0] * (nx * ny)
    cos_f = math.cos(math.radians(FLAT_DEG))
    me = obj.data
    for poly in me.polygons:
        if poly.normal.z <= 1e-6:
            continue                      # a downward face is a soffit, not a roof
        co = [me.vertices[vi].co for vi in poly.vertices]
        xs = [c.x for c in co]
        ys = [c.y for c in co]
        x0 = min(nx - 1, max(0, int((min(xs) - lo.x) / cell)))
        x1 = min(nx - 1, max(0, int((max(xs) - lo.x) / cell)))
        y0 = min(ny - 1, max(0, int((min(ys) - lo.y) / cell)))
        y1 = min(ny - 1, max(0, int((max(ys) - lo.y) / cell)))
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(lo.x + (np.arange(x0, x1 + 1) + 0.5) * cell,
                             lo.y + (np.arange(y0, y1 + 1) + 0.5) * cell)
        # Fan-triangulate the polygon in XY and keep the cells whose centre falls in one of the fans.
        inside = np.zeros(gx.shape, dtype=bool)
        for k in range(1, len(co) - 1):
            inside |= _in_tri(gx, gy, co[0], co[k], co[k + 1])
        if not inside.any():
            continue
        # The face's own plane at each cell centre: z = z0 - (n.x*dx + n.y*dy) / n.z.
        n = poly.normal
        p0 = co[0]
        z = p0.z - (n.x * (gx - p0.x) + n.y * (gy - p0.y)) / max(n.z, 1e-6)
        up = 1 if n.z >= cos_f else 0
        for jy, ix in zip(*np.nonzero(inside)):
            c = (y0 + int(jy)) * nx + (x0 + int(ix))
            if z[jy, ix] > top[c]:
                top[c] = float(z[jy, ix])
                flat[c] = up
    hs = bytearray(nx * ny)
    fs = bytearray(nx * ny)
    for i, z in enumerate(top):
        if z < -1e17:
            continue
        hs[i] = min(255, max(0, int(round(255.0 * (z - lo.z) / span))))
        fs[i] = int(flat[i]) * 255
    return {"cell_m": round(cell, 4), "nx": nx, "ny": ny,
            "origin": [round(lo.x, 3), round(lo.y, 3)], "z0": round(lo.z, 3),
            "z_span": round(span, 3), "flat_deg": FLAT_DEG,
            "h": base64.b64encode(bytes(hs)).decode("ascii"),
            "flat": base64.b64encode(bytes(fs)).decode("ascii")}


def _in_tri(px, py, a, b, c) -> "np.ndarray":
    """Point-in-triangle in XY for arrays of points, with a small negative tolerance at the edges."""
    d = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
    if abs(d) < 1e-12:
        return np.zeros(px.shape, dtype=bool)
    l0 = ((b.y - c.y) * (px - c.x) + (c.x - b.x) * (py - c.y)) / d
    l1 = ((c.y - a.y) * (px - c.x) + (a.x - c.x) * (py - c.y)) / d
    return (l0 >= -1e-6) & (l1 >= -1e-6) & (1.0 - l0 - l1 >= -1e-6)


def main() -> None:
    for aid in args():
        if aid not in BY_ID:
            print("ROOF SKIP %s (not in the asset table)" % aid)
            continue
        path = os.path.join(KIT, aid, aid + ".glb")
        row_path = os.path.join(KIT, aid, "row.json")
        if not os.path.exists(path) or not os.path.exists(row_path):
            print("ROOF SKIP %s (no glb / row)" % aid)
            continue
        common.reset()
        bpy.ops.import_scene.gltf(filepath=path)
        meshes = [o for o in bpy.data.objects if o.type == "MESH"]
        if not meshes:
            print("ROOF SKIP %s (no mesh)" % aid)
            continue
        rec = build(meshes[0])
        with open(row_path) as fh:
            row = json.load(fh)
        if rec:
            row["roof"] = rec
        else:
            row.pop("roof", None)
        with open(row_path, "w") as fh:
            json.dump(row, fh, indent=1)
        print("ROOF %-5s %s" % (aid, "%dx%d cells @ %.2f m"
                                % (rec["nx"], rec["ny"], rec["cell_m"]) if rec else "no mesh"))
    # The roof map lives in each asset's row.json and `kit.json` is derived from those, so the index
    # has to be rebuilt here or the map never reaches the placer or city-art. r9 hit exactly that:
    # `test_roofmap.py` reads row.json and passed while `test_roof_map.gd` read kit.json and failed.
    import process  # noqa: E402  (Blender-side import, same as farlod.py)
    process.save_index([])


if __name__ == "__main__":
    main()
