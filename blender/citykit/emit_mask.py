"""Always-on emission mask derived from a Tripo albedo texture (ART.md §4: signage and shopfronts).

What goes in here is the light a facade emits regardless of the hour: neon signage and the shopfront /
arcade interiors the concept art already painted as lit. Lit *windows* are deliberately NOT baked —
`McKitSkin` finds the dark glass panes in the albedo itself and lights a hashed fraction of them per
4 m floor cell from the TimeOfDay lit fraction, which is the only way the escalation 40 % -> 75 %
can move at runtime. This texture is handed over as the glTF material's emission map.
"""
from __future__ import annotations

from typing import Optional, Tuple

import bpy
import numpy as np

NEON_MIN_VALUE = 0.50      # a sign is bright ...
NEON_MIN_SAT = 0.38        # ... and saturated (cyan / red / amber / jade, never a pale wall)
INTERIOR_MIN_VALUE = 0.80  # shopfronts the painter lit: bright and warm
INTERIOR_HUE = (18.0, 62.0)
#: ... and COLOURED. r6 measured why this is needed: with no saturation floor the class swallowed
#: 15.7 % of t01's atlas and 7.9 % of k03's, because a Tripo albedo is near-white and "bright and
#: warm" describes every wall it has. Shipped at `EMISSION_STRENGTH` 2.4 that is a second sun on the
#: facade — the large pale peach planes the lead saw at T1fac, and the black/white alternation on the
#: cover pieces at A5deck and A6garden (MUST-FIX 2), whose ALBEDO is clean bronze
#: (`captures/kit/wall_k03_alb.png` against `wall_k03.png`).
INTERIOR_MIN_SAT = 0.20
NEON_GAIN = 1.0
INTERIOR_GAIN = 0.45       # interiors read as glow, not as a second sun
#: A model whose "lit interior" still covers more of its atlas than this has no signage in it, only a
#: pale texture; the class is dropped whole rather than shipped as a glowing wall.
INTERIOR_MAX_PCT = 4.0


def _hue(r: np.ndarray, g: np.ndarray, b: np.ndarray, mx: np.ndarray, mn: np.ndarray) -> np.ndarray:
    d = np.maximum(mx - mn, 1e-6)
    h = np.where(mx == r, (g - b) / d % 6.0, np.where(mx == g, (b - r) / d + 2.0, (r - g) / d + 4.0))
    return h * 60.0


MASK_SIDE = 512           # the mask is sparse and mostly black; 4 MB of VRAM each x 40 is waste


def build(albedo: bpy.types.Image, _tex: int,
          signage: bool = True) -> Tuple[Optional[bpy.types.Image], dict]:
    """Return (packed emission image, stats).

    `signage=False` is for the bands that carry no signs at all — cover, industrial, tileable. A cargo
    crate and a pipe rack have nothing to emit, and a Tripo albedo's bright highlights are the only
    thing the classifier can find on them.

    The albedo is sampled through a 512 px COPY: scaling the original in place would silently ship
    every 2K tower with a 1K base colour, which is exactly what it did until r3.
    """
    src = albedo.copy()
    src.scale(MASK_SIDE, MASK_SIDE)
    buf = np.empty(MASK_SIDE * MASK_SIDE * 4, dtype=np.float32)
    src.pixels.foreach_get(buf)
    bpy.data.images.remove(src)
    px = buf.reshape(-1, 4)
    r, g, b = px[:, 0], px[:, 1], px[:, 2]
    mx, mn = px[:, :3].max(axis=1), px[:, :3].min(axis=1)
    sat = np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    hue = _hue(r, g, b, mx, mn)

    neon = (mx >= NEON_MIN_VALUE) & (sat >= NEON_MIN_SAT)
    interior = ((mx >= INTERIOR_MIN_VALUE) & (sat >= INTERIOR_MIN_SAT)
                & (hue >= INTERIOR_HUE[0]) & (hue <= INTERIOR_HUE[1]) & ~neon)
    if not signage or 100.0 * float(interior.mean()) > INTERIOR_MAX_PCT:
        interior = np.zeros_like(interior)
    gain = np.where(neon, NEON_GAIN, 0.0) + np.where(interior, INTERIOR_GAIN, 0.0)
    out = np.zeros((len(px), 4), dtype=np.float32)
    for ch, chan in enumerate((r, g, b)):
        out[:, ch] = chan * gain
    out[:, 3] = 1.0
    stats = {"neon_pct": round(100.0 * float(neon.mean()), 2),
             "interior_pct": round(100.0 * float(interior.mean()), 2)}
    if not signage:
        stats["emit_off"] = 1
    img = bpy.data.images.new("kit_emit", MASK_SIDE, MASK_SIDE, alpha=False)
    img.pixels.foreach_set(out.reshape(-1))
    img.pack()
    return img, stats
