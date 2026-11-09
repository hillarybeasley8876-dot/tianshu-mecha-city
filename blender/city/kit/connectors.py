"""Connectors: one piece of geometry per level-graph edge (level-design 3.4).

Everything that goes UP wears the reserved cyan `mc_up_accent` (ART.md 2): ramps and stairs get a
lit handrail, lifts and catapults a lit shaft, vents a lit grille. `drop` and `edgejump` are
commitments rather than structures, so they only get a painted lip at the take-off edge.
"""
import math

from . import solid as solid_mod

RAIL_H = 4.5
LIFT_W = 3.0


def _railing(kit, solids, a, b, width):
    """Handrail plus posts on both sides of a sloped run."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    if length < 1e-3:
        return
    yaw = math.atan2(dy, dx)
    nx, ny = -math.sin(yaw), math.cos(yaw)
    for side in (-1.0, 1.0):
        ox, oy = nx * side * width * 0.5, ny * side * width * 0.5
        p0 = (a[0] + ox, a[1] + oy, a[2] + RAIL_H)
        p1 = (b[0] + ox, b[1] + oy, b[2] + RAIL_H)
        kit.sweep("mc_up_accent", [(-0.5, 0.0), (0.5, 0.0), (0.5, 0.8), (-0.5, 0.8)], [p0, p1],
                  closed_profile=True)
        n = max(1, int(length / 16.0))
        for k in range(n + 1):
            t = k / n
            px = a[0] + (b[0] - a[0]) * t + ox
            py = a[1] + (b[1] - a[1]) * t + oy
            pz = a[2] + (b[2] - a[2]) * t
            kit.box("mc_metal", (px, py, pz + RAIL_H * 0.5), (1.0, 1.0, RAIL_H), yaw)
        mid = ((a[0] + b[0]) * 0.5 + ox, (a[1] + b[1]) * 0.5 + oy,
               (a[2] + b[2]) * 0.5 + RAIL_H * 0.5)
        solids.box(mid, (length, 1.0, RAIL_H), yaw, False)


def ramp(kit, solids, con):
    path = con.get("path") or [con["from"], con["to"]]
    width = float(con["width"])
    pts = [(p[0], p[1], p[2]) for p in path]
    for a, b in zip(pts, pts[1:]):
        kit.sweep("mc_deck", [(-width * 0.5, 0.0), (width * 0.5, 0.0), (width * 0.5, -3.0),
                              (-width * 0.5, -3.0)], [a, b], closed_profile=True)
        solid_mod.ramp_solid(solids, a, b, width, 3.0)
        _railing(kit, solids, a, b, width)


def stairs(kit, solids, con):
    """Terraced flights: 16-32 m steps (level-design 3.4), with a walkable collision ramp."""
    path = con.get("path") or [con["from"], con["to"]]
    width = float(con["width"])
    flights = int(con.get("params", {}).get("flights", 2))
    pts = [(p[0], p[1], p[2]) for p in path]
    for a, b in zip(pts, pts[1:]):
        solid_mod.ramp_solid(solids, a, b, width, 3.0)
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        yaw = math.atan2(b[1] - a[1], b[0] - a[0])
        n = max(flights, int(math.ceil(abs(b[2] - a[2]) / 26.0)))
        for k in range(n):
            t0, t1 = k / n, (k + 1) / n
            z = a[2] + (b[2] - a[2]) * t1
            px = a[0] + (b[0] - a[0]) * (t0 + t1) * 0.5
            py = a[1] + (b[1] - a[1]) * (t0 + t1) * 0.5
            kit.box("mc_concrete", (px, py, z - 1.5), (length / n + 1.0, width, 3.0), yaw)
            kit.box("mc_stone", (px, py, z - (z - a[2] - (b[2] - a[2]) * t0) * 0.5),
                    (length / n * 0.6, width * 0.9, max(2.0, abs(b[2] - a[2]) / n * 0.5)), yaw)
        _railing(kit, solids, a, b, width)


def _shaft(kit, solids, con, pad, role="mc_concrete", open_top=True):
    """Corner columns + guide rails for a lift / catapult / vent shaft."""
    x, y = float(con["from"][0]), float(con["from"][1])
    lo = min(float(con["from"][2]), float(con["to"][2]))
    hi = max(float(con["from"][2]), float(con["to"][2]))
    hw, hd = float(pad[0]) * 0.5, float(pad[1]) * 0.5
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            kit.box(role, (x + sx * hw, y + sy * hd, (lo + hi) * 0.5), (LIFT_W, LIFT_W, hi - lo))
            solids.box((x + sx * hw, y + sy * hd, (lo + hi) * 0.5), (LIFT_W, LIFT_W, hi - lo),
                       0.0, False)
    for sx in (-1.0, 1.0):
        kit.box("mc_up_accent", (x + sx * (hw - 0.6), y, (lo + hi) * 0.5), (1.2, 1.2, hi - lo))
    if not open_top:
        kit.box(role, (x, y, hi + 2.0), (hw * 2.0 + 8.0, hd * 2.0 + 8.0, 4.0))
    return lo, hi, hw, hd


def lift(kit, solids, con):
    pad = con.get("params", {}).get("pad", [40.0, 40.0])
    lo, hi, hw, hd = _shaft(kit, solids, con, pad)
    x, y = float(con["from"][0]), float(con["from"][1])
    kit.box("mc_metal", (x, y, lo + 1.5), (hw * 2.0 - 2.0, hd * 2.0 - 2.0, 3.0))
    kit.box("mc_up_accent", (x, y, lo + 3.4), (hw * 1.6, hd * 1.6, 0.8))
    solids.box((x, y, lo + 1.5), (hw * 2.0 - 2.0, hd * 2.0 - 2.0, 3.0), 0.0, False)
    kit.box("mc_metal", (x, y, hi + 3.0), (hw * 2.0 + 6.0, hd * 2.0 + 6.0, 6.0))


def vcat(kit, solids, con):
    """Vertical catapult: a pad with a lit ring and four guide masts."""
    pad = con.get("params", {}).get("pad", [44.0, 44.0])
    x, y, z = (float(v) for v in con["from"])
    hw, hd = float(pad[0]) * 0.5, float(pad[1]) * 0.5
    kit.box("mc_metal", (x, y, z + 1.0), (hw * 2.0, hd * 2.0, 2.0))
    solids.box((x, y, z + 1.0), (hw * 2.0, hd * 2.0, 2.0), 0.0, False)
    kit.cylinder("mc_up_accent", (x, y, z + 2.4), hw * 0.82, 0.8, 32)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            kit.box("mc_metal", (x + sx * hw, y + sy * hd, z + 14.0), (2.0, 2.0, 24.0))
    kit.box("mc_up_accent", (x, y, z + 26.0), (hw * 2.0, 2.0, 2.0))


def vent(kit, solids, con):
    """Updraft shaft: a lined throat with a lit grille at the bottom."""
    pad = con.get("params", {}).get("pad", [36.0, 36.0])
    lo, hi, hw, hd = _shaft(kit, solids, con, pad, open_top=True)
    x, y = float(con["from"][0]), float(con["from"][1])
    kit.box("mc_metal", (x, y, lo + 0.6), (hw * 2.0, hd * 2.0, 1.2))
    n = max(3, int(hw / 4.0))
    for k in range(n):
        px = x - hw + (hw * 2.0) * (k + 0.5) / n
        kit.box("mc_up_accent", (px, y, lo + 1.6), (hw * 2.0 / n * 0.5, hd * 1.8, 0.8))
    solids.box((x, y, lo + 0.6), (hw * 2.0, hd * 2.0, 1.2), 0.0, False)


def lcat(kit, solids, con):
    """Long catapult: a launch rail aimed at the landing point."""
    a = [float(v) for v in con["from"]]
    b = [float(v) for v in con["to"]]
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    if length < 1e-3:
        return
    yaw = math.atan2(dy, dx)
    run = min(length, 120.0)
    for side in (-1.0, 1.0):
        ox, oy = -math.sin(yaw) * side * 14.0, math.cos(yaw) * side * 14.0
        kit.box("mc_metal", (a[0] + dx / length * run * 0.5 + ox,
                             a[1] + dy / length * run * 0.5 + oy, a[2] + 2.0),
                (run, 3.0, 4.0), yaw)
    kit.box("mc_metal", (a[0], a[1], a[2] + 1.0), (44.0, 40.0, 2.0), yaw)
    solids.box((a[0], a[1], a[2] + 1.0), (44.0, 40.0, 2.0), yaw, False)
    kit.box("mc_up_accent", (a[0], a[1], a[2] + 2.4), (36.0, 32.0, 0.8), yaw)


def lip(kit, solids, con):
    """drop / edgejump: a painted take-off lip so the commitment reads."""
    x, y, z = (float(v) for v in con["from"])
    tx, ty = float(con["to"][0]), float(con["to"][1])
    yaw = math.atan2(ty - y, tx - x)
    width = float(con["width"])
    kit.box("mc_up_accent", (x, y, z + 0.5), (3.0, width, 1.0), yaw)


BUILDERS = {"ramp": ramp, "stairs": stairs, "lift": lift, "vcat": vcat, "vent": vent,
            "lcat": lcat, "drop": lip, "edgejump": lip, "path": lip, "rail": lip}


def build(kit, solids, layout):
    for con in layout.connectors:
        fn = BUILDERS.get(con["kind"])
        if fn is None:
            print("city-build: no connector builder for kind %r (%s)" % (con["kind"], con["id"]))
            continue
        fn(kit, solids, con)
