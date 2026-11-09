"""What carries what: support towers for the named decks, mega-columns, Block 9.

Split out of props.py. Every plate in the city either stands on a tower, on mega-columns
(Hengsha, dossier §1.8), on the ground, or spans between two things - and says so in the
data, so the Blender build never has to guess (lead note, round 2, point 5).
"""
from __future__ import annotations

import math
import random

from shapely.geometry import Point, Polygon
from shapely.ops import unary_union

import geom
import mapconst as C


# Decks that stand on named towers rather than on piers (MAP §4: "Sky Garden deck +144
# between towers", "Crystal Bridge +176" spanning towers like Raffles City).
# The D7 decks are carried by towers.py, which plants them before the fill so they have the
# room to straddle the Ring Viaduct and the Skyrail (MAP §4 viaduct/rail-through).
SUPPORTS = (
    # deck id,        count, height, tier, footprint, district
    ("W4_foundry_l3", 2, 74.0, "B", 48.0, "D6"),
)
# The civic core is almost entirely plaza, avenue and Spire structure, so the towers that
# ring it are searched outward from the plaza centre and stay slim (48 m footprint).
PLAZA_RING = (0.0, -40.0, (200.0, 260.0, 320.0, 380.0))
PLAZA_TOWERS = 3
PLAZA_FOOT = 48.0


def support_towers(rules: dict, decks: list[dict], mask: Polygon, canal: Polygon,
                   arenas: list[dict], rng: random.Random,
                   caps: list[tuple[Polygon, float]] = ()) -> list[dict]:
    """Towers that carry a deck, plus the landmark towers ringing the Spire Plaza.

    Positions are searched on the deck's own inset ring and rejected against the corridor
    mask, so a declared tower can never sit on a street (check L2). Standing inside an arena
    is intended: the Sky Garden is a plate over its own towers.
    """
    glob = rules["global"]
    spire = tuple(glob["spire_center"])
    arena_area = unary_union([geom.poly(a["polygon"]) for a in arenas])
    by_id = {d["id"]: d for d in decks}
    out: list[dict] = []
    for deck_id, count, height, tier, foot, district in SUPPORTS:
        deck = by_id.get(deck_id)
        if deck is None:
            continue
        area = geom.poly(deck["polygon"])
        if area.is_empty:
            continue
        placed: list[tuple[float, float]] = []
        for reach in (12.0, 60.0, 110.0, 170.0):   # widen until enough ground is free
            if len(placed) >= count:
                break
            band = area.buffer(foot * 0.5 + reach)
            for pt, _nx, _ny in geom.inward_normals(band, max(count * 8, 16)):
                if len(placed) >= count:
                    break
                box = geom.rect(pt, (foot, foot))
                if box.intersects(mask) or box.intersects(canal):
                    continue
                # A rail or a viaduct flying over the site caps the tower. That is allowed -
                # straddle.adopt() grows such a carrier across the corridor and lets it rise
                # again (MAP §4 viaduct/rail-through) - but only where there is room to grow,
                # which is why the carriers are spaced well apart below.
                limits = [h for area, h in caps if box.intersection(area).area > 4.0]
                if limits and min(limits) < 24.0:
                    continue
                if max(abs(box.bounds[0]), abs(box.bounds[2])) > C.HALF - 20 or \
                        max(abs(box.bounds[1]), abs(box.bounds[3])) > C.HALF - 20:
                    continue
                if any(math.dist(pt, other) < foot * 2.6 for other in placed):
                    continue
                placed.append(pt)
                out.append(_tower(f"{district}_sup{len(out) + 1}", district, tier, pt, foot,
                                  0.0, min([height, geom.snap(
                                      blocks_spire_cap(spire, pt[0], pt[1],
                                                       glob["spire_cap_r"],
                                                       glob.get("spire_cap_top", 200.0)),
                                      4.0)]
                                      + [geom.snap(v, 4.0) for v in limits]), deck_id))
        deck["supported_by"] = [t["id"] for t in out if t.get("supports") == deck_id]
    cx, cy, radii = PLAZA_RING
    placed: list[tuple[float, float]] = []
    for radius in radii:
        for pt, _nx, _ny in geom.inward_normals(Point(cx, cy).buffer(radius), PLAZA_TOWERS * 6):
            if len(placed) >= PLAZA_TOWERS:
                break
            box = geom.rect(pt, (PLAZA_FOOT, PLAZA_FOOT))
            if box.intersects(mask) or box.intersects(canal) or box.intersects(arena_area) \
                    or max(abs(pt[0]), abs(pt[1])) > C.HALF - 60:
                continue
            if any(math.dist(pt, other) < 120.0 for other in placed):
                continue
            cap = blocks_spire_cap(spire, pt[0], pt[1], glob["spire_cap_r"],
                                   glob.get("spire_cap_top", 200.0))
            # 128 m (the L4 datum) keeps the civic towers under the Spire's silhouette from
            # street level, and any rail or vista slot crossing the site caps them further
            height = min(128.0, geom.snap(cap, 4.0))
            limits = [h for area, h in caps if box.intersection(area).area > 4.0]
            if limits:
                height = geom.snap(min(height, min(limits)), 4.0)
            if height < 24.0:
                continue
            placed.append(pt)
            out.append(_tower(f"D4_plaza_tower{len(placed)}", "D4", "C", pt, PLAZA_FOOT, 0.0,
                              height, "A3_terrace"))
        if len(placed) >= PLAZA_TOWERS:
            break
    return out


def blocks_spire_cap(center: tuple[float, float], x: float, y: float, cap_r: float,
                     top: float = 208.0) -> float:
    """Mirror of lots.spire_cap so declared towers obey the same skyline break."""
    r = math.hypot(x - center[0], y - center[1])
    return 1e9 if r >= cap_r else max(48.0, top * (r / cap_r))


