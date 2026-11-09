"""Pose the exported hero3 rig and render the stress poses (hero-v3 gate evidence).

    tools/blender.sh run blender/hero3/pose_check.py -- --pose=stress_knees

Imports game/player/model/hero3/hero3.glb, applies one named pose to the armature and writes a GLB
that `tools/blender.sh preview` can shoot. The poses are the brief's stress set: they are where rigid
plates interpenetrate if the cuts or the joint mechanisms are wrong.

Poses are stored as data (bone -> euler degrees in bone space) so the same table can drive the
Blender check and, later, the Godot capture harness.
"""
import argparse
import math
import os
import sys

import bpy
from mathutils import Euler

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/hero3"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
import hero3_lib as H  # noqa: E402
from lib import common  # noqa: E402

SRC = "game/player/model/hero3/hero3.glb"

## bone -> (rx, ry, rz) degrees. Blender bone space: +Y runs along the bone, so a positive X
## rotation swings the limb forward and a Z rotation swings it outward.
POSES = {
    "rest": {},
    "stress_knees": {"R_Thigh": (-55, 0, 0), "L_Thigh": (-55, 0, 0), "R_Calf": (95, 0, 0),
                     "L_Calf": (95, 0, 0), "R_Foot": (-40, 0, 0), "L_Foot": (-40, 0, 0),
                     "Pelvis": (0, 0, 0)},
    "stress_arms": {"R_Upperarm": (-150, 0, -25), "L_Upperarm": (-150, 0, 25),
                    "R_Forearm": (-35, 0, 0), "L_Forearm": (-35, 0, 0),
                    "Spine02": (-12, 0, 0)},
    "stress_twist": {"Spine01": (0, 0, 32), "Spine02": (0, 0, 22), "Head": (0, 0, -40),
                     "R_Upperarm": (-60, 0, -30), "L_Upperarm": (-25, 0, 15),
                     "R_Forearm": (-70, 0, 0), "L_Forearm": (-45, 0, 0)},
    "stress_lunge": {"R_Thigh": (-70, 0, 0), "R_Calf": (80, 0, 0), "R_Foot": (-25, 0, 0),
                     "L_Thigh": (35, 0, 0), "L_Calf": (25, 0, 0), "L_Foot": (-20, 0, 0),
                     "R_Upperarm": (-95, 0, -20), "R_Forearm": (-30, 0, 0),
                     "L_Upperarm": (30, 0, 20), "Spine01": (-14, 0, -8)},
}


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--pose", default="stress_knees", choices=sorted(POSES))
    p.add_argument("--src", default=SRC)
    return p.parse_args(argv)


def apply_pose(arm, pose: dict) -> None:
    for bone in arm.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = Euler((0.0, 0.0, 0.0))
    for name, (rx, ry, rz) in pose.items():
        bone = arm.pose.bones.get(name)
        if bone is None:
            print("POSE warning: no bone %s" % name)
            continue
        bone.rotation_euler = Euler((math.radians(rx), math.radians(ry), math.radians(rz)))
    bpy.context.view_layer.update()


def main() -> None:
    args = parse_args()
    common.reset()
    objs = H.load_glb(args.src)
    arm = next((o for o in objs if o.type == "ARMATURE"), None)
    if arm is None:
        raise RuntimeError("pose: %s has no armature" % args.src)
    meshes = [o for o in objs if o.type == "MESH"]
    apply_pose(arm, POSES[args.pose])
    # the pose has to be baked into the meshes for a preview render: the preview tool imports a GLB
    # with no armature, so export the deformed result instead
    for obj in meshes:
        bpy.context.view_layer.objects.active = obj
        for mod in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    out = os.path.join(H.TMP, "pose_%s.glb" % args.pose)
    H.export_glb(out, meshes, animations=False)
    print("POSE %s: %d bones posed, wrote %s" % (args.pose, len(POSES[args.pose]), out))


if __name__ == "__main__":
    main()
