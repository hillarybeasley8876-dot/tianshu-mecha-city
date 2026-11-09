"""Collision and occluder proxies (city-build).

Render meshes are never used as collision. Every solid in the city is reduced to axis boxes
(and extruded polygons for decks and terrain) written into two Kits:
  * `col` -> exported as `<name>-colonly`  (StaticBody3D, Layers.WORLD)
  * `occ` -> exported as `<name>-occonly`  (Occluder3D) for big facades and deck slabs only.

Building masses carry rectangular holes (arcades, rail-through, breaches). `mass_boxes` cuts the
mass with a grid decomposition instead of a boolean, so the openings are exact and the proxy
stays a handful of closed boxes.
"""
import math

import bmesh
from mathutils import Matrix, Vector

from .builder import Kit, rotate

CONCRETE = "mc_concrete"
OCC_MIN_PLAN = 18.0   ## a proxy smaller than this in plan never hides anything worth baking
OCC_MIN_HEIGHT = 16.0


class Solids:
    """Collision + occluder box accumulators for one tile or district."""

    def __init__(self) -> None:
        self.col = Kit("col")
        self.occ = Kit("occ")
        self.props = Kit("props")   ## decoration: collides, but never blocks navigation
        self.curtain = Kit("curtain")   ## the map-edge no-fly curtain: collides, never HLOD

    # ------------------------------------------------------------------ writers
    def box(self, center, size, rot_z: float = 0.0, occlude: bool = False) -> None:
        if min(size) <= 1e-3:
            return
        self.col.box(CONCRETE, center, size, rot_z)
        if occlude and min(size[0], size[1]) >= OCC_MIN_PLAN and size[2] >= OCC_MIN_HEIGHT:
            self.occ.box(CONCRETE, center, size, rot_z)

    def curtain_box(self, center, size, rot_z: float = 0.0) -> None:
        """Collision that is deliberately NOT part of the HLOD stand-in.

        The C16 no-fly curtain is four 1 400 x 260 m cards with no render mesh of their own, and
        they are only ever seen as the thing that stops the player leaving. Merged into a tile's
        HLOD proxy they became a flat wall filling the frame from every vista (city-art r3:
        `t-1_3_hlod` is a planar 0 x 260 x 1 406 m card). They collide; they do not stand in for
        the city at distance.
        """
        if min(size) <= 1e-3:
            return
        self.curtain.box(CONCRETE, center, size, rot_z)

    def prism(self, poly, z0: float, z1: float, occlude: bool = False) -> None:
        self.col.prism(CONCRETE, poly, z0, z1)
        if occlude:
            self.occ.prism(CONCRETE, poly, z0, z1)

    def slab(self, poly, holes, z0: float, z1: float, occlude: bool = False) -> None:
        self.col.slab(CONCRETE, poly, holes, z0, z1)
        if occlude:
            self.occ.slab(CONCRETE, poly, holes, z0, z1)

    def mass(self, center, size, yaw: float, holes=(), occlude: bool = True) -> None:
        """A building segment (world centre/size, `yaw` rad) minus local rectangular holes.

        `holes` entries: {"rect": (x0, y0, x1, y1) in the mass's own frame, "z": (z0, z1) world}.
        A mass with holes gets no occluder: a solid occluder would cull what shows through the
        arcade, and a decomposed one is too small to be worth baking.
        """
        for c, s in mass_boxes(center, size, yaw, holes):
            self.box(c, s, yaw, False)
        if occlude and not holes and min(size[0], size[1]) >= OCC_MIN_PLAN and size[2] >= OCC_MIN_HEIGHT:
            self.box(center, size, yaw, True)

    def prop(self, center, size, rot_z: float = 0.0) -> None:
        """A decorative collider on the PROPS layer: it stops shots and bodies, but the navmesh
        bake only reads Layers.WORLD, so decoration never fragments the walkable surface."""
        self.props.box(CONCRETE, center, size, rot_z)

    def is_empty(self) -> bool:
        return (self.col.is_empty() and self.occ.is_empty() and self.props.is_empty()
                and self.curtain.is_empty())


def mass_boxes(center, size, yaw: float, holes=()):
    """Grid decomposition of one box minus rectangular holes -> [(centre, size)] in world space."""
    out = []
    for (xa, xb), (ya, yb), za, zb in mass_cells(size, holes, center[2] - size[2] * 0.5):
        p = rotate((center[0] + (xa + xb) * 0.5, center[1] + (ya + yb) * 0.5),
                   (center[0], center[1]), yaw)
        out.append(((p[0], p[1], (za + zb) * 0.5), (xb - xa, yb - ya, zb - za)))
    return out


