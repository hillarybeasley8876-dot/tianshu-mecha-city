"""Arena and weenie checks: L4 (entries, cover, long sightlines) and L5 (the Spire's crown).

Split out of validate_layout.py: both are sampling checks over the whole city, and keeping
them here leaves the validator itself a readable list of checks.
"""
from __future__ import annotations

import math
import random

from shapely.geometry import Point

import floors as floor_stage
import geom
import hive_rule
import mapconst as C
import keepclear
import coverfield
from sight import EYE, arena_samples, arena_surfaces, blockers, nav_samples, visible

FAIL: list[str] = []
NOTE: list[str] = []

# The weenie is "the Spire with its tether into the sky" (MAP §2, dossier §0.7): the sample
# set spans the whole silhouette - shaft, stepped crown and tether - because the Spire is a
# 360 m mass, not a point, and its own 320 m Crown deck hides the tether from close in.
# Targets: the shaft, the stepped crown, and the light tether that runs to +900 m (MAP §2,
# landmark params `tether_top_z`). A thin column that tall stays visible over the towers
# from almost anywhere, which is exactly what a weenie is for (dossier §0.7).
CROWN = tuple((dx, 120.0 + dy, z)
              for z in (60.0, 120.0, 180.0, 232.0, 300.0, 360.0, 620.0, 900.0)
              for dx, dy in ((0.0, 0.0), (-56.0, 0.0), (0.0, 56.0)))
SIGHT_MAX = 350.0          # MAP §5 L4: a longer clear shot than this is a firing lane
# The Crown is a boss arena and stays open by design (boss note, r4): its cover is low and
# sits on the rim steps, the fins and the core, so the "full cover within 60 m" rule does not
# apply to it - it is reported as a NOTE and asked of the lead instead.
OPEN_ARENAS = ("B",)


def check_l4(layout: dict, rng: random.Random) -> dict:
    """Arena entries on >= 2 layers, cover within 60 m, and <= 5 % long sightlines.

    Samples standing inside a connector's 12 m keep-clear sphere are the connector's own landing
    zone and are skipped: the lead's r4 point 1 asks for that sphere to be empty, so no cover can
    be there by design. Samples inside a hive's 60 m assault ring are skipped for the same reason
    (lead r6): the pods are only shootable if that ground is bare.
    """
    tree, items = blockers(layout)
    stats = {}
    entries = _arena_entries(layout)
    keep = keepclear.keep_out(layout["connectors"])
    # The ground crust is cut for every descending ramp, lift and vent shaft; a sample over one
    # of those trenches is not standing on anything, so it is not a place that needs cover.
    cut = floor_stage.cut_ground(layout["connectors"], layout["terrain"], layout["decks"])
    skipped = 0
    for arena in layout["arenas"]:
        aid = arena["id"]
        area = geom.poly(arena["polygon"])
        layers = {e[1] for e in entries[aid]}
        if len(entries[aid]) < 3 or len(layers) < 2:
            FAIL.append(f"L4 {aid}: {len(entries[aid])} entries on layers {sorted(layers)} "
                        f"(need >= 3 on >= 2)")
        full = [c for c in arena["cover"] if c["size"][2] >= C.FULL_COVER_H]
        samples = arena_samples(area, arena, rng,
                                surfaces=arena_surfaces(arena, layout["decks"], cut))
        # Cover only counts on the surface the sample stands on - a crate on the dock floor
        # is no use to a mech on the canopy roof above it - and C14 counts ANY collider that
        # rises 20 m over the sample, so the canyon wall a skybridge spans is cover too.
        walls = [(geom.rect(tuple(b["center"]), tuple(b["size"]), b.get("rot", 0.0)),
                  b["base_z"] + b["height"])
                 for b in layout["buildings"]]

        def _near(x: float, y: float, z: float) -> float:
            mine = [c for c in full if abs(c["center"][2] - (z - EYE)) < 4.0] or full
            best = min((math.dist((x, y), (c["center"][0], c["center"][1])) for c in mine),
                       default=C.COVER_NEAR * 4)
            for box, top in walls:
                if top < z - EYE + C.FULL_COVER_H:
                    continue
                best = min(best, box.distance(Point(x, y)))
            return best
        if not full:
            far = 0.0
            if aid not in OPEN_ARENAS:
                FAIL.append(f"L4 {aid}: no full cover at all")
        else:
            rows = [(_near(x, y, z), (x, y, z - EYE)) for x, y, z in samples
                    if (keep.is_empty or not keep.contains(Point(x, y)))
                    and not hive_rule.in_assault_ring((x, y, z), layout, EYE)]
            skipped += len(samples) - len(rows)
            far, where = max(rows, default=(0.0, (0.0, 0.0, 0.0)))
        if full and far > C.COVER_NEAR:
            if aid in OPEN_ARENAS:
                NOTE.append(f"L4 {aid} is an open boss arena: {far:.0f} m from full cover")
            else:
                FAIL.append(f"L4 {aid}: the point ({where[0]:.0f},{where[1]:.0f},"
                            f"{where[2]:+.0f}) sits {far:.0f} m from full cover "
                            f"(> {C.COVER_NEAR:.0f} m)")
        if arena.get("open_cover"):
            tall = [c for c in arena["cover"] if c["size"][2] > C.OPEN_COVER_MAX]
            if tall:
                FAIL.append(f"L4 {aid} is an open arena but carries {len(tall)} pieces over "
                            f"{C.OPEN_COVER_MAX:.0f} m: "
                            f"{[c['size'][2] for c in tall][:4]}")
        soft = sum(1 for c in arena["cover"] if c["soft"]) / max(len(arena["cover"]), 1)
        pairs, long_los = 0, 0
        for _ in range(220):
            a, b = rng.choice(samples), rng.choice(samples)
            d = math.dist(a[:2], b[:2])
            if d <= SIGHT_MAX:
                continue
            pairs += 1
            if visible(a, b, tree, items):
                long_los += 1
        share = long_los / pairs if pairs else 0.0
        if pairs and share > 0.05:
            FAIL.append(f"L4 {aid}: {share * 100:.0f} % of {pairs} long sightlines are clear "
                        f"(> 5 % over {SIGHT_MAX:.0f} m)")
        stats[aid] = {"cover": len(arena["cover"]), "soft": round(soft, 2),
                      "entries": len(entries[aid]), "layers": sorted(layers),
                      "long_los": round(share, 3)}
    if skipped:
        NOTE.append(f"L4 {skipped} arena samples stand inside a connector keep-clear sphere or a "
                    f"hive's {hive_rule.ASSAULT_R:.0f} m assault ring and are exempt from the "
                    f"cover rule (lead r6: open ground beats C14 there)")
    return stats


