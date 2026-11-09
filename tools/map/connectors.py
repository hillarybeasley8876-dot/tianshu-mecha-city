"""Connector stage: every non-corridor graph edge becomes exactly one connector.

Kinds follow the dossier §3.4 palette. Ramps carry an explicit `path` polyline so the grade
can be checked (and so the Blender build can extrude a real ramp); the Knot's ramps are
helices around the interchange centre, everything else is straight or switchbacked.
"""
from __future__ import annotations

import math

import geom
import mapconst as C

WIDTH = {"ramp": 32.0, "edgejump": 24.0, "stairs": 28.0, "lift": 40.0, "vcat": 44.0,
         "lcat": 40.0, "vent": 36.0, "drop": 24.0}
SPIRAL_CENTRES = {"knot": (-470.0, -40.0, 130.0)}   # x, y, max radius for a helix


def _grade(path: list[list[float]]) -> float:
    rise = abs(path[-1][2] - path[0][2])
    run = sum(math.dist(a[:2], b[:2]) for a, b in zip(path, path[1:]))
    return math.degrees(math.atan2(rise, run)) if run else 90.0


def _helix(p0: list[float], p1: list[float], centre: tuple[float, float, float],
           max_deg: float) -> list[list[float]]:
    """Spiral around `centre` from p0 to p1, adding turns until the grade fits."""
    cx, cy, r_max = centre
    r0 = math.hypot(p0[0] - cx, p0[1] - cy)
    r1 = math.hypot(p1[0] - cx, p1[1] - cy)
    a0 = math.atan2(p0[1] - cy, p0[0] - cx)
    a1 = math.atan2(p1[1] - cy, p1[0] - cx)
    rise = abs(p1[2] - p0[2])
    need = rise / math.tan(math.radians(max_deg)) * 1.15
    turns = 0
    while True:
        sweep = (a1 - a0) % (2 * math.pi) + turns * 2 * math.pi
        if sweep <= 0:
            sweep += 2 * math.pi
        steps = max(8, int(sweep / 0.18))
        path = []
        for i in range(steps + 1):
            f = i / steps
            r = r0 + (r1 - r0) * f
            ang = a0 + sweep * f
            path.append([round(cx + max(r, 6.0) * math.cos(ang), 1),
                         round(cy + max(r, 6.0) * math.sin(ang), 1),
                         round(p0[2] + (p1[2] - p0[2]) * f, 1)])
        path[0], path[-1] = [round(v, 1) for v in p0], [round(v, 1) for v in p1]
        run = sum(math.dist(a[:2], b[:2]) for a, b in zip(path, path[1:]))
        if run >= need or turns >= 3:
            return path
        turns += 1
        if r_max and max(r0, r1) > r_max:
            return path


def _switchback(p0: list[float], p1: list[float], max_deg: float) -> list[list[float]]:
    """Zigzag a ramp that is too steep to run straight (mech service ramp <= 20 deg)."""
    run = math.dist(p0[:2], p1[:2])
    rise = abs(p1[2] - p0[2])
    need = rise / math.tan(math.radians(max_deg)) * 1.12
    legs = max(2, math.ceil(need / max(run, 1.0)))
    ux, uy = (p1[0] - p0[0]) / (run or 1), (p1[1] - p0[1]) / (run or 1)
    px, py = -uy, ux
    jog = need / legs
    path = [[round(v, 1) for v in p0]]
    for i in range(legs):
        f0, f1 = i / legs, (i + 1) / legs
        side = jog * (1 if i % 2 == 0 else -1)
        mid = [p0[0] + ux * run * f1 + px * side, p0[1] + uy * run * f1 + py * side,
               p0[2] + (p1[2] - p0[2]) * f1]
        path.append([round(v, 1) for v in mid])
    path.append([round(v, 1) for v in p1])
    return path


