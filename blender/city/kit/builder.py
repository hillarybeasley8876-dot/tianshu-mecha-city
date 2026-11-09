"""Kit: the per-role geometry accumulator every city builder writes into (city-build).

A Kit collects geometry in WORLD space (Blender metres, Z up) into one bmesh per material role.
Nothing is normalised globally: every primitive is built with explicit outward winding, because a
Kit holds many disconnected shells (window quads sit coplanar with walls) and a global
recalc_face_normals would flip them unpredictably.

`Kit.merged()` returns one tagged bmesh whose faces carry their role as `material_index`;
`tiles.py` then cuts it into 60 m chunks and merges per role.
"""
import math

import bmesh
import bpy
from mathutils import Vector

from lib import geo
from . import roles

WINDOW = roles.ROLE_ORDER.index("mc_window")

# Chamfer (reviews/look/city-build.md item 2). Every structural element in the A6 reference frame
# met its neighbour at a knife-sharp 90 degrees with no highlight line, so nothing caught the low
# sun and the city read as untextured CAD. The band is flat-shaded: the six big faces stay flat
# and only the 12 edge bands and 8 corner facets take a different normal.
CHAMFER_ON = True       ## build_city.py --no-chamfer flips this for the A/B
CHAMFER_FRAC = 0.015    ## of the smallest side
CHAMFER_MIN = 0.1
CHAMFER_MAX = 0.6
CHAMFER_MAX_SIDE = 40.0  ## only elements under this get a chamfer


def ccw(poly):
    """Return the polygon wound counter-clockwise (positive area)."""
    area = 0.5 * sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(poly, poly[1:] + poly[:1]))
    return list(poly) if area >= 0.0 else list(reversed(poly))


def dedupe(poly, eps=1e-4):
    """Drop consecutive duplicate points and collinear-zero-length steps."""
    out = []
    for p in poly:
        if not out or abs(p[0] - out[-1][0]) > eps or abs(p[1] - out[-1][1]) > eps:
            out.append((float(p[0]), float(p[1])))
    while len(out) > 1 and abs(out[0][0] - out[-1][0]) < eps and abs(out[0][1] - out[-1][1]) < eps:
        out.pop()
    return out


def rotate(p, pivot, ang):
    c, s = math.cos(ang), math.sin(ang)
    dx, dy = p[0] - pivot[0], p[1] - pivot[1]
    return (pivot[0] + dx * c - dy * s, pivot[1] + dx * s + dy * c)


