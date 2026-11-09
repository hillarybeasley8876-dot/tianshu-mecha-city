"""Decks: plaza, skydeck, garden, platform, terrace and the Crown.

Every deck is a slab (polygon with inner boundaries) plus a parapet, an under-side of beams, and
visible support: columns at <= 48 m, or a truss when the layout declares a `span` between two
buildings (MAP 4). The Crown (kind `crown`) additionally builds its stepped rim, four fins and
the central core from the layout's `rim_steps` / `fins` / `core`.
"""
import math

from . import builder

PARAPET_T = 2.0
COLUMN_W = 9.0
COLUMN_STEP = 48.0
BEAM = 3.0


def _parapet(kit, solids, poly, z, height, role="mc_concrete"):
    if height <= 0.1:
        return
    for a, b in zip(poly, poly[1:] + poly[:1]):
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        if length < 1e-3:
            continue
        yaw = math.atan2(dy, dx)
        mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, z + height * 0.5)
        size = (length + PARAPET_T, PARAPET_T, height)
        kit.box(role, mid, size, yaw)
        solids.box(mid, size, yaw, False)


def _soffit(kit, solids, poly, z_bottom, under_clear):
    """Beams under the slab so a floating deck reads as structure, not a plate."""
    x0, x1 = min(p[0] for p in poly), max(p[0] for p in poly)
    y0, y1 = min(p[1] for p in poly), max(p[1] for p in poly)
    step = max(18.0, min(40.0, (x1 - x0) / 6.0))
    x = x0 + step * 0.5
    while x < x1:
        kit.box("mc_concrete", (x, (y0 + y1) * 0.5, z_bottom - BEAM * 0.5),
                (BEAM * 1.6, y1 - y0, BEAM))
        x += step
    y = y0 + step * 0.5
    while y < y1:
        kit.box("mc_concrete", ((x0 + x1) * 0.5, y, z_bottom - BEAM * 0.5),
                (x1 - x0, BEAM * 1.6, BEAM))
        y += step
    if under_clear and under_clear > 40.0:
        kit.box("mc_metal", ((x0 + x1) * 0.5, (y0 + y1) * 0.5, z_bottom - BEAM * 1.6),
                (x1 - x0, y1 - y0, 1.2))


def _columns(kit, solids, deck, ground):
    """Columns every <= 48 m, either at the layout's declared positions or on a grid."""
    z = float(deck["z"])
    thick = float(deck["thickness"])
    declared = deck.get("columns")
    if declared:
        spots = [(float(c[0]), float(c[1])) for c in declared]
    else:
        x0, x1 = min(p[0] for p in deck["polygon"]), max(p[0] for p in deck["polygon"])
        y0, y1 = min(p[1] for p in deck["polygon"]), max(p[1] for p in deck["polygon"])
        nx = max(1, int(math.ceil((x1 - x0) / COLUMN_STEP)))
        ny = max(1, int(math.ceil((y1 - y0) / COLUMN_STEP)))
        spots = [(x0 + (x1 - x0) * (i + 0.5) / nx, y0 + (y1 - y0) * (j + 0.5) / ny)
                 for i in range(nx) for j in range(ny)]
    for x, y in spots:
        base = ground(x, y)
        h = z - thick - base
        if h <= 4.0:
            continue
        kit.box("mc_concrete", (x, y, base + h * 0.5), (COLUMN_W, COLUMN_W, h))
        kit.box("mc_concrete", (x, y, z - thick - 2.0), (COLUMN_W + 6.0, COLUMN_W + 6.0, 4.0))
        solids.box((x, y, base + h * 0.5), (COLUMN_W, COLUMN_W, h), 0.0, False)


