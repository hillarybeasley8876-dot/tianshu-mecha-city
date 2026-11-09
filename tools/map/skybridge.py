"""Skybridges: the ties that make D5 read as one megastructure and D7 as a tower cluster.

Lead review r1, point 4:

* **D5 Megablocks** must read as a wall of 128-200 m megablocks around the canyon, with
  skybridges at +80 and +128 every 80-120 m. The canyon is arena A4, so the bridges span
  it east-west and land on whichever megablock stands at each end; a bridge with no
  megablock at one end is dropped rather than left floating.
* **D7 Financial** must have 128-240 m glass towers on podiums between *and over* the
  converging streets, so the Sky Garden (+144) and the Crystal Bridge (+176) are ringed by
  glass. The wall and podium stages already build the mass; this stage adds the two links
  that hold the composition together and the towers that carry them.
"""
from __future__ import annotations

import math

from shapely.geometry import Point, Polygon

import geom
import mapconst as C

CANYON_LEVELS = (80.0, 128.0)
CANYON_SPACING = (80.0, 120.0)     # MAP §4 D5: a bridge every 80-120 m
BRIDGE_WIDTH = 24.0
BRIDGE_THICK = 6.0
LANDING = 32.0                     # how far onto a roof the deck must reach


def canyon_bridges(rules: dict, decks: list[dict], arenas: list[dict],
                   buildings: list[dict],
                   caps: list[tuple[Polygon, float]] = ()) -> list[dict]:
    """Skybridges across the Megablock Canyon, one pair of levels per station.

    `caps` is the camera keep-out (lead, r7): a bridge that would cross within 30 m of a vista
    camera above its lens is left out - V4 stands on the canyon floor at +100 and a skydeck
    over its head is the frame.
    """
    spec = rules["arenas"].get("A4")
    if spec is None:
        return []
    canyon = None
    for arena in arenas:
        if arena["id"] == "A4":
            canyon = geom.poly(arena["polygon"])
    if canyon is None:
        return []
    minx, miny, maxx, maxy = canyon.bounds
    cx = (minx + maxx) / 2
    out: list[dict] = []
    step = sum(CANYON_SPACING) / 2
    index = 0
    y = miny + step * 0.5
    while y <= maxy - step * 0.25:
        for level in CANYON_LEVELS:
            index += 1
            slab = _span((cx, y), minx, maxx, buildings, level)
            if slab is None or _capped(slab["polygon"], level, caps):
                continue
            deck = {"id": f"D5_skybridge_{index:02d}", "kind": "skydeck", "z": level,
                    "thickness": BRIDGE_THICK, "parapet": 5.0, "district": "D5",
                    "polygon": slab["polygon"], "under_clear": level - BRIDGE_THICK,
                    "span": slab["span"], "skybridge": True}
            out.append(deck)
        y += step
    return out


def _capped(polygon: list[list[float]], z: float,
            caps: list[tuple[Polygon, float]]) -> bool:
    """Would this slab break a height cap it overlaps?"""
    area = geom.poly(polygon)
    return any(z > top and area.intersects(poly) for poly, top in caps)


def _span(centre: tuple[float, float], minx: float, maxx: float,
          buildings: list[dict], level: float) -> dict | None:
    """The slab from the megablock west of the canyon to the one east of it."""
    west = _landing(centre, buildings, level, -1.0, minx)
    east = _landing(centre, buildings, level, 1.0, maxx)
    if west is None or east is None:
        return None
    half = BRIDGE_WIDTH / 2
    polygon = geom.rect_points(((west[1] + east[1]) / 2, centre[1]),
                               (east[1] - west[1], BRIDGE_WIDTH), 0.0)
    return {"polygon": polygon, "span": [west[0], east[0]], "half": half}


def _landing(centre: tuple[float, float], buildings: list[dict], level: float,
             side: float, edge: float) -> tuple[str, float] | None:
    """The building whose roof this bridge lands on, and how far in it reaches."""
    best = None
    for b in buildings:
        if b["district"] != "D5" or b.get("landmark"):
            continue
        top = b["base_z"] + b["height"]
        if top < level or top > level + 96.0:
            continue                     # the deck has to meet a roof at this level
        box = geom.rect(tuple(b["center"]), tuple(b["size"]), b["rot"])
        if not box.intersects(geom.rect((centre[0] + side * 200.0, centre[1]),
                                        (400.0, BRIDGE_WIDTH), 0.0)):
            continue
        reach = (box.bounds[2] if side > 0 else box.bounds[0])
        if side > 0 and reach <= edge:
            continue
        if side < 0 and reach >= edge:
            continue
        depth = abs(reach - edge)
        if best is None or depth > best[2]:
            best = (b["id"], reach - side * LANDING, depth)
    return None if best is None else (best[0], best[1])


