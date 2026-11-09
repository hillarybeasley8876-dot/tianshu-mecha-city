"""Write the plane normal onto every face of a wall region (lead r6 MUST-FIX 1).

`planar.flatten()` makes each wall ONE plane, so inside a region every face normal already IS the
plane normal — but the SHADING normal is a different thing. `tripo_import.shade()` finishes with a
weighted-normal modifier, and that averages across the region border: the last row of vertices on a
40 m wall takes its normal from the balcony next to it, and the wall's outer metre bends. Worse, the
wobble the flattening pass could not remove is still there, and smooth shading interpolates it — so a
wall that is flat to within 20 cm still renders as a patchwork of light and dark wedges, one per
triangle. That is what the lead photographed at T1fac and A4st.

So each wall's faces get their split normals written EXPLICITLY, from a plane fitted to that wall,
and the weighted-normal result is kept only for the surface that is genuinely curved. Inside a region
the shading term `dot(N, L)` is then constant — measured on t01, the worst lit region's spread went
from 354 % to 2.4 %.

**Why region growing and not `planar`'s accumulator.** The accumulator is the right tool for MOVING
vertices: it has to find planes that are already almost exact, because a plane that is 20 cm out
cannot be snapped to without dragging real features with it, and it caps the model at `MAX_PLANES`
planes for that reason. Deciding a NORMAL has neither constraint — nothing moves — so the region can
be grown from a seed face by connectivity, which covers 90 %+ of a facade where the accumulator's
strict fit gate and 90-plane cap covered 53 % (measured on t01: `plane_area_pct` 52.9, and the half it
missed is exactly the half the eye reads as wall). r5's note that region growing is the wrong shape of
solution is about the FLATTENING pass, where a vertex on the border of sixteen patches satisfies none
of them; here a face belongs to exactly one region and no vertex moves.

Order matters: this runs AFTER `tripo_import.shade()`, because `shade()` clears the custom split
normals it is about to replace and `normals_split_custom_set()` needs a starting value for the loops
this pass does not touch.
"""
from __future__ import annotations

import math
from typing import Dict, List, Tuple

import bmesh
import bpy
from mathutils import Vector

#: A face joins the region being grown when its normal is within this of the region's fitted plane.
#: Swept against `tools/citykit/normalqa.py` on b01 (a balcony tower, the worst case in the kit) and
#: t01: 20 deg leaves 68.9 % of b01's lit wall area inside the gate, 28 deg leaves 99.9 %, and 40 deg
#: starts merging real corners back together and costs t01 three points. 28 is the peak.
GROW_DEG = 28.0
#: ... and when every one of its vertices is within this many metres of that plane. Scaled by the
#: model's own size in `apply()` (`DEV_FRAC` of the longest axis, floor `GROW_DEV`) — 0.5 m on a 12 m
#: crate is a different statement from 0.5 m on a 200 m tower. Swept with `GROW_DEG`: 0.004 of the span
#: left b01 at 68.9 % of its lit wall area inside the gate, 0.010 took it to 92.6 % before the angle
#: was raised, and 0.018 changed nothing more.
GROW_DEV = 0.5
DEV_FRAC = 0.010
#: A grown region whose vertices sit further than this (RMS, as a fraction of `dev`) off its fitted
#: plane is a CURVE, not a wall: a dome or a tank. It keeps the smooth shading, because flattening it
#: would band it.
RMS_FRAC = 0.55
#: Regions smaller than this (m^2) are left alone — a 1 m^2 patch cannot show a wedge.
MIN_AREA = 1.5
#: How many times the region is re-grown against its own refitted plane. Two is enough for a wall
#: whose wobble is a few centimetres; the third is there for a battered one.
REFIT = 3


def _fit(verts: List[Vector]) -> Tuple[Vector, Vector, float]:
    """(centroid, unit normal, RMS deviation) of the least-squares plane through `verts`."""
    n = len(verts)
    c = Vector((0.0, 0.0, 0.0))
    for v in verts:
        c += v
    c /= n
    xx = xy = xz = yy = yz = zz = 0.0
    for v in verts:
        d = v - c
        xx += d.x * d.x
        xy += d.x * d.y
        xz += d.x * d.z
        yy += d.y * d.y
        yz += d.y * d.z
        zz += d.z * d.z
    spread = (xx / n, yy / n, zz / n)
    k = min(range(3), key=lambda i: spread[i])
    axis = Vector((1.0 if k == 0 else 0.0, 1.0 if k == 1 else 0.0, 1.0 if k == 2 else 0.0))
    nrm = _smallest_eigen((xx, xy, xz, yy, yz, zz), axis)
    rms = math.sqrt(sum((v - c).dot(nrm) ** 2 for v in verts) / n)
    return c, nrm, rms


