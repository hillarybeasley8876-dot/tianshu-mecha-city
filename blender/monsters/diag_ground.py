"""What the ground lock actually wrote, and on which bone (monster-assets, lead r5 item 3).

    tools/blender.sh run blender/monsters/diag_ground.py -- --type=ripper

`probe_floor` and the build disagreed on the ripper's `idle` by 0.86 m while agreeing on its walk,
run and scuttle, so this prints, per clip, every location track the exported GLB carries: which bone,
how many keys, and the value range."""
import argparse
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

from monsters import mon_anims, mon_ground, mon_lib  # noqa: E402


def _posed_z(mesh, arm, action, frame: int):
    """World z of every vertex with `action` evaluated at `frame`."""
    from monsters import mon_skin
    bidx, wts, rest = mon_skin._skin_tables(mesh, arm)
    sub_c = np.concatenate([rest, np.ones((len(rest), 1))], axis=1)
    data = arm.animation_data_create()
    data.action = action
    if hasattr(action, "slots") and len(action.slots):
        data.action_slot = action.slots[0]
    bpy.context.scene.frame_set(frame)
    skin = mon_skin._skin_matrices(arm)
    posed = np.einsum("mkij,mj->mki", skin[bidx], sub_c)[:, :, :3]
    pos = (posed * wts[:, :, None]).sum(axis=1)
    mw = np.array(arm.matrix_world)
    data.action = None
    bpy.context.scene.frame_set(0)
    return mw[2, :3] @ pos.T + mw[2, 3]


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--type", default="ripper")
    args = p.parse_args(argv)
    common.reset()
    path = os.path.join(mon_lib.OUT_DIR, args.type, "%s.glb" % args.type)
    mon_lib.load_glb(path)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    print("GROUND %s root bone '%s' (mon_anims wants one of %s)"
          % (args.type, mon_ground.root_bone(arm), ", ".join(mon_anims.ROOT_BONES)))
    tops = [b.name for b in arm.data.bones if b.parent is None]
    print("GROUND %s parentless bones: %s" % (args.type, tops))
    lo, hi = mon_lib.mesh_bounds(mesh)
    print("GROUND %s rest mesh bounds z %.3f .. %.3f | meshes %s | armatures %s"
          % (args.type, lo.z, hi.z,
             [(o.name, len(o.data.vertices)) for o in bpy.data.objects if o.type == "MESH"],
             [o.name for o in bpy.data.objects if o.type == "ARMATURE"]))
    for action in sorted(bpy.data.actions, key=lambda a: a.name):
        rows = []
        for fc in mon_anims._fcurves(action):
            if not fc.data_path.endswith(".location"):
                continue
            bone = fc.data_path.split('"')[1] if '"' in fc.data_path else "?"
            values = [kp.co[1] for kp in fc.keyframe_points]
            rows.append("%s[%d] %d keys %+.3f..%+.3f"
                        % (bone, fc.array_index, len(values), min(values), max(values)))
        print("GROUND %-11s %-14s %s" % (args.type, action.name,
                                        "  ".join(rows) if rows else "(no location tracks)"))
    # the round trip: what the exported GLB's own animation does to the exported mesh
    verts = mon_ground.floor_vertices(mesh, arm)
    for name in ("idle", "walk", "run", "charge_run", "scuttle"):
        action = bpy.data.actions.get(name)
        if action is None:
            continue
        frames, lowest = mon_ground.lowest_per_frame(mesh, arm, action, verts)
        print("GROUND %-11s %-14s %d samples, scene fps %d, frame_range %s"
              % (args.type, name, len(frames), bpy.context.scene.render.fps,
                 tuple(round(c, 2) for c in action.frame_range)))
        root = arm.pose.bones[mon_ground.root_bone(arm)]
        rest = arm.data.bones[root.name].head_local
        data = arm.animation_data_create()
        data.action = action
        if hasattr(action, "slots") and len(action.slots):
            data.action_slot = action.slots[0]
        bpy.context.scene.frame_set(int(frames[0]))
        posed = (arm.matrix_world @ root.matrix).translation
        bpy.context.scene.frame_set(int(frames[len(frames) // 2]))
        mid = (arm.matrix_world @ root.matrix).translation
        data.action = None
        bpy.context.scene.frame_set(0)
        low_v = int(np.argmin(_posed_z(mesh, arm, action, int(frames[0]))))
        owner = sorted(((float(g.weight), mesh.vertex_groups[g.group].name)
                        for g in mesh.data.vertices[low_v].groups), reverse=True)[:3]
        print("GROUND %-11s %-14s lowest vert %d driven by %s"
              % (args.type, name, low_v, " + ".join("%s %.2f" % (n, w) for w, n in owner)))
        print("GROUND %-11s %-14s round trip lowest %+.3f..%+.3f m | root rest z %+.3f"
              " posed z %+.3f / %+.3f | mesh mw %s arm mw %s"
              % (args.type, name, lowest.min(), lowest.max(),
                 (arm.matrix_world @ rest).z, posed.z, mid.z,
                 tuple(round(c, 3) for c in mesh.matrix_world.translation),
                 tuple(round(c, 3) for c in arm.matrix_world.translation)))


main()