class Kit:
    """One structure (or one merged tile chunk) accumulating geometry per material role."""

    def __init__(self, name: str = "kit"):
        self.name = name
        self._bm: dict = {}

    # ---------------------------------------------------------------- primitives
    def bm(self, role: str) -> bmesh.types.BMesh:
        b = self._bm.get(role)
        if b is None:
            b = bmesh.new()
            self._bm[role] = b
        return b

    def box(self, role: str, center, size, rot_z: float = 0.0, chamfer=None) -> None:
        """A box, chamfered by default (reviews/look/city-build.md item 2).

        `chamfer=None` applies the auto rule: 1.5 % of the smallest side, clamped to
        CHAMFER_MIN..CHAMFER_MAX, and only for elements under CHAMFER_MAX_SIDE — a 200 m slab
        lip is not what makes an edge catch the low sun, and the skyline ring must stay cheap.
        `chamfer=0.0` forces a raw 8-corner box (interiors, hidden structure).
        """
        if size[0] <= 1e-4 or size[1] <= 1e-4 or size[2] <= 1e-4:
            return
        c = self.chamfer_size(size) if chamfer is None else float(chamfer)
        if c <= 1e-4:
            geo.box(self.bm(role), center, size, rot_z)
        else:
            _chamfer_box(self.bm(role), center, size, rot_z, c)

    def chamfer_size(self, size):
        """The auto chamfer for a box of this size, or 0.0 when it must stay raw."""
        if not CHAMFER_ON or max(size) > CHAMFER_MAX_SIDE:
            return 0.0
        return min(max(min(size) * CHAMFER_FRAC, CHAMFER_MIN), CHAMFER_MAX)

    def local_box(self, role: str, origin, yaw: float, center, size) -> None:
        """Box placed in a frame rotated by `yaw` (rad) about Z around `origin` (x, y)."""
        p = rotate((origin[0] + center[0], origin[1] + center[1]), origin, yaw)
        self.box(role, (p[0], p[1], center[2]), size, yaw)

    def cylinder(self, role: str, center, radius: float, depth: float, segments: int = 16,
                 axis: str = "Z") -> None:
        geo.cylinder(self.bm(role), center, radius, depth, segments, axis)

    def prism(self, role: str, poly, z0: float, z1: float) -> None:
        """Extrude a simple polygon between two heights with outward normals."""
        if z1 - z0 <= 1e-4:
            return
        pts = dedupe(poly)
        if len(pts) < 3:
            return
        bm = self.bm(role)
        ring = ccw(pts)
        lo = [bm.verts.new((x, y, z0)) for x, y in ring]
        hi = [bm.verts.new((x, y, z1)) for x, y in ring]
        bm.faces.new(list(reversed(lo)))
        bm.faces.new(hi)
        n = len(ring)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((lo[i], lo[j], hi[j], hi[i]))

    def slab(self, role: str, poly, holes, z0: float, z1: float) -> None:
        """Polygon with inner boundaries, extruded. Holes are triangulated away with
        bmesh.ops.triangle_fill (scanfill handles inner loops)."""
        if z1 - z0 <= 1e-4:
            return
        outer = ccw(dedupe(poly))
        if len(outer) < 3:
            return
        inner = [list(reversed(ccw(dedupe(h)))) for h in (holes or []) if len(dedupe(h)) >= 3]
        _warn_touching_holes(outer, inner)
        tmp = bmesh.new()
        rings = []
        for loop in [outer] + inner:
            vs = [tmp.verts.new((x, y, z0)) for x, y in loop]
            for i in range(len(vs)):
                tmp.edges.new((vs[i], vs[(i + 1) % len(vs)]))
            rings.append(vs)
        bmesh.ops.triangle_fill(tmp, use_beauty=True, use_dissolve=False, edges=tmp.edges[:])
        for f in tmp.faces:
            if f.normal.z > 0.0:
                f.normal_flip()
        bm = self.bm(role)
        me = bpy.data.meshes.new("mc_tmp_slab")
        tmp.to_mesh(me)
        bm.from_mesh(me)
        bmesh.ops.translate(tmp, verts=tmp.verts[:], vec=(0.0, 0.0, z1 - z0))
        for f in tmp.faces:
            f.normal_flip()
        tmp.to_mesh(me)
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        tmp.free()
        for loop, vs in zip([outer] + inner, rings):
            for i in range(len(vs)):
                a, b = loop[i], loop[(i + 1) % len(loop)]
                q = [(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)]
                if _degenerate(q):
                    continue
                bm.faces.new([bm.verts.new(p) for p in q])

    def sweep(self, role: str, profile, path, closed_profile: bool = False, **kw) -> None:
        """Extrude a profile along a path (roads, barriers, beams, tunnel linings)."""
        src = geo.sweep(profile, [Vector(p) for p in path], closed_profile=closed_profile, **kw)
        me = bpy.data.meshes.new("mc_tmp_sweep")
        src.to_mesh(me)
        self.bm(role).from_mesh(me)
        bpy.data.meshes.remove(me)

    def loft(self, role: str, sections, cap_start: bool = False, cap_end: bool = False) -> None:
        """Skin a list of equal-length world-space sections into a tube (arch ribs, glazing)."""
        src = geo.loft([[Vector(p) for p in sec] for sec in sections],
                       cap_start=cap_start, cap_end=cap_end)
        me = bpy.data.meshes.new("mc_tmp_loft")
        src.to_mesh(me)
        self.bm(role).from_mesh(me)
        bpy.data.meshes.remove(me)

    def quad(self, role: str, a, b, c, d) -> None:
        pts = [a, b, c, d]
        if _degenerate(pts):
            return
        bm = self.bm(role)
        bm.faces.new([bm.verts.new(p) for p in pts])

    def window(self, a, b, c, d) -> None:
        """One emissive window cell: a single quad, UV 0..1 (ART.md 4)."""
        self.quad("mc_window", a, b, c, d)

    # ---------------------------------------------------------------- assembly
    def is_empty(self) -> bool:
        return not any(len(b.faces) for b in self._bm.values())

    def stats(self) -> dict:
        """Per-role (verts, faces, volume) — the collision fingerprint `probe_skin.py` diffs.

        Every solid this build writes is a closed box, so the volume is exact and additive; it is
        the number that must not move when a structure is skinned.
        """
        out = {}
        for role, bm in self._bm.items():
            if len(bm.faces):
                out[role] = (len(bm.verts), len(bm.faces),
                             round(abs(bm.calc_volume(signed=True)), 3))
        return out

    def merged(self):
        """Consume the kit into one bmesh whose faces carry `material_index` = index into
        roles.ROLE_ORDER, or None when empty. The Kit is empty afterwards."""
        live = [(r, b) for r, b in self._bm.items() if len(b.faces)]
        if not live:
            return None
        for role, b in live:
            idx = roles.ROLE_ORDER.index(role)
            for f in b.faces:
                f.material_index = idx
        base = live[0][1]
        for _, b in live[1:]:
            me = bpy.data.meshes.new("mc_tmp_merge")
            b.to_mesh(me)
            base.from_mesh(me)
            bpy.data.meshes.remove(me)
            b.free()
        self._bm = {}
        return base

    def bounds(self):
        """World-space (lo, hi) of everything added so far, or None when empty."""
        lo = Vector((1e18, 1e18, 1e18))
        hi = Vector((-1e18, -1e18, -1e18))
        seen = False
        for b in self._bm.values():
            for v in b.verts:
                seen = True
                for i in range(3):
                    lo[i] = min(lo[i], v.co[i])
                    hi[i] = max(hi[i], v.co[i])
        return (lo, hi) if seen else None


