"""Every wall on a model, grouped so the repaint and the window mask cover the whole facade.

`planar.facade_faces()` answers "which faces lie on one of the model's dominant PLANES", which is the
right question for the flattening pass and the wrong one for the texture pass: a candidate plane is
rejected whole when its least-squares fit is worse than `FIT_M` (0.07 m RMS) or one vertex sits more
than `MAX_DEV` (0.25 m) off it, and a Tripo wall almost never clears that. Measured on the r5 exports,
`facade_faces` reached 1.5-31 % of each atlas (t06 8.7 %, m04 5.4 %, f03 1.5 %), so 70-98 % of every
facade kept the Tripo albedo's own blotches — lead r6 MUST-FIX 3.

This module asks the looser question the texture pass actually needs: **is this face a wall, and which
way does it face?** Faces are bucketed by quantised normal AND quantised plane offset, so one bucket
is one wall with one well-defined along-wall axis for `panes.raster()`; nothing has to be planar, and
a balcony front, a fin side or a battered wall is a wall like any other.

`top_faces()` is the same idea for the near-horizontal surface (roofs, decks, soffits), which gets the
plain field rather than the storey grid.
"""
from __future__ import annotations

from typing import Dict, List, Tuple

import bpy

#: |n.z| at or below this is a wall (0.35 = 20.5 degrees off vertical), above `TOP_MIN` is a roof.
#: The gap between them is the cornice / chamfer band, which is left with the Tripo albedo.
VERT_MAX = 0.35
TOP_MIN = 0.80
#: Normal quantisation for the wall buckets. 4.0 is a 14 degree bucket: tight enough that one bucket
#: has one along-wall axis, loose enough that a battered or slightly curved wall stays in one piece.
QUANT = 4.0
#: Plane-offset quantisation, in metres, so two parallel walls 30 m apart are two buckets. Coarse on
#: purpose — a wrong merge only shares an along-wall axis, which both walls agree on anyway.
OFF_QUANT = 3.0
#: A bucket smaller than this many faces is a speck (a bolt, a cable clip); painting it costs a
#: rasteriser call per triangle and buys nothing.
MIN_FACES = 2


def _key(normal, centre) -> Tuple[int, int, int, int]:
    n = (int(round(normal.x * QUANT)), int(round(normal.y * QUANT)), int(round(normal.z * QUANT)))
    # The offset has to be measured along a STABLE axis or two faces of one curved wall land in
    # different buckets; the dominant horizontal component of the bucket normal is that axis.
    axis = 0 if abs(normal.x) >= abs(normal.y) else 1
    return n + (int(round((centre[axis] if axis == 0 else centre[1]) / OFF_QUANT)),)


def _buckets(obj: bpy.types.Object, want_wall: bool) -> Dict[Tuple[int, int, int, int], List[int]]:
    me = obj.data
    out: Dict[Tuple[int, int, int, int], List[int]] = {}
    for poly in me.polygons:
        nz = abs(poly.normal.z)
        if want_wall:
            if nz > VERT_MAX:
                continue
        elif nz < TOP_MIN:
            continue
        out.setdefault(_key(poly.normal, poly.center), []).append(poly.index)
    return out


def wall_faces(obj: bpy.types.Object, min_faces: int = MIN_FACES) -> List[List[int]]:
    """Groups of face indices, one per wall: every near-vertical face on the model, by orientation.

    Unlike `planar.facade_faces()` this never rejects a group, so the caller can repaint the whole
    vertical surface. `min_faces` drops single-face specks.
    """
    return [g for g in _buckets(obj, True).values() if len(g) >= min_faces]


def top_faces(obj: bpy.types.Object, min_faces: int = MIN_FACES) -> List[List[int]]:
    """Groups of face indices for the near-horizontal surface — roofs, decks, soffits.

    These get the plain world field (no storey grid): a roof is not a facade, but it is still a large
    pale Tripo surface that the dusk sun blows out if it keeps the atlas's own near-white value.
    """
    return [g for g in _buckets(obj, False).values() if len(g) >= min_faces]


def coverage(obj: bpy.types.Object) -> Dict[str, float]:
    """Area share of the mesh that is wall / top / neither — the number the repaint gate reports."""
    me = obj.data
    total = sum(p.area for p in me.polygons)
    if total <= 0.0:
        return {"wall_area_pct": 0.0, "top_area_pct": 0.0}
    wall = sum(p.area for p in me.polygons if abs(p.normal.z) <= VERT_MAX)
    top = sum(p.area for p in me.polygons if abs(p.normal.z) >= TOP_MIN)
    return {"wall_area_pct": round(100.0 * wall / total, 2),
            "top_area_pct": round(100.0 * top / total, 2)}
