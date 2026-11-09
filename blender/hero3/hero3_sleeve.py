"""Band every joint cut so the gap between two plates never looks into the mech (hero-v3).

The plates are capped individually, and each cap is recessed RECESS_M inside its own plate so the
opening reads as a machined rim. That leaves a band of empty space across every cut: looking straight
into it -- which is exactly what the front and the close 3/4 views do at the ankle -- the ray passes
between the two recessed caps and lands on the inner core. That was the last of the magenta in the
core gate (lead look r1, item 1: "rest must be 0 magenta px").

The fix is the collar a real machine has at a joint: a short tube built on the cut's own rim loop,
inset a couple of centimetres so it can never stand proud of the armour, and split at the cut plane so
each half is bound rigidly to its own plate and travels with it. At rest the two halves meet exactly.

  import hero3_sleeve; collars = hero3_sleeve.build(body, bone_ids, names)
"""
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/hero3"))
import hero3_cap  # noqa: E402
import hero3_lib as H  # noqa: E402

FIT_INSET = 0.012    ## metres the collar sits inside the rim, so it never grazes the armour edge
HALF = 0.22          ## half length along the cut normal (the caps recess 0.07 m on each side)
SEGMENTS = 48        ## rim points per ring: 2 mm of chord error on a 1 m rim, and a fixed tri cost
MIN_LOOP = 10        ## shorter walks are T-junction fragments, not a joint rim
MIN_RADIAL = 0.05    ## a rim point this close to the axis gets no inset


def cut_edges(bm, bone_ids) -> list:
    """Every edge of the body whose two faces belong to different bones -- the cut lines."""
    out = []
    for edge in bm.edges:
        if len(edge.link_faces) != 2:
            continue
        a, b = edge.link_faces
        if bone_ids[a.index] != bone_ids[b.index]:
            out.append(edge)
    return out


def loop_normal(pts: list) -> Vector:
    """Newell's normal: the area-weighted plane normal of a (roughly planar) closed loop."""
    n = Vector()
    for i, p in enumerate(pts):
        q = pts[(i + 1) % len(pts)]
        n.x += (p.y - q.y) * (p.z + q.z)
        n.y += (p.z - q.z) * (p.x + q.x)
        n.z += (p.x - q.x) * (p.y + q.y)
    return n.normalized() if n.length > 1e-9 else Vector((0.0, 0.0, 1.0))


def resample(pts: list, count: int) -> list:
    """`count` points evenly spaced by arc length around a closed loop."""
    lengths = [(pts[(i + 1) % len(pts)] - p).length for i, p in enumerate(pts)]
    total = sum(lengths)
    if total < 1e-6:
        return [pts[0]] * count
    out, walked, i = [], 0.0, 0
    for k in range(count):
        want = total * k / count
        while i < len(pts) - 1 and walked + lengths[i] < want:
            walked += lengths[i]
            i += 1
        t = (want - walked) / max(lengths[i], 1e-9)
        out.append(pts[i].lerp(pts[(i + 1) % len(pts)], min(max(t, 0.0), 1.0)))
    return out


def rim_loops(body, bone_ids) -> list:
    """The cut rims of the body as (points, normal, centre, parent_id, child_id), one per joint.

    The walk is over the CUT edges only, so the original open boundaries of the Tripo mesh (the soles,
    the odd hole in a skirt) never appear: they have one face, not two."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.edges.ensure_lookup_table()
    edges = cut_edges(bm, bone_ids)
    loops = hero3_cap._boundary_loops(edges)
    mw = body.matrix_world
    out = []
    for verts, used in loops:
        if len(verts) < MIN_LOOP:
            continue
        pts = [mw @ v.co for v in verts]
        centre = sum(pts, Vector()) / len(pts)
        normal = loop_normal(pts)
        sides = {}
        for edge in used:
            for face in edge.link_faces:
                key = int(bone_ids[face.index])
                c = mw @ face.calc_center_median()
                sides.setdefault(key, []).append((c - centre).dot(normal))
        if len(sides) < 2:
            continue
        ranked = sorted(sides, key=lambda k: sum(sides[k]) / len(sides[k]))
        parent, child = ranked[0], ranked[-1]
        if (sum(sides[child]) / len(sides[child])) < 0.0:
            normal = -normal
        out.append({"pts": pts, "normal": normal, "centre": centre,
                    "parent": parent, "child": child})
    bm.free()
    print("SLEEVE %d cut rims from %d cut edges" % (len(out), len(edges)))
    return out


def _band(name: str, ring_a: list, ring_b: list, mat, cap_at: str):
    """A closed tube between two rings, capped at one end. The other end is the cut plane."""
    verts = list(ring_a) + list(ring_b)
    faces = []
    n = len(ring_a)
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    faces.append(tuple(range(n, 2 * n)) if cap_at == "b" else tuple(range(n - 1, -1, -1)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.validate()
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def build(body, bone_ids, names: list) -> list:
    """One collar per cut rim, split at the plane so each half is rigid on its own plate."""
    mat = hero3_cap.cap_material()
    out = []
    for index, rim in enumerate(rim_loops(body, bone_ids)):
        normal, centre = rim["normal"], rim["centre"]
        ring = []
        for p in resample(rim["pts"], SEGMENTS):
            radial = p - centre - normal * (p - centre).dot(normal)
            ring.append(p - radial.normalized() * FIT_INSET if radial.length > MIN_RADIAL else p)
        mid = ring
        lo = [p - normal * HALF for p in ring]
        hi = [p + normal * HALF for p in ring]
        pair = []
        for label, a, b, cap_at, bone in (("A", lo, mid, "a", rim["parent"]),
                                          ("B", mid, hi, "b", rim["child"])):
            obj = _band("H3S_%02d%s" % (index, label), a, b, mat, cap_at)
            obj["hero3_bone"] = names[bone]
            pair.append(obj)
        out.extend(pair)
        print("SLEEVE %02d %-12s | %-12s  %3d pts, r %.2f-%.2f m" % (
            index, names[rim["parent"]], names[rim["child"]], len(rim["pts"]),
            min((p - centre).length for p in ring), max((p - centre).length for p in ring)))
    print("SLEEVES %d collar halves, %d tris" % (
        len(out), sum(H.tri_count(o) for o in out)))
    return out
