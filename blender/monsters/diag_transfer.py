"""Isolate where the ripper's skin weights go wrong (monster-assets).

    tools/blender.sh run blender/monsters/diag_transfer.py -- --type=ripper

Runs the same stages as the build (load, decimate, align, Data Transfer, place) and prints the
"distance from a vertex to the bone that dominates it" metric after each one, so the stage that
breaks the weights is unambiguous.
"""
import argparse
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

from monsters import mon_build, mon_lib, mon_rig, mon_types  # noqa: E402


def weight_metric(label: str, mesh, arm) -> None:
    """Median / p95 / max distance from each vertex to its dominant bone's head, in model units."""
    heads = {b.name: np.array(arm.matrix_world @ b.head_local) for b in arm.data.bones}
    groups = [g.name for g in mesh.vertex_groups]
    co = np.array([list(v.co) for v in mesh.data.vertices])
    mw = np.array(mesh.matrix_world)
    dist = []
    for v in mesh.data.vertices:
        best, name = 0.0, None
        for g in v.groups:
            if g.weight > best:
                best, name = g.weight, groups[g.group]
        if name is None:
            continue
        world = mw[:3, :3] @ co[v.index] + mw[:3, 3]
        dist.append(float(np.linalg.norm(world - heads[name])))
    d = np.array(dist) if dist else np.zeros(1)
    print("METRIC %-22s verts %6d  median %.3f  p95 %.3f  max %.3f"
          % (label, len(d), float(np.median(d)), float(np.percentile(d, 95)), float(d.max())))


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--type", default="ripper")
    p.add_argument("--tris", type=int, default=0)
    args = p.parse_args(argv)
    monster = args.type
    common.reset()
    rigged = mon_lib.load_glb(mon_lib.tripo_path(monster, "rigged.glb"))
    arm = mon_lib.only_armature(rigged, monster)
    remesh = mon_lib.only_mesh(rigged, monster)
    remesh.modifiers.clear()
    mon_rig.bind_mesh(remesh, arm)
    weight_metric("remesh (source)", remesh, arm)

    hi_objs = mon_lib.load_glb(mon_lib.tripo_path(monster, "model.glb"))
    hi = mon_lib.only_mesh(hi_objs, monster)
    hi.name = "Body"
    target = args.tris or mon_types.TRIS[monster][0]
    print("DECIMATE %d -> %d tris" % (mon_lib.tri_count(hi), mon_lib.decimate(hi, target)))
    matrix, rms, scale = mon_build.align_highres(hi, remesh)
    print("ALIGN rms %.5f  (icp scale %.4f)" % (rms, scale))
    mon_lib.transform_mesh(hi, matrix)
    lo_a, hi_a = mon_lib.mesh_bounds(hi)
    lo_b, hi_b = mon_lib.mesh_bounds(remesh)
    print("BOUNDS hires %s .. %s" % (tuple(round(c, 3) for c in lo_a),
                                     tuple(round(c, 3) for c in hi_a)))
    print("BOUNDS remesh %s .. %s" % (tuple(round(c, 3) for c in lo_b),
                                      tuple(round(c, 3) for c in hi_b)))
    groups = mon_lib.transfer_weights(remesh, hi)
    print("TRANSFER %d groups" % groups)
    mon_rig.bind_mesh(hi, arm)
    weight_metric("hires after transfer", hi, arm)
    mon_build.place(hi, arm, mon_types.YAW[monster], mon_types.SIZES[monster])
    weight_metric("hires after place", hi, arm)


main()
