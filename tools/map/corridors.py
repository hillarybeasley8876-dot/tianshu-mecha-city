"""Corridor stage: streets, the Ring Viaduct, the Skyrail, L0 tunnels and decks.

Graph edges of kind path/rail/tunnel become corridors here (MAP §3: "every graph edge must
be realised by exactly one connector, or a corridor segment that contains both endpoints");
every other kind is left to connectors.py. Long runs get a dogleg so no straight sightline
exceeds 300 m (dossier §3.2).

It also owns the two questions every later stage asks about a finished corridor set: what a
corridor caps above it (`height_caps`) and which part of it traffic actually uses
(`navigable_core`).
"""
from __future__ import annotations

import math
import random

from shapely.geometry import LineString, MultiLineString, Point, Polygon
from shapely.ops import unary_union

import geom
import keepclear
import mapconst as C

CORRIDOR_KINDS = ("path", "rail", "tunnel")
SQUEEZE_EDGES = ("U3>U6",)
VIADUCT_WIDTH = 56.0
PIER_SPACING = 48.0
RAIL_Z, RAIL_W = 80.0, 24.0
TUNNEL_Z, TUNNEL_W, TUNNEL_CLEAR = -40.0, 56.0, 34.0
# The Spire's own shaft is a square collider (`kit/spire.py::_loft`), so a viaduct chord that
# clears the round shaft still clips its corners. The collar chords (S3w-S3s-S3e-S3n) cut inside
# the collar ring, so each is bowed outward until its edge clears the box (lead, r8).
ARENA_COVER_REACH = 100.0     # MAP §4: the arena's own approaches may be decked
ARENA_CANOPY_COLUMNS = 48.0   # MAP §4: every remaining deck carries columns at <= 48 m
CANOPY_Z = 32.0               # the L1 canopy datum (28 m clear on a 4 m slab)
CANOPY_Z_ARENA = 40.0         # ...but 32 m clear inside an arena (C13, lead r4 point 2)
SPIRE_XY = (0.0, 120.0)
SPIRE_HALF = 41.4     # m: the shaft box's half side at the collar (`spire.py::_loft`, r 44 x 0.94)


def _bow_round_spire(pts: list[list[float]]) -> list[list[float]]:
    """Bow a viaduct outward until its deck clears the Spire's shaft box (`kit/spire.py`).

    The collider is a square, so a chord that clears the round shaft still clips its corners;
    the test is the real one - the deck's own plan strip against the box - and the bow grows
    until it passes. No random number: the same chord always bows the same way.
    """
    from shapely.geometry import box as sbox
    keep = sbox(SPIRE_XY[0] - SPIRE_HALF, SPIRE_XY[1] - SPIRE_HALF,
                SPIRE_XY[0] + SPIRE_HALF, SPIRE_XY[1] + SPIRE_HALF)
    for _ in range(12):
        line = geom.line(pts)
        if not line.buffer(VIADUCT_WIDTH / 2, cap_style=2).intersects(keep):
            return pts
        mid = line.interpolate(line.length / 2)
        ux, uy = mid.x - SPIRE_XY[0], mid.y - SPIRE_XY[1]
        norm = math.hypot(ux, uy) or 1.0
        push = max(SPIRE_HALF + VIADUCT_WIDTH / 2 + 8.0 - norm, 12.0)
        pts = pts[:1] + [[round(mid.x + ux / norm * push, 1),
                          round(mid.y + uy / norm * push, 1)]] + pts[1:]
    return pts


def key(edge: dict) -> str:
    return f"{edge['from']}>{edge['to']}"


def split_edges(graph: dict) -> tuple[list[dict], list[dict]]:
    corridors = [e for e in graph["edges"] if e["kind"] in CORRIDOR_KINDS]
    connectors = [e for e in graph["edges"] if e["kind"] not in CORRIDOR_KINDS]
    return corridors, connectors


def ground_z(plateau: Polygon, x: float, y: float) -> float:
    return 32.0 if plateau.contains(Point(x, y)) else 0.0


def street_width(edge: dict, rules: dict, default: float) -> tuple[str, float, str | None]:
    entry = rules["named_streets"].get(key(edge))
    if entry:
        return entry["kind"], float(entry["width"]), entry.get("name")
    return "street", default, None


