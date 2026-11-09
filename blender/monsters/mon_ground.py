"""Ground lock: plant a monster's lowest point on the floor in every frame (monster-assets).

Lead r5 item 3. The mantis floated — its `run` loop never brought a foot below +0.36 m and rose to
+1.44 m, so it hovered above the deck in 38 of 38 frames while casting no shadow — and the others
sank: juggernaut idle to -1.13 m, spitter scuttle -1.01 m, ripper scuttle -0.52 m, titan idle
-2.15 m. The rig data's `grounded` flag was read by nothing.

The fix is a per-clip vertical offset written onto the rig's root bone, measured from the mesh
itself: for every frame of a clip the build skins the vertices that can reach the floor, takes the
lowest one (skipping the bridge triangles, the same rule `probe_floor.gd` uses so the two numbers
compare), and keys the root so that point sits on y = 0. Clips that are *meant* to leave the ground
(a leap, a dive, a death fall) only get a constant offset, so the arc survives but its lowest point
still lands on the floor.

Everything is measured in Blender at build time and baked into the clip, so nothing in
`game/enemies/**` changes and `probe_floor` sees the planted pose by seeking the animation.
"""
import bpy
import numpy as np
import os

from monsters import mon_skin

#: How far up the model a vertex can still be the lowest point in some frame. It has to be the whole
#: mesh: a ripper's head swings below its rest-pose feet mid-stride, and restricting the solve to the
#: bottom third left `probe_floor` reading -0.44 m where the build had measured 0.00. The solve is
#: affordable — 75k vertices x 4 influences x ~1200 frames is a few seconds of numpy.
FLOOR_BAND = 1.0
#: How far above a contact bone still counts as support. Three hops is a leg: toe -> foot -> calf.
SUPPORT_HOPS = 3
#: Frames sampled per second of clip. 30 Hz matches `probe_floor.gd`.
HZ = 30.0
#: Root bones a Tripo clip drives its translation from (`mon_anims.ROOT_BONES`).
ROOT_BONES = ("tripo::Root", "BoneRoot", "Hip", "Root")


def support_bones(arm, monster: str) -> set:
    """The bones that can bear this monster's weight: `mon_types.FOOT_BONES` and everything within
    `SUPPORT_HOPS` of them up the tree.

    The lock plants *these*, not the global lowest point. A hand claw or a tail is not support, and
    pinning whichever vertex happens to be lowest lifts the whole animal the moment one of them
    swings past the feet — the juggernaut's knuckle claws did exactly that in `charge_run` (claws
    0.64 m below the feet, so pinning them floated the feet 0.24 m up instead), and the titan's tail
    does it in four clips (pinning `Tail_5` left the feet 2.2 m in the air during `tail_sweep`)."""
    from monsters import mon_types

    parent = {b.name: (b.parent.name if b.parent else None) for b in arm.data.bones}
    out = set()
    for foot in mon_types.FOOT_BONES.get(monster, ()):
        node, up = foot, 0
        while node is not None and up <= SUPPORT_HOPS:
            out.add(node)
            node = parent.get(node)
            up += 1
    if not out:
        raise RuntimeError("mon_ground: %s has none of the foot bones %s"
                           % (monster, mon_types.FOOT_BONES.get(monster)))
    return out


def root_bone(arm):
    """The bone the ground lock is written to: Tripo's technical root, else the top of the tree."""
    for name in ROOT_BONES:
        if name in arm.pose.bones:
            return name
    tops = [b.name for b in arm.data.bones if b.parent is None]
    if not tops:
        raise RuntimeError("mon_ground: %s has no root bone" % arm.name)
    return tops[0]


def clear_pose(arm) -> None:
    """Put every pose bone back to its rest transform before a clip is measured.

    Blender only writes the channels an action actually drives — a bone with no fcurve *keeps
    whatever value it currently holds*. So measuring clip after clip on one armature leaves each
    clip sitting on top of the previous one's leftovers, and a clip that drives 13 of 54 bones is
    then measured against 41 bones frozen in someone else's pose.

    That is exactly how the juggernaut's `charge_run` shipped 0.70 m under the floor while the build
    measured 0.09 m: glTF has no such notion (a node with no channel is at its rest transform, which
    is what Godot plays), so the leftovers only ever existed inside Blender."""
    from mathutils import Matrix

    for pose in arm.pose.bones:
        pose.matrix_basis = Matrix.Identity(4)


