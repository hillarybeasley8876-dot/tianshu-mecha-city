"""Arena stage: outlines shaped by the streets around them, walkable surfaces inside, cover
on every surface.

Split out of props.py so both files stay readable: the arena machinery is the part that grew
with r4 (cover per surface, connector keep-clear, the open boss arena, the late top-up), and
props.py is the set dressing - landmarks, Block 9, hives, anchors, the start and the skyline.
Spawn sockets are their own stage (`sockets.py`, lead r5): they need the finished layout.

Cover follows dossier §3.2: a piece every 40-60 m, 30-40 % of it destructible, and every
point of the arena within 60 m of full cover at least 20 m tall (check L4). Every placement
goes through a `coverfield.Field` (lead, r7), so no two pieces on one surface ever touch and
nothing is ever placed inside a keep-out.
"""
from __future__ import annotations

import math
import random

from shapely.geometry import Point, Polygon, LineString, box as sbox
from shapely.ops import unary_union
from shapely.strtree import STRtree

import geom
import mapconst as C
import coverfield
import floors as floor_mod
import hive_rule
from geom import shape_by_streets

LOW_COVER_H = (8.0, 10.0)
FULL_COVER_H = (20.0, 28.0)
CANOPY_COVER_SPACING = 28.0  # a canopy roof is 64 x ~56 m: it carries its own cover
# The sizes `_place_near` falls back to when the drawn box does not fit the gap it found. The
# last one is the smallest piece that still counts as full cover, so a spot that can hold any
# legal piece at all holds one of these - which is what makes the top-up idempotent.
TALL_FALLBACK = ((26.0, 28.0, 24.0), (20.0, 20.0, 20.0))


def _circle_outline(center: tuple[float, float], radius: float,
                    segments: int = 48) -> list[list[float]]:
    """A disc arena outline (the Crown deck), as a closed polygon."""
    return [[round(center[0] + radius * math.cos(2 * math.pi * i / segments), 1),
             round(center[1] + radius * math.sin(2 * math.pi * i / segments), 1)]
            for i in range(segments)]


def cover_for(surface: Polygon, z: float, spacing: float, soft_share: float,
              rng: random.Random, field: coverfield.Field,
              allow: Polygon | None = None) -> int:
    """Cover pieces on one arena surface: alternate full and low cover, then top up until
    every point of the surface is within 60 m of a piece at least 20 m tall.

    `field` carries the arena's live cover list and the keep-out every piece has to miss
    (lead, r7): the connector keep-clear union (r4), the socket floors (r5), the hive's open
    ground (r6) and the 30 m spheres round the vista cameras - plus the rule that no piece may
    stand within `coverfield.MIN_GAP` of another piece on the same surface. `allow` restricts
    the pieces to part of the surface - the boss arena's rim steps and fins (r4, boss note) -
    and keeps them all low, so a wide arena can stay open and still have the pieces it is
    shaped by. Returns how many pieces were added.
    """
    added = 0
    low_only = allow is not None
    zone = surface.intersection(allow) if allow is not None else surface
    for i, (x, y) in enumerate(geom.poisson_points(zone, spacing, rng)):
        tall = (i % 2 == 0) and not low_only
        piece = _place(x, y, z, tall, rng.random() < soft_share, rng, surface, field, allow)
        if piece is not None:
            field.add(piece)
            added += 1
    if low_only:
        return added
    full = _full_on(field, z)
    if not full:
        # a narrow surface (a skybridge, a canopy roof) can come out of the Poisson pass with
        # nothing tall on it: seed one piece and let the top-up do the rest
        mid = surface.representative_point()
        piece = _place_near(mid.x, mid.y, z, soft_share, rng, surface, field)
        if piece is not None:
            field.add(piece)
            full.append(piece)
            added += 1
    if full:
        added += _top_up(surface, z, field, full, soft_share, rng)
    return added


def _full_on(field: coverfield.Field, z: float) -> list[dict]:
    """The full-height pieces standing on the surface at `z`."""
    return [p for p in field.pieces
            if p["size"][2] >= C.FULL_COVER_H and abs(p["center"][2] - z) <= coverfield.BAND]


