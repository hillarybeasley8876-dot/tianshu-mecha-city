"""Boolean helpers (city-build).

`Kit.slab` triangulates inner boundaries with scanfill, which needs disjoint holes. The ground
crust is cut by the canal, the dock trench, the sunken court and every ramp trench and lift
shaft, and those overlap freely — so the crust (and anything else with overlapping cuts) is
built as a closed solid and cut with Blender's exact boolean against a collection of cutters.
"""
import bmesh
import bpy

from .builder import ccw, dedupe


def _prism_object(name, poly, z0, z1, col):
    """A closed manifold prism object from a simple polygon (used for cutters and bases)."""
    pts = dedupe(poly)
    if len(pts) < 3:
        return None
    bm = bmesh.new()
    ring = ccw(pts)
    vs = [bm.verts.new((x, y, z0)) for x, y in ring]
    face = bm.faces.new(vs)
    ret = bmesh.ops.extrude_face_region(bm, geom=[face])
    moved = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=moved, vec=(0.0, 0.0, z1 - z0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    col.objects.link(obj)
    return obj


def difference(name, base_poly, z0, z1, cutter_polys, col, base_holes=()):
    """(base polygon minus every cutter polygon) as a mesh datablock; caller frees it.

    `base_holes` are inner boundaries that do not overlap anything AND are strictly inside the
    base (kept out of the boolean so scanfill handles them). Anything that touches the base's
    edge — a plateau that runs to the map boundary, say — must be passed as a cutter instead:
    scanfill treats it as a hole, produces a partial triangulation, and the boolean then keeps
    only that fragment. Cutters are extruded a little past both faces so no coplanar faces
    confuse the solver.
    """
    objs = []
    if base_holes:
        from .builder import Kit
        kit = Kit(name)
        kit.slab("mc_concrete", base_poly, base_holes, z0, z1)
        bm = kit.merged()
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-3)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        base = bpy.data.objects.new(name, me)
        col.objects.link(base)
    else:
        base = _prism_object(name, base_poly, z0, z1, col)
    if base is None:
        return None
    cutters = bpy.data.collections.new(name + "_cutters")
    col.children.link(cutters)
    for i, poly in enumerate(cutter_polys):
        obj = _prism_object("%s_cut%d" % (name, i), poly, z0 - 2.0, z1 + 2.0, cutters)
        if obj is not None:
            objs.append(obj)
    if objs:
        mod = base.modifiers.new("cut", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.operand_type = "COLLECTION"
        mod.collection = cutters
        mod.solver = "EXACT"
        bpy.context.view_layer.objects.active = base
        bpy.ops.object.modifier_apply(modifier=mod.name)
    me = base.data
    me.name = name
    for obj in objs:
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(cutters)
    bpy.data.objects.remove(base, do_unlink=True)
    return me


def add_mesh(kit, solids, role, me, collision=True):
    """Append a boolean result to the render kit (as `role`) and to the collision kit."""
    kit.bm(role).from_mesh(me)
    if collision:
        solids.col.bm("mc_concrete").from_mesh(me)