def floor_vertices(mesh, arm, support: set = None, band: float = FLOOR_BAND) -> np.ndarray:
    """Indices of the vertices the ground lock may plant on.

    Bridge triangles join bones more than three hops apart in the skeleton; a torn sheet between two
    limbs is not a foot, and counting it would plant the monster on its own tear. `support` then
    keeps only the vertices a leg owns — see `support_bones` for why that matters."""
    pts = mon_skin.world_points(mesh)
    lo, hi = pts[:, 2].min(), pts[:, 2].max()
    keep = pts[:, 2] <= lo + band * (hi - lo)
    names = [b.name for b in arm.data.bones]
    parents = [names.index(b.parent.name) if b.parent else -1 for b in arm.data.bones]
    dom = mon_skin.dominant_bones(mesh, names)
    tris = mon_skin.triangulate(mesh.data.polygons)
    d = dom[tris]
    bad = np.zeros(len(pts), dtype=bool)
    hops = _hop_table(parents)
    for e in range(3):
        a, b = d[:, e], d[:, (e + 1) % 3]
        far = (a >= 0) & (b >= 0) & (a != b)
        if not far.any():
            continue
        h = np.zeros(len(tris), dtype=np.int64)
        h[far] = hops(a[far], b[far])
        if (h > 3).any():
            bad[tris[h > 3].reshape(-1)] = True
    keep &= ~bad
    if support:
        keep &= np.isin(dom, [names.index(n) for n in support if n in names])
    return np.nonzero(keep)[0]


def _hop_table(parents: list):
    """Vectorised bone-tree distance: `hops(a, b)` for arrays of bone indices."""
    ancestor = []
    for i in range(len(parents)):
        chain, n = [], i
        while n >= 0:
            chain.append(n)
            n = parents[n]
        ancestor.append(chain)
    cache = {}

    def hops(a: np.ndarray, b: np.ndarray) -> np.ndarray:
        out = np.full(len(a), 99, dtype=np.int64)
        for i in range(len(a)):
            key = (int(a[i]), int(b[i]))
            key = key if key[0] < key[1] else (key[1], key[0])
            if key not in cache:
                ca, cb = ancestor[key[0]], ancestor[key[1]]
                common = next((j for j, n in enumerate(ca) if n in cb), None)
                cache[key] = 99 if common is None else common + cb.index(ca[common])
            out[i] = cache[key]
        return out

    return hops


def sample_times(action, hz: float = HZ) -> list:
    """The times `probe_floor.gd` samples: 30 Hz across the clip, as float frames.

    They have to be *fractional* whenever the clip's keys are sparser than 30 Hz: sampling only at
    the authored keys misses the dip between them, because bone rotations interpolate as quaternions
    and a foot on a rotating hip swings along an arc that passes below the chord between two keys.
    Since `mon_anims.bake_fps` every clip is on a 30 fps grid, so these land on or very near
    the authored keys and the lock is exact rather than approximate."""
    start, end = int(action.frame_range[0]), int(action.frame_range[1])
    fps = bpy.context.scene.render.fps
    steps = max(int(np.ceil((end - start) / max(fps / hz, 1e-6))), 1)
    return [start + i * (end - start) / steps for i in range(steps)]


def _seek(frame: float) -> None:
    """Move the scene to a fractional frame."""
    whole = int(np.floor(frame))
    bpy.context.scene.frame_set(whole, subframe=float(frame - whole))


def lowest_per_frame(mesh, arm, action, verts: np.ndarray, hz: float = HZ) -> tuple:
    """(times, lowest world z) for one clip, skinning only `verts`."""
    bidx, wts, rest = mon_skin._skin_tables(mesh, arm)
    sub_b, sub_w = bidx[verts], wts[verts]
    sub_c = np.concatenate([rest[verts], np.ones((len(verts), 1))], axis=1)
    mw = np.array(arm.matrix_world)
    times = sample_times(action, hz)
    data = arm.animation_data_create()
    previous = data.action
    data.action = action
    if hasattr(action, "slots") and len(action.slots):
        data.action_slot = action.slots[0]
    clear_pose(arm)
    out = np.zeros(len(times))
    for i, frame in enumerate(times):
        _seek(frame)
        skin = mon_skin._skin_matrices(arm)
        posed = np.einsum("mkij,mj->mki", skin[sub_b], sub_c)[:, :, :3]
        pos = (posed * sub_w[:, :, None]).sum(axis=1)
        out[i] = float((mw[2, :3] @ pos.T).min() + mw[2, 3])
    data.action = previous
    bpy.context.scene.frame_set(0)
    return times, out


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


