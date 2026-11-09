"""The numbers validate_layout prints: coverage, walls, tiers, sightlines, tallest masses.

Split out of validate_layout.py so the checks stay readable and the report can be reused.
"""
from __future__ import annotations

import geom
import mapconst as C
from shapely.ops import unary_union
from shapely.geometry import Polygon


ARENA_REACH = 100.0        # MAP §4: "inside arenas and within 100 m of their outline"
COVER_IN_ARENA = (0.40, 0.60)
COVER_ELSEWHERE = 0.25


def overhead_cover(layout: dict) -> dict:
    """L1 street length under something, split the way MAP §4 (revised) asks for it.

    Inside arenas and within 100 m of their outline the target is 40-60 %; everywhere else
    at most 25 %, and only architecture counts there - a free-standing canopy is not
    architecture, so `canopy` slabs are excluded from the "elsewhere" figure.
    """
    above = [(geom.poly(d["polygon"]), bool(d.get("canopy")))
             for d in layout["decks"] if d["z"] >= 8.0]
    above += [(geom.line(v["points"]).buffer(v["width"] / 2), False)
              for v in layout["viaducts"] + layout["rails"]]
    all_cover = unary_union([a for a, _ in above]) if above else Polygon()
    built = unary_union([a for a, canopy in above if not canopy]) if above else Polygon()
    near = unary_union([geom.poly(a["polygon"]).buffer(ARENA_REACH)
                        for a in layout["arenas"]]) if layout["arenas"] else Polygon()
    rows = {"arena": [0.0, 0.0, 0.0], "open": [0.0, 0.0, 0.0]}
    per_district: dict[str, list[float]] = {}
    for street in layout["streets"]:
        if street["z"] > 0.5:
            continue
        line = geom.line(street["points"])
        for key, band in (("arena", line.intersection(near) if not near.is_empty else None),
                          ("open", line.difference(near) if not near.is_empty else line)):
            if band is None or band.is_empty:
                continue
            length = band.length
            acc = rows[key]
            acc[0] += length
            acc[1] += band.intersection(all_cover).length
            acc[2] += band.intersection(built).length
            did = street.get("district", "graph")
            if key == "open":
                slot = per_district.setdefault(did, [0.0, 0.0])
                slot[0] += length
                slot[1] += band.intersection(built).length
    return {
        "arena_m": round(rows["arena"][0]), "arena": round(rows["arena"][1] / rows["arena"][0], 3)
        if rows["arena"][0] else 0.0,
        "open_m": round(rows["open"][0]),
        "open": round(rows["open"][2] / rows["open"][0], 3) if rows["open"][0] else 0.0,
        "open_any": round(rows["open"][1] / rows["open"][0], 3) if rows["open"][0] else 0.0,
        "total_m": round(rows["arena"][0] + rows["open"][0]),
        "per_district": {k: round(v[1] / v[0], 2) for k, v in sorted(per_district.items())
                         if v[0] > 0},
    }


def summarise(layout: dict, l4: dict, l5: dict, l6: dict, over: dict) -> None:
    cover = layout["meta"].get("coverage", {})
    if cover:
        print("built coverage of non-corridor land: "
              + "  ".join(f"{d} {v:.0%}" for d, v in sorted(cover.items())))
    walls = {k: v for k, v in layout["meta"].get("street_walls", {}).items()
             if not k.endswith("#unbuildable")}
    dead = [v for k, v in layout["meta"].get("street_walls", {}).items()
            if k.endswith("#unbuildable")]
    if walls:
        print(f"avenue street walls: mean {sum(walls.values()) / len(walls):.0%} "
              f"over {len(walls)} avenues, worst {min(walls.values()):.0%}; "
              f"{sum(dead) / max(len(dead), 1):.0%} of avenue frontage is junction/plaza")
    podiums = [b for b in layout["buildings"] if b.get("podium_z") is not None]
    if podiums:
        clears = [h["clear"] for b in podiums for h in b.get("holes", [])]
        print(f"podium-through blocks: {len(podiums)} bridging "
              f"{len({s for b in podiums for s in b['through']})} streets, arcade clear "
              f"{min(clears):.0f}-{max(clears):.0f} m, podium top "
              f"{min(b['podium_z'] for b in podiums):.0f}-"
              f"{max(b['podium_z'] for b in podiums):.0f} m")
    straddles = [b for b in layout["buildings"] if b.get("straddles")]
    if straddles:
        clears = [h["clear"] for b in straddles for h in b.get("holes", [])]
        pierced = {c for b in straddles for c in b["straddles"]}
        print(f"viaduct/rail-through towers: {len(straddles)} piercing "
              f"{len(pierced)} corridors ({', '.join(sorted(pierced))}), openings "
              f"{min(clears):.0f}-{max(clears):.0f} m clear, heights "
              f"{min(b['height'] for b in straddles):.0f}-"
              f"{max(b['height'] for b in straddles):.0f} m")
    carriers = [b for b in layout["buildings"] if b.get("carries")]
    if carriers:
        print(f"deck carriers: {len(carriers)} towers carrying "
              + ", ".join(sorted({b["carries"] for b in carriers}))
              + f", {min(b['height'] for b in carriers):.0f}-"
              + f"{max(b['height'] for b in carriers):.0f} m")
    bridges = [d for d in layout["decks"] if d.get("skybridge")]
    if bridges:
        levels = sorted({d["z"] for d in bridges})
        print(f"D5 canyon skybridges: {len(bridges)} at "
              + "/".join(f"+{z:.0f}" for z in levels)
              + f", each spanning {bridges[0]['span']}")
    tiers: dict[str, dict[str, int]] = {}
    for b in layout["buildings"]:
        tiers.setdefault(b["district"], {}).setdefault(b["tier"], 0)
        tiers[b["district"]][b["tier"]] += 1
    print("buildings per district/tier: " + "  ".join(
        f"{d} " + "/".join(f"{t}{tiers[d].get(t, 0)}" for t in C.TIERS if tiers[d].get(t))
        for d in sorted(tiers)))
    kinds: dict[str, int] = {}
    for con in layout["connectors"]:
        kinds[con["kind"]] = kinds.get(con["kind"], 0) + 1
    print("connectors: " + "  ".join(f"{k} {v}" for k, v in sorted(kinds.items())))
    print("arenas: " + "  ".join(
        f"{aid} cover {s['cover']} soft {s['soft']:.0%} entries {s['entries']}"
        f"{s['layers']} longLOS {s['long_los']:.0%}" for aid, s in sorted(l4.items())))
    print("anchors per arena: " + "  ".join(f"{k} {v}" for k, v in sorted(l6.items())))
    print(f"L1 streets under cover: inside/near arenas {over['arena']:.0%} of "
          f"{over['arena_m']} m (want 40-60 %); elsewhere {over['open']:.0%} of "
          f"{over['open_m']} m by architecture (want <= 25 %, "
          f"{over['open_any']:.0%} counting canopies)  "
          + "  ".join(f"{k} {v:.0%}" for k, v in over["per_district"].items()))
    print(f"Spire crown visible from {l5['visible']:.1%} of {l5['samples']} navigable samples")
    heights = sorted((b["base_z"] + b["height"], b["id"]) for b in layout["buildings"])
    print(f"tallest buildings: " + "  ".join(f"{h:.0f} m {i}" for h, i in heights[-4:][::-1])
          + f"   Spire {C.SPIRE_HEIGHT:.0f} m")


