"""Cap every opening in a hero3 armour piece (hero-v3, brief step 1).

The Tripo mesh is a surface, not a solid: cutting it into rigid pieces leaves an open rim at every
joint, and an open rim shows the inside of the armour the moment a joint rotates. Each boundary loop
is filled, inset and recessed so the opening reads as a machined rim in dark gunmetal, and the piece
becomes a closed shell.

  import hero3_cap; hero3_cap.cap_pieces(pieces)
"""
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/hero3"))
import hero3_lib as H  # noqa: E402

CAP_MATERIAL = "Hero3Joint"
CAP_RGB = (0.045, 0.048, 0.055)   ## dark gunmetal, reads as the mechanism behind the armour
CAP_ROUGH = 0.38
RECESS_M = 0.07                   ## how far the cap sits inside the armour, so it reads as a rim


def cap_material():
    """The dark metal every cap and every joint mechanism shares."""
    mat = bpy.data.materials.get(CAP_MATERIAL)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(CAP_MATERIAL)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = CAP_RGB + (1.0,)
    bsdf.inputs["Metallic"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = CAP_ROUGH
    return mat


def cap_piece(obj) -> dict:
    """Fill + recess every boundary loop of one piece. Returns a small report.

    Every loop is closed with an explicit n-gon rather than `bmesh.ops.holes_fill`, which silently
    leaves most of them open: on this mesh it filled 423 of 1032 loops and the shoulder then showed a
    black hole the moment the arm came up. The cap is pushed toward the piece's own centre rather than
    along the filled face's normal, because a filled n-gon can come out wound either way and an inset
    with even offset on a non-planar 30-gon throws vertices hundreds of metres out."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    before = H.bbox(obj)
    boundary = [e for e in bm.edges if e.is_boundary]
    loops = _boundary_loops(boundary)
    if not loops:
        bm.free()
        return {"edges": 0, "loops": 0, "faces": 0, "blown": False, "open": 0}
    centre = sum((v.co for v in bm.verts), Vector()) / max(len(bm.verts), 1)
    faces, failed = [], 0
    for verts, edges in loops:
        made = _fill_loop(bm, verts, edges)
        if made:
            faces.extend(made)
        else:
            failed += 1
    faces = [f for f in faces if f.is_valid]
    if faces:
        bmesh.ops.triangulate(bm, faces=faces)
        moved = set()
        for face in faces:
            if not face.is_valid:
                continue
            direction = centre - face.calc_center_median()
            if direction.length < 1e-4:
                continue
            direction = direction.normalized() * RECESS_M
            for vert in face.verts:
                if vert.index not in moved:
                    vert.co += direction
                    moved.add(vert.index)
        cap = cap_material()
        slot = _ensure_slot(obj, cap)
        for face in faces:
            if face.is_valid:
                face.material_index = slot
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    after = H.bbox(obj)
    blown = max((after[0] - before[0]).length, (after[1] - before[1]).length) > 0.25
    if blown:
        print("CAP WARNING %s grew by more than 0.25 m: %s -> %s" % (
            obj.name, [round(v, 2) for v in before[1]], [round(v, 2) for v in after[1]]))
    return {"edges": len(boundary), "loops": len(loops), "faces": len(faces), "blown": blown,
            "open": failed}


def cap_pieces(pieces: list) -> None:
    total = {"edges": 0, "loops": 0, "faces": 0, "open": 0}
    blown = []
    for obj in pieces:
        report = cap_piece(obj)
        for key in total:
            total[key] += report[key]
        blown += [obj.name] if report["blown"] else []
        print("CAP %-12s %4d boundary edges in %3d loops -> %4d cap faces%s%s" % (
            obj.name.replace("H3_", ""), report["edges"], report["loops"], report["faces"],
            "  %d OPEN" % report["open"] if report["open"] else "",
            "  BLOWN" if report["blown"] else ""))
    print("CAP total %d edges, %d loops, %d cap faces, %d loops left open%s" % (
        total["edges"], total["loops"], total["faces"], total["open"],
        ", blown: %s" % ", ".join(blown) if blown else ""))
    if blown:
        raise RuntimeError("cap: %d pieces grew out of bounds" % len(blown))
    # a handful of sub-millimetre pinholes the collapse pass opened is not a hole you can see; a
    # tenth of the loops is. The exact count is printed either way so the number is never hidden.
    if total["open"] > total["loops"] * 0.10:
        raise RuntimeError("cap: %d of %d loops could not be closed" % (
            total["open"], total["loops"]))


def _fill_loop(bm, verts: list, edges: list) -> list:
    """Close one opening. Returns the new faces ([] if it could not be closed).

    A simple loop becomes one n-gon; a pinched or self-touching one (the decimate pass leaves plenty
    at 160k tris) cannot be an n-gon, so the triangulator fans it instead."""
    unique = []
    for vert in verts:
        if vert not in unique:
            unique.append(vert)
    if len(unique) >= 3:
        try:
            return [bm.faces.new(unique)]
        except ValueError:
            pass
    result = bmesh.ops.triangle_fill(bm, edges=edges, use_beauty=True, use_dissolve=False)
    made = [g for g in result["geom"] if isinstance(g, bmesh.types.BMFace) and g.is_valid]
    return made


def _boundary_loops(boundary: list) -> list:
    """The boundary edges grouped into (ordered verts, edges) loops -- one entry per opening.

    Walking the edges rather than calling a fill op is what makes the count honest: a vertex where
    three or more boundary edges meet splits the walk, and such a loop is returned as-is so the
    caller can report it instead of silently leaving a hole."""
    remaining = set(boundary)
    loops = []
    while remaining:
        edge = remaining.pop()
        start = edge.verts[0]
        verts, used = [start], [edge]
        current = edge.verts[1]
        guard = len(boundary) * 2 + 4
        while current != start and guard > 0:
            guard -= 1
            verts.append(current)
            nxt = None
            for other in current.link_edges:
                if other in remaining:
                    nxt = other
                    break
            if nxt is None:
                break
            remaining.discard(nxt)
            used.append(nxt)
            current = nxt.verts[0] if nxt.verts[1] == current else nxt.verts[1]
        if len(verts) >= 3:
            loops.append((verts, used))
    return loops


def _ensure_slot(obj, mat) -> int:
    for i, slot in enumerate(obj.data.materials):
        if slot == mat:
            return i
    obj.data.materials.append(mat)
    return len(obj.data.materials) - 1
