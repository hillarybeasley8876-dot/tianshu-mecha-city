"""Street walls: the canyon faces that line the corridors, and the podiums that bridge them.

Two lead notes drive this stage (review r1, points 2 and 3):

* every corridor gets a built frontage - the block/lot machinery only reaches land that
  happens to survive as a block, and beside a wide avenue that land is a ribbon it drops;
* **podium-through** (MAP §4 "General"): in D4/D5/D7 a *street* (never an avenue, never the
  Ring Viaduct footprint) may pass through a building's podium through an arcade at least
  32 m clear and as wide as the street, with the tower carried over the roadway. The
  building declares `through` = the street ids it bridges and carries `holes`, so city-build
  can cut the arcade and L2 can accept the crossing.

Walls run first and hand their footprints to `fill.generate` as reserved land, so the two
stages can never build on top of each other.
"""
from __future__ import annotations

import math
import random

from shapely.geometry import Point, Polygon
from shapely.ops import unary_union
from shapely.strtree import STRtree

import fill
import geom
import fabric
import lots as lot_stage
import mapconst as C
import zones as zone_stage

WALL_KINDS = ("avenue", "street")
PODIUM_DISTRICTS = ("D4", "D5", "D7")
PODIUM_SHARE = 0.40          # MAP §4: at most 40 % of a street's length may be bridged
PODIUM_STEP = 72.0           # a portal every 72 m where the wall has no room to stand
MIN_LOT_AREA = 200.0        # m2: below this a kerb leftover is pavement, not a lot
WALL_LOT = 26.0              # kerb station spacing: fine enough to line a whole block
SLIVER = 6.0                 # m2 of a footprint may hang off the free land


def _square() -> Polygon:
    """The playable square, inset by the wall thickness: nothing may stand outside it (L7)."""
    half = C.HALF - C.SETBACK
    return geom.poly([[-half, -half], [half, -half], [half, half], [-half, half]])


def open_ground(rules: dict, mask: Polygon, canal: Polygon,
                plateau: Polygon) -> dict[str, Polygon]:
    """District ground that is not a corridor and not water - plazas and arena floors
    included. A podium's legs may stand on a plaza; only the roadway is off limits."""
    square = _square()
    lower = square.difference(plateau)
    out: dict[str, Polygon] = {}
    for zone in zone_stage.zones(rules):
        fp = zone["footprint"]
        ground = (plateau if zone["ground_z"] >= 31.0 else lower).intersection(square)
        area = geom.poly([[fp[0], fp[1]], [fp[2], fp[1]], [fp[2], fp[3]], [fp[0], fp[3]]])
        piece = area.intersection(ground).difference(canal).difference(mask)
        did = zone["district"]
        out[did] = out[did].union(piece) if did in out else piece
    return out


def free_land(rules: dict, mask: Polygon, canal: Polygon, plateau: Polygon,
              decks: list[dict], arenas: list[tuple[Polygon, float]]) -> dict[str, Polygon]:
    """Buildable land per district: inside the footprint, on its own ground, not spoken for.

    Same reservation rule as `fill.generate`, so the wall and the block machinery agree on
    what is for sale.
    """
    square = _square()
    lower = square.difference(plateau)
    out: dict[str, Polygon] = {}
    for zone in zone_stage.zones(rules):
        fp = zone["footprint"]
        ground_z = zone["ground_z"]
        ground = (plateau if ground_z >= 31.0 else lower).intersection(square)
        area = geom.poly([[fp[0], fp[1]], [fp[2], fp[1]], [fp[2], fp[3]], [fp[0], fp[3]]])
        ground_arenas = unary_union([poly for poly, head in arenas if head <= ground_z])
        reserved = fill.reserved_space(rules, decks, ground_arenas)
        piece = area.intersection(ground).difference(canal).difference(mask) \
            .difference(reserved)
        did = zone["district"]
        out[did] = out[did].union(piece) if did in out else piece
    return out


class Occupancy:
    """Everything already placed, so two stages never build the same ground twice."""

    def __init__(self) -> None:
        self._boxes: list[Polygon] = []
        self._tree: STRtree | None = None

    def add(self, box: Polygon) -> None:
        """Rebuild on every add: a stale index would let two kerb lots overlap."""
        self._boxes.append(box)
        self._tree = STRtree(self._boxes)

    def rebuild(self) -> None:
        self._tree = STRtree(self._boxes) if self._boxes else None

    def union(self) -> Polygon:
        return unary_union(self._boxes) if self._boxes else Polygon()

    def hits(self, box: Polygon) -> bool:
        if self._tree is None:
            return False
        return any(self._boxes[i].intersection(box).area > SLIVER
                   for i in self._tree.query(box))