def _truss(kit, solids, deck, ground):
    """A span deck gets a warren truss under the slab along its long axis."""
    poly = deck["polygon"]
    x0, x1 = min(p[0] for p in poly), max(p[0] for p in poly)
    y0, y1 = min(p[1] for p in poly), max(p[1] for p in poly)
    z = float(deck["z"]) - float(deck["thickness"])
    along_x = (x1 - x0) >= (y1 - y0)
    length = (x1 - x0) if along_x else (y1 - y0)
    cy = (y0 + y1) * 0.5
    cx = (x0 + x1) * 0.5
    depth = 12.0
    for side in (-1.0, 1.0):
        off = side * ((y1 - y0) * 0.5 - 4.0) if along_x else side * ((x1 - x0) * 0.5 - 4.0)
        for k in range(2):
            zz = z - depth * k
            pos = (cx, cy + off, zz) if along_x else (cx + off, cy, zz)
            size = (length, 3.0, 3.0) if along_x else (3.0, length, 3.0)
            kit.box("mc_metal", pos, size)
        n = max(2, int(length / 32.0))
        for i in range(n + 1):
            t = i / n
            px = x0 + (x1 - x0) * t if along_x else cx + off
            py = cy + off if along_x else y0 + (y1 - y0) * t
            kit.box("mc_metal", (px, py, z - depth * 0.5), (2.4, 2.4, depth))
    solids.box((cx, cy, z - 1.0), (x1 - x0, y1 - y0, 4.0), 0.0, False)


def deck(kit, solids, d, ground, skin=None):
    poly = [tuple(p) for p in d["polygon"]]
    holes = [[tuple(p) for p in h] for h in d.get("holes", [])]
    z = float(d["z"])
    thick = float(d["thickness"])
    role = "mc_deck"
    # Kit skin mode: a deck-edge row replaces the parapet with a kit railing. A `deck_full` row
    # (city-kit r6, `pieces.skybridges`) places s06 TUBE segments down the deck's centreline — the
    # model is 6.7 m wide and 6 m tall, a guideway, not a floor — so it mutes the parapet exactly
    # like a deck-edge row and leaves the slab and its soffit alone. Muting the slab left three
    # quarters of a 24-30 m skybridge with no render at all, and the arena cover the layout puts on
    # that deck standing in mid-air over it (lead, r9).
    edge_kit = kit
    if skin is not None and (skin.deck(d["id"]) or skin.deck_full(d["id"])):
        edge_kit = builder.MutedKit(d["id"])
    if d["kind"] == "garden":
        role = "mc_panel_white"
    elif d["kind"] in ("plaza", "crown"):
        role = "mc_stone"
    kit.slab(role, poly, holes, z - thick, z)
    solids.slab(poly, holes, z - thick, z, occlude=(d["kind"] in ("plaza", "crown", "skydeck")))
    _parapet(edge_kit, solids, poly, z, float(d.get("parapet", 0.0)))
    if d["kind"] != "plaza" and not d.get("on_ground"):
        # The Crown is a disc: a bbox beam grid pokes out past its rim (it read as loose tabs
        # floating around the edge). kit/spire.py dresses its soffit radially instead.
        if d["kind"] != "crown":
            _soffit(kit, solids, poly, z - thick, float(d.get("under_clear") or 0.0))
        if d.get("span"):
            _truss(kit, solids, d, ground)
        elif not d.get("supported_by"):
            _columns(kit, solids, d, ground)
    if d["kind"] == "crown":
        _crown(kit, solids, d, poly, z)
    if d["kind"] == "garden":
        _garden(kit, solids, poly, z)


