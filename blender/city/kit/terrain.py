"""Terrain: escarpment, plateau, canal, docks and the ground crust the lower city stands on.

The crust is one slab at z=0..-6 with holes cut for the canal, the dock trench, the sunken court,
lift shafts and every ramp that dives below it; the plateau is a second slab at +32 north of the
crest. The escarpment between them is a retaining wall with stepped terraces and the two `lips`
(MAP 3) left open as ramps.
"""
import math

import bpy

from . import solid as solid_mod

CRUST = 6.0
PLATEAU_CRUST = 6.0
BANK_DEPTH = 20.0
WALL_T = 8.0


def boundary_edges(poly, half=700.0, eps=0.5):
    """Polygon edges that are NOT on the map boundary (the ones that need a wall)."""
    out = []
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        on_x = abs(abs(a[0]) - half) < eps and abs(abs(b[0]) - half) < eps
        on_y = abs(abs(a[1]) - half) < eps and abs(abs(b[1]) - half) < eps
        if not on_x and not on_y:
            out.append((a, b))
    return out


def wall_along(kit, solids, role, polyline, z0, z1, thickness, occlude=False, closed=False):
    """A thick wall following a polyline: one box per edge (corners overlap invisibly)."""
    n = len(polyline)
    last = n if closed else n - 1
    for i in range(last):
        a, b = polyline[i], polyline[(i + 1) % n]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        if length < 1e-3:
            continue
        yaw = math.atan2(dy, dx)
        mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, (z0 + z1) * 0.5)
        size = (length + thickness * 0.5, thickness, z1 - z0)
        kit.box(role, mid, size, yaw)
        solids.box(mid, size, yaw, occlude)


def ground_cuts(layout, z_lo, z_hi):
    """Every polygon the crust at z_lo..z_hi must be open at: the canal, the dock trench, the
    sunken court, and any lift/vent/catapult shaft or descending ramp that pierces it.
    They overlap freely, so the crust is cut with a boolean (kit.boolop)."""
    cuts = []
    if z_hi > -CRUST - 1.0:
        cuts.append(("canal", layout.terrain["canal"]["polygon"]))
        cuts.append(("docks", layout.terrain["docks"]["polygon"]))
        for deck in layout.decks:
            if deck["kind"] == "plaza" and float(deck["z"]) < z_hi - 1.0:
                cuts.append((deck["id"], deck["polygon"]))
    for con in layout.connectors:
        pad = con.get("params", {}).get("pad")
        lo = min(float(con["from"][2]), float(con["to"][2]))
        hi = max(float(con["from"][2]), float(con["to"][2]))
        if not (lo < z_hi - 0.5 and hi > z_lo + 0.5):
            continue
        if con["kind"] in ("lift", "vent", "vcat") and pad:
            cuts.append((con["id"], _pad_poly(con["from"], pad)))
        if con["kind"] in ("ramp", "stairs"):
            path = con.get("path") or [con["from"], con["to"]]
            for poly in _trench_polys(path, float(con["width"]) + 8.0, z_hi):
                cuts.append((con["id"], poly))
    return [c for _, c in cuts if len(c) >= 3]


def _trench_polys(path, width, z_max):
    """The trench a descending ramp or stairs cuts through the crust, as ONE RECTANGLE PER
    SEGMENT plus a square at every joint.

    It used to be a single mitred outline, which self-intersects at a bend. Blender's exact
    boolean resolves a self-intersecting cutter by the winding rule and an even-odd
    point-in-polygon test does not, so the two disagreed by up to 1.6 m and the C18 gate read the
    difference as a hole in the ground beside `con_W7_U3_ramp` (lead, r9). Separate rectangles
    are unambiguous to both, and `markers.py` exports the same list as the crust's holes.
    """
    segs = [(a, b) for a, b in zip(path, path[1:]) if min(a[2], b[2]) < z_max - 0.5]
    if not segs:
        return []
    hw = width * 0.5
    out = []
    for a, b in segs:
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        if length < 1e-6:
            continue
        nx, ny = -dy / length * hw, dx / length * hw
        out.append([(a[0] + nx, a[1] + ny), (b[0] + nx, b[1] + ny),
                    (b[0] - nx, b[1] - ny), (a[0] - nx, a[1] - ny)])
    for p in [segs[0][0]] + [b for _, b in segs]:
        out.append([(p[0] - hw, p[1] - hw), (p[0] + hw, p[1] - hw),
                    (p[0] + hw, p[1] + hw), (p[0] - hw, p[1] + hw)])
    return out


