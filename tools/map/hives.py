"""Hive spire siting: reserve the open ground, open the well, repair what lands late.

The rule this builds to lives in `hive_rule.py` (open ground, pods, approach routes) and the
check that enforces it in `checks_hives.py`; this module is the generator's side of it.

Order matters, and it is the same order the connector keep-clear spheres and the spawn sockets
use: the sites are chosen *before* anything solid exists, they are handed to every stage that
places a solid as a keep-out, and a late pass re-measures the finished layout and repairs it.
"""
from __future__ import annotations

import copy
import math
import random

from shapely.geometry import Point, Polygon
from shapely.ops import unary_union

import geom
import coverfield
import mapconst as C
from hive_repair import clear_ground, clear_lanes, recover_cover
from hive_rule import (AIR_H, ASSAULT_R, HIVE_H, HIVES, MIN_APPROACHES, OPEN_R, WELL_KEEP,
                       approaches, open_disc, sectors, tier_surface, verify)

SITE_STEP = 12.0           # m: the candidate grid inside an arena
NODE_GUARD = 34.0          # m: the fallback plate a graph node keeps (corridors.py's own guard)
NODE_KEEP = 20.0           # m: the plate a node keeps when the well can be cut round it
PLATFORM_MIN = 10.0        # m: deck a node must still have round it after the cut
MIN_PIECE = 400.0          # m2: a deck sliver left by the well is not a deck
CORNICE_DROP = 2.0         # m: a building in the open ground stops just under the tier


def wells(sites: list[dict]) -> list[tuple[Polygon, float]]:
    """(well polygon, 0 m) as a canopy height cap: no slab may ever roof a hive's ground."""
    return [(open_disc(s, OPEN_R + WELL_KEEP), 0.0) for s in sites]


def cornice_caps(sites: list[dict]) -> list[tuple[Polygon, float]]:
    """(open ground, highest top allowed) for the fill: no mass rises into a hive's ground."""
    return [(open_disc(s, OPEN_R), s["pos"][2] - CORNICE_DROP) for s in sites]


def arena_stubs(rules: dict, outlines: dict) -> list[dict]:
    """Minimal arena records, so the shared geometry helpers can run before the real ones exist."""
    out = []
    for aid, spec in rules["arenas"].items():
        out.append({"id": aid, "polygon": outlines[aid],
                    "tiers": [float(t) for t in spec["tiers"]],
                    "main_tier": float(spec["main_tier"]), "cover": []})
    return out


def stub_layout(rules: dict, outlines: dict, parts: dict, decks: list[dict],
                cons: list[dict], nodes: dict) -> dict:
    """A layout-shaped dict of what exists when the sites are chosen.

    `hive_rule` reads only the layout, so the site search measures the same way the late repair
    and the L4 check will - no second, more forgiving geometry. `nodes` is the graph's, kept for
    the plate guard: a well is never cut out of the deck a node stands on.
    """
    layout = {"arenas": arena_stubs(rules, outlines), "decks": decks, "connectors": cons,
              "buildings": [], "nodes": nodes}
    for group in ("streets", "viaducts", "rails", "tunnels"):
        layout[group] = parts[group]
    return layout


