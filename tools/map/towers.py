"""The towers that carry the D7 decks and ring them (MAP §4 D7, lead r2 point 2).

The Sky Garden (+144) and the Crystal Bridge (+176) have to be *strung between glass
towers*, and the district has to read as a tower canyon with the Ring Viaduct and the
Skyrail running through it. Neither the block machinery nor the viaduct/rail-through stage
can deliver that on its own:

* the block machinery probes its lots inward from a frontage, so it never spans a 64 m
  corridor, and in D7 almost every lot is capped at 28 m by the Ring Viaduct or 76 m by the
  Skyrail - the district's own corridors are why it had no skyline;
* `straddle.build` only places a straddling mass where the land beside the corridor is
  still empty, and by then it is not.

So the carriers are planted **first**, before the fill, on a ring around each deck. Each
one straddles whatever corridor it opens onto - the holes and `through` are declared exactly
as MAP §4 asks - and where it opens onto none it is a plain tower, capped normally. Planting
before the fill is what gives them room, and it is why they can carry the decks instead of
being clamped under them.
"""
from __future__ import annotations

import math
import random

from shapely.geometry import Point, Polygon
from shapely.ops import unary_union

import geom
import lots as lot_stage
import mapconst as C
import straddle
import zones as zone_stage

# deck id, how many carriers, footprint, tier band key
CARRIER_DECKS = (("A6_sky_garden", 5, 64.0), ("F5_crystal", 4, 72.0),
                 ("F6_skydeck", 2, 56.0))
SITES_PER_RING = 32
RADIUS = tuple(round(0.7 + 0.09 * i, 2) for i in range(20))   # x the deck's own reach
FOOT = (1.0, 0.84, 0.7)                # fractions of the nominal footprint


def build(decks: list[dict], parts: dict, rules: dict, land: Polygon, occ,
          caps: list[tuple[Polygon, float, str]], slots: list[tuple[Polygon, float]],
          keep_out: list[Polygon], rng: random.Random) -> tuple[list[dict], dict]:
    """Plant the deck carriers and return them with a small report."""
    glob = rules["global"]
    spire = tuple(glob["spire_center"])
    items = straddle.straddlable(parts)
    bands = {item["id"]: straddle._band(item) for item in items}
    out: list[dict] = []
    for ident, count, foot in CARRIER_DECKS:
        deck = next((d for d in decks if d["id"] == ident), None)
        if deck is None:
            continue
        area = geom.poly(deck["polygon"])
        centre = (area.centroid.x, area.centroid.y)
        reach = max(math.dist(centre, (x, y)) for x, y in deck["polygon"])
        placed = 0
        # A6's own arena is a keep-out for everything else - nothing may stand over the Sky
        # Garden - but its carriers have to stand right beside it; the deck test in
        # `_carrier` is what keeps them off the plate itself.
        deck_keep = [a for a in keep_out if a.distance(area) > 40.0] \
            if ident == "A6_sky_garden" else keep_out
        # walk outward from the deck on every bearing: the ring is an ideal, the ground is
        # a street grid and a viaduct, so the site is the first one that actually stands
        for angle in range(SITES_PER_RING):
            if placed >= count:
                break
            theta = 2.0 * math.pi * angle / SITES_PER_RING
            for scale in RADIUS:
                site = (centre[0] + reach * scale * math.cos(theta),
                        centre[1] + reach * scale * math.sin(theta))
                record = _carrier(ident, deck, site, foot, items, bands, parts["rails"],
                                  land, occ, caps, slots, deck_keep, rules, glob, spire,
                                  len(out) + 1)
                if record is None:
                    continue
                box = geom.rect(tuple(record["center"]), tuple(record["size"]),
                                record["rot"])
                out.append(record)
                occ.add(box)
                land = land.difference(box)
                placed += 1
                break
        deck["supported_by"] = sorted(set(deck.get("supported_by", []))
                                      | {b["id"] for b in out if b.get("carries") == ident})
    return out, {"carriers": len(out),
                 "straddling": len([b for b in out if b.get("straddles")])}


