"""Pure geometry helpers for the city-layout generator (metres, Blender axes).

Everything here is deterministic: randomness only enters through an explicit
`random.Random` the caller owns, so the same seed always rebuilds the same city.
"""
from __future__ import annotations

import math
import random

from shapely import affinity
from shapely.ops import nearest_points
from shapely.geometry import LineString, Point, Polygon, box as sbox


def poly(points: list[list[float]]) -> Polygon:
    return Polygon([(p[0], p[1]) for p in points])


def line(points: list[list[float]]) -> LineString:
    return LineString([(p[0], p[1]) for p in points])


def rect(center: tuple[float, float], size: tuple[float, float], rot_deg: float = 0.0) -> Polygon:
    """Axis-aligned rectangle rotated about its centre."""
    w, d = size
    r = sbox(center[0] - w / 2, center[1] - d / 2, center[0] + w / 2, center[1] + d / 2)
    return affinity.rotate(r, rot_deg, origin=center) if rot_deg else r


def rect_points(center: tuple[float, float], size: tuple[float, float],
                rot_deg: float = 0.0) -> list[list[float]]:
    return [[round(x, 2), round(y, 2)] for x, y in rect(center, size, rot_deg).exterior.coords[:-1]]


def snap(value: float, module: float) -> float:
    """Snap to the facade module (4 m) so every building height reads as whole storeys."""
    return round(value / module) * module


def dogleg(a: tuple[float, float], b: tuple[float, float], max_straight: float,
           rng: random.Random) -> list[list[float]]:
    """A polyline a->b with a jog inserted so no straight run exceeds `max_straight`.

    Breaks lane sniping (dossier §3.2 "straight street segment <= 300 m"); the endpoints
    are untouched, so graph nodes stay on the corridor.
    """
    length = math.dist(a, b)
    if length <= max_straight:
        return [[a[0], a[1]], [b[0], b[1]]]
    legs = math.ceil(length / max_straight)
    out = [[a[0], a[1]]]
    dx, dy = (b[0] - a[0]) / length, (b[1] - a[1]) / length
    for i in range(1, legs):
        f = i / legs
        jog = (0.06 + 0.05 * rng.random()) * length / legs * (1 if i % 2 else -1)
        out.append([round(a[0] + dx * length * f - dy * jog, 1),
                    round(a[1] + dy * length * f + dx * jog, 1)])
    out.append([b[0], b[1]])
    return out


def sample_along(points: list[list[float]], spacing: float,
                 start: float = 0.0) -> list[tuple[float, float]]:
    """Points every `spacing` metres along a polyline (first one `start` metres in)."""
    ls = line(points)
    out, d = [], start
    while d <= ls.length:
        p = ls.interpolate(d)
        out.append((round(p.x, 1), round(p.y, 1)))
        d += spacing
    return out


def length_of(points: list[list[float]]) -> float:
    return round(line(points).length, 1)


def poisson_points(polygon: Polygon, radius: float, rng: random.Random,
                   tries: int | None = None) -> list[tuple[float, float]]:
    """Bridson-style Poisson-disc sample inside a polygon (cover / building site placement).

    Rejection sampling with a spatial hash; the try budget scales with the area so big
    districts fill as densely as small ones.
    """
    minx, miny, maxx, maxy = polygon.bounds
    if tries is None:
        tries = max(900, int(polygon.area / max(radius * radius, 1.0) * 8))
    cell = radius / math.sqrt(2)
    grid: dict[tuple[int, int], tuple[float, float]] = {}
    pts: list[tuple[float, float]] = []
    for _ in range(tries):
        p = (rng.uniform(minx, maxx), rng.uniform(miny, maxy))
        if not polygon.contains(Point(p)):
            continue
        key = (int(p[0] / cell), int(p[1] / cell))
        if any(math.dist(p, q) < radius
               for gx in range(key[0] - 2, key[0] + 3)
               for gy in range(key[1] - 2, key[1] + 3)
               for q in [grid.get((gx, gy))] if q):
            continue
        grid[key] = p
        pts.append((round(p[0], 1), round(p[1], 1)))
    return pts


