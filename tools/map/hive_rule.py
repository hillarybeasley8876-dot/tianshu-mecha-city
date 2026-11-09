"""The rule a Hive Spire has to satisfy to be assaultable (lead, r6), measured from the layout.

flow's E2E bot stands on 8 bearings x 3 ranges (70/100/140 m) x 2 lifts round a spire and shoots
the pod it locked with the gun's own ray. r3 found that at `hive_a2` and `hive_a5` *none* of the 48
candidates had a shot: both spires stood inside their own arena's structures - the Knot's helix
over the L2 plate, the Foundry's L3 plate with cover pieces on it. "Move the hive or clear the
structure" (lead, r6) is answered on the layout side by `hives.py`; this module is the measure
both of them use:

* 40 m of open ground round the base on its own tier, and no solid in the 64 m of air over it;
* every pod in the 10-55 m band shootable from >= 8 of the 48 positions flow's bot tries;
* >= 3 approach routes onto that ground, in three different 60 deg sectors.

`verify()` re-derives all of it from the layout JSON - never from the generator's geometry - so
`hives.build` (which repairs) and `checks_hives.check_l4_hives` (which gates) cannot agree by
construction.

Pods and trunk come from `game/flow/hive_visual.gd` (POD_HEIGHT 0.30, TRUNK_RADIUS 0.22 of a 60 m
spire): four pods 18 m up on the trunk's surface at 45 + 90k degrees. The lead's 10-55 m band is
sampled at three heights so a spire only passes when the whole band is shootable, not one bulb.
"""
from __future__ import annotations

import math

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union
from shapely.strtree import STRtree

import checks_routes
import geom
import route3d
from sight import arena_surfaces

# MAP §2 / lead r6: the numbers this module is built on.
HIVE_H = 60.0             # m: the spire's height (SPEC §7.1, SYNTHESIS §enemies)
TRUNK_R = 0.22 * HIVE_H   # 13.2 m: hive_visual TRUNK_RADIUS - a real solid, it occludes
POD_BAND = (12.0, 30.0, 48.0)   # m up the trunk, inside the lead's 10-55 m band
POD_BEARINGS = 4          # four pods, 45 + 90k degrees (hive_visual pod_positions)
OPEN_R = 40.0             # m: open ground radius round the base, on its tier
AIR_H = 64.0              # m: clear air over that ground (pods to 48 m + the mech's reach)
RANGES = (70.0, 100.0, 140.0)   # m: flow's ORBIT_RANGES - the ring the bot actually uses
LIFTS = (8.0, 30.0)       # m over the pod: flow's ORBIT_LIFTS, and the mech can hover there
BEARINGS = 8              # flow's ORBIT_BEARINGS: 48 candidates a pod, the ones that failed
MIN_POSITIONS = 8         # lead r6: >= 8 firing positions with a clear line to a pod
MIN_APPROACHES = 3        # lead r6: >= 3 approach routes onto the open ground
APPROACH_REACH = 130.0    # m: how far out an approach is still counted
APPROACH_SECTOR = 60.0    # deg: routes in one sector are one approach, not two
APPROACH_DZ = 10.0        # m: an approach must arrive on the tier, not 40 m under it
WELL_KEEP = 4.0           # m: the well is cut a little wider than the ground it opens
# The ring where cover gives way to firing lines, = flow's nearest candidate range: a pod at
# 12 m is only shootable if the lanes are clear out to where the player actually stands, and
# C14 wants a 20 m piece within 60 m of the same spot. The lead's r6 note (open ground, clear
# lines to all four pods) wins inside this ring; `checks_arena` exempts it the way it already
# exempts a connector's keep-clear sphere, and `hives.recover_cover` fills cover outside it.
ASSAULT_R = 70.0
ASSAULT_DZ = 8.0          # m: the exemption is for the spire's own tier, not the ground under it

# The three objectives (MAP §2): arena, the tier its node stands on, and where the dossier puts
# it. The site search may move the last two numbers inside the arena; the tier never changes,
# because it is the graph's own datum (K3 +32, W4 +80, the Sky Garden +144).
HIVES = (
    {"id": "hive_a2", "arena": "A2", "tier": 32.0, "hint": (-470.0, -40.0)},
    {"id": "hive_a5", "arena": "A5", "tier": 80.0, "hint": (470.0, -200.0)},
    {"id": "hive_a6", "arena": "A6", "tier": 144.0, "hint": (-60.0, -450.0)},
)


def trunk(hive: dict) -> Polygon:
    """The spire's own plan footprint - a solid 26 m across that occludes the far pods."""
    return Point(hive["pos"][0], hive["pos"][1]).buffer(TRUNK_R, quad_segs=12)


