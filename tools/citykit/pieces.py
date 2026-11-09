"""Street-piece placement for the kit (brief step 5): railings, pylons, podiums, paifang, skybridges,
market rows, metro entrances and pipe racks.

Split out of `assign.py` for length; every function takes the `Assigner` that owns the layout, the
models and the 2D helpers, and returns rows in the same shape the placer reads.
"""
from __future__ import annotations

import math
import zlib
from typing import List, Sequence, Tuple

import geom2d as g
from tuning import (FASCIA_SEG, GATE_NEAR, MARKET_MAX, MARKET_NEAR, PARAPET_SEG,  # noqa: F401
                    PODIUM_DEPTH, PODIUM_H, PODIUM_NEAR, RAIL_NEAR, RAIL_SEG)


def build_all(a: "Assigner", rows: Sequence[dict]) -> List[dict]:
    """Every piece row, in one list. `near` (buildings near an arena) is computed once."""
    near = near_arena(a)
    return (railings(a) + deck_edges(a) + parapets(a) + pylons(a) + shopfronts(a, near)
            + gates(a) + skybridges(a) + markets(a) + metros(a) + pipe_racks(a)
            + rooftops(a, rows))


def long_axis(size: Sequence[float]) -> int:
    """0 if the model's long horizontal axis is its local X, 1 if it is Y (kit.json is Blender space)."""
    return 1 if size[1] >= size[0] else 0


def span(size: Sequence[float], length: float, depth: float, height: float,
         yaw: float) -> Tuple[float, List[float]]:
    """(yaw, Blender-space scale) for one tileable segment of `length`, its section scaled to fit.

    `yaw_along` points the model's local +Y from a to b, so a model whose long axis is X needs the
    quarter turn the placer's `_segment` would have applied in its own `len` branch. The placer maps
    Blender (x, y, z) onto Godot (x, z, -y) itself, so this stays in Blender space.
    """
    if long_axis(size) == 1:
        return yaw, [round(depth / max(size[0], 1e-6), 4), round(length / max(size[1], 1e-6), 4),
                     round(height / max(size[2], 1e-6), 4)]
    return (yaw + 90.0) % 360.0, [round(length / max(size[0], 1e-6), 4),
                                   round(depth / max(size[1], 1e-6), 4),
                                   round(height / max(size[2], 1e-6), 4)]


def deck_edges(a: "Assigner") -> List[dict]:
    """u01 wrapping the outer face of every elevated deck (r2 item 4).

    The fascia hangs off the slab: its top is the deck surface, its depth covers the slab thickness,
    and it stands proud of the parapet line so the two do not z-fight. The outward normal comes from
    the deck centroid, not the polygon winding, so it is right whichever way the layout lists it.
    Ground plazas are left out: 26 km of elevated edge is already ~1 100 segments and a plaza rim has
    no soffit to hide.
    """
    u01 = a.models.get("u01")
    if u01 is None:
        return []
    depth = float(u01["size"][1 - long_axis(u01["size"])])
    rows: List[dict] = []
    for d in a.lay["decks"]:
        if d.get("parapet", 0) <= 0 or d.get("on_ground") or len(d["polygon"]) < 3:
            continue
        thick = float(d.get("thickness", 4.0))
        z = float(d["z"]) - thick - 1.0
        c = g.centroid([tuple(p) for p in d["polygon"]])
        segs = []
        for m, yaw, L in a._along([tuple(p) for p in d["polygon"]] + [tuple(d["polygon"][0])],
                                  FASCIA_SEG, z):
            ox, oy = m[0] - c[0], m[1] - c[1]
            r = math.hypot(ox, oy) or 1.0
            out = depth * 0.5 - 0.8
            sy, sc = span(u01["size"], L, depth, thick + 1.0, yaw)
            segs.append({"pos": [round(m[0] + ox / r * out, 2), round(m[1] + oy / r * out, 2),
                                 round(z, 2)],
                         "yaw": round(sy, 2), "len": round(L, 2), "scale": sc})
        if segs:
            rows.append({"id": d["id"], "kind": "deck_edge", "model": "u01", "segments": segs})
    return rows


