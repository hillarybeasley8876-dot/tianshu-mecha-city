#!/usr/bin/env python3
"""Measure the grazing-light gate numerically: ripple-band energy, r3 export vs r5 export.

    python3 tools/citykit/graze_measure.py captures/kit/graze_t01.png [...]

`blender/citykit/graze.py` renders the same model twice in one frame under one sun — the r3 export on
the left, the r5 export on the right, flat grey material, no texture, no windows, no normal map. This
turns that picture into a number. `graze_<id>_lod.png` is the same gate on the model's LOD, which is
the mesh the cover pieces are placed from (lead r4 MUST-FIX 2).

The metric is the energy in the RIPPLE BAND: |blur(4 px) - blur(28 px)| over the model's own pixels.
A reconstruction wobble on a 30 m wall lands squarely in that band at this framing; a real mullion or
a setback edge is 1-3 px and lands above it, and the overall shading gradient is below it. So the
number falls when the surface stops rippling and does not fall when the model simply loses detail.

It cannot reach zero — real architecture has detail in that band too — so the honest reading is the
CHANGE between the two halves, not the absolute value.
"""
from __future__ import annotations

import sys

import numpy as np
from PIL import Image

#: Box-blur radii whose difference isolates the ripple band, in pixels.
LO_R, HI_R = 2, 14
#: Vertical slice of the model the measurement uses — the shaft, away from the crown and the base.
SLICE = (0.30, 0.70)


def box(im: np.ndarray, r: int) -> np.ndarray:
    """Separable box blur of radius `r`, edges replicated."""
    p = np.pad(im, r, mode="edge")
    c = np.cumsum(p, axis=0)
    rows = (c[2 * r:, :] - c[:-2 * r, :]) / (2 * r)
    c = np.cumsum(rows, axis=1)
    return (c[:, 2 * r:] - c[:, :-2 * r]) / (2 * r)


def halves(path: str):
    """The two models in one gate render, as (x0, x1) column runs."""
    im = np.asarray(Image.open(path).convert("L"), dtype=np.float32) / 255.0
    bg = float(np.median(im[:20, :20]))
    obj = np.abs(im - bg) > 0.02
    cols = np.nonzero(obj.any(axis=0))[0]
    if cols.size == 0:
        return im, obj, []
    gaps = np.nonzero(np.diff(cols) > 20)[0]
    runs = [(int(cols[0]), int(cols[-1]))]
    if gaps.size:
        runs = [(int(cols[0]), int(cols[gaps[0]])),
                (int(cols[gaps[0] + 1]), int(cols[-1]))]
    return im, obj, runs


def energy(path: str):
    im, obj, runs = halves(path)
    if len(runs) < 2:
        return []
    ripple = np.abs(box(im, LO_R) - box(im, HI_R))
    out = []
    for x0, x1 in runs:
        rows = np.nonzero(obj[:, x0:x1].any(axis=1))[0]
        y0, y1 = int(rows[0]), int(rows[-1])
        h = y1 - y0
        cy0, cy1 = y0 + int(h * SLICE[0]), y0 + int(h * SLICE[1])
        v = ripple[cy0:cy1, x0:x1][obj[cy0:cy1, x0:x1]]
        out.append((float(v.mean()), float(np.percentile(v, 90))))
    return out


def main() -> int:
    paths = sys.argv[1:] or (
        ["captures/kit/graze_%s.png" % i for i in ("t01", "b01", "o01", "s04", "k02", "k06")]
        + ["captures/kit/graze_%s_lod.png" % i for i in ("k01", "k02", "k06", "s01")])
    print("%-9s %-22s %-22s %s" % ("model", "r3 (left)", "r5 (right)", "change"))
    for p in paths:
        e = energy(p)
        if len(e) < 2:
            print("%-9s (not a two-model gate render)" % p)
            continue
        name = p.rsplit("graze_", 1)[-1].rsplit(".", 1)[0]
        print("%-9s mean %.4f p90 %.4f   mean %.4f p90 %.4f   %+.0f %% mean, %+.0f %% p90"
              % (name, e[0][0], e[0][1], e[1][0], e[1][1],
                 100.0 * (e[1][0] / max(e[0][0], 1e-6) - 1.0),
                 100.0 * (e[1][1] / max(e[0][1], 1e-6) - 1.0)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
