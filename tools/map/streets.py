"""Street networks, per district: a connected hierarchy of avenues, streets and alleys.

The lead's note (round 2): the network comes first, the buildings follow. Each district
gets its own pattern and orientation, every corridor ends on another corridor, and the
leftovers are proper blocks that `lots.py` can subdivide:

    grid     D1 Harbor, D4 Civic, D5 Megablocks, D6 Foundry, D7 Financial
    contour  D3 Old Town - terrace lanes that follow the escarpment, plus cross lanes
    radial   D2 Interchange Knot - roads radiating from the knot, plus a ring road

Widths are MAP §4 "General": avenue 56-72 m, street 36-48 m, alley 24-32 m.
"""
from __future__ import annotations

import math
import random

from shapely import affinity as aff
from shapely.geometry import LineString, MultiLineString, Point, Polygon
from shapely.ops import nearest_points, unary_union

import geom
import mapconst as C
import zones as zone_stage

SNAP_MAX = 46.0          # an end this close to another corridor is snapped onto it
MIN_SEGMENT = 56.0       # shorter pieces are dropped rather than left dangling
MIN_AVENUE = 200.0       # a shorter avenue stub is demoted to a street
CLASSES = ("avenue", "street", "alley")


def _segments(piece) -> list[LineString]:
    if isinstance(piece, LineString):
        return [piece] if piece.length >= MIN_SEGMENT else []
    if isinstance(piece, MultiLineString):
        return [g for g in piece.geoms if g.length >= MIN_SEGMENT]
    return [g for g in getattr(piece, "geoms", []) if isinstance(g, LineString)
            and g.length >= MIN_SEGMENT]


def _family(area: Polygon, usable: Polygon, angle: float, spacing: float) -> list[LineString]:
    """Parallel lines at `angle` degrees across the district, clipped to free ground."""
    minx, miny, maxx, maxy = area.bounds
    cx, cy = (minx + maxx) / 2, (miny + maxy) / 2
    reach = max(maxx - minx, maxy - miny) * 0.85
    out: list[LineString] = []
    steps = int(reach / spacing) + 1
    for i in range(-steps, steps + 1):
        offset = i * spacing
        line = aff.rotate(LineString([(cx - reach, cy + offset), (cx + reach, cy + offset)]),
                          angle, origin=(cx, cy))
        out.extend(_segments(line.intersection(usable)))
    return out


def snap_ends(segments: list[LineString], targets) -> list[LineString]:
    """Pull each free end onto the nearest other corridor: no street may just stop."""
    if targets is None or targets.is_empty:
        return segments
    out = []
    for seg in segments:
        coords = list(seg.coords)
        for index in (0, len(coords) - 1):
            end = Point(coords[index])
            near = nearest_points(end, targets)[1]
            if end.distance(near) <= SNAP_MAX:
                coords[index] = (round(near.x, 1), round(near.y, 1))
        fixed = LineString(coords)
        if fixed.length >= MIN_SEGMENT and not fixed.is_simple is False:
            out.append(fixed)
    return out


def _record(did: str, kind: str, width: float, z: float, line: LineString,
            counter: list[int], w_r1: float = 0.0) -> dict:
    counter[0] += 1
    return {"id": f"{did.lower()}_{kind}_{counter[0]}", "kind": kind, "z": z,
            "width": float(width), "w_r1": float(w_r1 or width),
            "points": [[round(x, 1), round(y, 1)] for x, y in line.coords],
            "name": None, "district": did}


def _usable(area: Polygon, ground: Polygon, canal: Polygon, occupied) -> Polygon:
    return area.intersection(ground).difference(canal).difference(occupied)


def grid_network(did: str, pattern: dict, area: Polygon, usable: Polygon, z: float,
                 counter: list[int], rng: random.Random) -> list[dict]:
    """Rectilinear hierarchy: avenues one way, streets and alleys both ways."""
    out: list[dict] = []
    angle = pattern["angle_deg"]
    placed = []
    for kind in CLASSES:
        spacing = pattern[f"{kind}_spacing"]
        width = pattern[f"{kind}_width"]
        w_r1 = pattern.get(f"{kind}_w_r1", width)
        if spacing <= 0 or width <= 0:
            continue
        free = usable.difference(unary_union(placed).buffer(width / 2 + C.SETBACK)) \
            if placed else usable
        offsets = (0.0,) if kind == "avenue" else (0.0, 90.0)
        targets = unary_union(placed) if placed else None
        for offset in offsets:
            lines = _family(area, free, angle + offset, spacing)
            for line in snap_ends(lines, targets):
                out.append(_record(did, kind, width, z, line, counter, w_r1))
                placed.append(line)
    return out


def contour_network(did: str, pattern: dict, area: Polygon, usable: Polygon, z: float,
                    crest: list[list[float]], counter: list[int],
                    rng: random.Random) -> list[dict]:
    """Old Town: terrace lanes parallel to the escarpment plus steep cross lanes."""
    out: list[dict] = []
    placed: list[LineString] = []
    seam = geom.line(crest)
    for index, offset in enumerate(range(70, 620, int(pattern["street_spacing"]))):
        lane = _offset_lane(seam, float(offset), north_only=True)
        if lane is None:
            continue
        for line in _segments(lane.intersection(usable)):
            out.append(_record(did, "street" if index else "avenue", pattern["street_width"],
                               z, line, counter, pattern.get("street_w_r1")))
            placed.append(line)
    cross = _family(area, usable, pattern["angle_deg"] + 90.0, pattern["alley_spacing"] * 2.4)
    for line in snap_ends(cross, unary_union(placed) if placed else None):
        out.append(_record(did, "alley", pattern["alley_width"], z, line, counter,
                           pattern.get("alley_w_r1")))
    return out