def parapets(a: "Assigner") -> List[dict]:
    """u02 on both edges of every viaduct (r2 item 4).

    city-build's skin drops the viaduct's own barrier mesh wherever a `viaduct_edge` row exists, so
    this has to be emitted for every viaduct: without it the deck runs bare, with only the s07 light
    rail standing where a 4 m concrete parapet should be.
    """
    u02 = a.models.get("u02")
    if u02 is None:
        return []
    depth = float(u02["size"][1 - long_axis(u02["size"])])
    h = float(u02["size"][2])
    rows: List[dict] = []
    for v in a.lay["viaducts"]:
        segs = []
        for side in (-1.0, 1.0):
            pts = a._offset([tuple(p) for p in v["points"]], side * (v["width"] * 0.5 - depth * 0.4))
            for m, yaw, L in a._along(pts, PARAPET_SEG, v["z"]):
                sy, sc = span(u02["size"], L, depth, h, yaw)
                segs.append({"pos": [round(m[0], 2), round(m[1], 2), round(v["z"], 2)],
                             "yaw": round(sy, 2), "len": round(L, 2), "scale": sc})
        if segs:
            rows.append({"id": v["id"], "kind": "viaduct_edge", "model": "u02", "segments": segs})
    return rows



def railings(a: "Assigner") -> List[dict]:
    """s07 crowning every deck parapet and both viaduct edges.

    Deliberately ADDED, not replacing the parapet: the layout's parapets are 5 m of collision, and a
    1.5 m guardrail standing in for one would leave the player walking into nothing. So the rail sits
    on top, which is also where ART.md puts the cyan LED rails.
    """
    s07 = a.models.get("s07")
    if s07 is None:
        return []
    rows: List[dict] = []
    for d in a.lay["decks"]:
        if d.get("parapet", 0) <= 0 or len(d["polygon"]) < 3:
            continue
        c = g.centroid([tuple(p) for p in d["polygon"]])
        if not (g.dist(c, a.spire_xy) <= RAIL_NEAR
                or any(g.dist_to_poly(c, poly) <= RAIL_NEAR for poly in a.arena_polys)):
            continue
        # The DECK SURFACE, which is `d["z"]` itself: `kit/decks.py` lays the slab from `z - thickness`
        # to `z`. It is NOT `z + thickness + parapet` — this row is what makes city-build mute the
        # parapet's render mesh (`skin.py` maps kind "railing" onto the deck's parapet), so there is
        # nothing up there to stand on and the rail hung up to 13 m over the slab (city-art r10,
        # 11-03: 902 of 1 500 railings floated).
        z = float(d["z"])
        segs = a._edge_segments(d["polygon"], RAIL_SEG, z)
        if segs:
            rows.append({"id": d["id"], "kind": "railing", "model": "s07", "segments": segs})
    # NOT on the viaducts: u02 is a 4.7 m concrete parapet with its own top rail, and a 1.4 m guard
    # rail standing on top of it is 1.1 M triangles nobody can see from a vehicle deck.
    return rows


def pylons(a: "Assigner") -> List[dict]:
    """s05 under every viaduct span (r2 item 4), at the piers the layout declares or synthesises.

    Ten of the eleven viaducts carry explicit piers; the eleventh gets them at its own
    `pier_spacing` so no span is left standing on nothing. city-build's skin drops their procedural
    pylons wherever a viaduct row exists, so every viaduct has to appear here.
    """
    s05 = a.models.get("s05")
    if s05 is None:
        return []
    rows: List[dict] = []
    for v in a.lay["viaducts"]:
        piers = v.get("piers") or synthesise_piers(v)
        segs = []
        for p in piers:
            h = float(p[2])
            segs.append({"pos": [round(p[0], 2), round(p[1], 2), 0.0], "yaw": 0.0,
                         "scale": [round(1.0, 3), round(1.0, 3), round(h / s05["size"][2], 3)],
                         "len": round(h, 2)})
        rows.append({"id": v["id"], "kind": "pylon", "model": "s05", "segments": segs})
    return rows


def synthesise_piers(v: dict) -> List[List[float]]:
    """Piers every `pier_spacing` along a viaduct the layout did not place them on."""
    pts = [tuple(p) for p in v["points"]]
    step = float(v.get("pier_spacing", 48.0))
    z = float(v["z"])
    out: List[List[float]] = []
    for i in range(len(pts) - 1):
        a0, b0 = pts[i], pts[i + 1]
        L = g.dist(a0, b0)
        if L < step * 0.5:
            continue
        n = max(1, int(round(L / step)))
        for k in range(n):
            t = (k + 0.5) / n
            out.append([a0[0] + (b0[0] - a0[0]) * t, a0[1] + (b0[1] - a0[1]) * t, z])
    return out