def _crown(kit, solids, d, poly, z):
    """Stepped rim, four fins and the central core, all from the layout fields.

    The OUTERMOST rim step gets no parapet here: CONTRACTS 6 hands that ring to the boss, which
    breaks it segment by segment, so `world/city.gd` builds it from `layout.json`'s `crown_rim`."""
    cx = sum(p[0] for p in poly) / len(poly)
    cy = sum(p[1] for p in poly) / len(poly)
    steps = d.get("rim_steps", [])
    outer_r = max((float(s["r"]) for s in steps), default=0.0)
    for step in steps:
        r, rz = float(step["r"]), float(step["z"])
        rise = float(step.get("rise", 8.0))
        ring = [(cx + math.cos(a * math.tau / 48.0) * r, cy + math.sin(a * math.tau / 48.0) * r)
                for a in range(48)]
        kit.slab("mc_stone", ring, [], rz, rz + 1.5)
        solids.slab(ring, [], rz, rz + 1.5)
        if r < outer_r - 0.5:
            _parapet(kit, solids, ring, rz + 1.5, 5.0, "mc_bronze")
        for a in range(0, 48, 4):
            ang = a * math.tau / 48.0
            kit.box("mc_stone", (cx + math.cos(ang) * (r - 3.0), cy + math.sin(ang) * (r - 3.0),
                                 rz - rise * 0.5), (10.0, 10.0, rise), ang)
    for fin in d.get("fins", []):
        ang = math.radians(float(fin["angle_deg"]))
        reach, width, height = float(fin["reach"]), float(fin["width"]), float(fin["height"])
        # Outboard of the rim, not on it: the fins used to sit at a hardcoded r 120, which is
        # between the r 126 and r 104 rim steps, so their tops (z 248) broke the rim profile the
        # boss walks — probe heights read 226/234/241/248 m at r 0.92/0.72/0.55/0.80, and that
        # last one is a fin (boss r2). `reach` is how far each blade projects past the rim.
        r = outer_r + reach * 0.5
        px, py = cx + math.cos(ang) * r, cy + math.sin(ang) * r
        kit.box("mc_panel_white", (px, py, z + height * 0.5), (reach, width, height), ang)
        kit.box("mc_up_accent", (px, py, z + height + 1.0), (reach * 0.8, 2.0, 2.0), ang)
        solids.box((px, py, z + height * 0.5), (reach, width, height), ang, False)
    core = d.get("core")
    if core:
        r, height = float(core["r"]), float(core["height"])
        kit.cylinder("mc_panel_white", (cx, cy, z + height * 0.5), r, height, 32)
        kit.cylinder("mc_up_accent", (cx, cy, z + height + 2.0), r * 0.9, 4.0, 32)
        solids.box((cx, cy, z + height * 0.5), (r * 1.6, r * 1.6, height), 0.0, False)


def _garden(kit, solids, poly, z):
    """Planter beds and a lit kerb so the Sky Garden reads as planted, not as a slab."""
    x0, x1 = min(p[0] for p in poly), max(p[0] for p in poly)
    y0, y1 = min(p[1] for p in poly), max(p[1] for p in poly)
    n = 5
    for i in range(n):
        for j in range(3):
            px = x0 + (x1 - x0) * (i + 0.5) / n
            py = y0 + (y1 - y0) * (j + 0.5) / 3.0
            kit.box("mc_stone", (px, py, z + 1.5), (26.0, 16.0, 3.0))
            kit.box("mc_terracotta", (px, py, z + 3.6), (23.0, 13.0, 1.2))


def build(kit, solids, layout, ground, skin=None, skip_kinds=(), only_kinds=()):
    for d in layout.decks:
        if d["kind"] in skip_kinds or (only_kinds and d["kind"] not in only_kinds):
            continue
        deck(kit, solids, d, ground, skin)


def edge_rings(d):
    """The parapet polyline of one deck, as city-kit needs it for railings. Only decks that
    actually have a parapet in the geometry are listed — a hole rim gets no railing today."""
    height = float(d.get("parapet", 0.0))
    if height <= 0.1:
        return []
    return [{"id": "%s_rim" % d["id"], "points": [[p[0], p[1]] for p in d["polygon"]],
             "z": float(d["z"]), "kind": "deck", "closed": True,
             "height": height, "thickness": PARAPET_T,
             "deck": d["id"], "deck_kind": d["kind"]}]