def _smallest_eigen(m: Tuple[float, float, float, float, float, float], seed: Vector) -> Vector:
    """The eigenvector of the symmetric 3x3 `m` closest to `seed` (inverse power iteration).

    The same routine `planar.py` uses, kept here rather than imported so this module has no
    dependency on the pass it exists to correct.
    """
    xx, xy, xz, yy, yz, zz = m
    det = (xx * (yy * zz - yz * yz) - xy * (xy * zz - yz * xz) + xz * (xy * yz - yy * xz))
    if abs(det) < 1e-12:
        return seed.normalized()
    ixx = (yy * zz - yz * yz) / det
    ixy = (xz * yz - xy * zz) / det
    ixz = (xy * yz - xz * yy) / det
    iyy = (xx * zz - xz * xz) / det
    iyz = (xy * xz - xx * yz) / det
    izz = (xx * yy - xy * xy) / det
    v = seed.normalized()
    for _ in range(24):
        w = Vector((ixx * v.x + ixy * v.y + ixz * v.z,
                    ixy * v.x + iyy * v.y + iyz * v.z,
                    ixz * v.x + iyz * v.y + izz * v.z))
        if w.length < 1e-12:
            return v
        v = w.normalized()
    return v


def _grow(faces: List, seed_i: int, centre: Vector, nrm: Vector, taken: List[bool],
          cos_g: float, dev: float) -> List[int]:
    """Flood fill from `seed_i` over faces that lie on the plane (centre, nrm)."""
    out: List[int] = []
    stack = [seed_i]
    seen = {seed_i}
    while stack:
        i = stack.pop()
        f = faces[i]
        if f.normal.dot(nrm) < cos_g:
            continue
        if any(abs((v.co - centre).dot(nrm)) > dev for v in f.verts):
            continue
        out.append(i)
        for e in f.edges:
            for g in e.link_faces:
                gi = g.index
                if gi in seen or taken[gi]:
                    continue
                seen.add(gi)
                stack.append(gi)
    return out


def wall_normals(obj: bpy.types.Object, dev: float) -> Dict[int, Vector]:
    """{polygon index: plane normal} for every face that belongs to a grown wall region.

    Faces are seeded largest-first, so the big walls claim their faces before a speck on the same
    plane can start a competing region, and each region is re-grown `REFIT` times against its own
    refitted plane. A region whose plane fit is worse than `RMS_FRAC * dev` is a curve and is dropped
    whole, which is what keeps a dome or a fuel tank smooth.
    """
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    faces = list(bm.faces)
    if not faces:
        bm.free()
        return {}
    cos_g = math.cos(math.radians(GROW_DEG))
    order = sorted(range(len(faces)), key=lambda i: -faces[i].calc_area())
    taken = [False] * len(faces)
    out: Dict[int, Vector] = {}
    for seed_i in order:
        if taken[seed_i]:
            continue
        centre = faces[seed_i].calc_center_median().copy()
        nrm = faces[seed_i].normal.copy()
        region: List[int] = []
        for _ in range(REFIT):
            region = _grow(faces, seed_i, centre, nrm, taken, cos_g, dev)
            if not region:
                break
            pts = [v.co.copy() for i in region for v in faces[i].verts]
            centre, nrm, _rms = _fit(pts)
            if nrm.dot(faces[seed_i].normal) < 0.0:
                nrm = -nrm
        if not region:
            continue
        area = sum(faces[i].calc_area() for i in region)
        pts = [v.co.copy() for i in region for v in faces[i].verts]
        _c, _n, rms = _fit(pts)
        if area < MIN_AREA or rms > RMS_FRAC * dev:
            continue
        for i in region:
            taken[i] = True
            out[faces[i].index] = nrm
    bm.free()
    return out


def apply(obj: bpy.types.Object, dev: float = 0.0) -> Dict[str, float]:
    """Overwrite the split normals of every wall-region face with its plane normal, in place.

    Returns the stats the row reports: the share of surface AREA that ends up with an exact plane
    normal, and the share of FACES. The two differ a lot on a model whose big walls are a small
    fraction of its triangles, and the area number is the one the eye reads.
    """
    me = obj.data
    if len(me.polygons) == 0:
        return {"plane_area_pct": 0.0, "plane_face_pct": 0.0, "plane_regions": 0, "dev_m": 0.0}
    if dev <= 0.0:
        span = max(obj.dimensions)
        dev = max(GROW_DEV, DEV_FRAC * span)
    regions = wall_normals(obj, dev)
    if not regions:
        return {"plane_area_pct": 0.0, "plane_face_pct": 0.0, "plane_regions": 0, "dev_m": dev}

    # `mesh.corner_normals` is the READ side of the split normals in Blender 4.1+; it is what
    # `normals_split_custom_set()` would otherwise reset to the smooth-by-angle default.
    base = [Vector(cn.vector) for cn in me.corner_normals]
    total_area = sum(p.area for p in me.polygons)
    plane_area = 0.0
    for poly in me.polygons:
        n = regions.get(poly.index)
        if n is None:
            continue
        plane_area += poly.area
        for li in poly.loop_indices:
            base[li] = n
    me.normals_split_custom_set(base)
    me.update()
    return {"plane_area_pct": round(100.0 * plane_area / max(total_area, 1e-9), 2),
            "plane_face_pct": round(100.0 * len(regions) / max(len(me.polygons), 1), 2),
            "plane_regions": len({tuple(round(c, 4) for c in n) for n in regions.values()}),
            "dev_m": round(dev, 3)}
