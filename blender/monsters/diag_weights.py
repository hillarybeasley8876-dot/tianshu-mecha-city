"""Diagnose skin weights on a built monster GLB (monster-assets).

    tools/blender.sh run blender/monsters/diag_weights.py -- --type=ripper --clip=walk

Reports, for the rest pose and the clip's worst frame: the weight-sum distribution, how far each
vertex sits from the bone that dominates it, and which vertices move the most. A vertex whose
dominant bone is far away, or whose weights do not sum to 1, is what tears a skinned mesh apart.
"""
import argparse
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

from monsters import mon_lib  # noqa: E402


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--type", required=True)
    p.add_argument("--file", default="")
    p.add_argument("--clip", default="walk")
    args = p.parse_args(argv)
    common.reset()
    path = args.file or os.path.join(mon_lib.OUT_DIR, args.type, "%s.glb" % args.type)
    bpy.ops.import_scene.gltf(filepath=path)
    for obj in list(bpy.data.objects):
        if obj.type == "MESH" and not obj.data.materials:
            bpy.data.objects.remove(obj, do_unlink=True)
    body = next(o for o in bpy.data.objects if o.type == "MESH" and o.data.materials)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    groups = [g.name for g in body.vertex_groups]
    index = {name: i for i, name in enumerate(groups)}
    n = len(body.data.vertices)
    sums = np.zeros(n)
    dominant = np.full(n, -1)
    best = np.zeros(n)
    dist = np.zeros(n)
    heads = {b.name: np.array(arm.matrix_world @ b.head_local) for b in arm.data.bones}
    co = np.array([list(v.co) for v in body.data.vertices])
    for v in body.data.vertices:
        for g in v.groups:
            sums[v.index] += g.weight
            if g.weight > best[v.index]:
                best[v.index], dominant[v.index] = g.weight, g.group
    for i in range(n):
        if dominant[i] >= 0:
            dist[i] = np.linalg.norm(co[i] - heads[groups[dominant[i]]])
    print("WEIGHTS %s groups %d verts %d" % (args.type, len(groups), n))
    print("  weight sum: min %.3f  median %.3f  max %.3f  |  unweighted %d  |  >1.02 %d"
          % (sums.min(), float(np.median(sums)), sums.max(), int((sums < 1e-4).sum()),
             int((sums > 1.02).sum())))
    print("  dist to dominant bone head: median %.3f  p95 %.3f  max %.3f"
          % (float(np.median(dist)), float(np.percentile(dist, 95)), dist.max()))
    far = np.argsort(-dist)[:8]
    print("  farthest: " + ", ".join("%s@%.2fm" % (groups[dominant[i]], dist[i]) for i in far))

    action = bpy.data.actions.get(args.clip)
    if action is None:
        return
    arm.animation_data_create().action = action
    if hasattr(action, "slots") and len(action.slots):
        arm.animation_data.action_slot = action.slots[0]
    rest = co.copy()
    worst = None
    for f in range(int(action.frame_range[0]), int(action.frame_range[1]) + 1, 2):
        bpy.context.scene.frame_set(f)
        deps = bpy.context.evaluated_depsgraph_get()
        ev = body.evaluated_get(deps).to_mesh()
        moved = np.array([list(v.co) for v in ev.vertices])
        body.evaluated_get(deps).to_mesh_clear()
        d = np.linalg.norm(moved - rest, axis=1)
        if worst is None or d.max() > worst[1]:
            worst = (f, float(d.max()), d)
    frame, peak, d = worst
    print("  clip %s worst frame %d: max vertex move %.2f m, p99 %.2f m, moved>1m %d"
          % (args.clip, frame, peak, float(np.percentile(d, 99)), int((d > 1.0).sum())))
    top = np.argsort(-d)[:10]
    print("  movers: " + ", ".join("%s(%.2fm,w=%.2f,sum=%.2f)"
                                   % (groups[dominant[i]] if dominant[i] >= 0 else "-", d[i],
                                      best[i], sums[i]) for i in top))


main()
