"""Flatten what should be flat: a planar pass over a Tripo surface reconstruction (lead r4 MUST-FIX 1).

A Tripo mesh is a photogrammetry-style surface reconstruction, so a wall that should be one plane
arrives as 4 000 facets each tilted a few degrees and offset a few centimetres. Smoothing by angle
(r3) turned those hard facets into soft ripples; at a 6-20 degree grazing sun every ripple becomes a
bright or dark band and a matte grey wall reads as wet chrome. Measured by the lead on a flat-grey,
no-window, no-normal-map render: the streaks were still there, so the ORM was never the cause.

The fix is geometric, and it has to happen at the FINAL triangle count:

  1. find the model's dominant planes with a Hough-style accumulator — direction bucket, then offset
     bucket inside each direction — and keep the ones that still fit a plane inside `FIT_M` RMS;
  2. assign every face to the plane it belongs to, if any, and drop the confetti (a plane keeps one
     connected blob, not a scatter of stripes);
  3. project every vertex onto the planes of the faces around it — by hand, because
     `bmesh.ops.planar_faces` flattens each face onto its OWN plane and a triangle is already planar,
     so on a triangulated mesh (which is what the decimator leaves) the op moves nothing at all
     (lead r4: 0 of t01's 40 000 triangles moved, and the shipped surface was 2.8 % flat before and
     after). A vertex shared by two planes goes to the least-squares point of both, which for a
     90 degree corner is the intersection line;
  4. report the share of surface area that was flattened, per model.

Two things that were tried and are the wrong shape of solution, both measured on t01:

* **Region growing** tiles the surface with hundreds of patches. Every vertex then sits on the border
  of two to sixteen of them (10 701 vertices across 1 087 patches, mean 4.5 each), the shared-vertex
  solve puts nearly every vertex somewhere that satisfies none of its planes, and the export plateaus
  at ~21 % flat however the tolerances are tuned. A wall has to become ONE plane with a large
  interior, which is what the accumulator gives.
* **Flattening before the last collapse** is wasted work: Blender's collapse decimator does not
  preserve coplanarity (a 50 %-flat 120 k mesh came out 6 % flat after one 3:1 collapse), so the pass
  runs on the final mesh, `FLATTEN_PASSES` times in `process.py`.

Normals then come out right for free: every face on a plane carries the same normal, so smooth
shading interpolates to exactly the plane normal and the grazing sun lights the wall as one value.
`tripo_import.shade()` finishes the job at the plane borders with a weighted-normal pass.

The gate is on the EXPORT, not on what this returns: `tools/citykit/meshqa.py` measures the share of
the shipped glb that is truly flat (every welded neighbour within 1 degree of the triangle's plane).
"""
from __future__ import annotations

import math
from typing import Dict, List, Tuple

import bmesh
import bpy
from mathutils import Vector

