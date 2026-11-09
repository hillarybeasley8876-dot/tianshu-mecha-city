"""Landmarks (MAP 4): the Knot, the harbor cranes, the reactor stacks, Block 9's hologram, the
Crystal Bridge, the Stilt Pagoda base and the civic hologram. The Spire has its own module
(`spire.py`) because its silhouette is art-directed on its own.

Tripo props and statues are city-art's: every landmark leaves a prop slot in the side-car JSON.
"""
import math

from . import spire as spire_mod


def _ngon(cx, cy, r, n, phase=0.0):
    return [(cx + math.cos(phase + i * math.tau / n) * r, cy + math.sin(phase + i * math.tau / n) * r)
            for i in range(n)]


def deck_ring_radii(layout, centre, ids=("S3_collar", "S4_roof_ring", "B1_crown")):
    """Inner-hole radius of the decks that ring a landmark, so its shaft can fill them."""
    out = []
    for deck_id in ids:
        found = None
        for d in layout.decks:
            if d["id"] == deck_id and d.get("holes"):
                cx, cy = centre
                found = max(math.hypot(p[0] - cx, p[1] - cy) for p in d["holes"][0])
        out.append(found if found else 40.0)
    return tuple(out)


def knot(kit, solids, lm, slots):
    """Three stacked loop decks with helix ramps between them (the Interchange Knot)."""
    x, y, _ = (float(v) for v in lm["pos"])
    p = lm["params"]
    levels = [float(v) for v in p["levels"]]
    r_out = float(p["radius"])
    r_in = r_out - 34.0
    for i, z in enumerate(levels):
        outer = _ngon(x, y, r_out - i * 8.0, 40)
        inner = _ngon(x, y, r_in - i * 8.0, 40)
        kit.slab("mc_deck", outer, [inner], z - 4.0, z)
        solids.slab(outer, [inner], z - 4.0, z)
        _ring_barrier(kit, solids, outer, z, 5.0)
        _ring_barrier(kit, solids, inner, z, 5.0)
        for a in range(0, 40, 5):
            ang = a * math.tau / 40.0
            rr = (r_out - i * 8.0) - 6.0
            kit.box("mc_concrete", (x + math.cos(ang) * rr, y + math.sin(ang) * rr, z - 6.0),
                    (12.0, 12.0, 4.0), ang)
        if i + 1 < len(levels):
            _helix(kit, solids, x, y, z, levels[i + 1], r_in - i * 8.0 - 16.0, 30.0)
    for i in range(int(p.get("flyovers", 4))):
        ang = i * math.tau / 4.0 + 0.4
        z = levels[min(i + 1, len(levels) - 1)] + 6.0
        _flyover(kit, solids, x, y, ang, r_out + 60.0, z)
    slots.append({"kind": "traffic_hologram", "pos": [x, y, levels[-1] + 12.0], "yaw_deg": 0.0})


def _ring_barrier(kit, solids, ring, z, height):
    for a, b in zip(ring, ring[1:] + ring[:1]):
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        if length < 1e-3:
            continue
        yaw = math.atan2(dy, dx)
        mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, z + height * 0.5)
        kit.box("mc_concrete", mid, (length + 1.0, 2.0, height), yaw)
        solids.box(mid, (length + 1.0, 2.0, height), yaw, False)


def _helix(kit, solids, cx, cy, z0, z1, radius, width):
    """Spiral ramp between two loop decks (level-design 3.4: r 60-90 m)."""
    from . import solid as solid_mod
    steps = max(8, int((z1 - z0) / 6.0))
    prev = None
    for i in range(steps + 1):
        t = i / steps
        ang = t * math.tau * 0.75
        p = (cx + math.cos(ang) * radius, cy + math.sin(ang) * radius, z0 + (z1 - z0) * t)
        if prev is not None:
            kit.sweep("mc_deck", [(-width * 0.5, 0.0), (width * 0.5, 0.0), (width * 0.5, -3.0),
                                  (-width * 0.5, -3.0)], [prev, p], closed_profile=True)
            solid_mod.ramp_solid(solids, prev, p, width, 3.0)
        prev = p


def _flyover(kit, solids, cx, cy, ang, reach, z):
    a = (cx + math.cos(ang) * 40.0, cy + math.sin(ang) * 40.0, z)
    b = (cx + math.cos(ang) * reach, cy + math.sin(ang) * reach, z - 6.0)
    kit.sweep("mc_deck", [(-14.0, 0.0), (14.0, 0.0), (14.0, -4.0), (-14.0, -4.0)], [a, b],
              closed_profile=True)
    from . import solid as solid_mod
    solid_mod.ramp_solid(solids, a, b, 28.0, 4.0)


