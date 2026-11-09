"""Shared mesh primitives for the hero3 weapons and props (hero-v3).

Small, deterministic builders: a swept prism with an arbitrary cross-section, a bevelled plate from a
2D outline, a lathe for turned parts (pommel caps, bosses, collars). Every one returns an object whose
normals have been recalculated outward -- a hand-built cap comes out wound either way depending on
the frame, and an inward-facing one lights from behind and renders as a black disc.

  import hero3_props; obj = hero3_props.prism("Hilt", origin, direction, sections, mats)
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/hero3"))


def mesh(name: str, verts, faces, mats, smooth: bool = False):
    """A mesh object with outward normals and the given material slots."""
    data = bpy.data.meshes.new(name)
    data.from_pydata([tuple(v) for v in verts], [], faces)
    data.validate()
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(data)
    bm.free()
    data.update()
    for mat in mats:
        data.materials.append(mat)
    if smooth:
        for poly in data.polygons:
            poly.use_smooth = True
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def frame(direction: Vector) -> tuple:
    """An orthonormal frame with +X along `direction`."""
    x = Vector(direction).normalized()
    up = Vector((0.0, 0.0, 1.0))
    if abs(x.dot(up)) > 0.95:
        up = Vector((0.0, 1.0, 0.0))
    y = x.cross(up).normalized()
    return x, y, x.cross(y).normalized()


def prism(name: str, origin: Vector, direction: Vector, sections, mats, smooth: bool = False):
    """A swept solid: `sections` is [(along, profile)] where profile is [(u, v)] in the local frame.

    Every section must carry the same number of points, so a blade can go from a wide hexagonal
    cross-section at the guard to a point without a single triangle fold."""
    x, y, z = frame(direction)
    verts, faces = [], []
    count = len(sections[0][1])
    for along, profile in sections:
        base = origin + x * along
        verts.extend([base + y * u + z * v for u, v in profile])
    for s in range(len(sections) - 1):
        a, b = s * count, (s + 1) * count
        for i in range(count):
            j = (i + 1) % count
            faces.append((a + i, a + j, b + j, b + i))
    faces.append(tuple(range(count - 1, -1, -1)))
    last = (len(sections) - 1) * count
    faces.append(tuple(range(last, last + count)))
    return mesh(name, verts, faces, mats, smooth)


def box_profile(half_w: float, half_t: float) -> list:
    """The rectangular profile the original weapons used, as [(u, v)]."""
    return [(half_w, half_t), (-half_w, half_t), (-half_w, -half_t), (half_w, -half_t)]


def lathe(name: str, origin: Vector, axis: Vector, profile, mats, segments: int = 24,
          smooth: bool = True):
    """A surface of revolution: `profile` is [(along, radius)] and the ends are capped flat."""
    x, y, z = frame(axis)
    verts, faces = [], []
    for along, radius in profile:
        base = origin + x * along
        for i in range(segments):
            a = 2.0 * math.pi * i / segments
            verts.append(base + y * math.cos(a) * radius + z * math.sin(a) * radius)
    for s in range(len(profile) - 1):
        lo, hi = s * segments, (s + 1) * segments
        for i in range(segments):
            j = (i + 1) % segments
            faces.append((lo + i, lo + j, hi + j, hi + i))
    faces.append(tuple(range(segments - 1, -1, -1)))
    last = (len(profile) - 1) * segments
    faces.append(tuple(range(last, last + segments)))
    return mesh(name, verts, faces, mats, smooth)


def plate(name: str, origin: Vector, normal: Vector, outline, thickness: float, mats,
          bevel: float = 0.0, boss: float = 0.0):
    """A flat armour plate from a 2D outline, extruded along `normal`.

    The outline's u axis is horizontal (world up x normal) and its v axis is world up, so a shield
    built with a lateral normal stands vertically instead of lying flat. `bevel` shrinks the front
    and back faces inward, which is what turns a slab into a bevelled shield; `boss` raises the
    centre of the front face into a shallow dome."""
    n = Vector(normal).normalized()
    up = Vector((0.0, 0.0, 1.0))
    y = up - n * up.dot(n)
    y = y.normalized() if y.length > 1e-4 else Vector((0.0, 1.0, 0.0))
    x = y.cross(n).normalized()
    count = len(outline)
    cu = sum(p[0] for p in outline) / count
    cv = sum(p[1] for p in outline) / count
    verts, faces = [], []
    rings = [(0.0, 0.0), (thickness * 0.28, bevel), (thickness * 0.72, bevel), (thickness, 0.0)]
    for side, inset in rings:
        for u, v in outline:
            du, dv = u - cu, v - cv
            length = math.hypot(du, dv)
            scale = max(0.0, 1.0 - inset / max(length, 1e-6))
            verts.append(origin + x * (cu + du * scale) + y * (cv + dv * scale) + n * side)
    for s in range(len(rings) - 1):
        lo, hi = s * count, (s + 1) * count
        for i in range(count):
            j = (i + 1) % count
            faces.append((lo + i, lo + j, hi + j, hi + i))
    faces.append(tuple(range(count - 1, -1, -1)))
    faces.append(tuple(range(3 * count, 4 * count)))
    if boss > 0.0:
        centre = origin + x * cu + y * cv + n * (thickness + boss)
        apex = len(verts)
        verts.append(centre)
        base = 3 * count
        for i in range(count):
            faces.append((base + i, base + (i + 1) % count, apex))
    return mesh(name, verts, faces, mats)


def band(name: str, origin: Vector, normal: Vector, outer, inner, thickness: float, mats):
    """A flat RING between two outlines of the same vertex count, extruded along `normal`.

    `plate` fills its outline, so a seam drawn with it comes out as a solid disc -- which is how the
    shield's cyan seam turned the whole centre of the shield into a white slab."""
    n = Vector(normal).normalized()
    up = Vector((0.0, 0.0, 1.0))
    y = up - n * up.dot(n)
    y = y.normalized() if y.length > 1e-4 else Vector((0.0, 1.0, 0.0))
    x = y.cross(n).normalized()
    count = len(outer)
    verts, faces = [], []
    for side in (0.0, thickness):
        for outline in (outer, inner):
            for u, v in outline:
                verts.append(origin + x * u + y * v + n * side)
    lo_o, lo_i, hi_o, hi_i = 0, count, 2 * count, 3 * count
    for i in range(count):
        j = (i + 1) % count
        faces.append((hi_o + i, hi_o + j, hi_i + j, hi_i + i))     ## front annulus
        faces.append((lo_i + i, lo_i + j, lo_o + j, lo_o + i))     ## back annulus
        faces.append((lo_o + i, lo_o + j, hi_o + j, hi_o + i))     ## outer wall
        faces.append((hi_i + i, hi_i + j, lo_i + j, lo_i + i))     ## inner wall
    return mesh(name, verts, faces, mats)


def set_materials(obj, indices: dict) -> None:
    """Per-face material indices by face-range key: {"sides": 1, "front": 0}."""
    for poly in obj.data.polygons:
        poly.material_index = indices.get("default", 0)
    _ = indices


def assign_faces(obj, predicate) -> None:
    """Set each face's material slot from `predicate(face_index, face)` -> slot."""
    for i, poly in enumerate(obj.data.polygons):
        slot = predicate(i, poly)
        if slot is not None:
            poly.material_index = slot


def transform(obj, matrix: Matrix) -> None:
    obj.data.transform(matrix)
    obj.data.update()
