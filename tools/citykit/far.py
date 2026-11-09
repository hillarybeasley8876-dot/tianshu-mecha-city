"""Far-band tile rows (r2 item 2): which of city-build's HLOD proxies my far LOD replaces.

The placer already draws every building row twice — the detail batch to 450 m and the decimated
`<id>_far.glb` batch from 450 m to 1 600 m. What this module decides is the other half of the swap:
which 200 m tiles city-build may stand its collision-mass proxy down in.

A tile only stands down when EVERY building whose centre falls in it is covered by a kit model AND
every model it uses passed the far silhouette gate (blender/citykit/fargate.py). Standing a proxy
down over a tile that still has an unskinned building would make that building vanish at 450 m,
which is a worse bug than the box it replaces; standing one down for a model whose far mesh tears
would replace a solid box with a shredded one. Both rules are strict and the covered fraction is
printed rather than assumed.
"""
from __future__ import annotations

from typing import Dict, List, Sequence, Tuple

TILE = 200.0     # city-build's export granularity (blender/city/tiles.py)


def tile_key(x: float, y: float, half: float) -> Tuple[int, int]:
    """The same key city-build's tiles.py uses, so `t<tx>_<ty>` names its proxy object."""
    return (int((x + half) // TILE), int((y + half) // TILE))


def build(a: "Assigner", rows: Sequence[dict]) -> List[dict]:
    """One `far_lod` row per tile whose buildings are all skinned."""
    half = float(a.lay["bounds"]["half"])
    covered = {r["id"] for r in rows}
    gated = {mid for mid, m in a.models.items()
             if (m.get("far") or {}).get("gate", {}).get("pass", True)}
    total: Dict[Tuple[int, int], int] = {}
    done: Dict[Tuple[int, int], int] = {}
    for b in a.lay["buildings"]:
        k = tile_key(float(b["center"][0]), float(b["center"][1]), half)
        total[k] = total.get(k, 0) + 1
        if b["id"] in covered:
            done[k] = done.get(k, 0) + 1
    by_tile: Dict[Tuple[int, int], List[str]] = {}
    centres = {b["id"]: (float(b["center"][0]), float(b["center"][1]))
               for b in a.lay["buildings"]}
    for r in rows:
        by_tile.setdefault(tile_key(centres[r["id"]][0], centres[r["id"]][1], half),
                           []).append(r["model"])
    out: List[dict] = []
    full = 0
    for k in sorted(total):
        if done.get(k, 0) != total[k]:
            continue
        if any(mid not in gated for mid in by_tile.get(k, [])):
            continue
        full += 1
        out.append({"id": "t%d_%d" % k, "kind": "far_lod", "tile": list(k),
                    "buildings": total[k], "range": [450.0, 1600.0],
                    # city-build holds any far row without this verdict (blender/city/skin.py
                    # `_gate_pass`), so their proxy stays up rather than leaving a hole in the band.
                    "gate": "pass",
                    "gate_holes": max([float((a.models[mid].get("far") or {}).get("gate", {})
                                             .get("holes", 0.0)) for mid in by_tile.get(k, [])]
                                      or [0.0])})
    covered_b = sum(done.values())
    print("far lod: %d of %d tiles fully skinned (%d of %d buildings); %d tiles keep the box proxy"
          % (full, len(total), covered_b, len(a.lay["buildings"]), len(total) - full))
    return out
