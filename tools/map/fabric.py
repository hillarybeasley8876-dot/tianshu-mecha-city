"""Block and lot geometry: how a district's land is cut into parcels.

Split out of lots.py, which keeps the building record and the inscribed-rectangle search.
Two fabrics live here: `subdivide` (a perimeter row of street-wall lots plus a courtyard
grid, for the ordinary city) and `terrace_row` (contiguous party-wall terraces broken by
stair-alleys, for the Old Town - lead r2, point 5).
"""
from __future__ import annotations

import math
import random

from shapely import affinity
from shapely.geometry import Point, Polygon, box as sbox
from shapely.ops import unary_union

import geom
import mapconst as C

GAP = 3.0             # party-wall gap between neighbouring buildings
SLENDERNESS = {"A": 2.5, "B": 4.0, "C": 6.0, "D": 6.0}   # height / narrow side
LOT_MIN_AREA = 320.0  # m2: below this a leftover is a yard, not a lot


def block_polygons(area: Polygon, mask: Polygon, reserved: Polygon, canal: Polygon,
                   min_area: float = 420.0) -> list[Polygon]:
    """The land between corridors, minus arenas, plazas, water and reserved space."""
    free = area.difference(mask).difference(reserved).difference(canal)
    parts = [g for g in getattr(free, "geoms", [free])
             if isinstance(g, Polygon) and g.area >= min_area]
    return sorted(parts, key=lambda p: -p.area)


def subdivide(block: Polygon, lot_w: float, lot_d: float, angle: float,
              rng: random.Random) -> list[tuple[Polygon, float]]:
    """Lots for one block: a perimeter row of street-wall lots, plus a courtyard grid.

    The perimeter row is what makes a city read: buildings stand shoulder to shoulder along
    the block's own outline, facing every street that touches it, whatever shape the block
    is. A courtyard only gets built when it is big enough to hold real lots.
    """
    rect = block.minimum_rotated_rectangle
    rc = list(rect.exterior.coords)[:-1]
    depth = min(math.dist(rc[0], rc[1]), math.dist(rc[1], rc[2]))
    # the row must fit inside the block: two rows back to back, or one row in a thin block
    # the row must fit inside the block: two rows back to back, or one full-depth row
    if depth >= 2.0 * lot_d + 8.0:
        row_d = lot_d
    else:
        row_d = max(14.0, (depth - 2.0 * GAP) / (2.0 if depth > 3.0 * lot_d else 1.0))
    lots, left = _perimeter_lots(block, lot_w, row_d)
    # whatever the perimeter rows did not take is courtyard. It is gridded one piece at a
    # time - the remainder of a deep block is a multipolygon and a grid laid over its
    # bounding box would miss nearly every cell - and the ragged edge the grid could not
    # tile is handed over as lots for the inscribed-rectangle search to square off.
    court = left
    for part in getattr(court, "geoms", [court]):
        if not isinstance(part, Polygon) or part.area < max(2.0 * lot_w * lot_d, 900.0):
            continue
        grid = _grid_lots(part, lot_w, lot_d, angle)
        lots += grid
        if grid:
            rest = part.difference(unary_union([g for g, _ in grid]).buffer(GAP / 2))
            lots += [(g, angle) for g in getattr(rest, "geoms", [rest])
                     if isinstance(g, Polygon) and g.area >= LOT_MIN_AREA]
    # the leftovers the grid never looked at (pieces under the grid threshold) are land too
    taken = unary_union([g for g, _ in lots]) if lots else Polygon()
    for g in getattr(left.difference(taken), "geoms", [left.difference(taken)]):
        if isinstance(g, Polygon) and g.area >= LOT_MIN_AREA:
            lots.append((g, angle))
    return lots


STAIR_EVERY = (60.0, 90.0)  # MAP §4 / lead r2 point 5: a stair-alley this often
STAIR_WIDTH = 24.0          # ...and at least this wide, so it is a walkable lane


STAIR_EVERY = (60.0, 90.0)  # MAP §4 / lead r2 point 5: a stair-alley this often
STAIR_WIDTH = 24.0          # ...and at least this wide, so it is a walkable lane


