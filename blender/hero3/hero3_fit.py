"""Fit inner volumes to the armour they live in (hero-v3, lead review r1).

The first pass gave every limb ONE cylinder of a fixed radius taken from the limb's outer measurement.
On a tapered, flared armour plate that is wrong everywhere: at the thigh the cylinder burst out through
the lamellar skirt, at the chest it stood above the grille, and the whole mech read as a robot built
from drain pipes. A fixed radius cannot fit a shape that is not a cylinder.

So the inner volume is MEASURED off the plate itself: at K stations along the bone axis, N rays are
cast outward against the armour and the core radius at each sample is `FIT` x the distance to the
first hit. The core is then lofted through those rings, so it follows every taper and flare and is
strictly inside by construction. Where a ray leaves through a joint opening it has no hit, and the
neighbouring azimuths' minimum is used instead.

  import hero3_fit; rings = hero3_fit.shell_rings(tree, head, tail, extent)
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/hero3"))
import hero3_joints  # noqa: E402

FIT = 0.78           ## the core sits this fraction of the way out to the armour
MARGIN = 0.04        ## ... minus this many metres, so it never grazes a hairline cut line
STATIONS = 18        ## samples along the bone (a 4 m thigh is 0.23 m between rings)
AZIMUTHS = 16        ## rays around each station
RAY_MAX = 6.0        ## metres; a longer shot means the ray left the plate entirely
MIN_RADIUS = 0.06    ## never loft a degenerate ring
MIN_HIT = 0.10       ## a hit closer than this means the ray started on a surface, not inside one
ESCAPE = 1.25        ## a hit this much longer than the station's median left along a thin flange
                     ## (the tassets are 2.4 m wide but paper thin: a ray runs out along one and the
                     ## ring balloons into a 5 m disc at hip height)
CORE_RGB = (0.070, 0.078, 0.094)   ## #121418, near black: an opening must read as shadowed interior
CORE_ROUGH = 0.60
SHRINK_PASSES = 0     ## containment passes per core; OFF -- see shrink_to_fit for why
SHRINK = 0.86         ## how much of its radius a point outside the armour loses per pass
SNAP_DEPTH = 0.06      ## how far inside the armour wall a snapped core point sits
CORE_SHRINK = 0.62     ## final uniform shrink about each core's own centroid (see build_cores)
PROBE_DIRS = (Vector((0.577, 0.577, 0.577)), Vector((-0.707, 0.707, 0.0)),
              Vector((0.0, -0.577, 0.816)))


def _parity(tree: BVHTree, p: Vector) -> bool:
    """Inside ONE closed shell, by ray-crossing parity (3 directions, majority vote)."""
    votes = 0
    for d in PROBE_DIRS:
        crossings, origin = 0, p.copy()
        for _ in range(16):
            location, _, _, dist = tree.ray_cast(origin, d, RAY_MAX * 4.0)
            if location is None:
                break
            crossings += 1
            origin = location + d * 1e-4
        votes += 1 if crossings % 2 else 0
    return votes >= 2


class Armour:
    """Inside-ness against the whole plate set.

    Parity over ONE merged BVH is wrong here and it cost a whole build to find out: the plates overlap
    (the tassets wrap the thighs, the chest overlaps the spine), so a point inside two shells crosses
    an even number of surfaces and reads as outside. Spine02 collapsed to a 4 cm stub that way. Each
    plate is its own closed shell, so each is tested on its own and the answer is the OR."""

    def __init__(self, plates: list) -> None:
        self.trees = [armour_tree([p], quiet=True) for p in plates]
        self.merged = armour_tree(plates, quiet=True)
        self.centres = []
        for plate in plates:
            lo, hi = _bounds(plate)
            self.centres.append((lo + hi) * 0.5)
        print("ARMOUR %d plate shells for the containment test" % len(self.trees))

    def inside(self, p: Vector) -> bool:
        order = sorted(range(len(self.trees)), key=lambda i: (self.centres[i] - p).length_squared)
        for i in order:
            if _parity(self.trees[i], p):
                return True
        return False

    def snap_inside(self, p: Vector, depth: float = SNAP_DEPTH) -> Vector:
        """The nearest point just inside the armour wall, or `p` unchanged if there is none.

        Shrinking toward the ring centre cannot rescue a core whose BONE AXIS runs outside the plate:
        at the boot the straight line from the ankle to the toe leaves the instep entirely, so the loft
        converged onto a line that is still in the open air and the foot kept its magenta. The wall is
        the only thing that knows where "inside" is, so the point is moved onto it. Which side of the
        wall is the inside is MEASURED, not assumed: Tripo's normals are outward but the caps
        hero3_cap adds come out wound either way."""
        location, normal, _, _ = self.merged.find_nearest(p)
        if location is None:
            return p
        for candidate in (location - normal * depth, location + normal * depth):
            if self.inside(candidate):
                return candidate
        return p

    def audit(self, rings: list) -> int:
        """How many ring points and quad centres are still outside. The build prints this number."""
        bad = 0
        for ring in rings:
            bad += sum(1 for p in ring if not self.inside(p))
        for r in range(len(rings) - 1):
            lo, hi = rings[r], rings[r + 1]
            for i in range(len(lo)):
                j = (i + 1) % len(lo)
                if not self.inside((lo[i] + lo[j] + hi[j] + hi[i]) / 4.0):
                    bad += 1
        return bad


def _shrink_about_centroid(rings: list, factor: float) -> list:
    """One uniform scale of the whole core about its own centroid.

    The containment pass works sample by sample and leaves a tail: a quad that spans two snapped
    points can still bulge through a concave wall, and the pixel gate -- which is the ground truth --
    kept a few dozen magenta pixels at the feet and the chest. A uniform shrink moves every part of
    the core toward the middle of the limb it lives in, which is the one direction that is inside
    everywhere, and it costs the plug nothing that the joint collars do not already cover."""
    centre = sum((p for ring in rings for p in ring), Vector()) / sum(len(r) for r in rings)
    return [[centre + (p - centre) * factor for p in ring] for ring in rings]


def _bounds(obj) -> tuple:
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    return (Vector([min(p[i] for p in pts) for i in range(3)]),
            Vector([max(p[i] for p in pts) for i in range(3)]))


def shrink_to_fit(rings: list, armour: "Armour") -> tuple:
    """Pull the lofted surface inside the armour until every sample of it is enclosed.

    Two moves, in order. A sample outside is first SNAPPED onto the inside of the nearest armour wall
    -- that is the only move that works where the bone axis itself leaves the plate. If the snap finds
    no inside (the sample is in a gap between two plates) the sample is pulled toward its own ring
    centre instead, which is what thins a core that is simply too fat for its limb. Ring points alone
    are not enough either: the quad between two rings cuts the chord across a concave plate, so the
    quad centres are tested too and all four corners move. Returns (rings, moved samples)."""
    moved = 0
    for _ in range(SHRINK_PASSES):
        changed = _shrink_rings(rings, armour) + _shrink_quads(rings, armour)
        moved += changed
        if not changed:
            break
    return rings, moved


def _pull(p: Vector, centre: Vector, armour: "Armour") -> Vector:
    snapped = armour.snap_inside(p)
    if snapped != p:
        return snapped
    return centre + (p - centre) * SHRINK


def _shrink_rings(rings: list, armour: "Armour") -> int:
    changed = 0
    for ring in rings:
        centre = sum(ring, Vector()) / len(ring)
        for i, p in enumerate(ring):
            if armour.inside(p):
                continue
            ring[i] = _pull(p, centre, armour)
            changed += 1
    return changed


def _shrink_quads(rings: list, armour: "Armour") -> int:
    """The loft's own surface: a quad whose centre is outside drags all four of its corners in."""
    changed = 0
    centres = [sum(ring, Vector()) / len(ring) for ring in rings]
    for r in range(len(rings) - 1):
        lo, hi = rings[r], rings[r + 1]
        n = len(lo)
        for i in range(n):
            j = (i + 1) % n
            middle = (lo[i] + lo[j] + hi[j] + hi[i]) / 4.0
            if armour.inside(middle):
                continue
            for ring, centre, index in ((lo, centres[r], i), (lo, centres[r], j),
                                        (hi, centres[r + 1], i), (hi, centres[r + 1], j)):
                ring[index] = _pull(ring[index], centre, armour)
            changed += 1
    return changed


