"""The late repair half of the Hive Spire rule (lead, r6): clear the ground, open the lanes.

`hives.py` reserves each spire's open ground before anything solid exists and opens its light well;
this module is what runs on the *finished* layout, when the cover, the towers and the deck columns
are all in. It measures with `hive_rule` - the same functions L4 checks the written JSON with - and
only ever touches cover: a deck, a column or a building in the way is reported by the check, never
deleted. Split out of hives.py to keep both files readable.
"""
from __future__ import annotations

import math
import random

from shapely.geometry import LineString, Point, Polygon

import geom
import coverfield
import mapconst as C
from arenas import TALL_FALLBACK, _place as place, _place_sized
from sight import arena_surfaces
from hive_rule import (AIR_H, ASSAULT_DZ, ASSAULT_R, MIN_POSITIONS, _free, cover_index,
                       firing_grid, first_block, open_disc, pods, solids)

LANE_BUDGET = 24           # pieces a spire may flatten before the repair gives up
RECOVER_STEP = 24.0        # m: the grid C14's 60 m rule is re-checked on
LOW_COVER_H = 8.0          # m: what a cover piece is cut down to in a firing lane (C.OPEN_COVER_MAX)


def clear_ground(layout: dict, hive: dict) -> int:
    """Drop the cover pieces standing in a spire's open ground.

    The keep-out should have stopped them; this is the belt to its braces, and it is the
    "clear the structure" half of the lead's r6 note for anything a late pass added.
    """
    disc, tier = open_disc(hive), hive["pos"][2]
    dropped = 0
    for arena in layout["arenas"]:
        keep = []
        for piece in arena["cover"]:
            c = piece["center"]
            box = geom.rect((c[0], c[1]), (piece["size"][0], piece["size"][1]))
            if c[2] + piece["size"][2] > tier + 1.0 and c[2] < tier + AIR_H \
                    and box.intersects(disc):
                dropped += 1
                continue
            keep.append(piece)
        arena["cover"] = keep
    return dropped


def clear_lanes(layout: dict, hive: dict, budget: int = LANE_BUDGET) -> int:
    """Open the spire's firing lanes by flattening the cover that stands in them.

    A2's Interchange Knot is a stack of plates with 20-32 m cover pieces on them: the pods at
    12 m are behind a wall of crates from every bearing. The lead's r6 note allows either moving
    the hive or clearing the structure - the structure here is cover, so the pieces in the lanes
    are cut down to 8 m rubble (and dropped only if they are already low). Nothing else is
    touched: a deck, a column or a building in the way is reported, never deleted.
    """
    index = cover_index(layout)
    changed = 0
    for _ in range(budget):
        tree, items = solids(layout)
        worst, per_pod = None, None
        for i, pod in enumerate(pods(hive)):
            grid = firing_grid(hive, pod[2] - hive["pos"][2])
            free = [p for p in grid if _free(p, tree, items)]
            hits = sum(1 for s in free if not first_block(s, pod, tree, items))
            if per_pod is None or hits < per_pod:
                worst, per_pod = (i, pod, free), hits
        if per_pod is None or per_pod >= MIN_POSITIONS:
            break
        tally: dict[str, int] = {}
        for s in worst[2]:
            ident = first_block(s, worst[1], tree, items)
            if ident in index:
                tally[ident] = tally.get(ident, 0) + 1
        if not tally:
            break                       # a deck or a building is in the way: report, do not cut
        target = max(sorted(tally), key=lambda k: tally[k])
        _flatten(layout, index[target])
        changed += 1
    return changed


def needed_rays(layout: dict, hive: dict, spare: int = 4
                ) -> list[tuple[int, tuple, tuple]]:
    """The firing lines a new piece must mostly leave alone: each pod's clearest rays.

    Whatever else the repair does, these are the shots the assault depends on. `spare` is how
    many of them a piece may take away - a pod with 9 clear lines can lose one and still have
    the 8 the rule asks for, and refusing every crossing at all leaves nowhere to put cover.
    """
    tree, items = solids(layout)
    out: list[tuple[int, tuple, tuple]] = []
    for index, pod in enumerate(pods(hive)):
        grid = firing_grid(hive, pod[2] - hive["pos"][2])
        clear = [s for s in grid
                 if _free(s, tree, items) and not first_block(s, pod, tree, items)]
        out.extend((index, s, pod) for s in clear[:MIN_POSITIONS + spare])
    return out


