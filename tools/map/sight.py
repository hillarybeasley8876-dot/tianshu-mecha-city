"""2.5D sight and sampling helpers for the layout checks (docs/MAP.md §5, dossier C14/C15).

Occlusion is tested against each box's own z span, so passing *under* a high deck is clear
sky while a ray through a deck slab, a cover piece or a tower is blocked.
"""
from __future__ import annotations

import math
import random

from shapely.geometry import LineString, Point, Polygon
from shapely.strtree import STRtree

import geom
import mapconst as C

EYE = 12.0                 # sample eye height above the surface
NAV_STEP = 40.0


def box_of(b: dict) -> Polygon:
    return geom.rect(tuple(b["center"]), tuple(b["size"]), b.get("rot", 0.0))


def blockers(layout: dict) -> tuple[STRtree, list[tuple[Polygon, float, float]]]:
    """Every opaque box with its z span: buildings, cover pieces, deck slabs, columns."""
    items: list[tuple[Polygon, float, float]] = []
    for b in layout["buildings"]:
        items.append((box_of(b), b["base_z"], b["base_z"] + b["height"]))
    for arena in layout["arenas"]:
        for piece in arena["cover"]:
            c = piece["center"]
            items.append((geom.rect((c[0], c[1]), (piece["size"][0], piece["size"][1])),
                          c[2], c[2] + piece["size"][2]))
    for deck in layout["decks"]:
        area = geom.poly(deck["polygon"])
        for hole in deck.get("holes", []):
            area = area.difference(geom.poly(hole))
        items.append((area, deck["z"] - deck["thickness"], deck["z"]))
        for col in deck.get("columns", []):
            items.append((geom.rect((col[0], col[1]), (20.0, 20.0)), 0.0, deck["z"]))
    return STRtree([i[0] for i in items]), items


def visible(a: tuple[float, float, float], b: tuple[float, float, float],
            tree: STRtree, items: list[tuple[Polygon, float, float]]) -> bool:
    """2.5D line of sight: blocked only where the ray's own z crosses a box's z span.

    Passing *under* a high deck is clear sky, not an occluder - only the box's own height
    band counts, which is what makes decks, canopies and raised rails behave.
    """
    ray = LineString([(a[0], a[1]), (b[0], b[1])])
    for idx in tree.query(ray):
        poly, z0, z1 = items[idx]
        if not poly.intersects(ray):
            continue
        cut = poly.intersection(ray)
        for part in getattr(cut, "geoms", [cut]):
            if part.is_empty:
                continue
            coords = list(getattr(part, "coords", [])) or [(part.x, part.y)]
            for px, py in coords:
                t = 0.0 if ray.length == 0 else ray.project(Point(px, py)) / ray.length
                z = a[2] + (b[2] - a[2]) * t
                if z0 - 0.5 < z < z1 + 0.5:
                    return False
    return True


def nav_samples(layout: dict, step: float = NAV_STEP) -> list[tuple[float, float, float]]:
    """Points a player can stand on: along corridors, on decks, on walkable roofs."""
    out: list[tuple[float, float, float]] = []
    for group in ("streets", "viaducts", "rails", "tunnels"):
        for item in layout[group]:
            for x, y in geom.sample_along(item["points"], step, step / 2):
                out.append((x, y, item["z"] + EYE))
    for deck in layout["decks"]:
        area = geom.poly(deck["polygon"])
        for hole in deck.get("holes", []):
            area = area.difference(geom.poly(hole))
        minx, miny, maxx, maxy = area.bounds
        y = miny + step / 2
        while y <= maxy:
            x = minx + step / 2
            while x <= maxx:
                if area.contains(Point(x, y)):
                    out.append((x, y, deck["z"] + EYE))
                x += step
            y += step
    for b in layout["buildings"]:
        if b["roof_walkable"]:
            out.append((b["center"][0], b["center"][1], b["base_z"] + b["height"] + EYE))
    return out


def arena_samples(area: Polygon, arena: dict, rng: random.Random,
                   count: int = 160,
                   surfaces: list[tuple[Polygon, float]] | None = None
                   ) -> list[tuple[float, float, float]]:
    """Sample points on the arena's surfaces, each on the surface it really stands on.

    An arena is not one floor: the Container Yard has a dock at -12 and canopy roofs at +40
    over the same plan, and C13/C14 drop their ray from +320 m onto whatever is there. With
    `surfaces` the sample takes the topmost surface under the point, exactly like that ray;
    without it, the nearest cover piece is the cheap answer.
    """
    cover = arena["cover"]
    pts = []
    minx, miny, maxx, maxy = area.bounds
    while len(pts) < count:
        p = (rng.uniform(minx, maxx), rng.uniform(miny, maxy))
        if not area.contains(Point(p)):
            continue
        here = Point(p)
        if surfaces:
            on = [sz for poly, sz in surfaces if poly.contains(here)]
            if not on:
                continue      # no walkable surface under it: a ramp trench, a light well
            z = max(on)
        elif cover:
            z = float(min(cover, key=lambda c: math.dist(p, c["center"][:2]))["center"][2])
        else:
            z = float(max(set(arena["tiers"]), key=arena["tiers"].count))
        pts.append((round(p[0], 1), round(p[1], 1), z + EYE))
    return pts


def arena_surfaces(arena: dict, decks: list[dict],
                   cut: Polygon | None = None) -> list[tuple[Polygon, float]]:
    """(polygon, z) for every walkable surface inside an arena outline.

    The ground is the main tier minus the arena's own lower tiers - the Container Yard's
    dock floor is a cut in the ground, not a slab lying on it - and every deck that overlaps
    the outline is a surface of its own, canopy roofs included. `cut` is the area the ground
    crust is cut out of (`floors.cut_ground`): a descending ramp's trench is a hole in the
    ground, and a sample taken over one is not standing on anything (lead, r9).
    """
    area = geom.poly(arena["polygon"])
    main = float(arena.get("main_tier", min(arena["tiers"])))
    tiers = [float(t) for t in arena["tiers"]]
    out: list[tuple[Polygon, float]] = []
    ground = area
    for deck in decks:
        piece = geom.poly(deck["polygon"])
        for hole in deck.get("holes", []):
            piece = piece.difference(geom.poly(hole))
        piece = piece.intersection(area)
        if piece.area <= C.ARENA_SURFACE_MIN:
            continue
        if deck["z"] < main and deck["z"] in tiers:
            ground = ground.difference(piece)
        if deck["z"] > main or deck["z"] in tiers:
            out.append((piece, float(deck["z"])))
    if cut is not None and not cut.is_empty and abs(main) < 0.5:
        ground = ground.difference(cut)
    return [(ground, main)] + out


