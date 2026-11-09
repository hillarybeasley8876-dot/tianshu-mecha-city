"""The window mask: a pane is a rectangle on a vertical face (lead r4 MUST-FIX 2).

r3 carved panes out of the DARKEST 7-17 % of each atlas. On a Tripo atlas the darkest texels are not
windows — they are crevices, AO creases and seam noise (the lead's `tmp/lead/alb_sheet.jpg` is a
confetti of tiny islands). The shader then lit that noise warm/cool at 1.7 gain, and because the
noise follows the mesh wobble it read as reflections on chrome.

So panes come from GEOMETRY here, not from darkness:

  * `planar.facade_faces()` gives the large, near-vertical, near-planar wall regions;
  * every triangle in one of those regions is rasterised into a `side` x `side` mask through its own
    UVs, with the texel's real-world position on the wall recovered from the affine UV -> wall map
    (a planar triangle maps UV to 3D affinely, so this is exact);
  * a metric grid of `CELL_M` x `FLOOR_M` bays then stamps a `PANE_W` x `PANE_H` rectangle per bay.

Every pane is therefore a rectangle of a known size on a vertical face: 2.0 m x 2.4 m = 4.8 m^2,
which clears the lead's "under 10 % of pane texels in components smaller than 0.5 m^2" gate by
construction. Blobs, slivers and crevices can never become panes because they are never stamped.
The grid spacing matches `mc_kit_body.gdshaderinc`'s `win_cell_m` / `win_floor_m`, so the shader's
per-cell lit/unlit hash lands one decision per pane instead of one per arbitrary patch.
"""
from __future__ import annotations

import math
import struct
import zlib
from typing import Dict, List, Tuple

import numpy as np
from mathutils import Vector

import planar

#: Bay and storey spacing, in metres — the same numbers the shader uses for its lit-cell hash.
CELL_M = 3.4
FLOOR_M = 4.0
#: The pane inside its bay. 2.0 x 2.4 m is a real curtain-wall light: wide enough to read at 200 m,
#: small enough that the mullion between two panes is a metre of wall.
PANE_W = 2.0
PANE_H = 2.4
#: No panes in the lowest storeys — shopfronts, plant rooms and podiums are not curtain wall. The
#: shader applies the same cut (`win_podium_m`); doing it here as well keeps the mask honest.
PODIUM_M = 6.0
#: Share of bays left solid, so a facade is not a perfect pegboard. Hashed per (bay, floor, wall).
GAP_FRAC = 0.12
#: Starting mask resolution, and the two steps the adaptive loop in `build()` may raise it to. A pane
#: is 2.0 x 2.4 m and the mask has to resolve it: measured on t01 at 512 the facade texel was 0.52 m^2
#: — a third of a pane — so the grid came out 3 texels across. `build()` re-stamps at the next step up
#: until the texel is under 0.25 m^2, which lands a megablock (38 000-54 000 m^2 of wall) on 2048.
MASK_SIDE = 512
MASK_SIDE_BIG = 1024
MASK_SIDE_MAX = 2048
#: Components below this, in square metres, are not windows — the lead's rule. They are pruned from
#: the shipped mask and their share is reported, because a pane clipped by the edge of a small wall
#: region is a sliver, not a window.
MIN_PANE_M2 = 0.5


def side_for(tex: int) -> int:
    """The resolution `build()` starts from, for a model whose albedo ships at `tex`.

    Only a starting point: the loop in `build()` measures the facade texel and doubles until a pane
    is resolved, so this just saves a wasted pass on a model whose texture is already large.
    """
    return MASK_SIDE_BIG if tex >= 2048 else MASK_SIDE


