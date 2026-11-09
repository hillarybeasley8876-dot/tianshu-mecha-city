"""The 3D sub-checks of L1/L3 (lead, r8 item 4): does a route exist in space, not only in plan.

Four sub-checks, all reading the written layout the way `checks_sockets` and `hive_rule` do and
never the generator's geometry:

a. **run vs rise** - every ramp and stairs segment climbs on a plan run of at least
   `rise / tan 20 deg`, and no stairs flight rises more than 32 m (dossier C8).
b. **headroom** - every ramp and stairs path, and every edgejump from its take-off to the upper
   rim, sampled at 4 m along and across the width minus the capsule radius, has 24 m from its
   floor to the lowest solid above it (`mapconst.UNDER_DECK_CLEAR`).
c. **columns** - a lift, vent or vcat column runs from its pad to its top stop with no slab
   crossing it that has no declared hole, and its top lands on a floor with 16 m of air over it.
d. **rim crossings** - where a route or a corridor enters a deck, the crossing has 24 m of clear
   air and a declared parapet `openings` segment.

`route_ok` is the single verdict the hive rule and L1 use, so "3 approach routes" means three
routes that pass a-d rather than three records that exist.
"""
from __future__ import annotations

import math

from shapely.geometry import Point

import geom
import mapconst as C
import route3d

FAIL: list[str] = []
NOTE: list[str] = []

# Lead, r16: fixes owned by other units this round. Each entry names the unit and its item, so
# the exemption is a pointer and not a silence.
EXEMPT: dict[str, str] = {
    "con_A1_H3_stairs": "city-build r11 lowers the H3 crane cab under the deck (z 40-48)",
    "con_S3n_S4_lift": "city-build r11 notches Crown rib j=2 over the S3n shaft",
    "con_S4_B1_vcat": "city-build r11 notches Crown rib j=2 over the S4 pad",
}
CLIMBING = ("ramp", "stairs")


def _con_path(con: dict) -> list[list[float]]:
    return con.get("path") or [con["from"], con["to"]]


def check_run_rise(layout: dict) -> int:
    """(a) A climbing segment needs a plan run; a stairs flight needs <= 32 m of rise."""
    bad = 0
    for con in layout["connectors"]:
        if con["kind"] not in CLIMBING:
            continue
        path = _con_path(con)
        for i, (a, b) in enumerate(zip(path, path[1:])):
            rise = abs(b[2] - a[2])
            run = math.dist(a[:2], b[:2])
            if rise < 0.5:
                continue
            need = rise / math.tan(math.radians(route3d.MAX_DEG))
            if run < need - 0.5:
                bad += 1
                FAIL.append(f"L3a {con['id']} segment {i} climbs {rise:.0f} m on a "
                            f"{run:.0f} m plan run (need {need:.0f} m for "
                            f"{route3d.MAX_DEG:.0f} deg) at {a[:2]}->{b[:2]}")
        if con["kind"] == "stairs":
            flights = int(con.get("params", {}).get("flights", 1))
            rise = abs(path[-1][2] - path[0][2]) / max(flights, 1)
            if rise > route3d.MAX_FLIGHT_RISE + 0.5:
                bad += 1
                FAIL.append(f"L3a {con['id']} flight rises {rise:.0f} m over {flights} "
                            f"flights (> {route3d.MAX_FLIGHT_RISE:.0f} m, C8)")
            for i, (a, b) in enumerate(zip(path, path[1:])):
                if math.dist(a[:2], b[:2]) < route3d.MIN_LANDING and abs(b[2] - a[2]) > 0.5:
                    bad += 1
                    FAIL.append(f"L3a {con['id']} landing {i} is {math.dist(a[:2], b[:2]):.0f} m "
                                f"deep (< {route3d.MIN_LANDING:.0f} m) at {a[:2]}")
    return bad


