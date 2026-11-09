#!/usr/bin/env python3
"""validate_layout.py - checks L1-L7 on data/map/city_layout.json (docs/MAP.md §5).

L1 every graph edge realised, every node on a surface of its layer
L2 nothing intersects a corridor volume except a declared `through` / breach, and every
   connector endpoint keeps a 12 m sphere clear of buildings, cover and piers
L3 widths, ramp grades and clearances, and - from r8 - the four 3D route sub-checks
   (a run vs rise, b headroom, c lift/vent/vcat columns, d rim crossings)
L4 arenas: entries on >= 2 layers, cover within 60 m, <= 5 % of sightlines over 350 m
L5 the Spire crown visible from >= 80 % of navigable samples
L6 >= 8 skyhook anchors per arena, all inside the 120 m anchor range
L7 everything inside +/-700 m except the skyline ring
L8 each lead vista (data/vistas.json) hits its subject first, or frames through a canyon
L9 every deck declares what carries it (towers, columns, ground or a named span)
L10 the sky graph is connected and clear: nodes >= 12 m and edges >= 8 m off every
    building/deck/rail box, +60..+250 m, >= 24 per district, >= 6 per arena,
    >= 8 ringing the Crown
L11 arena spawn sockets: on the arena's own top walkable surface, >= 16 m off a wall,
    16 m of clear air above, >= 12 m of free floor (no solid within 8 m), on an island
    that reaches the arena centre

Usage: uv run --with numpy --with shapely --with networkx python3 tools/map/validate_layout.py
"""
from __future__ import annotations

import json
import math
import os
import random
import sys

from shapely.geometry import Point, Polygon
from shapely.strtree import STRtree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geom  # noqa: E402
import keepclear  # noqa: E402
import mapconst as C  # noqa: E402
from sight import box_of  # noqa: E402
import checks_arena  # noqa: E402
import checks_hives  # noqa: E402
import skygraph  # noqa: E402
import checks_routes  # noqa: E402
import checks_sockets  # noqa: E402
import coverfield  # noqa: E402
import vistas as vista_check  # noqa: E402
import layout_report as cover_report  # noqa: E402
from layout_report import overhead_cover, summarise  # noqa: E402

FAIL: list[str] = []
NOTE: list[str] = []


