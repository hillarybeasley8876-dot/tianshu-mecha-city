"""Where a cover piece may stand (lead, r7).

Two rules the arena stage never had:

* **No two pieces on the same surface may touch.** `_place_near` only ever asked "is this spot
  legal?" and never "is something already here?", so every pass that found a grid point blocked
  by a keep-clear sphere landed its replacement on the same nearest legal spot: 286 of 1,070
  pieces stood on 82 shared centres, 3,404 overlapping pairs, and two vista cameras ended up
  inside the pile. A piece now has to clear every piece already on its surface by MIN_GAP.
* **Nothing may stand inside a z-banded keep-out.** The flat plan masks (connector spheres,
  socket floors, hive open ground) apply at every z; the vista cameras (r7) are a 30 m sphere,
  so they only bite in their own height band.

`KeepOut` is the union of both kinds; `Field` is one arena's live cover list plus that keep-out,
and is what every placing function asks. `audit` re-derives the numbers from the written JSON.
"""
from __future__ import annotations

import math

from shapely.geometry import Polygon, box as sbox

MIN_GAP = 6.0     # m: two pieces on one surface are at least this far apart (lead, r7)
BAND = 1.0        # m: two pieces count as "the same surface" within this z difference


def rect_gap(a: tuple[float, float, float, float],
             b: tuple[float, float, float, float]) -> float:
    """Distance between two axis-aligned rects given as (cx, cy, w, d); 0 when they overlap."""
    dx = max(abs(a[0] - b[0]) - (a[2] + b[2]) / 2, 0.0)
    dy = max(abs(a[1] - b[1]) - (a[3] + b[3]) / 2, 0.0)
    return math.hypot(dx, dy)


class KeepOut:
    """Plan masks no solid may stand in, plus the z-banded spheres (the vista cameras)."""

    def __init__(self, plan: Polygon | None = None,
                 zones: list[tuple[Polygon, float, float, str]] = ()) -> None:
        self.plan = plan if plan is not None else Polygon()
        self.zones = list(zones)

    @property
    def is_empty(self) -> bool:
        return self.plan.is_empty and not self.zones

    def union(self, other: "KeepOut | Polygon") -> "KeepOut":
        if isinstance(other, KeepOut):
            return KeepOut(self.plan.union(other.plan), self.zones + other.zones)
        return KeepOut(self.plan.union(other), self.zones)

    def hits(self, area: Polygon, z0: float, z1: float) -> list[str]:
        """Ids of the keep-outs this solid stands in (empty when it is clear)."""
        out: list[str] = []
        if not self.plan.is_empty and area.intersects(self.plan):
            out.append("plan")
        for poly, low, high, ident in self.zones:
            if high <= z0 + 0.5 or low >= z1 - 0.5:
                continue
            if area.intersects(poly):
                out.append(ident)
        return out


class Field:
    """One arena's cover list plus the rules a new piece has to respect.

    `pieces` is the arena's own live list, so a piece dropped by a later stage (a firing lane,
    a carrier tower) is gone from the field too. The z buckets are rebuilt whenever the list
    changes length, which is the only way a piece leaves it.
    """

    def __init__(self, pieces: list[dict], keep: KeepOut | None = None) -> None:
        self.pieces = pieces
        self.keep = keep if keep is not None else KeepOut()
        self._n = -1
        self._rows: dict[int, list[dict]] = {}

    def free(self, x: float, y: float, z: float, size: tuple[float, float, float]) -> bool:
        """May a piece of this size stand here, on the surface at `z`?"""
        if self.keep.hits(sbox(x - size[0] / 2, y - size[1] / 2,
                               x + size[0] / 2, y + size[1] / 2), z, z + size[2]):
            return False
        mine = (x, y, size[0], size[1])
        return all(rect_gap(mine, (p["center"][0], p["center"][1],
                                   p["size"][0], p["size"][1])) >= MIN_GAP
                   for p in self._at(z))

    def add(self, piece: dict) -> dict:
        self.pieces.append(piece)
        return piece

    def _at(self, z: float) -> list[dict]:
        if self._n != len(self.pieces):
            self._rows = {}
            for piece in self.pieces:
                self._rows.setdefault(round(piece["center"][2]), []).append(piece)
            self._n = len(self.pieces)
        out: list[dict] = []
        for key, rows in self._rows.items():
            if abs(key - z) <= BAND:
                out.extend(rows)
        return out


def audit(layout: dict) -> dict:
    """The r7 numbers, re-derived from the written layout: pieces, distinct centres, pairs."""
    out: dict = {"pieces": 0, "centres": set(), "pairs": [], "per_arena": {}}
    for arena in layout["arenas"]:
        rows: list[tuple[tuple, dict]] = []
        seen: set[tuple] = set()
        for piece in arena["cover"]:
            c = piece["center"]
            key = (round(c[0], 1), round(c[1], 1), round(c[2], 1))
            out["pieces"] += 1
            out["centres"].add((arena["id"],) + key)
            seen.add(key)
            rows.append((key, piece))
        pairs = 0
        for i, (ka, a) in enumerate(rows):
            ra = (ka[0], ka[1], a["size"][0], a["size"][1])
            for kb, b in rows[i + 1:]:
                if abs(ka[2] - kb[2]) > BAND:
                    continue
                if rect_gap(ra, (kb[0], kb[1], b["size"][0], b["size"][1])) < MIN_GAP:
                    pairs += 1
                    if len(out["pairs"]) < 12:
                        out["pairs"].append(f"{arena['id']} {ka} / {kb}")
        out["per_arena"][arena["id"]] = {"pieces": len(rows), "centres": len(seen),
                                         "pairs": pairs}
    out["centres"] = len(out["centres"])
    return out
