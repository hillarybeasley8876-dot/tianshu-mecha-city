"""Shared Tripo glTF import for the city kit, with the weld that the decimator depends on.

`merge_vertices` matters: glTF splits a vertex at every UV seam, so without it every seam arrives as
an open boundary and the collapse decimator then shrinks each UV island on its own — islands drift
apart and the mesh ships as a shredded shell with daylight through it (lead r2 item 2; the same
thing bit monster-assets and hero3, see blender/monsters/mon_lib.py). Blender keeps UVs per face
corner, so welding costs no UVs.
"""
from __future__ import annotations

import bmesh
import bpy

from lib import common

#: A welded Tripo mesh may still have real boundaries (it ships open shells), but a UV seam must
#: never become one: past this fraction of all edges the build says so.
WELD_GATE = 0.02


def import_glb(path: str, weld: bool = True) -> list:
    """Import a glb, welded. Returns the objects it added.

    The importer's own `merge_vertices` is not enough on a glb Blender itself wrote: measured on
    m04's processed mesh it left 45.7 % of edges open, while an explicit `remove_doubles` at 0.1 mm
    took the same mesh to 0 (tmp/city-kit/weldtest2.py). glTF has one UV per vertex, so the exporter
    MUST split a vertex at every seam; whether those splits come back weldable or as drifted islands
    is the whole difference between a solid far LOD and a shredded one.
    """
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path, merge_vertices=True)
    new = [o for o in bpy.data.objects if o not in before]
    if weld:
        for obj in new:
            if obj.type == "MESH":
                weld_mesh(obj)
    return new


def weld_mesh(obj: bpy.types.Object, dist: float = 1e-4) -> int:
    """Merge coincident vertices in place. Returns the vertex count after the weld."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=dist)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return len(obj.data.vertices)


def check_welded(label: str, obj: bpy.types.Object) -> float:
    """Print a mesh's open-edge fraction — the QA gate for the weld above. Returns the fraction."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    total = len(bm.edges)
    boundary = sum(1 for e in bm.edges if len(e.link_faces) < 2)
    bm.free()
    frac = boundary / max(total, 1)
    print("WELD %-14s %6d open / %6d edges = %5.2f%%%s"
          % (label, boundary, total, 100.0 * frac,
             "  OVER GATE %.0f%%" % (100.0 * WELD_GATE) if frac > WELD_GATE else ""))
    return frac


def shade(obj: bpy.types.Object, angle_deg: float = 30.0) -> int:
    """Smooth-by-angle that actually takes effect, then area-weighted normals.

    A glTF always carries a NORMAL attribute, Blender imports it as custom split normals, and those
    SURVIVE a decimate (measured on t01: `has_custom_normals` True at 749 k tris and still True after a
    0.15 collapse). Custom normals override `use_smooth` and sharp edges outright, so a plain
    `common.smooth()` writes shading flags nothing reads and the mesh ships the collapse's interpolated
    per-facet normals — the faceting the lead saw as crumpled foil (r3). Returns 1 if it cleared any.

    The weighted-normal pass is r4's second half. `planar.flatten()` has already made each wall one
    plane, so inside a region every face normal IS the plane normal and smooth shading is already
    right; what is left is the BORDER, where a vertex is shared with a curved neighbour and a plain
    average bends the normal of the last row of the wall. Face-area weighting with `keep_sharp` pulls
    those back onto the plane, so a grazing sun lights a 30 m wall as one value instead of banding it.
    """
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    had = bool(getattr(obj.data, "has_custom_normals", False))
    if had:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    common.smooth(obj, angle_deg=angle_deg)
    mod = obj.modifiers.new("weighted", "WEIGHTED_NORMAL")
    mod.mode = "FACE_AREA_WITH_ANGLE"
    mod.weight = 60
    mod.keep_sharp = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return 1 if had else 0


def holes(obj: bpy.types.Object) -> int:
    """Open boundary EDGES — the direct measure of a torn mesh, cheaper than rendering for a gate.

    A closed Tripo shell has none; a collapsed one that lost its weld has thousands. This is what
    the far tier's silhouette gate reads (lead r2 item 2, step 2).
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    n = sum(1 for e in bm.edges if len(e.link_faces) < 2)
    bm.free()
    return n
