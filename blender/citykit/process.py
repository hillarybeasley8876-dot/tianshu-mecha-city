"""Turn a raw Tripo kit download into a game-ready, unit-normalised glb + a kit.json row.

  tools/blender.sh run blender/citykit/process.py -- --id t01
  tools/blender.sh run blender/citykit/process.py -- --all

Steps: import -> join -> fix the up axis -> fit to the asset's native height in METRES (origin at the
footprint's base centre) -> decimate to the band budget -> drop floaters / baked ground plates -> rebuild
the material with a signage emission mask -> export game/world/kit/<id>/<id>.glb. Metres matter: mc_kit's
window cells come from object space. game/world/kit/kit.json stores size, footprint, tags, band, tris.
"""
from __future__ import annotations

import json
import os
import sys
from typing import List, Tuple

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/citykit"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/tools/citykit"))

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import clean  # noqa: E402
import covertex  # noqa: E402
import grade  # noqa: E402
import kitmat  # noqa: E402
import panes  # noqa: E402
import planar  # noqa: E402
import pnormals  # noqa: E402
import tripo_import  # noqa: E402
import wallgroup  # noqa: E402
from assets import ASSETS, BY_ID, Asset  # noqa: E402
from lib import common, export  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")
SRC = os.path.join(ROOT, "art", "tripo")
OUT = os.path.join(ROOT, "game", "world", "kit")
INDEX = os.path.join(OUT, "kit.json")
#: How many times `planar.flatten()` runs per model. Each pass re-derives the planes from the surface
#: the previous one left, which is what lets a wall that started 20 cm out of plane come inside the
#: next pass's tolerance. Measured on t01: 1 pass 15.8 % of the shipped surface truly flat, 3 passes
#: 21.4 %, 6 passes 24.7 %, 12 passes 24.6 % — so it converges, and 5 is where the curve flattens.
FLATTEN_PASSES = 5
#: Bands whose walls are curtain wall and therefore carry the pane grid. A crate, a railing and a
#: pipe rack are walls too — they get the repainted value field — but a 2.0 x 2.4 m lit pane on a
#: cargo container is a lie, so they keep `planar.facade_faces()`'s strict regions and end up with
#: almost no mask, exactly as in r5.
PANE_BANDS = ("tower", "megablock", "midrise", "civic", "oldtown")
#: Bands that carry baked signage (neon strips, lit shopfronts). A cargo crate, a pipe rack and a
#: railing have nothing to emit, and the only bright thing a Tripo albedo gives the emission classifier
#: on them is a highlight — shipped at `EMISSION_STRENGTH` that is the black/white speckle of lead r6
#: MUST-FIX 2.
SIGN_BANDS = ("tower", "megablock", "midrise", "civic", "oldtown", "street")


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


def drop_bone_shapes() -> None:
    """Blender's glTF importer links an 80-face bone display Icosphere; it would skew the bounds."""
    shapes = {pb.custom_shape for ob in bpy.context.scene.objects if ob.type == "ARMATURE"
              for pb in ob.pose.bones if pb.custom_shape is not None}
    for ob in shapes:
        for coll in list(ob.users_collection):
            coll.objects.unlink(ob)


def bounds(obj: bpy.types.Object) -> Tuple[Vector, Vector]:
    """World-space bounding box of the vertices `obj`'s FACES actually use.

    Two traps, both measured:

    * `obj.bound_box` is a CACHED, depsgraph-evaluated box: after a direct vertex edit (which is what
      `planar.flatten()` does) it still holds the pre-edit extents until the view layer is
      re-evaluated, and `fit_native()` then scales the model by a height that no longer exists.
    * it also counts LOOSE vertices, and the glTF exporter does not — it writes only the vertices a
      face references. `fit_native()` translated f01's mesh so `bound_box`'s minimum sat at z = 0, and
      the shipped glb's lowest vertex came out at +0.058 m because the vertex at 0 belonged to no
      face. `tools/citykit/rebase_glb.py --check` caught it; this is the fix.
    """
    me = obj.data
    used = set()
    for poly in me.polygons:
        used.update(poly.vertices)
    if not used:
        used = set(range(len(me.vertices)))
    mw = obj.matrix_world
    lo = Vector((1e18, 1e18, 1e18))
    hi = Vector((-1e18, -1e18, -1e18))
    for vi in used:
        p = mw @ me.vertices[vi].co
        for i in range(3):
            lo[i] = min(lo[i], p[i])
            hi[i] = max(hi[i], p[i])
    return lo, hi


