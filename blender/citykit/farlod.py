"""Far-band LOD for every kit model (r2 item 2): the same buildings past 450 m, not a box proxy.

  tools/blender.sh run blender/citykit/farlod.py -- --id t01
  tools/blender.sh run blender/citykit/farlod.py -- --all

Reads the PROCESSED glb (game/world/kit/<id>/<id>.glb — already metric, pivoted at the footprint
base, one material), planar-dissolves it, collapses it to the far budget, drops its textures to a
256 px atlas and writes <id>/<id>_far.glb. The placer shows it from 450 m (where the detail batch
ends) to 1 600 m, so the skyline is the same buildings at distance instead of city-build's box proxy.

Why a decimated mesh and not an impostor: an octahedral impostor needs eight renders per model in a
hemi-octahedral atlas plus a custom shader, and at 450-1 600 m a 4 k-triangle silhouette of the real
building is already under a pixel of geometric error. The brief allows either.
"""
from __future__ import annotations

import json
import math
import os
import sys
from typing import List

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/citykit"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/tools/citykit"))

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import clean  # noqa: E402
import process  # noqa: E402
import tripo_import  # noqa: E402
from lib import common, export  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")
OUT = os.path.join(ROOT, "game", "world", "kit")
# The brief's 1 500-tri budget was measured as the wrong number for THIS geometry: a 200 m tower
# collapsed 27:1 comes out as long thin spikes, and at 450-600 m (where the swap happens) those read
# as speckle, not as a building (tmp/city-kit/kit2far.jpg, first pass). 4 000 tris is 2.7x the budget
# and still 1/10th of the detail mesh; a 358-building skyline is then ~1.4 M triangles in the far band.
FAR_TRIS = 4000
FAR_TEX = 256        # brief: 256 px atlas
DISSOLVE_DEG = 4.0    # planar pass: faces within this angle of each other become one panel


def args() -> dict:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    out, pending = {}, None
    for a in argv:
        if a.startswith("--"):
            if pending:
                out[pending] = "true"
            k, _, v = a[2:].partition("=")
            out[k], pending = (v, None) if v else (None, k)
        elif pending:
            out[pending], pending = a, None
    if pending:
        out[pending] = "true"
    return out


def dissolve(obj: bpy.types.Object, angle_deg: float) -> int:
    """Planar pass before the collapse: turn a facade's thousands of near-coplanar triangles back into
    flat panels. Collapsing a surface reconstruction straight to 4 k tris gives slivers that read as
    static; dissolving first gives the collapse actual planes to work with."""
    mod = obj.modifiers.new("far_dissolve", "DECIMATE")
    mod.decimate_type = "DISSOLVE"
    mod.angle_limit = math.radians(angle_deg)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return common.tri_count(obj)


def decimate(obj: bpy.types.Object, budget: int, passes: int = 3) -> int:
    """Collapse to `budget`, iterating.

    Blender's ratio is a target, not a guarantee: on a welded mesh with many small features one pass
    can land 3x over it (measured: f01 asked for 4 000 and stopped at 12 700). Re-applying with the
    remaining ratio converges — the second pass has already lost the detail the first one protected.
    """
    for _ in range(passes):
        tris = common.tri_count(obj)
        if tris <= budget * 1.05:
            return tris
        mod = obj.modifiers.new("far_decimate", "DECIMATE")
        mod.ratio = min(1.0, budget / float(tris))
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
        if common.tri_count(obj) >= tris:
            break       # the collapse cannot go further; more passes only cost time
    return common.tri_count(obj)