def street_w_r1(edge: dict, rules: dict, default: float) -> float:
    """The width this street had before the MAP §4 revision (for the land-freed report)."""
    entry = rules["named_streets"].get(key(edge))
    return float(entry["w_r1"]) if entry and "w_r1" in entry else default


def build_corridors(graph: dict, nodes: dict, rules: dict, plateau: Polygon,
                    rng: random.Random, cons: list[dict] | None = None) -> dict:
    """Streets / viaducts / rails / tunnels realised from the corridor edges of the graph.

    `cons` are the connectors: a viaduct pier may not stand inside a connector's 12 m
    keep-clear sphere, or the take-off sits on a pier base (lead, r4 point 1).
    """
    streets, viaducts, rails, tunnels = [], [], [], []
    corridors, _ = split_edges(graph)
    for edge in corridors:
        a, b = nodes[edge["from"]]["pos"], nodes[edge["to"]]["pos"]
        p0, p1 = (a[0], a[1]), (b[0], b[1])
        ident = key(edge).replace(">", "_")
        if edge["kind"] == "rail":
            pts = geom.dogleg(p0, p1, 300.0, rng)
            rails.append({"id": f"rail_{ident}", "z": RAIL_Z, "width": RAIL_W,
                          "points": pts, "through": [], "nodes": [edge["from"], edge["to"]]})
        elif edge["kind"] == "tunnel":
            squeeze = key(edge) in SQUEEZE_EDGES
            pts = geom.dogleg(p0, p1, 250.0, rng)
            tunnels.append({"id": f"tunnel_{ident}",
                            "kind": "squeeze" if squeeze else ("old_line" if "U4" in ident
                                                                else "trunk"),
                            "z": TUNNEL_Z, "width": 32.0 if squeeze else TUNNEL_W,
                            "clear": C.SQUEEZE_CLEAR if squeeze else TUNNEL_CLEAR,
                            "points": pts, "nodes": [edge["from"], edge["to"]]})
        elif abs(a[2] - b[2]) < 0.5 and a[2] >= 31.0:
            pts = _bow_round_spire(geom.dogleg(p0, p1, 300.0, rng))
            piers = [(x, y) for x, y in geom.sample_along(pts, PIER_SPACING, PIER_SPACING / 2)
                     if ground_z(plateau, x, y) < 31.0]
            if cons:
                piers = [(x, y) for x, y in piers
                         if keepclear.pier_ok(cons, x, y)]
            if piers:
                viaducts.append({"id": f"via_{ident}", "kind": "ring", "z": 32.0,
                                 "width": VIADUCT_WIDTH, "points": pts,
                                 "pier_spacing": PIER_SPACING,
                                 "piers": [[x, y, round(32.0 - ground_z(plateau, x, y), 1)]
                                           for x, y in piers],
                                 "nodes": [edge["from"], edge["to"]]})
            else:
                kind, width, name = street_width(edge, rules, 44.0)
                streets.append({"id": f"st_{ident}", "kind": kind, "z": 32.0, "width": width,
                                "w_r1": street_w_r1(edge, rules, 52.0),
                                "points": pts, "name": name, "nodes": [edge["from"], edge["to"]]})
        else:
            kind, width, name = street_width(edge, rules, 44.0)
            pts = geom.dogleg(p0, p1, C.MAX_STRAIGHT_STREET, rng)
            streets.append({"id": f"st_{ident}", "kind": kind, "z": 0.0, "width": width,
                            "w_r1": street_w_r1(edge, rules, 52.0),
                            "points": pts, "name": name, "nodes": [edge["from"], edge["to"]]})
    ring = ring_viaduct(viaducts, streets, nodes)
    if ring:
        viaducts.append(ring)
    return {"streets": streets, "viaducts": viaducts, "rails": rails, "tunnels": tunnels}


RING_NODES = ("K3", "V2", "V3", "V4", "V5", "V6", "M1", "S5", "O3", "V7")


