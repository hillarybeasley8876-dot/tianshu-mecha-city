"""The Spire (MAP 4 B1, ART 1): the landmark the whole city is oriented by.

Language, from the key art (`art/concept/keyart/v1_pier-1.png`, `v8_crown-1.png`):
the shaft is a TRUMPET — it tapers to a waist at +110 and then flares out to a 60 m mouth under
the Crown soffit, so from mid-distance it reads as a mass that carries the disc rather than a stick
under a plate. Ten splayed brackets leave that waist and step out to the rim, each with a lit
edge; the Crown's underside is a radial structure of ribs, rings and lit slots, never a black disc.
The collar (+80) and roof (+160) decks are carried on stepped cantilevered corbels, and the light
tether stands on the needle.

Only the layout's own numbers are read: `height`, `base_radius`, the three deck heights and the
inner-hole radii of the decks that ring it (so each deck visibly rests on the shaft).
"""
import math

SEG = 16           ## shaft facets
FIN_N = 16         ## vertical fins, one per facet
RIB_N = 10         ## radiating brackets under the Crown
RIB_STEPS = 8      ## stepped corbel layers per bracket
CROWN_RIB_BASE = 120.0   ## the brackets leave the shaft at its waist, well below the soffit
CROWN_DECK_THICK = 6.0   ## the Crown slab's own thickness, so the soffit is this far below its z
SOFFIT_BEAMS = 20  ## radial beams dressing the Crown's underside
SOFFIT_RINGS = (72.0, 106.0, 140.0)
TETHER_R = 3.0
BAND_STEP = 16.0   ## horizontal band rhythm on the shaft (4 m floor module x 4)

## (z, radius) knots of the flared shaft below the Crown. Drums and corbels are added on top.
TRUMPET = [(26.0, 44.0), (74.0, 38.0), (110.0, 34.0), (140.0, 34.5),
           (170.0, 39.0), (196.0, 48.0), (214.0, 58.0), (218.0, 60.0)]
## Above the soffit the shaft necks back to pass through the Crown's 40 m hole and its core mass,
## then tapers to the needle. The neck is hidden inside the core above the deck.
NECK = [(214.0, 36.0), (256.0, 34.0), (300.0, 20.0), (336.0, 8.0), (360.0, 2.0)]


def _interp(knots, z: float, k: float) -> float:
    """Radius at height `z`, linear between the knots. Authored for `base_radius` 70; `k` rescales
    them to the layout's own radius."""
    if z <= knots[0][0]:
        return knots[0][1] * k
    for (z0, r0), (z1, r1) in zip(knots, knots[1:]):
        if z <= z1:
            return (r0 + (r1 - r0) * (z - z0) / (z1 - z0)) * k
    return knots[-1][1] * k


def shaft_r(z: float, k: float = 1.0) -> float:
    """Radius of the flared shaft below the Crown."""
    return _interp(TRUMPET, z, k)


def neck_r(z: float, k: float = 1.0) -> float:
    """Radius of the shaft where it passes through the Crown and rises to the needle."""
    return _interp(NECK, z, k)


def _ngon(cx, cy, r, n=SEG, phase=0.0):
    return [(cx + math.cos(phase + i * math.tau / n) * r, cy + math.sin(phase + i * math.tau / n) * r)
            for i in range(n)]


def _loft(kit, solids, role, cx, cy, sections, collide=True, occlude=False):
    """Tapered prism between consecutive (z, r) knots, plus a collision box per section."""
    for (z0, r0), (z1, r1) in zip(sections, sections[1:]):
        if z1 - z0 <= 0.01:
            continue
        a, b = _ngon(cx, cy, r0), _ngon(cx, cy, r1)
        for i in range(SEG):
            j = (i + 1) % SEG
            kit.quad(role, (a[i][0], a[i][1], z0), (a[j][0], a[j][1], z0),
                     (b[j][0], b[j][1], z1), (b[i][0], b[i][1], z1))
        kit.prism(role, a, z0, z0 + 0.01)
        kit.prism(role, b, z1 - 0.01, z1)
        if collide:
            rm = max(r0, r1) * 0.94
            solids.box((cx, cy, (z0 + z1) * 0.5), (rm * 2.0, rm * 2.0, z1 - z0), 0.0, occlude)


def _radial(kit, role, cx, cy, ang, sections):
    """A radial wedge stacked in Z, in a frame rotated by `ang`:
    sections = [(z, r_inner, r_outer, half_width)]."""
    c, s = math.cos(ang), math.sin(ang)

    def P(r, w, z):
        return (cx + c * r - s * w, cy + s * r + c * w, z)

    rings = [[P(r0, -hw, z), P(r1, -hw, z), P(r1, hw, z), P(r0, hw, z)]
             for z, r0, r1, hw in sections]
    for a, b in zip(rings, rings[1:]):
        for i in range(4):
            j = (i + 1) % 4
            kit.quad(role, a[i], a[j], b[j], b[i])
    kit.quad(role, rings[0][3], rings[0][2], rings[0][1], rings[0][0])
    kit.quad(role, *rings[-1])


