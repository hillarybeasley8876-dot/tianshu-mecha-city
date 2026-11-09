"""Mesh repair for the prop pipeline (city-kit r10): measure the real bounds, cap the tears the
Tripo sources ship with, and drop the stray triangles.

`process_prop.py` calls `mesh_bounds` (scale + recentre), then `prune_floaters` and `fill_holes`
either side of the decimate. `probe_holes.py` uses `boundary_groups` to report what is left.
"""
from typing import List, Optional, Tuple

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

# A boundary loop no bigger than this is a tear in the Tripo mesh, not a modelled opening, so it gets
# capped. Measured over all 30 sources (`probe_holes.py --all`, status/city-kit.md r10): the largest
# loop anywhere is blossom_tree's 0.416 m and four props are already watertight, so 0.45 m closes
# every one of them and nothing legitimate is that small and open. Capped again by a tenth of the
# prop's own size so a 2.4 m vending machine cannot grow a 45 cm patch.
HOLE_FILL_M = 0.45
HOLE_FILL_FRACTION = 0.10
# Weld threshold in metres, applied after the prop is scaled to its real size. 0.5 mm is two orders
# below the smallest panel line on a 2-16 m prop and four above float noise in a Tripo export.
WELD_M = 0.0005


def mesh_bounds(obj: bpy.types.Object) -> Tuple[Vector, Vector]:
    """World-space AABB of the vertices a FACE references, read from the MESH DATA.

    Two traps, both measured on the 60 m crane (r10):

    * `obj.bound_box` and `obj.dimensions` are CACHED, depsgraph-evaluated boxes. Straight after
      `apply_transforms()` they still hold the pre-transform extents until the view layer is
      re-evaluated, so a fresh run scaled the crane by a stale longest side and then recentred it on a
      stale box: the exported mesh came out centred, base at y = -24.9 m, sunk about 25 m into its
      deck. `tools/citykit/rebase_glb.py --check --set props` is the gate.
    * they also count LOOSE vertices, and the glTF exporter does not write a vertex no face
      references -- so a prop whose lowest vertex is loose ships a few cm above the surface. Same fix
      `blender/citykit/process.py::bounds()` already carries for the kit.
    """
    me = obj.data
    used = set()
    for poly in me.polygons:
        used.update(poly.vertices)
    if not used:
        used = set(range(len(me.vertices)))
    mw = obj.matrix_world
    lo = Vector((1e18, 1e18, 1e18))
    hi = Vector((-1e18, -1e18, -1e18))
    for i in used:
        v = mw @ me.vertices[i].co
        lo = Vector((min(lo.x, v.x), min(lo.y, v.y), min(lo.z, v.z)))
        hi = Vector((max(hi.x, v.x), max(hi.y, v.y), max(hi.z, v.z)))
    return lo, hi




def boundary_groups(bm: bmesh.types.BMesh) -> List[Tuple[List[bmesh.types.BMEdge], float]]:
    """Connected components of the open-boundary graph, each with its perimeter in metres."""
    bm.edges.ensure_lookup_table()
    bm.edges.index_update()
    boundary = [e for e in bm.edges if len(e.link_faces) == 1]
    adjacency: dict = {}
    for e in boundary:
        for v in e.verts:
            adjacency.setdefault(v.index, []).append(e)
    seen = set()
    groups: List[Tuple[List[bmesh.types.BMEdge], float]] = []
    for start in boundary:
        if start.index in seen:
            continue
        seen.add(start.index)
        stack = [start]
        edges: List[bmesh.types.BMEdge] = []
        perimeter = 0.0
        while stack:
            e = stack.pop()
            edges.append(e)
            perimeter += e.calc_length()
            for v in e.verts:
                for other in adjacency.get(v.index, []):
                    if other.index not in seen:
                        seen.add(other.index)
                        stack.append(other)
        groups.append((edges, perimeter))
    return groups


def boundary_cycle(edges: List[bmesh.types.BMEdge]) -> List[bmesh.types.BMVert]:
    """The boundary component's vertices in order. A proper hole is a closed cycle (every vertex has
    two boundary edges); a TEAR is an open chain whose two ends have one each, and the triangle that
    would close it is simply missing. `bmesh.ops.holes_fill` only handles the first kind, which is why
    food_stall kept three of its five after the first pass — this walks both."""
    adjacency: dict = {}
    for e in edges:
        for v in e.verts:
            adjacency.setdefault(v.index, []).append(e)
    ends = [v for v, es in ((v, adjacency[v.index]) for v in _verts_of(edges)) if len(es) == 1]
    start = ends[0] if ends else edges[0].verts[0]
    order = [start]
    prev: Optional[bmesh.types.BMEdge] = None
    cur = start
    while True:
        options = [e for e in adjacency[cur.index] if e is not prev]
        if not options:
            break
        e = options[0]
        prev = e
        cur = e.other_vert(cur)
        if cur is start:
            break
        order.append(cur)
    return order