def ring_viaduct(viaducts: list[dict], streets: list[dict], nodes: dict) -> dict | None:
    """The Ring Viaduct as one closed polyline, so it reads as a single loop in plan.

    The per-edge segments stay (L1 realises one corridor per graph edge); this record chains
    them into the 2.8 km loop the dossier asks for and lists the segments it is made of.
    """
    seg = {}
    # the loop is viaduct where it flies and a plateau road where it has landed
    for item in viaducts + [s for s in streets if abs(s["z"] - 32.0) < 1.0]:
        if not item.get("nodes") or len(item["nodes"]) != 2:
            continue
        a, b = item["nodes"]
        if a in RING_NODES and b in RING_NODES:
            seg[(a, b)] = item
            seg[(b, a)] = item
    points: list[list[float]] = []
    used: list[str] = []
    order = list(RING_NODES)
    for a, b in zip(order, order[1:] + order[:1]):
        item = seg.get((a, b)) or seg.get((b, a))
        if item is None:
            return None
        if item["id"] not in used:
            used.append(item["id"])
        pts = item["points"] if item["nodes"][0] == a else list(reversed(item["points"]))
        points.extend(pts if not points else pts[1:])
    if len(points) < 4:
        return None
    return {"id": "ring_viaduct_loop", "kind": "ring", "z": 32.0, "width": VIADUCT_WIDTH,
            "points": points + [points[0]], "pier_spacing": PIER_SPACING, "segments": used,
            "loop_length": round(geom.length_of(points + [points[0]]), 1), "nodes": []}


def _circle(center: tuple[float, float], radius: float, segments: int = 40) -> list[list[float]]:
    return [[round(center[0] + radius * math.cos(2 * math.pi * i / segments), 1),
             round(center[1] + radius * math.sin(2 * math.pi * i / segments), 1)]
            for i in range(segments)]


def perforate_decks(decks: list[dict], parts: dict, nodes: dict) -> int:
    """Open a deck wherever a corridor's navigable volume would pass through it.

    A plate at +16 cannot roof an L1 street with only 12 m of headroom, so the deck is cut
    back over the street: the ramps and terraces read as decks with slots, the street stays
    open to the sky, and L2/L3 hold without pretending the space under a low plate is usable.
    """
    cut = 0
    for _ in range(3):                      # new islands may themselves straddle a street
        made = _perforate_pass(decks, parts, nodes)
        cut += made
        if not made:
            break
    return cut


def _perforate_pass(decks: list[dict], parts: dict, nodes: dict) -> int:
    cut = 0
    extra: list[dict] = []
    for deck in list(decks):
        span = (deck["z"] - deck["thickness"], deck["z"])
        blockers = []
        for group in ("streets", "viaducts", "rails", "tunnels"):
            for item in parts[group]:
                top = item["z"] + item.get("clear", C.UNDER_DECK_CLEAR)
                if not (span[0] < top - 0.5 and item["z"] < span[1] - 0.5):
                    continue
                band = geom.line(item["points"]).buffer(item["width"] / 2 + 2.0)
                # never cut away the surface a graph node stands on
                for node in nodes.values():
                    if abs(node["pos"][2] - deck["z"]) <= C.ON_DATUM_TOL and \
                            band.contains(Point(node["pos"][0], node["pos"][1])):
                        band = band.difference(
                            Point(node["pos"][0], node["pos"][1]).buffer(34.0))
                if not band.is_empty and band.intersects(geom.poly(deck["polygon"])):
                    blockers.append(band)
        if not blockers:
            continue
        area = geom.poly(deck["polygon"])
        for hole in deck.get("holes", []):
            area = area.difference(geom.poly(hole))
        keep = area.difference(unary_union(blockers))
        if keep.is_empty or keep.area < 400.0:
            continue
        islands = sorted((g for g in getattr(keep, "geoms", [keep])
                          if isinstance(g, Polygon) and g.area > 400.0),
                         key=lambda g: -g.area)
        if not islands:
            continue
        for index, part in enumerate(islands):
            target = deck if index == 0 else dict(deck, id=f"{deck['id']}_b{index}")
            target["polygon"] = [[round(x, 1), round(y, 1)]
                                 for x, y in part.exterior.coords[:-1]]
            target["holes"] = [[[round(x, 1), round(y, 1)] for x, y in ring.coords[:-1]]
                               for ring in part.interiors] + \
                (list(deck.get("holes", [])) if index == 0 else [])
            if index:
                extra.append(target)
        cut += 1
    decks.extend(extra)
    return cut


