"""2D helpers for the kit assignment (Blender map plane: X east, Y north, metres)."""
from __future__ import annotations

import math
from typing import Iterable, List, Optional, Sequence, Tuple

Pt = Tuple[float, float]


def dist(a: Pt, b: Pt) -> float:
    return math.hypot(b[0] - a[0], b[1] - a[1])


def seg_closest(p: Pt, a: Pt, b: Pt) -> Tuple[Pt, float]:
    """Closest point on segment ab to p, and the distance."""
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    if L2 < 1e-9:
        return a, dist(p, a)
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / L2))
    q = (ax + t * dx, ay + t * dy)
    return q, dist(p, q)


def polyline_closest(p: Pt, pts: Sequence[Pt]) -> Tuple[Pt, float, int]:
    """Closest point on a polyline: (point, distance, segment index)."""
    best: Tuple[Pt, float, int] = (pts[0], dist(p, pts[0]), 0)
    for i in range(len(pts) - 1):
        q, d = seg_closest(p, pts[i], pts[i + 1])
        if d < best[1]:
            best = (q, d, i)
    return best


def polyline_length(pts: Sequence[Pt]) -> float:
    return sum(dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))


def centroid(poly: Sequence[Pt]) -> Pt:
    return (sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly))


def point_in_poly(p: Pt, poly: Sequence[Pt]) -> bool:
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > p[1]) != (y2 > p[1]):
            xin = x1 + (p[1] - y1) * (x2 - x1) / (y2 - y1)
            if p[0] < xin:
                inside = not inside
    return inside


def dist_to_poly(p: Pt, poly: Sequence[Pt]) -> float:
    """0 inside, else the distance to the outline."""
    if point_in_poly(p, poly):
        return 0.0
    return min(polyline_closest(p, list(poly) + [poly[0]])[1], 1e9)


def resample(pts: Sequence[Pt], step: float) -> List[Tuple[Pt, float]]:
    """Walk a polyline in `step` chunks: [(midpoint, chunk length)] — for railings and kerbs."""
    out: List[Tuple[Pt, float]] = []
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        L = dist(a, b)
        if L < 1e-6:
            continue
        n = max(1, int(round(L / step)))
        seg = L / n
        for k in range(n):
            t = (k + 0.5) / n
            out.append((((a[0] + (b[0] - a[0]) * t), (a[1] + (b[1] - a[1]) * t)), seg))
    return out


def yaw_along(a: Pt, b: Pt) -> float:
    """Yaw in degrees so a model's long axis (+Y in model space) runs from a to b."""
    return math.degrees(math.atan2(b[0] - a[0], b[1] - a[1]))


def yaw_towards(p: Pt, target: Pt) -> float:
    """Yaw so a model's front (+Y in model space) faces `target` from `p`."""
    return math.degrees(math.atan2(target[0] - p[0], target[1] - p[1]))


def footprint_at_yaw(size: Sequence[float], yaw: float) -> Tuple[float, float]:
    """Model footprint (x, y) after a yaw snapped to 0/90/180/270."""
    q = int(round(yaw / 90.0)) % 2
    return (size[1], size[0]) if q else (size[0], size[1])


def anisotropy(scale: Iterable[float]) -> float:
    s = [abs(v) for v in scale if abs(v) > 1e-9]
    return max(s) / min(s) if s else 1.0


class Grid:
    """Uniform spatial hash for the neighbour-repeat rule."""

    def __init__(self, cell: float = 96.0) -> None:
        self.cell = cell
        self.buckets: dict = {}

    def key(self, p: Pt) -> Tuple[int, int]:
        return (int(p[0] // self.cell), int(p[1] // self.cell))

    def add(self, p: Pt, value) -> None:
        self.buckets.setdefault(self.key(p), []).append((p, value))

    def near(self, p: Pt, radius: float) -> List:
        r = int(math.ceil(radius / self.cell))
        kx, ky = self.key(p)
        out = []
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                for q, v in self.buckets.get((kx + dx, ky + dy), ()):
                    if dist(p, q) <= radius:
                        out.append(v)
        return out


def nearest(p: Pt, items: Sequence[Tuple[Pt, object]]) -> Optional[Tuple[Pt, object, float]]:
    best: Optional[Tuple[Pt, object, float]] = None
    for q, v in items:
        d = dist(p, q)
        if best is None or d < best[2]:
            best = (q, v, d)
    return best
