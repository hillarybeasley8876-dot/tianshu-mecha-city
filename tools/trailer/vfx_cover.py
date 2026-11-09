#!/usr/bin/env python3
"""How much of a frame a coloured VFX covers — the spitter's acid cloud, measured instead of eyeballed.

    uv run --with numpy --with pillow python tools/trailer/vfx_cover.py --hue 95 --tol 40 \
        tmp/trailer/r6/sweep/m3_spitter_b*_t7_5_16x9.jpg

A pixel counts as covered when its hue is within `--tol` degrees of `--hue` AND it is chromatic enough
to be a VFX rather than a grey surface (`--chroma`, on the 0-1 HSV saturation scale). Prints one line
per file plus the worst, so "the acid cloud covers a third of the frame" becomes a number the lead can
check. r6: this is the gate for the spitter segment's re-rig.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image


def cover(path: Path, hue: float, tol: float, chroma: float, value: float) -> float:
    """The fraction of the frame (0-100 %) inside the hue band."""
    im = Image.open(path).convert("RGB").resize((320, 180), Image.BILINEAR)
    rgb = np.asarray(im, dtype=np.float32) / 255.0
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    # HSV hue in degrees, vectorised the same way colorsys defines it.
    d = np.maximum(mx - mn, 1e-6)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60.0
    delta = np.abs((h - hue + 180.0) % 360.0 - 180.0)
    hit = (delta <= tol) & (sat >= chroma) & (mx >= value)
    return 100.0 * float(hit.mean())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+", type=Path)
    ap.add_argument("--hue", type=float, default=95.0, help="the VFX's hue in degrees (green ~ 95-140)")
    ap.add_argument("--tol", type=float, default=40.0)
    ap.add_argument("--chroma", type=float, default=0.22)
    ap.add_argument("--value", type=float, default=0.12)
    args = ap.parse_args()

    worst = (0.0, "")
    for f in sorted(args.files):
        pct = cover(f, args.hue, args.tol, args.chroma, args.value)
        print(f"{pct:6.2f} %  {f.name}")
        worst = max(worst, (pct, f.name))
    print(f"worst {worst[0]:.2f} %  {worst[1]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
