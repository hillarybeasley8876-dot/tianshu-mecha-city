"""Godot-side marker data (city-build).

Godot cannot read `data/map/*.json` (it is outside `res://`), so the Blender build writes a
trimmed `game/world/city/layout.json` with exactly what `world/city.gd` needs: player start,
spawn zones, arenas, landmarks, anchors, hives, vistas, nav links, the sky graph and the prop
slots left for city-art. Coordinates stay in Blender convention here; city.gd converts.
"""
import json
import os

# Edges a navmesh can walk (ramp/street/rail); everything else needs a NavigationLink3D.
WALK_KINDS = {"ramp", "path", "rail"}
LINK_KINDS = {"edgejump", "drop", "vcat", "lcat", "vent", "lift", "stairs"}


def write(lay, slots, path, podium_walls=(), skin=None, ring_slots=()):
    data = {
        "meta": {"source": "data/map/city_layout.json", "seed": lay.meta["seed"],
                 "version": lay.meta["version"],
                 "revision": lay.meta.get("revision")},
        "bounds": lay.bounds,
        "player_start": lay.player_start,
        "spawn_zones": _spawn_zones(lay),
        # The 96 skyline-ring towers (reviews/city-build-r8.md item 3): centre, size, height and
        # the index into `city_layout.json["skyline"]`, so city-kit can drop a far model on any of
        # them. `dropped: true` marks the ones a `ring` row already removed from `skyline.glb`.
        "skyline_ring": list(ring_slots),
        # Escarpment retaining walls as facade footprints (city-art r3). They are terrain, not
        # buildings, so they have no row in the design layout and city-art's facade mask gives
        # them no windows at eye level — around the A4 megablock quarter they are the 32 m face a
        # player reads as the district's podium. Each entry is a rotated footprint in the same
        # shape as a `buildings` row, plus `outward` (the face normal away from the plateau) so a
        # shader can tell which side is facade. Merge these into the mask input alongside
        # `design["buildings"]`.
        "podium_walls": list(podium_walls),
        # Deck and viaduct EDGES (lead 12:10): the parapet / barrier polylines with their heights,
        # so city-kit can lay kit railings along them instead of the brown box fence. One row per
        # edge: {id, points [[x, y], ...], z, kind, closed, height, thickness}. Blender metres.
        "edges": _edges(lay),
        # The C18 top-face gate's inputs (lead r9): every walkable floor the layout declares and
        # every mass that stands on one. Without these the gate would have to read
        # `data/map/city_layout.json`, which is outside `res://` and invisible to Godot.
        "floors": _floors(lay, skin),
        "blocks": _blocks(lay),
        # Which structures were built without a render mesh because city-kit skins them.
        # `city.gd` warns when `--blockout` is used against a skinned build (rebuild with
        # `build_city.py --blockout` to get the procedural city back).
        "kit_skin": (skin.to_json() if skin is not None else {"active": False}),
        "arenas": [{"id": a["id"], "name": a["name"], "polygon": a["polygon"],
                    "tiers": a["tiers"], "open_cover": bool(a.get("open_cover", False)),
                    "sockets": [{"id": s["id"], "pos": s["pos"], "kind": s["kind"]}
                                for s in a["spawn_sockets"]]} for a in lay.arenas],
        "landmarks": [{"id": lm["id"], "kind": lm["kind"], "pos": lm["pos"],
                       "params": lm.get("params", {})}
                      for lm in lay.landmarks],
        "hives": lay.hives,
        "crown_rim": _crown_rim(lay),
        "anchors": lay.anchors,
        "vistas": _vistas(),
        "nav_links": [{"id": c["id"], "kind": c["kind"], "edge": c["edge"],
                       "from": c["from"], "to": c["to"], "width": c["width"],
                       "oneway": bool(c.get("oneway"))}
                      for c in lay.connectors if c["kind"] in LINK_KINDS],
        "walk_edges": [{"id": c["id"], "kind": c["kind"], "edge": c["edge"],
                        "from": c["from"], "to": c["to"], "width": c["width"],
                        "path": c.get("path") or [c["from"], c["to"]]}
                       for c in lay.connectors if c["kind"] in WALK_KINDS],
        "sky_waypoints": lay.sky_waypoints,
        "sky_edges": lay.sky_edges,
        "prop_slots": slots,
    }
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        json.dump(data, fh, indent=1)
    # city-art r12 §3: the design layout's buildings, decks and landmarks, beside the layout the same
    # run just wrote. Godot cannot read `data/`, and the runtime used to name an absolute /Users/ path
    # to reach it, so the roof dressing and the cargo blocks vanished on any other machine. Written
    # HERE, by the step that already writes the game copies, so it cannot drift from the layout.
    write_design(lay, os.path.join(os.path.dirname(path), "design_layout.json"))
    print("MARKERS %s (%d arenas, %d anchors, %d nav links, %d prop slots, %d podium walls, "
          "%d edges, %d ring towers, %d floors, %d blocks)"
          % (path, len(data["arenas"]), len(data["anchors"]), len(data["nav_links"]),
             len(data["prop_slots"]), len(data["podium_walls"]), len(data["edges"]),
             len(data["skyline_ring"]), len(data["floors"]), len(data["blocks"])))
    return data


