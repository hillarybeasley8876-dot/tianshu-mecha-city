"""Corridors: streets, viaducts, the Skyrail and the tunnels.

Streets are flat ribbons on the ground crust (they add kerbs and a road surface, no collision —
the crust is the floor). Viaducts and rails are real structure: deck slab, barriers, pylons with
capitals, and an underside with beams so they read as supported from below (MAP 4 `carries`).
Tunnels are lined boxes with lit niches and open portals.
"""
import math

from lib import geo

from . import builder
from . import solid as solid_mod

KERB = 3.0
KERB_H = 1.2
BARRIER = 2.5
BARRIER_H = 5.0
PIER_W = 14.0
BEAM_DEPTH = 4.0


def _path3(points, z):
    return [(p[0], p[1], z) for p in points]


def _offset_path(path, offset):
    """Parallel polyline `offset` metres to the right of travel."""
    out = []
    n = len(path)
    for i, p in enumerate(path):
        a, b = path[max(0, i - 1)], path[min(n - 1, i + 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        nx, ny = (0.0, 0.0) if length < 1e-6 else (-dy / length, dx / length)
        out.append((p[0] + nx * offset, p[1] + ny * offset, p[2]))
    return out


def _ribbon(kit, solids, role, path, half, thickness, collide=True, occlude=False):
    """A closed slab swept along a path: top face at the path height."""
    prof = [(-half, 0.0), (half, 0.0), (half, -thickness), (-half, -thickness)]
    kit.sweep(role, prof, path, closed_profile=True)
    if collide:
        for a, b in zip(path, path[1:]):
            _seg_solid(solids, a, b, half * 2.0, thickness, occlude)


def _seg_solid(solids, a, b, width, thickness, occlude=False):
    if math.hypot(b[0] - a[0], b[1] - a[1]) < 1e-3:
        return
    solid_mod.ramp_solid(solids, a, b, width, thickness, occlude)


def street(kit, solids, s):
    """Road surface, kerbs and (for avenues) a lit centre line."""
    z = float(s["z"])
    width = float(s["width"])
    path = _path3(s["points"], z + 0.25)
    _ribbon(kit, solids, "mc_road", path, width * 0.5 - KERB, 0.5, collide=False)
    for side in (-1.0, 1.0):
        kerb = _offset_path(path, side * (width * 0.5 - KERB * 0.5))
        _ribbon(kit, solids, "mc_concrete", kerb, KERB * 0.5, KERB_H + 0.25, collide=False)
    if s["kind"] == "avenue":
        centre = _offset_path(path, 0.0)
        kit.sweep("mc_up_accent", [(-0.6, 0.35), (0.6, 0.35)], centre)


def viaduct(kit, solids, v, layout, skin=None):
    """Deck slab + barriers + pylons with capitals + an underside of beams.

    Kit skin mode: city-kit's railings replace the barriers and its pylon model replaces the
    piers, so a skinned viaduct mutes those two and keeps the drivable deck slab and all collision.
    """
    z = float(v["z"])
    half = float(v["width"]) * 0.5
    path = _path3(v["points"], z)
    edge_kit = builder.MutedKit(v["id"]) if skin is not None and skin.viaduct(v["id"]) else kit
    _ribbon(kit, solids, "mc_deck", path, half, 6.0, True, True)
    for side in (-1.0, 1.0):
        edge = _offset_path(path, side * (half - BARRIER * 0.5))
        edge_kit.sweep("mc_concrete",
                       [(-BARRIER * 0.5, 0.0), (BARRIER * 0.5, 0.0), (BARRIER * 0.5, BARRIER_H),
                        (-BARRIER * 0.5, BARRIER_H)], [(p[0], p[1], p[2] + 0.2) for p in edge],
                       closed_profile=True)
        edge_kit.sweep("mc_up_accent", [(-0.5, BARRIER_H + 0.2), (0.5, BARRIER_H + 0.2)],
                       [(p[0], p[1], p[2]) for p in edge])
        solids_from_path(solids, edge, BARRIER, BARRIER_H, z + 0.2)
        beam = _offset_path(path, side * half * 0.55)
        kit.sweep("mc_concrete", [(-2.0, -6.0), (2.0, -6.0), (2.0, -6.0 - BEAM_DEPTH),
                                  (-2.0, -6.0 - BEAM_DEPTH)], beam, closed_profile=True)
    for px, py, pz in v.get("piers", []):
        _pier(edge_kit, solids, px, py, pz - 6.0, _ground_z(layout, px, py))


def viaduct_edges(v):
    """The two barrier polylines of one viaduct (city-kit lays railings along them)."""
    z = float(v["z"])
    half = float(v["width"]) * 0.5
    path = _path3(v["points"], z)
    out = []
    for side, tag in ((-1.0, "left"), (1.0, "right")):
        pts = _offset_path(path, side * (half - BARRIER * 0.5))
        out.append({"id": "%s_%s" % (v["id"], tag), "points": [[p[0], p[1]] for p in pts],
                    "z": z, "kind": "viaduct", "closed": False,
                    "height": BARRIER_H, "thickness": BARRIER, "viaduct": v["id"]})
    return out


def solids_from_path(solids, path, width, height, z):
    for a, b in zip(path, path[1:]):
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        if length < 1e-3:
            continue
        mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, z + height * 0.5)
        solids.box(mid, (length + 0.5, width, height), math.atan2(dy, dx), False)


def _pier(kit, solids, x, y, z_top, z_bottom):
    """A viaduct pylon: shaft, flared capital, base pad."""
    h = z_top - z_bottom
    if h <= 2.0:
        return
    kit.box("mc_concrete", (x, y, z_bottom + h * 0.5), (PIER_W, PIER_W, h))
    kit.box("mc_concrete", (x, y, z_top - 2.0), (PIER_W + 6.0, PIER_W + 6.0, 4.0))
    kit.box("mc_concrete", (x, y, z_bottom + 1.5), (PIER_W + 5.0, PIER_W + 5.0, 3.0))
    solids.box((x, y, z_bottom + h * 0.5), (PIER_W, PIER_W, h), 0.0, True)


def rail(kit, solids, r, layout):
    """Skyrail beam: 24 m walkway on twin guide beams, carried by pylons where nothing else does."""
    z = float(r["z"])
    half = float(r["width"]) * 0.5
    path = _path3(r["points"], z)
    _ribbon(kit, solids, "mc_deck", path, half, 4.0, True, True)
    for side in (-1.0, 1.0):
        edge = _offset_path(path, side * (half - 1.5))
        kit.sweep("mc_metal", [(-1.2, 1.2), (1.2, 1.2), (1.2, -1.2), (-1.2, -1.2)],
                  [(p[0], p[1], p[2] + 1.2) for p in edge], closed_profile=True)
        solids_from_path(solids, edge, 2.4, 2.4, z)
        beam = _offset_path(path, side * half * 0.5)
        kit.sweep("mc_metal", [(-2.5, -4.0), (2.5, -4.0), (2.5, -4.0 - BEAM_DEPTH),
                               (-2.5, -4.0 - BEAM_DEPTH)], beam, closed_profile=True)
    centre = _offset_path(path, 0.0)
    kit.sweep("mc_up_accent", [(-1.0, 0.5), (1.0, 0.5)], centre)
    for x, y, _ in _pier_stations(r["points"], 96.0):
        if _under_building(layout, x, y, z):
            continue
        _pier(kit, solids, x, y, z - 8.0, _ground_z(layout, x, y))


def _pier_stations(points, spacing):
    out, carry = [], 0.0
    for a, b in zip(points, points[1:]):
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        d = spacing - carry
        while d <= length:
            t = d / length
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, 0.0))
            d += spacing
        carry = length - (d - spacing)
    return out