def _remove_fcurve(action, fc) -> None:
    try:
        action.fcurves.remove(fc)
        return
    except AttributeError:
        pass
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                if fc in list(bag.fcurves):
                    bag.fcurves.remove(fc)
                    return


def _sample_locations(arm, action, bone: str, frames: list) -> list:
    """The root bone's authored location at each frame, read before any key is written.

    Snapshotting first matters: inserting a key at frame f changes what the curve interpolates at
    every frame after it, so reading and writing in one pass would compound the offset."""
    data = arm.animation_data_create()
    previous = data.action
    data.action = action
    if hasattr(action, "slots") and len(action.slots):
        data.action_slot = action.slots[0]
    clear_pose(arm)
    out = []
    for frame in frames:
        _seek(frame)
        out.append(arm.pose.bones[bone].location.copy())
    data.action = previous
    bpy.context.scene.frame_set(0)
    return out


def write_offset(arm, action, bone: str, frames: list, offsets: np.ndarray,
                 replace: bool = True) -> None:
    """Key a world-space vertical offset onto `bone` for every frame, keeping its authored motion.

    A pose bone's `location` lives in the bone's rest axes, so a world +Z offset has to be rotated
    into them; the root has no parent, so nothing else rotates it on the way out. With `replace` the
    clip's own vertical root motion is removed first, so the offset is the whole vertical story."""
    from mathutils import Vector

    pose = arm.pose.bones[bone]
    rest = arm.data.bones[bone].matrix_local.to_3x3()
    basis = rest.inverted()
    original = _sample_locations(arm, action, bone, frames)
    # Replace the clip's own vertical root motion instead of adding to it: `strip_root_motion` only
    # zeroes the bones it recognises, and on the ripper Tripo's idle still carried -0.42 m of its
    # own, so adding the lock's -0.42 on top planted the model 0.85 m *below* the floor. Horizontal
    # motion (a lunge, a drift) is left exactly as authored.
    if replace:
        original = [loc - (basis @ Vector((0.0, 0.0, (rest @ loc).z))) for loc in original]
    # The clip has to be the armature's *active* action while the keys go in: with `action` left at
    # None (the build stashes every clip on a muted NLA track) `keyframe_insert` quietly creates a
    # fresh action of its own and the offset lands nowhere.
    data = arm.animation_data_create()
    previous = data.action
    data.action = action
    if hasattr(action, "slots") and len(action.slots):
        data.action_slot = action.slots[0]
    # Drop the channel's existing keys first. Layering new keys on top of the old ones leaves the
    # authored curve in place between them, and the interpolation then follows *those* — which is
    # how the ripper's idle ended up 0.44 m under the floor with the root bone moving exactly the
    # distance the build had asked for. The sampled `original` above already carries whatever the
    # clip authored, so rewriting the channel loses nothing.
    path = 'pose.bones["%s"].location' % bone
    for fc in [f for f in _fcurves(action) if f.data_path == path]:
        _remove_fcurve(action, fc)
    for i, frame in enumerate(frames):
        pose.location = original[i] + (basis @ Vector((0.0, 0.0, float(offsets[i]))))
        pose.keyframe_insert("location", frame=frame)
    data.action = previous
    bpy.context.scene.frame_set(0)
    for fc in _fcurves(action):
        if fc.data_path != path:
            continue
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
        fc.update()
    pose.location = (0.0, 0.0, 0.0)


def lock(monster: str, arm, mesh, clips: dict, const_clips: tuple) -> dict:
    """Plant every grounded clip of one monster. Returns {clip: report} for the build report.

    A clip in `const_clips` is meant to leave the floor (a leap, a dive, a death fall), so it only
    gets one offset for the whole clip: the arc survives and its lowest point still lands on y = 0.
    Everything else is pinned frame by frame."""
    verts = floor_vertices(mesh, arm)
    bone = root_bone(arm)
    out = {}
    for clip_id in sorted(clips):
        action = clips[clip_id]
        frames, lowest = lowest_per_frame(mesh, arm, action, verts)
        if clip_id in const_clips:
            offsets = np.full(len(frames), -float(lowest.min()))
            mode = "const"
        else:
            offsets = -lowest
            mode = "lock"
        write_offset(arm, action, bone, frames, offsets, replace=mode == "lock")
        _, after = lowest_per_frame(mesh, arm, action, verts)
        out[clip_id] = {"mode": mode, "was_low": round(float(lowest.min()), 3),
                        "was_high": round(float(lowest.max()), 3),
                        "now_low": round(float(after.min()), 3),
                        "now_high": round(float(after.max()), 3)}
        print("GROUND %-11s %-14s %-5s  lowest %+.2f..%+.2f m -> %+.2f..%+.2f m"
              % (monster, clip_id, mode, lowest.min(), lowest.max(),
                 after.min(), after.max()))
    return out


