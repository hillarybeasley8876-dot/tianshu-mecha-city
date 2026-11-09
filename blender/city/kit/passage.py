"""Corridor-through passages (city-build): podium arcades, viaduct/rail straddles.

MAP 3 v2 lets a corridor run THROUGH a building: `holes` + `through` on the building, `through` on
the corridor. Layout r3 declares `through` on some corridors (the four streets and two rails that
cross Block 9) without the matching `holes` on the building, so `derived_holes` reads the
corridor's own centreline, width and height and cuts the opening the corridor asks for — still
entirely from the JSON, never hand-placed.

`dress` then makes the passage read as architecture rather than a hole in a box (lead, r3): a
lined throat, soffit light strips, a portal frame at both mouths so the corridor visibly enters
and leaves, and signage panels with prop slots for city-art's real signs.
"""
import math

CLEAR = {"viaduct": 40.0, "rail": 32.0, "street": 32.0, "tunnel": 34.0}
MARGIN = 4.0        ## MAP 3 v2: hole = corridor width + 2 x 4 m
LINER = 1.5
LIGHT_W = 1.4


def through_index(layout):
    """{building id: [corridor dicts]} for every corridor that declares `through` on a building."""
    out = {}
    for kind in ("streets", "viaducts", "rails", "tunnels"):
        singular = kind[:-1]
        for c in getattr(layout, kind, []):
            for bid in c.get("through", []) or []:
                out.setdefault(bid, []).append({"kind": singular, "corridor": c})
    return out


def _to_local(p, center, yaw):
    c, s = math.cos(-yaw), math.sin(-yaw)
    dx, dy = p[0] - center[0], p[1] - center[1]
    return (dx * c - dy * s, dx * s + dy * c)


def _to_world(p, center, yaw):
    c, s = math.cos(yaw), math.sin(yaw)
    return (center[0] + p[0] * c - p[1] * s, center[1] + p[0] * s + p[1] * c)


def _clip(a, b, rect):
    """Liang-Barsky clip of a segment against an axis rect; None when it misses."""
    x0, y0, x1, y1 = rect
    dx, dy = b[0] - a[0], b[1] - a[1]
    t0, t1 = 0.0, 1.0
    for p, q in ((-dx, a[0] - x0), (dx, x1 - a[0]), (-dy, a[1] - y0), (dy, y1 - a[1])):
        if abs(p) < 1e-9:
            if q < 0.0:
                return None
            continue
        t = q / p
        if p < 0.0:
            t0 = max(t0, t)
        else:
            t1 = min(t1, t)
    if t0 > t1:
        return None
    return ((a[0] + dx * t0, a[1] + dy * t0), (a[0] + dx * t1, a[1] + dy * t1))


def crossings(entry, b):
    """Where one corridor crosses one building, in the building's local frame.

    Returns [(local_a, local_b, z0, z1, half_width, kind, corridor id)]."""
    c = entry["corridor"]
    kind = entry["kind"]
    center = (float(b["center"][0]), float(b["center"][1]))
    yaw = math.radians(float(b["rot"]))
    w, d = float(b["size"][0]), float(b["size"][1])
    rect = (-w * 0.5, -d * 0.5, w * 0.5, d * 0.5)
    z = float(c.get("z", b["base_z"]))
    clear = CLEAR.get(kind, 32.0)
    half = float(c.get("width", 32.0)) * 0.5 + MARGIN
    pts = [_to_local((p[0], p[1]), center, yaw) for p in c["points"]]
    out = []
    for a, bb in zip(pts, pts[1:]):
        seg = _clip(a, bb, rect)
        if seg is None:
            continue
        out.append((seg[0], seg[1], z, z + clear, half, kind, c["id"]))
    return out


def derived_holes(index, b):
    """Local rectangular holes for every corridor that asks to pass through this building and is
    not already declared by the building's own `holes`."""
    declared_rects = []
    declared_corridors = set()
    for h in b.get("holes", []):
        declared_corridors.add(h.get("corridor"))
        if abs(float(h["z"]) - float(b["base_z"])) < 1.0:
            declared_rects.append(_rect_of(h, b))
    out = []
    for entry in index.get(b["id"], []):
        if entry["corridor"]["id"] in declared_corridors:
            continue
        for a, bb, z0, z1, half, _kind, _cid in crossings(entry, b):
            rect = (min(a[0], bb[0]) - half, min(a[1], bb[1]) - half,
                    max(a[0], bb[0]) + half, max(a[1], bb[1]) + half)
            if any(_overlaps(rect, r) for r in declared_rects):
                continue
            out.append({"rect": rect, "z": (z0, z1)})
    return out