def terrace_row(block: Polygon, lot_w: float, lot_d: float, axis: float,
                rng: random.Random) -> list[tuple[Polygon, float]]:
    """The Old Town fabric: contiguous stepped terraces along every frontage.

    Lead r2, point 5. The perimeter-lot machinery leaves a party-wall gap between
    neighbours, which from the NW sun reads as rows of separate boxes on a hillside instead
    of one dense town. A terrace row has no gap at all - each house shares its walls with
    the next - and it is broken every 60-90 m by a stair-alley at least 24 m wide, which is
    the lane the player actually walks up. The blocks between the contour lanes are
    ribbons, so a house takes as much depth as the block still has at that point.
    """
    out: list[tuple[Polygon, float]] = []
    free = block
    for _ in range(3):
        placed = 0
        for part in [g for g in getattr(free, "geoms", [free]) if isinstance(g, Polygon)]:
            ring = part.exterior
            length = ring.length
            t = lot_w * 0.5
            since_stair = rng.uniform(*STAIR_EVERY)
            while t < length:
                here = ring.interpolate(t % length)
                ahead = ring.interpolate((t + lot_w * 0.4) % length)
                tx, ty = ahead.x - here.x, ahead.y - here.y
                norm = math.hypot(tx, ty)
                if norm < 1e-6:
                    t += lot_w
                    continue
                nx, ny = -ty / norm, tx / norm
                if not part.contains(Point(here.x + nx * 4.0, here.y + ny * 4.0)):
                    nx, ny = -nx, -ny
                if since_stair <= 0.0:
                    # the stair-alley: leave a full 24 m of frontage and start counting again
                    t += STAIR_WIDTH
                    since_stair = rng.uniform(*STAIR_EVERY)
                    continue
                lot_axis = math.degrees(math.atan2(ty, tx))
                depth = _local_depth(free, here, nx, ny, lot_d)
                if depth < 14.0:
                    t += lot_w
                    since_stair -= lot_w
                    continue
                centre = (here.x + nx * (depth / 2 + 1.0), here.y + ny * (depth / 2 + 1.0))
                # a frontage on a curve never holds a clean rectangle, so the house takes the
                # land the block really has at this station and `building_from_lot` squares
                # it off - the same clip-then-inscribe the kerb walls use
                patch = geom.rect(centre, (lot_w, depth), lot_axis).intersection(free)
                parts = [g for g in getattr(patch, "geoms", [patch]) if isinstance(g, Polygon)]
                box = max(parts, key=lambda g: g.area) if parts else None
                if box is None or box.area < LOT_MIN_AREA:
                    t += lot_w
                    since_stair -= lot_w
                    continue
                out.append((box, lot_axis))
                free = free.difference(box)      # party walls: no buffer, the next house abuts
                placed += 1
                t += lot_w
                since_stair -= lot_w
        if not placed:
            break
        free = free.buffer(0)
    # the yards the rows could not reach are land too: grid them on the district's grain and
    # hand the ragged edge to the inscribed-rectangle search, exactly as `subdivide` does
    for part in [g for g in getattr(free, "geoms", [free]) if isinstance(g, Polygon)]:
        if part.area < max(2.0 * lot_w * lot_d, 900.0):
            continue
        grid = _grid_lots(part, lot_w, lot_d, axis)
        out += grid
        if grid:
            rest = part.difference(unary_union([g for g, _ in grid]))
            out += [(g, axis) for g in getattr(rest, "geoms", [rest])
                    if isinstance(g, Polygon) and g.area >= LOT_MIN_AREA]
    taken = unary_union([g for g, _ in out]) if out else Polygon()
    for g in getattr(free.difference(taken), "geoms", [free.difference(taken)]):
        if isinstance(g, Polygon) and g.area >= LOT_MIN_AREA:
            out.append((g, axis))
    return out


