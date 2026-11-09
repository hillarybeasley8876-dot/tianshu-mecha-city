"""The sky graph: waypoints and edges the Harriers and the boss's adds fly along (MAP §3, r3).

Lead r2, point 4. Flyers need a routing graph that is *clear*: a node stands at least 12 m
from every building, deck and rail box and an edge at least 8 m, so a Harrier that follows
the graph never clips a tower. The band is +60 to +250 m - above the street canyons, below
the no-fly ceiling - and the graph has to be one connected component, dense enough per
district (>= 24 nodes), reach every arena (>= 6 within 150 m of its centre) and ring the
Crown deck at +232..+250 (>= 8 nodes) where the Brood Titan's summons arrive.

Nodes are sampled on a plan grid at six heights; a column keeps the level that is clear and
closest to the L4 rooftop band, because that is where the player fights. Edges join
neighbours whose straight run is clear at 8 m. Anything left isolated is dropped rather than
shipped: an unreachable waypoint is worse than no waypoint.
"""
from __future__ import annotations

import math

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union
from shapely.strtree import STRtree

import geom
import mapconst as C
import zones as zone_stage

LEVELS = (80.0, 112.0, 144.0, 176.0, 208.0, 240.0)   # sampled heights, all inside +60..+250
GRID = 118.0                # plan spacing of the candidate columns
NODE_CLEAR = 12.0           # MAP §3: a node stands this far off every box
EDGE_CLEAR = 8.0            # MAP §3: an edge runs this far off every box
LINK_RANGE = 205.0          # 3D reach of one hop
TARGET_BAND = 144.0         # prefer the L4 rooftop band: that is where the fight is
CROWN_RING = (200.0, 12, 240.0)   # radius, count, height of the ring around the Crown
ARENA_REACH = 150.0         # MAP §3: >= 6 nodes within this of each arena centre
MIN_PER_DISTRICT = 24


def solids(layout: dict) -> list[tuple[Polygon, float, float]]:
    """Every box a flyer must stay clear of: buildings, deck slabs, rails and viaducts."""
    out: list[tuple[Polygon, float, float]] = []
    for b in layout["buildings"]:
        out.append((geom.rect(tuple(b["center"]), tuple(b["size"]), b.get("rot", 0.0)),
                    b["base_z"], b["base_z"] + b["height"]))
    for deck in layout["decks"]:
        area = geom.poly(deck["polygon"])
        for hole in deck.get("holes", []):
            area = area.difference(geom.poly(hole))
        out.append((area, deck["z"] - deck["thickness"], deck["z"]))
        core = deck.get("core")
        if core:
            centre = area.centroid
            out.append((Point(centre.x, centre.y).buffer(core["r"], quad_segs=16),
                        core["z"], core["z"] + core["height"]))
    for group, clear in (("rails", 12.0), ("viaducts", 24.0)):
        for item in layout[group]:
            out.append((geom.line(item["points"]).buffer(item["width"] / 2),
                        item["z"], item["z"] + clear))
    return out


class Airspace:
    """The no-fly volumes, indexed once and queried with a clearance margin."""

    def __init__(self, boxes: list[tuple[Polygon, float, float]]) -> None:
        self.boxes = boxes
        self.node = STRtree([p.buffer(NODE_CLEAR) for p, _z0, _z1 in boxes])
        self.edge = STRtree([p.buffer(EDGE_CLEAR) for p, _z0, _z1 in boxes])

    def _hits(self, tree: STRtree, shape, z: float, pad: float) -> bool:
        for idx in tree.query(shape):
            _poly, z0, z1 = self.boxes[idx]
            if z0 - pad <= z <= z1 + pad:
                return True
        return False

    def node_clear(self, x: float, y: float, z: float) -> bool:
        return not self._hits(self.node, Point(x, y), z, NODE_CLEAR)

    def edge_clear(self, a: tuple[float, float, float], b: tuple[float, float, float]) -> bool:
        ray = LineString([(a[0], a[1]), (b[0], b[1])])
        for idx in self.edge.query(ray):
            poly, z0, z1 = self.boxes[idx]
            cut = poly.intersection(ray)
            if cut.is_empty:
                continue
            for part in getattr(cut, "geoms", [cut]):
                coords = list(getattr(part, "coords", [])) or [(part.x, part.y)]
                for px, py in coords:
                    t = 0.0 if ray.length == 0 else ray.project(Point(px, py)) / ray.length
                    z = a[2] + (b[2] - a[2]) * t
                    if z0 - EDGE_CLEAR <= z <= z1 + EDGE_CLEAR:
                        return False
        return True


def build(layout: dict, rules: dict) -> tuple[list[dict], list[list[str]], dict]:
    """The waypoints and the edges, both already reduced to one connected component."""
    air = Airspace(solids(layout))
    half = C.HALF - 40.0
    nodes: list[dict] = []
    for gx in _grid(-half, half, GRID):
        for gy in _grid(-half, half, GRID):
            zone = _zone_at(rules, gx, gy)
            if zone is None:
                continue
            level = _best_level(air, gx, gy)
            if level is None:
                continue
            nodes.append({"id": f"sky_{len(nodes) + 1:04d}", "pos": [round(gx, 1),
                                                                     round(gy, 1), level],
                          "district": zone})
    nodes += _crown_ring(air, len(nodes))
    nodes += _arena_nodes(layout, air, rules, len(nodes))
    nodes += _densify(nodes, air, rules)
    edges = _edges(nodes, air)
    nodes, edges = _connected(nodes, edges)
    return nodes, edges, _stats(layout, nodes, edges)


