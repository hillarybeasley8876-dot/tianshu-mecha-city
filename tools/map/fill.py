"""Fill every district: corridors -> blocks -> lots -> buildings, with coverage numbers.

Replaces the round-1 scattered fill (lead note, round 2): the district's own street network
defines the blocks, the blocks are cut into lots on the district's grain, and every lot that
is not arena interior, plaza, water or reserved space is built. `coverage` per district is
the built share of its non-corridor land and is printed and checked against the rules.
"""
from __future__ import annotations

import math
import random

from shapely.geometry import Point, Polygon
from shapely.ops import unary_union

import geom
import fabric
import lots as lot_stage
import mapconst as C
import zones as zone_stage

LANDMARK_KEEPOUT = (
    ("spire", 78.0, 78.0),            # id, half-width, half-depth (Spire shaft + collar)
    ("stilt_pagoda", 44.0, 44.0),
    ("block9", 70.0, 70.0),
    ("reactor_stacks", 150.0, 110.0),
    ("harbor_cranes", 190.0, 40.0),
)


def arena_limits(rules: dict, arenas: list[dict]) -> list[tuple[Polygon, float]]:
    """(arena footprint, highest top a building under it may reach).

    A rooftop arena (A6 Sky Garden at +144) must not sterilise the ground beneath it: that
    ground is where the towers carrying the deck stand (Hengsha mega-columns, dossier §1.8).
    """
    out = []
    for arena in arenas:
        spec = rules["arenas"][arena["id"]]
        out.append((geom.poly(arena["polygon"]),
                    min(float(t) for t in spec["tiers"]) - C.UNDER_DECK_CLEAR))
    return out


def reserved_space(rules: dict, decks: list[dict], ground_arenas: Polygon) -> Polygon:
    """Ground that is not for sale: arena floors, ground plazas, landmark footprints."""
    shapes: list[Polygon] = []
    if not ground_arenas.is_empty:
        shapes.append(ground_arenas)
    for deck in decks:
        if deck["z"] <= 8.0:                      # pier, sunken court, dock floor
            area = geom.poly(deck["polygon"])
            for hole in deck.get("holes", []):
                area = area.difference(geom.poly(hole))
            shapes.append(area)
    for ident, hw, hd in LANDMARK_KEEPOUT:
        pos = _landmark_pos(ident)
        if pos:
            shapes.append(geom.rect((pos[0], pos[1]), (hw * 2, hd * 2)))
    return unary_union(shapes) if shapes else Polygon()


_LANDMARK_POS = {"spire": (0.0, 120.0), "stilt_pagoda": (-520.0, 430.0),
                 "block9": (330.0, 250.0), "reactor_stacks": (600.0, -140.0),
                 "harbor_cranes": (-470.0, -345.0)}


def _landmark_pos(ident: str):
    return _LANDMARK_POS.get(ident)


def deck_heads(decks: list[dict]) -> list[tuple[Polygon, float]]:
    """(footprint minus holes, underside z) per deck: how high something below may reach."""
    out = []
    for deck in decks:
        area = geom.poly(deck["polygon"])
        for hole in deck.get("holes", []):
            area = area.difference(geom.poly(hole))
        out.append((area, deck["z"] - deck["thickness"]))
    return out


def generate(rules: dict, mask: Polygon, decks: list[dict],
             arenas: list[tuple[Polygon, float]], streets: list[dict], canal: Polygon,
             plateau: Polygon, caps: list[tuple[Polygon, float]], blocked: Polygon,
             rng: random.Random) -> tuple[list[dict], dict]:
    """All generic buildings, plus the coverage report per district.

    A district may own several build zones (D4 = the plaza ground + the Civic Quarter on
    the plateau); each zone is filled on its own datum and its numbers are added into the
    district's report row.
    """
    glob = rules["global"]
    spire = tuple(glob["spire_center"])
    heads = deck_heads(decks) + caps
    lower = geom.poly([[-C.HALF, -C.HALF], [C.HALF, -C.HALF], [C.HALF, C.HALF],
                       [-C.HALF, C.HALF]]).difference(plateau)
    out: list[dict] = []
    report: dict[str, dict] = {}
    for zone in zone_stage.zones(rules):
        did = zone["district"]
        fp = zone["footprint"]
        base_z = zone["ground_z"]
        build = zone["buildings"]
        ground = plateau if base_z >= 31.0 else lower
        area = geom.poly([[fp[0], fp[1]], [fp[2], fp[1]], [fp[2], fp[3]], [fp[0], fp[3]]])
        area = area.intersection(ground)
        ground_arenas = unary_union([poly for poly, head in arenas if head <= base_z])
        reserved = reserved_space(rules, decks, ground_arenas).union(blocked)
        # MAP §4 (revised): coverage is measured against BUILDABLE land - the non-corridor
        # ground minus the arena floors, plazas and landmark keep-outs that can never hold a
        # building - and the raw non-corridor area is reported next to it.
        open_land = area.difference(mask).difference(canal)
        land = open_land.difference(reserved)
        blocks = fabric.block_polygons(area, mask, reserved, canal)
        lot_w, lot_d = build["lot"]
        axis = float(zone["streets"]["angle_deg"])
        built = 0.0
        row = report.setdefault(did, {"blocks": 0, "buildings": 0, "lots": 0, "none": 0,
                                      "conflict": 0, "capped": 0, "block_built": 0.0,
                                      "land": 0.0, "open_land": 0.0})
        row["land"] += land.area
        row["open_land"] += open_land.area
        row["blocks"] += len(blocks)
        index = row["buildings"]
        for block in blocks:
            maker = fabric.terrace_row if build.get("fabric") == "terrace" \
                else fabric.subdivide
            for lot, lot_axis in maker(block, lot_w, lot_d, axis, rng):
                centre = lot.centroid
                front = _fronts_avenue(centre, streets, did)
                record = lot_stage.building_from_lot(
                    lot, lot_axis, did, {"buildings": build}, glob, base_z, spire, front, rng,
                    index + 1)
                if record is not None and zone["quarter"]:
                    record["quarter"] = zone["quarter"]
                row["lots"] += 1
                if record is None:
                    row["none"] += 1
                    continue
                box = geom.rect(tuple(record["center"]), tuple(record["size"]), record["rot"])
                if box.intersection(mask).area > 4.0:
                    row["conflict"] += 1
                    continue
                # a deck overhead or a corridor flying over does not delete the lot, it
                # caps the cornice: the mass stops under the slab, or carries it
                cap = lot_stage.head_cap(box, heads, arenas)
                want = record["height"]
                record["height"] = geom.snap(min(want, cap - base_z), C.FLOOR_MODULE)
                if record["height"] < 12.0:
                    row["conflict"] += 1
                    continue
                if record["height"] < want - 0.5:
                    row["capped"] += 1
                lot_stage.refresh_roof(record, glob)
                index += 1
                built += box.area
                out.append(record)
        row["buildings"] = index
        row["block_built"] += built
    _add_breaches(out, rng)
    return out, report


