"""Viaduct/rail-through: towers straddling the Ring Viaduct and the Skyrail (MAP §4, r2).

The lead's answer to the D7 skyline problem (review r2, answer 1 and point 2): neither move
the Ring Viaduct nor accept a low district. In D4/D5/D7 a tower may stand *over* the Ring
Viaduct (+32) or the Skyrail (+80) - Chongqing's Liziba, where the train runs through the
building. The corridor runs through a hole = corridor width + 2 x 4 m, with at least 40 m
clear above a viaduct deck and 32 m above the rail.

Declared as `holes` + `through` on the building and `through` on the corridor, which is what
L2 already accepts for podium arcades and the Block 9 rail hole.

Two things the rule needs before it works in practice:

* no ordinary lot ever spans a 64 m corridor - the block machinery probes its lots inward
  from a frontage - so this stage *places* the straddling masses the way `wall.podium_row`
  places its portals, and it claims the flanks before the kerb walls take them;
* in D7 the Ring Viaduct and the Skyrail run within 60 m of each other, so a tower over one
  would be capped by the other. A straddle therefore pierces *every* straddlable corridor its
  box crosses and is capped by none of them - the Liziba image twice over.

The same "a corridor passes through a mass" bookkeeping for the masses this stage does NOT
place - the landmark blocks - lives here too: `declare_through`, `loop_through` and
`rail_termini` write the `through` / `terminus` fields the layout schema reads.
"""
from __future__ import annotations

import math
import os
import random
import sys

from shapely.geometry import Point, Polygon
from shapely.ops import nearest_points, unary_union

import geom
import lots
import lots as lot_stage
import mapconst as C
import zones as zone_stage

STRADDLE_DISTRICTS = ("D4", "D5", "D7")
HOLE_MARGIN = 4.0          # MAP §4: the opening is the corridor width + 2 x 4 m
CLEAR_VIADUCT = 40.0       # clear headroom above a viaduct deck
CLEAR_RAIL = 32.0          # clear headroom above the rail
STATION_STEP = 48.0        # one candidate portal every 48 m of corridor
ALONG = (88.0, 72.0, 60.0, 48.0)   # the mass's length along the corridor, generous first
# The mass has to reach across the corridor and land on solid ground either side. In D7 the
# Ring Viaduct and the Skyrail run ~35 m apart, so the useful widths are the ones that span
# both bands at once; the narrow ones are for the stretches where they separate.
ACROSS = (152.0, 132.0, 176.0, 112.0, 96.0, 200.0)
NUDGE = (0.0, 14.0, -14.0, 26.0, -26.0)   # slide along the corridor to find clear flanks
# ...and sideways, so the two flanks need not be equal: the Ring Viaduct runs 50 m inside
# D7's north edge, where the only way to stand on ground both sides is a long south leg and
# a short north one.
OFFSET = (0.0, 26.0, -26.0, 46.0, -46.0)
MIN_FLANK = 0.12           # each side of the openings keeps this share of the footprint
CLIP_SHARE = 0.34           # overhang worth squaring off against the buildable envelope
TALL_SHARE = 0.5           # share of straddles that go into the district's D band
RING_CAP = 240.0           # no straddling mass outgrows its district's tower band


def straddlable(parts: dict) -> list[dict]:
    """The corridors a tower may stand over: the Ring Viaduct and the Skyrail only.

    The ring is emitted twice - as one closed loop record and as its per-edge segments - so
    the loop record (no `nodes`) is dropped and the segments are used.
    """
    out = [v for v in parts["viaducts"] if v.get("kind") == "ring" and v.get("nodes")]
    out += list(parts["rails"])
    return out


def clear_of(item: dict, rails: list[dict]) -> float:
    """MAP §4: 40 m clear over a viaduct deck, 32 m over the rail."""
    return CLEAR_RAIL if item in rails else CLEAR_VIADUCT


def _band(item: dict) -> Polygon:
    return geom.line(item["points"]).buffer(item["width"] / 2 + HOLE_MARGIN)