def candidates(layout: dict, spec: dict) -> list[tuple[tuple, float, float]]:
    """Every legal site for one spire, best first: (sort key, x, y).

    Legal means 40 m of its own tier under the open ground and inside the arena. The sort key is
    (approach routes met?, area of a graph node's plate that would have to be cut, deck area to
    cut away above it, distance from the dossier's own position) - so the spire stays where the
    level design put it unless the ground says no. The second term matters because the well can
    never be cut out of the plate a node stands on: that plate is the node's own platform.
    """
    arena = next(a for a in layout["arenas"] if a["id"] == spec["arena"])
    area = geom.poly(arena["polygon"])
    tier = float(spec["tier"])
    hive = {"id": spec["id"], "arena": spec["arena"], "height": HIVE_H,
            "pos": [spec["hint"][0], spec["hint"][1], tier]}
    ground = tier_surface(layout, hive)
    above = [(geom.poly(d["polygon"]), d["z"]) for d in layout["decks"]
             if tier + 0.5 < d["z"] <= tier + AIR_H]
    guard = unary_union([Point(n["pos"][0], n["pos"][1]).buffer(NODE_KEEP)
                         for n in layout["nodes"].values()
                         if tier + 0.5 < n["pos"][2] <= tier + AIR_H])
    out: list[tuple[tuple, float, float]] = []
    minx, miny, maxx, maxy = area.bounds
    y = miny
    while y <= maxy:
        x = minx
        while x <= maxx:
            disc = Point(x, y).buffer(OPEN_R, quad_segs=8)
            if not ground.contains(disc) or not area.contains(disc):
                x += SITE_STEP
                continue
            cut = sum(disc.intersection(p).area for p, _ in above)
            hive["pos"] = [round(x, 1), round(y, 1), tier]
            routes = len(sectors(approaches(layout, hive, strict=False)))
            far = math.dist((x, y), spec["hint"])
            out.append(((0 if routes >= MIN_APPROACHES else 1,
                         round(disc.intersection(guard).area) if not guard.is_empty else 0,
                         round(cut), round(far)), x, y))
            x += SITE_STEP
        y += SITE_STEP
    out.sort(key=lambda row: row[0])
    return out


def reserve(rules: dict, outlines: dict, decks: list[dict], parts: dict,
            cons: list[dict], nodes: dict) -> tuple[list[dict], Polygon]:
    """The three sites and the keep-out every solid stage must respect.

    Runs right after the arena outlines: before the canopies, the cover, the buildings and the
    deck columns, so nothing has to be deleted afterwards that was never legal.
    """
    layout = stub_layout(rules, outlines, parts, decks, cons, nodes)
    sites: list[dict] = []
    for spec in HIVES:
        rows = candidates(layout, spec)
        if not rows:
            raise SystemExit(f"{spec['id']}: no site in {spec['arena']} has "
                             f"{OPEN_R:.0f} m of tier {spec['tier']:+.0f} under it")
        _, x, y = rows[0]
        sites.append({"id": spec["id"], "arena": spec["arena"], "height": HIVE_H,
                      "pos": [round(x, 1), round(y, 1), float(spec["tier"])]})
    keep = unary_union([open_disc(s, OPEN_R + WELL_KEEP) for s in sites])
    return sites, keep


def punch(decks: list[dict], sites: list[dict], nodes: dict) -> int:
    """Open each spire's light well through the decks above its tier.

    A hive under the Knot's flyover or the Foundry's L3 plate has no sky: the pods cannot be seen
    from above and the ground cannot see them. The plate is cut back over the open ground, the
    way `corridors.perforate_decks` cuts it back over a street - but a graph node standing on
    that plate keeps its platform: first by 20 m, and by the full 34 m guard that stage uses if
    20 m would leave it on a ledge.
    """
    cut = 0
    for site in sites:
        tier = site["pos"][2]
        well = open_disc(site, OPEN_R + WELL_KEEP)
        for deck in list(decks):
            if not (tier + 0.5 < deck["z"] <= tier + AIR_H):
                continue
            area = geom.poly(deck["polygon"])
            if not area.intersects(well):
                continue
            mine = [n for n in nodes.values()
                    if abs(n["pos"][2] - deck["z"]) <= C.ON_DATUM_TOL
                    and area.contains(Point(n["pos"][0], n["pos"][1]))]
            keep = area.difference(well.difference(_platforms(mine, NODE_KEEP)))
            if not _nodes_kept(keep, mine):
                keep = area.difference(well.difference(_platforms(mine, NODE_GUARD)))
            if _install(deck, keep, decks, site["id"]):
                cut += 1
    return cut


def _platforms(mine: list[dict], radius: float) -> Polygon:
    """The plate every node on this deck keeps, whatever the well takes."""
    if not mine:
        return Polygon()
    return unary_union([Point(n["pos"][0], n["pos"][1]).buffer(radius) for n in mine])