# city-art r12 §3: the design-layout keys the Godot side reads. `data/map/city_layout.json` is outside
# `res://`, so these are copied into the project by the same run that writes `layout.json`. Everything
# else in the design layout (terrain, rails, tunnels, the sky graph) is already in `layout.json` or is
# never read at runtime.
DESIGN_KEYS = ("buildings", "decks", "streets", "landmarks", "arenas")


def design_subset(lay):
    """The design layout's runtime half: the rows themselves, plus a stamp of the file they came from
    so a stale copy is detectable (`world/art/tests/test_design_copy.gd`)."""
    src = lay.path if hasattr(lay, "path") else None
    return {
        "meta": {"source": "data/map/city_layout.json",
                 "seed": lay.meta["seed"], "version": lay.meta["version"],
                 "revision": lay.meta.get("revision"),
                 "source_md5": _md5(src) if src else None},
        **{k: getattr(lay, k, []) for k in DESIGN_KEYS},
    }


def write_design(lay, path):
    """`design_subset` beside `layout.json`. Called by `write()` on every full build; also runnable on
    its own (`tools/blender.sh run blender/city/markers.py`) because it needs no Blender scene and a
    full city rebuild to refresh one JSON file is not a thing anyone should have to do."""
    data = design_subset(lay)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        json.dump(data, fh, indent=1)
    print("MARKERS %s (%d buildings, %d decks, %d streets)"
          % (path, len(data["buildings"]), len(data["decks"]), len(data["streets"])))
    return data


def _md5(path):
    import hashlib
    try:
        with open(path, "rb") as fh:
            return hashlib.md5(fh.read()).hexdigest()
    except OSError:
        return None


def _terrain_floors(lay):
    """The three terrain surfaces the render draws, in the same polygon/holes shape as a deck.

    The crust is the map square with the canal, the dock trench, every sunken plaza and every
    descending connector cut out of it - the exact hole list `kit/terrain.py` cuts the slab with,
    so the gate samples the ground the player walks on and nothing else.
    """
    from kit import terrain as terrain_kit
    half = float(lay.bounds["half"])
    t = lay.terrain
    height = float(t["escarpment"]["height"])
    square = [[-half, -half], [half, -half], [half, half], [-half, half]]
    return [
        {"id": "terrain_crust", "kind": "terrain", "z": 0.0, "polygon": square,
         "holes": [list(map(list, h)) for h in
                   terrain_kit.ground_cuts(lay, -terrain_kit.CRUST, 0.0)
                   + [[tuple(p) for p in t["plateau"]["polygon"]]]],
         "arena": None, "deck_full": False},
        {"id": "terrain_plateau", "kind": "terrain", "z": height,
         "polygon": [list(p) for p in t["plateau"]["polygon"]],
         "holes": [list(map(list, h)) for h in
                   terrain_kit.ground_cuts(lay, height - terrain_kit.PLATEAU_CRUST, height)],
         "arena": None, "deck_full": False},
        {"id": "terrain_docks", "kind": "terrain", "z": float(t["docks"]["z"]),
         "polygon": [list(p) for p in t["docks"]["polygon"]], "holes": [],
         "arena": None, "deck_full": False},
    ]


def _floors(lay, skin=None):
    """Every walkable floor the layout declares, for the C18 top-face gate (lead r9).

    One row per deck: its polygon and holes at its own z. `deck_full` marks a deck whose render
    is city-kit's model rather than my slab, which the gate exempts. The Godot side samples a
    4 m grid over each one and wants a RENDERED up-facing face within 0.3 m of `z`.
    """
    out = []
    for d in lay.decks:
        out.append({"id": d["id"], "kind": d["kind"], "z": _floor_z(d),
                    "polygon": [[round(float(p[0]), 2), round(float(p[1]), 2)]
                                for p in d["polygon"]],
                    "holes": [[[round(float(p[0]), 2), round(float(p[1]), 2)] for p in h]
                              for h in d.get("holes", [])],
                    "arena": d.get("arena"),
                    "deck_full": bool(skin is not None and skin.deck_full(d["id"]))})
    return out + _terrain_floors(lay)


