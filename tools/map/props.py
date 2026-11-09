"""Props stage: the set dressing that is not an arena - the landmarks, Block 9 and its
Liziba station, the skyhook anchors, the player start and the skyline ring
(docs/MAP.md §2-§3).

The arenas themselves live in arenas.py; the two `build_arenas` / `cover_pass` entry points
are re-exported here so the orchestrator keeps one import for "the props". The Hive Spires
moved out to hives.py: since the lead's r6 note they are a siting problem, not a constant.
"""
from __future__ import annotations

import math
import random

from shapely.geometry import Point, Polygon
from shapely.ops import unary_union

import geom
import mapconst as C
from arenas import build_arenas, arena_outlines, cover_pass, set_soft, settle_cover  # noqa: F401
from supports import deck_columns, support_towers  # noqa: F401  (re-exported)

# Block 9's openings (MAP §3 v2 `holes`): corridor width + 2 x 4 m, and MAP §4's headroom -
# 40 m over a viaduct deck, 32 m over the rail and over a plateau road.
BLOCK9_MARGIN = 4.0
BLOCK9_VIA_CLEAR = 40.0
BLOCK9_RAIL_CLEAR = 32.0
BLOCK9_STREET_CLEAR = 32.0


def landmarks() -> list[dict]:
    """One global weenie plus one local landmark per district (dossier §2, §4.1)."""
    return [
        {"id": "spire", "kind": "spire", "pos": [0, 120, 0],
         "params": {"height": 360, "base_radius": 70, "stepped_crown": True,
                    "collar_z": 80, "roof_ring_z": 160, "crown_deck_z": 224,
                    "tether_length": 600, "tether_top_z": 960}},
        {"id": "stilt_pagoda", "kind": "pagoda", "pos": [-520, 430, 32],
         "params": {"height": 96, "top_z": 128, "tiers": 7, "stilt_base_z": 32,
                    "footprint": [64, 64]}},
        {"id": "interchange_knot", "kind": "knot", "pos": [-470, -40, 0],
         "params": {"loops": 3, "levels": [16, 32, 56, 80], "flyovers": 4, "radius": 132}},
        {"id": "harbor_cranes", "kind": "cranes", "pos": [-470, -345, 0],
         "params": {"count": 4, "cab_z": 48, "boom": 96, "positions":
                    [[-620, -350], [-520, -330], [-420, -360], [-330, -330]]}},
        {"id": "crystal_bridge", "kind": "crystal_bridge", "pos": [-40, -330, 176],
         "params": {"length": 300, "width": 36, "height": 28, "glazed": True}},
        {"id": "reactor_stacks", "kind": "stacks", "pos": [600, -140, 0],
         "params": {"count": 4, "top_z": 144, "radius": 22, "plume": True,
                    "positions": [[540, -120], [600, -80], [650, -150], [580, -190]]}},
        {"id": "block9", "kind": "block9", "pos": [330, 250, 32],
         "params": {"height": 200, "footprint": [130, 130],
                    "rail_hole": {"z": 80, "width": 44, "height": 36},
                    "hologram": {"z": 232, "width": 120}}},
        {"id": "civic_hologram", "kind": "hologram", "pos": [0, -60, 16],
         "params": {"height": 90, "width": 60, "colour": "cyan"}},
    ]


def block9_building() -> dict:
    """Block 9 as a building record so the corridors that pierce it can be declared
    `through` (Liziba station: a rail tunnel cut through a megablock, dossier §1.14).

    The openings are filled in afterwards by `declare_block9_holes`, once
    `_declare_through` has decided which corridors run through it.
    """
    return {"id": "D5_block9", "district": "D5", "tier": "D", "archetype": "megablock",
            "center": [330, 250], "size": [130, 130], "rot": 0, "base_z": 32.0,
            "height": 200, "roof_walkable": True, "landmark": "block9",
            "breaches": [{"face": "s", "z": 80, "width": 44, "height": 36}],
            "through": [], "holes": []}