#: A face joins a plane when its own normal is within ASSIGN_DEG of the plane's and its centre within
#: ASSIGN_DEV of it. Much looser than the few degrees a finished wall shows, on purpose: the wobble
#: being removed is exactly what would otherwise keep a face off the wall it belongs to. Tuned on
#: t01 by sweeping both against the shipped flat share — 25 deg / 0.60 m is the peak (22 % of the
#: shipped surface truly flat at 40 k tris, against 2.8 % for the r3 and r4 exports).
ASSIGN_DEG = 25.0
ASSIGN_DEV = 0.60
#: Plane accumulator resolution: normals are bucketed on a grid of 1/DIR_Q, and the plane offsets
#: within one direction bucket on a grid of OFF_Q metres.
DIR_Q = 8.0
OFF_Q = 0.35
#: How many planes one model may keep. A tower is a few dozen real planes; the cap is what stops a
#: noisy model from turning every facet into its own plane (and every vertex into a border vertex).
MAX_PLANES = 90
#: A candidate plane whose least-squares fit is worse than this (RMS, metres) is a curve, not a
#: wobble, and is left alone.
FIT_M = 0.07
#: Planes smaller than this (m^2) are noise specks; flattening them costs time and buys nothing.
MIN_AREA = 0.8
#: A single vertex further than this from the fitted plane means the plane swallowed a real feature
#: (a balcony slab, a duct) rather than a wobble, so the candidate is rejected whole.
MAX_DEV = 0.25
#: A shared vertex whose least-squares landing point is further than this from where it started is
#: the same story one level up: two planes meet there at an angle that is not a corner of the
#: building. The vertex is left alone rather than dragged across the wall.
MAX_MOVE = 0.35
#: Two planes are the same wall when they agree this closely; the accumulator's direction buckets
#: overlap, so the same wall is normally found several times. Deliberately loose on the offset: a
#: wrong merge only flattens 25 cm of wobble, a missed one leaves the wall split in two.
MERGE_DEG = 5.0
MERGE_DEV = 0.25
#: A plane keeps a connected blob of its faces only if the blob is at least this fraction of the
#: plane's biggest blob. Without it a wall whose faces are split between two near-identical planes
#: comes out as interleaved stripes — measured on t01, a 1 400 m2 plane was only 37 % flat.
KEEP_FRAC = 0.30


def _plane_fit(points: List[Vector]) -> Tuple[Vector, Vector, float]:
    """Least-squares plane through `points`: (centroid, unit normal, RMS deviation)."""
    n = len(points)
    c = Vector((0.0, 0.0, 0.0))
    for p in points:
        c += p
    c /= n
    # Covariance of the centred points; the smallest eigenvector is the plane normal.
    xx = xy = xz = yy = yz = zz = 0.0
    for p in points:
        d = p - c
        xx += d.x * d.x
        xy += d.x * d.y
        xz += d.x * d.z
        yy += d.y * d.y
        yz += d.y * d.z
        zz += d.z * d.z
    # Inverse power iteration would need scipy; the normal is instead seeded from the axis-aligned
    # direction of least spread and refined on the real covariance below. This only has to be good
    # enough to gate a plane and to measure its deviation.
    spread = (xx / n, yy / n, zz / n)
    k = min(range(3), key=lambda i: spread[i])
    axis = Vector((1.0 if k == 0 else 0.0, 1.0 if k == 1 else 0.0, 1.0 if k == 2 else 0.0))
    nrm = _smallest_eigen((xx, xy, xz, yy, yz, zz), axis)
    rms = math.sqrt(sum((p - c).dot(nrm) ** 2 for p in points) / n)
    return c, nrm, rms


def _smallest_eigen(m: Tuple[float, float, float, float, float, float],
                    seed: Vector) -> Vector:
    """The eigenvector of the symmetric 3x3 `m` closest to `seed` (inverse power iteration).

    Written out rather than pulled from numpy/scipy because this runs inside Blender's Python and the
    matrix is 3x3: 24 iterations of `v <- M^-1 v` converge on the smallest eigenvector, and the
    3x3 inverse is a cofactor expansion.
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


def _fit(group: List) -> Tuple[Vector, Vector, float, float]:
    """(centroid, unit normal, RMS deviation, max deviation) of a face group's least-squares plane."""
    pts = [v.co.copy() for f in group for v in f.verts]
    centre, nrm, rms = _plane_fit(pts)
    return centre, nrm, rms, max(abs((p - centre).dot(nrm)) for p in pts)


