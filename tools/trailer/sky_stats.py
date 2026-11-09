#!/usr/bin/env python3
"""The numbers behind the time-of-day A/B: what the sky band of each still actually measures.

    uv run --with numpy --with pillow python tools/trailer/sky_stats.py tmp/trailer/r6/tod/*_16x9.jpg

For every still: the mean hue / chroma / lightness of the **top 22 % of the frame** (the sky band where
the camera has one) in HSV degrees, 0-1 saturation and 0-1 value, plus the whole frame's mean value.
city-art's own gate for a golden-hour sky is `skylo_hue` 65-85 deg with `skylo_chroma` >= 16/100 on the
0-9 deg band of a vista camera; this is the same idea on a trailer frame, where the band is whatever
the top of the composition happens to be — so it is a comparison between arms of ONE take, not an
absolute gate.

**What it is and is not good for, measured.** On a low-angle shot the top 22 % of the frame is the blue
ZENITH, not the golden band, so `warmest` reads 213-271 deg (blue) for `c_gatling`, `s01_cold`,
`s02_city` and `s07_hive` at every time of day and says nothing. `brightest` and `most chromatic` do
carry: over the twelve takes measured in r6 the brightest arm is 0.35 or 0.6 in 9 of 12, which is the
numeric form of "0.6 is the flattest". The pick itself is made on the frames (`tod_ab.py`'s sheets).

Prints one row per still, sorted, plus a per-take summary of which time of day is warmest and which is
brightest.
"""
from __future__ import annotations

import argparse
import re
from collections import defaultdict
from pathlib import Path

import numpy as np
from PIL import Image

BAND = 0.22


def stats(path: Path) -> tuple[float, float, float, float]:
    im = Image.open(path).convert("RGB").resize((320, 180), Image.BILINEAR)
    rgb = np.asarray(im, dtype=np.float32) / 255.0
    band = rgb[: max(1, int(rgb.shape[0] * BAND))]
    out = []
    for a in (band, rgb):
        mx = a.max(axis=2)
        mn = a.min(axis=2)
        sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
        d = np.maximum(mx - mn, 1e-6)
        r, g, b = a[..., 0], a[..., 1], a[..., 2]
        h = np.where(mx == r, ((g - b) / d) % 6,
                     np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60.0
        w = sat * mx          # weight the hue by how chromatic and bright the pixel is
        ang = np.deg2rad(h)
        hue = float(np.rad2deg(np.arctan2((w * np.sin(ang)).sum(), (w * np.cos(ang)).sum())) % 360.0)
        out += [hue, float(sat.mean()), float(mx.mean())]
    return out[0], out[1], out[2], out[5]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+", type=Path)
    ap.add_argument("--quiet", action="store_true", help="only the per-take summary")
    args = ap.parse_args()

    rows: dict[str, dict[str, tuple[float, float, float, float]]] = defaultdict(dict)
    for f in sorted(args.files):
        m = re.match(r"(.+)_tod([0-9.]+)_t[0-9_]+_16x9$", f.stem)
        if not m:
            continue
        take, tod = m.group(1), m.group(2)
        rows[take][tod] = stats(f)
        if not args.quiet:
            h, c, v, fv = rows[take][tod]
            print(f"{take:<14} tod {tod:<5} sky hue {h:6.1f}  chroma {c:.3f}  value {v:.3f}  "
                  f"frame {fv:.3f}  {f.name}")
    print()
    print(f"{'take':<14} {'warmest (hue->65)':<20} {'most chromatic':<18} {'brightest':<12}")
    for take, arms in rows.items():
        warm = min(arms, key=lambda t: abs(((arms[t][0] - 65 + 180) % 360) - 180))
        chroma = max(arms, key=lambda t: arms[t][1])
        bright = max(arms, key=lambda t: arms[t][3])
        print(f"{take:<14} {warm + ' (' + format(arms[warm][0], '.0f') + ')':<20} "
              f"{chroma + ' (' + format(arms[chroma][1], '.3f') + ')':<18} "
              f"{bright + ' (' + format(arms[bright][3], '.3f') + ')'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