def under_clearance(decks: list[dict], parts: dict, arenas: list[dict]) -> None:
    """Set each deck's `under_clear` to the real headroom over navigable space below.

    Decks with nothing navigable beneath them get no `under_clear` at all: the space under a
    low ramp ring is structure, not a place the player walks.
    """
    below: list[tuple[Polygon, float]] = []
    for group in ("streets", "viaducts", "rails", "tunnels"):
        for item in parts[group]:
            below.append((geom.line(item["points"]).buffer(item["width"] / 2), item["z"]))
    for deck in decks:
        underside = deck["z"] - deck["thickness"]
        arena_below = []
        for arena in arenas:
            if arena["id"] == deck.get("arena"):
                continue          # the deck is that arena's own floor, not a roof over it
            overlap = geom.poly(arena["polygon"]).intersection(geom.poly(deck["polygon"])).area
            if overlap < 1500.0:
                continue          # a sliver at the edge is not "space under the deck"
            arena_below.append((geom.poly(arena["polygon"]), min(arena["tiers"])))
        area = geom.poly(deck["polygon"])
        for hole in deck.get("holes", []):
            area = area.difference(geom.poly(hole))
        clear = [underside - z for poly, z in below + arena_below
                 if z < underside and poly.intersection(area).area > 1.0]
        deck.pop("under_clear", None)
        if clear:
            deck["under_clear"] = round(min(clear), 1)


def build_decks(rules: dict, nodes: dict) -> list[dict]:
    """Decks from the rules table: plazas, terraces, the Spire collar and roof rings, the
    Crown, the Sky Garden, the Knot's stacked loops and the Foundry lattice decks.

    `holes` (extra to the MAP §3 schema) carries the inner ring of a ring deck and the
    openings of a lattice deck, so Blender can cut them.
    """
    out: list[dict] = []
    for spec in rules["decks"]:
        deck = {"id": spec["id"], "kind": spec["kind"], "z": float(spec["z"]),
                "thickness": float(spec["thickness"]), "parapet": float(spec.get("parapet", 5))}
        if "district" in spec:
            deck["district"] = spec["district"]
        if "arena" in spec:
            deck["arena"] = spec["arena"]
        if "under_clear" in spec:
            deck["under_clear"] = float(spec["under_clear"])
        if spec.get("over_water"):
            deck["over_water"] = True
        if spec["shape"] == "rect":
            deck["polygon"] = geom.rect_points(tuple(spec["center"]), tuple(spec["size"]),
                                               spec.get("rot", 0.0))
            area = geom.rect(tuple(spec["center"]), tuple(spec["size"]), spec.get("rot", 0.0))
        else:
            deck["polygon"] = _circle(tuple(spec["center"]), spec["r_out"])
            area = Polygon([(p[0], p[1]) for p in deck["polygon"]])
            if spec.get("r_in", 0) > 0:
                deck["holes"] = [_circle(tuple(spec["center"]), spec["r_in"])]
        if "rim_steps" in spec:
            deck["rim_steps"] = [{"r": float(s["r"]), "z": float(s["z"]),
                                  "rise": float(s["rise"])} for s in spec["rim_steps"]]
        if "fins" in spec:
            deck["fins"] = [{"angle_deg": float(f["angle_deg"]), "reach": float(f["reach"]),
                             "width": float(f["width"]), "height": float(f["height"])}
                            for f in spec["fins"]]
        if "core" in spec:
            deck["core"] = {"r": float(spec["core"]["r"]), "z": float(deck["z"]),
                            "height": float(spec["core"]["height"])}
        if spec.get("lattice"):
            deck["holes"] = _lattice_holes(area, spec, nodes)
        out.append(deck)
    return out


def _lattice_holes(area: Polygon, spec: dict, nodes: dict) -> list[list[list[float]]]:
    """Square voids in a foundry deck, kept clear of the graph nodes standing on it."""
    holes = []
    cx, cy = spec["center"]
    w, d = spec["size"]
    keep = [(n["pos"][0], n["pos"][1]) for n in nodes.values()
            if abs(n["pos"][2] - spec["z"]) < 2.0]
    for gx in range(-int(w / 2) + 60, int(w / 2) - 40, 90):
        for gy in range(-int(d / 2) + 60, int(d / 2) - 40, 90):
            cell = geom.rect((cx + gx, cy + gy), (44, 44))
            if not area.contains(cell):
                continue
            if any(cell.distance(Point(k)) < 46.0 for k in keep):
                continue
            holes.append(geom.rect_points((cx + gx, cy + gy), (44, 44)))
    return holes