def check_headroom(layout: dict) -> dict[str, float]:
    """(b) 24 m from the floor to the lowest solid over every ramp and stairs path.

    An edgejump is a flight, not a walk: it is measured as "the arc passes through no solid and
    the landing has 24 m of air over it". Asking a descending arc for 24 m of air *above* itself
    would forbid every jump that lands under a deck, which is the normal case.
    """
    tree, items = route3d.solids(layout)
    worst: dict[str, float] = {}
    for con in layout["connectors"]:
        if con["kind"] not in CLIMBING + ("edgejump",) or con.get("usable") is False:
            continue
        path = route3d.path_of(con)
        a, b = route3d.ends(con)
        clear, who, where = 1e9, "", (0.0, 0.0, 0.0)
        hit = ""
        for p in route3d.sample_path(path, float(con["width"])):
            if con["kind"] == "edgejump":
                # the take-off and the landing stand ON their own floors: a solid within 6 m of
                # either is the deck the mech is standing on, not something over its head
                if math.dist(p, a) < 6.0 or math.dist(p, b) < 6.0:
                    continue
                if not hit:
                    hit = _pierced_by(p, tree, items, con)
            gap, ident = route3d.headroom(p, tree, items)
            if gap < clear and not _skip(con, ident):
                clear, who, where = gap, ident, p
        worst[con["id"]] = round(clear, 1)
        if con["id"] in EXEMPT:
            if clear < route3d.CLEAR or hit:
                NOTE.append(f"L3b {con['id']} exempt: {EXEMPT[con['id']]} "
                            f"(measures {clear:.1f} m under {who})")
            continue
        if hit:
            FAIL.append(f"L3b {con['id']} arc passes through {hit} - the take-off at "
                        f"({a[0]:.0f},{a[1]:.0f},{a[2]:.0f}) is not in the open")
        elif clear < route3d.CLEAR:
            FAIL.append(f"L3b {con['id']} has {clear:.1f} m of headroom at "
                        f"({where[0]:.0f},{where[1]:.0f},{where[2]:.0f}) under {who} "
                        f"(need {route3d.CLEAR:.0f} m)")
    return worst


def _skip(con: dict, sid: str) -> bool:
    """Is this blocker set aside for this connector (a partial exemption with a named fix)?"""
    return bool(route3d.exempt_blocker(con["id"], sid))


def _pierced_by(p: tuple[float, float, float], tree, items, con: dict) -> str:
    """The first solid a jumping mech's capsule passes through, "" when the arc is clear.

    The two endpoints stand ON their own floors, so a solid within 6 m of the take-off or the
    landing is the ground, not an obstruction. The plateau and the dock shelf are never counted:
    `terrain.build` puts a climb lip exactly where a free-climb connector crosses the escarpment.
    """
    a, b = route3d.ends(con)
    near = math.dist(p, a) < 6.0 or math.dist(p, b) < 6.0
    here = Point(p[0], p[1]).buffer(C.CAPSULE_R, quad_segs=6)
    for idx in tree.query(here):
        poly, z0, z1, ident = items[idx]
        if ident == con["id"] or ident in ("plateau", "docks"):
            continue
        if near and (abs(z1 - a[2]) < 2.5 or abs(z1 - b[2]) < 2.5):
            continue
        if _skip(con, ident):
            continue
        if route3d.pierces(p, poly, z0, z1) and poly.intersects(here):
            return ident
    return ""


def floors(layout: dict) -> list[tuple[object, float, str]]:
    """Every walkable surface in plan with its z and id: corridors, decks, ground, cover tops."""
    out: list[tuple[object, float, str]] = []
    for group in ("streets", "viaducts", "rails", "tunnels"):
        for item in layout.get(group, []):
            out.append((geom.line(item["points"]).buffer(item["width"] / 2),
                        float(item["z"]), item["id"]))
    for deck in layout.get("decks", []):
        area = geom.poly(deck["polygon"])
        for hole in deck.get("holes", []):
            area = area.difference(geom.poly(hole))
        out.append((area, float(deck["z"]), deck["id"]))
    terr = layout.get("terrain")
    half = float(layout.get("bounds", {}).get("half", C.HALF))
    ground = geom.poly([[-half, -half], [half, -half], [half, half], [-half, half]])
    if terr:
        out.append((ground.difference(geom.poly(terr["plateau"]["polygon"])), 0.0, "ground"))
        out.append((geom.poly(terr["plateau"]["polygon"]), float(terr["plateau"]["z"]),
                    "plateau"))
    for arena in layout.get("arenas", []):
        for i, piece in enumerate(arena["cover"]):
            c = piece["center"]
            out.append((Point(c[0], c[1]).buffer(max(piece["size"][:2]) / 2),
                        float(c[2]) + float(piece["size"][2]), f"{arena['id']}#{i}"))
    return out