def armour_tree(objects: list, quiet: bool = False) -> BVHTree:
    """A BVH over the listed plates. Pass ONE plate when fitting that plate's core: a ray that leaves
    through a joint opening must MISS, not hit the neighbouring limb 2 m away.

    Fitting against the whole armour is what produced a 2 m radius neck core and a 1.1 m calf core --
    the ray went out of the collar, crossed the gap and came back on the shoulder."""
    verts, polys = [], []
    for obj in objects:
        offset = len(verts)
        mesh = obj.data
        mw = obj.matrix_world
        verts.extend([mw @ v.co for v in mesh.vertices])
        for poly in mesh.polygons:
            polys.append([offset + i for i in poly.vertices])
    tree = BVHTree.FromPolygons(verts, polys, all_triangles=False, epsilon=0.0)
    if not quiet:
        print("FIT bvh over %d plate(s), %d polys" % (len(objects), len(polys)))
    return tree


def _frame(axis: Vector) -> tuple:
    up = Vector((0.0, 0.0, 1.0))
    if abs(axis.dot(up)) > 0.95:
        up = Vector((0.0, 1.0, 0.0))
    u = axis.cross(up).normalized()
    return u, axis.cross(u).normalized()


def plate_extent(plate, head: Vector, axis: Vector) -> tuple:
    """How far the plate reaches along the bone axis, measured from the bone head."""
    lo, hi = 1e9, -1e9
    for v in plate.data.vertices:
        s = (plate.matrix_world @ v.co - head).dot(axis)
        lo, hi = min(lo, s), max(hi, s)
    return lo, hi