def zone_at(rules: dict, x: float, y: float, z: float = 0.0) -> str | None:
    """Which build zone a point falls in, by its footprint and its ground datum.

    Graph corridors carry no district tag, and the footprints meet at the escarpment, so
    the corridor's own datum breaks the tie. A zone is narrower than its district (the
    Civic Quarter is D4's plateau ground), which is why this and `district_at` both exist.
    """
    best = None
    for zone in zone_stage.zones(rules):
        fp = zone["footprint"]
        if fp[0] <= x <= fp[2] and fp[1] <= y <= fp[3]:
            if abs(zone["ground_z"] - z) < 1.0:
                return zone["id"]
            best = best or zone["id"]
    return best


def district_at(rules: dict, x: float, y: float, z: float = 0.0) -> str | None:
    """The district tag a point falls in, or None outside every footprint."""
    zone = zone_at(rules, x, y, z)
    if zone is None:
        return None
    return next(z["district"] for z in zone_stage.zones(rules) if z["id"] == zone)


def land_at(free: dict[str, Polygon], rules: dict, x: float, y: float,
            z: float) -> tuple[str, Polygon, str] | None:
    """The district a point belongs to, its free land and the zone whose rules apply.

    An avenue that crosses two districts has to be walled from both, so this is asked per
    site, not per street.
    """
    zone_id = zone_at(rules, x, y, z)
    if zone_id is None:
        return None
    did = next(z["district"] for z in zone_stage.zones(rules) if z["id"] == zone_id)
    if did not in free:
        return None
    return did, free[did], zone_id


def kerb_sites(street: dict, lot_w: float) -> list[tuple[Point, float, float]]:
    """(station on the centreline, outward normal, along-street axis) for both kerbs."""
    line = geom.line(street["points"])
    out: list[tuple[Point, float, float]] = []
    d = lot_w * 0.5
    while d < line.length - 4.0:
        here = line.interpolate(d)
        ahead = line.interpolate(min(d + 6.0, line.length))
        tx, ty = ahead.x - here.x, ahead.y - here.y
        norm = math.hypot(tx, ty)
        if norm > 1e-6:
            out.append((here, math.degrees(math.atan2(ty, tx)), d))
        d += lot_w
    return out


def probe_depth(free: Polygon, here: Point, nx: float, ny: float, start: float,
                limit: float) -> float:
    """How far the free land reaches from the kerb outward, capped at `limit`."""
    depth = 0.0
    while depth + 4.0 <= limit:
        p = Point(here.x + nx * (start + depth + 4.0), here.y + ny * (start + depth + 4.0))
        if not free.contains(p):
            break
        depth += 4.0
    return depth


def fit_lot(free: Polygon, here: Point, nx: float, ny: float, kerb: float, lot_w: float,
            lot_d: float, axis: float) -> tuple[tuple[float, float], float, float, float] | None:
    """The kerb lot at this station: the site's share of the free land, squared off.

    A kerb is a ragged boundary - the next street's setback, a plaza corner, a deck edge -
    so the lot is the free land clipped to the station's reach and then squared to the
    biggest rectangle that fits in it, instead of being thrown away when the corner of an
    ideal lot hangs over a plaza.
    """
    reach = geom.rect((here.x + nx * (kerb + lot_d / 2), here.y + ny * (kerb + lot_d / 2)),
                      (lot_w, lot_d), axis)
    patch = reach.intersection(free)
    if patch.is_empty or patch.area < MIN_LOT_AREA:
        return None
    parts = [g for g in getattr(patch, "geoms", [patch]) if isinstance(g, Polygon)]
    if not parts:
        return None
    best = max(parts, key=lambda g: g.area)
    fit = lot_stage.largest_inscribed_rect(best, axis)
    if fit is None or fit[3] < MIN_LOT_AREA:
        return None
    # the fit carries its own rotation - the free land is not always square to the kerb -
    # and the lot has to be built at that angle, not at the street's
    return fit[0], fit[1][0], fit[1][1], fit[2]