TOWER_DECKS = ("A6_sky_garden", "F5_crystal")
TOWER_REACH = 260.0        # how far from the deck a carrier tower may stand
TOWER_FOOT_MIN = 700.0     # m2: below this a lot cannot carry a 128 m tower
TOWER_MAX = 5              # carriers raised per deck (consolidate_towers adds more)


def tower_ring(rules: dict, decks: list[dict], buildings: list[dict],
               caps: list[tuple[Polygon, float, str]],
               slots: list[tuple[Polygon, float]]) -> int:
    """Raise the big lots around the Sky Garden and the Crystal Bridge into glass towers.

    The deck's underside is a cap for everything *under* it, but the key art has the Sky
    Garden strung between towers and the Crystal Bridge landing on them, so the carriers
    stand clear of the slab and are exempt: they are what holds the deck up, and the deck
    declares them in `supported_by` (check L9).
    """
    band = rules["districts"]["D7"]["buildings"]["tier_h"]
    raised = 0
    for deck in decks:
        if deck["id"] not in TOWER_DECKS:
            continue
        area = geom.poly(deck["polygon"])
        centre = (area.centroid.x, area.centroid.y)
        carriers = deck.setdefault("supported_by", [])
        ranked = sorted(
            (b for b in buildings
             if b["district"] == "D7"
             and math.dist(b["center"], centre) <= TOWER_REACH
             and b["size"][0] * b["size"][1] >= TOWER_FOOT_MIN
             and not _blocked(b, area, caps)),
            key=lambda b: -b["size"][0] * b["size"][1])
        for b in ranked[:TOWER_MAX]:
            top = geom.snap(_tower_height(b, band), C.FLOOR_MODULE)
            # a lead vista is a soft cap: the carrier stops under the sightline
            box = geom.rect(tuple(b["center"]), tuple(b["size"]), b["rot"])
            for slot, cap in slots:
                if box.intersection(slot).area > 1.0:
                    top = min(top, geom.snap(cap - b["base_z"], C.FLOOR_MODULE))
            if top <= b["height"]:
                continue
            b["height"] = top
            b["tier"] = "D" if top >= band["D"][0] else "C"
            b["archetype"] = "podium_tower"
            b["carries"] = deck["id"]
            b["roof_walkable"] = C.LAYER_Z["L4"] <= b["base_z"] + top <= C.LAYER_Z["L4"] + 60
            carriers.append(b["id"])
            raised += 1
    return raised


def _on_road(box: Polygon, mask: Polygon | None) -> bool:
    """Does a merged podium footprint reach over a corridor? A tower stands beside the
    street, never on it (check L2)."""
    return mask is not None and not mask.is_empty and box.intersection(mask).area > 20.0


def _blocked(b: dict, deck_area: Polygon,
             caps: list[tuple[Polygon, float]]) -> bool:
    """A carrier must clear the deck slab and still reach 128 m under anything flying over.

    A viaduct band over a corner of the lot is not fatal - it caps the cornice like it does
    everywhere else - but a lot that cannot reach the L4 datum under it is not a tower site.
    """
    box = geom.rect(tuple(b["center"]), tuple(b["size"]), b["rot"])
    if box.intersection(deck_area).area > 1.0:
        return True
    limits = [cap for area, cap, ident in caps
              if ident not in b.get("through", []) and box.intersection(area).area > 1.0]
    return bool(limits) and min(limits) - b["base_z"] < 128.0


def _tower_height(b: dict, band: dict) -> float:
    """A carrier's height: inside the district's C/D band and inside its slenderness."""
    low, high = band["D"] if b["tier"] == "D" else band["C"]
    want = high - (high - low) * (1.0 - min(b["size"][0] * b["size"][1] / 6400.0, 1.0))
    return min(want, 6.0 * min(b["size"]))


