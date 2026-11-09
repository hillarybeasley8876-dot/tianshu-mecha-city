"""`open_up`: the last pass, where the finished city yields to the routes that cross it.

Runs after every deck exists (the canopies, the canyon skybridges, the Block 9 station deck), and
it only ever ADDS `holes` and `openings` to records that are already there, or reports the masses
a filter has to drop. It draws no random number, so nothing except the pierced geometry moves.

Policy (lead, r8 item 4; see `routes3d` for the whole rule):

* a deck, a tunnel roof or a span truss in the way becomes a `holes` entry - the light well the
  acceptance pass needed. The hole is the route's own plan corridor clipped to the deck, inset
  from the rim so the deck stays in one piece;
* a parapet or an edge barrier in the way becomes an `openings` entry - the additive MAP §3 field
  this round adds, one plan polygon per gap, naming the routes it serves;
* a viaduct slab, a rail beam, a landmark, a building or an arena crate is NOT pierced: the first
  three are reported for `routes3d.place` to route round (or for `overrides.json` to move), the
  last two for `cuts` to drop.

The sweep repeats until it is stable, because holing one deck can expose the next one above it.
"""
from __future__ import annotations

import math

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

import geom
import mapconst as C
import route3d

RIM_INSET = 2.0        # m: a hole stops this far short of the rim, so it stays a hole
WELL_MARGIN = 8.0      # m: a hole is cut wider than the route, so the capsule fits
MAX_PASSES = 6         # the sweep repeats until it is stable
NODE_PLATE = 20.0      # m: no route well is cut through a graph node's own plate
CLIMBING = ("ramp", "stairs")


def open_up(layout: dict) -> dict:
    """Pierce the city until every designed route has its 24 m. Returns what it did."""
    done = {"holes": 0, "openings": 0, "stubborn": []}
    keep = _node_plates(layout)
    for _ in range(MAX_PASSES):
        holes, gaps, stubborn = _sweep(layout)
        if not holes and not gaps:
            done["stubborn"] = stubborn
            return done
        done["holes"] += _apply_holes(layout, holes, keep)
        done["openings"] += _apply_openings(layout, gaps)
    done["stubborn"] = _sweep(layout)[2]
    return done


def _corridor(con: dict) -> Polygon:
    """The plan strip a route needs: its own width plus the well margin."""
    path = route3d.path_of(con)
    line = LineString([(p[0], p[1]) for p in path])
    if line.length < 1.0:
        return Point(path[0][0], path[0][1]).buffer(float(con["width"]) / 2 + WELL_MARGIN)
    return line.buffer(float(con["width"]) / 2 + WELL_MARGIN, cap_style=2, join_style=2)


def _column(con: dict) -> Polygon:
    x, y = route3d.shaft_xy(con)
    half = float(con["width"]) / 2 + WELL_MARGIN
    return Point(x, y).buffer(half, quad_segs=8)


def _routes(layout: dict) -> list[tuple[str, Polygon, list, list]]:
    """(id, plan strip, the samples to sweep, the two ends) for every route and every column."""
    out: list[tuple[str, Polygon, list, list]] = []
    for con in layout["connectors"]:
        if con.get("usable") is False:
            continue
        if con["kind"] in CLIMBING + ("edgejump",):
            path = route3d.path_of(con)
            a, b = route3d.ends(con) if con["kind"] == "edgejump" else (path[0], path[-1])
            out.append((con["id"], _corridor(con),
                        route3d.sample_path(path, float(con["width"])), [a, b]))
        elif con["kind"] in ("lift", "vent", "vcat"):
            x, y = route3d.shaft_xy(con)
            lo = min(float(con["from"][2]), float(con["to"][2]))
            hi = max(float(con["from"][2]), float(con["to"][2]))
            samples = [(x, y, lo + (hi - lo) * i / max(1, int((hi - lo) / route3d.STEP)))
                       for i in range(int((hi - lo) / route3d.STEP) + 1)]
            samples += [(x, y, hi + route3d.TOP_AIR * i / 4.0) for i in range(1, 5)]
            out.append((con["id"], _column(con), samples, [(x, y, lo), (x, y, hi)]))
    # The elevated corridors are routes too: two viaducts that meet cross each other's edge
    # barrier, and a rail leaving a skydeck crosses its parapet.
    for group in ("viaducts", "rails"):
        for item in layout[group]:
            path = [[p[0], p[1], item["z"]] for p in item["points"]]
            out.append((item["id"],
                        geom.line(item["points"]).buffer(
                            float(item["width"]) / 2 + WELL_MARGIN, cap_style=2),
                        route3d.sample_path(path, float(item["width"])),
                        [path[0], path[-1]]))
    return out


