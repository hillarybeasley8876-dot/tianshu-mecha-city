"""Fit the Tripo architecture kit over the city blockout: data/map/kit_assign.json.

  tools/citykit/assign.py [--out data/map/kit_assign.json] [--report]

For every layout building this picks a kit model by district + archetype + height band, scales it to
the building's box, rotates it so the model's front faces the street the building fronts, and refuses
anything whose per-axis scale would stretch the architecture past ANISO_MAX. Buildings with `holes`
(arcades, the rail through Block 9) keep their procedural mesh unless a model carries the opening.

Street pieces are placed from the same data: railings along deck/viaduct edges, pylons under the
viaducts, shopfront podiums on street frontages near the arenas, paifang gates at arena entries and
skybridge tubes between the towers the layout spans.

Coordinates are Blender map space (X east, Y north, Z up), like data/map/city_layout.json; the Godot
placer converts with city.gd's to_godot() and uses the same numeric yaw about the up axis.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
from typing import Dict, List, Optional, Sequence, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from assets import PROP_BANDS  # noqa: E402

import geom2d as g  # noqa: E402
import pieces as pieces_mod  # noqa: E402
import cover as cover_mod  # noqa: E402
import far as far_mod  # noqa: E402
import ring as ring_mod  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LAYOUT = os.path.join(ROOT, "data", "map", "city_layout.json")
KIT = os.path.join(ROOT, "game", "world", "kit", "kit.json")
OUT = os.path.join(ROOT, "data", "map", "kit_assign.json")

from tuning import (ANISO_MAX, ANISO_SOFT, FLAT_TOP, FRONT_BONUS, HR_HI, HR_LO,  # noqa: E402
                    MIN_COPY_M, NEIGHBOUR_PENALTY, NEIGHBOUR_R, TIER_PENALTY, TIERS,
                    TILE_MAX, TILE_MAX_COPIES, TILE_PENALTY, USAGE_PENALTY)


def load(path: str) -> dict:
    with open(path) as fh:
        return json.load(fh)


def _grids(w: float, d: float) -> List[Tuple[int, int]]:
    """The copy grids `tile_pick` may try, cheapest (fewest copies) first.

    A divided axis has to leave a copy at least `MIN_COPY_M` wide — a 3 m sliver is a fence panel, not
    a building. An axis left whole is unconstrained: the single-model pick already accepted that
    dimension, which is how a 5.3 m thick wall can still be answered by a row of copies along it.
    """
    out: List[Tuple[int, int]] = []
    for nx in range(1, TILE_MAX + 1):
        for ny in range(1, TILE_MAX + 1):
            if nx * ny < 2 or nx * ny > TILE_MAX_COPIES:
                continue
            if nx > 1 and w / nx < MIN_COPY_M:
                continue
            if ny > 1 and d / ny < MIN_COPY_M:
                continue
            out.append((nx, ny))
    return sorted(out, key=lambda g: (g[0] * g[1], g[0] + g[1]))


class Assigner:
    def __init__(self, layout: dict, kit: dict) -> None:
        self.lay = layout
        self.models = {m["id"]: m for m in kit["models"]}
        for mid, m in self.models.items():
            if mid in FLAT_TOP:
                m.setdefault("tags", []).append("flat_top")
        self.streets = {s["id"]: s for s in layout["streets"]}
        self.grid = g.Grid()
        self.uses: Dict[str, int] = {}
        self.arena_polys = [a["polygon"] for a in layout["arenas"]]
        spire = next((l for l in layout["landmarks"] if l["kind"] == "spire"), None)
        self.spire_xy = (spire["pos"][0], spire["pos"][1]) if spire else (0.0, 0.0)
        self.arenas = [(a["polygon"], a["id"]) for a in layout["arenas"]]

    # ---------------------------------------------------------------- facing
    def facing_target(self, b: dict) -> Optional[g.Pt]:
        """Where the building's front should look: the street it fronts, else the nearest corridor."""
        c = (b["center"][0], b["center"][1])
        sid = b.get("fronts")
        if sid and sid in self.streets:
            q, _, _ = g.polyline_closest(c, [tuple(p) for p in self.streets[sid]["points"]])
            return q
        best: Optional[Tuple[g.Pt, float]] = None
        for s in self.lay["streets"]:
            q, d, _ = g.polyline_closest(c, [tuple(p) for p in s["points"]])
            if best is None or d < best[1]:
                best = (q, d)
        for v in self.lay["viaducts"]:
            q, d, _ = g.polyline_closest(c, [tuple(p) for p in v["points"]])
            if best is None or d < best[1]:
                best = (q, d)
        return best[0] if best else None

    # ------------------------------------------------------------- candidates
    def candidates(self, b: dict, district: bool, archetype: bool, height: bool,
                   allow_hole: bool = False) -> List[dict]:
        out = []
        for m in self.models.values():
            if m["band"] in PROP_BANDS:
                continue
            # r9: the four skyline-ring masses are silhouettes for 700 m and up. They carry no
            # district or archetype, so without this they would win boxes all over the city.
            if "ring_only" in m.get("tags", []):
                continue
            if not allow_hole and "hole" in m.get("tags", []):
                continue    # a model built around a through-opening on a solid box reads as a mistake
            if district and m["districts"] and b["district"] not in m["districts"]:
                continue
            if archetype and m["archetypes"] and b["archetype"] not in m["archetypes"]:
                continue
            if height and not (HR_LO <= b["height"] / max(m["size"][2], 1e-6) <= HR_HI):
                continue
            out.append(m)
        return out

    def score(self, b: dict, m: dict, j: int, face_yaw: float, tier: int) -> Tuple[float, float, List[float], float]:
        """(score, anisotropy, per-axis scale, yaw) for model `m` at quarter-turn `j` of the box.

        The model's footprint has to line up with the building's box, so the only free rotation is a
        multiple of 90 deg on top of the layout's own `rot`. Its front (the face Tripo detailed, -Y in
        Blender) then points at `yaw + 180`; the street lies at `face_yaw`, and the gap between them is
        what the front-facing term measures.
        """
        w, d, h = b["size"][0], b["size"][1], b["height"]
        mx, my, mz = m["size"]
        rot = float(b.get("rot", 0.0))
        yaw = (rot + 90.0 * j) % 360.0
        fx, fy = (my, mx) if j % 2 else (mx, my)
        sx, sy, sz = w / max(fx, 1e-6), d / max(fy, 1e-6), h / max(mz, 1e-6)
        aniso = g.anisotropy((sx, sy, sz))
        off = abs(((yaw + 180.0 - face_yaw + 180.0) % 360.0) - 180.0)   # 0 = front on the street
        s = math.log(aniso) + FRONT_BONUS * (off / 90.0)
        variant = (m["id"], j % 2)
        used = sum(1 for v in self.grid.near((b["center"][0], b["center"][1]), NEIGHBOUR_R)
                   if v == variant)
        s += NEIGHBOUR_PENALTY * used + USAGE_PENALTY * self.uses.get(m["id"], 0)
        s += TIER_PENALTY * tier
        # The scale is per MODEL axis (the placer scales the mesh in its own frame, then turns it). On
        # an odd quarter turn the model's Y lies along the box's w, so `sx` belongs to Y and `sy` to X.
        # Written in the box's order, 189 of 384 buildings drew stretched across the wrong axis (11-03).
        return s, aniso, ([sy, sx, sz] if j % 2 else [sx, sy, sz]), yaw

    def pick(self, b: dict, allow_hole: bool = False) -> Optional[dict]:
        face = self.facing_target(b)
        rot = float(b.get("rot", 0.0))
        face_yaw = g.yaw_towards((b["center"][0], b["center"][1]), face) if face else rot + 180.0
        # The quarter-turn whose front lands closest to the street, plus its two neighbours: swapping
        # the footprint between them is the only other lever on anisotropy. Never the opposite turn —
        # a shopfront row or a warehouse with its doors to the back wall is worse than a stretched one.
        d = (face_yaw - 180.0 - rot) % 360.0
        j0 = int(round(d / 90.0))
        turns = [j % 4 for j in (j0, j0 + 1, j0 - 1)]
        # Every tier is scored, not just the first that answers: a twin next door in the strict tier
        # must be able to lose to a clean pick from a looser one, or D3 ends up as a row of one house.
        for limit in (ANISO_MAX, ANISO_SOFT):
            best: Optional[dict] = None
            for ti, (district, archetype, height) in enumerate(TIERS):
                cands = self.candidates(b, district, archetype, height, allow_hole)
                if b.get("roof_walkable"):
                    flat = [m for m in cands if "flat_top" in m.get("tags", [])]
                    if flat:
                        cands = flat
                for m in cands:
                    for j in turns:
                        sc, aniso, scale, yaw = self.score(b, m, j, face_yaw, ti)
                        if aniso > limit:
                            continue
                        if best is None or sc < best["score"]:
                            best = {"model": m["id"], "yaw": round(yaw, 2), "variant": j % 2,
                                    "scale": [round(v, 4) for v in scale], "aniso": round(aniso, 3),
                                    "score": round(sc, 4), "tier": ti, "soft": limit > ANISO_MAX}
            if best is not None:
                return best
        return None

    # --------------------------------------------------------------- buildings
    def buildings(self) -> Tuple[List[dict], List[dict]]:
        rows: List[dict] = []
        skipped: List[dict] = []
        hole_models = [m["id"] for m in self.models.values() if "hole" in m.get("tags", [])]
        # Tallest first: the signature towers pick their model before a mid-rise takes it as filler.
        for b in sorted(self.lay["buildings"], key=lambda x: -x["height"]):
            cx, cy = b["center"]
            if b.get("holes") or b.get("through"):
                chosen = self.pick_hole(b, hole_models)
                if chosen is None:
                    skipped.append({"id": b["id"], "reason": "holes/through: no kit model has the opening"})
                    continue
            else:
                chosen = self.pick(b)
            if chosen is None:
                chosen = self.tile_pick(b)
                if chosen is None:
                    skipped.append({"id": b["id"],
                                    "reason": "no model within anisotropy %.2f, single or tiled"
                                              % ANISO_SOFT,
                                    "district": b["district"], "height": b["height"],
                                    "size": b["size"]})
                    continue
            rows.append(dict(chosen, id=b["id"], kind="building", model=chosen["model"],
                             pos=[round(cx, 2), round(cy, 2), round(b["base_z"], 2)],
                             box=[round(b["size"][0], 2), round(b["size"][1], 2),
                                  round(b["height"], 2)],
                             height=round(b["height"], 2), district=b["district"],
                             archetype=b["archetype"], roof_walkable=bool(b.get("roof_walkable"))))
            # One grid entry per BUILDING, not per copy: a tiled row's copies are metres apart and
            # are not neighbours of each other, and registering them made the scorer think a model
            # was already crowded and push the next box onto whatever was left (f01 ended up on 19).
            self.grid.add((cx, cy), (chosen["model"], chosen.get("variant", 0)))
            self.uses[chosen["model"]] = self.uses.get(chosen["model"], 0) + 1
        return rows, skipped

    def pick_hole(self, b: dict, hole_models: Sequence[str]) -> Optional[dict]:
        """A building pierced by a street/rail keeps its procedural mesh unless a model has the opening.

        r9: the tiled fallback runs inside the same hole-only model set, so a pierced box that no single
        pierced model fits (Block 9 is 130 x 130 x 200 and m04 is a 2.9:1 slab) can still be answered by
        a row of them — which is what the real Liziba block is.
        """
        if not hole_models:
            return None
        saved, self.models = self.models, {k: v for k, v in self.models.items() if k in hole_models}
        try:
            return self.pick(b, allow_hole=True) or self.tile_pick(b, allow_hole=True)
        finally:
            self.models = saved

    # ------------------------------------------------------------ tiling (r2 item 3, r9 item 2)
    def tile_pick(self, b: dict, allow_hole: bool = False) -> Optional[dict]:
        """A grid of copies of one model filling the box.

        The long-block assets (l01-l03) answer 4:1 and 6:1 slabs, but the boxes left over are the ones
        no single model matches at all — a 5 x 49 x 32 m wall, a 56 x 152 x 132 m block. Each copy is
        scored on its OWN sub-box, so nothing is stretched: the sub-box IS the copy's footprint.

        r2 only divided the box's long axis into 2 or 3. r9 divides both: a box can be too big in plan
        for one model in either direction, and a 2 x 2 of a megablock over a 130 m square reads as one
        building rather than as four. `TILE_PENALTY` is per COPY, so a grid is only ever chosen when a
        single model genuinely does not fit.
        """
        w, d, h = b["size"][0], b["size"][1], b["height"]
        rot = math.radians(float(b.get("rot", 0.0)))
        ca, sa = math.cos(rot), math.sin(rot)
        best: Optional[dict] = None
        for nx, ny in _grids(w, d):
            sub = dict(b, size=[w / nx, d / ny])
            got = self.pick(sub, allow_hole)
            if got is None:
                continue
            score = float(got["score"]) + TILE_PENALTY * (nx * ny - 1)
            if best is not None and score >= best["score"]:
                continue
            pieces = []
            for ix in range(nx):
                for iy in range(ny):
                    lx = (ix - (nx - 1) * 0.5) * (w / nx)
                    ly = (iy - (ny - 1) * 0.5) * (d / ny)
                    pieces.append({"pos": [round(b["center"][0] + lx * ca - ly * sa, 2),
                                           round(b["center"][1] + lx * sa + ly * ca, 2),
                                           round(b["base_z"], 2)],
                                   "yaw": got["yaw"], "scale": got["scale"]})
            best = dict(got, pieces=pieces, tiled=nx * ny, tile_grid=[nx, ny], score=score)
        return best

    # ----------------------------------------------------------- street pieces
    # ----------------------------------------------------------------- helpers
    @staticmethod
    def _along(pts: Sequence[g.Pt], seg_len: float, _z: float) -> List[Tuple[g.Pt, float, float]]:
        out = []
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            L = g.dist(a, b)
            if L < 1e-3:
                continue
            n = max(1, int(round(L / seg_len)))
            step = L / n
            yaw = g.yaw_along(a, b)
            for k in range(n):
                t = (k + 0.5) / n
                out.append(((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t), yaw, step))
        return out

    def _edge_segments(self, poly: Sequence[Sequence[float]], seg_len: float,
                       z: float) -> List[dict]:
        pts = [tuple(p) for p in poly] + [tuple(poly[0])]
        return [{"pos": [round(m[0], 2), round(m[1], 2), round(z, 2)], "yaw": round(yaw, 2),
                 "len": round(L, 2), "scale": round(L / seg_len, 3)}
                for m, yaw, L in self._along(pts, seg_len, z)]

    @staticmethod
    def _offset(pts: Sequence[g.Pt], d: float) -> List[g.Pt]:
        out = []
        for i, p in enumerate(pts):
            a = pts[max(i - 1, 0)]
            b = pts[min(i + 1, len(pts) - 1)]
            tx, ty = b[0] - a[0], b[1] - a[1]
            L = math.hypot(tx, ty) or 1.0
            out.append((p[0] + ty / L * d, p[1] - tx / L * d))
        return out

    def near_arena(self) -> List[dict]:
        """Buildings within PODIUM_NEAR of an arena outline or the Spire plaza."""
        out = []
        for b in self.lay["buildings"]:
            c = (b["center"][0], b["center"][1])
            if g.dist(c, self.spire_xy) <= PODIUM_NEAR or any(
                    g.dist_to_poly(c, poly) <= PODIUM_NEAR for poly in self.arena_polys):
                out.append(b)
        return out


