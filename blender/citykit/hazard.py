"""Hazard bands, painted back into the bake as an OBJECT-SPACE pattern (lead r8 §3).

**Why it has to be drawn and not preserved.** r7 measured `hazard_pct` 0.0 on both prototypes: the
0.45 m chroma diffusion is wider than the 0.5 m band it had to preserve, and the soft saturation
threshold then dropped what was left of it. No amount of tuning fixes that — a band half a metre wide
on a model whose texels are 14 mm is 36 texels of chroma that a 0.45 m blur is specifically designed
to erase. (And the texel is not the 14 mm r7 reported either — the real density on k07 is 121 mm per
texel, so a 0.5 m band is FOUR texels tall and nothing that survives a resample is left of it.) So the
band is drawn, after the diffusion, from the geometry rather than from the atlas.

**Where.** The band positions are fractions of each model's own height, read off its concept by eye
(`BANDS`). They are a table because "the k07 plinth" is a thing a human sees and no measurement in the
atlas survives to say so.

**How.** 45-degree stripes at a 0.6 m period, evaluated in the plane coordinates `coverlook.plane_axes`
gives — which are metres on the surface, so the period is 0.6 m on a 5 m barrier and on a 16 m
transformer alike. At 121 mm per texel that period is 5 texels, which is the narrowest stripe this
atlas can carry. The edge is one texel of antialias and no more: a hard step aliases into a crawling
moire at 15 m, and anything wider is the diffusion this replaces.

k12 is deliberately absent. Both of its concept candidates show a white concrete silo, grey culvert
rings and bronze trim with cyan neon, and no hazard band anywhere — inventing one would contradict
r8 §2 ("the cover keeps its concept's colours") on the very sheet that is supposed to prove it.
"""
from __future__ import annotations

from typing import Dict, List, Tuple

import numpy as np

#: Stripe colours, STORED sRGB. The lead's r8 §3 yellow and black; the k05 pair is that barrier's own
#: red-on-white banner, which is what its concept actually carries.
YELLOW = (0.85, 0.70, 0.10)
BLACK = (0.06, 0.06, 0.07)
RED = (0.72, 0.13, 0.12)
WHITE = (0.86, 0.86, 0.84)
#: Stripe pitch in metres, and the chevron's own repeat for the jersey barriers.
PERIOD_M = 0.60
CHEVRON_M = 3.20
#: A face counts as a side (and can carry a band) below this |n.z|.
SIDE_NZ = 0.55

Band = Dict[str, object]
#: zf is (low, high) as a fraction of the model's height above its own base.
BANDS: Dict[str, List[Band]] = {
    # Precast jersey barriers: the chevrons cover the upper two thirds of the sloped face, the
    # concrete toe and cap stay bare.
    "k04": [{"zf": (0.14, 0.74), "mode": "chevron", "on": YELLOW, "off": BLACK}],
    # The sandbag barricade's banner: a red-on-white diagonal across the middle of the plates.
    "k05": [{"zf": (0.30, 0.60), "mode": "stripe", "on": RED, "off": WHITE}],
    # The transformer's plinth: a band around the top of the concrete base, which is the bottom
    # 10 % of a 16 m machine.
    "k07": [{"zf": (0.050, 0.098), "mode": "stripe", "on": YELLOW, "off": BLACK}],
}


def _edge_soft(x: np.ndarray, mpt: np.ndarray) -> np.ndarray:
    """One texel of antialias on a hard pattern edge, and nothing wider."""
    soft = np.maximum(mpt * 0.75, 1e-4)
    return np.clip(x / soft + 0.5, 0.0, 1.0)


def _stripe(u: np.ndarray, v: np.ndarray, mpt: np.ndarray, mode: str) -> np.ndarray:
    """The stripe field in 0..1: 1 is the `on` colour. 45 degrees, `PERIOD_M` along the surface."""
    if mode == "chevron":
        # A chevron is a stripe field in (|u| + v) where u is measured from the middle of each repeat,
        # which makes the V and its mirror without a second pass.
        um = ((u / CHEVRON_M + 0.5) % 1.0 - 0.5) * CHEVRON_M
        field = (np.abs(um) + v) / PERIOD_M
    else:
        field = (u + v) / PERIOD_M
    frac = field % 1.0
    return _edge_soft(np.minimum(frac, 1.0 - frac) * PERIOD_M, mpt)


def draw(rgb: np.ndarray, pos: np.ndarray, nrm: np.ndarray, cov: np.ndarray, mpt: np.ndarray,
         u: np.ndarray, v: np.ndarray, aid: str) -> Tuple[np.ndarray, np.ndarray, Dict[str, float]]:
    """Paint `aid`'s bands into the composed albedo. Returns (rgb, band mask, stats).

    `u` / `v` are the caller's metre coordinates on the surface (`coverlook.plane_axes`) — passed in
    rather than recomputed, so the stripes lie in exactly the frame the panel seams do.
    The mask comes back because the ORM and the normal need it: a painted band is glossier than the
    concrete under it and carries none of the panel relief.
    """
    mask = np.zeros(cov.shape, dtype=np.float32)
    bands = BANDS.get(aid, [])
    if not bands or not cov.any():
        return rgb, mask, {"hazard_pct": 0.0, "hazard_bands": 0}
    z = pos[..., 2]
    z0 = float(z[cov].min())
    span = max(float(z[cov].max()) - z0, 1e-3)
    side = np.abs(nrm[..., 2]) < SIDE_NZ
    out = rgb
    for b in bands:
        lo, hi = (float(b["zf"][0]), float(b["zf"][1]))
        sel = cov & side & (z >= z0 + lo * span) & (z <= z0 + hi * span)
        if not sel.any():
            continue
        s = _stripe(u, v, mpt, str(b["mode"]))
        on = np.array(b["on"], dtype=np.float32)
        off = np.array(b["off"], dtype=np.float32)
        target = off[None, None, :] + (on - off)[None, None, :] * s[..., None]
        out = np.where(sel[..., None], target, out)
        mask = np.where(sel, 1.0, mask)
    return out, mask, {"hazard_pct": round(100.0 * float((mask > 0.5).mean()), 2),
                       "hazard_bands": len(bands)}