def _floor_z(deck):
    """The height a player actually stands on, which is not always the deck's own `z`.

    The Crown's outermost rim step sits ON the datum: `kit/decks.py::_crown` draws each step as a
    disc from `z` to `z + 1.5`, so the rim step at the deck's own z covers the whole floor and the
    walkable surface - collider included - is 1.5 m above the datum. Exporting 224 there made the
    gate call the entire Crown a missing floor.
    """
    z = float(deck["z"])
    if deck["kind"] != "crown":
        return z
    steps = deck.get("rim_steps") or []
    return z + 1.5 if any(abs(float(s["z"]) - z) < 0.01 for s in steps) else z


def _blocks(lay):
    """Everything that stands ON a floor and would hide it from the gate's downward ray.

    Buildings and arena cover, as rotated footprints with their z span. The C18 gate skips a grid
    sample inside one of these: a crate standing on a deck is the float audit's business, not the
    floor's.
    """
    out = []
    for b in lay.buildings:
        out.append({"kind": "building",
                    "c": [round(float(v), 2) for v in b["center"]],
                    "s": [round(float(v), 2) for v in b["size"]],
                    "yaw": round(float(b.get("rot", 0.0)), 2),
                    "z0": float(b["base_z"]), "z1": float(b["base_z"]) + float(b["height"])})
    for a in lay.arenas:
        for c in a.get("cover", []):
            z = float(c["center"][2])
            out.append({"kind": "cover",
                        "c": [round(float(c["center"][0]), 2), round(float(c["center"][1]), 2)],
                        "s": [round(float(c["size"][0]), 2), round(float(c["size"][1]), 2)],
                        "yaw": round(float(c.get("rot", 0.0)), 2),
                        "z0": z, "z1": z + float(c["size"][2])})
    return out


def _edges(lay):
    """Every deck parapet ring and viaduct barrier line, from the same geometry the build emits."""
    from kit import corridors, decks
    out = []
    for d in lay.decks:
        out.extend(decks.edge_rings(d))
    for v in lay.viaducts:
        out.extend(corridors.viaduct_edges(v))
    return out


def _crown_rim(lay):
    """The Crown's outermost rim ring (CONTRACTS 6 "Crown rim"): the boss breaks it in phase 2,
    so it is built in Godot as separate segments instead of being merged into the tile. The
    geometry it replaces is the parapet `kit/decks.py` would put on that step."""
    for d in lay.decks:
        if d["kind"] != "crown":
            continue
        steps = d.get("rim_steps") or []
        if not steps:
            continue
        outer = max(steps, key=lambda s: float(s["r"]))
        poly = d["polygon"]
        cx = sum(p[0] for p in poly) / len(poly)
        cy = sum(p[1] for p in poly) / len(poly)
        return {"deck": d["id"], "centre": [cx, cy], "radius": float(outer["r"]),
                "z": float(outer["z"]) + 1.5, "height": 5.0, "thickness": 2.0,
                "segments": 16}
    print("city-build: no crown deck in the layout; no crown rim exported")
    return None


def _spawn_zones(lay):
    """One zone per graph node that is a spawn-relevant place, plus the arena sockets."""
    out = []
    for nid, node in lay.nodes.items():
        if node.get("type") in ("start", "arena", "hub", "boss"):
            out.append({"id": nid, "pos": node["pos"], "kind": node["type"],
                        "arena": node.get("arena")})
    for a in lay.arenas:
        for s in a["spawn_sockets"]:
            out.append({"id": s["id"], "pos": s["pos"], "kind": s["kind"], "arena": a["id"]})
    return out


def _vistas():
    from layout import load_vistas
    return [{"id": v["id"], "desc": v["desc"], "pos": v["pos_blender"],
             "look": v["look_blender"], "fov": v["fov"]} for v in load_vistas()]


if __name__ == "__main__":
    # `tools/blender.sh run blender/city/markers.py` — refresh `game/world/city/design_layout.json`
    # alone. The full build writes it too; this exists because the layout changed without the city
    # needing a rebuild, and a 400 MB tile export is not the price of one JSON file.
    import sys
    _here = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, _here)
    sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
    from lib import common as _common
    from layout import Layout as _Layout
    write_design(_Layout(), os.path.join(_common.GAME, "world", "city", "design_layout.json"))