def build(parts: dict, buildings: list[dict], rules: dict, free: dict[str, Polygon],
          occ, caps: list[tuple[Polygon, float, str]],
          slots: list[tuple[Polygon, float]], keep_out: list[Polygon],
          rng: random.Random) -> dict:
    """Place the straddling towers and declare every hole on both sides of each crossing."""
    glob = rules["global"]
    spire = tuple(glob["spire_center"])
    items = straddlable(parts)
    bands = {item["id"]: _band(item) for item in items}
    # the flanks may stand on any buildable ground: a corridor that runs along a district
    # boundary (the Ring Viaduct across D7's north edge) has one flank in each district
    land = unary_union([v for v in free.values() if not v.is_empty])
    made: list[dict] = []
    for item in items:
        line = geom.line(item["points"])
        d = STATION_STEP * 0.5
        index = 0
        while d < line.length:
            here = line.interpolate(d)
            ahead = line.interpolate(min(d + 8.0, line.length))
            axis = math.degrees(math.atan2(ahead.y - here.y, ahead.x - here.x))
            d += STATION_STEP
            site = _site(rules, here, item["z"])
            if site is None or land.is_empty:
                continue
            portal = _portal(here, axis, item, items, bands, land, occ, keep_out)
            if portal is None:
                continue
            box, size, crossers = portal
            index += 1
            centre = (box.centroid.x, box.centroid.y)
            record = _record(site, centre, axis, box, size, crossers, parts["rails"], rules,
                             glob, spire, caps, slots, rng, index)
            if record is None:
                index -= 1
                continue
            occ.add(box)
            land = land.difference(box)
            buildings.append(record)
            for crosser in crossers:
                crosser.setdefault("through", []).append(record["id"])
            made.append(record)
    return {"pierced": len(made), "raised": len([b for b in made if b["height"] >= 128.0])}


def _site(rules: dict, here: Point, z: float) -> str | None:
    """The district whose ground this station stands over, if it may straddle at all."""
    for zone in zone_stage.zones(rules):
        fp = zone["footprint"]
        if fp[0] <= here.x <= fp[2] and fp[1] <= here.y <= fp[3] \
                and zone["district"] in STRADDLE_DISTRICTS \
                and zone["ground_z"] <= z + 1.0:
            return zone["district"]
    return None


def _crossers(box: Polygon, items: list[dict], bands: dict[str, Polygon]) -> list[dict]:
    """Every straddlable corridor this footprint opens onto.

    The station's own corridor is a full straddle - mass left on both sides. A second,
    near-parallel corridor (the Skyrail beside the Ring Viaduct in D7) only clips the box;
    it still gets a hole, because a corridor band that is allowed to cap the cornice of a
    tower standing 20 m away would make the whole rule useless.
    """
    out = []
    for item in items:
        hole = box.intersection(bands[item["id"]])
        if hole.is_empty or hole.area < 40.0:
            continue
        out.append(item)
    return out


def _flanks(solid: Polygon, box: Polygon) -> bool:
    """Are there two real flanks left, one each side? A third corridor crossing the same
    box splits the mass further, so the two biggest pieces are what count."""
    parts = sorted((g.area for g in getattr(solid, "geoms", [solid])
                    if isinstance(g, Polygon)), reverse=True)
    return len(parts) >= 2 and parts[1] >= MIN_FLANK * box.area


def _straddles(box: Polygon, band: Polygon) -> bool:
    """Does this corridor cross the footprint, leaving real mass on both sides?"""
    return _flanks(box.difference(band), box)