def mass_cells(size, holes=(), z0=None):
    """The same decomposition in the box's OWN plan frame, keeping the holes' z frame:
    [((xa, xb), (ya, yb), za, zb), ...].

    Anything that has to sit ON the surviving part of a holed mass (a rooftop machine, a parapet)
    needs the cells rather than the world boxes, because its own placements are local to the
    segment. `z0` is the mass's bottom in the same frame as the holes' `z` (world, by default the
    box's own centre-relative frame when it is not given).
    """
    w, d, h = size
    z0 = -h * 0.5 if z0 is None else z0
    z1 = z0 + h
    if w <= 1e-3 or d <= 1e-3 or h <= 1e-3:
        return []
    if not holes:
        return [((-w * 0.5, w * 0.5), (-d * 0.5, d * 0.5), z0, z1)]
    hw, hd = w * 0.5, d * 0.5
    live = []
    for hole in holes:
        hx0, hy0, hx1, hy1 = hole["rect"]
        hz0, hz1 = hole["z"]
        if hx1 <= -hw or hx0 >= hw or hy1 <= -hd or hy0 >= hd or hz1 <= z0 or hz0 >= z1:
            continue
        live.append((max(hx0, -hw), max(hy0, -hd), min(hx1, hw), min(hy1, hd),
                     max(hz0, z0), min(hz1, z1)))
    if not live:
        return [((-hw, hw), (-hd, hd), z0, z1)]
    zc = sorted({z0, z1} | {v for _, _, _, _, a, b in live for v in (a, b)})
    out = []
    for za, zb in zip(zc, zc[1:]):
        if zb - za <= 1e-3:
            continue
        zmid = (za + zb) * 0.5
        band = [hh for hh in live if hh[4] <= zmid <= hh[5]]
        if not band:
            out.append(((-hw, hw), (-hd, hd), za, zb))
            continue
        xc = sorted({-hw, hw} | {v for hh in band for v in (hh[0], hh[2])})
        yc = sorted({-hd, hd} | {v for hh in band for v in (hh[1], hh[3])})
        for xa, xb in zip(xc, xc[1:]):
            for ya, yb in zip(yc, yc[1:]):
                if xb - xa <= 1e-3 or yb - ya <= 1e-3:
                    continue
                cx, cy = (xa + xb) * 0.5, (ya + yb) * 0.5
                if any(hh[0] < cx < hh[2] and hh[1] < cy < hh[3] for hh in band):
                    continue
                out.append(((xa, xb), (ya, yb), za, zb))
    return out


def face_breach_holes(center, size, yaw: float, breaches):
    """Layout `breaches` ({face, z, width, height}) -> mass_boxes hole dicts in the mass frame.

    A breach is cut right through the mass: it is a spawn opening, so both facades open.
    """
    w, d = size[0], size[1]
    out = []
    for b in breaches:
        span = w if b["face"] in ("n", "s") else d
        half = min(float(b["width"]), span) * 0.5
        thick = (d if b["face"] in ("n", "s") else w) * 0.5 + 1.0
        out.append({"rect": (-half, -thick, half, thick),
                    "z": (float(b["z"]), float(b["z"]) + float(b["height"]))})
    return out


def local_rect(poly, center, yaw: float):
    """Axis-aligned bounding rect of a world polygon in a mass's local frame."""
    inv = -yaw
    pts = [rotate((p[0], p[1]), (center[0], center[1]), inv) for p in poly]
    xs = [p[0] - center[0] for p in pts]
    ys = [p[1] - center[1] for p in pts]
    return (min(xs), min(ys), max(xs), max(ys))


def box_polygon(center, size, yaw: float):
    """The four plan corners of a rotated box, CCW."""
    hw, hd = size[0] * 0.5, size[1] * 0.5
    corners = [(-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)]
    return [rotate((center[0] + x, center[1] + y), (center[0], center[1]), yaw) for x, y in corners]


def ramp_solid(solids: "Solids", a, b, width: float, thickness: float, occlude: bool = False):
    """A sloped slab from a to b (both 3D), `width` across, `thickness` deep: one rotated box,
    which is all collision needs for ramps, stair flights and connector decks."""
    dx, dy, dz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    length = math.hypot(dx, dy, dz)
    if length < 1e-3 or width <= 1e-3 or thickness <= 1e-3:
        return
    yaw = math.atan2(dy, dx)
    pitch = math.asin(max(-1.0, min(1.0, dz / length)))
    mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, (a[2] + b[2]) * 0.5 - thickness * 0.5)
    mat = (Matrix.Translation(Vector(mid))
           @ Matrix.Rotation(yaw, 4, "Z")
           @ Matrix.Rotation(-pitch, 4, "Y")
           @ Matrix.Diagonal(Vector((length, width, thickness, 1.0))))
    for kit in ([solids.col, solids.occ] if occlude else [solids.col]):
        res = bmesh.ops.create_cube(kit.bm(CONCRETE), size=1.0)
        bmesh.ops.transform(kit.bm(CONCRETE), matrix=mat, verts=res["verts"])
