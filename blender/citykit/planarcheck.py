"""Isolated check of planar.flatten(): does it MOVE vertices, and does the result read as flat?

    tools/blender.sh run blender/citykit/planarcheck.py -- --id t01

The lead's r4 reproduction, in Blender: build a 30 x 30 m grid with +/- 5 cm of noise, triangulate
it, run the pass, and print the RMS height before and after plus the largest vertex move. The r4 bug
was that the stats said "flattened" and the surface was unchanged.
"""
from __future__ import annotations

import math
import os
import random
import sys

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/citykit"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/tools/citykit"))

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import planar  # noqa: E402
from lib import common  # noqa: E402


def grid(name: str, n: int = 30, noise: float = 0.05, tris: bool = True):
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=n, y_subdivisions=n, size=30.0)
    ob = bpy.context.active_object
    ob.name = name
    rng = random.Random(7)
    for v in ob.data.vertices:
        v.co.z += rng.uniform(-noise, noise)
    if tris:
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bm.to_mesh(ob.data)
        bm.free()
    return ob


def zrms(ob) -> float:
    z = [v.co.z for v in ob.data.vertices]
    m = sum(z) / len(z)
    return math.sqrt(sum((v - m) ** 2 for v in z) / len(z))


def run(name: str, ob) -> None:
    before = [v.co.copy() for v in ob.data.vertices]
    r0 = zrms(ob)
    stats = planar.flatten(ob)
    moves = [(v.co - b).length for v, b in zip(ob.data.vertices, before)]
    moved = max(moves)
    big = sum(1 for m in moves if m > 0.5)
    print("PLANARCHECK %-12s planar %.1f%% regions %d rejected %d | z rms %.4f -> %.4f | "
          "max vertex move %.5f m | verts moved %d | moves>0.5m %d"
          % (name, stats["planar_pct"], stats["regions"], stats["regions_rejected"], r0, zrms(ob),
             moved, stats["verts_moved"], big))


def main() -> None:
    common.reset()
    run("grid_tris", grid("g1", tris=True))
    run("grid_quads", grid("g2", tris=False))
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ids = "t01"
    for i, a in enumerate(argv):
        if a == "--id" and i + 1 < len(argv):
            ids = argv[i + 1]
        elif a.startswith("--id="):
            ids = a.split("=", 1)[1]
    if ids and ids != "none":
        import process
        import tripo_import
        from assets import BY_ID
        for aid in ids.split(","):
            a = BY_ID[aid]
            common.reset()
            src = os.path.expanduser("~/m/mecha-city/art/tripo/kit_%s/model.glb" % aid)
            tripo_import.import_glb(src)
            process.drop_bone_shapes()
            meshes = [o for o in bpy.data.objects if o.type == "MESH"]
            obj = common.join(meshes, aid) if len(meshes) > 1 else meshes[0]
            process.fix_up(obj, a)
            process.fit_native(obj, a.native_h)
            process.decimate(obj, a.tris * 3)
            import clean
            obj, _k, _d = clean.clean(obj, common.join)
            process.fit_native(obj, a.native_h)
            before = [v.co.copy() for v in obj.data.vertices]
            stats = planar.flatten(obj)
            moved = max((v.co - b).length for v, b in zip(obj.data.vertices, before))
            print("PLANARCHECK %-12s planar %.1f%% regions %d rejected %d skipped %d | "
                  "max vertex move %.4f m | verts moved %d of %d"
                  % (aid, stats["planar_pct"], stats["regions"], stats["regions_rejected"],
                     stats.get("verts_skipped", 0), moved, stats["verts_moved"],
                     len(obj.data.vertices)))
            out = os.path.expanduser("~/m/mecha-city/tmp/city-kit")
            os.makedirs(out, exist_ok=True)
            from lib import export
            export.export_glb(os.path.join(out, "pc_%s_flat1.glb" % aid), objects=[obj],
                              jpeg_quality=60)
            s2 = planar.flatten(obj)
            print("PLANARCHECK %-12s pass 2: planar %.1f%% regions %d"
                  % (aid, s2["planar_pct"], s2["regions"]))
            export.export_glb(os.path.join(out, "pc_%s_flat2.glb" % aid), objects=[obj],
                              jpeg_quality=60)
            process.decimate(obj, a.tris)
            export.export_glb(os.path.join(out, "pc_%s_dec.glb" % aid), objects=[obj],
                              jpeg_quality=60)
            s3 = planar.flatten(obj)
            print("PLANARCHECK %-12s post-decimate pass: planar %.1f%% regions %d (%d tris)"
                  % (aid, s3["planar_pct"], s3["regions"], common.tri_count(obj)))
            export.export_glb(os.path.join(out, "pc_%s_decflat.glb" % aid), objects=[obj],
                              jpeg_quality=60)


if __name__ == "__main__":
    main()