CLUSTER_MIN = 2200.0       # m2 of merged footprint before it can carry a tower
CLUSTER_MAX = 5            # lots merged into one tower


def consolidate_towers(rules: dict, decks: list[dict], buildings: list[dict],
                       caps: list[tuple[Polygon, float, str]],
                       slots: list[tuple[Polygon, float]],
                       mask: Polygon | None = None) -> int:
    """Merge the small lots around the D7 decks into tower podiums (lead r1, point 4).

    The Financial district's land is a handful of ribbons between the corridors that
    converge on F2, so no single lot is big enough for a 128 m tower. Merging neighbours
    into one podium footprint is how the district gets its glass: the merged mass keeps the
    ground it stood on, carries the tower, and the lots it swallowed are removed.
    """
    import lots as lot_stage

    band = rules["districts"]["D7"]["buildings"]["tier_h"]
    dropped: set[str] = set()
    made = 0
    for deck in decks:
        if deck["id"] not in TOWER_DECKS:
            continue
        area = geom.poly(deck["polygon"])
        centre = (area.centroid.x, area.centroid.y)
        pool = [b for b in buildings
                if b["id"] not in dropped and b["district"] == "D7"
                and not b.get("straddles") and not b.get("carries")
                and math.dist(b["center"], centre) <= TOWER_REACH
                and not _blocked(b, area, caps)]
        pool.sort(key=lambda b: -b["size"][0] * b["size"][1])
        for seed in pool[:TOWER_MAX]:
            if seed["id"] in dropped:
                continue
            group = [seed]
            shape = geom.rect(tuple(seed["center"]), tuple(seed["size"]), seed["rot"])
            for other in pool:
                if len(group) >= CLUSTER_MAX or other["id"] in dropped:
                    continue
                if other is seed:
                    continue
                grown = shape.union(
                    geom.rect(tuple(other["center"]), tuple(other["size"]), other["rot"]))
                if grown.area > CLUSTER_MIN * 2.2:
                    continue
                fit = lot_stage.largest_inscribed_rect(grown, seed["rot"])
                if fit is None or fit[3] < CLUSTER_MIN:
                    continue
                if _blocked(dict(seed, center=list(fit[0]), size=list(fit[1]), rot=fit[2]),
                            area, caps):
                    continue
                group.append(other)
                shape = grown
            fit = lot_stage.largest_inscribed_rect(shape, seed["rot"])
            if fit is None or fit[3] < CLUSTER_MIN or len(group) < 2:
                continue
            if _on_road(geom.rect(fit[0], fit[1], fit[2]), mask):
                continue
            if _make_tower(seed, fit, band, slots, deck):
                dropped.update(b["id"] for b in group[1:])
                made += 1
    if dropped:
        buildings[:] = [b for b in buildings if b["id"] not in dropped]
    return made


def _make_tower(seed: dict, fit: tuple, band: dict,
                slots: list[tuple[Polygon, float]], deck: dict) -> bool:
    """Turn the merged footprint into the tower that carries `deck`."""
    centre, size, rot, _area = fit
    probe = dict(seed, center=list(centre), size=list(size), rot=rot)
    top = geom.snap(_tower_height(probe, band), C.FLOOR_MODULE)
    box = geom.rect(centre, size, rot)
    for slot, cap in slots:
        if box.intersection(slot).area > 1.0:
            top = min(top, geom.snap(cap - seed["base_z"], C.FLOOR_MODULE))
    if top < 128.0:
        return False
    seed.update({"center": [round(centre[0], 1), round(centre[1], 1)],
                 "size": [round(size[0], 1), round(size[1], 1)],
                 "rot": round(rot % 180.0, 1), "height": top,
                 "tier": "D" if top >= band["D"][0] else "C",
                 "archetype": "podium_tower", "carries": deck["id"], "merged": True,
                 "roof_walkable": C.LAYER_Z["L4"] <= seed["base_z"] + top
                 <= C.LAYER_Z["L4"] + 60})
    deck.setdefault("supported_by", []).append(seed["id"])
    return True


RING_TARGET = 8            # MAP §4 D7 / lead r2 point 2: towers 128-240 m ringing the decks
RING_TALL = 3              # ...of which this many reach 200 m or more
RING_BAND = (128.0, 240.0)