def _under_building(layout, x, y, z):
    for b in layout.buildings:
        w, d = b["size"]
        if (abs(x - b["center"][0]) < w * 0.6 and abs(y - b["center"][1]) < d * 0.6
                and float(b["base_z"]) < z < float(b["base_z"]) + float(b["height"])):
            return True
    return False


def _ground_z(layout, x, y):
    crest = layout.terrain["escarpment"]["crest"]
    for a, b in zip(crest, crest[1:]):
        if a[0] - 1e-6 <= x <= b[0] + 1e-6:
            t = (x - a[0]) / max(1e-6, b[0] - a[0])
            return float(layout.terrain["escarpment"]["height"]) if y > a[1] + (b[1] - a[1]) * t else 0.0
    return 0.0


def tunnel(kit, solids, t):
    """Lined tube: floor, haunched walls, ceiling, lit niches and open portals."""
    z = float(t["z"])
    half = float(t["width"]) * 0.5
    clear = float(t["clear"])
    path = _path3(t["points"], z)
    _ribbon(kit, solids, "mc_concrete", path, half, 4.0, True, False)
    for side in (-1.0, 1.0):
        wall = _offset_path(path, side * (half + 3.0))
        kit.sweep("mc_concrete", [(-3.0, 0.0), (3.0, 0.0), (3.0, clear), (-3.0, clear)],
                  wall, closed_profile=True)
        solids_from_path(solids, wall, 6.0, clear, z)
        kit.sweep("mc_up_accent", [(-0.8, 3.0), (0.8, 3.0)],
                  [(p[0], p[1], p[2]) for p in _offset_path(path, side * (half - 0.5))])
    kit.sweep("mc_concrete", [(-half - 6.0, clear), (half + 6.0, clear),
                              (half + 6.0, clear + 2.0), (-half - 6.0, clear + 2.0)],
              path, closed_profile=True)
    solids_from_path(solids, path, (half + 6.0) * 2.0, 2.0, z + clear)
    for x, y, _ in _pier_stations(t["points"], 64.0):
        # Lit maintenance niches, recessed into the lining (never in the running width).
        for side in (-1.0, 1.0):
            nx, ny = _normal_at(t["points"], x, y, side * (half + 1.0))
            kit.box("mc_panel_white", (nx, ny, z + clear * 0.45), (10.0, 4.0, clear * 0.6))
            kit.box("mc_up_accent", (nx, ny, z + clear * 0.45 + clear * 0.32),
                    (8.0, 2.0, 1.0))
    for p in (path[0], path[-1]):
        _portal(kit, p, half, clear, z)


