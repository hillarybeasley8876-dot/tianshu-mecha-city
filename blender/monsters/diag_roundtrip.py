"""Why Blender's round-trip and the shipped .glb disagree about a clip's floor (lead r6).

`mon_ground.round_trip` re-imports the exported GLB and measures it in Blender; `probe_floor` and
`diag_glb_floor` measure the same file the way Godot reads it. For the juggernaut's `charge_run`
those differ by 0.6 m. This prints everything the two could differ on, for one clip:

  * which mesh object the round-trip picks (the GLB carries LOD0 *and* LOD1),
  * how many vertex groups survive the import and how many map onto a bone,
  * how many vertices end up with no influence at all (`_skin_tables` renormalises, so an unmatched
    group silently contributes the armature origin — a very convincing 0.0 m),
  * which bones the imported action really drives,
  * the per-frame lowest point and the bone that carries it.

    tools/blender.sh run blender/monsters/diag_roundtrip.py -- --type=juggernaut --clip=charge_run
"""
import argparse
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

from monsters import mon_ground, mon_lib, mon_skin  # noqa: E402


def _influences(mesh, arm) -> tuple:
    """(vertices with no influence, vertices whose heaviest group is not a bone)."""
    bidx, wts, _rest = mon_skin._skin_tables(mesh, arm)
    return int((wts.sum(axis=1) <= 1e-9).sum()), int((bidx[:, 0] < 0).sum())


def _animated_bones(arm, action) -> list:
    paths = {fc.data_path for fc in mon_ground._fcurves(action)}
    out = []
    for bone in arm.data.bones:
        if 'pose.bones["%s"]' % bone.name in paths:
            out.append(bone.name)
    return out


def _action_inventory() -> None:
    """Every imported action, with both fcurve APIs and its slots.

    Blender 4.4 moved fcurves into `action.layers[].strips[].channelbags[slot]`. `action.fcurves`
    still exists but only reports the *legacy* view, so a helper that tries it first and only falls
    back on `AttributeError` silently sees an empty action — and an action that evaluates as empty
    leaves the rig in its rest pose, which sits at 0.0 m and passes any floor gate."""
    for action in sorted(bpy.data.actions, key=lambda a: a.name):
        try:
            legacy = len(action.fcurves)
        except AttributeError:
            legacy = -1
        bagged = 0
        bags = []
        for layer in getattr(action, "layers", []):
            for strip in layer.strips:
                for bag in strip.channelbags:
                    bagged += len(bag.fcurves)
                    bags.append("%s:%d" % (getattr(bag, "slot_identifier", "?"),
                                           len(bag.fcurves)))
        slots = [getattr(s, "identifier", "?") for s in getattr(action, "slots", [])]
        print("ACTION %-18s users %d slots %s bags %s | action.fcurves %d | channelbags %d"
              % (action.name, action.users, slots, bags, legacy, bagged))