def ring_towers(rules: dict, decks: list[dict], buildings: list[dict],
                caps: list[tuple[Polygon, float, str]],
                slots: list[tuple[Polygon, float]]) -> dict:
    """Ring the Sky Garden (+144) and the Crystal Bridge (+176) with glass towers.

    Lead r2, point 2: at least 8 towers of 128-240 m within 260 m of the two decks, at
    least 3 of them 200 m or taller, with the A6 arena left open to the sky - the towers
    stand *around* it, never over it. The wall and block stages already put the mass on the
    ground; this raises the lots that can carry a tower into the district's own band, tallest
    first, so the tall ones are the ones with the footprint to stand on.
    """
    band = rules["districts"]["D7"]["buildings"]["tier_h"]
    centres = [_deck_centre(decks, ident) for ident in TOWER_DECKS]
    centres = [c for c in centres if c is not None]
    open_sky = [_deck_area(decks, "A6_sky_garden")]
    open_sky = [a for a in open_sky if a is not None]
    made, tall = 0, 0

    def near(b: dict) -> bool:
        return any(math.dist(b["center"], c) <= TOWER_REACH for c in centres)

    def ring() -> list[dict]:
        return [b for b in buildings if b["district"] == "D7" and near(b)
                and RING_BAND[0] <= b["height"] <= RING_BAND[1]]

    for want_tall in (True, False):
        for b in sorted(buildings, key=lambda b: -b["size"][0] * b["size"][1]):
            if b["district"] != "D7" or b.get("landmark") or not near(b):
                continue
            have = ring()
            if len(have) >= RING_TARGET and sum(1 for x in have if x["height"] >= 200.0) \
                    >= RING_TALL:
                return {"raised": made, "ring": len(have), "tall": sum(
                    1 for x in have if x["height"] >= 200.0)}
            if b in have and not (want_tall and b["height"] < 200.0):
                continue          # already a tower; only the tall pass may raise one further
            top = _ring_height(b, band, want_tall, caps, slots, open_sky)
            if top is None or top <= b["height"]:
                continue
            b["height"] = top
            b["tier"] = "D" if top >= band["D"][0] else "C"
            b["archetype"] = "podium_tower"
            b["roof_walkable"] = C.LAYER_Z["L4"] <= b["base_z"] + top <= C.LAYER_Z["L4"] + 60
            made += 1
            tall += 1 if top >= 200.0 else 0
    have = ring()
    return {"raised": made, "ring": len(have),
            "tall": sum(1 for x in have if x["height"] >= 200.0)}


def _deck_area(decks: list[dict], ident: str) -> Polygon | None:
    for deck in decks:
        if deck["id"] == ident:
            return geom.poly(deck["polygon"])
    return None


def _deck_centre(decks: list[dict], ident: str) -> tuple[float, float] | None:
    area = _deck_area(decks, ident)
    return None if area is None else (area.centroid.x, area.centroid.y)


def _ring_height(b: dict, band: dict, want_tall: bool,
                 caps: list[tuple[Polygon, float, str]],
                 slots: list[tuple[Polygon, float]], open_sky: list[Polygon]) -> float | None:
    """The tallest this lot may reach inside the ring, or None when it cannot be a tower."""
    box = geom.rect(tuple(b["center"]), tuple(b["size"]), b["rot"])
    if any(box.intersection(area).area > 1.0 for area in open_sky):
        return None                      # the A6 arena stays open to the sky
    limits = [cap for area, cap, ident in caps
              if ident not in b.get("through", []) and box.intersection(area).area > 1.0]
    if limits and min(limits) - b["base_z"] < RING_BAND[0]:
        return None
    low, high = band["D"] if want_tall else band["C"]
    want = high - (high - low) * (1.0 - min(b["size"][0] * b["size"][1] / 6400.0, 1.0))
    # a glass tower is slender: MAP puts no slenderness rule on the D7 band, and 7x the
    # narrow side is what lets a 32 m wide lot carry a 200 m shaft
    want = min(want, 7.0 * min(b["size"]), RING_BAND[1])
    for slot, cap in slots:
        if box.intersection(slot).area > 1.0:
            want = min(want, cap - b["base_z"])
    for limit in limits:
        want = min(want, limit - b["base_z"])
    top = geom.snap(want, C.FLOOR_MODULE)
    return top if top >= RING_BAND[0] else None