def _project(p: Vector, planes: List[Tuple[Vector, Vector]]) -> Vector:
    """Move `p` onto every plane in `planes` at once, by the smallest displacement that does it.

    Minimising sum_i ((x - c_i).n_i)^2 is a least-squares problem whose normal equations are
    rank-deficient whenever the normals do not span 3-space — which is the common case, a vertex on
    the corner of two walls. Solving the raw 3x3 with a Tikhonov term blows the shared component up
    by 1/epsilon (measured: a 46 m move on a 30 m grid), so the system is solved in an orthonormal
    basis of the normals' own span instead: exact for the rank it has, and the leftover freedom is
    spent on the minimum displacement, which for a 90 degree corner is the intersection line.
    """
    basis: List[Vector] = []
    for _c, n in planes:
        v = n.copy()
        for u in basis:
            v -= u * v.dot(u)
        if v.length > 1e-6:
            basis.append(v.normalized())
    k = len(basis)
    if k == 1:
        u = basis[0]
        target = sum(c.dot(u) for c, _n in planes) / len(planes)
        return p + u * (target - p.dot(u))
    # a_ik = n_i . u_k ; solve (sum_i a_i a_i^T) y = sum_i a_i (n_i . c_i) for the target coordinates.
    a = [[n.dot(u) for u in basis] for _c, n in planes]
    m = [[sum(row[i] * row[j] for row in a) for j in range(k)] for i in range(k)]
    b = [sum(a[i][j] * planes[i][0].dot(planes[i][1]) for i in range(len(a))) for j in range(k)]
    y = _solve_small(m, b)
    if y is None:
        c, n = planes[0]
        return p - n * (p - c).dot(n)
    out = p.copy()
    for j in range(k):
        out += basis[j] * (y[j] - p.dot(basis[j]))
    return out


def _solve_small(m: List[List[float]], b: List[float]) -> List[float] | None:
    """Gaussian elimination with partial pivoting for a k x k system (k <= 3). None if singular."""
    k = len(b)
    a = [row[:] + [b[i]] for i, row in enumerate(m)]
    for col in range(k):
        piv = max(range(col, k), key=lambda r: abs(a[r][col]))
        if abs(a[piv][col]) < 1e-12:
            return None
        a[col], a[piv] = a[piv], a[col]
        for r in range(k):
            if r == col:
                continue
            f = a[r][col] / a[col][col]
            for c in range(col, k + 1):
                a[r][c] -= f * a[col][c]
    return [a[i][k] / a[i][i] for i in range(k)]


def _dominant(faces: List, min_area: float) -> List[Tuple[Vector, Vector, float]]:
    """The model's dominant planes: (centre, unit normal, area) for each, largest first.

    A Hough-style accumulator, not region growing — see the module docstring for why a tiling of
    small patches cannot work. Direction bucket first, then the plane offset inside each direction,
    and every surviving bucket is refitted properly before it is kept.
    """
    dirs: Dict[Tuple[int, int, int], List[int]] = {}
    for i, f in enumerate(faces):
        n = f.normal
        key = (int(round(n.x * DIR_Q)), int(round(n.y * DIR_Q)), int(round(n.z * DIR_Q)))
        dirs.setdefault(key, []).append(i)
    planes: List[Tuple[Vector, Vector, float]] = []
    for key, members in dirs.items():
        if sum(faces[i].calc_area() for i in members) < min_area * 2.0:
            continue
        n0 = Vector(key)
        if n0.length < 1e-6:
            continue
        n0.normalize()
        offs: Dict[int, List[int]] = {}
        for i in members:
            d = faces[i].calc_center_median().dot(n0)
            offs.setdefault(int(math.floor(d / OFF_Q)), []).append(i)
        for group_i in offs.values():
            group = [faces[i] for i in group_i]
            area = sum(f.calc_area() for f in group)
            if area < min_area:
                continue
            centre, nrm, rms, worst = _fit(group)
            if rms > FIT_M or worst > MAX_DEV:
                continue
            if nrm.dot(n0) < 0.0:
                nrm = -nrm
            planes.append((centre, nrm, area))
    planes.sort(key=lambda p: -p[2])
    return _dedupe(planes)[:MAX_PLANES]


def _dedupe(planes: List[Tuple[Vector, Vector, float]]) -> List[Tuple[Vector, Vector, float]]:
    """Drop a plane that another, larger one already covers (the direction buckets overlap)."""
    cos_d = math.cos(math.radians(MERGE_DEG))
    out: List[Tuple[Vector, Vector, float]] = []
    for centre, nrm, area in planes:
        if any(abs(nrm.dot(n2)) >= cos_d and abs((centre - c2).dot(n2)) <= MERGE_DEV
               for c2, n2, _a in out):
            continue
        out.append((centre, nrm, area))
    return out


