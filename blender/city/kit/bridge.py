"""The Crystal Bridge (MAP 4 / ART.md 4, D7 "glass + steel, gold reflections").

Reviews/look/city-build.md item 1: the landmark used to be 13 stations of 3 x 3 m metal posts and
4 x 36 m glass slabs — a 300 m farm fence, and the biggest structure in the A6 hive frame. It is
now a glazed faceted arch:

  * an octagonal `mc_glass` tube swept along a sin(pi t) arch, 4 m panels between 0.6 m bronze
    mullion rings, with eight 0.55 m bronze ribs running the facet edges and two `mc_up_accent`
    light lines along the lower flanks;
  * tapered diagrid struts (1.2 m at the deck, 0.6 m at the tube) every 12 m in a V, with bronze
    node caps at the joints;
  * a slim 10-segment deck slab with chamfered kerbs and a lit underside, and the maglev beam
    running INSIDE the glass.

It keeps the layout's envelope (pos, length, width, height) and its prop slot. It still has no
collision: the old fence had none either, and adding a walkable deck would move the navmesh bake
every other unit's numbers are measured against.
"""
import math

from mathutils import Vector

from lib import geo

FACETS = 8
PANEL = 4.0        ## mullion spacing along the arch (m)
STRUT_STEP = 12.0  ## diagrid station spacing (m)
DECK_SEGMENTS = 10
TUBE_R = 11.0      ## octagon circumradius: ~20 m across flats over a 36 m deck
SPRING = TUBE_R + 2.0   ## tube centre above the deck at the abutments
MULLION = 0.6
RIB = 0.55
LIGHT = 0.3


def _arch(x, y, z, length, rise, n):
    """(centreline points, rise parameter) for the n+1 stations of the arch."""
    pts, ts = [], []
    for i in range(n + 1):
        t = i / n
        pts.append(Vector((x - length * 0.5 + length * t, y, z + SPRING + math.sin(t * math.pi)
                           * rise)))
        ts.append(t)
    return pts, ts


def _profile(radius, sides=FACETS, phase=math.pi / FACETS, squash=1.0):
    """Regular polygon in the (right, up) frame of a station."""
    return [(math.cos(phase + i * math.tau / sides) * radius,
             math.sin(phase + i * math.tau / sides) * radius * squash) for i in range(sides)]


def _ring(centre, right, up, profile, lift=0.0):
    return [tuple(centre + right * a + up * (b + lift)) for a, b in profile]


def _loft(kit, role, pts, frames, profile, lift=0.0, caps=False):
    kit.loft(role, [_ring(p, r, u, profile, lift) for p, (_t, r, u) in zip(pts, frames)],
             cap_start=caps, cap_end=caps)


def crystal_bridge(kit, solids, lm, slots):
    p = lm["params"]
    x, y, z = (float(v) for v in lm["pos"])
    length, width = float(p["length"]), float(p["width"])
    rise = float(p["height"])

    _deck(kit, x, y, z, length, width)
    n = max(8, int(round(length / PANEL)))
    pts, _ts = _arch(x, y, z, length, rise, n)
    frames = geo.frames(pts)
    _glazing(kit, pts, frames)
    _mullions(kit, pts, frames)
    _ribs(kit, pts, frames)
    _maglev(kit, pts, frames)
    _struts(kit, x, y, z, length, width, rise)
    _abutments(kit, x, y, z, length, width)

    slots.append({"kind": "maglev_car", "pos": [x, y, z + SPRING + rise - TUBE_R * 0.55],
                  "yaw_deg": 0.0})


def _deck(kit, x, y, z, length, width):
    """Ten 30 m segments rather than one 300 m slab: each is under the chamfer threshold, so the
    slab lips get a lit edge band and the joints read as expansion joints."""
    seg = length / DECK_SEGMENTS
    for i in range(DECK_SEGMENTS):
        cx = x - length * 0.5 + seg * (i + 0.5)
        kit.box("mc_deck", (cx, y, z - 1.5), (seg - 0.4, width, 3.0))
        for sy in (-1.0, 1.0):
            kit.box("mc_metal", (cx, y + sy * (width * 0.5 - 0.9), z + 0.7),
                    (seg - 0.4, 1.8, 1.4))
            kit.box("mc_up_accent", (cx, y + sy * (width * 0.5 - 0.3), z - 3.3),
                    (seg - 2.0, 0.5, 0.5))