# --- the shipped file is the thing that has to be planted ---------------------------------------

#: How close to y = 0 the shipped GLB has to be, in metres, before the build stops correcting.
GROUND_TOL = 0.05
#: Correction passes. Two are enough in practice; the third is a guard.
GROUND_PASSES = 3


def round_trip(path: str, clips: dict, support: set = None) -> dict:
    """Measure every clip of an exported GLB by reading the file itself, the way Godot does.

    This used to load the GLB back into Blender and measure it there, and that measurement could not
    be trusted: Blender only writes the channels an action drives, so measuring clip after clip on
    one imported armature left each clip on top of the previous one's leftovers (see `clear_pose`),
    and the number it produced for the juggernaut's `charge_run` — 0.09 m — described a rig that was
    never posed. The clip really sank 0.70 m.

    `diag_glb_floor` reads the container directly (nodes, skins, inverse bind matrices, animation
    samplers) and skins it with numpy, so the number it returns is the number the engine plays — it
    agrees with Godot's `probe_floor` to the millimetre. It also needs no Blender scene, which makes
    it roughly fifty times cheaper than a re-import.

    `support` is only used for the `CLEARANCE` diagnostic: the gap between the feet's lowest point
    and the whole body's, which is what catches a limb hanging below the feet.

    Returns {clip: (times in Blender frames, lowest world y per frame)}."""
    from monsters import diag_glb_floor as glbfile

    gltf, bufs, skin = _parsed(path)
    joints = skin.support_joints(support or ()) if support else frozenset()
    names = glbfile.clip_names(gltf)
    fps = float(bpy.context.scene.render.fps)
    out = {}
    for name in clips:
        if name not in names:
            continue
        anim = gltf["animations"][names.index(name)]
        tracks = glbfile.animation_tracks(gltf, bufs, anim)
        length = max(float(glbfile.accessor(gltf, bufs, s["input"])[:, 0].max())
                     for s in anim["samplers"])
        got = glbfile.measure(skin, tracks, length, HZ)
        out[name] = ([t * fps for t, _low, _bone in got["rows"]],
                     np.array([low for _t, low, _bone in got["rows"]]))
        if joints:
            feet = glbfile.measure(skin, tracks, length, HZ, joints)
            print("CLEARANCE %-11s %-14s feet %+.2f m  body %+.2f m  gap %+.2f m"
                  % (os.path.basename(os.path.dirname(path)), name, feet["low"], got["low"],
                     got["low"] - feet["low"]))
    return out


#: Parsing a GLB and building its bridge mask is the expensive part of a measurement, and
#: `_plant_shipped` measures the same file up to four times. Keyed by path and mtime so a re-export
#: is never read stale.
_PARSED: dict = {}


def _parsed(path: str) -> tuple:
    """(gltf JSON, buffers, Skin) for an exported GLB, parsed once per file version."""
    from monsters import diag_glb_floor as glbfile

    key = (path, os.path.getmtime(path), os.path.getsize(path))
    if key not in _PARSED:
        _PARSED.clear()
        gltf, binary = glbfile.read_glb(path)
        bufs = glbfile.buffers(gltf, binary)
        _PARSED[key] = (gltf, bufs, glbfile.Skin(gltf, bufs))
    return _PARSED[key]


def nudge(arm, bone: str, action, frames: list, deltas: np.ndarray) -> None:
    """Add a world-space vertical delta to a clip's existing root location keys."""
    from mathutils import Vector

    rest = arm.data.bones[bone].matrix_local.to_3x3()
    basis = rest.inverted()
    path = 'pose.bones["%s"].location' % bone
    curves = [fc for fc in _fcurves(action) if fc.data_path == path]
    if not curves:
        return
    for fc in curves:
        for kp in fc.keyframe_points:
            i = int(np.argmin(np.abs(np.array(frames, dtype=float) - kp.co[0])))
            shift = basis @ Vector((0.0, 0.0, float(deltas[i])))
            kp.co[1] += shift[fc.array_index]
            kp.handle_left[1] += shift[fc.array_index]
            kp.handle_right[1] += shift[fc.array_index]
        fc.update()
