"""Scripted monster clips (monster-assets): the ones Tripo did not deliver.

Everything is keyframed on the *existing* skeleton in bone-local space. Blender bones point along
their local +Y, so for both a spine bone and a leg bone **local X is the main swing axis**:
`rx` swings forward/back, `ry` twists about the bone, `rz` splays sideways. Rotations are given in
degrees as Euler XYZ and written as quaternions, because every Tripo clip drives
`rotation_quaternion` and a pose bone's rotation mode is shared by all its actions.

Curves are shaped, never linear: `interp`/`easing` per key give the anticipation (slow in) and
follow-through (fast out) that reads as weight (FEEL.md, brief "Done when": no mechanical motion).
"""
import math

import bpy
from mathutils import Euler, Quaternion, Vector

#: The rate every clip is baked to, and the scene's frame rate. It has to be Godot's
#: `animation/fps` import default (30), because the engine re-bakes imported animations onto that
#: grid: author anywhere else and the pose the game plays is a resample of the pose the build
#: measured, which is worth up to 0.24 m on the titan's `stagger`.
FPS = 30
#: What the clip tables in `mon_clips*.py` are authored in. They read in 24 fps frames because that
#: is how they were written; `bake_fps` converts them.
AUTHOR_FPS = 24
#: bones that carry the character's root translation in a Tripo clip
ROOT_BONES = ("tripo::Root", "BoneRoot", "Hip", "Root")


def _fcurves(action) -> list:
    try:
        return list(action.fcurves)
    except AttributeError:
        out = []
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    out.extend(bag.fcurves)
        return out


def new_action(arm, clip_id: str):
    """A fresh action wired to `arm` through its own slot (Blender 5 slotted actions)."""
    action = bpy.data.actions.new(clip_id)
    data = arm.animation_data_create()
    data.action = action
    if hasattr(action, "slots"):
        data.action_slot = action.slots.new(id_type="OBJECT", name=arm.name)
    return action


def stash(arm, action, clip_id: str) -> None:
    """Push the action onto a muted NLA track so the glTF exporter picks it up as its own clip."""
    data = arm.animation_data
    track = data.nla_tracks.new()
    track.name = clip_id
    strip = track.strips.new(clip_id, int(action.frame_range[0]), action)
    if hasattr(strip, "action_slot") and hasattr(data, "action_slot") and data.action_slot:
        strip.action_slot = data.action_slot
    track.mute = True
    data.action = None


def build_clip(arm, clip_id: str, keys: list, stash_it: bool = True, signs: dict = None):
    """Key `keys` into a new action.

    A key is `(bone, frame, rot_deg)` with optional `interp`, `easing` and `loc` (metres, bone-local):
      `(bone, frame, (rx, ry, rz))`
      `(bone, frame, (rx, ry, rz), "QUAD", "EASE_IN")`
      `(bone, frame, None, "BEZIER", "AUTO", (0.0, 0.0, 0.4))`   # location only

    `signs` (from `axis_signs`) turns the authored angles into world-intuitive ones: +rx swings the
    bone's tip forward (+Y), +rz splays it right (+X)."""
    action = new_action(arm, clip_id)
    touched = set()
    for key in keys:
        bone_name, frame, rot = key[0], int(key[1]), key[2]
        interp = key[3] if len(key) > 3 else "BEZIER"
        easing = key[4] if len(key) > 4 else "AUTO"
        loc = key[5] if len(key) > 5 else None
        pose = arm.pose.bones.get(bone_name)
        if pose is None:
            raise RuntimeError("%s: no bone '%s'" % (clip_id, bone_name))
        touched.add(bone_name)
        if rot is not None:
            s = (signs or {}).get(bone_name, (1.0, 1.0, 1.0))
            angles = [math.radians(rot[i] * s[i]) for i in range(3)]
            pose.rotation_quaternion = Euler(angles, "XYZ").to_quaternion()
            pose.keyframe_insert("rotation_quaternion", frame=frame)
        if loc is not None:
            # `loc` is authored as a WORLD offset (metres); pose bone locations are bone-local.
            basis = arm.data.bones[bone_name].matrix_local.to_3x3().inverted()
            pose.location = basis @ Vector(loc)
            pose.keyframe_insert("location", frame=frame)
        _shape(action, bone_name, frame, interp, easing)
    for bone_name in touched:
        arm.pose.bones[bone_name].rotation_quaternion = Quaternion()
        arm.pose.bones[bone_name].location = (0.0, 0.0, 0.0)
    if stash_it:
        stash(arm, action, clip_id)
    return action


