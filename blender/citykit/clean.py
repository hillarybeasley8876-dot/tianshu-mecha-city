"""Geometry cleanup for imported Tripo kit meshes: drop floaters and baked-in ground plates.

Tripo returns one fused body plus junk — pebbles, shadow-catcher plates, the odd floating panel. The QA
gate rejects both, so they are removed here rather than by hand. Rules are deliberately conservative
about thin-but-long parts (antennas, masts, railings) and aggressive about small isolated ones.
"""
from __future__ import annotations

from typing import List, Tuple

import bpy
from mathutils import Vector

# A part is kept if it carries a share of the model's surface area, or if it is long. Volume alone is
# a trap: Tripo returns facades as hundreds of thin wall shells whose bbox volume is a rounding error
# next to the roof slab, and an aggressive volume rule shreds them (see status Evidence: o02 r1).
AREA_KEEP = 0.995       # keep the parts carrying this share of the model's surface area ...
LONG_FRAC = 0.06        # ... and anything at least this long, which is what saves masts and railings
PLATE_HEIGHT_FRAC = 0.03  # a ground plate is this flat ...
PLATE_AREA_FRAC = 0.35   # ... and this wide, relative to the model
OUTSIDE_FRAC = 0.15      # centre this far outside the body's XY bbox (reported, not a rule)


def _bbox(obj: bpy.types.Object) -> Tuple[Vector, Vector]:
    pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def _parts(obj: bpy.types.Object) -> List[bpy.types.Object]:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")
    return [o for o in bpy.context.selected_objects if o.type == "MESH"]


def _vol(lo: Vector, hi: Vector) -> float:
    d = hi - lo
    return max(d.x, 1e-6) * max(d.y, 1e-6) * max(d.z, 1e-6)


def _area(obj: bpy.types.Object) -> float:
    return sum(p.area for p in obj.data.polygons)


def classify(parts: List[bpy.types.Object]) -> Tuple[List[bpy.types.Object], List[str]]:
    """Return (keep, dropped-reasons).

    Tripo returns a fused body plus hundreds of specks, and a fixed size threshold cannot serve both a
    tower (where the antenna is 0.01 % of the volume and must stay) and an old-town terrace (where the
    wall panels are). So parts are ranked by surface area and kept until AREA_KEEP of the model's area
    is covered; anything longer than LONG_FRAC of the model is kept regardless, which is what saves
    masts, railings and pipe runs.
    """
    boxes = [(p, *_bbox(p)) for p in parts]
    areas = {p.name: _area(p) for p in parts}
    total = sum(areas.values()) or 1.0
    main = max(boxes, key=lambda t: _vol(t[1], t[2]))
    lo = Vector((min(b[1].x for b in boxes), min(b[1].y for b in boxes), min(b[1].z for b in boxes)))
    hi = Vector((max(b[2].x for b in boxes), max(b[2].y for b in boxes), max(b[2].z for b in boxes)))
    size = hi - lo
    diag = size.length
    model_area = max(size.x, 1e-6) * max(size.y, 1e-6)
    mlo, mhi = main[1], main[2]

    ranked = sorted(boxes, key=lambda t: -areas[t[0].name])
    covered, area_keep = 0.0, set()
    for obj, _, _ in ranked:
        if covered >= AREA_KEEP * total:
            break
        area_keep.add(obj.name)
        covered += areas[obj.name]

    keep, why = [], []
    for obj, plo, phi in boxes:
        d = phi - plo
        centre = (plo + phi) * 0.5
        area2d = max(d.x, 1e-6) * max(d.y, 1e-6)
        flat = d.z <= PLATE_HEIGHT_FRAC * max(size.z, 1e-6)
        below_body = phi.z <= mlo.z + PLATE_HEIGHT_FRAC * max(size.z, 1e-6)
        if obj is not main[0] and flat and below_body and area2d >= PLATE_AREA_FRAC * model_area:
            why.append("%s:ground-plate" % obj.name)
            continue
        long_part = d.length >= LONG_FRAC * diag
        if obj.name in area_keep or long_part or obj is main[0]:
            keep.append(obj)
            continue
        outside = (abs(centre.x - (mlo.x + mhi.x) * 0.5) > (mhi.x - mlo.x) * (0.5 + OUTSIDE_FRAC)
                   or abs(centre.y - (mlo.y + mhi.y) * 0.5) > (mhi.y - mlo.y) * (0.5 + OUTSIDE_FRAC))
        why.append("%s:%s" % (obj.name, "outside" if outside else "speck"))
    return keep, why


def clean(obj: bpy.types.Object, join) -> Tuple[bpy.types.Object, int, int]:
    """Split `obj` into loose parts, delete junk, re-join. Returns (object, parts_kept, parts_dropped)."""
    name = obj.name  # captured before any removal: `obj` is itself one of the loose parts
    parts = _parts(obj)
    if len(parts) <= 1:
        return obj, 1, 0
    keep, why = classify(parts)
    if not keep or len(keep) == len(parts):
        return join(parts, name) if len(parts) > 1 else parts[0], len(keep), len(why)
    for p in parts:
        if p not in keep:
            bpy.data.objects.remove(p, do_unlink=True)
    merged = join(keep, name) if len(keep) > 1 else keep[0]
    for w in why:
        print("  drop %s" % w)
    return merged, len(keep), len(why)