def canopies(streets: list[dict], arenas: list[dict] | dict, rng: random.Random,
             chunk: float = 64.0, period: float = 118.0,
             slots: list[tuple[Polygon, float]] = ()) -> list[dict]:
    """Overhead slabs on the L1 streets that run through or beside an arena.

    MAP §4 (revised after r2): 40-60 % of L1 street length is under cover *inside arenas and
    within 100 m of their outline*, and at most 25 % everywhere else - and outside the
    arenas only structures that read as architecture (podium decks between buildings,
    skybridges, viaducts, rails) count. A free-standing plate over a street kills the dusk
    light shafts and costs a shadow draw per slab, so the free-standing canopies live only
    where the fight needs them.

    A slab over arena ground sits at +40, not +32: C13 wants 32 m of headroom under anything
    inside an arena polygon and a 4 m slab at +32 only leaves 28 (lead, r4 point 2).

    Each slab stays inside its street corridor (width + 8 m), so it can never collide with a
    building: buildings keep a >= 4 m setback from every corridor edge. It spans between the
    two frontages it roofs, which `supports.deck_columns` records as `span: "street walls"`.
    """
    shapes = (list(arenas.values()) if isinstance(arenas, dict)
              else [a["polygon"] for a in arenas])
    inside = [geom.poly(p) for p in shapes]
    near = unary_union([p.buffer(ARENA_COVER_REACH) for p in inside]) if inside else Polygon()
    if near.is_empty:
        return []
    out: list[dict] = []
    for street in streets:
        if street["z"] > 0.5:
            continue
        line = geom.line(street["points"])
        total = line.intersection(near).length
        if total < chunk * 1.5:
            continue
        d = period * 0.3
        index = 0
        while d + chunk <= line.length:
            a = line.interpolate(d)
            b = line.interpolate(d + chunk)
            d += period
            if near.intersection(geom.line([(a.x, a.y), (b.x, b.y)])).length < chunk * 0.5:
                continue                     # only the arena's own approaches get a canopy
            angle = math.degrees(math.atan2(b.y - a.y, b.x - a.x))
            slab = geom.rect(((a.x + b.x) / 2, (a.y + b.y) / 2),
                             (chunk, street["width"] + 8.0), angle)
            # a canopy must never roof over a vista: the camera looks along this slot
            if any(cap < 36.0 and slab.intersects(area) for area, cap in slots):
                continue
            over_arena = any(slab.intersects(p) for p in inside)
            z = CANOPY_Z_ARENA if over_arena else CANOPY_Z
            index += 1
            out.append({"id": f"canopy_{street['id']}_{index}", "kind": "platform",
                        "z": z, "thickness": 4.0, "parapet": 4.0,
                        "under_clear": z - 4.0, "canopy": True,
                        "over_arena": over_arena,
                        "column_spacing": ARENA_CANOPY_COLUMNS,
                        "polygon": geom.rect_points(((a.x + b.x) / 2, (a.y + b.y) / 2),
                                                    (chunk, street["width"] + 8.0), angle)})
    return out


def height_caps(parts: dict, with_id: bool = False) -> list:
    """(footprint, highest top allowed under it[, corridor id]) for every corridor that
    flies over. The id lets a stage drop the cap for the corridor a tower now straddles."""
    caps: list = []
    for item in parts["viaducts"] + parts["rails"]:
        band = geom.line(item["points"]).buffer(item["width"] / 2 + 4.0)
        caps.append((band, item["z"] - 4.0, item["id"]) if with_id
                    else (band, item["z"] - 4.0))
    return caps


def navigable_core(parts: dict) -> Polygon:
    """The navigable core of every corridor: a deck column may stand in a wide corridor's
    outer 24 m (a median pier) but never in the part traffic actually uses."""
    shapes = []
    for group in ("streets", "viaducts", "rails", "tunnels"):
        for item in parts[group]:
            half = max(item["width"] / 2 - C.UNDER_DECK_CLEAR, 0.0)
            if half > 0:
                shapes.append(geom.line(item["points"]).buffer(half))
    return unary_union(shapes) if shapes else Polygon()
