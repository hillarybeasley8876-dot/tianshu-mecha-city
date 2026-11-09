"""Lots that stand over a hole in the ground crust (lead, r9).

`kit/terrain.py` cuts the crust for the canal, the dock trench, every sunken plaza and the
below-crust part of every descending connector. Anything standing on one of them stands over a
hole, so the lot is dropped. This is a FILTER, deliberately: putting the cut into the block mask
instead would change the shape of every block `fabric` cuts, and from the first changed block on
the one shared `rng` stream would draw different numbers for every lot after it - measured, that
replaced 334 of the 354 buildings the user has already seen and broke every pinned street camera.
A filter draws no random number, renumbers nothing and leaves a gap where the id was.

The same cut is taken at the PLATEAU slab's own height: `kit/terrain.py` cuts that slab with
`ground_cuts` over the 6 m below its top, so a lot on the plateau can stand over a hole the crust
filter never looks at (lead, r9: one lot's corner had nothing under it for 400 m). Both polygons
are built once by the orchestrator and swept twice - once after the kerb walls, once after the
support towers - because that is where the finished mass lists are.
"""
from __future__ import annotations

from shapely.geometry import Polygon

import geom
from floors import cut_ground

CRUST = 6.0     # m: the slab thickness both the crust and the plateau are cut through
TOL = 4.0       # m2: a lot overlapping a cut by less than this keeps its corner


def ground(cons: list[dict], terrain: dict, decks: list[dict]) -> Polygon:
    """The plan area the ground crust is cut out of, at street level."""
    return cut_ground(cons, terrain, decks)


def plateau(cons: list[dict], terrain: dict, decks: list[dict],
            crust: float = CRUST) -> Polygon:
    """The same cut, taken at the plateau slab and clipped to the plateau polygon."""
    height = float(terrain["escarpment"]["height"])
    # Intersected with the plateau itself: `ground_cuts` cuts the trench for the WHOLE path of
    # any connector that crosses the plateau's 6 m band, and most of that path is over the lower
    # city, where there is no plateau slab to cut. Without the intersection this dropped 8 lots
    # for the one corner the gate actually found.
    return cut_ground(cons, terrain, decks, z_hi=height, z_lo=height - crust).intersection(
        geom.poly(terrain["plateau"]["polygon"]))


def route_bands(cons: list[dict], margin: float = 2.0,
                corridors: list[dict] | None = None) -> list[tuple[Polygon, float, float]]:
    """(plan strip, z bottom, z top) for every designed route (lead, r8).

    Only the kinds that are built as structure are swept - a `drop` is a commitment, not a solid -
    and each band carries its own z span, so a lot under a +80 ramp is left alone. The strip is
    the route's own width plus `margin` - the same strip `openings` pierces with.
    """
    from shapely.geometry import LineString, Point
    import route3d

    out: list[tuple[Polygon, float, float]] = []
    for con in cons:
        if con.get("usable") is False:
            continue
        half = float(con["width"]) / 2 + margin
        if con["kind"] in ("ramp", "stairs", "edgejump"):
            path = route3d.path_of(con)
            zs = [float(p[2]) for p in path]
            line = LineString([(p[0], p[1]) for p in path])
            strip = line.buffer(half, cap_style=2, join_style=2) if line.length >= 1.0 \
                else Point(path[0][0], path[0][1]).buffer(half)
            out.append((strip, min(zs) - 1.0, max(zs) + route3d.CLEAR))
        elif con["kind"] in ("lift", "vent", "vcat"):
            x, y = route3d.shaft_xy(con)
            lo = min(float(con["from"][2]), float(con["to"][2]))
            hi = max(float(con["from"][2]), float(con["to"][2]))
            out.append((Point(x, y).buffer(half, quad_segs=8), lo,
                        hi + route3d.TOP_AIR))
    for item in corridors or []:
        half = float(item["width"]) / 2 + margin
        z = float(item["z"])
        out.append((LineString([(p[0], p[1]) for p in item["points"]])
                    .buffer(half, cap_style=2), z, z + route3d.CLEAR))
    return out


def _overlaps(bands: list[tuple[Polygon, float, float]], poly: Polygon,
              lo: float, hi: float) -> bool:
    """Does a mass standing between `lo` and `hi` stand in any route band it shares a height with?"""
    return any(poly.intersection(strip).area > 0.2 and z0 < hi and z1 > lo
               for strip, z0, z1 in bands)


def route_lots(buildings: list[dict], bands: list[tuple[Polygon, float, float]],
               decks: list[dict], tol: float = TOL) -> list[str]:
    """Drop the lots that stand in a route's strip at their own height. A pure FILTER."""
    protected = carriers(decks)
    dropped: list[str] = []
    keep: list[dict] = []
    for b in buildings:
        box = geom.rect(tuple(b["center"]), tuple(b["size"]), b.get("rot", 0.0))
        lo, hi = float(b["base_z"]), float(b["base_z"]) + float(b["height"])
        if b["id"] not in protected and _overlaps(bands, box, lo, hi):
            dropped.append(b["id"])
        else:
            keep.append(b)
    buildings[:] = keep
    return dropped


def route_cover(arenas: list[dict], bands: list[tuple[Polygon, float, float]],
                tol: float = TOL) -> list[str]:
    """Drop the arena crates that stand in a route's strip at their own height.

    `keepclear` only ever kept the connector ENDPOINTS clear, so a crate could stand on the
    centre line of the stair that climbs through its own arena (lead, r8 item 4).
    """
    dropped: list[str] = []
    for arena in arenas:
        keep: list[dict] = []
        for i, piece in enumerate(arena["cover"]):
            c = piece["center"]
            box = geom.rect((c[0], c[1]), (piece["size"][0], piece["size"][1]))
            lo, hi = float(c[2]), float(c[2]) + float(piece["size"][2])
            if _overlaps(bands, box, lo, hi):
                dropped.append(f"{arena['id']}#{i}")
            else:
                keep.append(piece)
        arena["cover"] = keep
    return dropped


def carriers(decks: list[dict]) -> set[str]:
    """Ids that must never be dropped: the towers a named deck stands on. A straddle tower is
    exempted separately, by its own `straddles` field. Removing either would leave the thing it
    carries hanging."""
    return {c for d in decks for c in (d.get("supported_by") or [])}


def drop_lots(buildings: list[dict], cut: Polygon, protected: set[str] = frozenset(),
              tol: float = TOL) -> list[str]:
    """Remove the lots that stand over one cut, and nothing else.

    `buildings` is edited in place; the dropped ids come back so the caller can print them.
    """
    if cut.is_empty:
        return []
    dropped: list[str] = []
    keep: list[dict] = []
    for b in buildings:
        box = geom.rect(tuple(b["center"]), tuple(b["size"]), b.get("rot", 0.0))
        if b["id"] not in protected and not b.get("straddles") \
                and box.intersection(cut).area > tol:
            dropped.append(b["id"])
        else:
            keep.append(b)
    buildings[:] = keep
    return dropped


def sweep(buildings: list[dict], cuts: tuple[Polygon, Polygon], decks: list[dict]) -> list[str]:
    """Drop the lots over the crust cut AND over the plateau cut, in that order.

    The carrier towers are exempt, read from `decks` as it stands at the call - a deck added
    between the two sweeps brings its own carriers with it.
    """
    keep = carriers(decks)
    return drop_lots(buildings, cuts[0], keep) + drop_lots(buildings, cuts[1], keep)