def _stair_path(p0: list[float], p1: list[float], flights: int) -> list[list[float]]:
    """Terrace stair: `flights` runs of <= 32 m rise with landings between them."""
    path = [[round(v, 1) for v in p0]]
    run = math.dist(p0[:2], p1[:2])
    ux, uy = ((p1[0] - p0[0]) / run, (p1[1] - p0[1]) / run) if run else (0.0, 0.0)
    px, py = -uy, ux
    for i in range(1, flights):
        f = i / flights
        side = 26.0 * (1 if i % 2 else -1)
        path.append([round(p0[0] + ux * run * f + px * side, 1),
                     round(p0[1] + uy * run * f + py * side, 1),
                     round(p0[2] + (p1[2] - p0[2]) * f, 1)])
    path.append([round(v, 1) for v in p1])
    return path


def spiral_centre_for(p0: list[float], p1: list[float]) -> tuple[float, float, float] | None:
    for centre in SPIRAL_CENTRES.values():
        if all(math.hypot(p[0] - centre[0], p[1] - centre[1]) <= centre[2] for p in (p0, p1)):
            return centre
    return None


def build(graph: dict, nodes: dict) -> list[dict]:
    """One connector per non-corridor edge, carrying its geometry and its edge tags."""
    out: list[dict] = []
    for edge in graph["edges"]:
        if edge["kind"] in ("path", "rail", "tunnel"):
            continue
        p0, p1 = nodes[edge["from"]]["pos"], nodes[edge["to"]]["pos"]
        kind = edge["kind"]
        con = {"id": f"con_{edge['from']}_{edge['to']}_{kind}",
               "edge": [edge["from"], edge["to"]], "kind": kind,
               "from": [round(v, 1) for v in p0], "to": [round(v, 1) for v in p1],
               "width": WIDTH[kind], "tags": list(edge.get("tags", []))}
        if not edge["bidir"]:
            con["oneway"] = True
        if kind == "ramp":
            centre = spiral_centre_for(p0, p1)
            path = _helix(p0, p1, centre, C.MAX_RAMP_DEG) if centre else \
                _switchback(p0, p1, C.MAX_RAMP_DEG)
            if _grade(path) > C.MAX_RAMP_DEG and not centre:
                path = _switchback(p0, p1, C.MAX_RAMP_DEG * 0.8)
            con["path"] = path
            con["grade_deg"] = round(_grade(path), 1)
            if centre:
                con["params"] = {"spiral": True, "radius": round(
                    math.hypot(p0[0] - centre[0], p0[1] - centre[1]), 1)}
        elif kind == "stairs":
            flights = next((int(t.split(":")[1]) for t in con["tags"]
                            if t.startswith("steps:")), 1)
            con["path"] = _stair_path(p0, p1, flights)
            con["params"] = {"flights": flights, "flight_rise": round(abs(p1[2] - p0[2]) / flights, 1)}
        elif kind in ("lift", "vcat", "vent"):
            con["params"] = {"pad": [con["width"], con["width"]],
                             "rise": round(abs(p1[2] - p0[2]), 1)}
        elif kind == "lcat":
            con["params"] = {"range": round(math.dist(p0[:2], p1[:2]), 1),
                             "no_boost_s": 1.5}
        out.append(con)
    return out


def crest_crossings(connectors: list[dict], crest) -> list[tuple[float, float]]:
    """Where a free-climb connector crosses the escarpment: those points get a lip."""
    pts: list[tuple[float, float]] = []
    for con in connectors:
        if con["kind"] not in ("edgejump", "stairs"):
            continue
        if abs(con["to"][2] - con["from"][2]) > C.FREE_CLIMB:
            continue
        seg = geom.line([con["from"][:2], con["to"][:2]])
        hit = seg.intersection(crest)
        for part in getattr(hit, "geoms", [hit]):
            if part.is_empty:
                continue
            c = part.centroid
            pts.append((round(c.x, 1), round(c.y, 1)))
    return pts