def _perimeter_lots(block: Polygon, lot_w: float,
                    lot_d: float) -> tuple[list[tuple[Polygon, float]], Polygon]:
    """A row of lots around the block's outline, each square to the frontage it faces.

    The depth of each lot is probed from the frontage inward, so a ribbon between two
    viaducts gets shallow lots along its whole length instead of one box in its widest part.
    Lots are subtracted from the block as they are placed, so nothing overlaps.
    """
    out: list[tuple[Polygon, float]] = []
    free = block
    for _ in range(4):
        placed = 0
        for part in [g for g in getattr(free, "geoms", [free]) if isinstance(g, Polygon)]:
            ring = part.exterior
            length = ring.length
            t = lot_w * 0.5
            while t < length:
                here = ring.interpolate(t % length)
                ahead = ring.interpolate((t + lot_w * 0.4) % length)
                tx, ty = ahead.x - here.x, ahead.y - here.y
                norm = math.hypot(tx, ty)
                t += lot_w
                if norm < 1e-6:
                    continue
                nx, ny = -ty / norm, tx / norm
                if not part.contains(Point(here.x + nx * 4.0, here.y + ny * 4.0)):
                    nx, ny = -nx, -ny
                depth = _local_depth(free, here, nx, ny, lot_d)
                if depth < 14.0:
                    continue
                axis = math.degrees(math.atan2(ty, tx))
                # a curved or tapering frontage takes a smaller lot: try the biggest area
                # first, whichever way it has to give, so a megablock stays a megablock
                box = None
                for w_frac, d_frac in fit_order():
                    w, d = (lot_w - GAP) * w_frac, depth * d_frac
                    if w < 14.0 or d < 14.0:
                        continue
                    centre = (here.x + nx * (d / 2 + 1.0), here.y + ny * (d / 2 + 1.0))
                    trial = geom.rect(centre, (w, d), axis)
                    # test against the live remainder, not the pass's snapshot: two lots
                    # on the same block must never share ground
                    if free.contains(trial):
                        box = trial
                        break
                if box is None:
                    continue
                out.append((box, axis))
                free = free.difference(box.buffer(GAP / 2))
                placed += 1
        if not placed:
            break
        free = free.buffer(0)
    return out, (free if not free.is_empty else Polygon())


FRACS = (1.0, 0.84, 0.7, 0.56, 0.44, 0.34)


def fit_order() -> list[tuple[float, float]]:
    """(width, depth) scale pairs, biggest area first."""
    pairs = [(w, d) for w in FRACS for d in FRACS]
    return sorted(pairs, key=lambda p: -p[0] * p[1])


def _local_depth(part: Polygon, here: Point, nx: float, ny: float, limit: float) -> float:
    """How far the block reaches inward from this frontage point, capped at `limit`."""
    step = 4.0
    depth = 0.0
    while depth + step <= limit:
        probe = Point(here.x + nx * (depth + step + 1.0), here.y + ny * (depth + step + 1.0))
        if not part.contains(probe):
            break
        depth += step
    return depth


def _grid_lots(area: Polygon, lot_w: float, lot_d: float,
               angle: float) -> list[tuple[Polygon, float]]:
    """A plain grid of lots inside a courtyard, aligned to the district's grain."""
    out: list[tuple[Polygon, float]] = []
    rect = area.minimum_rotated_rectangle
    corners = list(rect.exterior.coords)[:-1]
    if len(corners) < 4:
        return out
    length = max(math.dist(corners[0], corners[1]), math.dist(corners[1], corners[2]))
    depth = min(math.dist(corners[0], corners[1]), math.dist(corners[1], corners[2]))
    if length < lot_w or depth < lot_d:
        return out
    cx, cy = rect.centroid.x, rect.centroid.y
    rows = max(1, int(depth // lot_d))
    per_row = max(1, int(length // lot_w))
    for row in range(rows):
        for col in range(per_row):
            u = -length / 2 + (col + 0.5) * (length / per_row)
            v = -depth / 2 + (row + 0.5) * (depth / rows)
            cell = _cell(u, v, cx, cy, lot_w, lot_d, angle)
            if area.contains(cell):
                out.append((cell, angle))
                continue
            # a courtyard is not a rectangle: a smaller cell at the same spot usually fits
            small = _cell(u, v, cx, cy, lot_w * 0.68, lot_d * 0.68, angle)
            if area.contains(small):
                out.append((small, angle))
    return out


def _cell(u: float, v: float, cx: float, cy: float, w: float, d: float,
          angle: float) -> Polygon:
    """One grid cell of a courtyard, on the district's grain."""
    return affinity.translate(
        affinity.rotate(sbox(u - w / 2, v - d / 2, u + w / 2, v + d / 2), angle,
                        origin=(0, 0)), cx, cy)


