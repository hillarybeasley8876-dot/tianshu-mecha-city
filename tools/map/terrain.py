"""Terrain stage: escarpment seam, plateau, canal and harbor docks (docs/MAP.md §3).

The two Lynch edges of the map: a 32 m escarpment at Y ~ +150 that separates the Lower
City from the Upper City plateau, and the canal that closes the south. The crest is a
*seam*, not a wall: it is free-climbable only at the declared lips.
"""
from __future__ import annotations

from shapely.geometry import LineString, Polygon

CREST_Y = 150.0
CREST_H = 32.0
CANAL_WATER_Z = -16.0
CANAL_BANK_Z = 0.0
DOCK_Z = -12.0
PLATEAU_Z = 32.0


def crest_points() -> list[list[float]]:
    """Meandering crest of the escarpment, west to east, one point every 50 m."""
    pts = []
    x = -700.0
    while x <= 700.0:
        y = CREST_Y + 34.0 * _wave(x / 260.0) + 12.0 * _wave(x / 95.0 + 1.7)
        pts.append([round(x, 1), round(y, 1)])
        x += 50.0
    return pts


def _wave(t: float) -> float:
    import math
    return math.sin(t * math.pi)


def plateau_polygon(crest: list[list[float]]) -> Polygon:
    ring = [(p[0], p[1]) for p in crest] + [(700.0, 700.0), (-700.0, 700.0)]
    return Polygon(ring)


def crest_line(crest: list[list[float]]) -> LineString:
    return LineString([(p[0], p[1]) for p in crest])


def canal_polygon() -> Polygon:
    """The southern canal: a 60-120 m wide water body with a basin at the insertion pier."""
    north = [(-700.0, -540.0), (-620.0, -560.0), (-560.0, -646.0), (-480.0, -600.0),
             (-330.0, -580.0), (-150.0, -566.0), (40.0, -556.0), (240.0, -582.0),
             (420.0, -566.0), (560.0, -548.0), (700.0, -556.0)]
    ring = north + [(700.0, -700.0), (-700.0, -700.0)]
    return Polygon(ring)


def dock_polygon(canal: Polygon) -> list[list[float]]:
    """Quays cut into the canal's north bank in D1 (working level -12 m)."""
    bank = canal.intersection(
        Polygon([(-700.0, -620.0), (-250.0, -620.0), (-250.0, -470.0), (-700.0, -470.0)]))
    if bank.is_empty:
        return []
    quay = bank.buffer(46.0).intersection(
        Polygon([(-700.0, -640.0), (-250.0, -640.0), (-250.0, -462.0), (-700.0, -462.0)]))
    return [[round(x, 1), round(y, 1)] for x, y in quay.exterior.coords[:-1]]


def lips_for(edges_crossing: list[tuple[float, float]], width: float = 40.0) -> list[dict]:
    """Declared free-climb lips: one per crossing point handed in by the caller."""
    return [{"pos": [round(x, 1), round(y, 1)], "width": width} for x, y in edges_crossing]


def build(lip_points: list[tuple[float, float]]) -> dict:
    crest = crest_points()
    canal = canal_polygon()
    plateau = plateau_polygon(crest)
    return {
        "terrain": {
            "escarpment": {
                "crest": crest,
                "height": CREST_H,
                "lips": lips_for(lip_points),
            },
            "canal": {
                "polygon": [[round(x, 1), round(y, 1)] for x, y in canal.exterior.coords[:-1]],
                "water_z": CANAL_WATER_Z,
                "bank_z": CANAL_BANK_Z,
            },
            "plateau": {
                "polygon": [[round(x, 1), round(y, 1)]
                            for x, y in plateau.exterior.coords[:-1]],
                "z": PLATEAU_Z,
            },
            "docks": {"polygon": dock_polygon(canal), "z": DOCK_Z},
        }
    }