def _verts_of(edges: List[bmesh.types.BMEdge]) -> List[bmesh.types.BMVert]:
    out: List[bmesh.types.BMVert] = []
    seen = set()
    for e in edges:
        for v in e.verts:
            if v.index not in seen:
                seen.add(v.index)
                out.append(v)
    return out


def orient(faces: List[bmesh.types.BMFace]) -> int:
    """Turn each new cap face the same way as the faces it is stitched to. A global
    `recalc_face_normals` would rewrite the winding of the whole prop and fight the split normals the
    glTF importer brought in, so this stays local to the patch."""
    flipped = 0
    for f in faces:
        ref = Vector()
        for e in f.edges:
            for g in e.link_faces:
                if g != f:
                    ref += g.normal
        if ref.length > 1e-9 and f.normal.dot(ref) < 0.0:
            f.normal_flip()
            flipped += 1
    return flipped


def fill_holes(obj: bpy.types.Object, cap_m: float) -> Tuple[int, float]:
    """Cap every open-boundary loop no bigger than `cap_m`. Returns (patches added, metres closed).

    The Tripo sources are not watertight: 27 of the 30 carry between 1 and 27 small tears, and the
    food_stall's 0.315 m one is the hole the lead's acceptance pass photographed in its roof. Blender's
    collapse decimator CONSTRAINS boundary edges, so an unfilled tear survives every budget and only
    grows -- ac_cluster's 0.270 m source loop came out of the 16k decimate as a single 1.09 m
    triangle. Filling before the decimate removes the constraint; the second pass afterwards catches
    anything the collapse opened.
    """
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    filled = 0
    closed = 0.0
    faces: List[bmesh.types.BMFace] = []
    for edges, perimeter in boundary_groups(bm):
        if perimeter > cap_m:
            continue
        added = _cap(bm, edges)
        if added:
            faces.extend(added)
            filled += 1
            closed += perimeter
    if faces:
        # The glTF exporter triangulates anyway; doing it here keeps the patch small and lets the
        # winding be checked per triangle instead of per n-gon.
        result = bmesh.ops.triangulate(bm, faces=faces)
        new_faces = result.get("faces", faces)
        orient(new_faces)
        # A fan-triangulated patch over a non-manifold corner leaves zero-area slivers, and the audit
        # counts those. 5 mm is far below anything that reads on a prop.
        patch = {e for f in new_faces for e in f.edges}
        bmesh.ops.dissolve_degenerate(bm, dist=WELD_M * 10.0, edges=list(patch))
    bm.to_mesh(me)
    bm.free()
    me.update()
    return filled, closed


def _cap(bm: bmesh.types.BMesh, edges: List[bmesh.types.BMEdge]) -> List[bmesh.types.BMFace]:
    """Close one boundary component. A simple cycle is one `faces.new`; a component whose vertices
    carry degree 4 or 6 is several holes sharing a corner (food_stall's roof is three of them), and
    only `holes_fill` can separate those. A component of two edges whose ring already exists is a
    one-sided FIN, not a hole -- there is nothing to add, so it is left alone."""
    ring = boundary_cycle(edges)
    if len(ring) >= 3:
        try:
            return [bm.faces.new(ring)]
        except ValueError:
            pass
    return list(bmesh.ops.holes_fill(bm, edges=edges, sides=0).get("faces", []))


def prune_floaters(obj: bpy.types.Object, max_tris: int = 2) -> int:
    """Delete connected components of at most `max_tris` triangles. Returns how many went.

    A Tripo export regularly leaves a stray triangle or quad hanging off a corner. It is invisible in
    a render but it is an ISLAND: all of its edges are boundary edges, so it is a large share of the
    "open edges" column in the audit and it drags the largest-hole number with it. Anything bigger
    than a couple of triangles is left alone -- on a 260k-tri source a real detail can be small.
    """
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    seen = set()
    doomed: List[bmesh.types.BMFace] = []
    for seed in bm.faces:
        if seed.index in seen:
            continue
        shell: List[bmesh.types.BMFace] = []
        stack = [seed]
        seen.add(seed.index)
        while stack:
            f = stack.pop()
            shell.append(f)
            for v in f.verts:
                for g in v.link_faces:
                    if g.index not in seen:
                        seen.add(g.index)
                        stack.append(g)
        if len(shell) <= max_tris:
            doomed.extend(shell)
    if doomed:
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(me)
    bm.free()
    me.update()
    return len(doomed)