def _offset_lane(seam: LineString, distance: float, north_only: bool = True):
    """A polyline running parallel to the crest, `distance` metres up-slope (north)."""
    side = "left" if not north_only else "right"
    try:
        band = seam.parallel_offset(distance, side)
    except Exception:                                    # noqa: BLE001 - degenerate seam
        return None
    if band.is_empty:
        return None
    parts = [g for g in getattr(band, "geoms", [band]) if isinstance(g, LineString)]
    if not parts:
        return None
    longest = max(parts, key=lambda g: g.length)
    coords = [(x, y) for x, y in longest.coords if not north_only or y > 60.0]
    return LineString(coords) if len(coords) > 1 else None


def radial_network(did: str, pattern: dict, area: Polygon, usable: Polygon, z: float,
                   centre: tuple[float, float], counter: list[int],
                   rng: random.Random) -> list[dict]:
    """The Knot district: roads radiating from the interchange plus one ring road."""
    out: list[dict] = []
    placed: list[LineString] = []
    reach = 420.0
    for i in range(8):
        angle = math.radians(pattern["angle_deg"] + i * 45.0)
        ray = LineString([centre, (centre[0] + reach * math.cos(angle),
                                   centre[1] + reach * math.sin(angle))])
        for line in _segments(ray.intersection(usable)):
            out.append(_record(did, "street", pattern["street_width"], z, line, counter,
                               pattern.get("street_w_r1")))
            placed.append(line)
    ring = Point(centre).buffer(230.0).exterior
    for line in _segments(ring.intersection(usable)):
        out.append(_record(did, "street", pattern["street_width"], z, line, counter,
                           pattern.get("street_w_r1")))
        placed.append(line)
    for line in snap_ends(_family(area, usable, pattern["angle_deg"],
                                  pattern["alley_spacing"] * 2.2),
                          unary_union(placed) if placed else None):
        out.append(_record(did, "alley", pattern["alley_width"], z, line, counter,
                           pattern.get("alley_w_r1")))
    return out


def _spines(zone: dict, pattern: dict, free: Polygon, counter: list[int]) -> list[dict]:
    """Hand-drawn corridors a zone's grid cannot produce: the ties that continue another
    district's corridor into this one (the Civic Quarter's axis off the Forum and its link
    east to the Ring Viaduct's M1 leg, MAP §4 D4)."""
    out: list[dict] = []
    for spine in pattern.get("spines", []):
        line = geom.line(spine["points"])
        for part in _segments(line.intersection(free.buffer(C.SETBACK))):
            record = _record(zone["tag"], spine.get("kind", "street"),
                             float(spine.get("width", pattern["street_width"])),
                             zone["ground_z"], part, counter,
                             float(spine.get("w_r1", pattern.get("street_w_r1", 0.0))))
            record["district"] = zone["district"]
            record["name"] = spine.get("name")
            if zone["quarter"]:
                record["quarter"] = zone["quarter"]
            out.append(record)
    return out


def build(rules: dict, plateau: Polygon, canal: Polygon, occupied, crest: list[list[float]],
          rng: random.Random) -> list[dict]:
    """Every zone's own network, in hierarchy order (all avenues, then streets...)."""
    half = C.HALF - 60.0
    square = geom.poly([[-half, -half], [half, -half], [half, half], [-half, half]])
    lower = geom.poly([[-C.HALF, -C.HALF], [C.HALF, -C.HALF], [C.HALF, C.HALF],
                       [-C.HALF, C.HALF]]).difference(plateau)
    out: list[dict] = []
    for zone in zone_stage.zones(rules):
        fp = zone["footprint"]
        area = geom.poly([[fp[0], fp[1]], [fp[2], fp[1]], [fp[2], fp[3]], [fp[0], fp[3]]])
        ground = plateau if zone["ground_z"] >= 31.0 else lower
        free = _usable(area, ground, canal, occupied).intersection(square)
        if free.is_empty:
            continue
        pattern = zone["streets"]
        did = zone["district"]
        counter = [0]
        mode = pattern.get("mode", "grid")
        if mode == "contour":
            made = contour_network(zone["tag"], pattern, area, free, zone["ground_z"],
                                   crest, counter, rng)
        elif mode == "radial":
            made = radial_network(zone["tag"], pattern, area, free, zone["ground_z"],
                                  tuple(pattern["centre"]), counter, rng)
        else:
            made = grid_network(zone["tag"], pattern, area, free, zone["ground_z"],
                                counter, rng)
        for street in made:
            street["district"] = did
            if zone["quarter"]:
                street["quarter"] = zone["quarter"]
        out += made
        out += _spines(zone, pattern, free, counter)
    for street in out:
        # a family line clipped by free ground leaves stubs: a 60 m fragment is not an avenue
        if street["kind"] == "avenue" and geom.length_of(street["points"]) < MIN_AVENUE:
            street["kind"] = "street"
            street["width"] = min(street["width"], C.STREET_MAX)
    return sorted(out, key=lambda s: (CLASSES.index(s["kind"]), s["id"]))
