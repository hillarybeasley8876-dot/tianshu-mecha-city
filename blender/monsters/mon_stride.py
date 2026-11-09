"""Stance-foot stride measurement (monster-assets).

A locomotion clip is authored for one ground speed. Playing it while the actor moves at another
speed makes the planted foot slide at the difference, so the model has to know the speed the clip
was authored for. Root travel is the wrong number: in-place clips (ours, and Tripo's spitter and
harrier) travel nothing, so they would all read 0 m/s.

What actually has to match the body speed is the STANCE FOOT's backward speed relative to the
root: while a foot is planted the ground holds it still, so in root space it moves backwards at
exactly the speed the clip was authored for. Lead review r1 defines the measurement this way:

  * foot bones = the lowest bone of each leg (`mon_types.FOOT_BONES` — see `diag_feet.py` for why
                this cannot be found automatically),
  * stance    = the frames where that foot is within STANCE_M (scaled by height / 16) of its
                lowest point,
  * stride    = how fast the legs cycle, measured against the pelvis.

The last line is where this departs from a literal reading of the review, because a literal reading
does not survive contact with the clips. Tripo's walks are marches in place with a small drift
(`diag_stride.py` prints the raw traces): the mantis's walk root travels 0.71 m/s while its foot
sweeps 6.7 m backwards per 1.17 s cycle, and the foot never holds still at its lowest point — it is
still moving at 8 m/s forwards down there. Taking the mean over the frames near the foot's lowest
point therefore measures the swing, not the stance: it returns -21 m/s for the mantis's run and
-0.2 m/s for the ripper's walk, which is the same class of wrong number as the 0.72 m/s this review
rejected.

What the legs do is unambiguous, and it is what the player reads as speed: over one cycle a contact
foot sweeps backwards past the body by the stride length, and the body covers that stride in the
same cycle. So

    stride_speed = (the foot's forward sweep over the loop, in root space) / loop seconds

which is the mean backward speed of the stance foot, averaged over the whole cycle instead of over
the stance frames only — the same quantity, without needing to find the stance frames of a clip that
does not have clean ones. The pelvis is the reference bone (`mon_types.ROOT_PREFERENCE`) because
that is the bone Tripo drives the travel from, so the clip's own root drift is already inside the
sweep and must not be added again (the review's "+ root travel" would double-count it).

The model's forward axis is +Y in Blender: every type is yawed to face +Y (`mon_types.YAW`), which
is −Z in Godot.
"""
import bpy
import numpy as np

from monsters import mon_types

#: stance band at a 16 m model, scaled by height / 16 (lead r1).
STANCE_M = 0.15
#: a leaf bone counts as a foot if its lowest point over the clip comes within this many stance
#: bands of the ground plane — loose enough for a toe bone sitting on top of an ankle bone.
CONTACT_BANDS = 2.5
#: Frames sampled per clip. `mon_anims.bake_fps` puts every clip on a 30 fps grid, because
#: that is the rate Godot's glTF importer works in (`animation/fps` is 30 project-wide): authoring
#: anywhere else means the engine resamples the clip and the pose it plays is not the pose the build
#: measured.
FPS = 30


def root_bone(arm):
    """The body reference the feet are measured against, or None if the rig has no such bone.

    Tripo drives a walk's travel from the pelvis, not from the technical root bone, so the pelvis is
    what a planted foot moves backwards relative to (`mon_types.ROOT_PREFERENCE`)."""
    for name in mon_types.ROOT_PREFERENCE:
        if name in arm.pose.bones:
            return arm.pose.bones[name]
    return None


def leaf_names(arm) -> list:
    """Bones with no children — the candidates a foot can be."""
    return [b.name for b in arm.data.bones if not b.children]


def sample(arm, action, names: list) -> dict:
    """Armature-space position of each named bone at every frame of `action` (Blender units = m).

    Returns name -> (frames, 3) float array. The action is left stashed exactly as it was found."""
    start, end = int(action.frame_range[0]), int(action.frame_range[1])
    frames = list(range(start, end + 1))
    data = arm.animation_data_create()
    previous = data.action
    data.action = action
    if hasattr(action, "slots") and len(action.slots):
        data.action_slot = action.slots[0]
    out = {n: np.zeros((len(frames), 3), dtype=np.float64) for n in names}
    mw = arm.matrix_world
    for i, frame in enumerate(frames):
        bpy.context.scene.frame_set(frame)
        for name in names:
            p = (mw @ arm.pose.bones[name].matrix).translation
            out[name][i] = (p.x, p.y, p.z)
    data.action = previous
    bpy.context.scene.frame_set(0)
    return out