def wall_row(street: dict, rules: dict, glob: dict, free: dict[str, Polygon],
             occ: Occupancy, heads: list, arenas: list, rng: random.Random,
             index: list[int], out: list[dict]) -> int:
    """One street's two kerbs: a lot every `lot_w` metres, as deep as the free land allows."""
    placed = 0
    kerb = street["width"] / 2 + C.SETBACK
    spire = tuple(glob["spire_center"])
    base_z = float(street["z"])
    for here, axis, _d in kerb_sites(street, WALL_LOT):
        rad = math.radians(axis)
        for side in (1.0, -1.0):
            nx, ny = -math.sin(rad) * side, math.cos(rad) * side
            site = land_at(free, rules, here.x, here.y, base_z)
            if site is None:
                continue
            did, land, zone_id = site
            rule = {"buildings": zone_stage.rule_of(rules, zone_id)["buildings"]}
            lot_w, lot_d = rule["buildings"]["lot"]
            fit = fit_lot(land, here, nx, ny, kerb, lot_w, lot_d, axis)
            if fit is None:
                continue
            centre, _w, _d, lot_axis = fit
            box = geom.rect(centre, (_w, _d), lot_axis)
            if occ.hits(box):
                continue
            # take the ground out of play so the next station sees what is really left
            free[did] = land = land.difference(box)
            record = lot_stage.building_from_lot(box, lot_axis, did, rule, glob, base_z,
                                                 spire, 0.0, rng, index[0] + 1)
            if record is None:
                continue
            record["height"] = geom.snap(
                min(record["height"],
                    lot_stage.head_cap(box, heads, arenas) - base_z), C.FLOOR_MODULE)
            if record["height"] < 12.0:
                continue
            lot_stage.refresh_roof(record, glob)
            record["id"] = f"{did}_w{index[0]:03d}"
            record["fronts"] = street["id"]
            index[0] += 1
            occ.add(geom.rect(tuple(record["center"]), tuple(record["size"]), record["rot"]))
            out.append(record)
            placed += 1
    return placed


def podium_row(street: dict, did: str, rule: dict, glob: dict, free: Polygon, occ: Occupancy,
               rng: random.Random, index: list[int], out: list[dict]) -> float:
    """Bridge this street with a podium whose ground storey is an arcade.

    Returns the bridged length. The opening is the full width of the street and at least
    `ARCADE_CLEAR` long (MAP §4); the two flanks carry the podium and the tower above it.
    A kerb only has room for a portal every so often, so the span and the flank depth are
    both tried from generous to tight and the first that stands on free ground wins.
    """
    budget = PODIUM_SHARE * geom.length_of(street["points"])
    if budget < C.ARCADE_CLEAR:
        return 0.0
    spire = tuple(glob["spire_center"])
    base_z = float(street["z"])
    bridged = 0.0
    for here, axis, _d in kerb_sites(street, PODIUM_STEP):
        if bridged >= budget:
            break
        rad = math.radians(axis)
        fit = _portal(here, rad, axis, street, free, occ)
        if fit is None:
            continue
        centre, span, across = fit
        box = geom.rect(centre, (span, across), axis)
        record = _podium_record(street, did, rule, glob, centre, span, across, axis,
                                base_z, spire, rng, index[0] + 1)
        index[0] += 1
        occ.add(box)
        out.append(record)
        bridged += span
    return bridged


def _portal(here: Point, rad: float, axis: float, street: dict, free: Polygon,
            occ: Occupancy) -> tuple[tuple[float, float], float, float] | None:
    """The widest portal that stands on free ground at this station."""
    for span in (C.ARCADE_CLEAR + 24.0, C.ARCADE_CLEAR + 8.0, C.ARCADE_CLEAR):
        for flank in (48.0, 32.0, 20.0, 12.0):
            across = street["width"] + 2.0 * (C.SETBACK + flank)
            centre = (here.x, here.y)
            box = geom.rect(centre, (span, across), axis)
            # the arcade opening is the roadway plus its setback on both sides
            flanks = box.difference(
                geom.rect(centre, (span, street["width"] + 2.0 * C.SETBACK), axis))
            if flanks.difference(free).area > SLIVER or occ.hits(flanks):
                continue
            return centre, span, across
    return None


