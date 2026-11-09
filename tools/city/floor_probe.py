#!/usr/bin/env python3
"""Why is an arena cover piece standing in mid-air? (lead r9)

Reads `data/map/city_layout.json` only — no Blender, no Godot — and answers, for one cover row
(`A4#49`) or a whole arena, which LAYOUT surfaces are under it:

    tools/city/floor_probe.py A4#49 A3#36 A1#45
    tools/city/floor_probe.py --all            # every cover row the audit flagged

The audit (`tools/godot.sh run res://tools/float_audit.tscn`) measures what is RENDERED. This
measures what the layout DECLARES, so the difference between the two is the diagnosis:

  * a deck polygon contains the point at the cover's z      -> my render lost the face (case a)
  * a deck polygon contains the point at another z          -> the cover is on the wrong tier (case b)
  * nothing contains the point                              -> no floor was ever declared (case c)

Coordinates are Blender metres (x east, y north, z up), the same space `build_city.py` builds in.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAYOUT = ROOT / "data" / "map" / "city_layout.json"
TOL = 0.35          ## a cover base within this of a deck top counts as standing on it


def _inside(poly: list, x: float, y: float) -> bool:
    """Even-odd point in polygon; `poly` is a list of [x, y]."""
    hit = False
    n = len(poly)
    for i in range(n):
        ax, ay = poly[i]
        bx, by = poly[(i + 1) % n]
        if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
            hit = not hit
    return hit


def _bbox(poly: list) -> tuple[float, float, float, float]:
    xs = [p[0] for p in poly]
    ys = [p[1] for p in poly]
    return min(xs), min(ys), max(xs), max(ys)


class Layout:
    def __init__(self, path: Path = LAYOUT) -> None:
        self.d = json.loads(path.read_text())
        self.decks = self.d["decks"]
        self.arenas = {a["id"]: a for a in self.d["arenas"]}
        self.streets = self.d["streets"]
        self.viaducts = self.d["viaducts"]
        self.terrain = self.d["terrain"]

    def decks_at(self, x: float, y: float) -> list[dict]:
        out = []
        for dk in self.decks:
            poly = dk["polygon"]
            x0, y0, x1, y1 = _bbox(poly)
            if not (x0 - 1 <= x <= x1 + 1 and y0 - 1 <= y <= y1 + 1):
                continue
            if not _inside(poly, x, y):
                continue
            if any(_inside(h, x, y) for h in dk.get("holes", [])):
                continue
            out.append(dk)
        return sorted(out, key=lambda r: float(r["z"]))

    def cover(self, arena: str, index: int) -> dict:
        return self.arenas[arena]["cover"][index]

    def streets_at(self, x: float, y: float) -> list[dict]:
        out = []
        for s in self.streets:
            for a, b in zip(s["points"], s["points"][1:]):
                if _near_segment(x, y, a, b, float(s.get("width", 20.0)) * 0.5):
                    out.append(s)
                    break
        return out


def _near_segment(x: float, y: float, a: list, b: list, r: float) -> bool:
    dx, dy = b[0] - a[0], b[1] - a[1]
    ll = dx * dx + dy * dy
    t = 0.0 if ll < 1e-9 else max(0.0, min(1.0, ((x - a[0]) * dx + (y - a[1]) * dy) / ll))
    return (x - a[0] - dx * t) ** 2 + (y - a[1] - dy * t) ** 2 <= r * r


def _corners(x: float, y: float, w: float, d: float, yaw_deg: float) -> list[tuple[float, float]]:
    """The four footprint corners of a cover box, plus the centre."""
    import math
    a = math.radians(yaw_deg)
    ca, sa = math.cos(a), math.sin(a)
    out = [(x, y)]
    for sx in (-0.5, 0.5):
        for sy in (-0.5, 0.5):
            lx, ly = sx * w, sy * d
            out.append((x + lx * ca - ly * sa, y + lx * sa + ly * ca))
    return out


def report(lay: Layout, arena: str, index: int) -> str:
    c = lay.cover(arena, index)
    x, y, z = (float(v) for v in c["center"])
    w, d, h = (float(v) for v in c["size"])
    decks = lay.decks_at(x, y)
    lines = ["%-8s base z %7.1f  size %.0fx%.0fx%.0f  at (%.1f, %.1f)  soft=%s"
             % ("%s#%d" % (arena, index), z, w, d, h, x, y, c.get("soft"))]
    under = [dk for dk in decks if float(dk["z"]) <= z + TOL]
    if not decks:
        lines.append("           no deck polygon contains the CENTRE  -> case (c)")
    for dk in decks:
        mark = "  <== ON" if abs(float(dk["z"]) - z) <= TOL else ""
        lines.append("           deck %-26s %-9s z %7.1f  poly %d pts%s"
                     % (dk["id"], dk["kind"], float(dk["z"]), len(dk["polygon"]), mark))
    if decks and not any(abs(float(dk["z"]) - z) <= TOL for dk in decks):
        top = max(under, key=lambda r: float(r["z"]))["z"] if under else None
        lines.append("           highest deck under it: %s  -> case (b), gap %.1f m"
                     % (top, z - top if top is not None else float("nan")))
    # The audit drops five points per instance (the centre and 40 % toward each corner), so a box
    # whose CENTRE is on the deck but whose corners overhang reads as floating. Name the overhang.
    on = [dk for dk in decks if abs(float(dk["z"]) - z) <= TOL]
    if on:
        pts = _corners(x, y, w, d, float(c.get("rot", 0.0)))
        off = [p for p in pts if not any(_inside(dk["polygon"], p[0], p[1])
                                         and not any(_inside(h, p[0], p[1]) for h in dk.get("holes", []))
                                         for dk in on)]
        if off:
            lines.append("           %d of 5 sample points are OFF the deck at z %.1f -> case (b): %s"
                         % (len(off), z, ", ".join("(%.1f, %.1f)" % p for p in off)))
    for s in lay.streets_at(x, y):
        lines.append("           street %-24s z %7.1f" % (s["id"], float(s.get("z", 0.0))))
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    lay = Layout()
    if not argv or argv[0] == "--all":
        ids = [("%s#%d" % (a["id"], i)) for a in lay.d["arenas"] for i in range(len(a.get("cover", [])))]
    else:
        ids = argv
    for cid in ids:
        arena, _, idx = cid.partition("#")
        if arena not in lay.arenas:
            print("no arena %s" % arena)
            continue
        if int(idx) >= len(lay.arenas[arena].get("cover", [])):
            print("%s has only %d cover rows" % (arena, len(lay.arenas[arena].get("cover", []))))
            continue
        print(report(lay, arena, int(idx)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
