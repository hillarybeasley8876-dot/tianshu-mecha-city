"""The 3D model the route checks sweep: every solid the Blender build really puts in the world.

`hive_rule.solids` is a 2.5D sight model (a box, a z span, an id). This one is the same idea
carried to the pieces a *route* has to fit through, because the r8 acceptance pass drove the mech
up every designed route and found the routes were drawn in plan only (lead, r8 items 1-4):

* the parapet is a real 2 m wall round every deck rim (`kit/decks.py::_parapet`), so a ramp that
  arrives at a rim needs a declared `openings` segment - the field this round adds;
* a `span` deck carries a truss collider 3 m under its slab top (`kit/decks.py::_truss`), which is
  the z 33 ceiling the verifier wedged under at the +40 canopies;
* viaducts and rails are slabs with edge barriers and piers (`kit/corridors.py`);
* the landmarks the builder makes are solids too - except the Knot, whose collision is the
  layout's own decks and connectors from r8 on (lead decision, r16).

Nothing here reads the generator's geometry: the argument is always the written layout dict.
"""
from __future__ import annotations

import math

from shapely.geometry import LineString, Point, Polygon, box as sbox
from shapely.ops import unary_union
from shapely.strtree import STRtree

import geom
import mapconst as C

CLEAR = C.UNDER_DECK_CLEAR      # 24 m: MAP L3, the capsule's own headroom
MAX_DEG = C.MAX_RAMP_DEG        # 20 deg: MAP L3
MAX_FLIGHT_RISE = 32.0          # dossier C8: one stair flight
MIN_LANDING = 8.0               # m: a landing between two flights
STEP = 4.0                      # m: the sample step along a path
TOP_AIR = 16.0                  # m: clear air over a lift / vent / vcat top stop
PARAPET_T = 2.0                 # m: kit/decks.py PARAPET_T
COLUMN_W = 9.0                  # m: kit/decks.py COLUMN_W
VIADUCT_T = 6.0                 # m: kit/corridors.py viaduct slab
RAIL_T = 4.0                    # m: kit/corridors.py rail slab
BARRIER_H = 5.0                 # m: kit/corridors.py BARRIER_H
PIER_W = 14.0                   # m: kit/corridors.py PIER_W
TRUSS_TOP = 1.0                 # m into the slab: kit/decks.py::_truss
TRUSS_DEPTH = 4.0               # m: the truss collider's own height

Solid = tuple[Polygon, float, float, str]

# Lead, r8 item 1 asks for the O4 -> O5 stair to climb OUTSIDE the pagoda's solid tiers, and it
# does. What it cannot do is stand on node O4 itself: the dossier puts O4 on the pagoda's axis
# and `kit/landmarks.py::pagoda` stacks its 53.8 m base tier from z 32 up, so the node has 13.7 m
# of headroom and no 16 m mech can be there. The stair's own geometry is checked in full; only the
# pagoda's own tiers are set aside, with the fix named.
PARTIAL_EXEMPT = {
    "con_O4_O5_stairs": (
        "stilt_pagoda",
        "city-build r11: open the Stilt Pagoda's base tier (z 32-46, 53.8 m wide) on the stair's "
        "side - node O4 stands inside it with 13.7 m of headroom"),
}


def exempt_blocker(con_id: str, sid: str) -> str:
    """The reason this blocker is set aside for this connector, "" when it is not."""
    row = PARTIAL_EXEMPT.get(con_id)
    return row[1] if row and sid.startswith(row[0]) else ""


def _ring(poly: Polygon, width: float) -> Polygon:
    """The band a parapet occupies: `width` thick, centred on the rim."""
    return poly.boundary.buffer(width * 0.5, cap_style=2)


def _openings(item: dict) -> Polygon:
    """The declared gaps in a deck's parapet, as one polygon to subtract from the band.

    An opening is a plan POLYGON (`docs/MAP.md` §3, r8): the builder skips every parapet or
    barrier segment whose midpoint falls inside one, which is the only shape that survives a
    deck being perforated into islands.
    """
    polys = [geom.poly(op["poly"]) for op in item.get("openings", [])]
    return unary_union(polys) if polys else Polygon()