def _place(x: float, y: float, z: float, tall: bool, soft: bool, rng: random.Random,
           surface: Polygon, field: coverfield.Field,
           allow: Polygon | None = None) -> dict | None:
    """The piece, if it may stand here: on the surface, inside the allowed zone when the
    arena declares one, clear of every keep-out, and MIN_GAP clear of its neighbours."""
    here = Point(x, y)
    if not surface.contains(here):
        return None
    if allow is not None and not allow.contains(here):
        return None
    piece = _piece(x, y, z, tall, soft, rng)
    if not field.free(x, y, z, tuple(piece["size"])):
        return None
    return piece


def _place_sized(x: float, y: float, z: float, size: tuple[float, float, float],
                 soft: bool, surface: Polygon, field: coverfield.Field) -> dict | None:
    """A piece of a given size, if it may stand here - the deterministic half of the search
    below, so a spot is never given up on because the dice rolled a big box."""
    if not surface.contains(Point(x, y)) or not field.free(x, y, z, size):
        return None
    return {"center": [round(x, 1), round(y, 1), z],
            "size": [round(v, 1) for v in size], "soft": soft}


def _place_near(x: float, y: float, z: float, soft_share: float, rng: random.Random,
                surface: Polygon, field: coverfield.Field) -> dict | None:
    """A tall piece at this point, or at the nearest spot to it that may carry one: the
    top-up grid must not leave a hole just because a keep-clear sphere sits on a grid point.

    The search is ordered by reach, so the piece lands as close to the hole as the field
    allows, and it never lands on one that is already there. When the drawn box does not fit,
    the smallest legal full-cover piece is tried at the same spot: a search that gave up on a
    size would leave the hole for the next pass to find, and `cover_pass` would not be
    idempotent (lead, r7 point 2).
    """
    for reach in (0.0, 16.0, 24.0, 32.0, 44.0, 56.0, 68.0):
        for i in range(8 if reach else 1):
            a = math.pi * i / 4.0
            px, py = x + reach * math.cos(a), y + reach * math.sin(a)
            soft = rng.random() < soft_share
            piece = _place(px, py, z, True, soft, rng, surface, field)
            if piece is not None:
                return piece
            for size in TALL_FALLBACK:
                piece = _place_sized(px, py, z, size, soft, surface, field)
                if piece is not None:
                    return piece
    return None


def _top_up(surface: Polygon, z: float, field: coverfield.Field, full: list[dict],
            soft_share: float, rng: random.Random) -> int:
    """Add full cover until every point of the surface is close to a piece.

    Three passes: a keep-clear sphere can block a whole cluster of grid points, and one pass
    then leaves a hole, so the grid is swept again until it adds nothing. The grid starts half
    a step in - a 24 m wide skybridge whose bounds align with the step would otherwise only
    ever offer its own boundary rows, which are not inside it. It is idempotent: once the
    holes are filled (or the field has nowhere legal left to put a piece) it adds nothing.
    """
    step = 24.0
    added = 0
    minx, miny, maxx, maxy = surface.bounds
    for _ in range(3):
        found = 0
        y = miny + step / 2
        while y <= maxy:
            x = minx + step / 2
            while x <= maxx:
                if surface.contains(Point(x, y)) and \
                        min(math.dist((x, y), (p["center"][0], p["center"][1]))
                            for p in full) > C.COVER_NEAR * 0.5:
                    piece = _place_near(x, y, z, soft_share, rng, surface, field)
                    if piece is not None:
                        field.add(piece)
                        full.append(piece)
                        found += 1
                x += step
            y += step
        added += found
        if not found:
            return added
    return added


def towers_for(surface: Polygon, z: float, spec: dict, rng: random.Random,
               field: coverfield.Field) -> list[dict]:
    """Landmark cover: the stacked container towers / crane bases an arena is named for.

    C14 counts a sample as covered when a >= 20 m collider stands within 60 m of it, so a
    yard whose character is low crates needs a few real towers in it (lead, r4 point 3).
    They go through the same field as every other piece, so a tower can never land on one.
    """
    out: list[dict] = []
    reach = float(spec.get("spacing", 120.0))
    want = int(spec["count"])
    for x, y in geom.poisson_points(surface, max(reach * 0.4, 40.0), rng):
        if len(out) >= want:
            break
        if out and min(math.dist((x, y), (p["center"][0], p["center"][1]))
                       for p in out) < reach * 0.7:
            continue
        w = rng.uniform(*spec.get("size", (24.0, 32.0)))
        h = geom.snap(rng.uniform(*spec["height"]), 4.0)
        size = (round(w, 1), round(w * 0.8, 1), round(h, 1))
        if not surface.contains(Point(x, y)) or not field.free(x, y, z, size):
            continue
        out.append(field.add({"center": [round(x, 1), round(y, 1), z], "size": list(size),
                              "soft": False, "kind": spec.get("kind", "stack")}))
    return out