def _hash2(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """A cheap deterministic 2D hash in [0, 1) — the same shape as the shader's `hash21`."""
    h = np.sin(a * 127.1 + b * 311.7) * 43758.5453
    return h - np.floor(h)


def _grid(s: np.ndarray, t: np.ndarray, seed: float) -> np.ndarray:
    """Pane coverage in [0, 1] for wall coordinates `s` (along the wall) and `t` (height)."""
    bay = np.floor(s / CELL_M + seed)
    flr = np.floor(t / FLOOR_M)
    u = s / CELL_M + seed - bay
    v = t / FLOOR_M - flr
    inside = ((np.abs(u - 0.5) < PANE_W / (2.0 * CELL_M))
              & (np.abs(v - 0.5) < PANE_H / (2.0 * FLOOR_M)) & (t > PODIUM_M))
    solid = _hash2(bay + seed * 17.0, flr) < GAP_FRAC
    return np.where(inside & ~solid, 1.0, 0.0).astype(np.float32)


def _wall_axes(normal: Vector) -> Tuple[Vector, Vector]:
    """(along-wall unit axis, up) for a vertical face — `up` is always world Z."""
    e = Vector((-normal.y, normal.x, 0.0))
    if e.length < 1e-6:
        e = Vector((1.0, 0.0, 0.0))
    return e.normalized(), Vector((0.0, 0.0, 1.0))


def _plane_axes(normal: Vector) -> Tuple[Vector, Vector]:
    """Two orthonormal in-plane axes for ANY face, so a roof gets a real 2D field.

    A roof rasterised with `_wall_axes` would have a constant `t` (every texel at the same height) and
    its weathering term would collapse to stripes along `s`.
    """
    seed = Vector((0.0, 0.0, 1.0)) if abs(normal.z) < 0.9 else Vector((1.0, 0.0, 0.0))
    e1 = seed - normal * seed.dot(normal)
    if e1.length < 1e-6:
        e1 = Vector((1.0, 0.0, 0.0))
    e1.normalize()
    return e1, normal.cross(e1).normalized()


def raster(obj, group: List[int], side: int, fn, flat: bool = False) -> int:
    """Rasterise one facade region's UV footprint at `side` px and report every texel's wall position.

    `fn(y0, y1, x0, x1, s, t, mpt, hit)` is called once per triangle with the block's index range, the
    texel's (along-wall, height) position in METRES, the texel's own size in METRES (`mpt`, from the
    affine map's Jacobian), and the barycentric hit mask. The caller merges the result into whatever it
    is painting — the window mask here, the repainted facade albedo in `facade_tex.py` — so the affine
    UV-to-wall maths, which is the whole difficulty, has one home.

    `mpt` is what makes a world-scaled field drawable at all: a Tripo atlas spends 0.06-0.49 m per
    texel depending on the model, so a 0.16 m storey line is 0.3-2.4 texels wide and simply cannot be
    resolved. Every feature `facade_tex` draws is widened to at least `MIN_PX` texels using this.
    `flat=True` measures `t` along the face's own plane instead of world Z — the roof/soffit case.
    Returns the texels covered.
    """
    me = obj.data
    uvl = me.uv_layers.active
    if uvl is None:
        return 0
    normal = Vector((0.0, 0.0, 0.0))
    for pi in group:
        normal += Vector(me.polygons[pi].normal)
    if normal.length < 1e-6:
        return 0
    e1, e2 = (_plane_axes if flat else _wall_axes)(normal.normalized())
    covered = 0
    for pi in group:
        for tri in _triangles(me.polygons[pi]):
            covered += _raster_tri(me, uvl, e1, e2, tri, side, fn)
    return covered


def _rasterise(obj, group: List[int], mask: np.ndarray, side: int, seed: float) -> int:
    """Stamp the pane grid over one facade region. Returns the texels written."""
    def stamp(y0: int, y1: int, x0: int, x1: int, s: np.ndarray, t: np.ndarray,
              mpt: float, hit: np.ndarray) -> None:
        block = mask[y0:y1 + 1, x0:x1 + 1]
        np.maximum(block, _grid(s, t, seed) * hit, out=block)

    return raster(obj, group, side, stamp)


def _triangles(poly) -> List[Tuple[int, int, int]]:
    """Loop-vertex triples for a polygon: a fan for a quad/ngon, which is all Blender produces here."""
    li = list(poly.loop_indices)
    if len(li) < 3:
        return []
    return [(li[0], li[i], li[i + 1]) for i in range(1, len(li) - 1)]


def _affine(uv: np.ndarray, st: np.ndarray) -> np.ndarray:
    """The 3x3 matrix taking homogeneous UV to (s, t), or None if the UV triangle is degenerate.

    A triangle on a plane maps UV to 3D affinely, so (s, t) — both linear in 3D — is affine in UV too.
    Three point correspondences solve it exactly.
    """
    a = np.array([[uv[0][0], uv[0][1], 1.0], [uv[1][0], uv[1][1], 1.0], [uv[2][0], uv[2][1], 1.0]])
    try:
        return np.linalg.solve(a, st)
    except np.linalg.LinAlgError:
        return None


def _raster_tri(me, uvl, e1: Vector, e2: Vector, tri: Tuple[int, int, int], side: int, fn) -> int:
    """Rasterise one triangle's UV footprint, reporting each texel's position on the wall."""
    uv = np.array([tuple(uvl.data[i].uv) for i in tri], dtype=np.float64)
    st = np.zeros((3, 2), dtype=np.float64)
    for k, i in enumerate(tri):
        co = me.vertices[me.loops[i].vertex_index].co
        st[k] = (co.dot(e1), co.dot(e2))
    m = _affine(uv, st)
    if m is None:
        return 0
    px = uv * side
    x0 = max(0, int(np.floor(px[:, 0].min())))
    x1 = min(side - 1, int(np.ceil(px[:, 0].max())))
    y0 = max(0, int(np.floor(px[:, 1].min())))
    y1 = min(side - 1, int(np.ceil(px[:, 1].max())))
    if x1 < x0 or y1 < y0:
        return 0
    xs = np.arange(x0, x1 + 1) + 0.5
    ys = np.arange(y0, y1 + 1) + 0.5
    gx, gy = np.meshgrid(xs, ys)
    # Barycentric test in texel space — cheaper than a per-row scanline and exact enough at 512 px.
    d = ((px[1][1] - px[2][1]) * (px[0][0] - px[2][0])
         + (px[2][0] - px[1][0]) * (px[0][1] - px[2][1]))
    if abs(d) < 1e-9:
        return 0
    l0 = ((px[1][1] - px[2][1]) * (gx - px[2][0]) + (px[2][0] - px[1][0]) * (gy - px[2][1])) / d
    l1 = ((px[2][1] - px[0][1]) * (gx - px[2][0]) + (px[0][0] - px[2][0]) * (gy - px[2][1])) / d
    l2 = 1.0 - l0 - l1
    hit = (l0 >= -1e-4) & (l1 >= -1e-4) & (l2 >= -1e-4)
    if not hit.any():
        # A sub-texel triangle contains no texel CENTRE, so the barycentric test drops it whole. In a
        # Tripo confetti atlas that is most of them: measured on t01 the wall pass reached 23 % of the
        # atlas while 75 % of the mesh AREA is wall, because thousands of islands are smaller than one
        # texel. Those islands are the near cover pieces the lead saw speckled (MUST-FIX 2), so the
        # triangle instead splats the single texel its own UV centroid falls in.
        return _splat(m, px, side, fn)
    u = gx / side
    v = gy / side
    s = m[0][0] * u + m[1][0] * v + m[2][0]
    t = m[0][1] * u + m[1][1] * v + m[2][1]
    # Metres per texel: the affine map takes one UV unit to `m`, so a texel of 1/side UV units covers
    # |det J| / side^2 square metres of wall. This is the number that decides whether a world-scaled
    # feature can be drawn at all (see the module docstring of `facade_tex`).
    det = abs(m[0][0] * m[1][1] - m[1][0] * m[0][1])
    fn(y0, y1, x0, x1, s, t, math.sqrt(det) / side, hit)
    return int(hit.sum())


def _splat(m: np.ndarray, px: np.ndarray, side: int, fn) -> int:
    """Paint the one texel a sub-texel triangle's UV centroid lands in. Returns 1, or 0 if outside."""
    x = min(side - 1, max(0, int(float(px[:, 0].mean()))))
    y = min(side - 1, max(0, int(float(px[:, 1].mean()))))
    u, v = (x + 0.5) / side, (y + 0.5) / side
    s = m[0][0] * u + m[1][0] * v + m[2][0]
    t = m[0][1] * u + m[1][1] * v + m[2][1]
    det = abs(m[0][0] * m[1][1] - m[1][0] * m[0][1])
    fn(y, y, x, x, np.array([[s]]), np.array([[t]]), math.sqrt(det) / side,
       np.ones((1, 1), dtype=bool))
    return 1


def build(obj, side: int = MASK_SIDE,
          texel_target: float = 0.25,
          groups: List[List[int]] | None = None) -> Tuple[np.ndarray, Dict[str, float]]:
    """Rasterise the window mask for `obj`. Returns (mask as a flat float32 array, stats).

    Call it AFTER `planar.flatten()` — the facade regions it reads are the flattened ones, and a
    wobbly wall would otherwise hand the grid a different plane per triangle.

    `groups` is the caller's region choice. `process.py` passes `wallgroup.wall_faces(obj)` for the
    building bands, so the mask covers the whole facade and not only the few percent of it that
    `planar.facade_faces()`'s strict plane fit accepts (lead r6 MUST-FIX 3); props keep the strict
    regions, because a crate is not a curtain wall. `None` means "use the strict regions".

    The resolution is raised once, to `MASK_SIDE_BIG`, if the first pass shows the facade texel is
    bigger than `texel_target` square metres. Measured: a 2.0 x 2.4 m pane needs a texel of ~0.25 m^2
    to come out as a 4 x 5 rectangle, and a wide low civic hall (c01, 24 977 m^2 of wall) was at 0.78
    on the texture-size rule alone. Re-stamping at 1024 costs one extra pass and a few seconds.

    `small_pct` is the lead's gate: the share of pane texels sitting in connected components smaller
    than 0.5 m^2, which must stay under 10 %. Texel area is recovered per model from the facade
    groups' own world area against the texels they cover, so the number is in real square metres and
    not in atlas pixels.
    """
    if not me_has_uv(obj):
        return np.zeros((side, side), dtype=np.float32).reshape(-1), {
            "walls": 0, "pane_pct": 0.0, "pane_px": 0, "small_pct": 0.0, "side": side}
    if groups is None:
        groups = planar.facade_faces(obj)
    me = obj.data
    wall_area = sum(me.polygons[pi].area for g in groups for pi in g)
    mask, covered = _stamp(obj, groups, side)
    texel_m2 = wall_area / max(covered, 1)
    while texel_m2 > texel_target and side < MASK_SIDE_MAX:
        side = min(side * 2, MASK_SIDE_MAX)
        mask, covered = _stamp(obj, groups, side)
        texel_m2 = wall_area / max(covered, 1)
    small, pruned = _small_and_prune(mask, texel_m2)
    stats = {"walls": len(groups),
             "pane_pct": round(100.0 * int((mask > 0.5).sum()) / float(side * side), 2),
             "pane_px": int((mask > 0.5).sum()), "uv_px": covered, "wall_m2": round(wall_area, 1),
             "texel_m2": round(texel_m2, 4), "small_pct": small, "pruned_pct": pruned, "side": side}
    return mask.reshape(-1), stats


def _stamp(obj, groups, side: int) -> Tuple[np.ndarray, int]:
    """One rasterisation pass of the pane grid over every facade region."""
    mask = np.zeros((side, side), dtype=np.float32)
    covered = 0
    for gi, group in enumerate(groups):
        seed = float((gi * 0.61803398875) % 1.0)
        covered += _rasterise(obj, group, mask, side, seed)
    return mask, covered


def _components(on: np.ndarray):
    """4-connected components of a boolean raster, as lists of (y, x) cells.

    One iterative flood fill over the whole mask. The mask is up to 2048^2 and mostly empty, so the
    scan starts from the set bits only; a megablock's 40 000 pane texels is a few hundred components.
    """
    seen = np.zeros_like(on)
    ys, xs = np.nonzero(on)
    for sy, sx in zip(ys.tolist(), xs.tolist()):
        if seen[sy, sx]:
            continue
        stack = [(sy, sx)]
        seen[sy, sx] = True
        cells = []
        while stack:
            y, x = stack.pop()
            cells.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < on.shape[0] and 0 <= nx < on.shape[1] and on[ny, nx] \
                        and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        yield cells


def _small_and_prune(mask: np.ndarray, texel_m2: float,
                     min_m2: float = MIN_PANE_M2) -> Tuple[float, float]:
    """(share of pane texels in components under `min_m2`, share erased) — one labelling pass.

    `small_pct` is the lead's gate measured on what the geometry route produced; the erase is what
    ships. "Blobs, slivers and crevices are not windows" (lead r4): a pane that a wall region's
    border cut into a 0.2 m^2 fragment is a sliver, and lighting it at 1.7 gain is exactly the
    glowing-scribble failure this whole pass exists to remove.
    """
    on = mask > 0.5
    total = int(on.sum())
    if total == 0:
        return 0.0, 0.0
    limit = max(1, int(min_m2 / max(texel_m2, 1e-6)))
    small = 0
    for cells in _components(on):
        if len(cells) >= limit:
            continue
        small += len(cells)
        for y, x in cells:
            mask[y, x] = 0.0
    return round(100.0 * small / total, 2), round(100.0 * small / total, 2)


def me_has_uv(obj) -> bool:
    return bool(obj.data.uv_layers) and obj.data.uv_layers.active is not None


def save(mask: np.ndarray, side: int, path: str) -> str:
    """Write the mask as an 8-bit GREYSCALE PNG next to the glb.

    Greyscale, and written by hand rather than through Blender's image saver: Godot imports an 8-bit
    grey PNG as `FORMAT_L8`, one byte per texel, where the RGB PNG Blender writes costs three. The kit's
    masks are 42 Mpx, so that is 168 MB resident against 56 MB — the single biggest VRAM lever in the
    kit after the albedo resolution. A hand-rolled PNG writer is 20 lines of zlib and struct and keeps
    Blender's Python free of a Pillow dependency.

    PNG, not JPEG: a jpeg's ringing puts a halo of mid-grey around every pane, and `window_mask()`
    turns any non-zero channel into glass.
    """
    rows = np.clip(mask.reshape(side, side) * 255.0 + 0.5, 0, 255).astype(np.uint8)
    raw = np.zeros((side, side + 1), dtype=np.uint8)
    raw[:, 1:] = rows                                  # one filter byte (0 = None) per scanline
    ihdr = struct.pack(">IIBBBBB", side, side, 8, 0, 0, 0, 0)
    chunks = [_chunk(b"IHDR", ihdr),
              _chunk(b"IDAT", zlib.compress(raw.tobytes(), 9)),
              _chunk(b"IEND", b"")]
    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n" + b"".join(chunks))
    return path


def _chunk(tag: bytes, data: bytes) -> bytes:
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def rel_path(aid: str) -> str:
    return "%s/%s_win.png" % (aid, aid)

