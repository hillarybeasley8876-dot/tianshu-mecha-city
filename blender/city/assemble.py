"""Emit the whole city into render/solid Kits for one skin setting (city-build).

Split out of `build_city.py` so a second caller can run exactly the same assembly twice — once
skinned, once not — and diff the collision it produced (`blender/city/probe_skin.py`). Nothing
here writes a file; `build_city.py` owns the tiles, the exports and the report.
"""
import random

from kit import (buildings, connectors, corridors, decks, landmarks, passage, props,
                 solid, terrain as terrain_mod)
from kit.builder import Kit
from lib import common

## Deck kinds that belong to a landmark rather than to the ordinary city: the Crown disc is what
## the Spire carries, so it has to travel with the landmark chunks (r8 item 1).
LANDMARK_DECKS = ("crown",)


def ground_fn(lay):
    """Terrain height at (x, y): the plateau north of the crest, the lower city elsewhere."""
    crest = lay.terrain["escarpment"]["crest"]
    height = float(lay.terrain["escarpment"]["height"])

    def ground(x, y):
        for a, b in zip(crest, crest[1:]):
            if a[0] - 1e-6 <= x <= b[0] + 1e-6:
                t = (x - a[0]) / max(1e-6, b[0] - a[0])
                return height if y > a[1] + (b[1] - a[1]) * t else 0.0
        return height if y > crest[-1][1] else 0.0

    return ground


def populate(lay, ground, skin, slots, podium_walls=None, terrain=True):
    """Build every structure in `lay` -> (render, structures, landmarks, solids x3, counts).

    `skin` decides which structures emit no render mesh (blender/city/skin.py); it can never
    change a collider, which is what `probe_skin.py` measures. `slots` and `podium_walls` are
    appended to in place — pass throwaway lists for a diff run.

    The landmarks (and the Crown disc they carry) go into their OWN Kit and Solids: they are the
    only geometry that must still be itself from every vista, so `city.gd` gives their chunks a
    2 km visibility range instead of the 450 m detail cut and `tiles.py` keeps their collision
    mass out of the tile HLOD proxy (reviews/city-build-r8.md item 1).
    """
    podium_walls = podium_walls if podium_walls is not None else []
    render = Kit("city")
    solids = solid.Solids()
    counts = {}

    if terrain:
        terrain_mod.build(render, solids, lay, common.collection("mc_scratch"), podium_walls)
        counts["terrain"] = 1

    through = passage.through_index(lay)
    skinned = 0
    for b in lay.buildings:
        rng = random.Random("%s:%s" % (lay.meta["seed"], b["id"]))
        hit = skin.building(b["id"])
        skinned += 1 if hit else 0
        if hit:
            skin.note(b)
        buildings.build(render, solids, b, rng, slots, through, skinned=hit)
    counts["buildings"] = len(lay.buildings)
    counts["skinned"] = skinned
    counts["through"] = sum(1 for v in through.values() for _ in v)

    sub = Kit("structures")
    sub_solids = solid.Solids()
    corridors.build(sub, sub_solids, lay, skin)
    decks.build(sub, sub_solids, lay, ground, skin, skip_kinds=LANDMARK_DECKS)
    connectors.build(sub, sub_solids, lay)
    props.cover(sub, sub_solids, lay, slots, skin)
    props.hives(sub, sub_solids, lay, slots)

    lm = Kit("landmarks")
    lm_solids = solid.Solids()
    landmarks.build(lm, lm_solids, lay, slots)
    decks.build(lm, lm_solids, lay, ground, skin, only_kinds=LANDMARK_DECKS)

    counts["streets"] = len(lay.streets)
    counts["viaducts"] = len(lay.viaducts)
    counts["rails"] = len(lay.rails)
    counts["tunnels"] = len(lay.tunnels)
    counts["decks"] = len(lay.decks)
    counts["connectors"] = len(lay.connectors)
    counts["landmarks"] = len(lay.landmarks)
    return render, sub, lm, solids, sub_solids, lm_solids, counts
