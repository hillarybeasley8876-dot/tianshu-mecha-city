"""Arena cover rows (r2 item 1): one kit prop cluster fitted over each cover box.

The layout's cover is 1 070 boxes 16-33 m in plan and 8-28 m tall — a concrete or metal box plus a
white cap, which is the cube field the user is pointing at. Each box here gets a kit cluster standing
in for it; city-build drops the render boxes (collision and the breakable prop slot are untouched)
when it reads the `cover` row kind.

Fitting rule (brief: "never scale a container more than 1.3x on any axis — stack/tile instead"):
every copy is scaled UNIFORMLY, so the anisotropy of a single copy is 1.0 by construction, and the
box is filled by tiling copies along the long axes and stacking them up. What is scored is the fill
(the model must cover the collision box, not sit inside it as a toy) against the instance count.
"""
from __future__ import annotations

from typing import Dict, List, Optional, Sequence, Tuple

import geom2d as g
from assets import BY_ID
from tuning import (COVER_FILL_MIN, COVER_MAX_COPIES, COVER_TRIS_PER_BOX,  # noqa: F401
                    NEIGHBOUR_R)

# Soft (breakable) cover must read flimsy and hard cover massive, so the two never swap roles.
Copy = Dict[str, object]


def _copies(box: Sequence[float], size: Sequence[float], turn: int,
            n: Tuple[int, int, int]) -> Optional[Tuple[float, float, List[Copy]]]:
    """(uniform scale, worst fill ratio, copies) for n copies of one model filling `box`, or None."""
    w, d, h = box
    fx, fy = (size[0], size[1]) if turn % 2 == 0 else (size[1], size[0])
    nx, ny, nz = n
    s = min(w / max(nx * fx, 1e-6), d / max(ny * fy, 1e-6), h / max(nz * size[2], 1e-6))
    if s <= 0.0:
        return None
    fill = min(nx * fx * s / w, ny * fy * s / d, nz * size[2] * s / h)
    cw, cd, ch = fx * s, fy * s, size[2] * s
    out: List[Copy] = []
    for iz in range(nz):
        for iy in range(ny):
            for ix in range(nx):
                out.append({"off": [round((ix - (nx - 1) * 0.5) * cw, 3),
                                    round((iy - (ny - 1) * 0.5) * cd, 3),
                                    round(iz * ch, 3)],
                            "scale": round(s, 4)})
    return s, fill, out


def _grids(box: Sequence[float], tris: int) -> List[Tuple[int, int, int]]:
    """Copy grids worth trying, cheapest first.

    The cap is a TRIANGLE budget, not a copy count: a jersey-barrier line is 1 400 tris at LOD and a
    25 m cover box needs seven of them across its depth to read as a defended position, while the
    same grid of a 2 200-tri crate pile would be 15 k tris of crate for one box. 1 070 boxes make
    that difference the whole budget.
    """
    w, d, h = box
    ar = max(w, d, h) / max(min(w, d, h), 1e-6)
    budget = max(4, int(COVER_TRIS_PER_BOX / max(tris, 1)))
    cap = min(8, max(COVER_MAX_COPIES if ar > 2.0 else 2, budget // 2))
    out = []
    for nx in range(1, cap + 1):
        for ny in range(1, cap + 1):
            for nz in range(1, min(cap, COVER_MAX_COPIES) + 1):
                if nx * ny * nz <= budget:
                    out.append((nx, ny, nz))
    return out


def fit(a: "Assigner", box: Sequence[float], centre: Sequence[float],
        soft: bool) -> Optional[dict]:
    """Best (model, turn, grid) for one cover box, or None when nothing fills it."""
    best: Optional[dict] = None
    for m in a.models.values():
        if m["band"] != "cover":
            continue
        # `soft` lives in the asset table, not in kit.json: it is a placement rule, not a property of
        # the exported mesh, and the assigner is the only thing that reads it.
        if bool(BY_ID[m["id"]].soft) != soft:
            continue
        used = sum(1 for v in a.grid.near((centre[0], centre[1]), NEIGHBOUR_R) if v == m["id"])
        tris = int((m.get("lod") or {}).get("tris", m.get("tris", 12000)))
        for turn in (0, 1):
            for n in _grids(box, tris):
                got = _copies(box, m["size"], turn, n)
                if got is None:
                    continue
                s, fill, copies = got
                if fill < COVER_FILL_MIN:
                    continue
                score = (2.0 * (1.0 - fill) + 0.12 * (len(copies) - 1) + 0.9 * used
                         + 0.05 * a.uses.get(m["id"], 0))
                if best is None or score < best["score"]:
                    best = {"model": m["id"], "turn": turn, "score": score, "fill": fill,
                            "scale": s, "copies": copies}
    return best


def build(a: "Assigner") -> List[dict]:
    """One row per cover box in every arena, in layout order."""
    rows: List[dict] = []
    misses = 0
    for arena in a.lay["arenas"]:
        for i, c in enumerate(arena.get("cover", [])):
            box = [float(v) for v in c["size"]]
            base = [float(v) for v in c["center"]]
            soft = bool(c.get("soft"))
            got = fit(a, box, base, soft)
            if got is None:
                misses += 1
                continue
            mid = str(got["model"])
            yaw = (float(c.get("yaw", 0.0)) + 90.0 * int(got["turn"])) % 360.0
            pieces = [{"pos": [round(base[0] + p["off"][0], 2), round(base[1] + p["off"][1], 2),
                               round(base[2] + p["off"][2], 2)],
                       "yaw": round(yaw, 2), "scale": [p["scale"]] * 3}
                      for p in got["copies"]]
            rows.append({"id": "%s#%d" % (arena["id"], i), "kind": "cover", "arena": arena["id"],
                         "index": i, "model": mid, "soft": soft, "pieces": pieces,
                         "box": [round(v, 2) for v in box],
                         "fill": round(float(got["fill"]), 3), "copies": len(pieces)})
            a.grid.add((base[0], base[1]), mid)
            a.uses[mid] = a.uses.get(mid, 0) + 1
    if misses:
        print("cover: %d boxes had no model that fills them and keep their procedural mesh" % misses)
    return rows


def report(rows: Sequence[dict]) -> None:
    by_model: Dict[str, int] = {}
    inst = 0
    for r in rows:
        by_model[r["model"]] = by_model.get(r["model"], 0) + 1
        inst += len(r["pieces"])
    fills = sorted(float(r["fill"]) for r in rows)
    print("cover: %d boxes, %d instances, fill p50 %.2f min %.2f, models %s"
          % (len(rows), inst, fills[len(fills) // 2] if fills else 0.0,
             fills[0] if fills else 0.0,
             ", ".join("%s:%d" % kv for kv in sorted(by_model.items()))))