def inward_normals(polygon: Polygon, count: int) -> list[tuple[tuple[float, float], float, float]]:
    """`count` perimeter points with inward normals: (point, normal_x, normal_y)."""
    ring = polygon.exterior
    out = []
    for i in range(count):
        t = (i + 0.5) / count
        p = ring.interpolate(t, normalized=True)
        ahead = ring.interpolate((t + 0.001) % 1.0, normalized=True)
        tx, ty = ahead.x - p.x, ahead.y - p.y
        norm = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / norm, tx / norm
        if not polygon.contains(Point(p.x + nx * 2, p.y + ny * 2)):
            nx, ny = -nx, -ny
        out.append(((round(p.x, 1), round(p.y, 1)), round(nx, 3), round(ny, 3)))
    return out


def shape_by_streets(outline: list[list[float]], mask, corridors: list[dict] | None = None,
                     reach: float = 40.0) -> list[list[float]]:
    """Snap the arena's four edges onto the streets that run beside it.

    The arena keeps the size the dossier gives it (dossier §4.5) but stops being a polygon
    floating in a field: each edge moves out to the kerb of the nearest parallel corridor, so
    the outline is "the block between these streets" and the streets themselves are the
    entries (lead note, round 2, point 4).
    """
    if not corridors:
        return outline
    raw = poly(outline)
    rect = raw.minimum_rotated_rectangle
    corners = list(rect.exterior.coords)[:-1]
    if len(corners) != 4:
        return outline
    centre = rect.centroid
    edges = []
    for i in range(4):
        a, b = corners[i], corners[(i + 1) % 4]
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        direction = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0])) % 180.0
        outward = (mid[0] - centre.x, mid[1] - centre.y)
        norm = math.hypot(*outward) or 1.0
        outward = (outward[0] / norm, outward[1] / norm)
        best = None
        for item in corridors:
            kerb = line(item["points"])
            angle = _line_angle(kerb)
            if min(abs(angle - direction), 180.0 - abs(angle - direction)) > 22.0:
                continue
            d = kerb.distance(Point(mid))
            if d > reach:
                continue
            near = nearest_points(Point(mid), kerb)[1]
            if (near.x - mid[0]) * outward[0] + (near.y - mid[1]) * outward[1] <= 0:
                continue                      # that street is behind this edge
            offset = d + item["width"] / 2
            if best is None or offset < best:
                best = offset
        edges.append((a, b, outward, best))
    moved = []
    for a, b, outward, offset in edges:
        push = 0.0 if offset is None else offset
        moved.append(((a[0] + outward[0] * push, a[1] + outward[1] * push),
                      (b[0] + outward[0] * push, b[1] + outward[1] * push)))
    polygon = _from_edges(moved)
    if polygon is None or polygon.area < raw.area * 0.6:
        return outline
    return [[round(x, 1), round(y, 1)] for x, y in polygon.exterior.coords[:-1]]


def _line_angle(line) -> float:
    coords = list(line.coords)
    a, b = coords[0], coords[-1]
    return math.degrees(math.atan2(b[1] - a[1], b[0] - a[0])) % 180.0


def _from_edges(edges: list[tuple[tuple, tuple]]) -> Polygon | None:
    """Intersect the four (possibly moved) edge lines back into a quad."""
    pts = []
    for i in range(4):
        (a1, a2), (b1, b2) = edges[i - 1], edges[i]
        hit = _intersect(a1, a2, b1, b2)
        if hit is None:
            return None
        pts.append(hit)
    poly = Polygon(pts)
    return poly if poly.is_valid and poly.area > 0 else None


def _intersect(p1, p2, p3, p4):
    x1, y1 = p1
    x2, y2 = p2
    x3, y3 = p3
    x4, y4 = p4
    den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
    if abs(den) < 1e-9:
        return None
    t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
    return (x1 + t * (x2 - x1), y1 + t * (y2 - y1))