def _sweep(layout: dict):
    """One pass: what really blocks each route, sorted into what may be pierced and what may not.

    The test is the check's own - a capsule standing on the route's floor either passes through a
    solid or has less than 24 m of air over it - so `open_up` and `checks_routes` can never
    disagree. Anything else in the same z band (a reactor stack 100 m to the side) is not a
    blocker and is not reported.
    """
    tree, items = route3d.solids(layout)
    decks = {d["id"]: d for d in layout["decks"]}
    pierceable = set(decks) | {t["id"] for t in layout["tunnels"]} | \
        {v["id"] for v in layout["viaducts"] + layout["rails"]} | \
        {b["id"] for b in layout["buildings"]}
    holes: dict[str, list[tuple[str, Polygon]]] = {}
    gaps: dict[str, list[tuple[str, Polygon]]] = {}
    stubborn: set[str] = set()
    for ident, strip, samples, ends in _routes(layout):
        for p in samples:
            for sid in _blockers(p, tree, items, ends):
                base = sid.rsplit("_", 1)[0] \
                    if sid.endswith(("_parapet", "_truss", "_barrier", "_roof", "_wall")) else sid
                if base in pierceable:
                    target = gaps if sid.endswith(("_parapet", "_barrier", "_wall")) else holes
                    target.setdefault(base, []).append((ident, strip))
                elif not route3d.exempt_blocker(ident, sid):
                    stubborn.add(f"{ident} is blocked by {sid}")
    return holes, gaps, sorted(stubborn)


def _blockers(p: tuple[float, float, float], tree, items, ends) -> list[str]:
    """The solids a route sample is inside, or has less than 24 m of air under."""
    near = any(math.dist(p, e) < 6.0 for e in ends)
    here = Point(p[0], p[1]).buffer(C.CAPSULE_R, quad_segs=6)
    out: list[str] = []
    for idx in tree.query(here):
        poly, z0, z1, sid = items[idx]
        if sid in ("plateau", "docks") or not poly.intersects(here):
            continue
        if near and any(abs(z1 - e[2]) < 2.5 for e in ends):
            continue                      # the floor the route starts or ends on
        if route3d.pierces(p, poly, z0, z1):
            out.append(sid)
        elif z0 > p[2] + 1.0 and z0 - p[2] < route3d.CLEAR:
            out.append(sid)
    return out


def _node_plates(layout: dict) -> Polygon:
    """A 20 m plate round every graph node: L1 needs a node to stand on a surface, so no route
    well may be cut through one."""
    spots = [Point(float(c[0]), float(c[1])).buffer(NODE_PLATE, quad_segs=8)
             for c in layout["connectors"] for c in (c["from"], c["to"])]
    spots += [Point(float(item["points"][0][0]), float(item["points"][0][1]))
              .buffer(NODE_PLATE, quad_segs=8)
              for group in ("streets", "viaducts", "rails", "tunnels")
              for item in layout.get(group, []) for item in (item,)]
    return unary_union(spots) if spots else Polygon()


