"""The generator half of the r8 route rule: make every designed route exist in 3D (lead, r8).

`route3d.py` is the model the checks sweep; this is the stage that shapes the city until the
sweep is clean. It draws NO random number - every function here is a search, a cut or a
declaration - so it can run late without re-rolling the one shared `rng` stream (lead, r8 item 5).

The policy is "a designed route has right of way", and what yields depends on what is in the way:

* a **deck** yields a `holes` entry - a ramp under a canopy or a jump up through a foundry plate
  gets a light well, which is what the acceptance pass needed;
* a **parapet or an edge barrier** yields an `openings` segment, the additive deck/corridor field
  this round adds (MAP §3);
* a **tunnel roof** yields a `holes` entry on the tunnel;
* a **building or an arena crate** is dropped by a late filter (`cuts.route_lots`, `cuts.route_cover`);
* a **viaduct or a rail does not yield**: a route whose take-off is capped by one is MOVED, because
  MAP §4 wants the Ring Viaduct to read as one continuous loop;
* a **landmark** does not yield either - the pagoda stairs climb outside it.

`place()` runs early (it chooses where shafts, take-offs and landings go, and re-lays the stairs
that had no horizontal run); `open_up()` runs last, on the finished city, because the canopies,
the skybridges and the station deck do not exist until then.
"""
from __future__ import annotations

import math

from shapely.geometry import LineString, Point
from shapely.ops import unary_union

import geom
import mapconst as C
import route3d

SHAFT_KINDS = ("lift", "vent", "vcat")
# Lead, r16 (city-build r11 decision): a connector that cannot be made to work carries
# `usable: false` and a reason. `checks_routes` skips it and every other stage leaves it alone.
UNUSABLE = {"con_B1_A3_lift": "lead r16: the Crown -> Spire Plaza lift has no working column "
                             "this round (the Spire's own shaft is in the way); city-build r11 "
                             "lists it as unusable"}
TAKE_OFF_REACH = 90.0     # m: how far from its node a take-off or a shaft may be placed
LAND_REACH = 90.0         # m: the same for a landing
LATTICE = 12.0            # m: the candidate grid
WELL_MARGIN = 4.0         # m: a hole is cut a little wider than the route that needs it
SHAFT_GAP = 56.0          # m: two shafts never share a plan spot
HIVE_KEEP = 60.0          # m: nothing this stage places lands in a spire's assault ring