def lift(action, bone: str, degrees, signs=None) -> int:
    """Compose a constant rotation onto every key a clip already has on `bone`.

    Tripo's juggernaut idle leaves the arms hanging: the knuckle claws sit 2.48 m *below* the toes,
    so the ground lock pins the claws and floats the whole animal 2.5 m above the deck. Raising the
    arm is the fix, but re-authoring a 15 s Tripo clip is not — so the existing keys are kept and a
    constant lift is composed onto them, in the bone's own axes, which preserves the clip's motion.

    Returns how many keys were touched (0 when the clip does not drive that bone)."""
    from mathutils import Euler, Quaternion

    path = 'pose.bones["%s"].rotation_quaternion' % bone
    curves = {fc.array_index: fc for fc in _fcurves(action) if fc.data_path == path}
    if len(curves) != 4:
        return 0
    s = (signs or {}).get(bone, (1.0, 1.0, 1.0))
    delta = Euler([math.radians(degrees[i] * s[i]) for i in range(3)], "XYZ").to_quaternion()
    touched = 0
    for i in range(len(curves[0].keyframe_points)):
        points = [curves[k].keyframe_points[i] for k in range(4)]
        turned = Quaternion([p.co[1] for p in points]) @ delta
        for k, point in enumerate(points):
            point.co[1] = turned[k]
            point.handle_left[1] = turned[k]
            point.handle_right[1] = turned[k]
        touched += 1
    for fc in curves.values():
        fc.update()
    return touched


def bake_fps(actions, fps: int = FPS, author_fps: int = AUTHOR_FPS) -> dict:
    """Resample every action onto an integer `fps` grid, and set the scene to that rate.

    Godot's glTF importer works at `animation/fps` (30, the project default), so a clip on any other
    timebase is *resampled* by the engine and the pose it plays is a linear interpolation between
    30 Hz samples of the curve the build measured — worth 0.24 m of floor error on the titan's
    `stagger`. Baking here puts the authored keys and the engine's keys on the same grid, so the
    measurement the build gates on is the pose the player sees.

    Resampling, not just retiming the existing keys: retiming was measured too (scale every key time
    by 30/24, keep the authored key count, and set `animation/fps=0` so the engine keeps the original
    times) and it is *worse* — the titan's `walk` came out 0.19 m under the deck against 0.14 m for
    the bake, because Godot compresses imported animations regardless of that setting and a sparser
    curve gives its compressor more leverage per key.

    Durations survive to within half a frame. Returns {action name: (frames before, frames after)}."""
    ratio = float(fps) / float(author_fps)
    scene = bpy.context.scene
    scene.render.fps = fps
    scene.render.fps_base = 1.0
    out = {}
    for action in actions:
        start, end = action.frame_range
        new_start, new_end = int(round(start * ratio)), int(round(end * ratio))
        out[action.name] = (int(round(end - start)), new_end - new_start)
        for fc in _fcurves(action):
            samples = [(frame, fc.evaluate(frame / ratio))
                       for frame in range(new_start, new_end + 1)]
            while len(fc.keyframe_points):
                fc.keyframe_points.remove(fc.keyframe_points[0])
            for frame, value in samples:
                fc.keyframe_points.insert(frame, value)
            for kp in fc.keyframe_points:
                # glTF has no Bezier, and Tripo's clips import with CONSTANT keys that the exporter
                # would write as STEP samplers — a staircase instead of a curve. LINEAR is the
                # closest thing to the authored motion that survives the export.
                kp.interpolation = "LINEAR"
            fc.update()
    return out