def _podium_record(street: dict, did: str, rule: dict, glob: dict,
                   centre: tuple[float, float], span: float, across: float, axis: float,
                   base_z: float, spire: tuple[float, float], rng: random.Random,
                   index: int) -> dict:
    """A podium_tower whose ground storey is an arcade over the street it bridges."""
    podium_h = 32.0
    band = rule["buildings"].get("tier_h", glob["tier_h"])
    tier = lot_stage.weighted(rule["buildings"]["podium_tier_mix"], rng)
    height = geom.snap(rng.uniform(*band[tier]), C.FLOOR_MODULE)
    height = max(height, podium_h + 48.0)
    height = min(height, geom.snap(lot_stage.spire_cap(spire, centre[0], centre[1],
                                                      glob["spire_cap_r"],
                                                      glob.get("spire_cap_top", 200.0)),
                                   C.FLOOR_MODULE))
    hole = geom.rect_points(centre, (span, street["width"] + 2.0 * C.SETBACK), axis)
    record = {
        "id": f"{did}_p{index:03d}", "district": did, "tier": tier,
        "archetype": "podium_tower", "center": [round(centre[0], 1), round(centre[1], 1)],
        "size": [round(span, 1), round(across, 1)], "rot": round(axis % 180.0, 1),
        "base_z": base_z, "height": height, "podium_z": base_z + podium_h,
        "roof_walkable": False, "breaches": [],
        "fronts": street["id"], "through": [street["id"]],
        "holes": [{"polygon": hole, "z": base_z, "height": podium_h,
                   "clear": C.ARCADE_CLEAR}],
    }
    lot_stage.refresh_roof(record, glob)
    return record


def build_podiums(rules: dict, streets: list[dict], mask: Polygon, canal: Polygon,
                  plateau: Polygon, ring: Polygon, keep_clear: list[tuple[Polygon, float]],
                  rng: random.Random) -> tuple[list[dict], dict]:
    """Podium-through blocks first: a portal claims its two kerbs before anything else does.

    They only need ground that is not a roadway, so plazas and arena floors are fair game
    for their legs; the block machinery and the walls then treat them as built land.
    """
    glob = rules["global"]
    open_land = open_ground(rules, mask, canal, plateau)
    # a keep-clear slot is a lead vista: its height cap means a normal mass stops under the
    # sightline, but a podium tower is tall by construction, so no podium may stand in one
    if keep_clear:
        slots = unary_union([area for area, _cap in keep_clear])
        open_land = {k: v.difference(slots) for k, v in open_land.items()}
    occ = Occupancy()
    out: list[dict] = []
    stats = {"podium": 0, "bridged_m": 0.0}
    index = [0]
    for street in streets:
        if street["kind"] != "street":
            continue
        line = geom.line(street["points"])
        mid = line.interpolate(line.length / 2)
        zone_id = zone_at(rules, mid.x, mid.y, street["z"])
        did = street.get("district") or district_at(rules, mid.x, mid.y, street["z"])
        if did not in PODIUM_DISTRICTS or zone_id is None or open_land[did].is_empty:
            continue
        if ring.intersects(line.buffer(street["width"] / 2)):
            continue                       # MAP §4: never over the Ring Viaduct footprint
        stats["bridged_m"] += podium_row(street, did, zone_stage.rule_of(rules, zone_id), glob,
                                         open_land[did], occ, rng, index, out)
    stats["podium"] = len(out)
    stats["occupied"] = occ.union()
    return out, stats


def build_walls(rules: dict, streets: list[dict], placed: list[dict], mask: Polygon,
                canal: Polygon, plateau: Polygon, decks: list[dict],
                arenas: list[tuple[Polygon, float]], caps: list[tuple[Polygon, float]],
                rng: random.Random) -> tuple[list[dict], dict]:
    """Kerb walls for every avenue and street, on whatever land the blocks left over.

    Two passes: the first lines the kerbs, the second picks up the pockets the first one
    boxed in.
    """
    glob = rules["global"]
    # 1 m of tolerance: a lot that sits exactly on the setback line must not fail on
    # rounding, and a kerb is never a clean straight edge anyway
    free = {k: v.buffer(1.0) for k, v in
            free_land(rules, mask, canal, plateau, decks, arenas).items()}
    heads = fill.deck_heads(decks) + caps
    occ = Occupancy()
    for b in placed:
        box = geom.rect(tuple(b["center"]), tuple(b["size"]), b["rot"])
        occ.add(box)
        free[b["district"]] = free[b["district"]].difference(box.buffer(fabric.GAP))
    out: list[dict] = []
    stats = {"wall": 0}
    index = [0]
    ordered = sorted(streets, key=lambda s: WALL_KINDS.index(s["kind"])
                     if s["kind"] in WALL_KINDS else 9)
    for _pass in range(2):
        before = stats["wall"]
        for street in ordered:
            if street["kind"] not in WALL_KINDS:
                continue
            stats["wall"] += wall_row(street, rules, glob, free, occ, heads, arenas,
                                      rng, index, out)
        if stats["wall"] == before:
            break
    return out, stats