def declare_block9_holes(record: dict, parts: dict) -> int:
    """One `holes` entry per corridor that claims `through` Block 9 (lead, r4 point 4).

    Six corridors cross this megablock - four plateau roads and the Ring Viaduct at +32
    through its ground arcade, and the Skyrail at +80 through the station hall. Each gets
    the MAP §3 v2 shape (`polygon`, `z`, `clear`, `corridor`), so L2 and the geometry agree
    instead of the builder inferring the openings from the corridor centrelines.
    """
    box = geom.rect(tuple(record["center"]), tuple(record["size"]), float(record["rot"]))
    for group, clear in (("streets", BLOCK9_STREET_CLEAR), ("viaducts", BLOCK9_VIA_CLEAR),
                         ("rails", BLOCK9_RAIL_CLEAR)):
        for item in parts[group]:
            if record["id"] not in item.get("through", []):
                continue
            hole = box.intersection(geom.line(item["points"]).buffer(
                item["width"] / 2 + BLOCK9_MARGIN))
            if hole.is_empty or hole.area < 40.0:
                continue
            record["through"].append(item["id"])
            record["holes"].append({
                "polygon": [[round(x, 1), round(y, 1)] for x, y in hole.exterior.coords[:-1]],
                "z": float(item["z"]), "height": clear, "clear": clear,
                "corridor": item["id"]})
    record["through"] = sorted(set(record["through"]))
    return len(record["holes"])


def block9_station(record: dict) -> dict | None:
    """The platform deck inside Block 9's rail hole (lead, r4 point 5).

    Both Skyrail halves end at the Through-Block Station node, which is the middle of the
    megablock: they terminate on this deck, inside the opening, instead of in solid mass.
    """
    hole = next((h for h in record["holes"] if h["corridor"].startswith("rail_")), None)
    if hole is None:
        return None
    area = geom.poly(hole["polygon"])
    centre = area.centroid
    deck = area.buffer(-2.0)
    return {"id": "deck_block9_platform", "kind": "platform", "z": float(hole["z"]),
            "thickness": 2.0, "parapet": 3.0, "district": "D5", "station": "block9",
            "under_clear": float(hole["z"]) - 2.0 - 32.0,
            "polygon": [[round(x, 1), round(y, 1)] for x, y in deck.exterior.coords[:-1]],
            "supported_by": ["D5_block9"],
            "platform": {"centre": [round(centre.x, 1), round(centre.y, 1)],
                         "length": round(max(deck.bounds[2] - deck.bounds[0],
                                             deck.bounds[3] - deck.bounds[1]), 1),
                         "serves": sorted(h["corridor"] for h in record["holes"]
                                          if h["corridor"].startswith("rail_"))}}


def anchors(arenas: list[dict], buildings: list[dict], rules: dict,
            rng: random.Random) -> list[dict]:
    """Glowing skyhook anchors: >= 8 per arena (check L6), on arena parapets and on the
    rooftops beside them. Every anchor belongs to exactly one arena - the nearest - so the
    per-arena counts are real, and each has a neighbour inside the 120 m anchor range."""
    out: list[dict] = []
    shapes = {a["id"]: geom.poly(a["polygon"]) for a in arenas}
    for arena in arenas:
        aid = arena["id"]
        z = float(rules["arenas"][aid]["main_tier"])
        area = shapes[aid]
        mine = [{"pos": [pt[0], pt[1], round(z + 26.0, 1)],
                 "normal": [round(nx, 3), round(ny, 3), 0.35], "arena": aid}
                for pt, nx, ny in geom.inward_normals(area, 12)]
        near = sorted((b for b in buildings
                       if b["roof_walkable"] and area.distance(Point(b["center"])) < 200.0),
                      key=lambda b: area.distance(Point(b["center"])))
        for b in near:
            top = b["base_z"] + b["height"]
            pos = [b["center"][0], b["center"][1], round(top + 5.0, 1)]
            if min(math.dist(pos, a["pos"]) for a in mine) > C.ANCHOR_RANGE * 0.7:
                continue
            if min((math.dist(pos[:2], (p.centroid.x, p.centroid.y))
                    for other, p in shapes.items() if other != aid),
                   default=math.inf) < area.distance(Point(b["center"])):
                continue                      # a different arena owns that rooftop
            mine.append({"pos": pos, "normal": [0.0, 0.0, 1.0], "arena": aid, "on": b["id"]})
        out.extend(_drop_stragglers(mine))
    return out