def _candidates(centre: tuple[float, float], reach: float) -> list[tuple[float, float]]:
    """A lattice of candidate plan spots round `centre`, nearest first."""
    out: list[tuple[float, float]] = []
    steps = int(reach // LATTICE)
    for i in range(-steps, steps + 1):
        for j in range(-steps, steps + 1):
            x, y = centre[0] + i * LATTICE, centre[1] + j * LATTICE
            d = math.dist((x, y), centre)
            if d <= reach:
                out.append((round(x, 1), round(y, 1), round(d, 1)))
    return [(x, y) for x, y, _ in sorted(out, key=lambda p: p[2])]


def _on_floor(floors: list, x: float, y: float, z: float, radius: float,
              share: float = 0.2) -> bool:
    here = Point(x, y).buffer(radius, quad_segs=8)
    return any(abs(sz - z) <= C.ON_DATUM_TOL and poly.intersects(here)
               and poly.intersection(here).area > share * here.area
               for poly, sz, _ in floors)


def _landing(floors: list, x: float, y: float, z: float, pad: float) -> bool:
    """The test `checks_routes.check_columns` makes: floor round the hole the shaft cuts."""
    ring = Point(x, y).buffer(pad + 12.0, quad_segs=8).difference(
        Point(x, y).buffer(pad * 0.9, quad_segs=8))
    return any(abs(sz - z) <= C.ON_DATUM_TOL and poly.intersects(ring)
               and poly.intersection(ring).area > 60.0 for poly, sz, _ in floors)


def _blocked(tree, items, x: float, y: float, lo: float, hi: float, radius: float,
             allow: tuple[str, ...] = ()) -> list[str]:
    """Ids of the solids a column of `radius` at (x, y) crosses between `lo` and `hi`."""
    here = Point(x, y).buffer(radius, quad_segs=8)
    out: list[str] = []
    for idx in tree.query(here):
        poly, z0, z1, ident = items[idx]
        if ident in ("plateau", "docks") or any(ident.startswith(a) for a in allow):
            continue
        if z1 <= lo + 0.5 or z0 >= hi - 0.5 or not poly.intersects(here):
            continue
        if poly.intersection(here).area > 0.2 * here.area:
            out.append(ident)
    return out


def place(cons: list[dict], decks: list[dict], parts: dict, terrain: dict,
          landmarks: list[dict], hive_sites: list[dict]) -> dict:
    """Choose where every shaft, take-off and landing goes, and re-lay the stairs.

    Runs after the hive sites are reserved and the canopies exist, because a shaft may not land
    in a spire's assault ring and a canopy is one of the things a column has to miss.
    """
    layout = _skeleton(cons, decks, parts, terrain, landmarks)
    tree, items = route3d.solids(layout)
    floors = _floors(layout)
    placed: dict[str, int] = {"shaft": 0, "take_off": 0, "land_at": 0, "stairs": 0}
    taken: list[tuple[float, float]] = []
    for con in cons:
        if con["id"] in UNUSABLE:
            # lead, r16 (city-build r11): `con_B1_A3_lift` cannot be made to work this round, so
            # it carries `usable: false` and is left alone by every stage that reads a connector.
            con["usable"] = False
            con["unusable_why"] = UNUSABLE[con["id"]]
            continue
        if con["kind"] in SHAFT_KINDS:
            if _place_shaft(con, tree, items, floors, hive_sites, taken):
                placed["shaft"] += 1
                taken.append(route3d.shaft_xy(con))
        elif con["kind"] == "edgejump":
            placed["take_off"] += _place_jump(con, tree, items, floors, landmarks)
        elif con["kind"] == "stairs":
            placed["stairs"] += _relay_stairs(con, decks, landmarks)
    placed["piers"] = _drop_piers(cons, parts)
    placed["cranes"] = _nudge_cranes(landmarks, cons, parts)
    return placed


CRANE_REACH = 160.0     # m: how far a crane may slide to get off a route
CRANE_STEP = 20.0       # m: the slide step


def _nudge_cranes(landmarks: list[dict], cons: list[dict], parts: dict) -> int:
    """Slide a gantry crane off a route it stands on. A pure search: no random number.

    `props.landmarks()` authors the four harbour cranes by hand, and one of them stood on V2 -
    the node the A1 -> V2 edgejump lands on - so its 52 x 44 m cab was 16 m over the take-off.
    A crane is set dressing; the route is not, so the crane moves and `params.positions` records
    where it ended up.
    """
    bands = _strips(cons + [dict(c, kind="ramp", width=c["width"],
                                 path=[[p[0], p[1], c["z"]] for p in c["points"]])
                            for c in parts["viaducts"] + parts["rails"]])
    if bands is None:
        return 0
    moved = 0
    for lm in landmarks:
        if lm["kind"] != "cranes":
            continue
        spots = []
        for cx, cy in lm["params"]["positions"]:
            spot = _clear_spot((float(cx), float(cy)), bands)
            spots.append([round(spot[0], 1), round(spot[1], 1)])
            moved += 0 if spot == (float(cx), float(cy)) else 1
        lm["params"]["positions"] = spots
    return moved


def _clear_spot(centre: tuple[float, float], bands: Polygon) -> tuple[float, float]:
    """The nearest spot to `centre` whose 52 x 44 m cab misses every route band."""
    from shapely.geometry import box as sbox
    for ring in range(0, int(CRANE_REACH // CRANE_STEP) + 1):
        for k in range(max(1, ring * 8)):
            ang = math.tau * k / max(1, ring * 8)
            x = centre[0] + math.cos(ang) * ring * CRANE_STEP
            y = centre[1] + math.sin(ang) * ring * CRANE_STEP
            if not sbox(x - 28, y - 24, x + 28, y + 24).intersects(bands):
                return (x, y)
    return centre


def _strips(cons: list[dict]):
    """The union of every route's plan strip, or None when there is none."""
    polys = _strip_polys(cons)
    return unary_union(polys) if polys else None


def _strip_polys(cons: list[dict]) -> list:
    out = []
    for con in cons:
        half = float(con["width"]) / 2 + 8.0
        if con["kind"] in ("ramp", "stairs", "edgejump"):
            pts = [(p[0], p[1]) for p in route3d.path_of(con)]
        elif con["kind"] in SHAFT_KINDS:
            pts = [route3d.shaft_xy(con)]
        else:
            continue
        line = LineString(pts) if len(pts) > 1 else None
        out.append(line.buffer(half, cap_style=2) if line is not None and line.length >= 1.0
                   else Point(pts[0][0], pts[0][1]).buffer(half))
    return out


def _drop_piers(cons: list[dict], parts: dict) -> int:
    """A viaduct pier or a rail pylon may not stand in a route's strip. A pure filter.

    `keepclear.pier_ok` already keeps a pier out of a connector's 12 m endpoint sphere, but the
    routes are laid after the corridors are built, so the piers are swept here instead - dropped,
    never moved, so no id shifts and nothing re-rolls.
    """
    strip = _strips(cons)
    if strip is None:
        return 0
    dropped = 0
    for group in ("viaducts", "rails"):
        for item in parts[group]:
            keep = [p for p in item.get("piers", [])
                    if not strip.intersects(Point(p[0], p[1]).buffer(PIER_W, quad_segs=4))]
            dropped += len(item.get("piers", [])) - len(keep)
            item["piers"] = keep
    return dropped


PIER_W = 12.0            # m: the plan radius a pier needs clear (kit PIER_W 14 plus a margin)


def _skeleton(cons: list[dict], decks: list[dict], parts: dict, terrain: dict,
              landmarks: list[dict]) -> dict:
    """The layout as far as it exists when `place` runs: enough for the solids model.

    The buildings and the arena cover are deliberately empty - they are placed later and a route
    that needs one of them gone drops it in `cuts`, which is a filter, not a re-roll.
    """
    return {"buildings": [], "decks": decks, "connectors": cons, "arenas": [],
            "landmarks": landmarks, "bounds": {"half": C.HALF},
            "viaducts": parts["viaducts"], "rails": parts["rails"],
            "tunnels": parts["tunnels"], "terrain": terrain,
            "streets": parts["streets"]}


def _floors(layout: dict) -> list:
    """The walkable surfaces `place` may stand a pad on (corridors, decks, ground, plateau)."""
    out = []
    for group in ("streets", "viaducts", "rails", "tunnels"):
        for item in layout[group]:
            out.append((geom.line(item["points"]).buffer(item["width"] / 2),
                        float(item["z"]), item["id"]))
    for deck in layout["decks"]:
        area = geom.poly(deck["polygon"])
        for hole in deck.get("holes", []):
            area = area.difference(geom.poly(hole))
        out.append((area, float(deck["z"]), deck["id"]))
    terr = layout["terrain"]
    half = float(layout["bounds"]["half"])
    ground = geom.poly([[-half, -half], [half, -half], [half, half], [-half, half]])
    out.append((ground.difference(geom.poly(terr["plateau"]["polygon"])), 0.0, "ground"))
    out.append((geom.poly(terr["plateau"]["polygon"]), float(terr["plateau"]["z"]), "plateau"))
    return out


IMMOVABLE = ("via_", "rail_", "ring_viaduct", "stilt_pagoda", "harbor_cranes", "reactor_stacks",
             "spire", "block9")


def _immovable(ids: list[str], landmarks: list[dict]) -> list[str]:
    """The blockers a route may never punch through: the elevated corridors and the landmarks."""
    fixed = tuple(IMMOVABLE) + tuple(lm["id"] for lm in landmarks)
    return [i for i in ids if any(i.startswith(f) or f in i for f in fixed)]


def _place_shaft(con: dict, tree, items, floors, hive_sites: list[dict],
                 taken: list[tuple[float, float]]) -> bool:
    """Put a lift / vent / vcat column where both its ends have a floor and nothing caps it.

    MAP has no rule that a shaft must stand on its own node - the dossier's §4.8 rows only say
    which two nodes the ride joins - so the column is placed within `TAKE_OFF_REACH` of both, and
    `params.shaft` says where. `from` and `to` stay on their nodes: they are the walk, not the ride.
    """
    a, b = con["from"], con["to"]
    pad = float(con["width"]) * 0.5
    lo, hi = min(a[2], b[2]), max(a[2], b[2]) + route3d.TOP_AIR
    spots = {(x, y) for x, y in _candidates(tuple(b[:2]), TAKE_OFF_REACH)} | \
            {(x, y) for x, y in _candidates(tuple(a[:2]), TAKE_OFF_REACH)}
    best, fallback = None, None
    for x, y in sorted(spots, key=lambda p: math.dist(p, a[:2]) + math.dist(p, b[:2])):
        walk = math.dist((x, y), a[:2]) + math.dist((x, y), b[:2])
        if walk > 2 * TAKE_OFF_REACH:
            continue
        if any(math.dist((x, y), t) < SHAFT_GAP for t in taken):
            continue
        if any(math.dist((x, y), h["pos"][:2]) < HIVE_KEEP
               and abs(h["pos"][2] - b[2]) < 8.0 for h in hive_sites):
            continue
        if not _on_floor(floors, x, y, a[2], pad) or not _landing(floors, x, y, b[2], pad):
            continue
        blocked = _blocked(tree, items, x, y, lo, hi, pad)
        if _immovable(blocked, []):
            continue
        if not blocked:
            best = (x, y)
            break
        if fallback is None:
            fallback = (x, y)      # the nearest spot whose caps are all pierceable
    best = best or fallback
    if best is None:
        return False
    con.setdefault("params", {})["shaft"] = [best[0], best[1]]
    con["params"]["walk_m"] = round(math.dist(best, a[:2]), 1)
    return True


def _place_jump(con: dict, tree, items, floors, landmarks: list[dict]) -> int:
    """Move an edgejump's take-off (and, if it must, its landing) until the arc is in the open.

    The dossier's `horiz 0` rows put several take-offs directly under the deck they jump to, and
    the Ring Viaduct runs over three more. A jump may start anywhere on the floor its node stands
    on, so the take-off moves and `params.take_off` says where; the node is still what the edge
    joins and the mech still walks to it.
    """
    moved = 0
    if _arc_ok(con, tree, items):
        return 0
    a, b = con["from"], con["to"]
    for x, y in _candidates(tuple(a[:2]), TAKE_OFF_REACH):
        if not _on_floor(floors, x, y, a[2], 8.0):
            continue
        con["params"] = {**con.get("params", {}), "take_off": [x, y, a[2]]}
        if _arc_ok(con, tree, items):
            moved += 1
            break
    starts = [(x, y) for x, y in _candidates(tuple(a[:2]), TAKE_OFF_REACH)
              if _on_floor(floors, x, y, a[2], 8.0)]
    lands = [(x, y) for x, y in _candidates(tuple(b[:2]), LAND_REACH)
             if _on_floor(floors, x, y, b[2], 8.0)]
    for lx, ly in lands[:24]:
        for sx, sy in starts[:24]:
            trial = dict(con)
            trial["params"] = {**con.get("params", {}), "take_off": [sx, sy, a[2]],
                               "land_at": [lx, ly, b[2]]}
            if _arc_ok(trial, tree, items):
                con["params"] = trial["params"]
                return 1
    con.get("params", {}).pop("take_off", None)      # nothing worked: leave the node take-off
    return 0


def _arc_ok(con: dict, tree, items) -> bool:
    """Does this edgejump's arc pass through nothing and land with 24 m of air over it?"""
    a, b = route3d.ends(con)
    for p in route3d.sample_path(route3d.jump_arc(con), float(con["width"])):
        if math.dist(p, a) < 6.0 or math.dist(p, b) < 6.0:
            continue
        if _pierce(p, tree, items):
            return False
        if route3d.headroom(p, tree, items)[0] < route3d.CLEAR:
            return False
    return True


def _pierce(p: tuple[float, float, float], tree, items) -> str:
    here = Point(p[0], p[1]).buffer(C.CAPSULE_R, quad_segs=6)
    for idx in tree.query(here):
        poly, z0, z1, ident = items[idx]
        if ident in ("plateau", "docks") or ident.endswith(("_parapet", "_barrier")):
            continue
        if route3d.pierces(p, poly, z0, z1) and poly.intersects(here):
            return ident
    return ""


STAIR_DEG = 18.0        # deg: a flight is laid a little under MAP's 20 deg so the check has room
STAIR_MARGIN = 1.15     # the run is a little longer than the minimum, for the same reason
BEARINGS = 16           # candidate orientations for a stair tower


def stair_flights(con: dict) -> int:
    """How many flights a stair has: the dossier's `steps:` tag, or one per 32 m of rise (C8)."""
    tagged = next((int(t.split(":")[1]) for t in con.get("tags", [])
                   if t.startswith("steps:")), 0)
    rise = abs(float(con["to"][2]) - float(con["from"][2]))
    return max(tagged, int(math.ceil(rise / route3d.MAX_FLIGHT_RISE)), 1)


def _need(rise: float, flights: int) -> float:
    """The plan run one flight needs at `STAIR_DEG`."""
    return (rise / flights) / math.tan(math.radians(STAIR_DEG)) * STAIR_MARGIN


def _relay_stairs(con: dict, decks: list[dict], landmarks: list[dict]) -> int:
    """Re-lay a stair that has no horizontal run, or one whose flights are over 20 deg.

    Two shapes, both generated and neither a hand `move`:

    * **a stair tower** - when the two nodes stand on the same spot (`horiz 0` in dossier §4.8,
      A4/M3 and O4/O5), the flights wrap the node as a regular polygon of `flights + 1` sides.
      The rise is spread over the first `flights` edges and the closing edge is flat, so the last
      flight arrives level with the deck it serves instead of driving into its rim.
    * **a detour** - when the nodes are apart but too close for the flights (F6/F4, A1/H3), the
      single intermediate landing goes where two circles of the needed run round the two nodes
      meet, on whichever side is clearer.
    """
    a, b = [float(v) for v in con["from"]], [float(v) for v in con["to"]]
    flights = stair_flights(con)
    rise = abs(b[2] - a[2])
    need = _need(rise, flights)
    run = math.dist(a[:2], b[:2])
    con["params"] = {**con.get("params", {}), "flights": flights,
                     "flight_rise": round(rise / flights, 1)}
    if run >= flights * need - 0.5:
        return 0
    if run < 1.0:
        con["path"] = _tower(a, b, flights, need, decks, landmarks)
        return 1
    if flights == 2:
        con["path"] = _detour(a, b, need, decks, landmarks)
        return 1
    return 0


def _clear_of(point: tuple[float, float], decks: list[dict], landmarks: list[dict],
              width: float, z: float) -> float:
    """How far a stair corner is from the nearest thing it may not pass through."""
    here = Point(point[0], point[1]).buffer(width, quad_segs=6)
    worst = 1e9
    for deck in decks:
        if deck["id"].startswith(("via_", "rail_")):
            continue
        area = geom.poly(deck["polygon"])
        if area.buffer(0).contains(here) and abs(float(deck["z"]) - z) < 40.0:
            worst = min(worst, 0.0)
    for lm in landmarks:
        poly = Point(lm["pos"][0], lm["pos"][1]).buffer(
            max(lm.get("params", {}).get("footprint", [56, 56])) * 0.42 + 12.0, quad_segs=8)
        if not poly.is_empty:
            worst = min(worst, here.distance(poly))
    return worst


def _tower(a: list[float], b: list[float], flights: int, need: float,
           decks: list[dict], landmarks: list[dict]) -> list[list[float]]:
    """A stair tower: a regular polygon of `flights + 1` sides wrapping the stacked nodes.

    Vertex 0 is the node; the closing edge is flat at the top, so the last flight arrives level
    with the deck it serves. The rotation is chosen to keep the corners off the landmarks (the
    pagoda's crown deck overhangs its tiers, so a stair may not hug it).
    """
    sides = flights + 1
    radius = need / (2.0 * math.sin(math.pi / sides))
    rise = (b[2] - a[2]) / flights
    best, best_score = None, -1e9
    for k in range(BEARINGS):
        phase = math.tau * k / BEARINGS
        cx = a[0] - radius * math.cos(phase)
        cy = a[1] - radius * math.sin(phase)
        corners = [(cx + radius * math.cos(phase + math.tau * i / sides),
                    cy + radius * math.sin(phase + math.tau * i / sides))
                   for i in range(sides)]
        score = min(_clear_of(c, decks, landmarks, 20.0, a[2]) for c in corners)
        if score > best_score:
            best_score, best = score, corners
    path = [[round(a[0], 1), round(a[1], 1), round(a[2], 1)]]
    for i, (x, y) in enumerate(best[1:], start=1):
        path.append([round(x, 1), round(y, 1), round(a[2] + rise * i, 1)])
    path.append([round(b[0], 1), round(b[1], 1), round(b[2], 1)])
    return path


def _detour(a: list[float], b: list[float], need: float, decks: list[dict],
            landmarks: list[dict]) -> list[list[float]]:
    """One landing where two circles of the needed run round the two nodes meet.

    Both nodes are on the flight's own floor level at their own z, so the landing carries half the
    rise; the two candidate sides are scored on what they clear and the clearer one is taken.
    """
    mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)
    span = math.dist(a[:2], b[:2])
    off = math.sqrt(max(need ** 2 - (span * 0.5) ** 2, 0.0))
    ux, uy = (b[0] - a[0]) / (span or 1.0), (b[1] - a[1]) / (span or 1.0)
    best, best_score = None, -1e9
    for side in (1.0, -1.0):
        p = (mid[0] - uy * off * side, mid[1] + ux * off * side)
        score = _clear_of(p, decks, landmarks, 24.0, (a[2] + b[2]) * 0.5)
        if score > best_score:
            best_score, best = score, p
    return [[round(a[0], 1), round(a[1], 1), round(a[2], 1)],
            [round(best[0], 1), round(best[1], 1), round((a[2] + b[2]) * 0.5, 1)],
            [round(b[0], 1), round(b[1], 1), round(b[2], 1)]]
