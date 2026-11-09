"""Cameras on the cover line-up, for the concept-fidelity sheet (lead r8 §4).

    python3 tools/citykit/cams_lineup.py     # writes tools/citykit/cams_lineup.json

Reads the same `game/world/kit/tests/lineup.json` the scene reads, so the cameras cannot drift from
the row they are looking at. Two per model — 15 m and 40 m off the model's own surface, at half its
height — which is the pair the lead's gate asks for.

The sun is at a low dusk elevation, so the camera stands on the sunlit side: the azimuth is taken from
`--sun-azimuth` (the same 315 deg the scene's TimeOfDay uses) and flipped so the model is front-lit
rather than a silhouette.
"""
from __future__ import annotations

import json
import math
import os
from typing import Dict, List, Tuple

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LINEUP = os.path.join(ROOT, "game", "world", "kit", "tests", "lineup.json")
KIT = os.path.join(ROOT, "game", "world", "kit", "kit.json")
OUT = os.path.join(ROOT, "tools", "citykit", "cams_lineup.json")
DISTANCES = (15.0, 40.0)
#: The sun's azimuth in degrees, matching the scene's TimeOfDay. The camera stands 40 deg off it so the
#: model is three-quarter lit instead of flat-on or back-lit.
SUN_AZIMUTH = 315.0
CAM_AZIMUTH = SUN_AZIMUTH + 40.0


def _godot(p: List[float]) -> Tuple[float, float, float]:
    return (float(p[0]), float(p[2]), -float(p[1]))


def build() -> List[dict]:
    spec = json.load(open(LINEUP))
    sizes = {m["id"]: m["size"] for m in json.load(open(KIT))["models"]}
    origin = _godot(spec["origin"])
    step = float(spec["spacing"])
    a = math.radians(CAM_AZIMUTH)
    out: List[dict] = []
    for i, model in enumerate(spec["models"]):
        size = sizes[model]
        h = float(size[2])
        half = max(float(size[0]), float(size[1])) * 0.5
        base = (origin[0] + step * i, origin[1], origin[2])
        # The camera sits BELOW the model's mid-height and looks up, so the model is framed against
        # the dusk sky rather than against 640 m of skyline — the row floats (it is a look-dev rig, not
        # a place), and a level camera puts the whole city behind every subject.
        look = [round(base[0], 2), round(base[1] + h * 0.62, 2), round(base[2], 2)]
        for d in DISTANCES:
            r = half + d
            out.append({"name": "%s_%dm" % (model, int(d)),
                        "pos": [round(base[0] + math.sin(a) * r, 2),
                                round(base[1] + h * 0.28, 2),
                                round(base[2] + math.cos(a) * r, 2)],
                        "look": look, "fov": 42})
    return out


if __name__ == "__main__":
    cams = build()
    with open(OUT, "w") as fh:
        json.dump(cams, fh, indent=1)
    print("%d cameras -> %s" % (len(cams), OUT))
    for c in cams[:4]:
        print("  %-10s pos %s look %s" % (c["name"], c["pos"], c["look"]))