def _carrier(deck_id: str, deck: dict, site: tuple[float, float], foot: float,
             items: list[dict], bands: dict[str, Polygon], rails: list[dict],
             land: Polygon, occ, caps: list[tuple[Polygon, float, str]],
             slots: list[tuple[Polygon, float]], keep_out: list[Polygon], rules: dict,
             glob: dict, spire: tuple[float, float], index: int) -> dict | None:
    """One carrier: a tower that straddles what it crosses and carries `deck` above it."""
    did = deck.get("district", "D7")
    if not _in_district(rules, did, site):
        return None
    heights = rules["districts"][did]["buildings"]["tier_h"]
    deck_area = geom.poly(deck["polygon"])
    for frac in FOOT:
        size = foot * frac
        box = geom.rect(site, (size, size))
        if box.intersects(deck_area) and deck_id == "A6_sky_garden":
            continue                     # the A6 arena stays open to the sky
        if any(box.intersects(area) for area in keep_out):
            continue
        crossers = straddle._crossers(box, items, bands)
        if crossers:
            legs = box.difference(unary_union([bands[c["id"]] for c in crossers]))
            if not straddle._flanks(legs, box) or legs.difference(land).area > 6.0 \
                    or occ.hits(legs):
                continue
        elif box.difference(land).area > 6.0 or occ.hits(box):
            continue
        pierced = {c["id"] for c in crossers}
        heads = [c["z"] + straddle.clear_of(c, rails) for c in crossers]
        want = heights["D"][1] if deck["z"] >= 144.0 else heights["C"][1]
        want = min(want, 6.0 * size, straddle.RING_CAP)
        want = min(want, lot_stage.spire_cap(spire, site[0], site[1], glob["spire_cap_r"],
                                             glob.get("spire_cap_top", 200.0)))
        for area, cap in slots:
            if box.intersection(area).area > 1.0:
                want = min(want, cap)
        for area, cap, ident in caps:
            if ident in pierced:
                continue                 # a corridor this mass pierces is its own hole
            if box.intersection(area).area > 1.0:
                want = min(want, cap)
        if heads:
            want = max(want, max(heads) + 24.0)
        height = geom.snap(want, C.FLOOR_MODULE)
        if height < deck["z"] + 8.0:
            continue                     # it has to reach the deck it carries
        record = {
            "id": f"{did}_car{index:02d}", "district": did,
            "tier": "D" if height >= heights["D"][0] else "C",
            "archetype": "podium_tower", "center": [round(site[0], 1), round(site[1], 1)],
            "size": [round(size, 1), round(size, 1)], "rot": 0.0, "base_z": 0.0,
            "height": height, "carries": deck_id, "supports": deck_id,
            "roof_walkable": C.LAYER_Z["L4"] <= height <= C.LAYER_Z["L4"] + 60,
            "breaches": [],
        }
        if crossers:
            record["through"] = sorted(pierced)
            record["straddles"] = sorted(pierced)
            record["holes"] = [{
                "polygon": [[round(x, 1), round(y, 1)]
                            for x, y in box.intersection(bands[c["id"]]).exterior.coords[:-1]],
                "z": float(c["z"]), "height": straddle.clear_of(c, rails),
                "clear": straddle.clear_of(c, rails), "corridor": c["id"]}
                for c in crossers]
            for crosser in crossers:
                crosser.setdefault("through", []).append(record["id"])
        return record
    return None


def _in_district(rules: dict, did: str, site: tuple[float, float]) -> bool:
    """A carrier belongs to the district whose ground it stands on, not to a neighbour's."""
    return any(z["district"] == did and z["footprint"][0] <= site[0] <= z["footprint"][2]
               and z["footprint"][1] <= site[1] <= z["footprint"][3]
               for z in zone_stage.zones(rules))