def _piece(x: float, y: float, z: float, tall: bool, soft: bool,
           rng: random.Random) -> dict:
    if tall:
        w, d = rng.uniform(20.0, 30.0), rng.uniform(20.0, 34.0)
        h = rng.uniform(*FULL_COVER_H)
    else:
        w, d = rng.uniform(16.0, 24.0), rng.uniform(16.0, 26.0)
        h = rng.uniform(*LOW_COVER_H)
    return {"center": [round(x, 1), round(y, 1), z],
            "size": [round(w, 1), round(d, 1), round(geom.snap(h, 4.0), 1)], "soft": soft}


def build_arenas(rules: dict, decks: list[dict], rng: random.Random,
                 corridors: list[dict] | None = None,
                 keep: coverfield.KeepOut | None = None) -> list[dict]:
    """Arena records: outline, tiers, cover on every surface inside the outline.

    Cover is placed per *walkable surface*, not per tier number: the ground, every arena
    deck that overlaps the outline and every canopy roof over it. C13/C14 sample the arena
    by dropping a ray from +320 m, so a sample lands on whatever surface is really there -
    the dock floor, a canopy roof, the deck under the deck - and each of those has to carry
    its own cover (lead, r4 points 2 and 3). Spawn sockets come later, in `sockets.py`: they
    are a statement about the finished layout (lead, r5).
    """
    out = []
    for aid, spec in rules["arenas"].items():
        polygon = arena_outlines(rules, corridors)[aid]
        area = geom.poly(polygon)
        arena = {"id": aid, "name": spec["name"], "polygon": polygon,
                 "tiers": [float(t) for t in spec["tiers"]],
                 "main_tier": float(spec["main_tier"]), "cover": [], "spawn_sockets": []}
        # one field for the whole arena, so a piece on the canopy roof is known to the piece
        # placed on the deck under it and no two surfaces at the same z can collide
        field = coverfield.Field(arena["cover"], keep)
        floors = surfaces(aid, area, spec, decks)
        allow = _open_zone(aid, spec, decks, area) if spec.get("open_cover") else None
        for z, surface in floors:
            # a canopy roof is a narrow slab: it needs its own spacing or a mech that lands
            # on it stands in the open (C14 samples the roof, not the street under it)
            step = min(float(spec["cover_spacing"]), CANOPY_COVER_SPACING) \
                if any(abs(z - d["z"]) < 1.0 and d.get("canopy") for d in decks) \
                else float(spec["cover_spacing"])
            cover_for(surface, z, step, spec["cover_soft"], rng, field,
                      allow if abs(z - float(spec["main_tier"])) < 1.0 else None)
        if spec.get("towers"):
            towers_for(floors[0][1], float(spec["main_tier"]), spec["towers"], rng, field)
        if allow is not None:
            arena["open_cover"] = True
        out.append(arena)
    return out


def set_soft(arenas: list[dict], rules: dict) -> dict[str, float]:
    """Mark destructible cover at the arena's exact share (MAP §5 L4 asks for 30-40 %).

    Deciding it piece by piece with a dice roll leaves the share wherever chance lands, and
    the arena's own spec is the design: a Bresenham step over the final list hits it exactly.
    Named towers are always solid.
    """
    out: dict[str, float] = {}
    for arena in arenas:
        share = float(rules["arenas"][arena["id"]]["cover_soft"])
        rows = [c for c in arena["cover"] if not c.get("kind")]
        for i, piece in enumerate(rows):
            piece["soft"] = share > 0.0 and \
                math.floor((i + 1) * share) > math.floor(i * share)
        soft = sum(1 for c in arena["cover"] if c["soft"])
        out[arena["id"]] = round(soft / max(len(arena["cover"]), 1), 2)
    return out