def _fins(kit, cx, cy, z0, z1, k=1.0, half_w=2.8):
    """FIN_N vertical fins standing on the shaft's corners, following its profile (key art: the
    shaft is all vertical piers and recessed slots). They deepen as the shaft flares, so at the top
    they read as the blades that carry the Crown rather than as stripes on a tube."""
    steps = [(z0 + (z1 - z0) * i / 12.0) for i in range(13)]
    for f in range(FIN_N):
        ang = f * math.tau / FIN_N
        t_last = (z1 - z0)
        sections = [(z, shaft_r(z, k) - 1.0,
                     shaft_r(z, k) + 4.5 + 5.0 * (z - z0) / t_last, half_w) for z in steps]
        _radial(kit, "mc_panel_white", cx, cy, ang, sections)
        r1 = shaft_r(z1, k)
        _radial(kit, "mc_bronze", cx, cy, ang,
                [(z1, r1 - 1.0, r1 + 10.3, half_w + 0.5), (z1 + 2.0, r1 - 1.0, r1 + 10.3, half_w + 0.5)])


def _windows(kit, cx, cy, z0, z1, k=1.0, half_w=4.0):
    """One emissive strip per facet, between the fins, following the taper."""
    knots = [z0] + [z for z, _ in TRUMPET if z0 < z < z1] + [z1]
    for f in range(FIN_N):
        ang = f * math.tau / FIN_N + math.pi / FIN_N
        c, s = math.cos(ang), math.sin(ang)
        for za, zb in zip(knots, knots[1:]):
            ra = (shaft_r(za, k) - 0.4) * math.cos(math.pi / FIN_N)
            rb = (shaft_r(zb, k) - 0.4) * math.cos(math.pi / FIN_N)
            pts = []
            for r, z in ((ra, za), (rb, zb)):
                pts.append(((cx + c * r + s * half_w, cy + s * r - c * half_w, z),
                            (cx + c * r - s * half_w, cy + s * r + c * half_w, z)))
            kit.window(pts[0][0], pts[0][1], pts[1][1], pts[1][0])


def _bands(kit, cx, cy, z0, z1, k=1.0):
    """Horizontal band rhythm: a bronze ring every BAND_STEP metres."""
    z = z0
    while z < z1:
        r = shaft_r(z, k) + 1.4
        kit.prism("mc_bronze", _ngon(cx, cy, r), z, z + 1.2)
        z += BAND_STEP


def _corbel(kit, solids, cx, cy, z_top, r_shaft, r_out, steps, rise):
    """Stepped cantilevered ring carrying a deck: each layer starts higher and reaches further
    out, so the soffit reads as stacked brackets instead of a smooth cone."""
    for i in range(steps):
        z = z_top - (steps - i) * rise
        r = r_shaft + (r_out - r_shaft) * (i + 1) / steps
        kit.prism("mc_panel_white", _ngon(cx, cy, r), z, z_top)
        _lit_ring(kit, cx, cy, r + 0.6, z - 1.0, z + 0.4)
    solids.box((cx, cy, z_top - steps * rise * 0.5),
               (r_out * 1.9, r_out * 1.9, steps * rise), 0.0, False)


def _lit_ring(kit, cx, cy, r, z0, z1, width=2.0, role="mc_up_accent"):
    """A lit edge on a ring, not a disc: the accent must read as a line of light along a step,
    not as a glowing plate over the whole soffit."""
    kit.slab(role, _ngon(cx, cy, r + width * 0.5), [_ngon(cx, cy, r - width * 0.5)], z0, z1)


def _drum(kit, solids, cx, cy, z0, z1, r):
    """The short drum a ring deck sits on: fills its hole, with a lit lip."""
    kit.prism("mc_panel_white", _ngon(cx, cy, r), z0, z1)
    _lit_ring(kit, cx, cy, r + 0.7, z1 - 1.6, z1, width=2.4, role="mc_bronze")
    _lit_ring(kit, cx, cy, r + 0.5, z1, z1 + 0.8)
    solids.box((cx, cy, (z0 + z1) * 0.5), (r * 1.9, r * 1.9, z1 - z0), 0.0, False)


def _crown_ribs(kit, solids, cx, cy, z_soffit, r_out, k=1.0):
    """RIB_N splayed brackets carrying the Crown (lead r3, key art v8_crown-1). Each one leaves
    the shaft's waist at +120 as a 24 m wide blade and steps out to the rim, its soffit rising as
    it goes, so from mid-distance the Crown reads as carried on ten ribs against the sky instead of
    sitting on a cone. Every step gets a lit edge along its outer soffit corner."""
    r_in = shaft_r(CROWN_RIB_BASE, k)
    span = z_soffit - CROWN_RIB_BASE
    for j in range(RIB_N):
        ang = j * math.tau / RIB_N + math.pi / RIB_N
        c, s = math.cos(ang), math.sin(ang)
        for i in range(RIB_STEPS):
            t0 = i / RIB_STEPS
            t1 = (i + 1) / RIB_STEPS
            z0 = CROWN_RIB_BASE + span * t0
            z1 = CROWN_RIB_BASE + span * t1
            hw = 12.0 - 5.0 * t0
            r1 = r_in + (r_out - r_in) * t1 ** 0.62
            _radial(kit, "mc_panel_white", cx, cy, ang, [(z0, r_in, r1, hw), (z1, r_in, r1, hw)])
            _radial(kit, "mc_up_accent", cx, cy, ang,
                    [(z0 - 1.6, r1 - 9.0, r1 + 0.8, hw * 0.5), (z0, r1 - 9.0, r1 + 0.8, hw * 0.5)])
            solids.box((cx + c * (r_in + r1) * 0.5, cy + s * (r_in + r1) * 0.5, (z0 + z1) * 0.5),
                       (r1 - r_in, hw * 2.0, z1 - z0), ang, False)