def check_columns(layout: dict) -> dict[str, list[str]]:
    """(c) A lift / vent / vcat column: open from the pad to the top stop, landing on a floor.

    The column is the shaft the builder raises at `params.shaft` (default: the `from` node), and
    it runs from the pad to `to.z + TOP_AIR`: the car stops level with the floor it serves and the
    shaft carries on past it, so that floor is holed like every other slab the column crosses and
    the landing is the ring of floor around the hole.
    """
    tree, items = route3d.solids(layout)
    surfs = floors(layout)
    out: dict[str, list[str]] = {}
    for con in layout["connectors"]:
        if con["kind"] not in ("lift", "vent", "vcat"):
            continue
        if con.get("usable") is False:
            NOTE.append(f"L3c {con['id']} is marked usable:false - not swept")
            continue
        x, y = route3d.shaft_xy(con)
        z0, z1 = float(con["from"][2]), float(con["to"][2])
        pad = float(con["width"]) * 0.5
        lo, hi = min(z0, z1), max(z0, z1) + route3d.TOP_AIR
        here = Point(x, y).buffer(pad, quad_segs=8)
        blocked: list[str] = []
        for idx in tree.query(here):
            poly, sz0, sz1, ident = items[idx]
            if ident in ("plateau", "docks") or ident == con["id"]:
                continue       # kit/terrain.py::ground_cuts already cuts the crust for a pad
            if sz1 <= lo + 0.5 or sz0 >= hi - 0.5 or not poly.intersects(here):
                continue
            if poly.intersection(here).area > 0.25 * here.area:
                blocked.append(f"{ident}@{sz0:.0f}")
        ring = Point(x, y).buffer(pad + 12.0, quad_segs=8).difference(
            Point(x, y).buffer(pad * 0.9, quad_segs=8))
        landed = [sid for poly, sz, sid in surfs
                  if abs(sz - z1) <= C.ON_DATUM_TOL and poly.intersects(ring)
                  and poly.intersection(ring).area > 60.0]
        air, over = route3d.headroom((x, y, z1), tree, items, floor=z1)
        out[con["id"]] = blocked
        if con["id"] in EXEMPT:
            NOTE.append(f"L3c {con['id']} exempt: {EXEMPT[con['id']]}")
            continue
        if blocked:
            FAIL.append(f"L3c {con['id']} column at ({x:.0f},{y:.0f}) from {lo:.0f} to "
                        f"{hi:.0f} is capped by {blocked[:4]} with no declared hole")
        if not landed:
            FAIL.append(f"L3c {con['id']} top stop at ({x:.0f},{y:.0f},{z1:.0f}) lands on no "
                        f"floor (its shaft is {math.dist((x, y), con['to'][:2]):.0f} m from "
                        f"the node in plan)")
        elif air < route3d.TOP_AIR:
            FAIL.append(f"L3c {con['id']} top stop at ({x:.0f},{y:.0f},{z1:.0f}) has "
                        f"{air:.1f} m of air over {landed[0]} under {over} "
                        f"(need {route3d.TOP_AIR:.0f} m)")
    return out