def deck_solids(deck: dict) -> list[Solid]:
    """Slab, parapet (minus its declared openings), columns and the span truss."""
    area = geom.poly(deck["polygon"])
    for hole in deck.get("holes", []):
        area = area.difference(geom.poly(hole))
    z, thick = float(deck["z"]), float(deck["thickness"])
    out: list[Solid] = [(area, z - thick, z, deck["id"])]
    parapet = float(deck.get("parapet", 0.0))
    if parapet > 0.1 and not area.is_empty:
        band = _ring(area, PARAPET_T).difference(_openings(deck))
        if not band.is_empty:
            out.append((band, z, z + parapet, f"{deck['id']}_parapet"))
    for i, col in enumerate(deck.get("columns", [])):
        out.append((sbox(col[0] - COLUMN_W / 2, col[1] - COLUMN_W / 2,
                         col[0] + COLUMN_W / 2, col[1] + COLUMN_W / 2),
                    -40.0, z, f"{deck['id']}_col{i}"))
    if deck.get("span") and not area.is_empty:
        # The truss collider is the polygon's bounding box (`kit/decks.py::_truss`), minus the
        # deck's own holes: a light well cut for a route has to open the truss too, or the well
        # is a hole in the slab with a ceiling 3 m under it.
        minx, miny, maxx, maxy = geom.poly(deck["polygon"]).bounds
        truss = sbox(minx, miny, maxx, maxy)
        for hole in deck.get("holes", []):
            truss = truss.difference(geom.poly(hole["polygon"]
                                               if isinstance(hole, dict) else hole))
        if not truss.is_empty:
            out.append((truss, z - TRUSS_DEPTH + TRUSS_TOP, z + TRUSS_TOP,
                        f"{deck['id']}_truss"))
    return out


def barrier_band(item: dict, barrier: float):
    """(the two edge barriers of a viaduct or rail as one band, the declared gaps in them)."""
    pts = item["points"]
    half = float(item["width"]) / 2
    edges = [_offset(pts, side * (half - barrier / 2)).buffer(barrier / 2, cap_style=2)
             for side in (-1.0, 1.0)]
    band = unary_union(edges)
    return band, _openings(item)


def corridor_solids(item: dict, thickness: float, barrier: float) -> list[Solid]:
    """A viaduct or a rail: slab, two edge barriers (minus their openings) and the piers."""
    pts = item["points"]
    half = float(item["width"]) / 2
    z = float(item["z"])
    slab = geom.line(pts).buffer(half, cap_style=2)
    for hole in item.get("holes", []):
        slab = slab.difference(geom.poly(hole))
    out: list[Solid] = [(slab, z - thickness, z, item["id"])]
    if barrier > 0:
        band, gaps = barrier_band(item, barrier)
        band = band.difference(gaps)
        if not band.is_empty:
            out.append((band, z + 0.2, z + 0.2 + BARRIER_H, f"{item['id']}_barrier"))
    for i, pier in enumerate(item.get("piers", [])):
        out.append((sbox(pier[0] - PIER_W / 2, pier[1] - PIER_W / 2,
                         pier[0] + PIER_W / 2, pier[1] + PIER_W / 2),
                    -40.0, z - thickness, f"{item['id']}_pier{i}"))
    return out


def tunnel_solids(item: dict) -> list[Solid]:
    """The lining: two walls and the roof, with the shafts' declared holes cut out of the roof."""
    pts = item["points"]
    half = float(item["width"]) / 2
    z, clear = float(item["z"]), float(item["clear"])
    lining = geom.line(pts).buffer(half + 6.0, cap_style=2)
    for hole in item.get("holes", []):
        lining = lining.difference(geom.poly(hole))
    out: list[Solid] = [(lining, z + clear, z + clear + 2.0, f"{item['id']}_roof")]
    walls = geom.line(pts).buffer(half + 6.0, cap_style=2).difference(
        geom.line(pts).buffer(half, cap_style=2))
    for hole in item.get("openings", []):
        walls = walls.difference(geom.poly(hole["poly"]))
    if not walls.is_empty:
        out.append((walls, z - 4.0, z + clear, f"{item['id']}_wall"))
    return out