def shopfronts(a: "Assigner", near: Sequence[dict]) -> List[dict]:
    """s01 podiums along L1 street frontage within PODIUM_NEAR of an arena or the Spire plaza."""
    s01 = a.models.get("s01")
    if s01 is None:
        return []
    rows: List[dict] = []
    for b in near:
        if b["height"] < PODIUM_H * 1.5 or min(b["size"]) < 14.0:
            continue
        face = a.facing_target(b)
        if face is None:
            continue
        cx, cy = b["center"]
        toward = g.yaw_towards((cx, cy), face)
        # The podium's long axis is its local Y and has to run ALONG the frontage, so the yaw is
        # the street bearing turned a quarter; its local X is then the depth, facing the street.
        yaw = (toward + 90.0) % 360.0
        n = (math.sin(math.radians(toward)), math.cos(math.radians(toward)))
        half = half_extent(b, n)
        pos = [round(cx + n[0] * (half + PODIUM_DEPTH * 0.45), 2),
               round(cy + n[1] * (half + PODIUM_DEPTH * 0.45), 2), round(b["base_z"], 2)]
        rows.append({"id": b["id"] + "_podium", "kind": "street", "model": "s01", "pos": pos,
                     "yaw": round(yaw, 2),
                     "scale": [round(PODIUM_DEPTH / s01["size"][0], 3),
                               round(max(b["size"]) / s01["size"][1], 3),
                               round(PODIUM_H / s01["size"][2], 3)],
                     "host": b["id"]})
    return rows


def half_extent(b: dict, n: Sequence[float]) -> float:
    """Half-width of a rotated box along unit direction n (the support function of the box)."""
    a = math.radians(float(b.get("rot", 0.0)))
    ex = (math.cos(a), math.sin(a))
    ey = (-math.sin(a), math.cos(a))
    return (abs(n[0] * ex[0] + n[1] * ex[1]) * b["size"][0]
            + abs(n[0] * ey[0] + n[1] * ey[1]) * b["size"][1]) * 0.5


def gates(a: "Assigner") -> List[dict]:
    """s04 paifang at each arena's street entry."""
    s04 = a.models.get("s04")
    if s04 is None:
        return []
    rows: List[dict] = []
    for poly, aid in a.arenas:
        best = None
        for s in a.lay["streets"]:
            if s["kind"] == "alley":
                continue
            pts = [tuple(p) for p in s["points"]]
            for i in range(len(pts) - 1):
                mid = ((pts[i][0] + pts[i + 1][0]) * 0.5, (pts[i][1] + pts[i + 1][1]) * 0.5)
                dd = g.dist_to_poly(mid, poly)
                if dd > GATE_NEAR or (best and dd >= best[0]):
                    continue
                yaw = g.yaw_along(pts[i], pts[i + 1]) + 90.0
                best = (dd, {"id": "gate_" + aid, "kind": "street", "model": "s04",
                             "pos": [round(mid[0], 2), round(mid[1], 2), round(s["z"], 2)],
                             "yaw": round(yaw % 360.0, 2), "arena": aid})
        if best:
            rows.append(best[1])
    return rows


def skybridges(a: "Assigner") -> List[dict]:
    """s06 tube segments along every deck the layout marks as a skybridge."""
    s06 = a.models.get("s06")
    if s06 is None:
        return []
    seg_len = max(s06["size"][0], s06["size"][1])
    rows: List[dict] = []
    for d in a.lay["decks"]:
        if not d.get("skybridge") or len(d["polygon"]) < 2:
            continue
        poly = [tuple(p) for p in d["polygon"]]
        p0 = min(poly, key=lambda p: p[0] + p[1])
        p1 = max(poly, key=lambda p: p[0] + p[1])
        if g.dist(p0, p1) < seg_len * 0.5:
            continue
        segs = [{"pos": [round(m[0], 2), round(m[1], 2), round(d["z"], 2)],
                 "yaw": round(yaw, 2), "len": round(L, 2)}
                for m, yaw, L in a._along([p0, p1], seg_len, d["z"])]
        rows.append({"id": d["id"], "kind": "deck_full", "model": "s06", "segments": segs})
    return rows


