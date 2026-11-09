"""Building archetypes on a 4 m floor module (ART.md 4: base / shaft / crown).

Every archetype resolves to a stack of massing segments; one shared detailing pass then adds the
plinth, the window bands (one `mc_window` quad per floor per facade, U in 4 m cells), the vertical
fins, the floor bands, the parapet and the rooftop machinery slots. That keeps the ten archetypes
consistent in facade language while their massing stays distinct.
"""
import math

from . import builder, passage, roles, solid

FLOOR = 4.0
CELL = 4.0          ## window cell width, metres
FIN_STEP = 11.0     ## vertical fin spacing
BAND_FLOORS = 8     ## a horizontal band every N floors
PLINTH = 6.0


def seg(cx, cy, w, d, z0, z1, yaw):
    return {"cx": cx, "cy": cy, "w": w, "d": d, "z0": z0, "z1": z1, "yaw": yaw}


def _inset(seg_dict, fw, fd, cx=0.0, cy=0.0):
    s = dict(seg_dict)
    s["w"] = max(6.0, seg_dict["w"] * fw)
    s["d"] = max(6.0, seg_dict["d"] * fd)
    s["cx"] = seg_dict["cx"] + cx
    s["cy"] = seg_dict["cy"] + cy
    return s


def segments(b, rng):
    """The massing stack for one layout building: [{cx, cy, w, d, z0, z1, yaw}, ...]."""
    cx, cy = b["center"]
    w, d = b["size"]
    z0, h = float(b["base_z"]), float(b["height"])
    yaw = math.radians(float(b["rot"]))
    arch = b["archetype"]
    top = z0 + h
    base = seg(cx, cy, w, d, z0, top, yaw)
    if arch == "slab" or h < 24.0:
        return [base]
    if arch == "warehouse":
        return [base]
    if arch == "industrial":
        hall_h = min(h, max(20.0, h * 0.55))
        bay = seg(cx + (w * 0.28 if rng.random() < 0.5 else -w * 0.28), cy, w * 0.34, d * 0.7,
                  z0, top, yaw)
        return [seg(cx, cy, w, d, z0, z0 + hall_h, yaw), bay]
    if arch == "podium_tower":
        pz = float(b.get("podium_z") or 0.0)
        pz = z0 + max(24.0, h * 0.2) if pz <= z0 else min(pz, top - 24.0)
        tower = _inset(seg(cx, cy, w, d, pz, top, yaw), 0.72, 0.72)
        return [seg(cx, cy, w, d, z0, pz, yaw), tower]
    if arch == "setback":
        n = max(2, min(4, int(h / 70.0) + 2))
        out, f = [], 1.0
        for i in range(n):
            za = z0 + h * i / n
            zb = z0 + h * (i + 1) / n
            out.append(_inset(seg(cx, cy, w, d, za, zb, yaw), f, f))
            f *= 0.8
        return out
    if arch == "twisted":
        n = max(4, min(8, int(h / 40.0)))
        out, f, a = [], 1.0, yaw
        for i in range(n):
            za = z0 + h * i / n
            zb = z0 + h * (i + 1) / n
            out.append(_inset(seg(cx, cy, w, d, za, zb, a), f, f))
            f *= 0.965
            a += math.radians(36.0 / n)
        return out
    if arch == "terrace":
        n = max(3, min(6, int(h / 14.0)))
        out, step = [], 0.0
        for i in range(n):
            za = z0 + h * i / n
            zb = z0 + h * (i + 1) / n
            s = _inset(seg(cx, cy, w, d, za, zb, yaw), 1.0, 1.0)
            s["d"] = max(8.0, d - step)
            s["cy"] = cy - step * 0.5
            out.append(s)
            step += d / (n + 1.2)
        return out
    if arch == "pagoda":
        n = max(4, min(7, int(h / 20.0)))
        out, f = [], 1.0
        for i in range(n):
            za = z0 + h * i / n
            zb = z0 + h * (i + 1) / n
            out.append(_inset(seg(cx, cy, w, d, za, zb, yaw), f, f))
            f *= 0.84
        return out
    if arch == "megablock":
        return [base]
    if arch == "stack":
        n = rng.choice((2, 3, 4))
        out = []
        for i in range(n):
            fx = (i % 2) * 0.5 - 0.25
            fy = (i // 2) * 0.5 - 0.25
            hh = h * (1.0 - 0.12 * i)
            out.append(seg(cx + w * fx, cy + d * fy, w * 0.46, d * 0.46, z0, z0 + hh, yaw))
        return out
    return [base]


def _blocked(z_lo, z_hi, holes):
    """True when a facade strip at z_lo..z_hi sits inside a hole or breach opening."""
    return any(not (z_hi <= hz0 or z_lo >= hz1) for hz0, hz1 in holes)


def _facade_strip(kit, s, role_wall, z_lo, z_hi, holes, floors=True):
    """Window bands, fins and floor bands for one massing segment."""
    hw, hd = s["w"] * 0.5, s["d"] * 0.5
    faces = ((0, -1, s["d"]), (0, 1, s["d"]), (-1, 0, s["w"]), (1, 0, s["w"]))
    z = s["z0"] + FLOOR
    while z + 2.6 <= s["z1"]:
        if floors and not _blocked(z, z + 2.6, holes):
            for nx, ny, span in faces:
                n = max(1, int(span // CELL))
                pad = (span - n * CELL) * 0.5
                for k in range(n):
                    u0 = -span * 0.5 + pad + k * CELL + 0.4
                    _window_quad(kit, s, nx, ny, u0, u0 + CELL - 0.8, z, z + 2.6)
        z += FLOOR
    height = s["z1"] - s["z0"]
    mid_z = (s["z0"] + s["z1"]) * 0.5
    for nx, ny, span in faces:
        n = max(1, int(span // FIN_STEP))
        for k in range(1, n):
            u = -span * 0.5 + span * k / n
            if abs(u) > span * 0.5 - 2.5:
                continue
            if ny:
                lx, ly = u, ny * (hd + 0.7)
            else:
                lx, ly = nx * (hw + 0.7), u
            kit.local_box(role_wall, (s["cx"], s["cy"]), s["yaw"], (lx, ly, mid_z),
                          (1.4, 1.4, height))
    zz = s["z0"] + FLOOR * BAND_FLOORS
    while zz < s["z1"] - FLOOR:
        if not _blocked(zz - 0.6, zz + 0.6, holes):
            kit.local_box(role_wall, (s["cx"], s["cy"]), s["yaw"], (0.0, 0.0, zz),
                          (s["w"] + 1.2, s["d"] + 1.2, 0.8))
        zz += FLOOR * BAND_FLOORS


def _window_quad(kit, s, nx, ny, u0, u1, z0, z1):
    """One emissive window band on a facade, proud by 0.15 m. `tag_windows` gives it
    U = 0..cells (one unit per 4 m cell) and V = 0..1, so each cell is UV 0..1."""
    hw, hd = s["w"] * 0.5, s["d"] * 0.5
    if ny:
        v = ny * (hd + 0.15)
        pts = [(u0, v, z0), (u1, v, z0), (u1, v, z1), (u0, v, z1)]
        if ny > 0:
            pts = list(reversed(pts))
    else:
        v = nx * (hw + 0.15)
        pts = [(v, u0, z0), (v, u1, z0), (v, u1, z1), (v, u0, z1)]
        if nx < 0:
            pts = list(reversed(pts))
    kit.window(*[_to_world(s, p) for p in pts])


def _to_world(s, p):
    c, sn = math.cos(s["yaw"]), math.sin(s["yaw"])
    return (s["cx"] + p[0] * c - p[1] * sn, s["cy"] + p[0] * sn + p[1] * c, p[2])


def _holes_for(b, s, extra=()):
    """Local rectangular holes for one segment: layout `holes` (arcades, viaduct/rail straddles),
    the openings the corridors' own `through` lists ask for, plus facade `breaches` (spawns).
    Returns ([hole dicts], [(z0, z1), ...])."""
    out = []
    for h in b.get("holes", []):
        rect = solid.local_rect(h["polygon"], (s["cx"], s["cy"]), s["yaw"])
        out.append({"rect": rect, "z": (float(h["z"]), float(h["z"]) + float(h["height"]))})
    out.extend(extra)
    for h in solid.face_breach_holes((s["cx"], s["cy"]), (s["w"], s["d"]), s["yaw"],
                                     b.get("breaches", [])):
        out.append(h)
    return out, [(h["z"][0], h["z"][1]) for h in out]


def _parapet(kit, solids, s, role, walkable, roof_cells):
    """4-6 m parapet ring on the crown (ART.md 4), clipped to the roof that actually survives.

    A breach or an arcade that reaches the top of a mass takes the roof with it, and a parapet
    drawn straight across that opening is a bar floating in mid-air (lead r7 item 1:
    `D1_b003`, `D1_b011`). Each side is therefore cut back to the spans where a roof cell still
    reaches that edge. Walkable roofs also get collision, exactly as before.
    """
    h = 5.0
    t = 1.6
    z = s["z1"] + h * 0.5
    hw, hd = s["w"] * 0.5, s["d"] * 0.5
    sides = (("x", (hd - t, hd)), ("x", (-hd, -(hd - t))),
             ("y", (hw - t, hw)), ("y", (-hw, -(hw - t))))
    for axis, (b0, b1) in sides:
        for a0, a1 in _spans(roof_cells, axis, b0, b1):
            if a1 - a0 <= 1.0:
                continue
            ac = (a0 + a1) * 0.5
            bc = (b0 + b1) * 0.5
            lx, ly = (ac, bc) if axis == "x" else (bc, ac)
            sx, sy = (a1 - a0, b1 - b0) if axis == "x" else (b1 - b0, a1 - a0)
            kit.local_box(role, (s["cx"], s["cy"]), s["yaw"], (lx, ly, z), (sx, sy, h))
            if walkable:
                solids.box(_to_world(s, (lx, ly, z)), (sx, sy, h), s["yaw"], False)
    _roof_accent(kit, s, roof_cells, t)


def _spans(roof_cells, axis, b0, b1):
    """The 1-D spans along `axis` where a surviving roof cell overlaps the edge band b0..b1."""
    spans = []
    for (xa, xb), (ya, yb) in roof_cells:
        c0, c1 = (ya, yb) if axis == "x" else (xa, xb)
        if c1 <= b0 + 1e-3 or c0 >= b1 - 1e-3:
            continue
        spans.append((xa, xb) if axis == "x" else (ya, yb))
    out = []
    for a, b in sorted(spans):
        if out and a <= out[-1][1] + 1e-3:
            out[-1] = (out[-1][0], max(out[-1][1], b))
        else:
            out.append((a, b))
    return out


def _roof_accent(kit, s, roof_cells, t):
    """The lit parapet line, inset from whichever part of the roof is still there."""
    for (xa, xb), (ya, yb) in roof_cells:
        sx, sy = xb - xa - t * 2.0, yb - ya - t * 2.0
        if sx <= 1.0 or sy <= 1.0:
            continue
        kit.local_box("mc_up_accent", (s["cx"], s["cy"]), s["yaw"],
                      ((xa + xb) * 0.5, (ya + yb) * 0.5, s["z1"] + 5.4), (sx, sy, 0.8))


def _roof_cap(kit, s, role, roof_cells):
    """The crown cornice. It only reads as a cornice on an unbroken roof, so a cut one gets none
    rather than a slab bridging the opening."""
    if len(roof_cells) != 1:
        return
    (xa, xb), (ya, yb) = roof_cells[0]
    kit.local_box(role, (s["cx"], s["cy"]), s["yaw"],
                  ((xa + xb) * 0.5, (ya + yb) * 0.5, s["z1"] - 0.8),
                  (xb - xa + 1.0, yb - ya + 1.0, 1.6))


def _roof(kit, solids, s, rng, slots, b_id, roof_cells):
    """Rooftop machinery: blockout masses plus a prop slot marker for city-art.

    The machines only land on roof cells that survived the holes, so a slot always has mass under
    it — `skin_probe.gd` raycasts down onto every slot, and a slot over an opening cannot collide.
    """
    area = sum((xb - xa) * (yb - ya) for (xa, xb), (ya, yb) in roof_cells)
    n = 2 if area < 1600.0 else (3 if area < 5000.0 else 5)
    for _i in range(n):
        (xa, xb), (ya, yb) = _pick_cell(roof_cells, rng, area)
        cw, cd = xb - xa, yb - ya
        mw = min(cw * 0.6, rng.uniform(6.0, 16.0))
        md = min(cd * 0.6, rng.uniform(6.0, 16.0))
        mh = rng.uniform(4.0, 11.0)
        lx = (xa + xb) * 0.5 + rng.uniform(-1.0, 1.0) * (cw - mw) * 0.5
        ly = (ya + yb) * 0.5 + rng.uniform(-1.0, 1.0) * (cd - md) * 0.5
        kit.local_box("mc_metal", (s["cx"], s["cy"]), s["yaw"], (lx, ly, s["z1"] + mh * 0.5),
                      (mw, md, mh))
        solids.prop(_to_world(s, (lx, ly, s["z1"] + mh * 0.5)), (mw, md, mh), s["yaw"])
        slots.append({"kind": "roof_machine", "building": b_id,
                      "pos": list(_to_world(s, (lx, ly, s["z1"]))),
                      "yaw_deg": round(math.degrees(s["yaw"]), 2),
                      "size": [round(mw, 2), round(md, 2), round(mh, 2)]})


def _pick_cell(roof_cells, rng, area):
    """One surviving roof cell, picked by area so a big half of a cut roof gets the machines."""
    want = rng.random() * area
    for cell in roof_cells:
        (xa, xb), (ya, yb) = cell
        want -= (xb - xa) * (yb - ya)
        if want <= 0.0:
            return cell
    return roof_cells[-1]


def _roof_cells(s, holes):
    """The part of the top segment's mass that still reaches its own top face, in local plan.
    Empty when a breach or an arcade has taken the whole roof — then there is nothing to dress."""
    h = s["z1"] - s["z0"]
    return [((xa, xb), (ya, yb))
            for (xa, xb), (ya, yb), _za, zb in solid.mass_cells((s["w"], s["d"], h), holes,
                                                               s["z0"])
            if zb >= s["z1"] - 1e-3]


def build(kit, solids, b, rng, slots, through=None, skinned=False):
    """Emit one layout building into `kit` (render) and `solids` (collision/occluders).

    `skinned` (kit skin mode): city-kit fits a Tripo model over this box, so the render mesh is
    dropped and the collision, occluders and prop slots stay exactly as they were."""
    if skinned:
        kit = builder.MutedKit(b["id"])
    district = b["district"]
    wall, trim, accent = roles.DISTRICT_ROLES.get(district, ("mc_concrete", "mc_panel_white",
                                                              "mc_metal"))
    segs = segments(b, rng)
    walkable = bool(b.get("roof_walkable"))
    extra = passage.derived_holes(through or {}, b)
    for i, s in enumerate(segs):
        holes, zspans = _holes_for(b, s, extra)
        active = [h for h in holes
                  if h["z"][0] < s["z1"] - 0.5 and h["z"][1] > s["z0"] + 0.5]
        top_seg = i == len(segs) - 1
        for c, size in solid.mass_boxes((s["cx"], s["cy"], (s["z0"] + s["z1"]) * 0.5),
                                        (s["w"], s["d"], s["z1"] - s["z0"]), s["yaw"], active):
            kit.box(wall, c, size, s["yaw"])
        solids.mass((s["cx"], s["cy"], (s["z0"] + s["z1"]) * 0.5),
                    (s["w"], s["d"], s["z1"] - s["z0"]), s["yaw"], active,
                    occlude=len(segs) == 1)
        if i == 0:
            kit.local_box(trim, (s["cx"], s["cy"]), s["yaw"],
                          (0.0, 0.0, s["z0"] + PLINTH * 0.5),
                          (s["w"] + 1.6, s["d"] + 1.6, PLINTH))
        _facade_strip(kit, s, accent, s["z0"], s["z1"], [z for z in zspans])
        if top_seg:
            cells = _roof_cells(s, active)
            if cells:
                _parapet(kit, solids, s, trim, walkable, cells)
                _roof(kit, solids, s, rng, slots, b["id"], cells)
                _roof_cap(kit, s, trim, cells)
    _landmark_extras(kit, solids, b, rng)
    if through:
        passage.dress(kit, solids, b, through, slots)


def _landmark_extras(kit, solids, b, rng):
    """Archetype-specific silhouette work that the massing stack alone does not give."""
    arch = b["archetype"]
    cx, cy = b["center"]
    w, d = b["size"]
    z0, top = float(b["base_z"]), float(b["base_z"]) + float(b["height"])
    yaw = math.radians(float(b["rot"]))
    if arch == "megablock":
        for f in (0.38, 0.68):
            z = z0 + (top - z0) * f
            kit.local_box("mc_deck", (cx, cy), yaw, (0.0, -d * 0.28, z), (w * 0.9, d * 0.5, 3.0))
            kit.local_box("mc_up_accent", (cx, cy), yaw,
                          (0.0, -d * 0.52, z + 2.2), (w * 0.9, 1.2, 1.2))
            solids.box(_to_world({"cx": cx, "cy": cy, "yaw": yaw}, (0.0, -d * 0.28, z)),
                       (w * 0.9, d * 0.5, 3.0), yaw, False)
    elif arch == "industrial":
        n = max(2, int(w // 26.0))
        for k in range(n):
            u = -w * 0.5 + w * (k + 0.5) / n
            kit.local_box("mc_metal", (cx, cy), yaw, (u, 0.0, z0 + (top - z0) * 0.55 + 2.0),
                          (w / n * 0.55, d * 0.9, 4.0))
    elif arch == "warehouse":
        kit.local_box("mc_metal", (cx, cy), yaw, (0.0, 0.0, top + 2.4), (w * 0.98, d * 0.98, 4.8))
        solids.box((cx, cy, top + 2.4), (w * 0.98, d * 0.98, 4.8), yaw, False)
    elif arch == "terrace":
        step = (top - z0) / max(3, min(6, int((top - z0) / 14.0)))
        z = z0 + step
        while z < top - 1.0:
            kit.local_box("mc_deck", (cx, cy), yaw, (0.0, -d * 0.5, z), (w, 6.0, 1.6))
            kit.local_box("mc_metal", (cx, cy), yaw, (0.0, -d * 0.5 - 2.6, z + 2.2),
                          (w, 0.6, 3.0))
            z += step
    elif arch == "pagoda":
        n = max(4, min(7, int((top - z0) / 20.0)))
        f = 1.0
        for i in range(n):
            zz = z0 + (top - z0) * (i + 1) / n
            kit.local_box("mc_terracotta", (cx, cy), yaw, (0.0, 0.0, zz), (w * f + 7.0,
                                                                           d * f + 7.0, 1.8))
            f *= 0.84
