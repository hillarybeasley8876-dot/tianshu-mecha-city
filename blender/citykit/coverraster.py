"""Rasterise a cover model's own geometry into its UV layout (lead r7 §1).

Split out of `covertex.py` for length. Everything here answers one question per texel — where on the
model is this texel, which way does it face, how sharp is the edge it sits on, and how many metres
does one texel span — and `coverlook` turns those four numbers into a look at metre scale.

`mpt` (metres per texel, from each triangle's UV->3D Jacobian) is the one that makes the rest possible:
without it a panel seam is a fixed number of TEXELS whatever the island it lands on, and the r5/r6
"the grid averaged away to nothing" failure is what you get. **It is the square root of the Jacobian's
cross-product length**, which is an AREA — reading the length as metres (r7) made everything downstream
9x too fine on k07, where the real density is 121 mm per texel.
"""
from __future__ import annotations

from typing import Dict, Tuple

import bmesh
import bpy
import numpy as np

from covertex import _uvs

#: Convex-edge sharpness (`1 - dot(n1, n2)`, so 0.29 is a 45 deg edge and 1.0 a right angle) below
#: which a vertex is not on a machined corner at all and above which it is a hard one. `coverlook`
#: paints wear between them.
#:
#: This is the vertex's SHARPEST convex edge, not a mean over its edges. r7 used the
#: sharpness-weighted mean and it was wrong in a way that only showed once the albedo was light
#: enough to see it: a decimated flat panel has six near-flat edges at every vertex, their sharpness
#: SUMS past any threshold, and the wear layer then drew the triangulation's own diagonals across
#: every flat face as soft bright creases (isolated with `QA_ONLY=albedo` against `QA_ONLY=normal` —
#: a flat material and the normal map are both clean).
WEAR_LO, WEAR_HI = 0.10, 0.55