def foot_bones(samples: dict, ground_z: float, tol: float, height_m: float) -> list:
    """The leaf bones that can be planted: the lowest ones over the clip.

    A foot bone's *head* sits well above the ground plane (an ankle on a 14 m mantis is ~1 m up),
    so proximity to the ground is only a sanity check; what separates feet from claws, tail tips and
    eyes is that they are the lowest thing on the rig. The band is generous — 15 % of the model's
    height — because a foot bone's head is far higher than its contact point."""
    if not samples:
        return []
    lowest = min(float(pts[:, 2].min()) for pts in samples.values())
    band = max(tol * CONTACT_BANDS, 0.15 * height_m)
    near_ground = ground_z + max(tol * CONTACT_BANDS, 0.25 * height_m)
    return sorted(n for n, pts in samples.items()
                  if float(pts[:, 2].min()) <= lowest + band
                  and float(pts[:, 2].min()) <= near_ground)


def measure(arm, action, height_m: float, ground_z: float, feet: tuple,
            grounded: bool = True) -> dict:
    """Stride speed (m/s) of one locomotion clip, plus the evidence behind it.

    `feet` is the type's contact bones; `height_m` / `ground_z` come from the rest-pose mesh bounds,
    so the stance band the cross-check uses scales with the monster. A clip whose rig never touches
    the ground (the harrier flies, and its legs are tucked) reports `contacts = 0` and a stride of
    0: nothing is planted, so nothing can slide and the model plays the clip at 1x."""
    empty = {"stride": 0.0, "feet": [], "contacts": 0, "sweep_m": 0.0, "cycle_s": 0.0,
             "stance_frac": 0.0, "stance_speed": 0.0, "root": 0.0, "airborne": not grounded}
    tol = STANCE_M * max(height_m, 1e-6) / 16.0
    named = [n for n in feet if n in arm.pose.bones]
    missing = [n for n in feet if n not in arm.pose.bones]
    if missing:
        print("STRIDE WARN: %s names contact bones this rig does not have: %s"
              % (action.name, ", ".join(missing)))
    root_pose = root_bone(arm)
    if not named or not grounded or root_pose is None:
        return empty
    pts = sample(arm, action, sorted(set(named + [root_pose.name] + leaf_names(arm))))
    root = pts.pop(root_pose.name)
    frames, seconds = len(root), len(root) / float(FPS)
    travel = float(np.hypot(*(root[-1] - root[0])[:2])) / seconds
    sweeps, stance, stance_speeds = [], 0, []
    for name in named:
        rel = pts[name] - root                      # root space: the pelvis is the reference
        step = rel[(np.arange(frames) + 1) % frames, 1] - rel[:, 1]   # wraps: a loop has no end
        sweeps.append(float(step[step > 0.0].sum()))
        low = rel[:, 2] <= float(rel[:, 2].min()) + tol
        stance += int(low.sum())
        stance_speeds.extend((-step[low] * FPS).tolist())
    # cross-check: nothing outside the table may reach the ground, or the table is out of date
    highest_foot = max(float(pts[n][:, 2].min()) for n in named)
    strays = sorted(n for n in foot_bones(pts, ground_z, tol, height_m) if n not in named)
    below = [n for n in strays if float(pts[n][:, 2].min()) < highest_foot]
    if below:
        print("STRIDE WARN: %s/%s — %s reach the ground below the contact bones in "
              "mon_types.FOOT_BONES" % (action.name, "/".join(below), "these bones"))
    stride = float(np.median(sweeps)) / seconds
    return {
        "stride": round(stride, 3), "feet": sorted(named), "contacts": len(named),
        "sweep_m": round(float(np.median(sweeps)), 3), "cycle_s": round(seconds, 3),
        "stance_frac": round(stance / float(frames * len(named)), 3),
        "stance_speed": round(float(np.mean(stance_speeds)), 3) if stance_speeds else 0.0,
        "root": round(travel, 3), "airborne": False, "strays": strays,
    }