def cover_pass(arenas: list[dict], decks: list[dict], rules: dict, rng: random.Random,
               keep: coverfield.KeepOut | None = None) -> int:
    """A last top-up over every arena surface, once the whole deck list exists.

    Two things only show up late: the Megablock Canyon's skybridges need the finished
    buildings to land on, and a surface whose Poisson pass lost its sites to a keep-clear
    sphere only shows the hole when everything else is placed. This pass tops up every
    surface that still leaves a point more than 30 m from full cover, so L4 holds on the
    data city-build actually reads.

    It is idempotent (lead, r7): the field now refuses to stand a piece on another one, so a
    second call over an unchanged layout finds every hole already filled and adds nothing.
    `build_layout` calls it twice and asserts the second call adds 0.
    """
    added = 0
    for arena in arenas:
        spec = rules["arenas"][arena["id"]]
        area = geom.poly(arena["polygon"])
        field = coverfield.Field(arena["cover"], keep)
        for z, surface in surfaces(arena["id"], area, spec, decks):
            if spec.get("open_cover") and abs(z - float(spec["main_tier"])) < 1.0:
                continue                     # an open boss arena is left open
            full = _full_on(field, z)
            if not full:
                mid = surface.representative_point()
                piece = _place_near(mid.x, mid.y, z, spec["cover_soft"], rng, surface, field)
                if piece is None:
                    continue
                field.add(piece)
                full.append(piece)
                added += 1
            added += _top_up(surface, z, field, full, spec["cover_soft"], rng)
    return added


SETTLE_REACH = (0.0, 4.0, 8.0, 12.0, 16.0, 24.0, 32.0, 40.0, 52.0, 68.0, 88.0, 112.0,
                144.0)   # m: the rings a homeless piece is walked outwards on. Finer than 8 m near
                       #    home - the crust between two ramp trenches is a narrow ledge, and an 8 m
                       #    ring stepped straight over the legal spots 7.6 m away (A3 lost its
                       #    tier-0 cover to the next ring, 88 m west).
SETTLE_SHRINK = (1.0, 0.8, 0.62)    # footprint scales tried before a piece is given up on
SETTLE_MIN_W = 16.0                 # m: a piece is never shrunk below this footprint — C14 casts 8
                               #    rays 45 deg apart, and a 12 m box at 40 m falls between them
SETTLE_DROP = 64.0                  # m: how far below its own z a piece may look for a floor


class HiveLanes:
    """The firing lines a relocated cover piece may not block (lead, r9).

    `hive_rule.verify` wants every pod shootable from >= 8 of the 48 positions flow's bot tries,
    and the ring it fires from (70-140 m) is exactly where arena cover belongs. The original cover
    cleared those lanes; a piece walked onto a floor by `settle_cover` does not have to. So a
    moved piece is rejected at any spot whose box crosses a pod-to-firing-position segment at its
    own height band. Pieces that never move are not tested: they are the layout the check passed.
    """

    def __init__(self, sites: list[dict]) -> None:
        self.lines: list[LineString] = []
        self.spans: list[tuple[float, float]] = []
        for hive in sites:
            for pod in hive_rule.pods(hive):
                for spot in hive_rule.firing_grid(hive, pod[2] - hive["pos"][2]):
                    self.lines.append(LineString([(spot[0], spot[1]), (pod[0], pod[1])]))
                    self.spans.append((min(spot[2], pod[2]), max(spot[2], pod[2])))
        self.tree = STRtree(self.lines) if self.lines else None

    def blocked(self, x: float, y: float, w: float, d: float, z0: float, z1: float) -> bool:
        if self.tree is None:
            return False
        area = sbox(x - w / 2, y - d / 2, x + w / 2, y + d / 2)
        for i in self.tree.query(area):
            lo, hi = self.spans[int(i)]
            if hi <= z0 + 0.5 or lo >= z1 - 0.5:
                continue
            if self.lines[int(i)].intersects(area):
                return True
        return False