def _densify(nodes: list[dict], air: Airspace, rules: dict) -> list[dict]:
    """A district the first grid left thin gets a second, offset pass over its own ground.

    MAP §3 asks for >= 24 nodes per district; the plateau districts (D3 Old Town, D7
    Financial) lose columns to their own towers and decks, so the coarse grid alone leaves
    them short.
    """
    counts: dict[str, int] = {}
    for n in nodes:
        counts[n["district"]] = counts.get(n["district"], 0) + 1
    out: list[dict] = []
    for zone in zone_stage.zones(rules):
        did = zone["district"]
        if counts.get(did, 0) >= MIN_PER_DISTRICT:
            continue
        fp = zone["footprint"]
        step = GRID * 0.62
        for gx in _grid(fp[0] + step / 2, fp[2], step):
            for gy in _grid(fp[1] + step / 2, fp[3], step):
                if counts.get(did, 0) + len([n for n in out if n["district"] == did]) \
                        >= MIN_PER_DISTRICT:
                    break
                if any(math.dist((gx, gy), n["pos"][:2]) < step * 0.7 for n in nodes):
                    continue
                level = _best_level(air, gx, gy)
                if level is None:
                    continue
                out.append({"id": f"sky_x{len(out) + 1:04d}",
                            "pos": [round(gx, 1), round(gy, 1), level], "district": did})
    return out


def _grid(low: float, high: float, step: float) -> list[float]:
    out, v = [], low
    while v <= high:
        out.append(round(v, 1))
        v += step
    return out


def _zone_at(rules: dict, x: float, y: float) -> str | None:
    for zone in zone_stage.zones(rules):
        fp = zone["footprint"]
        if fp[0] <= x <= fp[2] and fp[1] <= y <= fp[3]:
            return zone["district"]
    return None


def _best_level(air: Airspace, x: float, y: float) -> float | None:
    """The clear height in this column closest to the L4 band, or None if the column is shut."""
    clear = [z for z in LEVELS if air.node_clear(x, y, z)]
    if not clear:
        return None
    return min(clear, key=lambda z: (abs(z - TARGET_BAND), z))


def _crown_ring(air: Airspace, start: int) -> list[dict]:
    """The Harriers the Brood Titan summons arrive on a ring around the Crown deck."""
    radius, count, z = CROWN_RING
    out: list[dict] = []
    for i in range(count):
        theta = 2.0 * math.pi * i / count
        x, y = radius * math.cos(theta), 120.0 + radius * math.sin(theta)
        if not air.node_clear(x, y, z):
            continue
        out.append({"id": f"sky_{start + len(out) + 1:04d}",
                    "pos": [round(x, 1), round(y, 1), z], "district": "D4",
                    "ring": "crown"})
    return out


def _arena_nodes(layout: dict, air: Airspace, rules: dict, start: int) -> list[dict]:
    """Extra nodes over each arena, so a flyer can always reach the fight."""
    out: list[dict] = []
    for arena in layout["arenas"]:
        area = geom.poly(arena["polygon"])
        centre = area.centroid
        top = max(arena["tiers"])
        for radius in (0.0, 90.0, 140.0):
            for i in range(6 if radius else 1):
                theta = 2.0 * math.pi * i / 6
                x = centre.x + radius * math.cos(theta)
                y = centre.y + radius * math.sin(theta)
                level = _best_level(air, x, y)
                if level is None or level < top + 24.0:
                    level = next((z for z in LEVELS if z >= top + 24.0
                                  and air.node_clear(x, y, z)), None)
                if level is None:
                    continue
                out.append({"id": f"sky_{start + len(out) + 1:04d}",
                            "pos": [round(x, 1), round(y, 1), level],
                            "district": _zone_at(rules, x, y) or "D4",
                            "arena": arena["id"]})
    return out


def _edges(nodes: list[dict], air: Airspace) -> list[list[str]]:
    out: list[list[str]] = []
    for i, a in enumerate(nodes):
        near = sorted((math.dist(a["pos"], b["pos"]), j) for j, b in enumerate(nodes)
                      if j != i and math.dist(a["pos"], b["pos"]) <= LINK_RANGE)
        for _d, j in near[:5]:
            b = nodes[j]
            if [b["id"], a["id"]] in out or [a["id"], b["id"]] in out:
                continue
            if air.edge_clear(tuple(a["pos"]), tuple(b["pos"])):
                out.append([a["id"], b["id"]])
    return out


def _connected(nodes: list[dict], edges: list[list[str]]) -> tuple[list[dict], list[list[str]]]:
    """Keep only the largest component: a waypoint no flyer can reach is not a waypoint."""
    index = {n["id"]: n for n in nodes}
    parent = {n["id"]: n["id"] for n in nodes}

    def find(a: str) -> str:
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for a, b in edges:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    groups: dict[str, list[str]] = {}
    for ident in parent:
        groups.setdefault(find(ident), []).append(ident)
    keep = set(max(groups.values(), key=len))
    kept = [n for n in nodes if n["id"] in keep]
    return kept, [e for e in edges if e[0] in keep and e[1] in keep]


def _stats(layout: dict, nodes: list[dict], edges: list[list[str]]) -> dict:
    per: dict[str, int] = {}
    for n in nodes:
        per[n["district"]] = per.get(n["district"], 0) + 1
    arenas = {}
    for arena in layout["arenas"]:
        c = geom.poly(arena["polygon"]).centroid
        arenas[arena["id"]] = len([n for n in nodes
                                   if math.dist(n["pos"][:2], (c.x, c.y)) <= ARENA_REACH])
    crown = len([n for n in nodes if n.get("ring") == "crown"])
    return {"nodes": len(nodes), "edges": len(edges), "per_district": per,
            "per_arena": arenas, "crown": crown}