def vertex_wear(obj: bpy.types.Object) -> np.ndarray:
    """Per-vertex convex-edge sharpness in 0..1 — the input to the edge-wear layer.

    Blender's Cycles `Geometry -> Pointiness` is the same idea, but it is only available as a shader
    input, so using it would mean another bake. This is the mesh-side computation: for every edge with
    two faces the signed dihedral says convex or concave and `1 - dot(n1, n2)` says how sharp; a
    vertex takes the sharpest CONVEX edge that meets it, so a corner of a box is worn and a vertex in
    the middle of a curved or flat surface is not.
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    best = np.zeros(len(bm.verts), dtype=np.float64)
    for e in bm.edges:
        if len(e.link_faces) != 2:
            continue
        sharp = 1.0 - float(e.link_faces[0].normal.dot(e.link_faces[1].normal))
        if sharp <= 1e-5 or e.calc_face_angle_signed(0.0) <= 0.0:
            continue
        for v in e.verts:
            best[v.index] = max(best[v.index], sharp)
    bm.free()
    return np.clip((best - WEAR_LO) / (WEAR_HI - WEAR_LO), 0.0, 1.0)


def geom(obj: bpy.types.Object, side: int) -> Dict[str, np.ndarray]:
    """Rasterise the mesh's own geometry into the ACTIVE UV layout, at `side` px.

    Returns (H, W) rasters: `pos` (object-space metres, 3 ch), `nrm` (unit split normal, 3 ch), `wear`
    (convex-edge sharpness), `mpt` (metres per texel, from each triangle's UV->3D Jacobian) and `cov`
    (which texels the mesh covers at all).

    `mpt` is what lets `coverlook` draw at metre scale: a seam is the same width in metres whether the
    island it lands on is 20 texels or 400, and the tangent-space normal it writes needs the same
    number to turn a height in metres into a slope. Measured on the shipped glbs: 121 mm per texel on
    k07 and k02, 26 mm on k04 — a 9 000-island layout of a 1 200 m2 shell into a 1 k atlas.
    """
    me = obj.data
    uvl = me.uv_layers.active
    n = len(me.loops)
    uv = _uvs(uvl, n).astype(np.float64)
    co = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3).astype(np.float64)
    ln = np.empty(n * 3, dtype=np.float32)
    me.loops.foreach_get("normal", ln)
    ln = ln.reshape(-1, 3).astype(np.float64)
    norm = np.linalg.norm(ln, axis=1, keepdims=True)
    ln = np.where(norm > 1e-6, ln / np.maximum(norm, 1e-6), 0.0)
    lvert = np.empty(n, dtype=np.int32)
    me.loops.foreach_get("vertex_index", lvert)
    vw = vertex_wear(obj)

    pos = np.zeros((side, side, 3), dtype=np.float32)
    nrm = np.zeros((side, side, 3), dtype=np.float32)
    wear = np.zeros((side, side), dtype=np.float32)
    mpt = np.full((side, side), 3e-2, dtype=np.float32)
    cov = np.zeros((side, side), dtype=bool)
    fid = np.full((side, side), -1, dtype=np.int32)
    for poly in me.polygons:
        li = list(poly.loop_indices)
        for k in range(1, len(li) - 1):
            _raster(uv, co, ln, vw, lvert, (li[0], li[k], li[k + 1]), side,
                    pos, nrm, wear, mpt, cov, fid, poly.index)
    return {"pos": pos, "nrm": nrm, "wear": wear, "mpt": mpt, "cov": cov, "fid": fid}


def _raster(uv: np.ndarray, co: np.ndarray, ln: np.ndarray, vw: np.ndarray, lvert: np.ndarray,
            tri: Tuple[int, int, int], side: int, pos: np.ndarray, nrm: np.ndarray,
            wear: np.ndarray, mpt: np.ndarray, cov: np.ndarray, fid: np.ndarray,
            face: int) -> None:
    """Rasterise one triangle's UV footprint, writing interpolated position / normal / wear.

    A triangle too small to contain a texel CENTRE is splatted into the one texel its UV centroid falls
    in, for the reason `panes._splat` exists: dropping it loses real surface area, and on a decimated
    12 k-tri prop a large share of the triangles are sub-texel.
    """
    t = list(tri)
    p = uv[t] * side
    x0 = max(0, int(np.floor(p[:, 0].min())))
    x1 = min(side - 1, int(np.ceil(p[:, 0].max())))
    y0 = max(0, int(np.floor(p[:, 1].min())))
    y1 = min(side - 1, int(np.ceil(p[:, 1].max())))
    if x1 < x0 or y1 < y0:
        return
    # The affine map texel -> 3D. Its two columns are the surface tangents along u and v, so their
    # cross product's length is the texel's AREA in square metres — the square root is the metres per
    # texel the rest of the pipeline wants. (r7 read the length itself as metres and was therefore 9x
    # too fine on k07: the real density is 121 mm per texel, not 14 mm, which is why a 100 mm panel
    # seam came out 0.8 of a texel and the tangent-space slopes all saturated against SLOPE_CLAMP.)
    a = np.array([[p[0][0], p[0][1], 1.0], [p[1][0], p[1][1], 1.0], [p[2][0], p[2][1], 1.0]])
    try:
        m = np.linalg.solve(a, co[lvert[t]])
    except np.linalg.LinAlgError:
        return
    texel_m = float(np.linalg.norm(np.cross(m[0], m[1]))) ** 0.5
    if texel_m <= 1e-9:
        return
    gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    d = ((p[1][1] - p[2][1]) * (p[0][0] - p[2][0])
         + (p[2][0] - p[1][0]) * (p[0][1] - p[2][1]))
    if abs(d) < 1e-9:
        return
    l0 = ((p[1][1] - p[2][1]) * (gx - p[2][0]) + (p[2][0] - p[1][0]) * (gy - p[2][1])) / d
    l1 = ((p[2][1] - p[0][1]) * (gx - p[2][0]) + (p[0][0] - p[2][0]) * (gy - p[2][1])) / d
    hit = (l0 >= -1e-4) & (l1 >= -1e-4) & ((1.0 - l0 - l1) >= -1e-4)
    if not hit.any():
        cx = min(side - 1, max(0, int(float(p[:, 0].mean()))))
        cy = min(side - 1, max(0, int(float(p[:, 1].mean()))))
        x0 = x1 = cx
        y0 = y1 = cy
        w = np.full((1, 1, 3), 1.0 / 3.0)
        hit = np.ones((1, 1), dtype=bool)
    else:
        w = np.stack([l0, l1, 1.0 - l0 - l1], axis=-1)
    ys, xs = np.nonzero(hit)
    ys, xs = ys + y0, xs + x0
    ww = w[ys - y0, xs - x0]
    pos[ys, xs] = ww @ co[lvert[t]]
    nn = ww @ ln[t]
    ln_len = np.linalg.norm(nn, axis=1, keepdims=True)
    nrm[ys, xs] = np.where(ln_len > 1e-6, nn / np.maximum(ln_len, 1e-6), 0.0)
    wear[ys, xs] = ww @ vw[lvert[t]]
    mpt[ys, xs] = texel_m
    fid[ys, xs] = face
    cov[ys, xs] = True