def _rect_of(hole, b):
    center = (float(b["center"][0]), float(b["center"][1]))
    yaw = math.radians(float(b["rot"]))
    pts = [_to_local((p[0], p[1]), center, yaw) for p in hole["polygon"]]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return (min(xs), min(ys), max(xs), max(ys))


def _overlaps(a, b):
    return not (a[2] <= b[0] or b[2] <= a[0] or a[3] <= b[1] or b[3] <= a[1])


def dress(kit, solids, b, index, slots):
    """Light every corridor passage through this building like a tunnel."""
    center = (float(b["center"][0]), float(b["center"][1]))
    yaw = math.radians(float(b["rot"]))
    for entry in index.get(b["id"], []):
        for a, bb, z0, z1, half, kind, cid in crossings(entry, b):
            _passage(kit, solids, a, bb, z0, z1, half, center, yaw, b, cid, slots)


def _passage(kit, solids, a, bb, z0, z1, half, center, yaw, b, cid, slots):
    dx, dy = bb[0] - a[0], bb[1] - a[1]
    length = math.hypot(dx, dy)
    if length < 6.0:
        return
    clear = z1 - z0
    ang = yaw + math.atan2(dy, dx)
    mid_l = ((a[0] + bb[0]) * 0.5, (a[1] + bb[1]) * 0.5)
    mid = _to_world(mid_l, center, yaw)
    origin = (mid[0], mid[1])
    # lined throat: ceiling and two side liners, so the opening is a tunnel and not raw concrete
    kit.box("mc_panel_white", (mid[0], mid[1], z1 - LINER * 0.5), (length, half * 2.0, LINER), ang)
    for side in (-1.0, 1.0):
        ox = -math.sin(ang) * side * (half - LINER * 0.5)
        oy = math.cos(ang) * side * (half - LINER * 0.5)
        kit.box("mc_panel_white", (mid[0] + ox, mid[1] + oy, z0 + clear * 0.5),
                (length, LINER, clear), ang)
        solids.box((mid[0] + ox, mid[1] + oy, z0 + clear * 0.5), (length, LINER, clear), ang, False)
    # soffit light strips down the throat
    for side in (-0.55, 0.55):
        ox = -math.sin(ang) * side * half
        oy = math.cos(ang) * side * half
        kit.box("mc_up_accent", (mid[0] + ox, mid[1] + oy, z1 - LINER - 0.5),
                (length * 0.94, LIGHT_W, 0.9), ang)
    # portal frames at both mouths: the corridor visibly enters and leaves the tower
    for end, sign in ((a, -1.0), (bb, 1.0)):
        mouth = _to_world(end, center, yaw)
        nx, ny = math.cos(ang) * sign, math.sin(ang) * sign
        for side in (-1.0, 1.0):
            lat_x, lat_y = -math.sin(ang) * side, math.cos(ang) * side
            jx = mouth[0] + lat_x * (half + 1.5)
            jy = mouth[1] + lat_y * (half + 1.5)
            kit.box("mc_bronze", (jx, jy, z0 + clear * 0.5), (4.0, 3.0, clear), ang)
            solids.box((jx, jy, z0 + clear * 0.5), (4.0, 3.0, clear), ang, False)
            # signage plate, flush on the jamb's outer face (a prop slot for city-art's real sign)
            sx = jx + lat_x * 2.1
            sy = jy + lat_y * 2.1
            kit.box("mc_panel_white", (sx, sy, z0 + clear * 0.60), (11.0, 1.2, 7.0), ang)
            slots.append({"kind": "passage_sign", "building": b["id"], "corridor": cid,
                          "pos": [sx + lat_x * 0.8, sy + lat_y * 0.8, z0 + clear * 0.60],
                          "normal": [lat_x, lat_y, 0.0], "yaw_deg": round(math.degrees(ang), 2)})
        kit.box("mc_bronze", (mouth[0], mouth[1], z1 + 1.5), (4.0, half * 2.0 + 6.0, 3.0), ang)
        solids.box((mouth[0], mouth[1], z1 + 1.5), (4.0, half * 2.0 + 6.0, 3.0), ang, False)
        kit.box("mc_up_accent", (mouth[0], mouth[1], z1 - 1.0),
                (2.0, half * 2.0, 1.0), ang)
        kit.box("mc_up_accent", (mouth[0] + nx * 3.0, mouth[1] + ny * 3.0, z0 + 0.6),
                (3.0, half * 2.0, 0.8), ang)