def _blocked_counts(piece: dict, rays: list[tuple[int, tuple, tuple]]) -> dict[int, int]:
    """How many of each pod's kept firing lines this piece would stand in (2.5D, as the check)."""
    box = geom.rect(tuple(piece["center"][:2]), (piece["size"][0], piece["size"][1]))
    z0 = piece["center"][2]
    z1 = z0 + piece["size"][2]
    counts: dict[int, int] = {}
    for index, a, b in rays:
        ray = LineString([(a[0], a[1]), (b[0], b[1])])
        if not box.intersects(ray):
            continue
        hit = box.intersection(ray)
        for px, py in (list(getattr(hit, "coords", [])) or [(hit.x, hit.y)]):
            t = ray.project(Point(px, py)) / ray.length
            if z0 - 0.5 < a[2] + (b[2] - a[2]) * t < z1 + 0.5:
                counts[index] = counts.get(index, 0) + 1
                break
    return counts


def recover_cover(layout: dict, hive: dict, rules: dict, rng: random.Random,
                  keep: "coverfield.KeepOut", rounds: int = 2) -> int:
    """Put full cover back where flattening the firing lanes opened a hole.

    C14 (and L4) want a piece at least 20 m tall within 60 m of every point of an arena, and the
    lanes are radial, so the two only fight over the ground round the hive. The grid and the 60 m
    rule are L4's own; a piece is only placed where it crosses none of `needed_rays`, so the
    cover comes back between the lanes and never in one. It is placed through the arena's own
    `coverfield.Field` (lead, r7), so it is clear of the same keep-out the cover passes used,
    of the open ground, and of every piece already standing on that surface.
    """
    arena = next(a for a in layout["arenas"] if a["id"] == hive["arena"])
    soft = float(rules["arenas"][arena["id"]]["cover_soft"])
    field = coverfield.Field(arena["cover"], keep.union(open_disc(hive)))
    added = 0
    for _ in range(rounds):
        rays = needed_rays(layout, hive)
        holes = 0
        for surface, z in arena_surfaces(arena, layout["decks"]):
            full = [p for p in arena["cover"]
                    if p["size"][2] >= C.FULL_COVER_H and abs(p["center"][2] - z) < 4.0]
            if not full:
                continue
            for x, y in _grid(surface, RECOVER_STEP):
                # inside the assault ring the lead's r6 rule wins over C14: leave it bare
                if abs(z - hive["pos"][2]) <= ASSAULT_DZ and \
                        math.dist((x, y), hive["pos"][:2]) <= ASSAULT_R:
                    continue
                if min(math.dist((x, y), (p["center"][0], p["center"][1]))
                       for p in full) <= C.COVER_NEAR:
                    continue
                piece = _place_clear(x, y, z, soft, rng, surface, field, rays)
                if piece is not None:
                    full.append(field.add(piece))
                    holes += 1
        added += holes
        if not holes or not clear_lanes(layout, hive):
            break
    return added


def _place_clear(x: float, y: float, z: float, soft_share: float, rng: random.Random,
                 surface: Polygon, field: "coverfield.Field",
                 rays: list[tuple[int, tuple, tuple]]) -> dict | None:
    """A tall piece near this point, on the surface, clear of the keep-out and of its
    neighbours, and taking no more of any pod's firing lines than that pod has to spare.

    Like the arena top-up it falls back to the smallest legal piece rather than giving up on a
    spot because the dice rolled a box that did not fit the gap (lead, r7)."""
    budget = _spare(rays)
    for reach in (0.0, 16.0, 24.0, 32.0, 44.0, 56.0, 68.0):
        for i in range(8 if reach else 1):
            a = math.pi * i / 4.0
            px, py = x + reach * math.cos(a), y + reach * math.sin(a)
            soft = rng.random() < soft_share
            for piece in (place(px, py, z, True, soft, rng, surface, field),
                          *(_place_sized(px, py, z, s, soft, surface, field)
                            for s in TALL_FALLBACK)):
                if piece is None:
                    continue
                if all(n <= budget.get(pod, 0)
                       for pod, n in _blocked_counts(piece, rays).items()):
                    return piece
    return None


def _spare(rays: list[tuple[int, tuple, tuple]]) -> dict[int, int]:
    """How many of each pod's kept lines a new piece may block."""
    kept: dict[int, int] = {}
    for index, _, _ in rays:
        kept[index] = kept.get(index, 0) + 1
    return {pod: max(n - MIN_POSITIONS, 0) for pod, n in kept.items()}


def _grid(surface: Polygon, step: float) -> list[tuple[float, float]]:
    """A sample grid over one surface, half a step in from its bounds."""
    minx, miny, maxx, maxy = surface.bounds
    out = []
    y = miny + step / 2
    while y <= maxy:
        x = minx + step / 2
        while x <= maxx:
            if surface.contains(Point(x, y)):
                out.append((x, y))
            x += step
        y += step
    return out


def _flatten(layout: dict, where: tuple[dict, int]) -> None:
    """Cut one cover piece down to rubble height, or take it away if it is already low."""
    arena, i = where
    piece = arena["cover"][i]
    if piece["size"][2] > LOW_COVER_H:
        piece["size"][2] = LOW_COVER_H
        piece["soft"] = True
        piece["kind"] = "rubble"
    else:
        arena["cover"].pop(i)


