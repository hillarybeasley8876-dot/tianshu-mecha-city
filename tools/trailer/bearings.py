#!/usr/bin/env python3
"""A rendered bearing sweep of one arena (trailer unit, r5).

    tools/trailer/bearings.py 44 3                    # --cams=… for 24 bearings at 44 m, +3 m
    tools/trailer/bearings.py 44 3 --hero=-60,155,450 --fov=55

Prints the `--cams=` argument for `tools/godot.sh shot`, which is how the showcase's camera
bearings are actually chosen. The headless clutter probe (game/trailer/probe_clear.gd) is a screen
for gross failures, not a placement tool -- it scored two lenses that were buried in a wall as
clear -- so every bearing in the reel is picked from a rendered sweep like this one:

    MC_WINDOW_OK=1 tools/godot.sh shot --cams="$(tools/trailer/bearings.py 44 3)" \\
        --out=a6 --outdir=$PWD/tmp/trailer/bear --spawn=-60,155,450,225 --tod=0.6 \\
        --quality=high --skip-menu --stub=flow
    tools/trailer/sheet.py tmp/trailer/bear/a6_*.jpg -o /tmp/sheet.jpg

Bearing is Godot's: 0 = +X, 90 = +Z, measured from the hero, and the lens looks at the hero.
"""
from __future__ import annotations

import argparse
import math


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dist", type=float, help="lens distance from the hero, metres")
    ap.add_argument("height", type=float, help="lens height above the hero's origin, metres")
    ap.add_argument("--hero", default="-60,155,450", help="the arena's hero position")
    ap.add_argument("--fov", type=float, default=55.0)
    ap.add_argument("--step", type=float, default=15.0, help="bearing step, degrees")
    args = ap.parse_args()

    hx, hy, hz = (float(v) for v in args.hero.split(","))
    out = []
    az = 0.0
    while az < 360.0:
        a = math.radians(az)
        out.append("%03d:%.1f,%.1f,%.1f:%.1f,%.1f,%.1f:%g" % (
            int(az), hx + math.cos(a) * args.dist, hy + args.height,
            hz + math.sin(a) * args.dist, hx, hy, hz, args.fov))
        az += args.step
    print(";".join(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