def _rescue(floors, field: coverfield.Field, piece: dict, lanes: HiveLanes | None,
            sizes: tuple[float, ...] | None = None) -> tuple[float, float, float,
                                                              float, float] | None:
    """Where this piece may stand, or None. Returns (x, y, z, w, d).

    Three passes, cheapest first, and the FIRST that works wins so a piece is moved as little as
    possible: at its own height and size, then at its own height with a smaller footprint (a
    canopy roof or a 24 m skybridge cannot hold a 30 x 34 m crate, and the crate's HEIGHT is what
    C14 counts, so shrinking the plan costs nothing), then on the nearest floor BELOW it - which
    is where a piece on a canopy belongs anyway, on the street the canopy roofs.
    """
    x, y, z = (float(v) for v in piece["center"])
    w, d, h = (float(v) for v in piece["size"])
    plans = [(w, d)] if sizes is None else [(w, d)] + [(s[0], s[1]) for s in sizes]

    def legal(px: float, py: float, height: float, sw: float, sd: float) -> bool:
        if not field.free(px, py, height, (sw + 0.2, sd + 0.2, h)):
            return False
        return lanes is None or not lanes.blocked(px, py, sw, sd, height, height + h)

    # Reach-major, not size-major: the point is to move a piece as little as possible, so the
    # nearest legal spot wins even if it means a smaller box. Searching every reach for the
    # LARGEST size first sent a crate 144 m north when a 16 m box fitted 8 m away (A3).
    for height in [z] + floors.below(z, SETTLE_DROP):
        for reach in SETTLE_REACH:
            for pw, pd in plans:
                for scale in SETTLE_SHRINK:
                    sw = max(SETTLE_MIN_W, round(pw * scale, 1))
                    sd = max(SETTLE_MIN_W, round(pd * scale, 1))
                    spot = floors.spot(height, x, y, sw, sd, (reach,),
                                       free=lambda px, py: legal(px, py, height, sw, sd))
                    if spot is not None:
                        return spot[0], spot[1], height, sw, sd
    return None


def settle_cover(arenas: list[dict], decks: list[dict], terrain: dict, half: float,
                 keep: coverfield.KeepOut | None = None,
                 hives: list[dict] | None = None,
                 cons: list[dict] | None = None) -> dict:
    """Put every cover piece on a floor the render really has (lead, r9).

    Runs LAST, on the finished deck list, and draws no random numbers, so it is idempotent and
    it cannot move anything except the cover. A piece is wrong when its whole footprint is not
    on a floor at its own z - the deck polygon moved under it, the deck was perforated after the
    arena stage placed it, or only its centre was ever on the slab. Each wrong piece is walked
    onto the nearest floor it fits on (`_rescue`), clear of the hive firing lanes, and dropped
    only when there is none. Returns `{"moved": n, "dropped": [...], "kept": n}`.
    """
    floors = floor_mod.Floors(terrain, decks, half, cons)
    lanes = HiveLanes(hives) if hives else None
    moved, dropped, kept, filled = 0, [], 0, 0
    for arena in arenas:
        good: list[dict] = []
        bad: list[dict] = []
        gone: list[dict] = []
        for piece in arena["cover"]:
            x, y, z = (float(v) for v in piece["center"])
            w, d = float(piece["size"][0]), float(piece["size"][1])
            (good if floors.holds(z, x, y, w, d) else bad).append(piece)
        kept += len(good)
        # `field.pieces IS good`, so every relocated piece joins the list the field checks against
        # and `arena["cover"]` ends up as the pieces that stand on a floor, in place.
        field = coverfield.Field(good, keep)
        for piece in bad:
            found = _rescue(floors, field, piece, lanes)
            if found is None:
                c = piece["center"]
                dropped.append("%s (%.0f, %.0f, %.0f)" % (arena["id"], c[0], c[1], c[2]))
                gone.append(piece)
                continue
            x, y, z, w, d = found
            piece["center"] = [x, y, z]
            piece["size"] = [w, d, float(piece["size"][2])]
            field.add(piece)
            moved += 1
        arena["cover"] = good
        filled += _refill(arena, gone, floors, keep, lanes)
    return {"moved": moved, "dropped": dropped, "kept": kept, "filled": filled}


def _refill(arena: dict, gone: list[dict], floors, keep: coverfield.KeepOut,
            lanes: HiveLanes | None) -> int:
    """Put a piece back where one was DROPPED, as close to where it stood as the floors allow.

    Deliberately not a general L4 top-up: `validate_layout` already accepted this arena's cover
    density before the settle, so the only holes that matter are the ones the settle made. A grid
    sweep put 84 extra crates in A4 and filled the open boss arena, which is a much bigger change
    than the bug it was fixing. An arena the layout marks `open_cover` is left alone entirely.
    """
    if arena.get("open_cover") or not gone:
        return 0
    field = coverfield.Field(arena["cover"], keep)
    added = 0
    for piece in gone:
        found = _rescue(floors, field, piece, lanes, sizes=TALL_FALLBACK)
        if found is None:
            continue
        x, y, z, w, d = found
        field.add({"center": [x, y, z], "size": [w, d, float(piece["size"][2])], "soft": False})
        added += 1
    return added