def _drives_armature(arm, action) -> str:
    """Does assigning `action` to `arm` really move the rig? Pose the armature and report the
    largest bone movement over the clip — a rest-pose measurement reports ~0."""
    data = arm.animation_data_create()
    previous = data.action
    data.action = action
    if hasattr(action, "slots") and len(action.slots):
        try:
            data.action_slot = action.slots[0]
        except (TypeError, RuntimeError) as exc:
            print("ACTION slot bind failed: %s" % exc)
    moved = 0.0
    first = None
    for frame in (int(action.frame_range[0]), int(action.frame_range[1])):
        bpy.context.scene.frame_set(frame)
        pose = np.array([list(arm.pose.bones[b.name].matrix.translation)
                         for b in arm.data.bones])
        if first is None:
            first = pose
        else:
            moved = float(np.abs(pose - first).max())
    data.action = previous
    bpy.context.scene.frame_set(0)
    return "%.3f m" % moved


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    parser = argparse.ArgumentParser()
    parser.add_argument("--type", default="juggernaut")
    parser.add_argument("--clip", default="charge_run")
    args = parser.parse_args(argv)
    common.reset()
    path = os.path.join(mon_lib.OUT_DIR, args.type, "%s.glb" % args.type)
    mon_lib.load_glb(path)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    print("ROUNDTRIP %s: meshes %s | armature '%s' bones %d"
          % (args.type, [(o.name, len(o.data.vertices)) for o in meshes], arm.name,
             len(arm.data.bones)))
    # this is the object `mon_ground.round_trip` picks: the first MESH in bpy.data.objects order
    picked = meshes[0]
    print("ROUNDTRIP round_trip would measure '%s' (%d verts)"
          % (picked.name, len(picked.data.vertices)))
    for mesh in meshes:
        zero, unmatched = _influences(mesh, arm)
        print("ROUNDTRIP mesh %-10s groups %3d  verts %6d  no-influence %5d  unmatched %5d"
              % (mesh.name, len(mesh.vertex_groups), len(mesh.data.vertices), zero, unmatched))
    action = next((a for a in bpy.data.actions if a.name.split(".")[0] == args.clip), None)
    if action is None:
        print("ROUNDTRIP no action '%s'; have %s"
              % (args.clip, sorted(a.name for a in bpy.data.actions)))
        return
    _action_inventory()
    print("ROUNDTRIP '%s' really moves the rig by %s"
          % (action.name, _drives_armature(arm, action)))
    print("ROUNDTRIP armature bones: %s" % [b.name for b in arm.data.bones][:8])
    paths = [fc.data_path for fc in mon_ground._fcurves(action)]
    print("ROUNDTRIP %d fcurves, data_path sample: %s" % (len(paths), sorted(set(paths))[:6]))
    print("ROUNDTRIP rotation_mode of driven bones: %s"
          % sorted({arm.pose.bones[b.name].rotation_mode for b in arm.data.bones}))
    driven = _animated_bones(arm, action)
    print("ROUNDTRIP clip %s frame_range %s | drives %d bones: %s"
          % (args.clip, tuple(round(f, 2) for f in action.frame_range), len(driven), driven))
    mesh = picked
    verts = mon_ground.floor_vertices(mesh, arm)
    names = [b.name for b in arm.data.bones]
    dom = mon_skin.dominant_bones(mesh, names)
    times, lowest = mon_ground.lowest_per_frame(mesh, arm, action, verts)
    print("ROUNDTRIP clip %s measured on %d floor verts: lowest %+.3f m  highest %+.3f m"
          % (args.clip, len(verts), lowest.min(), lowest.max()))
    worst = int(np.argmin(lowest))
    print("ROUNDTRIP worst frame %.2f lowest %+.3f m" % (times[worst], lowest[worst]))
    # the same evaluation, but reporting which bone owns the lowest vertex each frame
    bidx, wts, rest = mon_skin._skin_tables(mesh, arm)
    sub_c = np.concatenate([rest[verts], np.ones((len(verts), 1))], axis=1)
    data = arm.animation_data_create()
    data.action = action
    if hasattr(action, "slots") and len(action.slots):
        data.action_slot = action.slots[0]
    mw = np.array(arm.matrix_world)
    for i in range(0, len(times), max(len(times) // 24, 1)):
        mon_ground._seek(times[i])
        skin = mon_skin._skin_matrices(arm)
        posed = np.einsum("mkij,mj->mki", skin[bidx[verts]], sub_c)[:, :, :3]
        pos = (posed * wts[verts][:, :, None]).sum(axis=1)
        z = mw[2, :3] @ pos.T + mw[2, 3]
        who = int(verts[int(np.argmin(z))])
        print("    f %6.2f  lowest %+.3f m  bone %s" % (times[i], z.min(), names[dom[who]]))
    data.action = None
    bpy.context.scene.frame_set(0)
    _bone_vs_file(arm, action, "R_Foot", 9.0, path)
    _bone_vs_file(arm, action, "R_Claw2", 9.0, path)
    _rest_vs_file(arm, path)
    _chain_vs_file(arm, action, "R_Foot", 9.0, path)


def _rest_vs_file(arm, path: str) -> None:
    """Every bone's *rest* matrix, Blender's imported armature against the file's node hierarchy.

    The animation delta turned out to be constant across frames, which can only mean the rest pose
    itself differs — an importer that drops or reparents a bone rebuilds the chain underneath it."""
    from monsters import diag_glb_floor as glbfile

    gltf, binary = glbfile.read_glb(path)
    skin = glbfile.Skin(gltf, glbfile.buffers(gltf, binary))
    rest = glbfile.globals_from(skin.rest, skin.parents, skin.order)
    yup_to_zup = np.array([[1.0, 0, 0, 0], [0, 0, -1, 0], [0, 1, 0, 0], [0, 0, 0, 1]])
    rows = []
    for node in skin.joints:
        name = skin.names[node]
        bone = arm.data.bones.get(name)
        if bone is None:
            rows.append((999.0, name, "MISSING in Blender"))
            continue
        want = yup_to_zup @ rest[node]
        got = np.array(bone.matrix_local)
        rows.append((float(np.abs(want - got).max()), name, ""))
    rows.sort(reverse=True)
    print("REST worst bone rest-matrix deltas (Blender import vs the .glb node hierarchy):")
    for delta, name, note in rows[:10]:
        print("    %-20s %.4f %s" % (name, delta, note))
    print("REST bones %d in the file, %d in Blender's armature"
          % (len(skin.joints), len(arm.data.bones)))


def _clear_pose(arm) -> None:
    """Put every pose bone back to its rest transform.

    Blender only writes the channels an action actually drives — a bone with no fcurve *keeps
    whatever value it currently holds*. Assign a second action and the first one's leftovers are
    still on the rig, so a clip that drives 13 of 54 bones is measured on top of another clip's
    pose. glTF has no such notion: a node with no channel is at its rest transform, which is what
    Godot plays."""
    from mathutils import Matrix

    for pose in arm.pose.bones:
        pose.matrix_basis = Matrix.Identity(4)


def _chain_vs_file(arm, action, leaf: str, frame: float, path: str) -> None:
    """Walk the file's own parent chain down to `leaf`, printing each joint's world translation from
    Blender and from the .glb. The first joint where they diverge is the one the importer rebuilds
    differently — everything below it just inherits the error."""
    from monsters import diag_glb_floor as glbfile

    gltf, binary = glbfile.read_glb(path)
    bufs = glbfile.buffers(gltf, binary)
    skin = glbfile.Skin(gltf, bufs)
    anim = gltf["animations"][glbfile.clip_names(gltf).index(action.name.split(".")[0])]
    tracks = glbfile.animation_tracks(gltf, bufs, anim)
    seconds = frame / bpy.context.scene.render.fps
    globals_ = glbfile.globals_from(glbfile.sample_locals(skin.rest, tracks, seconds),
                                    skin.parents, skin.order)
    yup_to_zup = np.array([[1.0, 0, 0, 0], [0, 0, -1, 0], [0, 1, 0, 0], [0, 0, 0, 1]])

    chain, node = [], skin.names.index(leaf)
    while node >= 0:
        chain.append(node)
        node = skin.parents[node]
    chain.reverse()

    data = arm.animation_data_create()
    previous = data.action
    data.action = action
    if hasattr(action, "slots") and len(action.slots):
        data.action_slot = action.slots[0]
    _clear_pose(arm)
    mon_ground._seek(frame)
    world = np.array(arm.matrix_world)
    print("CHAIN to %s @ frame %.2f (pose cleared first)" % (leaf, frame))
    for node in chain:
        name = skin.names[node]
        bone = arm.pose.bones.get(name)
        want = (yup_to_zup @ globals_[node])[:3, 3]
        got = (world @ np.array(bone.matrix))[:3, 3] if bone else np.zeros(3)
        print("    %-20s file %8.3f %8.3f %8.3f | blender %8.3f %8.3f %8.3f | delta %.3f"
              % (name, want[0], want[1], want[2], got[0], got[1], got[2],
                 float(np.linalg.norm(want - got))))
    data.action = previous
    bpy.context.scene.frame_set(0)


def _bone_vs_file(arm, action, bone_name: str, frame: float, path: str) -> None:
    """The same joint's world matrix from Blender and from the .glb, at one frame.

    If these agree, the two engines are posing the rig identically and any floor disagreement is
    about *which vertices* are measured; if they disagree, the pose itself is being rebuilt
    differently and the importer is the suspect."""
    sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
    from monsters import diag_glb_floor as glbfile

    gltf, binary = glbfile.read_glb(path)
    bufs = glbfile.buffers(gltf, binary)
    skin = glbfile.Skin(gltf, bufs)
    anim = gltf["animations"][glbfile.clip_names(gltf).index(action.name.split(".")[0])]
    tracks = glbfile.animation_tracks(gltf, bufs, anim)
    seconds = frame / bpy.context.scene.render.fps
    globals_ = glbfile.globals_from(glbfile.sample_locals(skin.rest, tracks, seconds),
                                    skin.parents, skin.order)
    node = skin.names.index(bone_name)
    from_file = globals_[node]

    data = arm.animation_data_create()
    previous = data.action
    data.action = action
    if hasattr(action, "slots") and len(action.slots):
        data.action_slot = action.slots[0]
    mon_ground._seek(frame)
    from_blender = np.array(arm.matrix_world) @ np.array(
        arm.pose.bones[bone_name].matrix)
    data.action = previous
    bpy.context.scene.frame_set(0)
    # the file is Y-up, Blender is Z-up: the importer rotates the root by +90 deg about X
    yup_to_zup = np.array([[1.0, 0, 0, 0], [0, 0, -1, 0], [0, 1, 0, 0], [0, 0, 0, 1]])
    converted = yup_to_zup @ from_file
    print("BONE %s @ frame %.2f (%.3f s)" % (bone_name, frame, seconds))
    print("  file    (Blender axes) translation %s" % np.round(converted[:3, 3], 4).tolist())
    print("  blender                translation %s" % np.round(from_blender[:3, 3], 4).tolist())
    print("  max |delta| over the 4x4: %.4f" % float(np.abs(converted - from_blender).max()))


main()
