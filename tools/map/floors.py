"""Every surface a cover piece may stand on, read from the FINISHED layout (lead, r9).

`arenas.surfaces()` answers the same question, but it answers it from the deck list as it stood
when the arena stage ran - before `corridors.perforate_decks` cut the decks into islands - and it
only ever asks whether a piece's CENTRE is inside. Both mistakes put a crate in mid-air:

* `perforate_decks` runs after `build_arenas`, so 8 of the 30 pieces the float audit found
  floating were standing on a deck island that the perforation took away afterwards;
* a 30 x 34 m piece whose centre is 1 m inside a 24 m wide skybridge overhangs by 15 m, and the
  audit drops five points per instance, so it reads as floating even though its centre is legal.

This module is the floor set as the RENDER has it, and it asks the whole footprint. The terrain
comes from `kit/terrain.py`: a crust at 0 with the plateau, the canal, the dock trench and every
sunken plaza cut out of it, a plateau slab at its own z and a dock floor at -12. Decks are their
polygon minus their holes.
"""
from __future__ import annotations

import math

from shapely.geometry import LineString, Polygon, box as sbox
from shapely.ops import unary_union

TOL = 0.5           # m: two surfaces count as the same floor within this z difference
MARGIN = 0.25       # m: a footprint may overhang a floor edge by this much and still count
QUAY_LIP = 3.0      # m: the rendered quay wall top inside a canal / dock / plaza edge


def _poly(points: list) -> Polygon:
    return Polygon([(float(p[0]), float(p[1])) for p in points])


def cut_ground(cons: list[dict], terrain: dict, decks: list[dict],
               z_hi: float = 0.0, z_lo: float = -6.0) -> Polygon:
    """The plan area the ground crust is CUT OUT of (lead, r9).

    `blender/city/kit/terrain.py::ground_cuts` cuts the crust for the canal, the dock trench,
    every plaza that sinks below street level and the below-crust part of every descending ramp,
    stairs, lift, vent and vertical catapult. Anything that stands on one of them stands over a
    hole - a lot, or an arena cover piece. The canal, the dock trench and the plazas carry a quay
    wall whose TOP is at street level and which is centred on the polygon edge, so their outer
    `QUAY_LIP` metres IS rendered floor and only what is inside it is a hole. The connector
    trenches get no such margin: `_trench_polys` cuts `width + 8` and the ramp inside is `width`.
    """
    out: list[Polygon] = [_poly(terrain["canal"]["polygon"]).buffer(-QUAY_LIP),
                          _poly(terrain["docks"]["polygon"]).buffer(-QUAY_LIP)]
    for deck in decks:
        if deck["kind"] == "plaza" and float(deck["z"]) < z_hi - 1.0:
            out.append(_poly(deck["polygon"]).buffer(-QUAY_LIP))
    for con in cons:
        lo = min(float(con["from"][2]), float(con["to"][2]))
        hi = max(float(con["from"][2]), float(con["to"][2]))
        if not (lo < z_hi - 0.5 and hi > z_lo + 0.5):
            continue
        pad = con.get("params", {}).get("pad")
        if con["kind"] in ("lift", "vent", "vcat") and pad:
            # the column is built where `routes3d.place` put it, not necessarily on the node
            shaft = con.get("params", {}).get("shaft")
            px, py = (float(shaft[0]), float(shaft[1])) if shaft else \
                (float(con["from"][0]), float(con["from"][1]))
            hw, hd = float(pad[0]) * 0.5 + 2.0, float(pad[1]) * 0.5 + 2.0
            out.append(Polygon([(px - hw, py - hd), (px + hw, py - hd),
                                (px + hw, py + hd), (px - hw, py + hd)]))
        if con["kind"] in ("ramp", "stairs"):
            path = con.get("path") or [con["from"], con["to"]]
            segs = [(a, b) for a, b in zip(path, path[1:])
                    if min(float(a[2]), float(b[2])) < z_hi - 0.5]
            if not segs:
                continue
            pts = [segs[0][0]] + [b for _, b in segs]
            out.append(LineString([(float(p[0]), float(p[1])) for p in pts])
                       .buffer(float(con["width"]) * 0.5 + 8.0, join_style=2))
    return unary_union(out)