def _drop_stragglers(mine: list[dict]) -> list[dict]:
    """Drop anchors with no neighbour inside the 120 m anchor range (check L6).

    One is only removed when the arena still has more than the eight it needs, so the count
    never falls under the floor while reaching the last anchor stays possible.
    """
    keep = list(mine)
    for anchor in list(mine):
        if len(keep) <= C.ANCHORS_PER_ARENA:
            break
        others = [a for a in keep if a is not anchor]
        if others and min(math.dist(anchor["pos"], a["pos"]) for a in others) \
                > C.ANCHOR_RANGE:
            keep.remove(anchor)
    return keep


def skyline(rng: random.Random, half: float = C.HALF, ring: float = C.SKYLINE_HALF,
            count: int = 96) -> list[dict]:
    """Scenery towers outside the playable square: the Brood Titan's walkway and the
    silhouette behind the soft walls (never navigable, dossier §1.9)."""
    out = []
    for i in range(count):
        side = i % 4
        along = rng.uniform(-ring, ring)
        depth = rng.uniform(half + 24.0, ring - 20.0)
        x, y = ((along, depth), (along, -depth), (depth, along), (-depth, along))[side]
        out.append({"center": [round(x, 1), round(y, 1)],
                    "size": [round(rng.uniform(50, 110), 1), round(rng.uniform(50, 110), 1)],
                    "height": round(geom.snap(rng.uniform(80, 260), 4.0), 1)})
    return out


def player_start(nodes: dict, target: str = "A1") -> dict:
    """Insertion pier: the hero drops from the carrier facing the tutorial arena."""
    pos = nodes["H0"]["pos"]
    dst = nodes[target]["pos"]
    yaw = math.degrees(math.atan2(dst[1] - pos[1], dst[0] - pos[0]))
    return {"pos": [round(v, 1) for v in pos], "yaw_deg": round(yaw, 1),
            "drop_from_z": 220.0}


def clear_cover_under_towers(arenas: list[dict], buildings: list[dict]) -> int:
    """Drop cover pieces a declared tower stands on (same footprint AND the same z band)."""
    towers = [(geom.rect(tuple(b["center"]), tuple(b["size"]), b["rot"]),
               b["base_z"], b["base_z"] + b["height"])
              for b in buildings if b.get("supports")]
    if not towers:
        return 0
    dropped = 0
    for arena in arenas:
        keep = []
        for c in arena["cover"]:
            disc = Point(c["center"][0], c["center"][1]).buffer(
                max(c["size"][0], c["size"][1]) / 2)
            if any(box.intersects(disc) and z0 - 2 <= c["center"][2] <= z1
                   for box, z0, z1 in towers):
                dropped += 1
                continue
            keep.append(c)
        arena["cover"] = keep
    return dropped


def tower_keep(buildings: list[dict]) -> Polygon:
    """The carrier towers' own footprints, as ground no cover piece may come back onto.

    Without this the late top-up and `clear_cover_under_towers` fight each other: the top-up
    fills the hole a tower's footprint left, the clear-out cuts it again, and `cover_pass` is
    not idempotent (lead, r7 point 2).
    """
    shapes = [geom.rect(tuple(b["center"]), tuple(b["size"]), b["rot"])
              for b in buildings if b.get("supports")]
    return unary_union(shapes) if shapes else Polygon()