def markets(a: "Assigner") -> List[dict]:
    """s03 stall rows along the kerb of the streets near the arenas (ART.md D3/D5 street life)."""
    s03 = a.models.get("s03")
    if s03 is None:
        return []
    step = max(s03["size"][0], s03["size"][1])
    rows: List[dict] = []
    for st in a.lay["streets"]:
        if st["kind"] == "avenue":
            continue
        pts = [tuple(p) for p in st["points"]]
        mid = ((pts[0][0] + pts[-1][0]) * 0.5, (pts[0][1] + pts[-1][1]) * 0.5)
        if not (g.dist(mid, a.spire_xy) <= MARKET_NEAR
                or any(g.dist_to_poly(mid, poly) <= MARKET_NEAR for poly in a.arena_polys)):
            continue
        kerb = a._offset(pts, st["width"] * 0.5 - 3.0)
        segs = [{"pos": [round(m[0], 2), round(m[1], 2), round(st["z"], 2)],
                 "yaw": round(yaw, 2), "len": round(L, 2)}
                for m, yaw, L in a._along(kerb, step, st["z"])]
        if segs:
            rows.append({"id": st["id"], "kind": "market", "model": "s03", "segments": segs})
    return rows


def metros(a: "Assigner") -> List[dict]:
    """s02 entrances on the street nearest each arena, one per arena plus the Spire plaza."""
    s02 = a.models.get("s02")
    if s02 is None:
        return []
    spots = [(g.centroid(poly), aid) for poly, aid in a.arenas] + [(a.spire_xy, "spire")]
    rows: List[dict] = []
    for centre, aid in spots:
        best = None
        for st in a.lay["streets"]:
            q, d, _ = g.polyline_closest(centre, [tuple(p) for p in st["points"]])
            if best is None or d < best[0]:
                best = (d, q, st)
        if best is None:
            continue
        _, q, st = best
        yaw = g.yaw_towards(centre, q)
        n = (math.sin(math.radians(yaw)), math.cos(math.radians(yaw)))
        off = st["width"] * 0.5 + 4.0
        rows.append({"id": "metro_" + aid, "kind": "street", "model": "s02",
                     "pos": [round(q[0] - n[0] * off, 2), round(q[1] - n[1] * off, 2),
                             round(st["z"], 2)],
                     "yaw": round(yaw % 360.0, 2)})
    return rows


def pipe_racks(a: "Assigner") -> List[dict]:
    """f03 runs along the foundry deck edges — the D6 pipe-rack language MAP.md asks for."""
    f03 = a.models.get("f03")
    if f03 is None:
        return []
    step = max(f03["size"][0], f03["size"][1])
    rows: List[dict] = []
    for d in a.lay["decks"]:
        if d.get("district") != "D6" or len(d["polygon"]) < 3:
            continue
        # `d["z"]` is the deck surface (see `railings`); adding the slab thickness again put every
        # rack 4 m over the deck it stands on.
        segs = a._edge_segments(d["polygon"], step, float(d["z"]))
        if segs:
            rows.append({"id": d["id"], "kind": "pipe_rack", "model": "f03", "segments": segs})
    return rows


def rooftops(a: "Assigner", rows: Sequence[dict]) -> List[dict]:
    """s08 machinery clusters on the roofs of the kit buildings whose top is a usable deck."""
    s08 = a.models.get("s08")
    if s08 is None:
        return []
    out: List[dict] = []
    for r in rows:
        if "flat_top" not in a.models.get(r["model"], {}).get("tags", []):
            continue
        w, d = r["box"][0], r["box"][1]
        if min(w, d) < 16.0 or r["height"] < 24.0:
            continue
        fit = min(1.0, min(w, d) * 0.30 / max(s08["size"][0], s08["size"][1]))
        # Deterministic jitter: the same building always gets the same cluster, in any rebuild.
        # crc32, not hash() — Python randomises string hashes per process.
        h = (zlib.crc32(r["id"].encode()) & 0xFFFF) / 65535.0
        off = ((h - 0.5) * w * 0.3, (((h * 7.0) % 1.0) - 0.5) * d * 0.3)
        out.append({"id": r["id"] + "_roof", "kind": "roof", "model": "s08",
                    "pos": [round(r["pos"][0] + off[0], 2), round(r["pos"][1] + off[1], 2),
                            round(r["pos"][2] + r["height"], 2)],
                    "yaw": round((h * 360.0) % 360.0, 2),
                    "scale": [round(fit, 3), round(fit, 3), round(fit, 3)]})
    return out


def near_arena(a: "Assigner") -> List[dict]:
    """Buildings within PODIUM_NEAR of an arena outline or the Spire plaza."""
    out = []
    for b in a.lay["buildings"]:
        c = (b["center"][0], b["center"][1])
        if g.dist(c, a.spire_xy) <= PODIUM_NEAR or any(
                g.dist_to_poly(c, poly) <= PODIUM_NEAR for poly in a.arena_polys):
            out.append(b)
    return out