def coverage_report(rules: dict, report: dict, buildings: list[dict]) -> dict:
    """Built share of each district's buildable land, and of its non-corridor land."""
    boxes = [(b["district"], geom.rect(tuple(b["center"]), tuple(b["size"]), b["rot"]),
              b.get("holes")) for b in buildings]
    for did, row in report.items():
        built = 0.0
        for bd, box, holes in boxes:
            if bd != did:
                continue
            for hole in holes or []:
                box = box.difference(geom.poly(hole["polygon"]))
            built += box.area
        row["coverage"] = round(built / row["land"], 3) if row["land"] else 0.0
        row["coverage_open"] = round(built / row["open_land"], 3) if row["open_land"] else 0.0
        row["target"] = rules["districts"][did]["buildings"]["coverage"]
        row["land_ha"] = round(row["land"] / 1e4, 1)
    return report





def _fronts_avenue(centre: Point, streets: list[dict], did: str) -> float | None:
    """Distance to the nearest avenue edge when the lot fronts one, else None."""
    best = None
    for street in streets:
        if street["kind"] != "avenue":
            continue
        if street.get("district") not in (did, None):
            continue
        d = centre.distance(geom.line(street["points"])) - street["width"] / 2
        if d <= 30.0 and (best is None or d < best):
            best = d
    return best


def _add_breaches(buildings: list[dict], rng: random.Random) -> None:
    """Facade breaches on the big blocks: swarmer spawn sockets the mech cannot enter
    (dossier §1.2/§4.5 'breaches (spawns)')."""
    faces = ("n", "e", "s", "w")
    for b in buildings:
        if b["tier"] not in ("B", "C", "D") or rng.random() > 0.4:
            continue
        for _ in range(rng.randint(1, 2)):
            b["breaches"].append({
                "face": rng.choice(faces),
                "z": round(b["base_z"] + rng.uniform(0.1, 0.7) * b["height"] / C.FLOOR_MODULE)
                * C.FLOOR_MODULE,
                "width": float(rng.choice((24, 32, 40))),
                "height": float(rng.choice((24, 32))),
            })


def street_wall_share(streets: list[dict], buildings: list[dict],
                      blocked: Polygon) -> dict:
    """Share of each avenue's two frontages that is built (MAP §4: >= 50 %).

    Sampled every 12 m along both kerbs, 12 m out from the kerb line. A sample counts as
    built when a building footprint covers it; a sample that could never be built - it
    stands in a junction, a plaza, an arena floor or a landmark keep-out - is not counted
    at all, so the number answers "of the frontage there is, how much is a wall".
    """
    from shapely.strtree import STRtree
    boxes = [geom.rect(tuple(b["center"]), tuple(b["size"]), b["rot"]) for b in buildings]
    tree = STRtree(boxes) if boxes else None
    out: dict[str, float] = {}
    for street in streets:
        if street["kind"] != "avenue":
            continue
        line = geom.line(street["points"])
        # this avenue's own band is not a junction: only other corridors disqualify a sample
        other = blocked.difference(line.buffer(street["width"] / 2 + C.SETBACK + 1.0))
        step, hits, total, dead = 12.0, 0, 0, 0
        d = step / 2
        while d < line.length:
            here = line.interpolate(d)
            ahead = line.interpolate(min(d + 3.0, line.length))
            tx, ty = ahead.x - here.x, ahead.y - here.y
            norm = math.hypot(tx, ty) or 1.0
            for side in (1.0, -1.0):
                off = street["width"] / 2 + 12.0
                probe = Point(here.x - ty / norm * off * side, here.y + tx / norm * off * side)
                if tree is not None and len(tree.query(probe)) > 0:
                    hits += 1
                    total += 1
                elif other.contains(probe):
                    dead += 1
                else:
                    total += 1
            d += step
        out[street["id"]] = round(hits / total, 2) if total else 0.0
        out[f"{street['id']}#unbuildable"] = round(dead / max(total + dead, 1), 2)
    return out