def shell_rings(tree: BVHTree, head: Vector, axis: Vector, lo: float, hi: float,
                fit: float = FIT) -> list:
    """One ring of points per station: the inner surface of the armour, scaled by `fit`.

    A station where no ray hits anything (the bone axis is outside the plate there) is dropped, so a
    core never appears where the armour does not cover it."""
    u, v = _frame(axis)
    rings = []
    for k in range(STATIONS):
        s = lo + (hi - lo) * (k + 0.5) / STATIONS
        origin = head + axis * s
        hits = []
        for a in range(AZIMUTHS):
            angle = 2.0 * math.pi * a / AZIMUTHS
            direction = (u * math.cos(angle) + v * math.sin(angle)).normalized()
            location, _, _, dist = tree.ray_cast(origin, direction, RAY_MAX)
            hits.append(dist if location is not None and dist >= MIN_HIT else None)
        hits = _drop_escapes(hits)
        radii = _fill_blind_spots(hits)
        if radii is None:
            continue
        ring = []
        for a in range(AZIMUTHS):
            angle = 2.0 * math.pi * a / AZIMUTHS
            direction = (u * math.cos(angle) + v * math.sin(angle)).normalized()
            ring.append(origin + direction * max(radii[a] * fit - MARGIN, MIN_RADIUS))
        rings.append(ring)
    return rings