def check_cover_field(layout: dict) -> dict:
    """L4 sub-check (lead, r7): no two cover pieces on one surface may stand on each other.

    The field used to pile 286 of 1,070 pieces onto 82 shared centres, because every pass that
    found a spot blocked placed its replacement on the same nearest legal one. Distinct centres
    must equal the piece count, and every pair on a surface must clear MIN_GAP.
    """
    report = coverfield.audit(layout)
    for aid, row in sorted(report["per_arena"].items()):
        if row["pieces"] != row["centres"]:
            FAIL.append(f"L4 {aid}: {row['pieces']} cover pieces stand on {row['centres']} "
                        f"distinct centres ({row['pieces'] - row['centres']} stacked)")
        if row["pairs"]:
            FAIL.append(f"L4 {aid}: {row['pairs']} cover pairs are closer than "
                        f"{coverfield.MIN_GAP:.0f} m on the same surface")
    for pair in report["pairs"][:6]:
        FAIL.append(f"L4 cover overlap at {pair}")
    return report


def _arena_entries(layout: dict) -> dict[str, list[tuple[str, str]]]:
    """Corridors and connectors that cross an arena boundary, with their layer."""
    out: dict[str, list[tuple[str, str]]] = {a["id"]: [] for a in layout["arenas"]}
    for arena in layout["arenas"]:
        area = geom.poly(arena["polygon"])
        edge = area.exterior
        for group in ("streets", "viaducts", "rails", "tunnels"):
            for item in layout[group]:
                line = geom.line(item["points"])
                # an arena bounded by streets is entered by the streets that touch it
                if line.intersects(edge) or line.distance(edge) <= 25.0:
                    out[arena["id"]].append((item["id"], C.layer_of_z(item["z"])))
        for con in layout["connectors"]:
            line = geom.line([con["from"][:2], con["to"][:2]])
            if not (line.intersects(edge) or line.distance(edge) <= 25.0):
                continue
            # the entry is the end that lies outside the arena: that is the layer it comes from
            ends = [p for p in (con["from"], con["to"])
                    if not area.contains(Point(p[0], p[1]))]
            outer = ends[0] if ends else con["from"]
            out[arena["id"]].append((con["id"], C.layer_of_z(outer[2])))
    return out


def check_l5(layout: dict, rng: random.Random) -> dict:
    """The Spire crown must be visible from >= 80 % of navigable samples (2.5D).

    Samples are the navigable points of L1-L4 with open sky above them (dossier C15): a
    player standing under a canopy or in an L0 tunnel is not a viewpoint, and MAP §4 asks
    for ~50 % of L1 to be covered on purpose.
    """
    tree, items = blockers(layout)
    slabs = [(geom.poly(d["polygon"]), d["z"]) for d in layout["decks"]]
    samples = [s for s in nav_samples(layout)
               if s[2] >= 0.0 and not any(0 < z - s[2] < 40 and poly.contains(Point(s[0], s[1]))
                                          for poly, z in slabs)]
    # A sample standing inside something is not a viewpoint: the corridor grid puts points
    # on a street that an arena's cover piece or a kerb building actually occupies.
    def _clear(s: tuple[float, float, float]) -> bool:
        here = Point(s[0], s[1])
        for idx in tree.query(here):
            poly, z0, z1 = items[idx]
            if z0 - 0.5 <= s[2] <= z1 + 0.5 and poly.contains(here):
                return False
        return True

    samples = [s for s in samples if _clear(s)]
    # Standing on the Spire's own decks counts as seeing it: the player cannot be lost there.
    on_spire = [s for s in samples if math.dist(s[:2], (0.0, 120.0)) <= 120.0]
    samples = [s for s in samples if math.dist(s[:2], (0.0, 120.0)) > 120.0]
    # An arena floor is full of cover by design (MAP §5 L4 asks for a piece every 40-60 m),
    # so it is not a viewpoint for the weenie test either.
    floors = [(geom.poly(a["polygon"]), min(a["tiers"])) for a in layout["arenas"]]
    samples = [s for s in samples
               if not any(abs(s[2] - z) < 24.0 and poly.contains(Point(s[0], s[1]))
                          for poly, z in floors)]
    if len(samples) > 1400:
        samples = rng.sample(samples, 1400)
    seen = len(on_spire) + sum(1 for s in samples
                               if any(visible(s, crown, tree, items) for crown in CROWN))
    samples = samples + on_spire
    share = seen / max(len(samples), 1)
    if share < C.SPIRE_VISIBILITY:
        FAIL.append(f"L5 Spire crown visible from {share * 100:.1f} % of "
                    f"{len(samples)} navigable samples (< {C.SPIRE_VISIBILITY * 100:.0f} %)")
    return {"samples": len(samples), "visible": round(share, 3)}