def landmark_solids(layout: dict) -> list[Solid]:
    """The colliders the landmark builders make, from the landmark's own params.

    The Knot is deliberately absent: from r8 the layout's decks and connectors ARE its
    collision and `kit/landmarks.py::knot` keeps only dressing (lead decision, r16). The
    Crystal Bridge is render-only - `kit/bridge.py` registers no collision at all.
    """
    out: list[Solid] = []
    for lm in layout.get("landmarks", []):
        kind, p = lm["kind"], lm.get("params", {})
        x, y, z = (float(v) for v in lm["pos"])
        if kind == "pagoda":
            out += _pagoda(lm, x, y, z, p)
        elif kind == "cranes":
            # r16: city-build r11 lowers the H3 cab under the deck (z 40-48); modelled there.
            cab = float(p["cab_z"])
            for i, (cx, cy) in enumerate(p["positions"]):
                out.append((sbox(cx - 26, cy - 22, cx + 26, cy + 22),
                            cab, cab + 8.0, f"{lm['id']}_cab{i}"))
        elif kind == "stacks":
            r, top = float(p["radius"]), float(p["top_z"])
            for i, (cx, cy) in enumerate(p["positions"]):
                out.append((sbox(cx - r, cy - r, cx + r, cy + r), 0.0, top,
                            f"{lm['id']}_stack{i}"))
        elif kind == "spire":
            out += _spire(lm, layout, x, y, p)
    return out


def _pagoda(lm: dict, x: float, y: float, z: float, p: dict) -> list[Solid]:
    """`kit/landmarks.py::pagoda`: 7 stacked octagon prisms, each 0.88 of the one below."""
    fw, fd = (float(v) for v in p["footprint"])
    top, tiers = float(p["top_z"]), int(p["tiers"])
    out: list[Solid] = []
    f = 1.0
    for i in range(tiers):
        za = z + (top - z) * i / tiers
        zb = z + (top - z) * (i + 1) / tiers
        out.append((sbox(x - fw * 0.42 * f, y - fd * 0.42 * f,
                         x + fw * 0.42 * f, y + fd * 0.42 * f), za, zb, f"{lm['id']}_tier{i}"))
        f *= 0.88
    return out


# `kit/spire.py`: the (z, radius) knots of the flared shaft and of the neck above the soffit.
TRUMPET = ((26.0, 44.0), (74.0, 38.0), (110.0, 34.0), (140.0, 34.5),
           (170.0, 39.0), (196.0, 48.0), (214.0, 58.0), (218.0, 60.0))
NECK = ((214.0, 36.0), (256.0, 34.0), (300.0, 20.0), (336.0, 8.0), (360.0, 2.0))
CROWN_RIB_BASE = 120.0
RIB_N = 10


def _spire(lm: dict, layout: dict, x: float, y: float, p: dict) -> list[Solid]:
    """Plinth, flared shaft, the two ring drums and the ten Crown ribs (`kit/spire.py`)."""
    base_r = float(p["base_radius"])
    k = base_r / 70.0
    z_soffit = float(p["crown_deck_z"]) - 6.0
    out: list[Solid] = [
        (sbox(x - base_r, y - base_r, x + base_r, y + base_r), -2.0, 8.0, f"{lm['id']}_plinth"),
        (sbox(x - base_r * 0.9, y - base_r * 0.9, x + base_r * 0.9, y + base_r * 0.9),
         2.0, 28.0, f"{lm['id']}_steps")]
    for knots, tag in ((TRUMPET, "shaft"), (NECK, "neck")):
        for i, ((z0, r0), (z1, r1)) in enumerate(zip(knots, knots[1:])):
            if z0 >= z_soffit and tag == "shaft":
                continue
            r = max(r0, r1) * k * 0.94
            out.append((sbox(x - r, y - r, x + r, y + r), z0, z1, f"{lm['id']}_{tag}{i}"))
    for deck_id, z_ring in (("S3_collar", float(p["collar_z"])),
                            ("S4_roof_ring", float(p["roof_ring_z"]))):
        r = _hole_radius(layout, deck_id, x, y)
        out.append((sbox(x - r * 0.95, y - r * 0.95, x + r * 0.95, y + r * 0.95),
                    z_ring - 6.0, z_ring + 6.0, f"{lm['id']}_drum_{deck_id}"))
    for j in range(RIB_N):
        ang = j * math.tau / RIB_N + math.pi / RIB_N
        c, s = math.cos(ang), math.sin(ang)
        for i in range(8):
            t0, t1 = i / 8, (i + 1) / 8
            z0 = CROWN_RIB_BASE + (z_soffit - CROWN_RIB_BASE) * t0
            z1 = CROWN_RIB_BASE + (z_soffit - CROWN_RIB_BASE) * t1
            r1 = 34.0 * k + (152.0 - 34.0 * k) * t1 ** 0.62
            hw = 12.0 - 5.0 * t0
            out.append((_wedge(x, y, c, s, 34.0 * k, r1, hw), z0, z1, f"{lm['id']}_rib{j}"))
    return out