def arena_outlines(rules: dict, corridors: list[dict] | None = None) -> dict[str, list]:
    """The arena outlines on their own - the stage that roofs the arenas needs them before
    any cover exists (canopies go up first, then the cover knows which roofs to stand on)."""
    out: dict[str, list] = {}
    for aid, spec in rules["arenas"].items():
        outline = (_circle_outline(tuple(spec["center"]), spec["size"][0] / 2)
                   if spec.get("_shape") == "disc"
                   else geom.rect_points(tuple(spec["center"]), tuple(spec["size"]),
                                         spec.get("rot", 0.0)))
        out[aid] = shape_by_streets(outline, None,
                                    corridors if spec.get("_shape") != "disc" else None)
    return out


def surfaces(aid: str, area: Polygon, spec: dict,
              decks: list[dict]) -> list[tuple[float, Polygon]]:
    """Every walkable surface inside the arena outline, as (z, polygon).

    The main tier is the ground *minus* the decks that sit below it (the Container Yard's
    dock floor is not at +0) and minus the voids of the arena's own floor deck (the Crown's
    core drum), plus each arena deck and canopy roof that overlaps the outline - a canopy
    roof is walkable and is where C14's samples land when one roofs the arena.
    """
    main = float(spec["main_tier"])
    tiers = [float(t) for t in spec["tiers"]]
    lower, surfaces, voids = [], [], []
    for deck in decks:
        piece = geom.poly(deck["polygon"])
        holes = [geom.poly(h) for h in deck.get("holes", [])]
        for hole in holes:
            piece = piece.difference(hole)
        piece = piece.intersection(area)
        if abs(deck["z"] - main) < 1.0:
            voids.extend(h.intersection(area) for h in holes)
            continue
        if piece.area < C.ARENA_SURFACE_MIN:
            continue
        # only a deck that is one of THIS arena's own tiers replaces the ground: the Crown
        # stands over the whole city, and the Spire's collar 100 m below it is not its floor
        if deck["z"] < main and deck["z"] in tiers:
            lower.append(piece)          # a lower tier is a cut in the ground, not a slab
        if deck["z"] > main or deck["z"] in tiers:
            surfaces.append((float(deck["z"]), piece))
    ground = area
    for cut in lower + voids:
        ground = ground.difference(cut)
    return [(main, ground)] + sorted(surfaces, key=lambda s: s[0])


def _open_zone(aid: str, spec: dict, decks: list[dict], area: Polygon) -> Polygon | None:
    """The part of a wide arena that may carry cover at all (the Crown, boss note r4).

    MAP §4 builds the Crown as a stepped rim, four fins and a central drum; the boss arena
    has to stay open, so cover lives on the rim steps, beside the fins and against the core,
    and the middle ring stays a clear floor.
    """
    zone = spec["open_cover"]
    centre = tuple(spec["center"])
    deck = next((d for d in decks if d.get("arena") == aid), None)
    rings = [float(d["r"]) for d in (deck or {}).get("rim_steps", [])]
    if not rings:
        return None
    keep = unary_union([_ring(centre, r, float(zone.get("rim_band", 26.0))) for r in rings])
    core = _ring(centre, float(zone["core_r"]), float(zone.get("core_band", 36.0)))
    fins = unary_union([_wedge(centre, float(f["angle_deg"]), float(f["reach"]),
                               float(zone.get("fin_band", 16.0)))
                        for f in (deck or {}).get("fins", [])])
    return keep.union(core).union(fins).intersection(area)


def _ring(centre: tuple[float, float], radius: float, band: float) -> Polygon:
    """An annulus of `band` metres centred on `radius`."""
    outer = Point(centre).buffer(radius + band / 2, quad_segs=48)
    return outer.difference(Point(centre).buffer(max(radius - band / 2, 0.0), quad_segs=48))


def _wedge(centre: tuple[float, float], angle: float, reach: float,
           band: float) -> Polygon:
    """A radial slot `band` degrees wide, from the centre out to `reach` + a piece's room."""
    far = reach + 48.0
    half = math.radians(band / 2)
    base = math.radians(angle)
    pts = [centre] + [(centre[0] + far * math.cos(base + t), centre[1] + far * math.sin(base + t))
                      for t in (-half, 0.0, half)]
    return Polygon(pts)

