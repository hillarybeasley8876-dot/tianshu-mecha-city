"""Connector keep-clear: a 12 m sphere at every connector `from`/`to` (lead, r4 point 1).

city-build's C12 starts its capsule sweep 1 m over the take-off surface, so anything built
inside the first metres of a connector's arc reads as "the endpoint is inside geometry":
35 of 48 endpoints were, mostly arena cover pieces and the Ring Viaduct's first pier.

The rule is a reservation, not a repair: the discs come from the graph's node positions
*before* the corridors, arenas and props are generated, and every stage that places a solid
takes them as a keep-out. Connectors that share a node are exempt from each other - a node is
a junction, and its own ramps are supposed to meet there.
"""
from __future__ import annotations

import math

from shapely.geometry import Point, Polygon
from shapely.ops import unary_union
from shapely.strtree import STRtree

KEEP_CLEAR = 12.0        # MAP §5 L2 (r4): the radius of the keep-clear sphere
CAPSULE_H = 18.0         # the height band the sphere covers above the endpoint
PIER_R = 9.0             # a viaduct pier's plan radius, for the same test


def discs(connectors: list[dict], radius: float = KEEP_CLEAR) -> list[tuple[str, str, Polygon]]:
    """[(connector id, end, plan disc, z)] - one per connector endpoint."""
    out: list[tuple[str, str, Polygon, float]] = []
    for con in connectors:
        for end in ("from", "to"):
            p = con[end]
            out.append((con["id"], end,
                        Point(p[0], p[1]).buffer(radius, quad_segs=16), float(p[2])))
    return out


def keep_out(connectors: list[dict], radius: float = KEEP_CLEAR) -> Polygon:
    """Every endpoint disc as one polygon, for the stages that only need the shape."""
    parts = [d for _, _, d, _ in discs(connectors, radius)]
    return unary_union(parts) if parts else Polygon()


def pier_ok(connectors: list[dict], x: float, y: float) -> bool:
    """May a viaduct pier stand here? Not inside an endpoint's keep-clear sphere."""
    reach = KEEP_CLEAR + PIER_R
    return not any(math.dist((x, y), (c[end][0], c[end][1])) < reach
                   for c in connectors for end in ("from", "to"))


def index(connectors: list[dict], radius: float = KEEP_CLEAR) -> tuple[STRtree, list]:
    """(STRtree, discs) so the placing and checking stages test a footprint in one query."""
    rows = discs(connectors, radius)
    return STRtree([r[2] for r in rows]), rows


def blocked(tree: STRtree, rows: list, area: Polygon, z0: float, z1: float,
            skip: set[str] | None = None) -> list[str]:
    """The endpoints whose sphere this solid stands in ("connector id:end").

    A solid only counts when it really shares the endpoint's height band: the deck an
    endpoint stands *on* is its floor, not an obstruction.
    """
    out: list[str] = []
    for idx in tree.query(area):
        ident, end, disc, z = rows[idx]
        if skip and ident in skip:
            continue
        if z + CAPSULE_H <= z0 + 0.5 or z >= z1 - 0.5:
            continue
        if disc.intersects(area):
            out.append(f"{ident}:{end}")
    return out
