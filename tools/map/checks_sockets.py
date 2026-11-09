"""L11 - arena spawn sockets (docs/MAP.md §5, lead r5).

Split out of validate_layout.py the way checks_arena.py is: it is a sampling check over the
finished layout, and keeping it here leaves the validator itself a readable list of checks.
"""
from __future__ import annotations

import math

from shapely.geometry import Point, Polygon
from shapely.strtree import STRtree

import geom
import mapconst as C
import sockets
from sight import arena_surfaces, blockers

FAIL: list[str] = []
REPORT_REACH = 40.0   # how far L11 looks for the nearest solid, to print a real number


def check_l11(layout: dict) -> dict:
    """Spawn sockets (lead, r5): on the arena's top walkable surface, off the walls, with
    clear air above and free floor around, on an island that reaches the arena centre.

    Re-derived from the written JSON, not from the generator's own geometry: `sight` builds
    its own surfaces and the solids come from `blockers`, so a bug in the socket stage cannot
    hide here.
    """
    tree, items = blockers(layout)
    stats: dict[str, dict] = {}
    for arena in layout["arenas"]:
        aid = arena["id"]
        sockets_rows = arena.get("spawn_sockets") or []
        if len(sockets_rows) < 3:
            FAIL.append(f"L11 {aid}: {len(sockets_rows)} spawn sockets (need >= 3)")
        rows = [(poly, z) for poly, z in arena_surfaces(arena, layout["decks"])
                if abs(z - arena.get("main_tier", min(arena["tiers"]))) < 1.0]
        surface, z = max(rows or [(geom.poly(arena["polygon"]),
                                   arena.get("main_tier", min(arena["tiers"])))],
                         key=lambda r: r[0].area)
        island = _island(surface, geom.poly(arena["polygon"]).centroid)
        worst = {"wall": 1e9, "cover": 1e9, "sep": 1e9}
        for s in sockets_rows:
            x, y, sz = s["pos"]
            here = Point(x, y)
            if abs(sz - z) > 1.0:
                FAIL.append(f"L11 {s['id']} sits at {sz:+.0f} but {aid}'s fight tier is "
                            f"{z:+.0f}")
            if not surface.contains(here):
                FAIL.append(f"L11 {s['id']} at ({x:.0f},{y:.0f}) is off {aid}'s walkable "
                            f"surface")
                continue
            wall = surface.boundary.distance(here)
            worst["wall"] = min(worst["wall"], wall)
            if wall < sockets.WALL_CLEAR - 0.5:
                FAIL.append(f"L11 {s['id']} stands {wall:.1f} m from the edge of {aid} "
                            f"(want >= {sockets.WALL_CLEAR:.0f} m)")
            if not surface.buffer(-sockets.FLOOR_CLEAR).contains(here):
                FAIL.append(f"L11 {s['id']} has less than {sockets.FLOOR_CLEAR:.0f} m of free "
                            f"floor around it")
            if not island.buffer(1.0).contains(here):
                FAIL.append(f"L11 {s['id']} is on an island that does not reach the middle of "
                            f"{aid}")
            near, span = _socket_solids(tree, items, x, y, z)
            worst["cover"] = min(worst["cover"], near)
            if near < sockets.COVER_CLEAR - 0.5:
                FAIL.append(f"L11 {s['id']} has a solid {near:.1f} m away "
                            f"(want >= {sockets.COVER_CLEAR:.0f} m)")
            if span:
                FAIL.append(f"L11 {s['id']} has something in the {sockets.AIR_CLEAR:.0f} m of "
                            f"air above it at +{span:+.0f}")
        for i, a in enumerate(sockets_rows):
            for b in sockets_rows[i + 1:]:
                worst["sep"] = min(worst["sep"], math.dist(a["pos"][:2], b["pos"][:2]))
        if worst["sep"] < min(sockets.SEP_STEPS):
            FAIL.append(f"L11 {aid}: two spawn sockets are {worst['sep']:.1f} m apart "
                        f"(the stage never places them closer than "
                        f"{min(sockets.SEP_STEPS):.0f} m)")
        stats[aid] = {"sockets": len(sockets_rows), "tier": z,
                      "wall": round(worst["wall"], 1), "cover": round(worst["cover"], 1),
                      "sep": round(min(worst["sep"], 1e4), 1)}
    return stats


def _socket_solids(tree: STRtree, items: list[tuple[Polygon, float, float]],
                   x: float, y: float, z: float) -> tuple[float, float]:
    """(distance to the nearest solid standing on the socket's floor, z of the lowest solid
    spanning the air above it - 0 when the air is clear). The query is wider than the 8 m rule
    so the printed number is a real distance, not a sentinel."""
    here = Point(x, y)
    agent = here.buffer(C.CAPSULE_R, quad_segs=8)
    near, span = 1e9, 0.0
    for idx in tree.query(here.buffer(REPORT_REACH, quad_segs=8)):
        poly, z0, z1 = items[idx]
        if z1 <= z + 0.5 or z0 >= z + sockets.AIR_CLEAR:
            continue
        if z0 > z + 0.5:
            if poly.intersects(agent):
                span = min(span, z0) if span else z0
        else:
            near = min(near, poly.distance(here))
    return near, span


def _island(surface: Polygon, centre: Point) -> Polygon:
    """The walkable island a socket must share with the middle of its arena: the surface
    eroded by the agent's own radius, so a 4 m agent can walk between them."""
    eroded = surface.buffer(-C.CAPSULE_R, quad_segs=8)
    parts = [p for p in getattr(eroded, "geoms", [eroded])
             if not p.is_empty and p.area > 1.0]
    return min(parts, key=lambda p: p.distance(centre)) if parts else surface