def _crown_soffit(kit, cx, cy, z_soffit, r_in, r_out):
    """The Crown's underside (lead r3: "never a black disc"). Radial beams on the half-pitch
    between the ribs, three concentric lit rings and a lit lip at the hole, so the soffit is
    structure and light from any angle below."""
    for i in range(SOFFIT_BEAMS):
        ang = i * math.tau / SOFFIT_BEAMS
        _radial(kit, "mc_metal", cx, cy, ang,
                [(z_soffit - 5.0, r_in, r_out, 3.2), (z_soffit, r_in, r_out, 3.2)])
        _radial(kit, "mc_up_accent", cx, cy, ang,
                [(z_soffit - 6.4, r_in + 8.0, r_out - 6.0, 1.2),
                 (z_soffit - 5.2, r_in + 8.0, r_out - 6.0, 1.2)])
    for r in SOFFIT_RINGS:
        if r >= r_out - 8.0:
            continue
        _lit_ring(kit, cx, cy, r, z_soffit - 2.4, z_soffit - 0.4, width=3.0)
    _lit_ring(kit, cx, cy, r_in + 4.0, z_soffit - 3.0, z_soffit - 0.4, width=4.0)


def _plinth(kit, solids, cx, cy, base_r):
    kit.prism("mc_stone", _ngon(cx, cy, base_r), -2.0, 8.0)
    solids.box((cx, cy, 3.0), (base_r * 2.0, base_r * 2.0, 10.0), 0.0, True)
    for i in range(4):
        r = base_r - 4.0 - i * 4.5
        kit.prism("mc_stone", _ngon(cx, cy, r), 8.0 + i * 4.5, 12.5 + i * 4.5)
        _lit_ring(kit, cx, cy, r + 0.7, 12.5 + i * 4.5, 13.9 + i * 4.5, width=2.4,
                  role="mc_bronze")
    solids.box((cx, cy, 15.0), (base_r * 1.8, base_r * 1.8, 26.0), 0.0, True)


def spire(kit, solids, lm, slots, deck_radii=None):
    x, y, _ = (float(v) for v in lm["pos"])
    p = lm["params"]
    height = float(p["height"])
    base_r = float(p["base_radius"])
    r_collar, r_roof, r_crown = deck_radii or (90.0, 56.0, 40.0)
    z_collar = float(p["collar_z"])
    z_roof = float(p["roof_ring_z"])
    z_crown = float(p["crown_deck_z"])
    z_soffit = z_crown - CROWN_DECK_THICK
    k = base_r / 70.0
    _plinth(kit, solids, x, y, base_r)
    _loft(kit, solids, "mc_panel_white", x, y,
          [(z, r * k) for z, r in TRUMPET if z <= z_soffit], occlude=True)
    # The neck starts inside the soffit drum so the two masses overlap and no seam shows.
    _loft(kit, solids, "mc_panel_white", x, y,
          [(z, r * k) for z, r in NECK if z <= height])
    _fins(kit, x, y, 30.0, z_soffit - 4.0, k)
    _windows(kit, x, y, 36.0, 200.0, k)
    _bands(kit, x, y, 42.0, 200.0, k)
    _corbel(kit, solids, x, y, z_collar - 6.0, shaft_r(z_collar - 6.0, k), r_collar, 5, 5.0)
    _drum(kit, solids, x, y, z_collar - 6.0, z_collar + 6.0, r_collar)
    _corbel(kit, solids, x, y, z_roof - 6.0, shaft_r(z_roof - 6.0, k), r_roof, 4, 4.0)
    _drum(kit, solids, x, y, z_roof - 6.0, z_roof + 6.0, r_roof)
    _crown_ribs(kit, solids, x, y, z_soffit, 152.0, k)
    _crown_soffit(kit, x, y, z_soffit, r_crown + 2.0, 147.0)
    _drum(kit, solids, x, y, z_crown - 10.0, z_crown, r_crown)
    kit.cylinder("mc_up_accent", (x, y, (height + float(p["tether_top_z"])) * 0.5), TETHER_R,
                 float(p["tether_top_z"]) - height, 8)
    slots.append({"kind": "spire_beacon", "pos": [x, y, height], "yaw_deg": 0.0})
    slots.append({"kind": "statue", "pos": [x, y - base_r - 24.0, 0.0], "yaw_deg": 180.0})