def _glazing(kit, pts, frames):
    _loft(kit, "mc_glass", pts, frames, _profile(TUBE_R))


def _mullions(kit, pts, frames):
    """A 0.6 m bronze ring every station, standing 0.3 m proud of the glass."""
    ring = _profile(TUBE_R + 0.3)
    for i, (p, (t, r, u)) in enumerate(zip(pts, frames)):
        if i in (0, len(pts) - 1):
            continue
        a = p - t * (MULLION * 0.5)
        b = p + t * (MULLION * 0.5)
        kit.loft("mc_bronze", [_ring(a, r, u, ring), _ring(b, r, u, ring)])


def _ribs(kit, pts, frames):
    """Eight bronze ribs on the facet edges, plus a light line on the two lower flanks."""
    corners = _profile(TUBE_R + 0.35)
    square = [(-RIB, -RIB), (RIB, -RIB), (RIB, RIB), (-RIB, RIB)]
    for a, b in corners:
        line = [p + r * a + u * b for p, (_t, r, u) in zip(pts, frames)]
        kit.loft("mc_bronze", [_ring(q, r, u, square) for q, (_t, r, u) in zip(line, frames)],
                 cap_start=True, cap_end=True)
    flanks = _profile(TUBE_R * math.cos(math.pi / FACETS) + 0.25)
    light = [(-LIGHT, -LIGHT), (LIGHT, -LIGHT), (LIGHT, LIGHT), (-LIGHT, LIGHT)]
    for k in (5, 7):
        a, b = flanks[k]
        line = [p + r * a + u * b for p, (_t, r, u) in zip(pts, frames)]
        kit.loft("mc_up_accent", [_ring(q, r, u, light) for q, (_t, r, u) in zip(line, frames)],
                 cap_start=True, cap_end=True)


def _maglev(kit, pts, frames):
    """The guideway runs inside the glass: a slim beam under the tube axis with a lit soffit."""
    beam = [(-2.6, -0.6), (2.6, -0.6), (2.6, 0.6), (-2.6, 0.6)]
    strip = [(-1.8, -0.15), (1.8, -0.15), (1.8, 0.15), (-1.8, 0.15)]
    _loft(kit, "mc_metal", pts, frames, beam, lift=-TUBE_R * 0.55, caps=True)
    _loft(kit, "mc_up_accent", pts, frames, strip, lift=-TUBE_R * 0.55 - 0.75, caps=True)


def _strut(kit, a, b, w0, w1):
    """A square strut tapering from w0 at `a` to w1 at `b`."""
    def profile(i, _d):
        w = (w0 if i == 0 else w1) * 0.5
        return [(-w, -w), (w, -w), (w, w), (-w, w)]

    kit.sweep("mc_metal", profile, [a, b], closed_profile=True)


def _struts(kit, x, y, z, length, width, rise):
    """V-shaped diagrid every 12 m: two tapered struts per side, bronze caps at the top joints."""
    n = max(2, int(round(length / STRUT_STEP)))
    for i in range(n + 1):
        t = i / n
        px = x - length * 0.5 + length * t
        zc = z + SPRING + math.sin(t * math.pi) * rise
        for sy in (-1.0, 1.0):
            top = (px, y + sy * TUBE_R * 0.72, zc - TUBE_R * 0.62)
            for lean in (-1.0, 1.0):
                foot = (px + lean * STRUT_STEP * 0.42, y + sy * (width * 0.5 - 3.0), z + 0.4)
                _strut(kit, foot, top, 1.2, 0.6)
            kit.box("mc_bronze", top, (1.8, 1.8, 1.8))


def _abutments(kit, x, y, z, length, width):
    for sx in (-1.0, 1.0):
        kit.box("mc_bronze", (x + sx * length * 0.5, y, z + SPRING * 0.5),
                (10.0, width * 0.82, SPRING + 2.0))