def _pad_poly(pos, pad):
    hw, hd = float(pad[0]) * 0.5 + 2.0, float(pad[1]) * 0.5 + 2.0
    return [(pos[0] - hw, pos[1] - hd), (pos[0] + hw, pos[1] - hd),
            (pos[0] + hw, pos[1] + hd), (pos[0] - hw, pos[1] + hd)]


def build(kit, solids, layout, col, podium_walls=None):
    """Emit all terrain into `kit` / `solids`. `col` is the scratch collection the boolean
    for the ground crust needs. `podium_walls`, when given, collects the escarpment retaining-wall
    segments as facade footprints for city-art (see `_escarpment`)."""
    from . import boolop
    half = float(layout.bounds["half"])
    terrain = layout.terrain
    esc = terrain["escarpment"]
    crest = [tuple(p) for p in esc["crest"]]
    plateau = [tuple(p) for p in terrain["plateau"]["polygon"]]
    canal = [tuple(p) for p in terrain["canal"]["polygon"]]
    docks = [tuple(p) for p in terrain["docks"]["polygon"]]
    height = float(esc["height"])

    square = [(-half, -half), (half, -half), (half, half), (-half, half)]
    # The plateau is cut, not passed as an inner boundary: it runs to the map edge (y = +half), so
    # it is a notch rather than a hole and `Kit.slab`'s scanfill mis-triangulates it — measured
    # 173 642 m2 of crust instead of 1 190 410 (probe: blender/city/probe_crust.py).
    crust = boolop.difference("mc_crust", square, -CRUST, 0.0,
                              ground_cuts(layout, -CRUST, 0.0) + [plateau], col)
    boolop.add_mesh(kit, solids, "mc_concrete", crust)
    bpy.data.meshes.remove(crust)
    plateau_cuts = ground_cuts(layout, height - PLATEAU_CRUST, height)
    top = boolop.difference("mc_plateau", plateau, height - PLATEAU_CRUST, height,
                            plateau_cuts, col)
    boolop.add_mesh(kit, solids, "mc_deck", top)
    bpy.data.meshes.remove(top)

    _escarpment(kit, solids, crest, esc, half, height, podium_walls)
    _canal(kit, solids, canal, terrain["canal"], half)
    _docks(kit, solids, docks, terrain["docks"], half)
    for deck in layout.decks:
        if deck["kind"] == "plaza" and float(deck["z"]) < -1.0:
            poly = [tuple(p) for p in deck["polygon"]]
            wall_along(kit, solids, "mc_stone", poly, float(deck["z"]), 0.0, 6.0, False, True)
    _soft_walls(kit, solids, half, float(layout.bounds["skyline_half"]),
                float(layout.bounds.get("ceiling", 260.0)))


def _escarpment(kit, solids, crest, esc, half, height, podium_walls=None):
    """Retaining wall + stepped terraces + the `lips` (open ramps through the crest).

    The retaining wall is what a player reads as the district's PODIUM: around the A4 megablock
    quarter it is a continuous 32 m face with terraces on it. It is terrain, not a building, so it
    has no row in the design layout's `buildings` and city-art's facade mask gives it no windows at
    eye level (city-art r3). Each segment is therefore also recorded as a footprint in
    `podium_walls`, which `markers.py` exports for them."""
    lips = [(tuple(l["pos"]), float(l["width"])) for l in esc.get("lips", [])]
    for a, b in zip(crest, crest[1:]):
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        if length < 1e-3:
            continue
        yaw = math.atan2(dy, dx)
        n = max(1, int(round(length / 24.0)))
        for k in range(n):
            t = (k + 0.5) / n
            cx, cy = a[0] + dx * t, a[1] + dy * t
            if any(math.hypot(cx - lp[0], cy - lp[1]) < lw * 0.5 + 4.0 for lp, lw in lips):
                continue
            seg_len = length / n + 0.5
            kit.box("mc_stone", (cx, cy, height * 0.5), (seg_len, WALL_T, height), yaw)
            solids.box((cx, cy, height * 0.5), (seg_len, WALL_T, height), yaw, True)
            if podium_walls is not None:
                podium_walls.append({
                    "id": "podium_wall_%d" % len(podium_walls),
                    "kind": "escarpment",
                    "center": [round(cx, 2), round(cy, 2)],
                    "size": [round(seg_len, 2), WALL_T],
                    "yaw_deg": round(math.degrees(yaw), 2),
                    "base_z": 0.0,
                    "height": round(height, 2),
                    "outward": [round(math.sin(yaw), 4), round(-math.cos(yaw), 4)],
                })
            for i, tz in enumerate((height * 0.28, height * 0.56, height * 0.82)):
                depth = 14.0 - i * 3.0
                off = WALL_T * 0.5 + depth * 0.5
                ox = cx + math.sin(yaw) * off
                oy = cy - math.cos(yaw) * off
                kit.box("mc_deck", (ox, oy, tz), (seg_len, depth, 2.5), yaw)
                solids.box((ox, oy, tz), (seg_len, depth, 2.5), yaw, False)
    for (lx, ly), lw in lips:
        _lip_ramp(kit, solids, lx, ly, lw, height)