def fill_holes(obj: bpy.types.Object, max_sides: int = 24) -> int:
    """Close the far mesh's boundary holes, so the silhouette is solid by construction.

    Cheaper than the voxel remesh the lead offered for a model that still tears, and it needs no
    re-bake: the fill inherits the surrounding faces' UVs, which at 450-1600 m is invisible. It is
    also what turns l01 (a 6.5:1 slab whose balcony bands read as 7.8 % daylight) from a gate failure
    into a usable far mesh. Returns the number of holes closed.
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    edges = [e for e in bm.edges if len(e.link_faces) < 2]
    before = len(edges)
    if edges:
        bmesh.ops.holes_fill(bm, edges=edges, sides=max_sides)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    after = tripo_import.holes(obj)
    return before - after


def shrink(tex: int) -> int:
    n = 0
    for img in bpy.data.images:
        if img.size[0] <= 0 or img.size[0] <= tex:
            continue
        img.scale(tex, tex)
        n += 1
    return n


def rebase(obj: bpy.types.Object, lo, hi) -> float:
    """Scale and move the collapsed mesh so its box matches the detail mesh's. Returns the move, metres.

    A 4 000-triangle collapse does not keep the extreme vertices: measured on l03 the far tier came out
    spanning y -2.76..+38.35 against the detail's 0.00..+40.00, so at the 450 m swap the silhouette
    jumped 2.8 m down and shrank 4 %. `tools/citykit/rebase_glb.py --check` compares the tiers and
    failed on it.

    The correction is a uniform scale about the base plus a translation, both measured on the mesh as
    it stands: at that range the far tier is a mass, not a shape, and matching its bounds exactly is
    worth more than preserving the collapse's own proportions.
    """
    cur_lo, cur_hi = process.bounds(obj)
    h_now = max(cur_hi.z - cur_lo.z, 1e-5)
    h_want = max(hi.z - lo.z, 1e-5)
    s = h_want / h_now
    obj.data.transform(Matrix.Diagonal((s, s, s, 1.0)))
    cur_lo, cur_hi = process.bounds(obj)
    d = Vector((0.5 * (lo.x + hi.x) - 0.5 * (cur_lo.x + cur_hi.x),
                0.5 * (lo.y + hi.y) - 0.5 * (cur_lo.y + cur_hi.y),
                lo.z - cur_lo.z))
    obj.data.transform(Matrix.Translation(d))
    obj.data.update()
    return round(d.length, 3)


def far(aid: str, budget: int = 0) -> dict:
    src = os.path.join(OUT, aid, aid + ".glb")
    if not os.path.exists(src):
        print("FAR SKIP %s (no processed glb)" % aid)
        return {}
    common.reset()
    tripo_import.import_glb(src)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        print("FAR FAIL %s (no meshes)" % aid)
        return {}
    obj = common.join(meshes, aid + "_far") if len(meshes) > 1 else meshes[0]
    obj.name = aid + "_far"
    common.apply_transforms(obj)
    # The far tier is swapped in by a visibility range on the SAME placement, so its silhouette has to
    # stand where the detail mesh stands. Record the detail's own box now, before the collapse.
    src_lo, src_hi = process.bounds(obj)
    tripo_import.check_welded(aid, obj)
    open_before = tripo_import.holes(obj)
    # Planar dissolve, then one collapse, then the floater sweep. Collapsing a Tripo surface
    # reconstruction straight to 4 k tris gives slivers that at 500 m read as static; dissolving the
    # near-coplanar facade back into panels first gives the collapse actual planes to work with.
    dissolved = dissolve(obj, DISSOLVE_DEG)
    tris = decimate(obj, budget or far_budget(aid))
    obj, _kept, _dropped = clean.clean(obj, common.join)
    # The silhouette gate (lead r2 item 2): a collapse that lost its weld grows open boundaries here.
    # `tools/citykit/far_gate.py` turns this into the render-side hole count and the rows that ship.
    filled = fill_holes(obj)
    open_after = tripo_import.holes(obj)
    rebased = rebase(obj, src_lo, src_hi)
    # Flat shading on a collapsed mesh turns every sliver into a hard black facet; smoothing by angle
    # costs nothing at this size and is what stops the far band reading as static.
    tripo_import.shade(obj, angle_deg=40.0)
    shrunk = shrink(FAR_TEX)
    out = export.export_glb(os.path.join(OUT, aid, aid + "_far.glb"), objects=[obj],
                            jpeg_quality=68)
    rec = {"glb": "%s/%s_far.glb" % (aid, aid), "tris": tris,
           "tex": FAR_TEX, "file_kb": int(os.path.getsize(out) / 1024),
           "open_before": open_before, "open_after": open_after, "holes_filled": filled,
           "tear": round(open_after / max(open_before, 1), 3)}
    path = os.path.join(OUT, aid, "row.json")
    try:
        with open(path) as fh:
            row = json.load(fh)
    except (OSError, ValueError) as exc:
        print("FAR WARN %s row.json unreadable (%s); the index will not carry the far glb" % (aid, exc))
        return rec
    row["far"] = rec
    with open(path, "w") as fh:
        json.dump(row, fh, indent=1)
    print("FAR OK %-4s tris=%-5d (dissolved to %d) open %d->%d filled=%d tex=%d file=%dkB"
          % (aid, tris, dissolved, open_before, open_after, filled, FAR_TEX, rec["file_kb"]))
    return rec


def far_budget(aid: str) -> int:
    """Per-model far budget. Thin, skeletal models (a pipe rack, a 6.5:1 slab, a station canopy)
    lose their silhouette to the collapse long before a solid tower does — the gate measures it and
    these are the ones it failed, so they keep more triangles rather than shipping with daylight
    through them (lead r2 item 2, step 2)."""
    return FAR_TRIS_OVERRIDE.get(aid, FAR_TRIS)


#: Set from the silhouette gate (blender/citykit/fargate.py): id -> far triangle budget. Only the
#: models the gate actually failed belong here, and only while more triangles fix them — l01 and s02
#: fail for structural reasons (a 6.5:1 slab's balcony bands and a glass canopy on slender columns are
#: mostly air) and no budget makes them solid, so they are left to the gate instead.
FAR_TRIS_OVERRIDE: dict = {"f03": 14000}


def main() -> None:
    a = args()
    if a.get("all"):
        ids = sorted(d for d in os.listdir(OUT)
                     if os.path.isdir(os.path.join(OUT, d))
                     and os.path.exists(os.path.join(OUT, d, d + ".glb")))
    else:
        ids = (a.get("id") or "t01").split(",")
    override = a.get("tris")
    if override:
        FAR_TRIS_OVERRIDE.update({i: int(override) for i in ids})
    rows: List[dict] = [r for r in (far(i) for i in ids) if r]
    if rows:
        # The `far` row lives in each asset's row.json, and kit.json is derived from those; without
        # this the placer would never see the far glbs.
        import process
        process.save_index(rows)
    print("far: %d models" % len(rows))


if __name__ == "__main__":
    main()