def _hole_radius(layout: dict, deck_id: str, x: float, y: float) -> float:
    for deck in layout.get("decks", []):
        if deck["id"] == deck_id and deck.get("holes"):
            return max(math.hypot(p[0] - x, p[1] - y) for p in deck["holes"][0])
    return 40.0


def _wedge(x: float, y: float, c: float, s: float, r0: float, r1: float,
           hw: float) -> Polygon:
    pts = [(x + c * r0 - s * hw, y + s * r0 + c * hw), (x + c * r1 - s * hw, y + s * r1 + c * hw),
           (x + c * r1 + s * hw, y + s * r1 - c * hw), (x + c * r0 + s * hw, y + s * r0 - c * hw)]
    return Polygon(pts)


def _offset(points: list[list[float]], offset: float) -> LineString:
    """A polyline `offset` metres to the right of travel (kit/corridors.py::_offset_path)."""
    out: list[tuple[float, float]] = []
    for i, p in enumerate(points):
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, len(points) - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy) or 1.0
        out.append((p[0] + dy / length * offset, p[1] - dx / length * offset))
    return LineString(out)


def terrain_solids(layout: dict) -> list[Solid]:
    """The plateau block and the dock shelf: real mass a ramp can run into."""
    terr = layout.get("terrain")
    if not terr:
        return []
    out: list[Solid] = []
    plateau = geom.poly(terr["plateau"]["polygon"])
    out.append((plateau, -40.0, float(terr["plateau"]["z"]), "plateau"))
    if terr["docks"]["polygon"]:
        out.append((geom.poly(terr["docks"]["polygon"]), -40.0,
                    float(terr["docks"]["z"]), "docks"))
    return out


def building_solids(b: dict) -> list[Solid]:
    """A building is its box, minus every declared `holes` opening over that opening's own z band.

    A MAP §3 v2 hole is a 3D thing - polygon x [z, z + height] - so the mass is cut into the bands
    the holes do not reach and the band under each hole loses it. Modelling it any other way made
    Block 9 a solid 200 m box with a 130 m footprint and put the M5 lift shaft inside it.
    """
    box = geom.rect(tuple(b["center"]), tuple(b["size"]), b.get("rot", 0.0))
    z0, z1 = float(b["base_z"]), float(b["base_z"]) + float(b["height"])
    holes = [(geom.poly(h["polygon"] if isinstance(h, dict) else h), float(h.get("z", z0)),
              float(h.get("z", z0)) + float(h.get("height", z1 - z0)))
             for h in b.get("holes", [])]
    cuts = sorted({z0, z1} | {z for _, a, c in holes for z in (a, c) if z0 < z < z1})
    out: list[Solid] = []
    for lo, hi in zip(cuts, cuts[1:]):
        area = box
        for poly, a, c in holes:
            if a <= lo + 0.1 and c >= hi - 0.1:
                area = area.difference(poly)
        if not area.is_empty:
            out.append((area, lo, hi, b["id"]))
    return out


def solids(layout: dict) -> tuple[STRtree, list[Solid]]:
    """Every collider the build makes, as (polygon, z bottom, z top, id) + a query tree."""
    items: list[Solid] = []
    for b in layout.get("buildings", []):
        items += building_solids(b)
    for deck in layout.get("decks", []):
        items += deck_solids(deck)
    for via in layout.get("viaducts", []):
        items += corridor_solids(via, VIADUCT_T, 2.5)
    for rail in layout.get("rails", []):
        items += corridor_solids(rail, RAIL_T, 2.4)
    for tunnel in layout.get("tunnels", []):
        items += tunnel_solids(tunnel)
    for arena in layout.get("arenas", []):
        for i, piece in enumerate(arena["cover"]):
            c = piece["center"]
            items.append((geom.rect((c[0], c[1]), (piece["size"][0], piece["size"][1])),
                          float(c[2]), float(c[2]) + float(piece["size"][2]),
                          f"{arena['id']}#{i}"))
    items += landmark_solids(layout)
    items += terrain_solids(layout)
    return STRtree([i[0] for i in items]), items