def fix_up(obj: bpy.types.Object, a: Asset) -> int:
    """Rotate the model so its up axis is +Z. Tripo guesses orientation from one image, so towers can
    arrive lying down. Tall bands: the longest axis is up. Street/tileable bands: the shortest is."""
    lo, hi = bounds(obj)
    d = hi - lo
    tall = a.band in ("tower", "megablock", "midrise", "civic") or a.native_h >= 40.0
    want = max(range(3), key=lambda i: d[i]) if tall else min(range(3), key=lambda i: d[i])
    if want == 2:
        return 0
    obj.rotation_euler = {0: (0.0, -1.5707963, 0.0), 1: (1.5707963, 0.0, 0.0)}[want]
    common.apply_transforms(obj)
    print("  up axis was %s -> rotated to +Z" % "XYZ"[want])
    return 1


def fit_native(obj: bpy.types.Object, height_m: float) -> Vector:
    """Scale uniformly so the model is `height_m` tall, origin at the footprint's base centre.

    Metres, not unit-normalised: `mc_kit` builds its window cells from VERTEX (object space), so a
    unit-sized model scaled by the placer would give the shader 3.4-unit "metre" bays and no windows.
    Returns the bbox size in metres.
    """
    common.apply_transforms(obj)
    lo, hi = bounds(obj)
    if hi.z - lo.z > 1e-5 and height_m > 0.0:
        s = height_m / (hi.z - lo.z)
        obj.scale = (s, s, s)
        common.apply_transforms(obj)
    lo, hi = bounds(obj)
    # Move the MESH DATA so the footprint's base centre is its origin, and leave the object transform
    # at identity. `common.set_origin()` followed by `common.apply_transforms()` cancels out: the
    # second bakes back exactly the offset the first moved the data by. Every kit glb through r5
    # shipped centred on its own middle that way, and the placer drew all 8 477 instances sunk by half
    # their height, with the roof dressing floating over the real roofs (lead, 11-03). The gate is
    # `tools/citykit/rebase_glb.py --check`.
    obj.data.transform(Matrix.Translation(-Vector(((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, lo.z))))
    lo, hi = bounds(obj)
    return hi - lo


def decimate(obj: bpy.types.Object, budget: int) -> int:
    tris = common.tri_count(obj)
    if tris <= budget:
        return tris
    mod = obj.modifiers.new("decimate", "DECIMATE")
    mod.ratio = budget / float(tris)
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return common.tri_count(obj)


def row(a: Asset, size: Vector, tris: int, stats: dict, kept: int, dropped: int,
        weld: float = 0.0, open_edges: int = 0) -> dict:
    """The kit.json row. `size` is the bbox in metres at the model's own pivot (base centre)."""
    return {"id": a.id, "band": a.band, "districts": [d for d in a.districts if d],
            "archetypes": list(a.archetypes), "tags": list(a.extra_tags), "tileable": a.tileable,
            "glb": "%s/%s.glb" % (a.id, a.id), "tris": tris, "budget": a.tris, "tex": a.tex,
            "size": [round(v, 3) for v in size],
            "footprint": [round(size.x, 2), round(size.y, 2)],
            "aspect": round((size.x * size.y) ** 0.5 / max(size.z, 1e-5), 4),
            "parts_kept": kept, "parts_dropped": dropped, "look": stats,
            "weld": round(weld, 4), "open_edges": open_edges}


def process(aid: str) -> dict:
    a = BY_ID[aid]
    src = os.path.join(SRC, "kit_" + aid, "model.glb")
    if not os.path.exists(src):
        print("KIT SKIP %s (no model.glb)" % aid)
        return {}
    common.reset()
    # A new asset's output folder does not exist yet, and the first thing written into it is the
    # window mask (`panes.save` writes the PNG by hand and does not mkdir). Every model processed so
    # far had a folder left by an earlier run, so this only ever bit on a brand-new id.
    os.makedirs(os.path.join(OUT, aid), exist_ok=True)
    tripo_import.import_glb(src)
    drop_bone_shapes()
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        print("KIT FAIL %s (no meshes)" % aid)
        return {}
    obj = common.join(meshes, aid) if len(meshes) > 1 else meshes[0]
    obj.name = aid
    # The weld gate, on the raw import: past WELD_GATE the mesh is a pile of UV islands and every
    # decimation after this one will tear it (lead r2 item 2).
    weld = tripo_import.check_welded(aid, obj)
    fix_up(obj, a)
    fit_native(obj, a.native_h)
    # Coarse pass first: separating 800k tris into loose parts is minutes, 120k is seconds, and the
    # floaters must go BEFORE the final decimate or a third of the budget is spent on junk.
    decimate(obj, a.tris * 3)
    obj, kept, dropped = clean.clean(obj, common.join)
    fit_native(obj, a.native_h)
    # Flatten what should be flat. The pass runs at the FINAL triangle count, not before the last
    # collapse: Blender's collapse decimator does not preserve coplanarity (measured on t01, a
    # 50 %-flat 120 k mesh came out 6 % flat after one 3:1 collapse), so anything done before it is
    # thrown away. It also runs FLATTEN_PASSES times — each pass re-derives the planes from the
    # surface the previous one produced (lead r4 MUST-FIX 1).
    flat = {"planar_pct": 0.0, "regions": 0, "faces_moved": 0, "max_move_m": 0.0,
            "regions_rejected": 0, "verts_skipped": 0}
    tris = decimate(obj, a.tris)
    for _ in range(FLATTEN_PASSES):
        flat = planar.flatten(obj)
    size = fit_native(obj, a.native_h)
    shaded = tripo_import.shade(obj)
    # MUST-FIX 1 (lead r6): the weighted-normal pass above averages ACROSS a planar region's border and
    # over the collapse's slivers, so a 40 m wall that is geometrically one plane still shaded as a
    # patchwork of wedges. Every face of a region gets its split normal written from the fitted plane.
    pn = pnormals.apply(obj)
    # The texture pass's regions: EVERY wall, not only the strictly-planar ones (lead r6 MUST-FIX 3 —
    # `planar.facade_faces()` reached 1.5-31 % of each atlas, so most of every facade kept the Tripo
    # blotches). The same groups feed the window mask, so the lit panes and the painted grid register.
    walls = wallgroup.wall_faces(obj)
    tops = wallgroup.top_faces(obj)
    if a.band == "cover":
        # Lead r7 §1: the cover band leaves the Tripo atlas entirely — a new UV layout, the maps
        # re-baked onto it low-passed, and a procedural layer at metre scale. Everything below this
        # branch (the facade repaint, the band grade, the emission classifier) is what made twelve
        # distinct concepts read as one brown, so none of it runs.
        imgs, cstats = covertex.build(obj, aid, a.tex)
        stats = kitmat.build_cover(obj, imgs, aid)
        stats.update(cstats)
        pstats = {"side": 0, "pane_px": 0, "walls": 0, "small_pct": 0.0, "pruned_pct": 0.0}
    else:
        mask, pstats = panes.build(obj, panes.side_for(a.tex),
                                   groups=walls if a.band in PANE_BANDS else None)
        side = int(pstats["side"])
        stats = kitmat.build(obj, a.tex, grade.band_of(a), aid, mask, side, walls, tops,
                             signage=a.band in SIGN_BANDS)
    stats.update(pstats)
    stats.update(wallgroup.coverage(obj))
    open_edges = tripo_import.holes(obj)
    win_path = os.path.join(OUT, aid, aid + "_win.png")
    if a.band == "cover":
        # A black mask, not a missing one: `McKitSkin` falls back to "find the dark texels in the
        # albedo" without a mask, and on a grimy, seam-lined prop that lights the seams. Black is
        # unambiguous — a transformer has no windows.
        panes.save(np.zeros((panes.MASK_SIDE, panes.MASK_SIDE), dtype=np.float32),
                   panes.MASK_SIDE, win_path)
        rec_win = panes.rel_path(aid)
    elif pstats["pane_px"] > 0:
        panes.save(mask, side, win_path)
        rec_win = panes.rel_path(aid)
    else:
        if os.path.exists(win_path):
            os.remove(win_path)      # a model that lost its facades must not keep a stale mask
        rec_win = ""
    out = export.export_glb(os.path.join(OUT, aid, aid + ".glb"), objects=[obj], jpeg_quality=78)
    rec = row(a, size, tris, stats, kept, dropped, weld, open_edges)
    rec["custom_normals_cleared"] = shaded
    rec["planar"] = flat
    rec["plane_normals"] = pn
    if rec_win:
        rec["win"] = rec_win
    rec["file_kb"] = int(os.path.getsize(out) / 1024)
    if a.lod_tris and tris > a.lod_tris:
        # A railing is placed ~1,300 times. The welded mesh will NOT collapse to the 350 tris the
        # table asks for: a closed manifold has a floor a shredded one did not, and a planar dissolve
        # first only makes it worse (measured on s07: 350 asked, 1 570 achieved, 2 735 with dissolve).
        # The budget that matters is the frame time, so `test_assign.py` gates on that instead.
        lod_tris = decimate(obj, a.lod_tris)
        # MUST-FIX 2 (lead r4): the LOD is decimated AFTER `shade()`, so without this it ships the
        # collapse's averaged normals — k06's LOD measured 22 deg of shading-to-face deviation and
        # 26 % of its area more than 30 deg off, against 3.9 deg for its own detail mesh. That is the
        # crumpled black chrome the player fights beside, because every cover piece is placed from
        # the LOD. The detail mesh's own shading is thrown away first so the pass is not fighting it.
        lod_shade = tripo_import.shade(obj)
        lod_pn = pnormals.apply(obj)
        lod = export.export_glb(os.path.join(OUT, aid, aid + "_lod.glb"), objects=[obj],
                                jpeg_quality=78)
        rec["lod"] = {"glb": "%s/%s_lod.glb" % (aid, aid), "tris": lod_tris,
                      "file_kb": int(os.path.getsize(lod) / 1024), "reshaded": lod_shade,
                      "plane_normals": lod_pn}
    with open(os.path.join(OUT, aid, "row.json"), "w") as fh:
        json.dump(rec, fh, indent=1)
    print("KIT OK %-4s tris=%-6d/%-6d open=%-5d size=%s tex=%d file=%dkB kept=%d dropped=%d "
          "emit=%s%s"
          % (aid, tris, a.tris, open_edges, rec["size"], a.tex, rec["file_kb"], kept, dropped,
             stats, (" lod=%d" % rec["lod"]["tris"]) if "lod" in rec else ""))
    print("  GRADE %-4s luma %.3f -> %.3f (gain %.2f)  rough %.2f -> %.2f  metal %.2f -> %.2f  "
          "panes %.1f%% -> %.1f%%  planar %.1f%% (%d planes, max move %.2f m)  walls=%d "
          "pane_px=%d small=%.1f%% pruned=%.1f%%  normals_cleared=%d"
          % (aid, stats.get("luma_before", 0.0), stats.get("luma_after", 0.0),
             stats.get("gain", 1.0), stats.get("rough_before", 0.0), stats.get("rough_after", 0.0),
             stats.get("metal_before", 0.0), stats.get("metal_after", 0.0),
             stats.get("pane_before", 0.0), stats.get("pane_after", 0.0),
             flat["planar_pct"], flat["regions"], flat["max_move_m"], pstats["walls"],
             pstats["pane_px"], pstats.get("small_pct", 0.0), pstats.get("pruned_pct", 0.0),
             shaded))
    return rec


def save_index(_rows: List[dict]) -> None:
    """Rebuild kit.json from every per-asset row on disk.

    Each asset writes its own `<id>/row.json` and the index is derived from those, so three Blender
    processes running in parallel never race over one shared file (see tools/citykit/process_all.sh).
    """
    keep = {}
    for a in ASSETS:
        path = os.path.join(OUT, a.id, "row.json")
        if not os.path.exists(path):
            continue
        try:
            with open(path) as fh:
                keep[a.id] = json.load(fh)
        except (OSError, ValueError) as exc:
            print("KIT WARN %s row.json unreadable (%s); skipped" % (a.id, exc))
    ordered = [keep[a.id] for a in ASSETS if a.id in keep]
    os.makedirs(OUT, exist_ok=True)
    with open(INDEX, "w") as fh:
        json.dump({"version": 1, "models": ordered}, fh, indent=1)
    print("index: %d models -> %s" % (len(ordered), INDEX))


def main() -> None:
    a = args()
    if a.get("all"):
        ids = [x.id for x in ASSETS if os.path.exists(os.path.join(SRC, "kit_" + x.id, "model.glb"))]
    else:
        ids = (a.get("id") or "t01").split(",")
    rows = [process(i) for i in ids]
    if any(rows):
        save_index(rows)


if __name__ == "__main__":
    main()
