"""Buildings on lots: the record one parcel becomes (lead note, round 2, point 2).

The block and lot geometry lives in fabric.py; this module turns one lot into one
building record - tier, height, slenderness, the Spire cone - and finds the biggest
rectangle that fits a lot that is not already one. It also owns the ground a lot may
stand on at all: `street_mask` (the streets with their setback) and `land_freed`, the
per-district measure of what the MAP §4 street widths gave back.
"""
from __future__ import annotations

import math
import random

from shapely.geometry import Point, Polygon, box as sbox
from shapely import affinity
from shapely.ops import polylabel, unary_union

import fabric
import geom
import mapconst as C
import zones as zone_stage

GAP = fabric.GAP                 # re-exported: the kerb walls pack their lots with this gap
SLENDERNESS = fabric.SLENDERNESS
LOT_MIN_AREA = fabric.LOT_MIN_AREA

def dominant_edge_angle(poly: Polygon) -> float:
    """Direction of the polygon's longest edge, in degrees."""
    coords = list(poly.exterior.coords)
    best, angle = 0.0, 0.0
    for a, b in zip(coords, coords[1:]):
        length = math.dist(a, b)
        if length > best:
            best = length
            angle = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
    return angle


SCALES = (1.0, 0.88, 0.76, 0.64, 0.52, 0.42)
OFFSETS = (0.0, -0.12, 0.12, -0.24, 0.24)
GOOD_ENOUGH = 0.9
RECT_LOT = 0.96      # a lot this close to its bounding rectangle is used as it is


def largest_inscribed_rect(lot: Polygon, axis: float) -> tuple[tuple[float, float],
                                                              tuple[float, float], float] | None:
    """Biggest rectangle that fits inside `lot`, aligned to `axis`.

    Blocks are not rectangles: a corner lot has cut corners and a leftover beside a viaduct
    is a wedge. Searching the scale and the offset of the rectangle around the lot's pole of
    inaccessibility fills the lot properly instead of dropping a small box in its middle.
    """
    rect = lot.minimum_rotated_rectangle
    # ...but only when the bounding rectangle really is the lot: 4 % of a corner lot is
    # enough to hang a wall over a street, which is exactly what L2 forbids
    if lot.area >= RECT_LOT * rect.area and rect.difference(lot).area <= 1.0:
        # the lot is already the rectangle: a terrace house or a kerb lot clipped to a clean
        # patch. Searching again would only find the same box by trial and error.
        rc = list(rect.exterior.coords)[:-1]
        ang = math.degrees(math.atan2(rc[1][1] - rc[0][1], rc[1][0] - rc[0][0]))
        return ((rect.centroid.x, rect.centroid.y),
                (math.dist(rc[0], rc[1]), math.dist(rc[1], rc[2])), ang, rect.area)
    try:
        pole = polylabel(lot, tolerance=1.5)
    except Exception:                                    # noqa: BLE001 - degenerate lot
        pole = lot.centroid
    rc = list(rect.exterior.coords)[:-1]
    side_a, side_b = math.dist(rc[0], rc[1]), math.dist(rc[1], rc[2])
    # `axis` is the lot's grain: the rectangle has to be sized along it, not by length,
    # or a lot whose long side runs across the grain gets a 90-degree box that never fits
    ang_a = math.degrees(math.atan2(rc[1][1] - rc[0][1], rc[1][0] - rc[0][0]))
    ang_b = math.degrees(math.atan2(rc[2][1] - rc[1][1], rc[2][0] - rc[1][0]))
    if abs(math.cos(math.radians(ang_a - axis))) >= abs(math.cos(math.radians(ang_b - axis))):
        base_w, base_d = side_a, side_b
    else:
        base_w, base_d = side_b, side_a
    rad = math.radians(axis)
    ux, uy = math.cos(rad), math.sin(rad)
    vx, vy = -uy, ux
    best = None
    for ws in SCALES:
        for ds in SCALES:
            w, d = base_w * ws, base_d * ds
            if best is not None and w * d <= best[3]:
                continue
            for du in OFFSETS:
                for dv in OFFSETS:
                    centre = (pole.x + ux * w * du + vx * d * dv,
                              pole.y + uy * w * du + vy * d * dv)
                    box = geom.rect(centre, (w, d), axis)
                    if lot.contains(box):
                        area = w * d
                        if best is None or area > best[3]:
                            best = (centre, (w, d), axis, area)
                        break
                if best is not None and best[3] >= w * d:
                    break
            # a rectangle that already covers most of the lot is the answer: the remaining
            # scales only cost time, and this search runs thousands of times per build
            if best is not None and best[3] >= base_w * base_d * GOOD_ENOUGH:
                return best
    return best


