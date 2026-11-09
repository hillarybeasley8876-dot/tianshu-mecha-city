"""Repaint every wall with a world-scaled, TEXEL-AWARE facade field (lead r6 MUST-FIX 1 and 3).

Two things were wrong with the r5 pass, and both are visible in `captures/lead_r6pre_st_T1fac.jpg`:

1. **It could not be drawn.** The field's features were specified in metres — a 0.16 m storey line, a
   0.30 m mullion, a 0.08 m panel joint — but a Tripo atlas spends 0.06-0.49 m per texel. Measured on
   the r5 exports, the storey line came out **0.33-0.73 texels** wide on every tower, megablock,
   mid-rise and civic model and the mullion 0.6-1.2 texels. A feature narrower than a texel is not a
   thin line, it is noise: on the buildings it averaged away to nothing (the blank pale sheets the
   lead saw) and on the small props, where it reached 1.4-2.4 texels, it aliased into exactly the
   black/white speckle of MUST-FIX 2.
2. **It covered almost nothing.** Only the faces on a strictly-fitted dominant PLANE were repainted,
   which is 1.5-31 % of each atlas.

So the field is now drawn against the texel grid it lands on:

* every feature is widened to at least `MIN_PX` texels — `w = max(design_m, MIN_PX * mpt)` — so it is
  always resolvable, and the widening is per-texel because `mpt` varies across one atlas by an order
  of magnitude;
* the load-bearing structure is not lines at all but **per-cell value**: each (bay, storey) cell is a
  3.4 x 4.0 m block, 9-70 texels across on every model in the kit, and it carries a hashed value
  offset. That reads as architecture at any texel density and is what the key art's mid-rise facades
  actually are — a field of slightly different panels, not a drawn grid;
* the value is the city's, not the atlas's: base luma 0.15-0.30 scene-linear (lead r6), against the
  0.32 the r5 pass inherited from `grade.BANDS`;
* the regions are `wallgroup.wall_faces()` — every near-vertical face — so nothing keeps the Tripo
  blotches (MUST-FIX 3), and `wallgroup.top_faces()` gives roofs the same value range without a
  storey grid.

`mpt` comes from `panes.raster()`, which recovers it from the affine UV -> wall map's Jacobian.
"""
from __future__ import annotations

from typing import Dict, List, Optional

import numpy as np

import grade
import panes

#: Bay and storey spacing in metres — `panes.CELL_M` / `panes.FLOOR_M`, the numbers the shader's
#: lit-cell hash uses. Read from there rather than repeated, so the two can never drift apart.
BAY_M, FLOOR_M = panes.CELL_M, panes.FLOOR_M
#: No feature may be drawn thinner than this many texels. 2.5 is the point where a hard-edged line
#: stops alternating between "on" and "off" texels under bilinear sampling; below ~2 it is noise.
MIN_PX = 2.5
#: Design widths in metres, before the `MIN_PX` floor: the mullion between two bays, the solid
#: spandrel under each storey line, and a panel joint halfway through a bay.
MULLION_M, SPANDREL_M, JOINT_M = 0.45, 1.05, 0.10
#: Value multipliers for those three features. A wall is read by its value steps, not by black lines.
MULLION_V, SPANDREL_V, JOINT_V = 0.74, 0.66, 0.88
#: Hard caps on the adaptive widening, as a fraction of each feature's own period. Past these the
#: feature stops widening and the per-cell value carries the structure instead — see `_field`.
MULL_FRAC, SPAN_FRAC, JOINT_FRAC = 0.34, 0.38, 0.16
#: A (bay, storey) cell narrower than this many texels cannot carry a value step either, so the hash
#: drops to a `COARSE` times larger cell: a 10 x 12 m block of facade is still architecture.
CELL_PX_MIN = 5.0
COARSE = 3.0
#: Per-cell value swing, as a fraction of the base. This is the feature that survives any texel
#: density, so it is the largest of the three: a facade is a field of panels, not a drawn grid.
CELL_AMP = 0.16
#: Slow weathering on top, at a ~9 m and ~23 m wavelength, so the field is never mathematically flat.
DIRT_AMP = 0.055
#: How much of the original albedo survives on a wall. Low: the Tripo atlas is a confetti of islands
#: and keeping much of it is what put the blotches (MUST-FIX 3) and the speckle (MUST-FIX 2) back.
KEEP_WALL = 0.16
#: Roofs and soffits keep more — a roof carries real detail (tanks, ducts, hatches) that a flat field
#: would erase, and it is seen at a grazing angle where the atlas's own value is mostly hidden.
KEEP_TOP = 0.42