def cranes(kit, solids, lm, slots):
    """Four gantry cranes: portal legs, boom, cab at +48. Tripo crane bodies are city-art's."""
    p = lm["params"]
    cab_z = float(p["cab_z"])
    boom = float(p["boom"])
    for i, (x, y) in enumerate(p["positions"]):
        x, y = float(x), float(y)
        for sx in (-1.0, 1.0):
            for sy in (-1.0, 1.0):
                kit.box("mc_metal", (x + sx * 22.0, y + sy * 18.0, cab_z * 0.5),
                        (5.0, 5.0, cab_z))
                solids.box((x + sx * 22.0, y + sy * 18.0, cab_z * 0.5), (5.0, 5.0, cab_z),
                           0.0, False)
        kit.box("mc_metal", (x, y, cab_z + 4.0), (52.0, 44.0, 8.0))
        kit.box("mc_metal", (x, y - boom * 0.25, cab_z + 14.0), (10.0, boom, 7.0))
        kit.box("mc_panel_white", (x, y + 12.0, cab_z + 10.0), (14.0, 12.0, 10.0))
        solids.box((x, y, cab_z + 4.0), (52.0, 44.0, 8.0), 0.0, False)
        slots.append({"kind": "gantry_crane", "pos": [x, y, cab_z + 8.0], "yaw_deg": 0.0,
                      "index": i})


def stacks(kit, solids, lm, slots):
    """Reactor stacks to +144 with flare rings; plumes are city-art particle props."""
    p = lm["params"]
    top = float(p["top_z"])
    r = float(p["radius"])
    for i, (x, y) in enumerate(p["positions"]):
        x, y = float(x), float(y)
        kit.cylinder("mc_metal", (x, y, top * 0.5), r, top, 24)
        kit.cylinder("mc_concrete", (x, y, 6.0), r + 6.0, 12.0, 24)
        for k in range(3):
            kit.cylinder("mc_bronze", (x, y, top * (0.35 + 0.2 * k)), r + 2.0, 3.0, 24)
        kit.cylinder("mc_metal", (x, y, top + 3.0), r + 4.0, 6.0, 24)
        solids.box((x, y, top * 0.5), (r * 2.0, r * 2.0, top), 0.0, True)
        slots.append({"kind": "smoke_plume", "pos": [x, y, top + 8.0], "yaw_deg": 0.0,
                      "index": i})


def block9(kit, solids, lm, slots):
    """The giant hologram above Block 9 (the block itself is a layout building)."""
    p = lm["params"]
    x, y, z = (float(v) for v in lm["pos"])
    holo = p.get("hologram") or {}
    hz = float(holo.get("z", z + float(p["height"])))
    w = float(holo.get("width", 120.0))
    kit.box("mc_up_accent", (x, y, hz + w * 0.25), (w, 2.0, w * 0.5))
    kit.box("mc_metal", (x, y, hz - 4.0), (w * 0.6, 16.0, 8.0))
    slots.append({"kind": "koi_hologram", "pos": [x, y, hz + w * 0.25], "yaw_deg": 0.0})


def crystal_bridge(kit, solids, lm, slots):
    """The glazed faceted arch — see kit/bridge.py (reviews/look/city-build.md item 1)."""
    from . import bridge
    bridge.crystal_bridge(kit, solids, lm, slots)


def pagoda(kit, solids, lm, slots):
    """The Stilt Pagoda: legs on the plateau plus the tiered base the landmark top sits on."""
    p = lm["params"]
    x, y, z = (float(v) for v in lm["pos"])
    top_z = float(p["top_z"])
    fw, fd = (float(v) for v in p["footprint"])
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            kit.box("mc_terracotta", (x + sx * fw * 0.42, y + sy * fd * 0.42, z * 0.5),
                    (7.0, 7.0, z))
            solids.box((x + sx * fw * 0.42, y + sy * fd * 0.42, z * 0.5), (7.0, 7.0, z),
                       0.0, False)
    tiers = int(p["tiers"])
    f = 1.0
    for i in range(tiers):
        za = z + (top_z - z) * i / tiers
        zb = z + (top_z - z) * (i + 1) / tiers
        kit.prism("mc_terracotta", _ngon(x, y, fw * 0.42 * f, 8, math.pi / 8.0), za, zb - 2.0)
        kit.prism("mc_bronze", _ngon(x, y, fw * 0.52 * f, 8, math.pi / 8.0), zb - 2.0, zb)
        solids.box((x, y, (za + zb) * 0.5), (fw * 0.84 * f, fd * 0.84 * f, zb - za), 0.0, False)
        f *= 0.88
    slots.append({"kind": "pagoda_top", "pos": [x, y, top_z], "yaw_deg": 0.0})


def hologram(kit, solids, lm, slots):
    p = lm["params"]
    x, y, z = (float(v) for v in lm["pos"])
    h, w = float(p["height"]), float(p["width"])
    kit.box("mc_up_accent", (x, y, z + h * 0.5), (w, 2.0, h))
    kit.box("mc_metal", (x, y, z + 1.0), (w * 0.5, w * 0.5, 2.0))
    slots.append({"kind": "holo_projector", "pos": [x, y, z], "yaw_deg": 0.0})


BUILDERS = {"knot": knot, "cranes": cranes, "stacks": stacks, "block9": block9,
            "crystal_bridge": crystal_bridge, "pagoda": pagoda, "hologram": hologram}


def build(kit, solids, layout, slots):
    for lm in layout.landmarks:
        if lm["kind"] == "spire":
            spire_mod.spire(kit, solids, lm, slots,
                            deck_ring_radii(layout, (lm["pos"][0], lm["pos"][1])))
            continue
        fn = BUILDERS.get(lm["kind"])
        if fn is None:
            print("city-build: no landmark builder for kind %r (%s)" % (lm["kind"], lm["id"]))
            continue
        fn(kit, solids, lm, slots)