def _assign(faces: List, planes: List[Tuple[Vector, Vector, float]]) -> List[int]:
    """Plane index per face, -1 when the face belongs to none of them."""
    cos_a = math.cos(math.radians(ASSIGN_DEG))
    out = [-1] * len(faces)
    for i, f in enumerate(faces):
        n = f.normal
        c = f.calc_center_median()
        best, best_d = -1, ASSIGN_DEV
        for pi, (centre, nrm, _area) in enumerate(planes):
            if n.dot(nrm) < cos_a:
                continue
            d = abs((c - centre).dot(nrm))
            if d < best_d:
                best, best_d = pi, d
        out[i] = best
    return out


def _prune(faces: List, assign: List[int], min_area: float) -> Tuple[List[int], int]:
    """Keep only the connected blobs of each plane's faces that are worth keeping.

    `_assign` picks the CLOSEST plane per face, so where two planes of the same wall sit 15 cm apart
    the faces alternate between them and the wall comes out as interleaved stripes — every face a
    border face. Requiring each plane's faces to be one dominant connected blob removes exactly that:
    a stripe fragment loses its plane and stays as it was, while the wall's main blob keeps its
    interior. Returns (assignment, number of blobs dropped).
    """
    index = {f.index: i for i, f in enumerate(faces)}
    by_plane: Dict[int, List[int]] = {}
    for i, pi in enumerate(assign):
        if pi >= 0:
            by_plane.setdefault(pi, []).append(i)
    dropped = 0
    for members in by_plane.values():
        member = set(members)
        seen: set = set()
        blobs: List[List[int]] = []
        areas: List[float] = []
        for start in members:
            if start in seen:
                continue
            seen.add(start)
            blob, stack = [start], [start]
            while stack:
                f = faces[stack.pop()]
                for e in f.edges:
                    for g in e.link_faces:
                        gi = index[g.index]
                        if gi in member and gi not in seen:
                            seen.add(gi)
                            blob.append(gi)
                            stack.append(gi)
            blobs.append(blob)
            areas.append(sum(faces[i].calc_area() for i in blob))
        biggest = max(areas)
        for blob, area in zip(blobs, areas):
            if area < max(min_area, KEEP_FRAC * biggest):
                for i in blob:
                    assign[i] = -1
                dropped += 1
    return assign, dropped


def _snap(faces: List, planes: List[Tuple[Vector, Vector, float]],
          assign: List[int]) -> Tuple[int, float, int]:
    """Project every vertex onto the least-squares point of the planes of the faces around it."""
    owner: Dict[object, Tuple[object, set]] = {}
    for i, f in enumerate(faces):
        pi = assign[i]
        if pi < 0:
            continue
        for v in f.verts:
            slot = owner.setdefault(v, (v, set()))
            slot[1].add(pi)
    moved, max_move, skipped = 0, 0.0, 0
    for vert, pids in owner.values():
        plist = [(planes[p][0], planes[p][1]) for p in sorted(pids)]
        if len(plist) > 1:
            co = _project(vert.co, plist)
        else:
            c, n = plist[0]
            co = vert.co - n * (vert.co - c).dot(n)
        d = (co - vert.co).length
        if d > MAX_MOVE:
            skipped += 1
            continue
        if d > 1e-9:
            moved += 1
            max_move = max(max_move, d)
        vert.co = co
    return moved, max_move, skipped


