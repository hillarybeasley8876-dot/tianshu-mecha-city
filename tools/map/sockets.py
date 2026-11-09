"""Arena spawn sockets (lead, r5).

A socket is where a 4 m-radius agent appears, so it may not stand in a hole, under a deck or
inside a cover piece. Every socket sits on its arena's own TOP walkable surface - the tier the
fight happens on - at least 16 m off a wall, with 16 m of clear air above it and 12 m of free
floor around it (no cover piece within 8 m), so the agent lands on a navmesh island that
reaches the arena centre.

The sockets are placed last, after the cover top-up and the tower clear-out: every rule here
is a statement about the finished layout, not about the arena outline.
"""
from __future__ import annotations

import math

from shapely.geometry import Point, Polygon
from shapely.ops import unary_union
from shapely.strtree import STRtree

import arenas as arena_stage
import geom
import mapconst as C

WALL_CLEAR = 16.0     # socket -> the wall the surface ends at
AIR_CLEAR = 16.0      # nothing may span the socket's air below this
FLOOR_CLEAR = 12.0    # free floor radius the socket stands in the middle of
COVER_CLEAR = 8.0     # socket -> the nearest cover piece's own box
SEP_STEPS = (56.0, 40.0, 28.0)   # socket -> socket, relaxed a step at a time
WALL_STEPS = (16.0, 12.0, 8.0)
GRID = 12.0           # candidate lattice over the field
# MAP §3 `spawn_sockets[].kind`
KINDS = ("hatch", "door", "lift", "tunnel", "drop", "breach")


def reserve(rules: dict, decks: list[dict],
            outlines: dict[str, list]) -> tuple[dict[str, list[dict]], Polygon]:
    """Pick each arena's socket sites before its cover exists, plus the floor they keep.

    An arena floor carries a cover piece every 40-60 m, so by the time the cover is in there
    is often nowhere left that is 8 m from a piece - the Megablock Canyon lost a third of its
    sockets that way. Choosing the sites first and letting the cover fill in around them is
    the same trick as the connector keep-clear spheres (r4): the discs come back as a keep-out
    for every cover pass, and `build` re-checks each site against the finished layout.
    """
    sites: dict[str, list[dict]] = {}
    discs: list[Polygon] = []
    for aid, spec in rules["arenas"].items():
        shell = {"id": aid, "polygon": outlines[aid]}
        z, surface = fight_surface(shell, spec, decks)
        rows = _ring(aid, surface, tuple(spec["center"]), int(spec["sockets"]))
        sites[aid] = [{"pos": [round(x, 1), round(y, 1), z], "min_separation": round(sep, 1)}
                      for x, y, sep in rows]
        discs += [Point(x, y).buffer(COVER_CLEAR, quad_segs=8) for x, y, _sep in rows]
    return sites, unary_union(discs) if discs else Polygon()


def _ring(aid: str, surface: Polygon, centre: tuple[float, float],
          count: int) -> list[tuple[float, float, float]]:
    """Socket sites on an empty floor: (x, y, separation they were placed at), rim first."""
    field, _wall = _field(aid, surface)
    if field.is_empty:
        return []
    island = _island(surface, centre).buffer(1.0)
    mid = (surface.centroid.x, surface.centroid.y)
    rows = sorted(_candidates(field), key=lambda p: -math.dist(p, mid))
    out: list[tuple[float, float, float]] = []
    for sep in SEP_STEPS:
        for x, y in rows:
            if len(out) >= count:
                return out
            if any(math.dist((x, y), (o[0], o[1])) < sep for o in out):
                continue
            if island.contains(Point(x, y)):
                out.append((x, y, sep))
    return out