def open_disc(hive: dict, radius: float = OPEN_R) -> Polygon:
    """The open ground a hive needs round its base, on its tier."""
    return Point(hive["pos"][0], hive["pos"][1]).buffer(radius, quad_segs=16)


def pods(hive: dict) -> list[tuple[float, float, float]]:
    """Every pod sample: four bearings x three heights up the trunk's surface."""
    x, y, z = hive["pos"]
    out: list[tuple[float, float, float]] = []
    for i in range(POD_BEARINGS):
        a = math.radians(45.0 + 360.0 * i / POD_BEARINGS)
        for h in POD_BAND:
            out.append((x + TRUNK_R * math.cos(a), y + TRUNK_R * math.sin(a), z + h))
    return out


def tier_surface(layout: dict, hive: dict) -> Polygon:
    """The walkable ground the spire stands on: the arena's surface at the hive's tier."""
    arena = next(a for a in layout["arenas"] if a["id"] == hive["arena"])
    tier = hive["pos"][2]
    parts = [poly for poly, z in arena_surfaces(arena, layout["decks"])
             if abs(z - tier) < 0.5]
    return unary_union(parts) if parts else Polygon()


def solids(layout: dict) -> tuple[STRtree, list[tuple[Polygon, float, float, str]]]:
    """Every opaque mass with its z span and its id: buildings, arena cover, decks, columns,
    and the three spires' own trunks (a pod on the far side of a 26 m trunk is not shootable)."""
    items: list[tuple[Polygon, float, float, str]] = []
    for b in layout["buildings"]:
        box = geom.rect(tuple(b["center"]), tuple(b["size"]), b.get("rot", 0.0))
        items.append((box, b["base_z"], b["base_z"] + b["height"], b["id"]))
    for arena in layout["arenas"]:
        for i, piece in enumerate(arena["cover"]):
            c = piece["center"]
            box = geom.rect((c[0], c[1]), (piece["size"][0], piece["size"][1]))
            items.append((box, c[2], c[2] + piece["size"][2], f"{arena['id']}_cover{i}"))
    for deck in layout["decks"]:
        area = geom.poly(deck["polygon"])
        for hole in deck.get("holes", []):
            area = area.difference(geom.poly(hole))
        items.append((area, deck["z"] - deck["thickness"], deck["z"], deck["id"]))
        for i, col in enumerate(deck.get("columns", [])):
            items.append((geom.rect((col[0], col[1]), (20.0, 20.0)), 0.0, deck["z"],
                          f"{deck['id']}_col{i}"))
    for hive in layout["hives"]:
        # 1 m in: the pods sit on the trunk's surface, and a ray that ends on a solid is not a
        # shot at it - only a ray that crosses the trunk counts as blocked by it.
        items.append((trunk(hive).buffer(-1.0), hive["pos"][2],
                      hive["pos"][2] + hive["height"], hive["id"]))
    return STRtree([i[0] for i in items]), items


def first_block(a: tuple[float, float, float], b: tuple[float, float, float],
                tree: STRtree, items: list) -> str:
    """The id of the first mass a 2.5D ray crosses, "" when the line is clear.

    Only a box the ray's own z crosses counts, so passing *under* a high deck is clear sky -
    the same rule `sight.visible` uses, with the id kept so a failure can name what is in the way.
    """
    ray = LineString([(a[0], a[1]), (b[0], b[1])])
    for idx in tree.query(ray):
        poly, z0, z1, ident = items[idx]
        if not poly.intersects(ray):
            continue
        cut = poly.intersection(ray)
        for part in getattr(cut, "geoms", [cut]):
            if part.is_empty:
                continue
            for px, py in (list(getattr(part, "coords", [])) or [(part.x, part.y)]):
                t = 0.0 if ray.length == 0 else ray.project(Point(px, py)) / ray.length
                z = a[2] + (b[2] - a[2]) * t
                if z0 - 0.5 < z < z1 + 0.5:
                    return ident
    return ""


def cover_index(layout: dict) -> dict[str, tuple[dict, int]]:
    """`A2_cover17` -> (the arena record, the piece's index), for the lane repair."""
    return {f"{a['id']}_cover{i}": (a, i)
            for a in layout["arenas"] for i in range(len(a["cover"]))}


def open_ground(hive: dict, tree: STRtree, items: list) -> list[str]:
    """The ids standing in the spire's 40 m of open ground or in the air over it.

    A solid only counts when it really shares the band: the plate the spire stands on is its
    floor, and a slab 80 m up is not "ground". `AIR_H` is the height the pods are shot through.
    """
    disc, z = open_disc(hive), hive["pos"][2]
    out: list[str] = []
    for idx in tree.query(disc):
        poly, z0, z1, ident = items[idx]
        if ident == hive["id"] or (z1 <= z + 1.0 and z0 >= z - 8.0):
            continue                      # the tier plate the spire stands on is its floor
        if z1 <= z + 1.0 or z0 >= z + AIR_H:
            continue
        if poly.intersects(disc):
            out.append(ident)
    return sorted(out)