def sample_path(path: list[list[float]], width: float,
                step: float = STEP) -> list[tuple[float, float, float]]:
    """Points every `step` metres along a route, and across it, clear of the capsule radius.

    The middle of a 32 m ramp may be clear while its edge is under a slab, so each station is
    sampled at the centre and at `width/2 - CAPSULE_R` either side (lead, r8 item 4b).
    """
    reach = max(width / 2 - C.CAPSULE_R, 0.0)
    out: list[tuple[float, float, float]] = []
    for a, b in zip(path, path[1:]):
        run = math.dist(a[:2], b[:2])
        rise = b[2] - a[2]
        n = max(1, int(math.ceil(max(run, abs(rise)) / step)))
        yaw = math.atan2(b[1] - a[1], b[0] - a[0]) if run else 0.0
        nx, ny = -math.sin(yaw), math.cos(yaw)
        for k in range(n + 1):
            f = k / n
            x, y, z = a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + rise * f
            for side in (0.0, reach, -reach) if reach else (0.0,):
                out.append((x + nx * side, y + ny * side, z))
    return out


def headroom(p: tuple[float, float, float], tree: STRtree, items: list[Solid],
             floor: float | None = None) -> tuple[float, str]:
    """Clear metres from `p`'s floor to the lowest solid above it, and that solid's id.

    The floor is the path's own z: a deck the route runs *on* is the floor, not an obstruction,
    so a solid only counts when its underside is above the walking surface.
    """
    z = p[2] if floor is None else floor
    here = Point(p[0], p[1])
    best, who = 1e9, ""
    for idx in tree.query(here):
        poly, z0, _z1, ident = items[idx]
        if z0 < z + 1.0 or not poly.contains(here):
            continue
        if z0 - z < best:
            best, who = z0 - z, ident
    return best, who


APEX_MIN = 8.0        # m: an edgejump clears the rim it lands on by at least this much
APEX_FRAC = 0.09      # m per m of plan distance, so a long jump arcs higher
APEX_MAX = 18.0       # m: the mech is not a ballistic missile


def jump_arc(con: dict) -> list[list[float]]:
    """The trajectory an `edgejump` flies: a boost up to an apex over the landing, then the drop.

    A straight `from` -> `to` segment is not the path a jumping mech takes - it enters the deck it
    lands on from below, which every edgejump in the city does - and a single parabola is no
    better: it is still under the landing's own floor for the last fifth of its run. So the arc
    climbs to `to.z + apex` directly over the landing and comes down onto it, which is what the
    acceptance pass flew and what makes "the take-off is in the open" a real statement.
    """
    a, b = ends(con)
    d = math.dist(a[:2], b[:2])
    apex = max(float(a[2]), float(b[2])) + min(max(APEX_MIN, APEX_FRAC * d), APEX_MAX)
    top = [float(b[0]), float(b[1]), apex]
    out: list[list[float]] = []
    climb = math.dist((a[0], a[1], a[2]), top)
    n = max(4, int(math.ceil(climb / STEP)))
    for i in range(n + 1):
        t = i / n
        out.append([a[0] + (top[0] - a[0]) * t, a[1] + (top[1] - a[1]) * t,
                    a[2] + (top[2] - a[2]) * t])
    drop = max(1, int(math.ceil((apex - float(b[2])) / STEP)))
    for i in range(1, drop + 1):
        out.append([top[0], top[1], apex + (float(b[2]) - apex) * i / drop])
    return out


def ends(con: dict) -> tuple[list[float], list[float]]:
    """Where an edgejump really starts and ends: `params.take_off` / `params.land_at` if the
    placement stage moved them, the two graph nodes otherwise."""
    a = con.get("params", {}).get("take_off") or con["from"]
    b = con.get("params", {}).get("land_at") or con["to"]
    return [float(v) for v in a], [float(v) for v in b]


def path_of(con: dict) -> list[list[float]]:
    """The route a connector really is: its declared path, or the arc an edgejump flies."""
    if con["kind"] == "edgejump":
        return jump_arc(con)
    return con.get("path") or [con["from"], con["to"]]


def shaft_xy(con: dict) -> tuple[float, float]:
    """Where a lift / vent / vcat column is really built (`kit/connectors.py::_shaft`)."""
    xy = con.get("params", {}).get("shaft")
    return (float(xy[0]), float(xy[1])) if xy else (float(con["from"][0]), float(con["from"][1]))


def pierces(p: tuple[float, float, float], poly: Polygon, z0: float, z1: float,
            height: float = C.H) -> bool:
    """Does a capsule standing at `p` pass through this solid?"""
    if not (z0 < p[2] + height and z1 > p[2]):
        return False
    return poly.intersects(Point(p[0], p[1]).buffer(C.CAPSULE_R, quad_segs=6))