def build(arenas: list[dict], decks: list[dict], buildings: list[dict], rules: dict,
          reserved: dict[str, list[dict]]) -> int:
    """Give every arena its spawn sockets; returns how many were placed."""
    solids, tree = _solids(decks, buildings, arenas)
    placed = 0
    for arena in arenas:
        spec = rules["arenas"][arena["id"]]
        z, surface = fight_surface(arena, spec, decks)
        found = _sockets(arena, spec, surface, z, int(spec["sockets"]), solids, tree,
                         reserved.get(arena["id"], []))
        arena["spawn_sockets"] = found
        arena["fight_tier"] = z
        placed += len(found)
        if len(found) < int(spec["sockets"]):
            print(f"  WARNING {arena['id']}: {len(found)}/{spec['sockets']} spawn sockets "
                  f"on the +{z:.0f} fight tier ({surface.area:.0f} m2)")
    return placed


def fight_surface(arena: dict, spec: dict, decks: list[dict]) -> tuple[float, Polygon]:
    """The floor the fight happens on, as (z, polygon): the arena's main tier.

    `arena_stage.surfaces` puts the main tier first - the arena polygon minus its own lower
    tiers (the Container Yard's dock is a cut in the ground, not a floor to appear on) and
    minus the voids of its own floor deck (the Crown's core drum). "Top surface" is then
    enforced where it matters, per socket: `_ok` refuses any point with a deck, a bridge or a
    canopy in the 16 m of air above it, so a socket never appears under an upper tier.
    """
    area = geom.poly(arena["polygon"])
    main = float(spec["main_tier"])
    rows = [(z, poly) for z, poly in arena_stage.surfaces(arena["id"], area, spec, decks)
            if abs(z - main) < 1.0]
    return max(rows or [(main, area)], key=lambda r: r[1].area)


def _sockets(arena: dict, spec: dict, surface: Polygon, z: float, count: int,
             solids: list[tuple[Polygon, float, float]], tree: STRtree,
             reserved: list[dict]) -> list[dict]:
    """The reserved sites that survived the finished layout, then replacements for the rest.

    A site is only given up when something late landed on it - a skybridge over its air, a
    deck column in its floor. The replacements come off the same 12 m grid, rim first, and the
    separation is relaxed a step at a time so a long thin arena can still fill its count.
    """
    field, wall = _field(arena["id"], surface)
    if field.is_empty:
        return []
    island = _island(surface, tuple(spec["center"])).buffer(1.0)
    out: list[dict] = []
    for site in reserved:
        x, y = site["pos"][0], site["pos"][1]
        if len(out) >= count:
            break
        if _legal(x, y, z, field, island, solids, tree):
            out.append(_record(arena, x, y, z, wall, site["min_separation"], len(out)))
    centre = (surface.centroid.x, surface.centroid.y)
    rows = sorted(_candidates(field), key=lambda p: -math.dist(p, centre))
    for sep in SEP_STEPS:
        for x, y in rows:
            if len(out) >= count:
                return out
            if any(math.dist((x, y), (s["pos"][0], s["pos"][1])) < sep for s in out):
                continue
            if _legal(x, y, z, field, island, solids, tree):
                out.append(_record(arena, x, y, z, wall, sep, len(out)))
    return out


def _record(arena: dict, x: float, y: float, z: float, wall: float, sep: float,
            index: int) -> dict:
    """One spawn socket record (MAP §3 `spawn_sockets`, plus the clearances r5 asks for)."""
    return {"id": f"{arena['id']}_sp{index + 1}", "pos": [round(x, 1), round(y, 1), z],
            "kind": KINDS[index % len(KINDS)], "surface_z": z,
            "wall_clear": round(wall, 1), "air_clear": AIR_CLEAR,
            "floor_clear": FLOOR_CLEAR, "min_separation": round(sep, 1)}


def _legal(x: float, y: float, z: float, field: Polygon, island: Polygon,
           solids: list[tuple[Polygon, float, float]], tree: STRtree) -> bool:
    """On the field (16 m off the wall), on the island that reaches the arena centre, and
    clear of every solid in the finished layout."""
    here = Point(x, y)
    return field.contains(here) and island.contains(here) and _ok(x, y, z, solids, tree)