def axis_signs(arm, mode: str = "forward") -> dict:
    """Per bone, the signs that make the authored angles world-intuitive.

    Blender bones point along local +Y; a positive rotation about local X carries the tip toward
    local +Z, and about local Z toward local −X. Bone roll decides where those land in the world, so
    the sign has to be measured instead of assumed — otherwise a leg swings backwards on half the rig.

    mode "forward": +rx swings the tip toward +Y, +rz splays it toward +X (legs, spine, tail).
    mode "up":      +rx raises the tip toward +Z, +rz sweeps it back toward −Y (wings).
    """
    signs = {}
    for bone in arm.data.bones:
        m = bone.matrix_local
        z, x = m.col[2], m.col[0]
        if mode == "up":
            signs[bone.name] = (1.0 if z.z >= 0.0 else -1.0, 1.0, 1.0 if x.y >= 0.0 else -1.0)
        else:
            signs[bone.name] = (1.0 if z.y >= 0.0 else -1.0, 1.0, -1.0 if x.x >= 0.0 else 1.0)
    return signs


def _shape(action, bone_name: str, frame: int, interp: str, easing: str) -> None:
    """Apply the interpolation of the key we just wrote (Blender defaults to BEZIER/AUTO)."""
    want = 'pose.bones["%s"]' % bone_name
    for fc in _fcurves(action):
        if not fc.data_path.startswith(want):
            continue
        for kp in fc.keyframe_points:
            if abs(kp.co[0] - frame) < 0.01:
                kp.interpolation = interp
                kp.easing = easing


def strip_root_motion(action, bones=ROOT_BONES) -> float:
    """Zero the root translation of a clip so locomotion loops in place (brief: "loops in place").

    Returns how many metres of travel were removed."""
    travel = 0.0
    for fc in _fcurves(action):
        if not fc.data_path.endswith(".location"):
            continue
        if not any('pose.bones["%s"]' % b in fc.data_path for b in bones):
            continue
        pts = fc.keyframe_points
        if len(pts) >= 2:
            travel = max(travel, abs(pts[-1].co[1] - pts[0].co[1]))
        for kp in pts:
            kp.co[1] = 0.0
            kp.handle_left[1] = 0.0
            kp.handle_right[1] = 0.0
        # without this the curve keeps evaluating its cached values and the "stripped" root motion
        # is still there (mon_ground found -0.42 m of it left on the ripper's idle)
        fc.update()
    return travel


def root_travel(action, bones=ROOT_BONES) -> float:
    """Horizontal distance the root bone covers over the clip, in metres (for the foot-slide report)."""
    delta = {}
    for fc in _fcurves(action):
        if not fc.data_path.endswith(".location"):
            continue
        if not any('pose.bones["%s"]' % b in fc.data_path for b in bones):
            continue
        pts = fc.keyframe_points
        if len(pts) >= 2 and fc.array_index in (0, 1):
            delta[fc.array_index] = pts[-1].co[1] - pts[0].co[1]
    return (delta.get(0, 0.0) ** 2 + delta.get(1, 0.0) ** 2) ** 0.5


#: A constant rotation composed onto the arm keys a Tripo clip already has, per (type, clip, bone).
#: The juggernaut's arms hang to the floor in its bind pose and Tripo's `idle` keeps them there: the
#: knuckle claws end up 2.48 m *below* the toes, so the ground lock pins the claws and floats the
#: animal 2.5 m above the deck — the "浮空" the user keeps reporting, invisible to a probe that only
#: reports the lowest point. +45 degrees of shoulder swing puts the claws 2.8 m clear of the feet at
#: every frame of the 15 s idle, measured against the shipped file with
#: `diag_glb_floor.py --support=L_ToeBase,R_ToeBase`. No other clip of any type has a body part
#: hanging below its feet (`mon_ground.round_trip` prints the `CLEARANCE` gap for every clip).
ARM_LIFTS = {
    ("juggernaut", "idle"): {"L_Upperarm": (45.0, 0.0, 0.0), "R_Upperarm": (45.0, 0.0, 0.0)},
}


def apply_lifts(monster: str, arm, clips: dict) -> None:
    """Compose `ARM_LIFTS` onto the clips that carry them, and say so in the log."""
    signs = axis_signs(arm, "up" if monster == "harrier" else "forward")
    for (lift_type, clip_id), bones in ARM_LIFTS.items():
        if lift_type != monster or clip_id not in clips:
            continue
        for bone, degrees in bones.items():
            keys = lift(clips[clip_id], bone, degrees, signs)
            if not keys:
                raise RuntimeError("%s/%s: clip does not drive '%s', so the lift did nothing"
                                   % (monster, clip_id, bone))
            print("LIFT %-11s %-14s %-12s %+.0f deg on %d keys"
                  % (monster, clip_id, bone, degrees[0], keys))