class MutedKit(Kit):
    """A Kit that swallows every render primitive.

    Kit skin mode (blender/city/skin.py) keeps a structure's collision and occluders but drops its
    render mesh, because city-kit fits a Tripo model over the same box. The builders write render
    and solids through separate objects, so handing them a MutedKit in place of the render Kit
    removes exactly the visible geometry and nothing else — no per-builder `if skinned:` branch.
    """

    def __init__(self, name: str = "muted"):
        super().__init__(name)

    def box(self, role, center, size, rot_z: float = 0.0, chamfer=None) -> None:
        return

    def cylinder(self, role, center, radius: float, depth: float, segments: int = 16,
                 axis: str = "Z") -> None:
        return

    def prism(self, role, poly, z0: float, z1: float) -> None:
        return

    def slab(self, role, poly, holes, z0: float, z1: float) -> None:
        return

    def sweep(self, role, profile, path, closed_profile: bool = False, **kw) -> None:
        return

    def loft(self, role, sections, cap_start: bool = False, cap_end: bool = False) -> None:
        return

    def quad(self, role, a, b, c, d) -> None:
        return


_CORNERS = [(sx, sy, sz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]


def _chamfer_box(bm, center, size, rot_z, c):
    """A box whose 12 edges and 8 corners are cut back by `c`: 24 verts, 26 flat faces.

    Winding is decided per face by comparing the face normal against the outward direction from
    the box centre, which is exact for a convex hull and costs nothing — a `recalc_face_normals`
    pass per box would, because a Kit holds tens of thousands of them.
    """
    h = (size[0] * 0.5, size[1] * 0.5, size[2] * 0.5)
    c = min(c, h[0] * 0.45, h[1] * 0.45, h[2] * 0.45)
    if c <= 1e-4:
        geo.box(bm, center, size, rot_z)
        return
    co, si = math.cos(rot_z), math.sin(rot_z)

    def world(p):
        return (center[0] + p[0] * co - p[1] * si, center[1] + p[0] * si + p[1] * co,
                center[2] + p[2])

    pos = {}
    for corner in _CORNERS:
        base = (corner[0] * h[0], corner[1] * h[1], corner[2] * h[2])
        for axis in range(3):
            p = list(base)
            p[axis] -= math.copysign(c, p[axis])
            pos[corner + (axis,)] = world(p)
    verts = {k: bm.verts.new(p) for k, p in pos.items()}

    def face(keys):
        pts = [pos[k] for k in keys]
        ux = [pts[1][i] - pts[0][i] for i in range(3)]
        vx = [pts[2][i] - pts[0][i] for i in range(3)]
        n = (ux[1] * vx[2] - ux[2] * vx[1], ux[2] * vx[0] - ux[0] * vx[2],
             ux[0] * vx[1] - ux[1] * vx[0])
        m = len(pts)
        out = [sum(p[i] for p in pts) / m - center[i] for i in range(3)]
        if sum(n[i] * out[i] for i in range(3)) < 0.0:
            keys = list(reversed(keys))
        bm.faces.new([verts[k] for k in keys])

    for axis in range(3):
        b, d = [a for a in range(3) if a != axis]
        for s in (-1, 1):
            ring = []
            for sb, sd in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                signs = [0, 0, 0]
                signs[axis], signs[b], signs[d] = s, sb, sd
                ring.append(tuple(signs) + (axis,))
            face(ring)
    for a in range(3):
        for b in range(a + 1, 3):
            d = 3 - a - b
            for sa in (-1, 1):
                for sb in (-1, 1):
                    lo = [0, 0, 0]
                    lo[a], lo[b], lo[d] = sa, sb, -1
                    hi = list(lo)
                    hi[d] = 1
                    lo, hi = tuple(lo), tuple(hi)
                    face([lo + (a,), lo + (b,), hi + (b,), hi + (a,)])
    for corner in _CORNERS:
        face([corner + (0,), corner + (1,), corner + (2,)])


def _degenerate(pts, eps=1e-4):
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        if abs(a[0] - b[0]) > eps or abs(a[1] - b[1]) > eps or abs(a[2] - b[2]) > eps:
            return False
    return True


def _warn_touching_holes(outer, inner, eps=0.5):
    """Scanfill needs strictly interior holes. A hole that reaches the outer ring is a notch, and
    scanfill silently returns a partial triangulation — which cost the ground crust 80 % of its
    area once (blender/city/probe_crust.py). Clip the hole back inside and say so."""
    if not inner:
        return
    ox0, ox1 = min(p[0] for p in outer), max(p[0] for p in outer)
    oy0, oy1 = min(p[1] for p in outer), max(p[1] for p in outer)
    out = []
    for h in inner:
        if (min(p[0] for p in h) >= ox0 + eps and max(p[0] for p in h) <= ox1 - eps
                and min(p[1] for p in h) >= oy0 + eps and max(p[1] for p in h) <= oy1 - eps):
            out.append(h)
            continue
        clipped = _clip_box(h, ox0 + eps, ox1 - eps, oy0 + eps, oy1 - eps)
        print("city-build: a slab hole reached the outer boundary and was clipped to it "
              "(outer x %.0f..%.0f y %.0f..%.0f, %d points left)"
              % (ox0, ox1, oy0, oy1, len(clipped)))
        if len(clipped) >= 3:
            out.append(clipped)
    inner[:] = out


def _clip_box(poly, x0, x1, y0, y1):
    """Sutherland-Hodgman clip of a polygon to an axis-aligned box."""
    def clip(pts, inside, cut):
        if not pts:
            return pts
        out = []
        for a, b in zip(pts, pts[1:] + pts[:1]):
            ia, ib = inside(a), inside(b)
            if ia:
                out.append(a)
            if ia != ib:
                t = cut(a, b)
                out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
        return out

    poly = clip(poly, lambda p: p[0] >= x0, lambda a, b: (x0 - a[0]) / (b[0] - a[0]))
    poly = clip(poly, lambda p: p[0] <= x1, lambda a, b: (x1 - a[0]) / (b[0] - a[0]))
    poly = clip(poly, lambda p: p[1] >= y0, lambda a, b: (y0 - a[1]) / (b[1] - a[1]))
    return clip(poly, lambda p: p[1] <= y1, lambda a, b: (y1 - a[1]) / (b[1] - a[1]))


def tag_windows(mesh, cell: float = 4.0) -> int:
    """Re-map every emissive-window quad: U = 0..cells (one unit per 4 m cell, so each cell is
    UV 0..1), V = 0..1 across the band height. Returns the band count."""
    if not mesh.uv_layers:
        return 0
    layer = mesh.uv_layers[0]
    n = 0
    for poly in mesh.polygons:
        if poly.material_index != WINDOW or poly.loop_total != 4:
            continue
        vs = [mesh.vertices[mesh.loops[li].vertex_index].co for li in poly.loop_indices]
        span = max((vs[i] - vs[(i + 1) % 4]).length for i in range(4))
        cells = max(1, int(round(span / cell)))
        corners = [(0.0, 0.0), (float(cells), 0.0), (float(cells), 1.0), (0.0, 1.0)]
        for k, li in enumerate(poly.loop_indices):
            layer.data[li].uv = corners[k]
        n += 1
    return n


def object_from_bmesh(name: str, bm, col, materials):
    """Turn a tagged bmesh into an object with one material slot per role used."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    col.objects.link(obj)
    for mat in materials:
        me.materials.append(mat)
    return obj