def building_from_lot(lot: Polygon, axis: float, did: str, rule: dict, glob: dict,
                      base_z: float, spire: tuple[float, float], front: float | None,
                      rng: random.Random, index: int) -> dict | None:
    """One building on one lot: the lot sets the footprint, the district sets the tier."""
    tier = weighted(rule["buildings"]["tier_mix"], rng)
    band = rule["buildings"].get("tier_h", glob["tier_h"])[tier]
    fit = largest_inscribed_rect(lot, axis)
    if fit is None or fit[3] < LOT_MIN_AREA * 0.6:
        return None
    centre, size, rot, _area = fit
    height = geom.snap(rng.uniform(*band), C.FLOOR_MODULE)
    height = min(height, geom.snap(spire_cap(spire, centre[0], centre[1],
                                             glob["spire_cap_r"],
                                             glob.get("spire_cap_top", 200.0)),
                                   C.FLOOR_MODULE))
    rise = rule["buildings"].get("north_rise")
    if rise is not None:
        # a district whose skyline has to read as a backdrop (the Civic Quarter): the mass
        # gets taller toward the north edge, so the Spire stands in front of a wall of city
        height = max(height, geom.snap(_north_rise(rise, centre[1]), C.FLOOR_MODULE))
    if front is not None:
        # street wall: an avenue frontage keeps the cornice line of its district band
        height = min(height, max(band[0], rule["buildings"].get("wall_cap", band[1])))
    # slenderness: a 240 m tower on a 19 m kerb lot is a needle, not architecture, and it
    # is what eats the Spire's silhouette from street level
    height = min(height, geom.snap(SLENDERNESS.get(tier, 4.0) * min(size), C.FLOOR_MODULE))
    if height < 12.0:
        return None
    top = base_z + height
    return {
        "id": f"{did}_b{index:03d}", "district": did, "tier": tier,
        "archetype": rng.choice(rule["buildings"]["archetypes"]),
        "center": [round(centre[0], 1), round(centre[1], 1)],
        "size": [round(size[0], 1), round(size[1], 1)], "rot": round(rot % 180.0, 1),
        "base_z": base_z, "height": height,
        "roof_walkable": tier in ("C", "D") and
        glob["l4_band"][0] <= top <= glob["l4_band"][1] + 24,
        "breaches": [],
    }


def _north_rise(rise: dict, y: float) -> float:
    """Floor height a site must reach, interpolated from the district's north edge ramp."""
    span = max(float(rise["y1"]) - float(rise["y0"]), 1.0)
    t = min(max((y - float(rise["y0"])) / span, 0.0), 1.0)
    return float(rise["h0"]) + (float(rise["h1"]) - float(rise["h0"])) * t


def weighted(mix: dict, rng: random.Random) -> str:
    roll = rng.random() * sum(mix.values())
    for tier, weight in mix.items():
        roll -= weight
        if roll <= 0:
            return tier
    return next(iter(mix))


def spire_cap(center: tuple[float, float], x: float, y: float, cap_r: float,
              top: float = 200.0) -> float:
    """Skyline break around the Spire: near the shaft nothing may rise into its silhouette.

    This is the lead's "cap heights inside the Spire's view cones" (review r1, point 3):
    the cone rises linearly from 48 m at the shaft to `top` at `cap_r`, so the mass gets
    lower the closer it stands to the weenie instead of being thinned out.
    """
    r = math.hypot(x - center[0], y - center[1])
    return 1e9 if r >= cap_r else max(48.0, top * (r / cap_r))


def head_cap(box: Polygon, heads: list[tuple[Polygon, float]],
             arenas: list[tuple[Polygon, float]]) -> float:
    """Highest top this footprint may reach: the lowest slab it is meaningfully under.

    L2 fails on any overlap of a square metre or more, so the cap has to bite at the same
    threshold: a tower whose corner clips a viaduct band by two square metres is still
    standing in the corridor.
    """
    need = 1.0
    tops = [head for area, head in heads + arenas if box.intersection(area).area > need]
    return min(tops) if tops else 1e9


def refresh_roof(record: dict, glob: dict) -> None:
    """A capped tower may no longer reach the walkable L4 band."""
    record["roof_walkable"] = record["tier"] in ("C", "D") and \
        glob["l4_band"][0] <= record["base_z"] + record["height"] <= glob["l4_band"][1] + 24


def street_mask(parts: dict, extra: list[Polygon] = (), width_key: str = "width") -> Polygon:
    """Ground a building may not stand on: the streets, with their setback.

    Tunnels are 40 m down and the viaducts and rails are 32-80 m up, so their *footprints*
    are buildable: a warehouse can stand over a tunnel and an industrial hall can stand under
    the Ring Viaduct. What those corridors forbid is height, which `corridors.height_caps`
    handles. `width_key` = "w_r1" rebuilds the pre-revision bands, so the freed land is measured.
    """
    shapes = [geom.line(item["points"]).buffer(item[width_key] / 2 + C.SETBACK)
              for item in parts["streets"]]
    shapes.extend(extra)
    return unary_union(shapes) if shapes else Polygon()


def land_freed(rules: dict, parts: dict, plateau: Polygon, canal: Polygon) -> dict:
    """Non-corridor land per district, now and under the r1 widths (MAP §4 revision)."""
    now, before = street_mask(parts), street_mask(parts, width_key="w_r1")
    lower = geom.poly([[-C.HALF, -C.HALF], [C.HALF, -C.HALF], [C.HALF, C.HALF],
                       [-C.HALF, C.HALF]]).difference(plateau)
    out: dict[str, tuple[float, float]] = {}
    for zone in zone_stage.zones(rules):
        fp = zone["footprint"]
        ground = plateau if zone["ground_z"] >= 31.0 else lower
        area = geom.poly([[fp[0], fp[1]], [fp[2], fp[1]], [fp[2], fp[3]],
                          [fp[0], fp[3]]]).intersection(ground).difference(canal)
        got = out.setdefault(zone["district"], (0.0, 0.0))
        out[zone["district"]] = (got[0] + area.difference(now).area,
                                 got[1] + area.difference(before).area)
    return out
