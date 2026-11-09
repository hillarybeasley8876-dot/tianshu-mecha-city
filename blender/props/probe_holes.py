"""Report the open-boundary loops of a prop mesh, on the Tripo SOURCE or on a shipped glb.

  tools/blender.sh run blender/props/probe_holes.py -- --name ac_cluster [--shipped]

Prints every boundary loop with its perimeter, its centre and the number of edges, biggest first, so
a hole can be located in the clay sheet. `process_prop.py` preserves boundary edges through the
decimate (Blender's collapse decimator constrains them), which is why a loop in the Tripo source
survives every budget -- see status/city-kit.md r10.
"""
import os
import sys
from typing import List, Tuple

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

from lib import common  # noqa: E402
from mesh_repair import WELD_M, boundary_groups  # noqa: E402
from process_prop import args, script_args, weld  # noqa: E402
from prop_table import prop  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")


def loops(obj: bpy.types.Object) -> List[Tuple[float, int, Tuple[float, float, float]]]:
    """Every open-boundary component as (perimeter, edge count, centre), biggest first. Shares
    `mesh_repair.boundary_groups` with the pipeline that fills them, so the two can never disagree
    about what a hole is."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    out: List[Tuple[float, int, Tuple[float, float, float]]] = []
    for edges, perimeter in boundary_groups(bm):
        centre = Vector()
        for e in edges:
            centre += e.verts[0].co + e.verts[1].co
        out.append((perimeter, len(edges), tuple(centre / float(2 * len(edges)))))
    bm.free()
    out.sort(reverse=True)
    return out


def main() -> None:
    a = args(script_args())
    if a.get("all"):
        base = os.path.join(ROOT, "art", "tripo")
        for name in sorted(d[5:] for d in os.listdir(base) if d.startswith("prop_")):
            report(name, bool(a.get("shipped")), summary=True)
        return
    report(a.get("name", "ac_cluster"), bool(a.get("shipped")))


def report(name: str, shipped: bool, summary: bool = False) -> None:
    if shipped:
        path = os.path.join(ROOT, "game", "world", "props", "meshes", name + ".glb")
    else:
        path = os.path.join(ROOT, "art", "tripo", "prop_" + name, "model.glb")
    if not os.path.exists(path):
        print("HOLES FAIL %s (no %s)" % (name, path))
        return
    common.reset()
    bpy.ops.import_scene.gltf(filepath=path, merge_vertices=True)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    obj = common.join(meshes, name) if len(meshes) > 1 else meshes[0]
    if not shipped:
        from process_prop import normalise
        normalise(obj, prop(name).size_m)
    # The glTF importer only merges EXACT duplicates, so a raw read of either file reports every UV
    # and normal seam as an open boundary. `process_prop.weld()` is what merges by POSITION, and it is
    # the topology after that weld which ships and which `probe_props.gd` measures.
    weld(obj, WELD_M)
    found = loops(obj)
    where = "shipped" if shipped else "source"
    print("HOLES %s %s loops=%d tris=%d max=%.3f m" % (name, where, len(found),
                                                       common.tri_count(obj),
                                                       found[0][0] if found else 0.0))
    if summary:
        return
    for perimeter, edges, centre in found[:24]:
        print("HOLES   perim %7.3f m edges %5d at (%.2f, %.2f, %.2f)"
              % (perimeter, edges, centre[0], centre[1], centre[2]))


if __name__ == "__main__":
    main()