def firing_grid(hive: dict, height: float) -> list[tuple[float, float, float]]:
    """flow's own search grid round a spire (`flow_debug_assault._firing_spot`).

    Eight bearings x three ranges x two lifts over the pod being shot - the 48 candidates the E2E
    bot tries before it gives up with "none of the 48 candidates can see the target". Measuring
    the same grid is the point: the layout is what made that search come up empty.
    """
    x, y, z = hive["pos"]
    out: list[tuple[float, float, float]] = []
    for i in range(BEARINGS):
        a = math.tau * i / BEARINGS
        for reach in RANGES:
            for lift in LIFTS:
                out.append((x + reach * math.cos(a), y + reach * math.sin(a), z + height + lift))
    return out


def _free(p: tuple[float, float, float], tree: STRtree, items: list) -> bool:
    """Is there air at the muzzle? A spot inside a mass is not a firing position."""
    here = Point(p[0], p[1])
    return not any(poly.contains(here) and z0 - 0.5 < p[2] < z1 + 0.5
                   for poly, z0, z1, _ in (items[j] for j in tree.query(here)))


def approaches(layout: dict, hive: dict, strict: bool = True) -> list[tuple[str, float]]:
    """(route id, bearing) for every INBOUND route that really arrives on the spire's tier.

    `strict=False` is the SITE-SEARCH reading: it counts the same routes without asking whether
    each one passes a-d. `hives.reserve` uses it so the three spires stay where the last round put
    them - the strict reading moves them, and a moved spire re-rolls the cover and the sky graph
    behind it (conflict map E7). The gate (`checks_hives`) always uses the strict reading.

    r8 (lead, item 4e) replaced the 2D version, which counted an outbound drop, a canopy roof and
    a straight from->to line in plan, and so passed on a tier nothing could reach. A route counts
    now only when

    * it arrives ON the tier - its `to` (or either end, if it is bidirectional) is within
      `APPROACH_DZ` of the hive's z and inside `APPROACH_REACH` of the spire;
    * it passes `checks_routes` a-d, so it is a route a mech can take and not a record;
    * its start is reachable from H0 without walking over the tier's own nodes, so a route that
      begins on the tier (the far end of an edgejump out of it) is not an approach to it;
    * and it crosses the ring round the open ground, which is what gives it its bearing.
    """
    base = Point(hive["pos"][0], hive["pos"][1])
    z = hive["pos"][2]
    ring = base.buffer(APPROACH_REACH, quad_segs=16).difference(
        base.buffer(OPEN_R, quad_segs=16))
    dead = checks_routes.failing(layout) if strict else set()
    tier_nodes = _tier_nodes(layout, hive)
    reachable = _reachable_from_h0(layout, tier_nodes) if strict else None
    rows: list[tuple[str, float]] = []
    for con in layout["connectors"]:
        if con.get("usable") is False or con["id"] in dead:
            continue
        src, dst = con["edge"]
        inbound = abs(float(con["to"][2]) - z) <= APPROACH_DZ
        if not inbound and not con.get("oneway"):
            inbound = abs(float(con["from"][2]) - z) <= APPROACH_DZ
        if not inbound or not con.get("oneway") and dst not in tier_nodes and src in tier_nodes:
            continue
        far = src if abs(float(con["to"][2]) - z) <= APPROACH_DZ else dst
        if reachable is not None and far not in reachable:
            continue
        _add_route(rows, base, _shape(con), con["id"], ring)
    for group in ("viaducts", "rails"):
        for item in layout[group]:
            if abs(item["z"] - z) > APPROACH_DZ:
                continue
            nodes = item.get("nodes") or []
            if reachable is not None and nodes and not any(n in reachable for n in nodes):
                continue
            _add_route(rows, base, geom.line(item["points"]), item["id"], ring)
    return rows


def _shape(con: dict):
    """The route's real plan line: its path, or an edgejump's arc."""
    return geom.line([[p[0], p[1]] for p in route3d.path_of(con)])


def _tier_nodes(layout: dict, hive: dict) -> set[str]:
    """The graph nodes that stand on the spire's own tier (its plate), which an approach may
    not start from - a route that begins there is a way OUT, not a way in."""
    out: set[str] = set()
    for con in layout["connectors"]:
        for end, node in zip(("from", "to"), con["edge"]):
            if abs(float(con[end][2]) - hive["pos"][2]) <= APPROACH_DZ and \
                    math.dist(con[end][:2], hive["pos"][:2]) <= APPROACH_REACH:
                out.add(node)
    return out


