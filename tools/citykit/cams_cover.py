"""Cameras on the arena cover, one pair per kit model, for the concept-fidelity sheet (lead r8 §4).

    python3 tools/citykit/cams_cover.py            # writes tools/citykit/cams_cover.json

The sheet the lead asked for is "concept | in-game at 15 m | in-game at 40 m", so the cameras have to
stand in front of a REAL placed instance of each model — not in a test street, where the material is
the same but the context is not. This reads `data/map/kit_assign.json`, and for every cover model it
picks the placed instance with the clearest line of sight, then puts a camera 15 m and 40 m out along
the direction that faces the middle of that arena.

Clearance is measured, not assumed: an arena is a field of 16-33 m boxes and a camera 15 m from one of
them is easily behind another. Every candidate instance is scored by the closest approach of any other
cover box to the camera-to-instance segment, and the best one wins.
"""
from __future__ import annotations

import json
import math
import os
from typing import Dict, List, Optional, Sequence, Tuple

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSIGN = os.path.join(ROOT, "data", "map", "kit_assign.json")
KIT = os.path.join(ROOT, "game", "world", "kit", "kit.json")
OUT = os.path.join(ROOT, "tools", "citykit", "cams_cover.json")
#: Standoff from the model's SURFACE, not from its centre — these are 10-25 m wide clusters, so a
#: camera 15 m from the centre of k02 is inside the tank.
DISTANCES = (15.0, 40.0)
#: Only cover within this radius of the instance can block the shot, so only it is scored.
BLOCK_R = 90.0


def _godot(p: Sequence[float]) -> Tuple[float, float, float]:
    """Layout (x, y, z-up) -> Godot (x, y-up, z). The same mapping `kit_placer._to_godot` uses."""
    return (float(p[0]), float(p[2]), -float(p[1]))


def _seg_dist(a: Tuple[float, float], b: Tuple[float, float], p: Tuple[float, float]) -> float:
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    den = dx * dx + dz * dz
    t = 0.0 if den < 1e-6 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - az) * dz) / den))
    return math.hypot(p[0] - (ax + t * dx), p[1] - (az + t * dz))


def _pick(rows: List[dict], model: str, boxes: List[Tuple[float, float, float]],
          centres: Dict[str, Tuple[float, float]]) -> Optional[Tuple[dict, Tuple[float, float]]]:
    """The placed instance of `model` with the clearest 40 m approach, and the direction to stand in."""
    best: Optional[Tuple[float, dict, Tuple[float, float]]] = None
    for row in rows:
        if row.get("model") != model:
            continue
        mid = centres[str(row.get("arena", ""))]
        for piece in row.get("pieces", []):
            g = _godot(piece["pos"])
            out = (g[0] - mid[0], g[2] - mid[1])
            n = math.hypot(*out)
            if n < 1e-3:
                continue
            out = (out[0] / n, out[1] / n)
            cam = (g[0] + out[0] * 60.0, g[2] + out[1] * 60.0)
            worst = min((_seg_dist(cam, (g[0], g[2]), (b[0], b[1]))
                         for b in boxes if math.hypot(b[0] - g[0], b[1] - g[2]) < BLOCK_R), default=99.0)
            if best is None or worst > best[0]:
                best = (worst, row, out)
    if best is None:
        return None
    return best[1], best[2]


def _centres(rows: List[dict]) -> Dict[str, Tuple[float, float]]:
    """The middle of each arena's cover field — the point the cameras stand outside of."""
    acc: Dict[str, List[Tuple[float, float]]] = {}
    for r in rows:
        for p in r.get("pieces", []):
            g = _godot(p["pos"])
            acc.setdefault(str(r.get("arena", "")), []).append((g[0], g[2]))
    return {k: (sum(x for x, _ in v) / len(v), sum(z for _, z in v) / len(v)) for k, v in acc.items()}


def build() -> List[dict]:
    assign = json.load(open(ASSIGN))
    kit = json.load(open(KIT))
    sizes = {m["id"]: m["size"] for m in kit["models"]}
    rows = assign["cover"]
    centres = _centres(rows)
    boxes = [(_godot(p["pos"])[0], _godot(p["pos"])[2], max(sizes.get(r["model"], [1, 1, 1])[:2]))
             for r in rows for p in r.get("pieces", [])]
    cams: List[dict] = []
    missing: List[str] = []
    for model in sorted({r["model"] for r in rows}):
        got = _pick(rows, model, boxes, centres)
        if got is None:
            missing.append(model)
            continue
        row, out = got
        piece = row["pieces"][0]
        g = _godot(piece["pos"])
        size = sizes[model]
        sc = float(piece["scale"][0])
        h = float(size[2]) * sc
        half = max(float(size[0]), float(size[1])) * sc * 0.5
        target = [round(g[0], 2), round(g[1] + h * 0.5, 2), round(g[2], 2)]
        for d in DISTANCES:
            r = half + d
            cams.append({"name": "%s_%dm" % (model, int(d)),
                         "pos": [round(g[0] + out[0] * r, 2), round(g[1] + h * 0.55 + r * 0.10, 2),
                                 round(g[2] + out[1] * r, 2)],
                         "look": target, "fov": 55})
    if missing:
        print("no placed instance for: %s" % ", ".join(missing))
    return cams


if __name__ == "__main__":
    out = build()
    with open(OUT, "w") as fh:
        json.dump(out, fh, indent=1)
    print("%d cameras -> %s" % (len(out), OUT))
    for c in out:
        print("  %-10s pos %s look %s" % (c["name"], c["pos"], c["look"]))