def _apply_holes(layout: dict, holes: dict, keep: Polygon | None = None) -> int:
    """Cut each route's strip out of whatever it crosses, inset from the rim."""
    made = 0
    records = {d["id"]: d for d in layout["decks"]}
    records.update({t["id"]: t for t in layout["tunnels"]})
    records.update({v["id"]: v for v in layout["viaducts"] + layout["rails"]})
    records.update({b["id"]: b for b in layout["buildings"]})
    for did, rows in holes.items():
        deck = records[did]
        area = _extent(deck)
        cut = unary_union([strip for _, strip in rows]).intersection(area)
        if cut.is_empty:
            continue
        # A notch that reaches the rim is what a ramp arriving at a deck looks like, so the cut
        # is taken to the rim; only when it would split the deck in two does it stop short.
        if "polygon" in deck:      # only a deck's hole has to stay clear of its own rim
            minx, miny, maxx, maxy = area.bounds
            inset = min(RIM_INSET, 0.2 * min(maxx - minx, maxy - miny))
            cut = cut.intersection(area.buffer(-inset))
        if keep is not None and not keep.is_empty:
            cut = cut.difference(keep)
        if cut.is_empty:
            continue
        parts = list(getattr(cut, "geoms", [cut]))
        have = [geom.poly(_ring(h)) for h in deck.get("holes", [])]
        fresh = [p for p in parts if p.area > 80.0
                 and not any(p.difference(h).area < 0.2 * p.area for h in have)]
        if not fresh:
            continue
        deck.setdefault("holes", []).extend(
            [_hole(deck, p, rows) for p in fresh])
        deck.setdefault("open_for", [])
        for ident, _ in rows:
            if ident not in deck["open_for"]:
                deck["open_for"].append(ident)
        made += len(fresh)
    return made


def _apply_openings(layout: dict, gaps: dict) -> int:
    """Declare a parapet / barrier gap wherever a route crosses one."""
    made = 0
    by_id = {d["id"]: d for d in layout["decks"]}
    by_id.update({c["id"]: c for c in layout["viaducts"] + layout["rails"]})
    by_id.update({t["id"]: t for t in layout["tunnels"]})
    for did, rows in gaps.items():
        item = by_id[did]
        band = _band(item)
        have = unary_union([geom.poly(o["poly"]) for o in item.get("openings", [])]) \
            if item.get("openings") else Polygon()
        cut = unary_union([strip for _, strip in rows]).intersection(band).difference(have)
        for part in getattr(cut, "geoms", [cut]):
            if part.is_empty or part.area < 4.0:
                continue
            # The gap is buffered before it is stored: a rotated bounding rectangle leaves slivers
            # of wall at the ends of a curved rim, and the next pass would find them again.
            gap = part.buffer(route3d.PARAPET_T).simplify(1.0)
            item.setdefault("openings", []).append({
                "poly": [[round(x, 1), round(y, 1)] for x, y in gap.exterior.coords[:-1]],
                "for": sorted({ident for ident, _ in rows}),
                "clear_m": route3d.CLEAR})
            made += 1
    return made


def _ring(hole) -> list:
    """A `holes` entry is a bare ring on a deck or a corridor and a MAP §3 v2 record on a building."""
    return hole["polygon"] if isinstance(hole, dict) else hole


def _hole(record: dict, part: Polygon, rows: list) -> object:
    """The `holes` entry for one cut, in the shape the record's own schema uses."""
    ring = [[round(x, 1), round(y, 1)] for x, y in part.simplify(1.0).exterior.coords[:-1]]
    if "base_z" not in record:                      # a deck, a tunnel or a corridor: a bare ring
        return ring
    return {"polygon": ring, "z": float(record["base_z"]),
            "height": float(record["height"]), "clear": route3d.CLEAR,
            "for": sorted({ident for ident, _ in rows})}


def _extent(item: dict) -> Polygon:
    """The plan extent a record's `holes` are cut out of: its polygon, or its own footprint."""
    if "polygon" in item:
        return geom.poly(item["polygon"])
    if "points" in item:
        half = float(item["width"]) / 2 + (6.0 if "clear" in item else 0.0)
        return geom.line(item["points"]).buffer(half, cap_style=2)
    return geom.rect(tuple(item["center"]), tuple(item["size"]), item.get("rot", 0.0))


def _band(item: dict) -> Polygon:
    """The wall band of a deck's parapet, a corridor's edge barriers or a tunnel's lining."""
    if "polygon" in item:
        area = geom.poly(item["polygon"])
        for hole in item.get("holes", []):
            area = area.difference(geom.poly(hole))
        return area.boundary.buffer(route3d.PARAPET_T, cap_style=2)
    if "clear" in item:
        half = float(item["width"]) / 2 + 6.0
        return geom.line(item["points"]).buffer(half, cap_style=2).boundary.buffer(3.0)
    return route3d.barrier_band(item, 2.5 if item["id"].startswith("via") else 2.4)[0]