def _reachable_from_h0(layout: dict, blocked: set[str]) -> set[str]:
    """Every node H0 can walk to without setting foot on the tier's own nodes."""
    adjacency: dict[str, set[str]] = {}
    for con in layout["connectors"]:
        if con.get("usable") is False:
            continue
        a, b = con["edge"]
        adjacency.setdefault(a, set()).add(b)
        if not con.get("oneway"):
            adjacency.setdefault(b, set()).add(a)
    for group in ("streets", "viaducts", "rails", "tunnels"):
        for item in layout[group]:
            ends = item.get("nodes")
            if not ends:
                continue
            adjacency.setdefault(ends[0], set()).add(ends[1])
            adjacency.setdefault(ends[1], set()).add(ends[0])
    seen, stack = {"H0"}, ["H0"]
    while stack:
        for nxt in adjacency.get(stack.pop(), ()):
            if nxt in seen or nxt in blocked:
                continue
            seen.add(nxt)
            stack.append(nxt)
    return seen


def _add_route(rows: list[tuple[str, float]], base: Point, shape, ident: str,
               ring: Polygon) -> None:
    """A route counts when it crosses the ring round the open ground; its bearing is where.

    Most of them arrive *at* the spire (a lift or a catapult lands on the node), so the route is
    clipped to the ring first: what matters is the direction the player comes in from.
    """
    ring = shape.intersection(ring)
    if ring.is_empty:
        return
    near = ring.representative_point() if ring.geom_type != "Point" else ring
    rows.append((ident, math.degrees(math.atan2(near.y - base.y, near.x - base.x)) % 360.0))


def sectors(rows: list[tuple[str, float]]) -> list[list[tuple[str, float]]]:
    """Group the routes by bearing: two ways in from the same 60 deg window are one approach."""
    out: list[list[tuple[str, float]]] = []
    for ident, bearing in sorted(rows, key=lambda r: r[1]):
        if out and min(_arc(bearing, b) for _, b in out[-1]) < APPROACH_SECTOR:
            out[-1].append((ident, bearing))
        else:
            out.append([(ident, bearing)])
    return out


def _arc(a: float, b: float) -> float:
    """The angle between two bearings, 0-180."""
    return abs((a - b + 180.0) % 360.0 - 180.0)


def verify(layout: dict, hive: dict, tree: STRtree | None = None,
           items: list | None = None) -> dict:
    """Measure one spire against the lead's r6 rule, from the layout alone.

    Returns the numbers the check prints and the builder sorts candidate sites on: the ids
    standing in the open ground, how many of the ring positions can see each pod, and how many
    separate ways in the ground has.
    """
    tree, items = solids(layout) if tree is None else (tree, items)
    blocked = open_ground(hive, tree, items)
    targets = pods(hive)
    per_pod = []
    spots = 0
    for pod in targets:
        grid = firing_grid(hive, pod[2] - hive["pos"][2])
        free = [p for p in grid if _free(p, tree, items)]
        spots = max(spots, len(free))
        per_pod.append(sum(1 for s in free if not first_block(s, pod, tree, items)))
    routes = approaches(layout, hive)
    groups = sectors(routes)
    problems: list[str] = []
    if blocked:
        problems.append(f"{len(blocked)} solids in the {OPEN_R:.0f} m of open ground or the "
                        f"{AIR_H:.0f} m over it: {blocked[:4]}")
    if min(per_pod, default=0) < MIN_POSITIONS:
        worst = per_pod.index(min(per_pod)) if per_pod else 0
        problems.append(f"pod {worst // len(POD_BAND)} at {POD_BAND[worst % len(POD_BAND)]:.0f} m "
                        f"is shootable from {min(per_pod, default=0)} of {len(firing_grid(hive, 0))} "
                        f"positions (need {MIN_POSITIONS})")
    if len(groups) < MIN_APPROACHES:
        problems.append(f"{len(groups)} approach routes (need {MIN_APPROACHES}): "
                        f"{[r[0] for r in routes][:6]}")
    return {"id": hive["id"], "pos": hive["pos"], "tier": hive["pos"][2], "blocked": blocked,
            "positions": spots, "per_pod": per_pod, "worst": min(per_pod, default=0),
            "routes": len(groups), "route_ids": [r[0] for r in routes],
            "ok": not problems, "problems": problems}


def in_assault_ring(sample: tuple[float, float, float], layout: dict,
                    eye: float = 0.0) -> bool:
    """Does this standing sample sit in a spire's assault ring, on that spire's own tier?

    `eye` is the height the sample was raised by (C14 samples stand 12 m over their surface), so
    the tier comparison is against the ground the sample is really on.
    """
    for hive in layout["hives"]:
        x, y, z = hive["pos"]
        if abs(sample[2] - eye - z) > ASSAULT_DZ:
            continue
        if math.dist(sample[:2], (x, y)) <= ASSAULT_R:
            return True
    return False