def _nodes_kept(keep: Polygon, mine: list[dict]) -> bool:
    """Does every node still have a platform with PLATFORM_MIN of deck round it?"""
    return all(not keep.is_empty and keep.contains(Point(n["pos"][0], n["pos"][1]))
               and Point(n["pos"][0], n["pos"][1]).distance(keep.boundary) >= PLATFORM_MIN
               for n in mine)


def _install(deck: dict, keep: Polygon, decks: list[dict], hive_id: str) -> bool:
    """Write a cut deck back, splitting it into islands when the well cut it in two."""
    if keep.is_empty:
        return False
    parts = sorted((g for g in getattr(keep, "geoms", [keep])
                    if isinstance(g, Polygon) and g.area > MIN_PIECE), key=lambda g: -g.area)
    if not parts:
        return False
    for index, part in enumerate(parts):
        target = deck if index == 0 else dict(deck, id=f"{deck['id']}_w{index}")
        target["polygon"] = [[round(x, 1), round(y, 1)] for x, y in part.exterior.coords[:-1]]
        target["holes"] = [[[round(x, 1), round(y, 1)] for x, y in ring.coords[:-1]]
                           for ring in part.interiors]
        target["open_for"] = sorted(set(target.get("open_for", []) + [hive_id]))
        if index:
            decks.append(target)
    return True


def _rank(report: dict) -> tuple:
    """Best trial first: passes, then open ground, then approach routes, then the worst pod."""
    return (0 if report["ok"] else 1, len(report["blocked"]),
            0 if report["routes"] >= MIN_APPROACHES else 1, -report["worst"])


def build(sites: list[dict], base: dict, nodes: dict, rules: dict, rng: random.Random,
          keep: coverfield.KeepOut, trials: int = 8) -> tuple[list[dict], list[str]]:
    """Re-measure each site on the finished layout and repair what landed in it.

    `base` is the layout as it stands at the end of the build (arenas, decks, buildings,
    corridors, connectors, the graph's nodes). Each candidate is tried on a copy - well punched,
    ground cleared, firing lanes opened - and the first that passes `verify` is committed, so
    the city keeps only what the trial needed. If none passes, the best is kept and its problems
    are returned: the layout is written anyway and L4 reports exactly what is wrong with it.
    """
    notes: list[str] = []
    placed: dict[str, dict] = {}
    for site in sites:
        spec = {"id": site["id"], "arena": site["arena"], "tier": site["pos"][2],
                "hint": (site["pos"][0], site["pos"][1])}
        base["hives"] = list(placed.values()) + [s for s in sites if s["id"] != site["id"]
                                                 and s["id"] not in placed]
        best: tuple[dict, dict, dict] | None = None
        for _, x, y in candidates(base, spec)[:trials]:
            trial = copy.deepcopy(base)
            hive = dict(site, pos=[round(x, 1), round(y, 1), site["pos"][2]])
            trial["hives"] = [h for h in base["hives"] if h["id"] != site["id"]] + [hive]
            punch(trial["decks"], [hive], nodes)
            clear_ground(trial, hive)
            clear_lanes(trial, hive)
            recover_cover(trial, hive, rules, rng, keep)
            report = verify(trial, hive)
            if best is None or _rank(report) < _rank(best[1]):
                best = (trial, report, hive)
            if report["ok"]:
                break
        if best is None:
            raise SystemExit(f"{site['id']}: no candidate site at all in {site['arena']}")
        trial, report, hive = best
        if not report["ok"]:
            notes.append(f"{site['id']} still fails: " + "; ".join(report["problems"]))
        elif (hive["pos"][0], hive["pos"][1]) != (site["pos"][0], site["pos"][1]):
            notes.append(f"{site['id']} moved "
                         f"{math.dist(hive['pos'][:2], site['pos'][:2]):.0f} m to "
                         f"{hive['pos'][0]:.0f},{hive['pos'][1]:.0f} for open ground")
        base["arenas"], base["decks"] = trial["arenas"], trial["decks"]
        placed[site["id"]] = hive
    base["hives"] = [dict(placed[s["id"]], open_r=OPEN_R, assault_r=ASSAULT_R, tier=s["pos"][2])
                     for s in sites]
    return base["hives"], notes