def flatten(obj: bpy.types.Object, fit_m: float = FIT_M,
            min_area: float = MIN_AREA) -> Dict[str, float]:
    """Snap every face that has a plane onto it, in place. Returns the stats the row reports."""
    me = obj.data
    if len(me.polygons) == 0:
        return _stats(0.0, 0, 0, 0.0, 0)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    faces = list(bm.faces)
    total_area = sum(f.calc_area() for f in faces)
    if total_area <= 0.0:
        bm.free()
        return _stats(0.0, 0, 0, 0.0, 0)

    planes = _dominant(faces, min_area)
    assign, dropped = _prune(faces, _assign(faces, planes), min_area)
    planar_area = sum(faces[i].calc_area() for i, pi in enumerate(assign) if pi >= 0)
    moved, max_move, skipped = _snap(faces, planes, assign)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.update()
    used = len({pi for pi in assign if pi >= 0})
    stats = _stats(100.0 * planar_area / total_area, used, moved, max_move, dropped)
    stats["verts_skipped"] = skipped
    stats["planes_found"] = len(planes)
    return stats


def _stats(planar_pct: float, regions: int, verts_moved: int, max_move: float,
           rejected: int) -> Dict[str, float]:
    return {"planar_pct": round(planar_pct, 2), "regions": regions, "faces_moved": verts_moved,
            "verts_moved": verts_moved, "max_move_m": round(max_move, 4),
            "regions_rejected": rejected}


def facade_faces(obj: bpy.types.Object, min_area: float = 4.0, vert_max: float = 0.30,
                 prune: bool = True) -> List[List[int]]:
    """Groups of face indices that form one large, near-vertical, near-planar wall.

    This is the input the window-mask pass needs: a pane is a rectangle on a vertical face, so only
    these groups may carry panes (lead r4 MUST-FIX 2). `vert_max` is |n.z| — 0.30 is 17.5 degrees off
    vertical, which lets a slightly battered wall in and keeps roofs and soffits out. The groups are
    the model's dominant planes, so a wall is ONE group however many triangles it is made of.

    `prune` drops each plane's small disconnected blobs, which the GEOMETRY pass needs (a stripe of
    faces on a plane it barely belongs to is exactly what bends a shared border vertex). The TEXTURE
    pass does not: a 2 m^2 patch of wall between two balconies is on the same plane as the 400 m^2
    patch above it and must be repainted with it, or the facade keeps the Tripo albedo's blotches in
    every gap. `facade_tex` therefore asks for `prune=False`.
    """
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    faces = list(bm.faces)
    index = {f.index: i for i, f in enumerate(faces)}
    planes = [p for p in _dominant(faces, min_area) if abs(p[1].z) <= vert_max]
    assign = _assign(faces, planes)
    if prune:
        assign, _dropped = _prune(faces, assign, min_area)
    out: List[List[int]] = []
    for pi in range(len(planes)):
        group = [index[faces[i].index] for i, a in enumerate(assign) if a == pi]
        if len(group) >= 4:
            out.append(group)
    bm.free()
    return out


def vertical_groups(obj: bpy.types.Object, vert_max: float = 0.35,
                    quant: float = 4.0) -> List[List[int]]:
    """Every near-vertical face, bucketed by its normal direction.

    The facade pass repaints the model's dominant wall planes; this catches the rest of the vertical
    surface — balcony fronts, fin sides, parapets — which on an articulated tower is most of what the
    player sees and is where the Tripo albedo's blotches survive (measured on t06: the wall planes are
    79 % of the vertical area but only 8.7 % of the atlas texels, because the atlas spends its
    resolution on the small protruding elements). Faces are bucketed by quantised normal so each
    group has a well-defined wall axis for the rasteriser; a group is only useful if its faces are
    roughly parallel, which is exactly what the bucket guarantees.
    """
    me = obj.data
    buckets: Dict[Tuple[int, int, int], List[int]] = {}
    for poly in me.polygons:
        if abs(poly.normal.z) > vert_max:
            continue
        n = poly.normal
        key = (int(round(n.x * quant)), int(round(n.y * quant)), int(round(n.z * quant)))
        buckets.setdefault(key, []).append(poly.index)
    return [g for g in buckets.values() if len(g) >= 2]