def _lip_ramp(kit, solids, lx, ly, width, height):
    """A 20-degree service ramp climbing the escarpment through a lip."""
    run = height / math.tan(math.radians(20.0))
    a = (lx, ly - run * 0.5, 0.0)
    b = (lx, ly + run * 0.5, height)
    kit.sweep("mc_deck", [(-width * 0.5, 0.0), (width * 0.5, 0.0), (width * 0.5, -3.0),
                          (-width * 0.5, -3.0)], [a, b], closed_profile=True)
    solid_mod.ramp_solid(solids, a, b, width, 3.0)
    for side in (-1.0, 1.0):
        kit.sweep("mc_metal", [(side * width * 0.5, 0.0), (side * width * 0.5, 4.0)],
                  [(a[0], a[1], a[2]), (b[0], b[1], b[2])])


def _canal(kit, solids, canal, spec, half):
    """Water plane, bed and quay walls along the shoreline (map-boundary edges get none)."""
    water_z = float(spec["water_z"])
    bank_z = float(spec["bank_z"])
    kit.slab("mc_water", canal, [], water_z - 1.0, water_z)
    kit.slab("mc_concrete", canal, [], -BANK_DEPTH, -BANK_DEPTH + 2.0)
    for a, b in boundary_edges(canal, half):
        _quay(kit, solids, a, b, bank_z)


def _quay(kit, solids, a, b, bank_z):
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    if length < 1e-3:
        return
    yaw = math.atan2(dy, dx)
    mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)
    kit.box("mc_stone", (mid[0], mid[1], (bank_z - BANK_DEPTH) * 0.5),
            (length + 1.0, 6.0, bank_z + BANK_DEPTH), yaw)
    solids.box((mid[0], mid[1], (bank_z - BANK_DEPTH) * 0.5),
               (length + 1.0, 6.0, bank_z + BANK_DEPTH), yaw, False)


def _docks(kit, solids, docks, spec, half):
    """Harbor trench at -12: floor slab plus quay walls up to street level."""
    z = float(spec["z"])
    kit.slab("mc_concrete", docks, [], z - 4.0, z)
    solids.slab(docks, [], z - 4.0, z)
    for a, b in boundary_edges(docks, half):
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        if length < 1e-3:
            continue
        yaw = math.atan2(dy, dx)
        mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)
        kit.box("mc_stone", (mid[0], mid[1], z * 0.5), (length + 1.0, 5.0, -z), yaw)
        solids.box((mid[0], mid[1], z * 0.5), (length + 1.0, 5.0, -z), yaw, False)


def _soft_walls(kit, solids, half, skyline_half, ceiling=260.0):
    """A skirt beyond the playable square so nothing reads as a cut edge, plus the boundary wall
    (C16): 60 m of visible parapet and a collision-only curtain up to the no-fly ceiling, so a
    rooftop or sky deck near the edge is walled too."""
    outer = skyline_half
    ring = [(-outer, -outer), (outer, -outer), (outer, outer), (-outer, outer)]
    inner = [(-half, -half), (half, -half), (half, half), (-half, half)]
    kit.slab("mc_concrete", ring, [inner], -CRUST, 0.0)
    wall_along(kit, solids, "mc_concrete", inner, 0.0, 60.0, 6.0, False, True)
    n = len(inner)
    for i in range(n):
        a, b = inner[i], inner[(i + 1) % n]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        if length < 1e-3:
            continue
        # Collision only, and never part of an HLOD proxy: these are four 1 400 x 260 m cards
        # with no render mesh, and merged into a tile's stand-in they read as a flat wall filling
        # the frame from every vista (city-art r3).
        solids.curtain_box(((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, ceiling * 0.5),
                           (length + 6.0, 6.0, ceiling), math.atan2(dy, dx))