def _drop_escapes(hits: list) -> list:
    """Blank the rays that left through a joint opening and hit something far away.

    Without this a calf station reads 0.56-3.16 m -- the long rays went out of the shin and hit the
    other leg -- and the loft is built through a wildly non-circular ring."""
    valid = sorted(h for h in hits if h is not None)
    if not valid:
        return hits
    median = valid[len(valid) // 2]
    return [h if (h is not None and h <= median * ESCAPE) else None for h in hits]


def _fill_blind_spots(hits: list):
    """Replace the rays that left through an opening with the smallest hit beside them."""
    valid = [h for h in hits if h is not None]
    if len(valid) < AZIMUTHS // 3:
        return None
    out = list(hits)
    for a in range(AZIMUTHS):
        if out[a] is not None:
            continue
        left = right = None
        for step in range(1, AZIMUTHS):
            lo = hits[(a - step) % AZIMUTHS]
            hi = hits[(a + step) % AZIMUTHS]
            if left is None and lo is not None:
                left = lo
            if right is None and hi is not None:
                right = hi
            if left is not None and right is not None:
                break
        out[a] = min(x for x in (left, right) if x is not None)
    return out


def loft(name: str, rings: list, mats: list):
    """A closed tube through the measured rings, smooth shaded."""
    if len(rings) < 2:
        return None
    verts, faces = [], []
    for ring in rings:
        verts.extend(ring)
    n = len(rings[0])
    for r in range(len(rings) - 1):
        a, b = r * n, (r + 1) * n
        for i in range(n):
            j = (i + 1) % n
            faces.append((a + i, a + j, b + j, b + i))
    faces.append(tuple(range(n - 1, -1, -1)))
    last = (len(rings) - 1) * n
    faces.append(tuple(range(last, last + n)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.validate()
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for mat in mats:
        obj.data.materials.append(mat)
    return obj


def core_material():
    """Near-black and matte: an opening has to read as shadowed interior, never as a grey surface."""
    mat = bpy.data.materials.get("Hero3Core")
    if mat is not None:
        return mat
    mat = bpy.data.materials.new("Hero3Core")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = CORE_RGB + (1.0,)
    bsdf.inputs["Metallic"].default_value = 0.25
    bsdf.inputs["Roughness"].default_value = CORE_ROUGH
    return mat


def build_cores(plates_by_bone: dict, bones: dict) -> list:
    """One fitted inner volume per limb/torso bone. Returns the new objects.

    Two passes: every core is measured against its OWN plate (a ray that leaves through a joint
    opening must miss, not come back on the neighbouring limb 2 m away), then all of them are shrunk
    until every ring point is inside the armour as a whole."""
    mat = core_material()
    plans = []
    for bone in hero3_joints.CORE_BONES:
        plate = plates_by_bone.get(bone)
        if plate is None:
            print("CORE %-12s no plate, skipped" % bone)
            continue
        head = Vector(bones[bone]["head"])
        tail = Vector(bones[bone]["tail"])
        axis = (tail - head).normalized()
        # the core fills the BONE's volume, not the whole plate: the pelvis plate reaches 2.6 m down
        # into the tassets, and a core lofted through them ends in an exposed cap at the crotch
        length = (tail - head).length
        lo, hi = plate_extent(plate, head, axis)
        lo, hi = max(lo, -length * 0.18), min(hi, length * 1.08)
        rings = shell_rings(armour_tree([plate]), head, axis, lo, hi)
        if len(rings) < 2:
            print("CORE %-12s only %d rings, skipped" % (bone, len(rings)))
            continue
        plans.append({"bone": bone, "rings": rings, "lo": lo, "hi": hi})
    armour = Armour(list(plates_by_bone.values()))
    out = []
    for plan in plans:
        rings, moved = shrink_to_fit(plan["rings"], armour)
        rings = _shrink_about_centroid(rings, CORE_SHRINK)
        obj = loft("H3C_" + plan["bone"], rings, [mat])
        if obj is None:
            continue
        obj["hero3_bone"] = plan["bone"]
        obj["hero3_core"] = True
        out.append(obj)
        widths = [_ring_radius(r) for r in rings]
        print("CORE %-12s %2d rings along s[%.2f %.2f], radius %.2f..%.2f m, %4d moved, %d still out"
              % (plan["bone"], len(rings), plan["lo"], plan["hi"],
                 min(min(w) for w in widths), max(max(w) for w in widths), moved,
                 armour.audit(rings)))
    print("CORES %d fitted inner volumes" % len(out))
    return out


def _ring_radius(ring: list) -> list:
    centre = sum(ring, Vector()) / len(ring)
    return [(p - centre).length for p in ring]


def joint_radius(plate, bones: dict, bone: str, along: float = 0.22) -> float:
    """The armour's inner radius just inside a joint, so a mechanism can be sized to fit.

    Sampled a fraction `along` down the bone rather than at the joint itself: on the joint the axis
    sits exactly on the cut plane between two plates, so an inward ray hits the neighbouring plate
    almost immediately and the measurement collapses (0.41 m at the shoulder instead of ~0.9)."""
    head = Vector(bones[bone]["head"])
    tail = Vector(bones[bone]["tail"])
    axis = (tail - head).normalized()
    origin = head + axis * ((tail - head).length * along)
    u, v = _frame(axis)
    tree = armour_tree([plate])
    hits = []
    for a in range(AZIMUTHS):
        angle = 2.0 * math.pi * a / AZIMUTHS
        direction = (u * math.cos(angle) + v * math.sin(angle)).normalized()
        location, _, _, dist = tree.ray_cast(origin, direction, RAY_MAX)
        hits.append(dist if location is not None and dist >= MIN_HIT else None)
    hits = _drop_escapes(hits)
    valid = [h for h in hits if h is not None]
    return min(valid) if valid else RAY_MAX