def check_rims(layout: dict) -> int:
    """(d) Where a route or a corridor crosses a wall: 24 m clear and a declared opening.

    The walls are a deck's parapet (`kit/decks.py::_parapet`, which walls EVERY rim) and a
    viaduct's or a rail's edge barrier (`kit/corridors.py`). A route that runs along a rim
    crosses it many times over, so the report is one line per (route, wall) pair, carrying the
    worst air and the first sample that had no opening.
    """
    tree, items = route3d.solids(layout)
    walls = [(f"{d['id']}_parapet", route3d._ring(_area(d), route3d.PARAPET_T),
              route3d._openings(d), float(d["z"]))
             for d in layout.get("decks", []) if float(d.get("parapet", 0.0)) > 0.1]
    for group, thick in (("viaducts", 2.5), ("rails", 2.4)):
        for item in layout[group]:
            band, gaps = route3d.barrier_band(item, thick)
            walls.append((f"{item['id']}_barrier", band, gaps, float(item["z"])))
    bad = 0
    for ident, path, width in _routes(layout):
        seen: dict[str, tuple[float, str, tuple[float, float]]] = {}
        for p in route3d.sample_path(path, width):
            here = Point(p[0], p[1])
            for wid, band, gaps, wz in walls:
                if abs(wz - p[2]) > 2.5 or wid in seen or not band.intersects(here):
                    continue
                if not gaps.is_empty and gaps.contains(here):
                    continue
                gap, over = route3d.headroom(p, tree, items, floor=wz)
                seen[wid] = (gap, over, (p[0], p[1]))
        for wid, (gap, over, at) in sorted(seen.items()):
            bad += 1
            if gap < route3d.CLEAR:
                FAIL.append(f"L3d {ident} crosses {wid} at ({at[0]:.0f},{at[1]:.0f}) with no "
                            f"declared opening and only {gap:.1f} m of air under {over}")
            else:
                FAIL.append(f"L3d {ident} crosses {wid} at ({at[0]:.0f},{at[1]:.0f}) with no "
                            f"declared opening")
    return bad


def _routes(layout: dict) -> list[tuple[str, list[list[float]], float]]:
    """Every route that walks or flies onto a deck: the climbing kinds and the edgejumps."""
    out = [(con["id"], route3d.path_of(con), float(con["width"]))
           for con in layout["connectors"]
           if con["kind"] in CLIMBING + ("edgejump",) and con.get("usable") is not False]
    for group in ("viaducts", "rails"):
        for item in layout[group]:
            out.append((item["id"], [[p[0], p[1], item["z"]] for p in item["points"]],
                        float(item["width"])))
    return out


def _area(deck: dict):
    area = geom.poly(deck["polygon"])
    for hole in deck.get("holes", []):
        area = area.difference(geom.poly(hole))
    return area


def summary(layout: dict) -> dict:
    """Run a-d and return the one line `validate_layout` prints, plus the failing ids.

    `failing()` is what L1 uses: an edge is only "realised" when the connector that carries it
    is a route a mech can actually take, not merely a record that exists (lead, r8 item 4).
    """
    check_run_rise(layout)
    head = check_headroom(layout)
    columns = check_columns(layout)
    rims = check_rims(layout)
    exempt = set(EXEMPT) | {c["id"] for c in layout["connectors"]
                            if c.get("usable") is False}
    swept = [c for c in layout["connectors"]
             if c["kind"] in ("ramp", "stairs", "edgejump", "lift", "vent", "vcat")
             and c["id"] not in exempt]
    named = failing()
    worst = min(((v, k) for k, v in head.items() if k not in exempt), default=(0.0, ""))
    return {"total": len(swept), "ok": len(swept) - len(named & {c["id"] for c in swept}),
            "columns": len(columns), "rims": rims, "worst": worst,
            "holes": sum(len(d.get("holes", [])) for d in layout["decks"]),
            "openings": sum(len(d.get("openings", [])) for d in layout["decks"]),
            "shafts": sum(1 for c in layout["connectors"] if c.get("params", {}).get("shaft")),
            "moved": sum(1 for c in layout["connectors"]
                         if c.get("params", {}).get("take_off"))}


_CACHE: dict[int, set[str]] = {}


def failing(layout: dict | None = None) -> set[str]:
    """The connector ids a-d rejects.

    With a layout it runs the four sub-checks on it (cached per layout object, because
    `hive_rule.approaches` asks once per candidate spire site); without one it reads back the
    ids out of the FAIL lines `summary` just wrote.
    """
    if layout is None:
        out: set[str] = set()
        for line in FAIL:
            parts = line.split()
            if len(parts) > 1 and parts[0] in ("L3a", "L3b", "L3c", "L3d"):
                out.add(parts[1])
        return out
    key = id(layout)
    if key not in _CACHE:
        FAIL.clear()
        check_run_rise(layout)
        check_headroom(layout)
        check_columns(layout)
        check_rims(layout)
        _CACHE[key] = failing()
        FAIL.clear()
    return _CACHE[key]