def load(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def corridor_volume(item: dict) -> tuple[Polygon, float, float]:
    """(plan footprint, z bottom, z top) of a corridor's navigable volume."""
    height = item.get("clear", C.UNDER_DECK_CLEAR)
    return (geom.line(item["points"]).buffer(item["width"] / 2),
            item["z"], item["z"] + height)


def _disc(centre, radius: float) -> Polygon:
    return Point(centre.x, centre.y).buffer(radius, quad_segs=24)


def overlaps(a: tuple[float, float], b: tuple[float, float]) -> bool:
    return a[0] < b[1] - 0.5 and b[0] < a[1] - 0.5


def check_l1(graph: dict, layout: dict) -> dict:
    """Every edge realised exactly once; every node standing on a surface of its layer."""
    nodes = {n["id"]: n for n in graph["nodes"]}
    realised: dict[tuple[str, str], list[str]] = {}
    for con in layout["connectors"]:
        key = (con["edge"][0], con["edge"][1])
        realised.setdefault(key, []).append(con["id"])
    for group in ("streets", "viaducts", "rails", "tunnels"):
        for item in layout[group]:
            ends = item.get("nodes")
            if not ends:
                continue
            realised.setdefault((ends[0], ends[1]), []).append(item["id"])
    # From r8 an edge counts as realised only when the connector that carries it is a route a
    # mech can take: `checks_routes` a-d must already have run (validate_layout calls it first).
    dead = checks_routes.failing()
    for edge in graph["edges"]:
        key = (edge["from"], edge["to"])
        found = realised.get(key, [])
        if not found:
            FAIL.append(f"L1 edge {key[0]}->{key[1]} ({edge['kind']}) is not realised")
        elif len(found) > 1:
            FAIL.append(f"L1 edge {key[0]}->{key[1]} realised {len(found)}x: {found}")
        elif found[0] in dead:
            FAIL.append(f"L1 edge {key[0]}->{key[1]} ({edge['kind']}) is carried by {found[0]}, "
                        f"which is not a walkable route (see L3a-d)")
    surfaces = _surfaces(layout)
    for nid, node in nodes.items():
        x, y, z = node["pos"]
        if not any(abs(sz - z) <= C.ON_DATUM_TOL and poly.contains(Point(x, y))
                   for poly, sz in surfaces):
            FAIL.append(f"L1 node {nid} at ({x:.0f},{y:.0f},{z:.0f}) is not on a surface")
    return {"edges": len(graph["edges"]), "connectors": len(layout["connectors"])}


def _surfaces(layout: dict) -> list[tuple[Polygon, float]]:
    """Every walkable surface in plan: corridors, decks, ground, plateau, docks, water."""
    out: list[tuple[Polygon, float]] = []
    for group in ("streets", "viaducts", "rails", "tunnels"):
        for item in layout[group]:
            out.append((geom.line(item["points"]).buffer(item["width"] / 2), item["z"]))
    for deck in layout["decks"]:
        area = geom.poly(deck["polygon"])
        for hole in deck.get("holes", []):
            area = area.difference(geom.poly(hole))
        out.append((area, deck["z"]))
        core = deck.get("core")
        if core:
            # the Crown's central drum: the shaft passes through it and node B1 stands on it
            out.append((_disc(geom.poly(deck["polygon"]).centroid, core["r"]), core["z"]))
    terr = layout["terrain"]
    square = geom.poly([[-C.HALF, -C.HALF], [C.HALF, -C.HALF], [C.HALF, C.HALF],
                        [-C.HALF, C.HALF]])
    out.append((square.difference(geom.poly(terr["plateau"]["polygon"])), 0.0))
    out.append((geom.poly(terr["plateau"]["polygon"]), terr["plateau"]["z"]))
    if terr["docks"]["polygon"]:
        out.append((geom.poly(terr["docks"]["polygon"]), terr["docks"]["z"]))
    for cover_owner in layout["arenas"]:
        for piece in cover_owner["cover"]:
            out.append((Point(piece["center"][0], piece["center"][1]).buffer(
                max(piece["size"][0], piece["size"][1]) / 2), piece["center"][2]))
    return out


def check_l2(layout: dict) -> None:
    """No solid intersects a corridor's navigable volume (declared `through` excepted).

    A podium-through block is two solids: the podium below `podium_z`, with its arcade
    `holes` cut out, and the tower above it. The arcade is what the street runs through,
    so the podium is tested as the ring around the hole and the tower as the whole slab.
    """
    corridors = []
    for group in ("streets", "viaducts", "rails", "tunnels"):
        for item in layout[group]:
            poly, z0, z1 = corridor_volume(item)
            corridors.append((item, poly, (z0, z1)))
    tree = STRtree([c[1] for c in corridors])
    solids: list[tuple[str, Polygon, tuple[float, float], set[str]]] = []
    for b in layout["buildings"]:
        box = box_of(b)
        through = set(b.get("through", []))
        podium = b.get("podium_z")
        if podium is None:
            solids.append((b["id"], box, (b["base_z"], b["base_z"] + b["height"]), through))
            continue
        for hole in b.get("holes", []):
            box = box.difference(geom.poly(hole["polygon"]))
        solids.append((b["id"], box, (b["base_z"], podium), through))
        solids.append((f"{b['id']}_tower", box_of(b), (podium, b["base_z"] + b["height"]),
                       through))
    for deck in layout["decks"]:
        if deck.get("canopy"):
            continue
        area = geom.poly(deck["polygon"])
        for hole in deck.get("holes", []):
            area = area.difference(geom.poly(hole))
        solids.append((deck["id"], area, (deck["z"] - deck["thickness"], deck["z"]), set()))
    for ident, poly, span, through in solids:
        for idx in tree.query(poly):
            item, corridor, cspan = corridors[idx]
            if item["id"] in through or ident in item.get("through", []) \
                    or not overlaps(span, cspan):
                continue
            hit = poly.intersection(corridor)
            if hit.is_empty or hit.area < 1.0:
                continue
            FAIL.append(f"L2 {ident} (z {span[0]:.0f}..{span[1]:.0f}) blocks "
                        f"{item['id']} (z {cspan[0]:.0f}..{cspan[1]:.0f}) over "
                        f"{hit.area:.0f} m2 near {list(hit.centroid.coords)[0]}")


def check_l2_keepclear(layout: dict) -> dict:
    """Every connector endpoint stands in a 12 m sphere kept clear of solid (lead, r4 pt 1).

    C12 sweeps its capsule from 1 m over the take-off surface, so a building, a cover piece
    or a viaduct pier inside that sphere reads in the built city as "the endpoint is inside
    geometry". The surface an endpoint stands *on* is its floor and does not count; a
    connector that shares the node does not count either - a node is a junction.
    """
    tree, rows = keepclear.index(layout["connectors"])
    solids: list[tuple[str, Polygon, tuple[float, float]]] = []
    for b in layout["buildings"]:
        box = box_of(b)
        holes = [geom.poly(h["polygon"]) for h in b.get("holes", [])]
        for hole in holes:
            box = box.difference(hole)
        solids.append((b["id"], box, (b["base_z"], b["base_z"] + b["height"])))
    for arena in layout["arenas"]:
        for i, piece in enumerate(arena["cover"]):
            solids.append((f"{arena['id']}_cover{i}",
                           geom.rect(tuple(piece["center"][:2]), tuple(piece["size"][:2]),
                                     piece.get("rot", 0.0)),
                           (piece["center"][2], piece["center"][2] + piece["size"][2])))
    for group in ("viaducts", "rails"):
        for item in layout[group]:
            for i, pier in enumerate(item.get("piers", [])):
                solids.append((f"{item['id']}_pier{i}",
                               Point(pier[0], pier[1]).buffer(keepclear.PIER_R),
                               (0.0, pier[2])))
    for deck in layout["decks"]:
        if deck.get("arena") or deck.get("over_water"):
            # an arena's own tier stack is the dossier's datum, not this check's (the Knot's
            # 16 m tiers are reported by `arena_headroom`), and nothing walks under a pier
            continue
        solids.append((deck["id"], geom.poly(deck["polygon"]),
                       (deck["z"] - deck["thickness"], deck["z"])))
    hits: dict[str, list[str]] = {}
    for ident, poly, span in solids:
        for name in keepclear.blocked(tree, rows, poly, span[0], span[1]):
            hits.setdefault(name, []).append(ident)
    for name, blockers in sorted(hits.items()):
        FAIL.append(f"L2 {name} keep-clear {C.KEEP_CLEAR:.0f} m is blocked by "
                    f"{sorted(set(blockers))[:4]}")
    ends = len(layout["connectors"]) * 2
    return {"endpoints": ends, "clear": ends - len(hits)}


def arena_headroom(layout: dict) -> list[dict]:
    """The headroom over every walkable surface inside an arena, worst first (C13).

    C13 asks for 32 m under anything inside an arena polygon, and it samples in 2D: a deck
    that IS one of the arena's own tiers leaves a tier below it whose headroom is the gap
    between two dossier datums. Where that gap is under 32 m the datum is the dossier's to
    change, so it is measured and reported rather than failed (lead, r4 point 2).
    """
    decks = [(geom.poly(d["polygon"]), d["z"] - d["thickness"], d["id"])
             for d in layout["decks"]]
    rows = []
    for arena in layout["arenas"]:
        area = geom.poly(arena["polygon"])
        tiers = sorted({float(c["center"][2]) for c in arena["cover"]} | set(arena["tiers"]))
        for z in tiers:
            worst, who = 1e9, ""
            for poly, under, ident in decks:
                if under <= z + 1.0 or poly.intersection(area).area < 1500.0:
                    continue
                if under - z < worst:
                    worst, who = under - z, ident
            if worst < C.ARENA_DECK_CLEAR:
                rows.append({"arena": arena["id"], "z": z, "clear": round(worst, 1),
                             "under": who})
    for row in sorted(rows, key=lambda r: r["clear"]):
        NOTE.append(f"L3 headroom {row['arena']} tier {row['z']:+.0f} has {row['clear']:.0f} m "
                    f"under {row['under']} (< {C.ARENA_DECK_CLEAR:.0f} m, C13; "
                    f"the datum is the dossier's)")
    return rows


def check_l3(layout: dict) -> None:
    """Ramp grades <= 20 deg, under-deck clear >= 24 m (32 m inside an arena), tunnel
    clear >= 32 m (squeeze 24)."""
    for con in layout["connectors"]:
        if con["kind"] != "ramp":
            continue
        grade = con.get("grade_deg")
        if grade is None:
            FAIL.append(f"L3 {con['id']} has no grade_deg")
        elif grade > C.MAX_RAMP_DEG:
            FAIL.append(f"L3 {con['id']} grade {grade:.1f} deg > {C.MAX_RAMP_DEG:.0f}")
        if con["width"] < C.ALLEY_MIN:
            FAIL.append(f"L3 {con['id']} width {con['width']:.0f} m < {C.ALLEY_MIN:.0f}")
    for tunnel in layout["tunnels"]:
        need = C.SQUEEZE_CLEAR if tunnel["kind"] == "squeeze" else C.TUNNEL_CLEAR_MIN
        if tunnel["clear"] < need:
            FAIL.append(f"L3 {tunnel['id']} clear {tunnel['clear']:.0f} m < {need:.0f}")
    arenas = [(arena["id"], geom.poly(arena["polygon"])) for arena in layout["arenas"]]
    for deck in layout["decks"]:
        clear = deck.get("under_clear")
        if clear is not None and clear < C.UNDER_DECK_CLEAR and deck["z"] > 0:
            FAIL.append(f"L3 {deck['id']} under_clear {clear:.0f} m < "
                        f"{C.UNDER_DECK_CLEAR:.0f}")
        # C13 asks for 32 m under anything that stands inside an arena polygon, and a
        # deck that IS an arena's own tier is exempt: the space under a fight floor is the
        # next tier down, and its datum is the dossier's, not this check's.
        if clear is None or deck.get("arena") or deck.get("over_water"):
            continue
        over = [aid for aid, area in arenas
                if area.intersection(geom.poly(deck["polygon"])).area > 1500.0]
        if over and clear < C.ARENA_DECK_CLEAR:
            FAIL.append(f"L3 {deck['id']} has {clear:.0f} m under it inside {over} "
                        f"(< {C.ARENA_DECK_CLEAR:.0f} m, C13)")
    for street in layout["streets"]:
        low, high = {"avenue": (C.AVENUE_MIN, C.AVENUE_MAX),
                     "street": (C.STREET_MIN, C.STREET_MAX),
                     "alley": (C.ALLEY_MIN, C.ALLEY_MAX)}[street["kind"]]
        if not low - 0.5 <= street["width"] <= high + 0.5:
            FAIL.append(f"L3 {street['id']} is a {street['kind']} of {street['width']:.0f} m "
                        f"(want {low:.0f}-{high:.0f})")


def check_l6(layout: dict) -> dict:
    """At least 8 anchors per arena, and every anchor within the 120 m range of another."""
    out = {}
    for arena in layout["arenas"]:
        aid = arena["id"]
        mine = [a for a in layout["anchors"] if a.get("arena") == aid]
        out[aid] = len(mine)
        if len(mine) < C.ANCHORS_PER_ARENA:
            FAIL.append(f"L6 {aid} has {len(mine)} anchors "
                        f"(< {C.ANCHORS_PER_ARENA})")
        for a in mine:
            near = min((math.dist(a["pos"], b["pos"]) for b in mine if b is not a),
                       default=math.inf)
            if near > C.ANCHOR_RANGE:
                FAIL.append(f"L6 anchor at {a['pos']} in {aid} is {near:.0f} m from the "
                            f"nearest other anchor (> {C.ANCHOR_RANGE:.0f} m)")
                break
    return out


def check_l7(layout: dict) -> dict:
    """Everything inside the playable square; the skyline ring outside it."""
    half, ring = layout["bounds"]["half"], layout["bounds"]["skyline_half"]

    def outside(poly: Polygon, what: str) -> None:
        minx, miny, maxx, maxy = poly.bounds
        if max(abs(minx), abs(maxx)) > half or max(abs(miny), abs(maxy)) > half:
            FAIL.append(f"L7 {what} leaves the playable square: "
                        f"[{minx:.0f},{miny:.0f},{maxx:.0f},{maxy:.0f}]")

    for group in ("streets", "viaducts", "rails", "tunnels"):
        for item in layout[group]:
            outside(geom.line(item["points"]).buffer(item["width"] / 2), item["id"])
    for deck in layout["decks"]:
        outside(geom.poly(deck["polygon"]), deck["id"])
    for b in layout["buildings"]:
        outside(box_of(b), b["id"])
    for item in layout["skyline"]:
        poly = geom.rect(tuple(item["center"]), tuple(item["size"]))
        if not poly.intersects(geom.poly([[-ring, -ring], [ring, -ring], [ring, ring],
                                          [-ring, ring]])):
            FAIL.append(f"L7 skyline tower at {item['center']} is outside the ring")
        if poly.within(geom.poly([[-half, -half], [half, -half], [half, half],
                                  [-half, half]])):
            FAIL.append(f"L7 skyline tower at {item['center']} is inside the playable square")
    for con in layout["connectors"]:
        for end in ("from", "to"):
            if max(abs(v) for v in con[end][:2]) > half:
                FAIL.append(f"L7 {con['id']} {end} {con[end]} leaves the playable square")
    return {"skyline": len(layout["skyline"])}


def check_l8(layout: dict) -> list[dict]:
    """Every lead vista reads: the subject is the first major hit, or the framing is a canyon."""
    rows, problems = vista_check.check(layout)
    FAIL.extend(problems)
    return rows


def check_l9(layout: dict) -> dict:
    """Every deck declares what carries it: towers, columns, the ground, or a span."""
    kinds: dict[str, int] = {}
    for deck in layout["decks"]:
        if deck.get("supported_by"):
            kind = "towers"
        elif deck.get("columns"):
            kind = "columns"
        elif deck.get("on_ground"):
            kind = "on ground"
        elif deck.get("span"):
            kind = "span"
        else:
            kind = "unsupported"
            FAIL.append(f"L9 {deck['id']} at z {deck['z']:.0f} declares nothing carrying it")
        kinds[kind] = kinds.get(kind, 0) + 1
    return kinds


def check_cover(over: dict) -> None:
    """MAP §4 (revised): 40-60 % of L1 under cover at the arenas, <= 25 % elsewhere."""
    low, high = cover_report.COVER_IN_ARENA
    if not low - 1e-6 <= over["arena"] <= high + 1e-6:
        FAIL.append(f"L-cover {over['arena'] * 100:.0f} % of {over['arena_m']} m of L1 street "
                    f"inside/near the arenas is under cover (want {low:.0%}-{high:.0%})")
    if over["open"] > cover_report.COVER_ELSEWHERE + 1e-6:
        FAIL.append(f"L-cover {over['open'] * 100:.0f} % of {over['open_m']} m of L1 street "
                    f"away from the arenas is under cover (want <= "
                    f"{cover_report.COVER_ELSEWHERE:.0%})")


def check_l10(layout: dict) -> dict:
    """The flyer routing graph: connected, inside the band, and clear of every box."""
    nodes = layout.get("sky_waypoints") or []
    edges = layout.get("sky_edges") or []
    if not nodes:
        FAIL.append("L10 the layout carries no sky_waypoints")
        return {"nodes": 0, "edges": 0}
    air = skygraph.Airspace(skygraph.solids(layout))
    index = {n["id"]: n for n in nodes}
    for n in nodes:
        x, y, z = n["pos"]
        if not 60.0 <= z <= 250.0:
            FAIL.append(f"L10 waypoint {n['id']} at z {z:.0f} is outside the +60..+250 band")
        if not air.node_clear(x, y, z):
            FAIL.append(f"L10 waypoint {n['id']} at ({x:.0f},{y:.0f},{z:.0f}) is closer than "
                        f"{skygraph.NODE_CLEAR:.0f} m to a building, deck or rail")
    for a, b in edges:
        if a not in index or b not in index:
            FAIL.append(f"L10 sky edge {a}->{b} names a waypoint that does not exist")
            continue
        if not air.edge_clear(tuple(index[a]["pos"]), tuple(index[b]["pos"])):
            FAIL.append(f"L10 sky edge {a}->{b} passes closer than "
                        f"{skygraph.EDGE_CLEAR:.0f} m to a building, deck or rail")
    seen, stack = set(), [nodes[0]["id"]]
    adjacency: dict[str, list[str]] = {n["id"]: [] for n in nodes}
    for a, b in edges:
        adjacency.setdefault(a, []).append(b)
        adjacency.setdefault(b, []).append(a)
    while stack:
        cur = stack.pop()
        if cur in seen:
            continue
        seen.add(cur)
        stack.extend(adjacency.get(cur, []))
    if len(seen) != len(nodes):
        FAIL.append(f"L10 the sky graph is in {len(nodes) - len(seen) + 1} pieces: "
                    f"{len(seen)} of {len(nodes)} waypoints are reachable")
    per: dict[str, int] = {}
    for n in nodes:
        per[n["district"]] = per.get(n["district"], 0) + 1
    for did in C.DISTRICTS:
        if per.get(did, 0) < skygraph.MIN_PER_DISTRICT:
            FAIL.append(f"L10 {did} has {per.get(did, 0)} sky waypoints "
                        f"(< {skygraph.MIN_PER_DISTRICT})")
    arenas = {}
    for arena in layout["arenas"]:
        c = geom.poly(arena["polygon"]).centroid
        arenas[arena["id"]] = len([n for n in nodes if math.dist(
            n["pos"][:2], (c.x, c.y)) <= skygraph.ARENA_REACH])
        if arenas[arena["id"]] < 6:
            FAIL.append(f"L10 {arena['id']} has {arenas[arena['id']]} sky waypoints within "
                        f"{skygraph.ARENA_REACH:.0f} m of its centre (< 6)")
    crown = len([n for n in nodes if n.get("ring") == "crown"
                 and 232.0 <= n["pos"][2] <= 250.0])
    if crown < 8:
        FAIL.append(f"L10 only {crown} waypoints ring the Crown at +232..+250 (< 8)")
    return {"nodes": len(nodes), "edges": len(edges), "per_district": per,
            "per_arena": arenas, "crown": crown}


def parse_args(argv: list[str]) -> str:
    """`--layout=<file>` checks another build (the lead re-runs the r7 file through it)."""
    for arg in argv[1:]:
        if arg.startswith("--layout="):
            return arg.split("=", 1)[1]
        if arg in ("-h", "--help"):
            print(__doc__)
            raise SystemExit(0)
    return C.LAYOUT_JSON


def main() -> int:
    graph, layout = load(C.GRAPH_JSON), load(parse_args(sys.argv))
    rng = random.Random(20261101)
    routes = checks_routes.summary(layout)
    FAIL.extend(checks_routes.FAIL)
    NOTE.extend(checks_routes.NOTE)
    l1 = check_l1(graph, layout)
    check_l2(layout)
    keep = check_l2_keepclear(layout)
    check_l3(layout)
    head = arena_headroom(layout)
    l4 = checks_arena.check_l4(layout, rng)
    field = checks_arena.check_cover_field(layout)
    l4_hives = checks_hives.check_l4_hives(layout)
    FAIL.extend(checks_hives.FAIL)
    l5 = checks_arena.check_l5(layout, rng)
    FAIL.extend(checks_arena.FAIL)
    NOTE.extend(checks_arena.NOTE)
    l6 = check_l6(layout)
    l7 = check_l7(layout)
    l8 = check_l8(layout)
    l9 = check_l9(layout)
    l10 = check_l10(layout)
    l11 = checks_sockets.check_l11(layout)
    FAIL.extend(checks_sockets.FAIL)
    over = overhead_cover(layout)
    check_cover(over)
    print(f"edges {l1['edges']} realised by {l1['connectors']} connectors + corridors · "
          f"skyline {l7['skyline']} towers")
    print(f"connector keep-clear: {keep['clear']}/{keep['endpoints']} endpoints clear of "
          f"buildings, cover and piers ({C.KEEP_CLEAR:.0f} m)")
    print(f"routes in 3D (r8): {routes['ok']}/{routes['total']} connectors pass a-d  ·  "
          f"{routes['holes']} deck holes, {routes['openings']} parapet openings, "
          f"{routes['shafts']} shafts placed, {routes['moved']} take-offs moved"
          + (f"  ·  worst headroom {routes['worst'][0]:.1f} m on {routes['worst'][1]}"
             if routes["worst"][1] else ""))
    if head:
        print(f"arena headroom: {len(head)} tiers under {C.ARENA_DECK_CLEAR:.0f} m, worst "
              + "  ".join(f"{r['arena']} {r['z']:+.0f} {r['clear']:.0f} m" for r in
                          sorted(head, key=lambda r: r['clear'])[:5]))
    summarise(layout, l4, l5, l6, over)
    print(f"cover field: {field['pieces']} pieces on {field['centres']} distinct centres, "
          f"{sum(r['pairs'] for r in field['per_arena'].values())} pairs closer than "
          f"{coverfield.MIN_GAP:.0f} m  ·  per arena "
          + "  ".join(f"{aid} {row['pieces']}/{row['centres']}"
                      for aid, row in sorted(field["per_arena"].items())))
    print("hive spires: " + checks_hives.report(l4_hives))
    print("deck supports: " + "  ".join(f"{k} {v}" for k, v in sorted(l9.items())))
    vista_check.report(l8)
    print(f"sky graph: {l10['nodes']} waypoints, {l10['edges']} edges, one component  "
          + "  ".join(f"{k} {v}" for k, v in sorted(l10.get("per_district", {}).items()))
          + "   per arena " + "  ".join(f"{k} {v}" for k, v in
                                        sorted(l10.get("per_arena", {}).items()))
          + f"   Crown ring {l10.get('crown', 0)}")
    print("spawn sockets: " + "  ".join(
        f"{k} {v['sockets']}@{v['tier']:+.0f} wall {v['wall']:.0f} cover {v['cover']:.0f} "
        f"sep {v['sep']:.0f}" for k, v in sorted(l11.items())))
    for note in NOTE:
        print(f"NOTE {note}")
    if FAIL:
        print(f"FAIL ({len(FAIL)})")
        for f in FAIL[:60]:
            print(f"  {f}")
        if len(FAIL) > 60:
            print(f"  ... and {len(FAIL) - 60} more")
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