def _candidates(field: Polygon) -> list[tuple[float, float]]:
    """Every point of a 12 m grid over the field, swept twice so nothing sits on one lattice."""
    minx, miny, maxx, maxy = field.bounds
    out: list[tuple[float, float]] = []
    for dx, dy in ((0.0, 0.0), (GRID / 2, GRID / 2)):
        y = miny + dy
        while y <= maxy:
            x = minx + dx
            while x <= maxx:
                if field.contains(Point(x, y)):
                    out.append((x, y))
                x += GRID
            y += GRID
    return out


def _ok(x: float, y: float, z: float, solids: list[tuple[Polygon, float, float]],
        tree: STRtree) -> bool:
    """The agent's own column: clear air above it, and nothing standing on the floor within
    8 m of it. The query disc is the 8 m gap, not the 4 m agent, so a piece 6 m away is
    seen and rejected."""
    here = Point(x, y)
    disc = here.buffer(COVER_CLEAR, quad_segs=8)
    for idx in tree.query(disc):
        poly, z0, z1 = solids[idx]
        if z1 <= z + 0.5 or z0 >= z + AIR_CLEAR:
            continue                       # under the floor, or over the agent's air
        if z0 > z + 0.5:
            if poly.intersects(here.buffer(C.CAPSULE_R, quad_segs=8)):
                return False               # a deck or bridge spans the socket
        elif poly.distance(here) < COVER_CLEAR:
            return False                   # a solid stands in the free floor
    return True


def _field(aid: str, surface: Polygon) -> tuple[Polygon, float]:
    """The part of the surface a socket may stand on: 16 m off the wall, or - printed, never
    silently - the widest erosion that leaves any floor at all."""
    for wall in WALL_STEPS:
        field = surface.buffer(-wall, quad_segs=16)
        if not field.is_empty:
            if wall < WALL_CLEAR:
                print(f"  WARNING {aid}: the fight tier only leaves {wall:.0f} m off the wall "
                      f"(want {WALL_CLEAR:.0f} m)")
            return field, wall
    print(f"  WARNING {aid}: the fight tier is too small for a spawn socket")
    return Polygon(), WALL_STEPS[-1]


def _island(surface: Polygon, centre: tuple[float, float]) -> Polygon:
    """The walkable island the arena centre stands on: a socket has to be reachable from the
    middle of the arena without leaving the floor (the lead's navmesh island)."""
    eroded = surface.buffer(-C.CAPSULE_R, quad_segs=8)
    parts = [p for p in getattr(eroded, "geoms", [eroded])
             if not p.is_empty and p.area > 1.0]
    return min(parts, key=lambda p: p.distance(Point(centre))) if parts else surface


def _solids(decks: list[dict], buildings: list[dict],
            arenas: list[dict]) -> tuple[list[tuple[Polygon, float, float]], STRtree]:
    """Every solid with its z span, as the checks see them: buildings, cover pieces, deck
    slabs (holes cut out) and deck columns."""
    items: list[tuple[Polygon, float, float]] = []
    for b in buildings:
        items.append((geom.rect(tuple(b["center"]), tuple(b["size"]), b.get("rot", 0.0)),
                      b["base_z"], b["base_z"] + b["height"]))
    for arena in arenas:
        for piece in arena["cover"]:
            c = piece["center"]
            items.append((geom.rect((c[0], c[1]), (piece["size"][0], piece["size"][1])),
                          c[2], c[2] + piece["size"][2]))
    for deck in decks:
        area = geom.poly(deck["polygon"])
        for hole in deck.get("holes", []):
            area = area.difference(geom.poly(hole))
        items.append((area, deck["z"] - deck["thickness"], deck["z"]))
        for col in deck.get("columns", []):
            items.append((geom.rect((col[0], col[1]), (20.0, 20.0)), 0.0, deck["z"]))
    return items, STRtree([i[0] for i in items])