def _portal(here: Point, axis: float, item: dict, items: list[dict],
            bands: dict[str, Polygon], land: Polygon, occ,
            keep_out: list[Polygon]) -> tuple[Polygon, tuple[float, float], list[dict]] | None:
    """The straddling footprint at this station: the corridors plus two standing flanks.

    Only the flanks have to stand on free land - the roadway between them is the hole. The
    flanks are tested against every corridor the box opens onto, not just this one, so a
    tower over the Ring Viaduct that also meets the Skyrail still stands on solid ground.
    The station slides along the corridor a little: a kerb setback or a plaza edge is
    usually clear a few metres one way or the other.
    """
    ux, uy = math.cos(math.radians(axis)), math.sin(math.radians(axis))
    for along in ALONG:
        for across in ACROSS:
            if across < item["width"] + 2.0 * HOLE_MARGIN + 24.0:
                continue
            for nudge in NUDGE:
                for shift in OFFSET:
                    centre = (here.x + ux * nudge - uy * shift,
                              here.y + uy * nudge + ux * shift)
                    box = geom.rect(centre, (along, across), axis)
                    found = _accept(box, along, across, item, items, bands, land, occ,
                                    keep_out)
                    if found is not None:
                        return found
    return None


def _accept(box: Polygon, along: float, across: float, item: dict, items: list[dict],
            bands: dict[str, Polygon], land: Polygon, occ,
            keep_out: list[Polygon]) -> tuple[Polygon, tuple[float, float], list[dict]] | None:
    """Is this footprint a straddle, and does it stand on ground it may stand on?"""
    if any(box.intersects(area) for area in keep_out):
        return None
    crossers = _crossers(box, items, bands)
    if item not in crossers or not _straddles(box, bands[item["id"]]):
        return None
    legs = box.difference(unary_union([bands[c["id"]] for c in crossers]))
    if not _flanks(legs, box):
        return None
    bad = 0.0 if legs.is_empty else legs.difference(land).area
    if bad > 6.0:
        # the ideal box overhangs a kerb or a plaza: square it off against the buildable
        # envelope (free land plus the openings) instead of giving up on the station
        if bad > CLIP_SHARE * legs.area:
            return None
        return _clip(box, land, bands, crossers, item, items, occ)
    if occ.hits(legs):
        return None
    return box, (along, across), crossers


def _clip(box: Polygon, land: Polygon, bands: dict[str, Polygon], crossers: list[dict],
          item: dict, items: list[dict], occ) -> tuple[Polygon, tuple[float, float], list[dict]] | None:
    """Square an overhanging straddle off against the ground it may really stand on."""
    envelope = land.union(unary_union([bands[c["id"]] for c in crossers]))
    patch = box.intersection(envelope)
    if patch.is_empty or patch.area < 1200.0:
        return None
    parts = [g for g in getattr(patch, "geoms", [patch]) if isinstance(g, Polygon)]
    if not parts:
        return None
    fit = lot_stage.largest_inscribed_rect(
        max(parts, key=lambda g: g.area), lots.dominant_edge_angle(box))
    if fit is None:
        return None
    centre, size, rot, area = fit
    if area < 1200.0 or min(size) < item["width"] + 2.0 * HOLE_MARGIN + 16.0:
        return None
    squared = geom.rect(centre, size, rot)
    crossers = _crossers(squared, items, bands)
    if item not in crossers or not _straddles(squared, bands[item["id"]]):
        return None
    legs = squared.difference(unary_union([bands[c["id"]] for c in crossers]))
    if not _flanks(legs, squared) or legs.difference(land).area > 6.0 or occ.hits(legs):
        return None
    return squared, (size[0], size[1]), crossers