def report(assign: dict, layout: dict) -> None:
    rows = assign["buildings"]
    total = len(layout["buildings"])
    aniso = sorted(r["aniso"] for r in rows)
    soft = [r for r in rows if r.get("soft")]
    by_model: Dict[str, int] = {}
    for r in rows:
        by_model[r["model"]] = by_model.get(r["model"], 0) + 1
    print("buildings: %d/%d covered (%.1f %%)" % (len(rows), total, 100.0 * len(rows) / total))
    if aniso:
        print("anisotropy: p50 %.2f  p90 %.2f  max %.2f  |  <= %.2f: %d (%.1f %%)  soft: %d"
              % (aniso[len(aniso) // 2], aniso[int(len(aniso) * 0.9)], aniso[-1], ANISO_MAX,
                 sum(1 for a in aniso if a <= ANISO_MAX),
                 100.0 * sum(1 for a in aniso if a <= ANISO_MAX) / len(aniso), len(soft)))
    print("tiers: %s" % sorted((t, sum(1 for r in rows if r["tier"] == t)) for t in {r["tier"] for r in rows}))
    print("models used: %d of %d" % (len(by_model), len(assign["meta"]["models"])))
    print("  " + ", ".join("%s:%d" % kv for kv in sorted(by_model.items(), key=lambda kv: -kv[1])))
    pieces = assign["pieces"]
    counts: Dict[str, int] = {}
    for p in pieces:
        counts[p["kind"]] = counts.get(p["kind"], 0) + len(p.get("segments", [p]))
    print("street pieces: %d rows, %d instances, %s" % (len(pieces), sum(counts.values()), counts))
    reasons: Dict[str, int] = {}
    for s in assign["skipped"]:
        key = s["reason"].split(":")[0]
        reasons[key] = reasons.get(key, 0) + 1
    print("skipped: %d %s" % (len(assign["skipped"]), reasons))


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--out", default=OUT)
    p.add_argument("--report", action="store_true")
    args = p.parse_args()
    layout, kit = load(LAYOUT), load(KIT)
    a = Assigner(layout, kit)
    rows, skipped = a.buildings()
    pieces = pieces_mod.build_all(a, rows)
    cover_rows = cover_mod.build(a)
    far_rows = far_mod.build(a, rows)
    ring_rows, ring_skipped = ring_mod.build(a)
    assign = {"version": 2,
              "meta": {"layout": os.path.relpath(LAYOUT, ROOT), "kit": os.path.relpath(KIT, ROOT),
                       "units": "m", "up": "Z", "space": "blender",
                       "models": sorted(a.models), "aniso_max": ANISO_MAX, "aniso_soft": ANISO_SOFT,
                       "buildings_total": len(layout["buildings"]),
                       "far_range": [450.0, 1600.0], "tile": far_mod.TILE,
                       "ring_range": [0.0, 3000.0], "ring_total": len(layout["skyline"])},
              "buildings": rows, "pieces": pieces, "cover": cover_rows, "far_lod": far_rows,
              "ring": ring_rows,
              "skipped": skipped + [dict(s, id="skyline#%d" % s["index"]) for s in ring_skipped]}
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w") as fh:
        json.dump(assign, fh, indent=1)
    # The placer reads it from inside the project: data/ is not res://, and the shipped build has no
    # data/ at all. Same file, two homes (godot-tech §8).
    if os.path.abspath(args.out) == os.path.abspath(OUT):
        game_copy = os.path.join(os.path.dirname(KIT), "kit_assign.json")
        with open(game_copy, "w") as fh:
            json.dump(assign, fh)
        print("wrote %s" % game_copy)
    print("wrote %s (%d buildings, %d piece rows, %d cover rows, %d far tiles, %d ring boxes)"
          % (args.out, len(rows), len(pieces), len(cover_rows), len(far_rows), len(ring_rows)))
    report(assign, layout)
    cover_mod.report(cover_rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