class Floors:
    """The walkable surfaces, bucketed by height. `at(z)` is the union of every floor there."""

    def __init__(self, terrain: dict, decks: list[dict], half: float,
                 cons: list[dict] | None = None) -> None:
        square = sbox(-half, -half, half, half)
        plateau = _poly(terrain["plateau"]["polygon"])
        canal = _poly(terrain["canal"]["polygon"])
        docks = _poly(terrain["docks"]["polygon"])
        # The crust is cut for the plateau, the canal, the dock trench and every plaza that
        # sinks below street level (kit/terrain.py::ground_cuts), and - when the caller passes
        # the connectors - for every descending ramp / stairs / lift trench as well.
        crust = square.difference(plateau).difference(canal).difference(docks)
        for deck in decks:
            if deck["kind"] == "plaza" and float(deck["z"]) < -1.0:
                crust = crust.difference(_poly(deck["polygon"]))
        if cons is not None:
            # The connector trenches. Leaving them out put 5 cover pieces over a ramp cut that
            # the render has and this model did not (lead, r9).
            crust = crust.difference(cut_ground(cons, terrain, decks))
        self._by_z: dict[float, Polygon] = {
            0.0: crust,
            float(terrain["plateau"]["z"]): plateau,
            float(terrain["docks"]["z"]): docks,
        }
        for deck in decks:
            piece = _poly(deck["polygon"])
            for hole in deck.get("holes", []):
                piece = piece.difference(_poly(hole))
            if piece.is_empty:
                continue
            z = float(deck["z"])
            self._by_z[z] = self._by_z[z].union(piece) if z in self._by_z else piece
        self._cache: dict[float, Polygon] = {}

    def at(self, z: float) -> Polygon:
        """Every floor within TOL of `z`, as one polygon (empty when there is none)."""
        key = round(z, 1)
        if key not in self._cache:
            self._cache[key] = unary_union([p for zz, p in self._by_z.items()
                                            if abs(zz - z) <= TOL and not p.is_empty])
        return self._cache[key]

    def heights(self) -> list[float]:
        """Every height that carries a floor, ascending."""
        return sorted(z for z, p in self._by_z.items() if not p.is_empty)

    def below(self, z: float, drop: float) -> list[float]:
        """The floor heights under `z`, nearest first, no further than `drop` below it."""
        return sorted((h for h in self.heights() if h < z - TOL and h >= z - drop),
                      key=lambda h: z - h)

    def holds(self, z: float, x: float, y: float, w: float, d: float) -> bool:
        """Does the whole w x d footprint at (x, y) stand on a floor at height `z`?"""
        floor = self.at(z)
        if floor.is_empty:
            return False
        return floor.buffer(MARGIN).contains(sbox(x - w / 2, y - d / 2, x + w / 2, y + d / 2))

    def spot(self, z: float, x: float, y: float, w: float, d: float,
             reaches: tuple[float, ...], free=None) -> tuple[float, float] | None:
        """The nearest point to (x, y) where this footprint fits on the floor at `z`.

        Deterministic and rng-free, so it is idempotent: a piece that already stands on a floor
        is returned where it is, and a second call over an unchanged layout moves nothing.
        `free(px, py)` is the caller's own legality test (the cover field's keep-outs and the
        minimum gap between pieces).
        """
        for reach in reaches:
            n = 1 if reach <= 0.0 else 16
            for i in range(n):
                a = 6.283185307179586 * i / n
                px = x + reach * math.cos(a)
                py = y + reach * math.sin(a)
                if not self.holds(z, px, py, w, d):
                    continue
                if free is not None and not free(px, py):
                    continue
                return round(px, 1), round(py, 1)
        return None