def _record(did: str, centre: tuple[float, float], axis: float, box: Polygon,
            size: tuple[float, float], crossers: list[dict], rails: list[dict],
            rules: dict, glob: dict, spire: tuple[float, float],
            caps: list[tuple[Polygon, float, str]], slots: list[tuple[Polygon, float]],
            rng: random.Random, index: int) -> dict | None:
    """The tower itself: the district's own C/D band, inside every cap it does not pierce."""
    heights = rules["districts"][did]["buildings"]["tier_h"]
    tier = "D" if rng.random() < TALL_SHARE else "C"
    pierced = {item["id"] for item in crossers}
    want = rng.uniform(*heights[tier])
    want = min(want, 6.0 * min(size))
    want = min(want, lot_stage.spire_cap(spire, centre[0], centre[1], glob["spire_cap_r"],
                                         glob.get("spire_cap_top", 200.0)))
    for area, cap in slots:
        if box.intersection(area).area > 1.0:
            want = min(want, cap)
    for area, cap, ident in caps:
        if ident in pierced:
            continue                     # a corridor this mass pierces is its own hole
        if box.intersection(area).area > 1.0:
            want = min(want, cap)
    # every opening needs a storey of structure over it: a gate is not a tower. This is a
    # floor on the mass, not a cap - the district's band still sets how tall it may get.
    heads = [item["z"] + clear_of(item, rails) for item in crossers]
    height = geom.snap(max(want, max(heads) + 24.0), C.FLOOR_MODULE)
    if height < max(heights["C"][0], max(heads) + 24.0):
        return None
    holes = []
    for item in crossers:
        hole = box.intersection(_band(item))
        holes.append({
            "polygon": [[round(x, 1), round(y, 1)] for x, y in hole.exterior.coords[:-1]],
            "z": float(item["z"]), "height": clear_of(item, rails),
            "clear": clear_of(item, rails), "corridor": item["id"]})
    return {
        "id": f"{did}_s{index:03d}", "district": did,
        "tier": "D" if height >= heights["D"][0] else "C",
        "archetype": "podium_tower",
        "center": [round(centre[0], 1), round(centre[1], 1)],
        "size": [round(size[0], 1), round(size[1], 1)],
        "rot": round(axis % 180.0, 1), "base_z": 0.0, "height": height,
        "roof_walkable": False, "breaches": [],
        "through": sorted(pierced), "straddles": sorted(pierced), "holes": holes,
    }


def declare_through(parts: dict, buildings: list[dict]) -> int:
    """Corridors that pierce a landmark block: declare them in `through` so L2 accepts it.

    Block 9 is a Liziba-style megablock: the rail runs through a hole in it and the plateau
    roads run through its ground arcade (dossier §1.14, §1.7).
    """
    hits = 0
    for group in ("streets", "viaducts", "rails", "tunnels"):
        for item in parts[group]:
            item.setdefault("through", [])
            band = geom.line(item["points"]).buffer(item["width"] / 2)
            top = item["z"] + item.get("clear", C.UNDER_DECK_CLEAR)
            for b in buildings:
                if b.get("landmark") is None:
                    continue
                box = geom.rect(tuple(b["center"]), tuple(b["size"]), b["rot"])
                if box.intersects(band) and b["base_z"] < top and \
                        item["z"] < b["base_z"] + b["height"]:
                    item["through"].append(b["id"])
                    hits += 1
    return hits


def loop_through(parts: dict) -> int:
    """The Ring Viaduct is one record made of segments: a mass that pierces a segment
    pierces the loop, so the loop's `through` is the union of its segments'."""
    loop = next((v for v in parts["viaducts"] if v["id"] == "ring_viaduct_loop"), None)
    if loop is None:
        return 0
    by_id = {v["id"]: v for v in parts["viaducts"] + list(parts["rails"])
             + list(parts["streets"])}
    pierced = {b for ident in loop.get("segments", []) for b in by_id.get(ident, {}).get("through", [])}
    loop["through"] = sorted(pierced)
    return len(pierced)


def rail_termini(rails: list[dict], station: dict, block9: dict) -> int:
    """A rail that ends inside a building ends on the station platform, not in mass.

    Both halves of the Skyrail terminate at the Through-Block Station node in the middle of
    Block 9 (lead, r4 point 5): the platform deck fills the rail hole, so the terminus is a
    place a train stands, and the record says which deck it is.
    """
    hole = geom.poly(station["polygon"])
    marked = 0
    for rail in rails:
        if block9["id"] not in rail.get("through", []):
            continue
        ends = [i for i, p in enumerate(rail["points"]) if hole.contains(Point(p[0], p[1]))]
        if not ends:
            continue
        rail["terminus"] = {"deck": station["id"], "node": rail["nodes"][-1]
                            if ends[-1] else rail["nodes"][0]}
        marked += 1
    return marked