#: Base albedo luminance (scene-linear) per grade band. The lead's r6 range is 0.15-0.30; these sit
#: inside it, in its upper half: the lower half was measured on the grazing-sun gate renders
#: (`captures/kit/wall_m01.png`, `wall_k03.png`) and read as a black silhouette once the emission bug
#: below was fixed and stopped filling the frame. They are still well below `grade.BANDS`, whose
#: targets were chosen for a whole-model median rather than for a wall the dusk sun hits square on.
WALL_LUMA: Dict[str, float] = {
    "tower": 0.255, "megablock": 0.245, "midrise": 0.250, "civic": 0.265, "oldtown": 0.225,
    "harbor": 0.205, "foundry": 0.195, "street": 0.235, "structure": 0.225, "cover": 0.285,
}
DEFAULT_LUMA = 0.235
#: Roofs read a little darker than the walls below them: they are seen against the sky, not lit by
#: the low sun, and a pale roof plane is the first thing that blows out in a vista.
TOP_SCALE = 0.82


def _hash2(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """The same cheap deterministic hash `panes._grid` uses, so the two agree cell for cell."""
    h = np.sin(a * 127.1 + b * 311.7) * 43758.5453
    return h - np.floor(h)


def _field(s: np.ndarray, t: np.ndarray, mpt: float, seed: float, grid: bool) -> np.ndarray:
    """The facade VALUE (a multiplier around 1.0) at wall positions (s, t), for a texel of `mpt` m.

    Everything here is in metres; `mpt` only ever widens a feature, never moves it, so the grid stays
    registered with `panes._grid` and with the shader's `win_cell_m` / `win_floor_m` cells.

    The widening is CLAMPED to a fraction of the feature's own period. Without the clamp a wall whose
    texel is coarser than ~1.4 m gets `w_mull > BAY_M / 2` and `w_span > FLOOR_M`, every texel is both
    mullion and spandrel, and the field collapses to one flat value — the blank plane the lead's gate
    forbids, produced by the very pass meant to remove it. When the lines cannot be drawn, the
    per-cell value carries the structure instead, and it drops to a 3x coarser cell so a (bay, storey)
    block is still several texels across.
    """
    dirt = (np.sin(s / 9.0 + seed * 6.3) * np.sin(t / 11.0 + seed * 4.1)
            + 0.5 * np.sin((s + t) / 23.0 + seed * 2.7))
    val = 1.0 + DIRT_AMP * dirt
    if not grid:
        return val
    bay = s / BAY_M + seed
    flr = np.floor(t / FLOOR_M)
    # Per-cell value: the structure that survives at any texel density. Hashed on the same cell index
    # the shader lights, so a storey that reads darker here is the storey the shader decides on.
    cell_px = min(BAY_M, FLOOR_M) / max(mpt, 1e-6)
    k = 1.0 if cell_px >= CELL_PX_MIN else COARSE
    val = val * (1.0 + CELL_AMP * (_hash2(np.floor(bay / k) + seed * 17.0, np.floor(flr / k)) - 0.5)
                 * 2.0)
    fu = bay - np.floor(bay)
    fv = t / FLOOR_M - flr
    w_mull = min(max(MULLION_M, MIN_PX * mpt), MULL_FRAC * BAY_M)
    w_span = min(max(SPANDREL_M, MIN_PX * mpt), SPAN_FRAC * FLOOR_M)
    w_joint = min(max(JOINT_M, MIN_PX * mpt), JOINT_FRAC * BAY_M)
    mull = (fu * BAY_M < w_mull) | ((1.0 - fu) * BAY_M < w_mull)
    joint = np.abs(fu - 0.5) * BAY_M < w_joint
    band = fv * FLOOR_M < w_span
    val = val * np.where(mull, MULLION_V, 1.0) * np.where(joint, JOINT_V, 1.0)
    return val * np.where(band, SPANDREL_V, 1.0)


def _base_rgb(band: str, luma: float) -> np.ndarray:
    """The band's tint at `luma` scene-linear luminance."""
    _target, tint, _sat = grade.BANDS.get(band, grade.DEFAULT_BAND)
    lin = np.array([grade._srgb_to_linear(c) for c in tint], dtype=np.float32)
    return lin / max(float(lin @ np.array((0.2126, 0.7152, 0.0722), dtype=np.float32)), 1e-6) \
        * np.float32(luma)


def repaint(obj, img, walls: List[List[int]], band: str = "street",
            tops: Optional[List[List[int]]] = None) -> tuple:
    """Repaint `img` (the model's albedo) over every wall and roof of `obj`.

    Returns `(stats, painted)` where `painted` is the boolean raster of the texels this pass wrote.
    `grade.albedo()` needs it: those texels are already at the band's wall value and the grade's
    `target / median` gain must not move them again.

    Called by `kitmat.build()` after the emission mask and the glass weight have been read from the
    ORIGINAL albedo — the neon signs and the pane band must be measured before the walls are replaced.
    """
    empty = np.zeros((1, 1), dtype=bool)
    if img is None or img.size[0] <= 0 or (not walls and not tops):
        return {"wall_px": 0, "wall_pct": 0.0, "top_px": 0, "top_pct": 0.0}, empty
    w, h = img.size
    if w != h:
        print("  WARN facade repaint skipped: %s albedo is %dx%d, not square" % (obj.name, w, h))
        return {"wall_px": 0, "wall_pct": 0.0, "top_px": 0, "top_pct": 0.0}, empty
    luma = WALL_LUMA.get(band, DEFAULT_LUMA)
    wall_rgb = _base_rgb(band, luma)
    top_rgb = _base_rgb(band, luma * TOP_SCALE)
    px = grade._pixels(img)
    rgb = px[:, :3].reshape(h, w, 3)
    out = {"wall": np.zeros((h, w), dtype=bool), "top": np.zeros((h, w), dtype=bool)}
    side = w

    def run(group: List[int], seed: float, grid: bool, keep: float, base: np.ndarray,
            tag: str, flat: bool) -> None:
        def paint(y0: int, y1: int, x0: int, x1: int, s: np.ndarray, t: np.ndarray,
                  mpt: float, hit: np.ndarray) -> None:
            block = rgb[y0:y1 + 1, x0:x1 + 1]
            new = base[None, None, :] * _field(s, t, mpt, seed, grid)[..., None]
            rgb[y0:y1 + 1, x0:x1 + 1] = np.where(hit[..., None],
                                                 new * (1.0 - keep) + block * keep, block)
            out[tag][y0:y1 + 1, x0:x1 + 1] |= hit

        panes.raster(obj, group, side, paint, flat=flat)

    for gi, group in enumerate(walls or []):
        run(group, float((gi * 0.61803398875) % 1.0), True, KEEP_WALL, wall_rgb, "wall", False)
    for gi, group in enumerate(tops or []):
        run(group, float((gi * 0.7548776662) % 1.0), False, KEEP_TOP, top_rgb, "top", True)
    px[:, :3] = rgb.reshape(-1, 3)
    img.pixels.foreach_set(px.reshape(-1))
    img.update()
    painted = out["wall"] | out["top"]
    return ({"wall_px": int(out["wall"].sum()),
             "wall_pct": round(100.0 * float(out["wall"].mean()), 2),
             "top_px": int(out["top"].sum()),
             "top_pct": round(100.0 * float(out["top"].mean()), 2)}, painted)
