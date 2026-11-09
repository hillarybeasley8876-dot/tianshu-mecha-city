#!/usr/bin/env python3
"""measure_arena.py - C13/C14 proxies for the arena data (docs/MAP.md §5, lead r4).

city-build runs the real C13 (headroom over navmesh samples) and C14 (a >= 20 m collider
within 60 m) against the built collision. This runs the same two questions against the layout
in 2.5D, so the layout can be judged before the city is rebuilt:

  * headroom: for every arena sample - taken on the surface it really stands on, the topmost
    deck under the point, which is what C13's ray from +320 m finds - the distance up to the
    first deck or building above it. The gate is 32 m inside an arena, 24 m outside.
  * cover: the nearest collider that rises >= 20 m over the sample, arena cover or building
    alike, as `_cover_near` casts for it.

Both are sampling measurements, not checks: validate_layout.py owns the pass/fail.

Usage: uv run --with shapely python3 tools/map/measure_arena.py
"""
from __future__ import annotations

import json
import math
import os
import random
import sys

from shapely.geometry import Point

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geom  # noqa: E402
import hive_rule  # noqa: E402
import keepclear  # noqa: E402
import mapconst as C  # noqa: E402
from sight import EYE, arena_samples, arena_surfaces, nav_samples  # noqa: E402

SAMPLES = 200
SEED = 4242


def boxes(layout: dict) -> list[tuple]:
    return [(geom.rect(tuple(b["center"]), tuple(b["size"]), b.get("rot", 0.0)),
             b["base_z"], b["base_z"] + b["height"], b["id"]) for b in layout["buildings"]]


def slabs(layout: dict) -> list[tuple]:
    return [(geom.poly(d["polygon"]), d["z"] - d["thickness"], d["id"])
            for d in layout["decks"]]


def headroom(x: float, y: float, floor: float, decks: list, builds: list) -> tuple[float, str]:
    """The clear height over this point, and what stops it."""
    here = Point(x, y)
    best, who = math.inf, "sky"
    for poly, under, ident in decks:
        if under > floor + 0.5 and poly.contains(here) and under - floor < best:
            best, who = under - floor, ident
    for box, _z0, z1, ident in builds:
        if z1 > floor + 0.5 and box.contains(here) and z1 - floor < best:
            best, who = z1 - floor, ident
    return best, who


def main() -> int:
    with open(C.LAYOUT_JSON, encoding="utf-8") as fh:
        layout = json.load(fh)
    rng = random.Random(SEED)
    decks, builds = slabs(layout), boxes(layout)
    print(f"C13 proxy — headroom over {SAMPLES} samples per arena "
          f"(gate {C.ARENA_DECK_CLEAR:.0f} m inside an arena)")
    total = under = 0
    for arena in layout["arenas"]:
        area = geom.poly(arena["polygon"])
        pts = arena_samples(area, arena, rng, SAMPLES, arena_surfaces(arena, layout["decks"]))
        low = [(headroom(x, y, z - EYE, decks, builds), (x, y)) for x, y, z in pts]
        bad = [row for row in low if row[0][0] < C.ARENA_DECK_CLEAR]
        worst = min(low, key=lambda r: r[0][0])
        total += len(pts)
        under += len(bad)
        print(f"  {arena['id']:3s} {len(bad):3d}/{len(pts):3d} under {C.ARENA_DECK_CLEAR:.0f} m "
              f"({100 * len(bad) / len(pts):5.1f} %)   worst {worst[0][0]:6.1f} m under "
              f"{worst[0][1]} at ({worst[1][0]:.0f},{worst[1][1]:.0f})")
    print(f"  all arenas {under}/{total} = {100 * under / total:.1f} % "
          f"(C13 tolerates 5 % of every sample on the map)")

    pts = nav_samples(layout, 60.0)
    bad = [p for p in pts if headroom(p[0], p[1], p[2] - EYE, decks, builds)[0]
           < C.UNDER_DECK_CLEAR]
    print(f"  nav samples outside the arenas: {len(bad)}/{len(pts)} = "
          f"{100 * len(bad) / len(pts):.1f} % under {C.UNDER_DECK_CLEAR:.0f} m")

    print("C14 proxy — a collider >= 20 m tall within 60 m of the sample")
    keep = keepclear.keep_out(layout["connectors"])
    for arena in layout["arenas"]:
        area = geom.poly(arena["polygon"])
        pts = arena_samples(area, arena, rng, SAMPLES, arena_surfaces(arena, layout["decks"]))
        full = [c for c in arena["cover"] if c["size"][2] >= C.FULL_COVER_H]
        covered = exempt = 0
        for x, y, z in pts:
            floor = z - EYE
            mine = [c for c in full if abs(c["center"][2] - floor) < 4.0] or full
            best = min((math.dist((x, y), (c["center"][0], c["center"][1])) for c in mine),
                       default=math.inf)
            for box, _z0, z1, _ident in builds:
                if z1 >= floor + C.FULL_COVER_H:
                    best = min(best, box.distance(Point(x, y)))
            if best <= C.COVER_NEAR:
                covered += 1
            elif (not keep.is_empty and keep.contains(Point(x, y))) or \
                    hive_rule.in_assault_ring((x, y, z), layout, EYE):
                exempt += 1        # the exemptions L4 applies (lead r4 / r6)
        note = "  (open boss arena: 0 % is the design)" if arena.get("open_cover") else ""
        print(f"  {arena['id']:3s} {covered:3d}/{len(pts):3d} = "
              f"{100 * covered / len(pts):5.1f} %  +{exempt} exempt = "
              f"{100 * (covered + exempt) / len(pts):5.1f} %{note}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