COLUMN_FOOT = 20.0
COLUMN_SPACING = 88.0


SPIRE_CARRIED = ("S3_collar", "S4_roof_ring", "B1_crown")


def deck_columns(decks: list[dict], mask: Polygon, canal: Polygon,
                 plateau: Polygon | None = None) -> int:
    """Give every deck something to stand on: towers, mega-columns, the ground, or a span.

    A plate with nothing under it is a floating rectangle in the data, and the Blender build
    has to know what carries it (lead note, round 2, point 5).
    """
    """Mega-columns under every high plate that no tower carries (Hengsha, dossier §1.8).

    Columns are placed on a lattice inside the deck footprint, skipping the corridor mask
    so they never block a street, and skipping the water.
    """
    added = 0
    for deck in decks:
        if deck["id"] in SPIRE_CARRIED:
            deck["supported_by"] = ["spire"]
            continue
        carrier = NAMED_CARRIERS.get(deck["id"])
        if carrier is None:
            # an island cut off a named-carrier deck by `perforate_decks` is carried by the
            # same landmark: it is a piece of the same plate, not a new floating slab
            carrier = next((v for k, v in NAMED_CARRIERS.items()
                            if deck["id"].startswith(f"{k}_b")), None)
        if carrier is not None:
            deck["supported_by"] = [carrier]
            continue
        if deck["id"] in SPANS:
            deck["span"] = SPANS[deck["id"]]      # a bridge spans; that is what it is
            continue
        if plateau is not None and deck["z"] <= 34.0 and \
                plateau.contains(geom.poly(deck["polygon"]).representative_point()):
            deck["on_ground"] = True
            continue
        if deck.get("canopy"):
            # an arena canopy is an arcade over the roadway: it stands on columns where the
            # street is wide enough to keep 24 m of navigable core between them, and on the
            # two facing frontages where it is not
            area = geom.poly(deck["polygon"])
            cols = _lattice_columns(area, mask, canal,
                                    deck.get("column_spacing", COLUMN_SPACING))
            if cols:
                deck["columns"] = cols
                added += len(cols)
            else:
                deck["span"] = "street walls"
            continue
        if deck.get("supported_by"):
            continue
        if deck["z"] <= 8.0 or deck.get("on_plateau"):
            deck["on_ground"] = True       # a pit floor, a pier or a plaza laid on the ground
            continue
        area = geom.poly(deck["polygon"])
        for hole in deck.get("holes", []):
            area = area.difference(geom.poly(hole))
        inner = area.buffer(-COLUMN_FOOT)
        if inner.is_empty:
            # too thin for a lattice: a corner column or a declared span, never nothing
            cols = _corner_columns(area, mask)
            if cols:
                deck["columns"] = cols
                added += len(cols)
            else:
                deck["span"] = "adjacent buildings"
            continue
        cols = _lattice_columns(inner, mask, canal, COLUMN_SPACING)
        if not cols:
            cols = _corner_columns(area, mask)
        if cols:
            deck["columns"] = cols
            added += len(cols)
        else:
            deck["span"] = "adjacent buildings"
    return added


SPANS = {"F5_crystal": "the two Crystal towers", "M3_bridge_mid": "the canyon megablocks"}
NAMED_CARRIERS = {"K2_knot_l1": "interchange_knot", "K3_knot_l2": "interchange_knot",
                  "K4_knot_flyover": "interchange_knot", "K5_knot_crown": "interchange_knot",
                  "H3_crane_cab": "harbor_cranes", "W5_stack_perch": "reactor_stacks",
                  "M4_roofline": "D5 megablock roof", "O5_pagoda_crown": "stilt_pagoda"}


def _lattice_columns(area: Polygon, mask: Polygon, canal: Polygon,
                     spacing: float) -> list[list[float]]:
    """Columns on a lattice inside the plate, never in a corridor or in the water."""
    inner = area.buffer(-COLUMN_FOOT)
    if inner.is_empty:
        return []
    minx, miny, maxx, maxy = inner.bounds
    out: list[list[float]] = []
    y = miny
    while y <= maxy:
        x = minx
        while x <= maxx:
            if inner.contains(Point(x, y)) and not geom.rect((x, y), (COLUMN_FOOT, COLUMN_FOOT)
                                                             ).intersects(mask) \
                    and not geom.rect((x, y), (COLUMN_FOOT, COLUMN_FOOT)).intersects(canal):
                out.append([round(x, 1), round(y, 1)])
            x += spacing
        y += spacing
    return out


def _corner_columns(area: Polygon, mask: Polygon) -> list[list[float]]:
    """Last resort: a column at each corner of the plate, clear of the streets."""
    inner = area.buffer(-28.0)
    parts = [g for g in getattr(inner, "geoms", [inner]) if isinstance(g, Polygon)]
    out = []
    for part in parts:
        for x, y in list(part.exterior.coords)[:-1]:
            box = geom.rect((x, y), (COLUMN_FOOT, COLUMN_FOOT))
            if not box.intersects(mask):
                out.append([round(x, 1), round(y, 1)])
    return out


def _tower(ident: str, district: str, tier: str, center: tuple[float, float], foot: float,
           base_z: float, height: float, deck_id: str) -> dict:
    return {"id": ident, "district": district, "tier": tier, "archetype": "podium_tower",
            "center": [round(center[0], 1), round(center[1], 1)],
            "size": [foot, foot], "rot": 0.0, "base_z": base_z, "height": height,
            "roof_walkable": height >= 120.0, "supports": deck_id, "breaches": []}