def _normal_at(points, x, y, offset):
    """The point `offset` metres to the side of the corridor near (x, y)."""
    best = None
    for a, b in zip(points, points[1:]):
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        if length < 1e-6:
            continue
        t = max(0.0, min(1.0, ((x - a[0]) * dx + (y - a[1]) * dy) / (length * length)))
        px, py = a[0] + dx * t, a[1] + dy * t
        d = math.hypot(x - px, y - py)
        if best is None or d < best[0]:
            best = (d, px - dy / length * offset, py + dx / length * offset)
    return (best[1], best[2]) if best else (x, y)


def _portal(kit, p, half, clear, z):
    """A ring frame around a tunnel mouth: two jambs and a lintel, so the opening stays clear."""
    t = 7.0
    for side in (-1.0, 1.0):
        kit.box("mc_stone", (p[0] + side * (half + t * 0.5), p[1], z + clear * 0.5),
                (t, t, clear))
    kit.box("mc_stone", (p[0], p[1], z + clear + t * 0.5), (half * 2.0 + t * 2.0, t, t))


def build(kit, solids, layout, skin=None):
    for s in layout.streets:
        street(kit, solids, s)
    for v in layout.viaducts:
        viaduct(kit, solids, v, layout, skin)
    for r in layout.rails:
        rail(kit, solids, r, layout)
    for t in layout.tunnels:
        tunnel(kit, solids, t)
