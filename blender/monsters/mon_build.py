"""Per-type build pipelines for the HUSK monsters (monster-assets).

Three shapes:
  * `tripo`  — ripper, mantis, juggernaut, titan: keep Tripo's skeleton and clips, but take the mesh
    from the high-res source decimated to budget with the weights Data Transferred onto it, then do
    the rig surgery (claws; the titan's tail and jaw).
  * `own`    — spitter, harrier: no Tripo rig, so the armature is fitted to the mesh and the weights
    come from a heat solve on a manifold voxel proxy.
  * `static` — hive: no rig, but three damage states and a convex collision proxy.

Everything is deterministic. `build_all.py` drives this and prints the report the brief asks for.
"""
import json
import math
import os
import shutil

import bpy
import numpy as np
from mathutils import Matrix, Vector

from monsters import (mon_anims, mon_clips, mon_clips_titan, mon_emit, mon_ground, mon_lib,
                      mon_rig, mon_skin, mon_stride, mon_types)
from monsters.mon_custom_rigs import harrier_rig, spitter_rig

#: sockets every model provides. "bone" sockets ride the animation, "pos" sockets are fixed.
#: Both the brief's names and the enemies unit's placeholder names are provided (status file).
BONE_SOCKETS = {
    "mouth": ("Jaw", "Head", "Head_1", "bone_8", "Launcher_1"),
    "muzzle": ("Jaw", "Head", "Head_1", "bone_8", "Launcher_1"),
    "claw_l": ("L_Hand", "L_Claw2", "bone_12", "LegFL_2", "WingL_2"),
    "claw_r": ("R_Hand", "R_Claw2", "bone_27", "LegFR_2", "WingR_2"),
    "hand_l": ("L_Hand", "L_Claw2", "bone_12", "LegFL_2", "WingL_2"),
    "hand_r": ("R_Hand", "R_Claw2", "bone_27", "LegFR_2", "WingR_2"),
}
#: fixed sockets, as a fraction of the model's height (x, y, z); y is +back
POS_SOCKETS = {
    "core": (0.0, 0.0, 0.52),
    "chest": (0.0, -0.10, 0.62),
    "back": (0.0, 0.12, 0.62),
}
LOOPING = ("idle", "walk", "run", "scuttle", "charge_run", "fly", "glide")
#: clips whose root translation is removed so the body only moves where the AI drives it. The
#: juggernaut's `charge` is an attack, not a loop, but the AI lunges it itself, so its travel goes.
STRIP_ROOT = LOOPING + ("charge",)
#: Playback-scale ceiling: the default, and the most a clip may ever be sped up (past this a leg
#: cycle stops reading as legs). A type gets the ceiling it needs to carry `GAME_SPEED` with its
#: fastest authored gait, and no more.
MAX_SCALE_DEFAULT = 2.2
MAX_SCALE_CEILING = 4.0
#: Playback floor: the default, and the slowest any clip may be played. A type gets a lower floor
#: only when its patrol speed is slower than its slowest gait can be played at (the titan).
MIN_SCALE_DEFAULT = 0.6
#: weight-field smoothing after the rig surgery (lead r5 item 1). Light enough that a joint keeps
#: its crease, strong enough that no single edge carries the whole step.
SMOOTH_STEPS = 2
SMOOTH_LAMBDA = 0.5
#: influences per vertex. glTF and Godot both carry four, so the build trims to four *before* it
#: measures — otherwise the stretch report describes a skin the game never sees.
INFLUENCES = 4
#: clip id -> the ground speed (m/s) the clip's stride was authored for; filled by `_clips_for`.
_STRIDE: dict = {}
#: monster -> the ground-lock report (lead r5 item 3); filled by `_clips_for`.
_GROUND: dict = {}
#: clip id -> what the stride measurement saw (feet, stance fraction, root travel) — evidence.
_STRIDE_DETAIL: dict = {}


def to_godot(v) -> list:
    """Blender (x, y, z) -> Godot (x, z, -y) (CONTRACTS §2: Z up +Y forward -> Y up -Z forward)."""
    return [round(float(v[0]), 4), round(float(v[2]), 4), round(-float(v[1]), 4)]


def yaw_matrix(deg: float) -> Matrix:
    return Matrix.Rotation(math.radians(deg), 4, "Z")


def place(mesh, arm, yaw_deg: float, size: dict, ground: bool = True) -> float:
    """Yaw, scale to the target size and put the model on the floor (or centre it if not grounded).

    Returns the scale that was applied. The rig and the mesh are moved together so the clips follow."""
    axis = {"height": 2, "length": 1, "span": 0}[size["axis"]]
    base = yaw_matrix(yaw_deg)
    lo, hi = _rotated_bounds(mesh, base)
    scale = size["m"] / max(hi[axis] - lo[axis], 1e-6)
    m = Matrix.Scale(scale, 4) @ base
    lo, hi = _rotated_bounds(mesh, m)
    if ground:
        offset = Vector((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z))
    else:
        offset = Vector((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -(lo.z + hi.z) * 0.5))
    m = Matrix.Translation(offset) @ m
    mon_lib.transform_mesh(mesh, m)
    if arm is not None:
        mon_lib.transform_rig(arm, m)
    return scale


def _rotated_bounds(mesh, matrix: Matrix) -> tuple:
    return mon_lib.mesh_bounds(mesh, matrix)


# --- shared stages ------------------------------------------------------------------------------

def finish_body(monster: str, mesh) -> dict:
    """Emission mask, weak points and the texture budget. Returns the weak-point list."""
    mat = mesh.data.materials[0]
    mask, _acid, violet = mon_emit.build_mask(mat, monster)
    mon_emit.wire_emission(mat, mask)
    MEDIAN_LUMA[monster] = mon_emit.median_luma(mesh, mat)
    print("LUMA %-11s median %.4f -> albedo gain %.3f"
          % (monster, MEDIAN_LUMA[monster],
             look_table(monster, monster)["albedo_gain"]))
    weak = mon_emit.find_weak_points(mesh, violet)
    albedo_px, other_px = mon_types.TEX[monster]
    keep = {mon_emit.albedo_image(mat).name}
    mon_lib.resize_images(albedo_px, only=keep)
    mon_lib.resize_images(other_px, only=None)
    return weak


#: Median albedo luminance per type, measured by mon_emit.build_mask (lead look r1).
MEDIAN_LUMA = {}


def look_table(monster: str, key: str) -> dict:
    """The shader's per-type look numbers: mon_types.LOOK plus the *measured* albedo gain that
    lands this type on ART.md's #1B2430 chitin. Grading by measurement instead of by hand keeps a
    re-baked Tripo texture from silently turning the monsters brown again."""
    look = dict(mon_types.LOOK.get(key) or mon_types.LOOK["ripper"])
    median = MEDIAN_LUMA.get(monster, mon_emit.GRADE_TARGET)
    lo, hi = mon_emit.GRADE_CLAMP
    look["albedo_gain"] = round(min(hi, max(lo, mon_emit.GRADE_TARGET / max(median, 1e-4))), 3)
    look["pod_boost"] = mon_types.POD_BOOST
    look["flash_energy"] = mon_types.FLASH.get(key, 1.0)
    look["tell_energy"] = mon_types.TELL.get(key, 2.6)
    return look


def make_lod1(mesh, target: int, name: str):
    """A decimated copy that shares the material and the skin weights, for the 120 m LOD."""
    me = mesh.data.copy()
    lod = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(lod)
    lod.matrix_world = mesh.matrix_world.copy()
    tris = mon_lib.decimate(lod, target)
    if mesh.parent is not None:
        lod.parent = mesh.parent
        lod.matrix_parent_inverse = mesh.matrix_parent_inverse.copy()
    for mod in mesh.modifiers:
        if mod.type == "ARMATURE":
            new = lod.modifiers.new("Armature", "ARMATURE")
            new.object = mod.object
    return lod, tris


def socket_table(monster: str, arm, mesh, weak: list) -> dict:
    """Every socket in Godot model space. Bone sockets carry a bone name and a rest-space target;
    the model script converts the target into bone-local space once, at load."""
    lo, hi = mon_lib.mesh_bounds(mesh)
    height = hi.z - lo.z
    out = {}
    if arm is not None:
        names = set(b.name for b in arm.data.bones)
        for socket, candidates in BONE_SOCKETS.items():
            bone = next((c for c in candidates if c in names), None)
            if bone is None:
                continue
            head = arm.matrix_world @ arm.data.bones[bone].head_local
            out[socket] = {"bone": bone, "pos": to_godot(head)}
    for socket, (fx, fy, fz) in POS_SOCKETS.items():
        out[socket] = {"bone": "", "pos": to_godot(((lo.x + hi.x) * 0.5 + fx * height,
                                                    (lo.y + hi.y) * 0.5 + fy * height,
                                                    lo.z + fz * height))}
    for i, cluster in enumerate(weak):
        out["weak_%d" % i] = {"bone": "", "pos": to_godot(cluster["pos"]),
                              "score": cluster["score"], "faces": cluster["faces"]}
    return out


def _size_report(monster: str, lo: Vector, hi: Vector) -> dict:
    """The measured size along the briefed axis, plus the height for reference."""
    spec = mon_types.SIZES[monster]
    index = {"height": 2, "length": 1, "span": 0}[spec["axis"]]
    return {"axis": spec["axis"], "value": round((hi - lo)[index], 3), "target": spec["m"],
            "height": round(hi.z - lo.z, 3)}


def write_rig_json(monster: str, data: dict) -> str:
    path = os.path.join(mon_lib.OUT_DIR, monster, "%s_rig.json" % monster)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        json.dump(data, fh, indent=1, sort_keys=True)
    print("RIGJSON %s" % path)
    return path


#: Tripo clip id -> our clip id, where they differ (SPEC §7 names one reaction, Tripo another).
CLIP_ALIAS = {"hit_light": "hit", "hit_to_body_01": "hit", "turn": "turn_in_place"}
#: A weight transfer is only trusted if the surfaces really are the same shape (fraction of size).
ALIGN_RMS_GATE = 0.02


def align_highres(hi, remesh) -> tuple:
    """Rigidly align the high-res mesh onto the rigged remesh. Tries the four yaw seeds, keeps the
    best, and reports the surface RMS in metres (the gate for trusting the weight transfer).

    Tripo's rigging step re-orients the character, so the two meshes differ by an unknown yaw; the
    seed covers that and ICP does the rest. The seed's scale and centroid shift are part of the
    returned matrix — dropping the shift silently produces weights transferred from the wrong place,
    which deforms correctly at rest and explodes the moment a bone moves."""
    src = mon_lib.sample_points(hi, 4000)
    dst = mon_lib.sample_points(remesh, 8000)
    best = (None, 1e9, 0.0)
    for seed in (0.0, 90.0, 180.0, 270.0):
        rot = yaw_matrix(seed)
        pts = np.array([[c for c in (rot @ Vector((float(p[0]), float(p[1]), float(p[2]))))]
                        for p in src])
        s = float(np.linalg.norm(np.ptp(dst, axis=0)) /
                  max(np.linalg.norm(np.ptp(pts, axis=0)), 1e-9))
        shift = dst.mean(axis=0) - pts.mean(axis=0) * s
        pts = pts * s + shift
        m, _ = mon_lib.icp(pts, dst, iterations=24)
        moved = np.array([[c for c in (m @ Vector((float(p[0]), float(p[1]), float(p[2]))))]
                          for p in pts])
        rms = mon_lib.surface_rms(moved, remesh)
        if rms < best[1]:
            total = (m @ Matrix.Translation(Vector((float(c) for c in shift)))
                     @ Matrix.Diagonal((s, s, s, 1.0)) @ rot)
            best = (total, rms, s)
    return best


def build_tripo(monster: str, clip_set: str = None) -> dict:
    """ripper / mantis / juggernaut / titan: Tripo's skeleton and clips, our mesh budget."""
    rigged = mon_lib.load_glb(mon_lib.tripo_path(monster, "rigged.glb"))
    arm = mon_lib.only_armature(rigged, monster)
    remesh = mon_lib.only_mesh(rigged, monster)
    target = mon_types.TRIS[clip_set or monster][0]
    hi_objs = mon_lib.load_glb(mon_lib.tripo_path(monster, "model.glb"))
    hi = mon_lib.only_mesh(hi_objs, monster + " hires")
    hi.name = "Body"
    hi_tris = mon_lib.decimate(hi, target)
    matrix, rms, _ = align_highres(hi, remesh)
    size = float(np.linalg.norm(np.ptp(mon_lib.sample_points(remesh, 4000), axis=0)))
    report = {"hires_tris": hi_tris, "align_rms": round(rms, 5),
              "align_rms_frac": round(rms / max(size, 1e-6), 4), "mesh": "hires"}
    if rms / max(size, 1e-6) > ALIGN_RMS_GATE:
        print("ALIGN %s: rms %.4f (%.1f%% of size) too high — keeping the Tripo remesh"
              % (monster, rms, 100.0 * rms / size))
        bpy.data.objects.remove(hi, do_unlink=True)
        body = remesh
        body.name = "Body"
        report.update(mesh="remesh", hires_tris=0, remesh_tris=mon_lib.tri_count(body))
    else:
        mon_lib.transform_mesh(hi, matrix)
        # Lead r5 item 1: nearest-face Data Transfer hands a limb's vertices to whichever limb is
        # closest in the bind pose, and those patches tear into sheets. mon_skin follows the
        # destination surface instead (473 -> 29 bridge triangles on the mantis).
        stats = mon_skin.transfer_surface(remesh, hi)
        report["groups"] = stats["groups"]
        report["xfer"] = stats
        bpy.data.objects.remove(remesh, do_unlink=True)
        body = hi
    body.modifiers.clear()
    mon_rig.bind_mesh(body, arm)
    return _finish_rigged(monster, arm, body, report, clip_set)


def _finish_rigged(monster: str, arm, body, report: dict, clip_set: str = None) -> dict:
    """Place, do the rig surgery, then emission / clips / LOD / export for a rigged monster."""
    key = clip_set or monster
    scale = place(body, arm, mon_types.YAW[monster], mon_types.SIZES[monster],
                  ground=monster != "harrier")
    report["scale"] = round(scale, 4)
    actions = list(bpy.data.actions)
    if monster in ("mantis", "juggernaut", "titan"):
        report["claws"] = mon_rig.collapse_claws(arm, body, actions)
    if monster == "titan":
        report["tail"] = mon_rig.add_tail(arm, body)
        report["jaw"] = mon_rig.add_jaw(arm, body)
    mon_rig.bind_mesh(body, arm)
    # After the rig surgery the weight field still carries steps that a single edge has to absorb, so
    # it is smoothed over the mesh graph and then trimmed to the four influences glTF carries (lead
    # r5 item 1). Pruning far-away influences was measured and *rejected*: it is a discontinuous
    # operation, so it adds high-frequency noise of its own (worst stretch 111x against 8x without
    # it — `diag_skin_sweep.py --reach=0,1.2,2.5`).
    report["smooth"] = mon_skin.smooth_weights(body, iterations=SMOOTH_STEPS, lam=SMOOTH_LAMBDA)
    report["influences"] = mon_skin.limit_influences(body, INFLUENCES)
    weak = finish_body(monster, body)
    clips = _clips_for(monster, arm, key, body)
    return _export(monster, arm, body, clips, weak, report, key)


def _clips_for(monster: str, arm, key: str, body) -> dict:
    """Rename Tripo's clips to our ids, measure their stride, clean the root motion, add ours."""
    _STRIDE.clear()
    _STRIDE_DETAIL.clear()
    clips = {}
    for src_id, action in mon_lib.match_source_clips(monster, mon_lib.imported_actions()).items():
        clip_id = CLIP_ALIAS.get(src_id, src_id)
        action.name = clip_id
        clips[clip_id] = action
    scripted = {"ripper": mon_clips.ripper_clips, "spitter": mon_clips.spitter_clips,
                "harrier": mon_clips.harrier_clips, "juggernaut": mon_clips.juggernaut_clips,
                "titan": mon_clips_titan.titan_clips}.get(monster)
    if scripted:
        signs = mon_anims.axis_signs(arm, "up" if monster == "harrier" else "forward")
        for clip_id, keys in scripted().items():
            clips[clip_id] = mon_anims.build_clip(arm, clip_id, keys, signs=signs)
    mon_anims.apply_lifts(monster, arm, clips)
    # Every clip onto Godot's own 30 fps grid before anything is measured: the stride, the ground
    # lock and the shipped file all have to describe the pose the engine will actually play.
    baked = mon_anims.bake_fps(list(clips.values()))
    print("BAKE %-11s %d clips to %d fps (e.g. %s)"
          % (monster, len(baked), mon_anims.FPS,
             "  ".join("%s %d->%d f" % (k, v[0], v[1]) for k, v in sorted(baked.items())[:3])))
    for clip_id, action in clips.items():
        if clip_id in STRIP_ROOT:
            travel = mon_anims.strip_root_motion(action)
        else:
            travel = 0.0
        if clip_id not in LOOPING:
            continue
        # lead r1: the stride a clip was authored for is how fast its legs cycle in root space,
        # not the root's own travel (in-place clips travel nothing) — see mon_stride
        detail = mon_stride.measure(arm, action, *_measure_frame(body),
                                    feet=mon_types.FOOT_BONES[monster],
                                    grounded=monster != "harrier")
        # an idle has no stride to match: scaling it by a body speed would only speed up a
        # breath. It keeps its measurement in stride_detail and plays at 1x.
        _STRIDE[clip_id] = detail["stride"] if clip_id != "idle" else 0.0
        _STRIDE_DETAIL[clip_id] = detail
        print("STRIDE %-11s %-11s %6.2f m/s = sweep %5.2f m / %.2f s  feet %d %-22s "
              "stance %.0f%%  root %.2f m/s  stripped %.3f m"
              % (monster, clip_id, detail["stride"], detail["sweep_m"], detail["cycle_s"],
                 detail["contacts"], ",".join(detail["feet"])[:22],
                 detail["stance_frac"] * 100.0, detail["root"], travel))
    missing = [c for c in mon_types.REQUIRED[key] if c not in clips]
    if missing:
        raise RuntimeError("%s: missing required clips %s" % (monster, missing))
    # lead r5 item 3: plant the feet. The rig data's `grounded` flag used to be read by nothing, so
    # the mantis hovered up to +1.44 m and the juggernaut sank to -1.13 m.
    if monster != "harrier":
        _GROUND[monster] = mon_ground.lock(monster, arm, body, clips, mon_types.GROUND_CONST)
    return clips


def _measure_frame(body) -> tuple:
    """(model height, ground plane z) from the rest-pose mesh — the stance band scales with them."""
    lo, hi = mon_lib.mesh_bounds(body)
    return hi.z - lo.z, lo.z


def speed_scale_max(monster: str) -> float:
    """The playback ceiling this type needs so its fastest authored gait carries `GAME_SPEED`.

    The ceiling exists so a clip is never sped up until the legs stop reading as legs; a type only
    gets more than the default when its gameplay speed genuinely needs it (lead r3: the ripper at
    30 m/s against a 0.33 s scuttle cycle)."""
    gaits = [float(_STRIDE.get(c, 0.0)) for ladder in mon_types.GAITS[monster].values()
             for c in ladder]
    fastest = max(gaits) if gaits else 0.0
    if fastest <= 0.1:
        return MAX_SCALE_DEFAULT
    need = mon_types.GAME_SPEED.get(monster, 0.0) / fastest
    return round(min(max(need, MAX_SCALE_DEFAULT), MAX_SCALE_CEILING), 3)


def speed_scale_min(monster: str) -> float:
    """The playback floor this type needs to walk its patrol speed without skating.

    `brain.gd` patrols at 0.35 × move speed, and a clip can only be slowed to 0.6x by default. A
    60 m titan whose walk measures 17.5 m/s would then patrol at 4.9 m/s playing a 10.5 m/s stride,
    i.e. skating; it gets the floor it needs instead, and nothing goes below the hard floor."""
    strides = [float(_STRIDE.get(c, 0.0)) for ladder in mon_types.GAITS[monster].values()
               for c in ladder if c != "idle"]
    grounded = [s for s in strides if s > 0.1]
    if not grounded:
        return MIN_SCALE_DEFAULT
    need = mon_types.GAME_SPEED.get(monster, 0.0) * mon_types.PATROL_FRACTION / min(grounded)
    return round(min(max(need, mon_types.SPEED_SCALE_FLOOR), MIN_SCALE_DEFAULT), 3)


def gait_table(monster: str, clips: dict) -> dict:
    """Per locomotion state, the clips the model may pick from, slowest first, each with the ground
    speed it stays clean up to (lead r3).

    A clip stays clean while playback can be scaled to match the body: `stride * ceiling` metres a
    second, less the slide tolerance. The model plays the first entry that covers the real speed and
    the last one above it, so a patrol keeps the Tripo walk and a chase switches to the scuttle
    without the enemies unit changing state."""
    tol = 1.0 - mon_types.SLIDE_TOLERANCE.get(monster, mon_types.SLIDE_DEFAULT)
    ceiling = speed_scale_max(monster)
    out = {}
    for state, ladder in mon_types.GAITS[monster].items():
        entries = []
        for clip_id in ladder:
            if clip_id not in clips:
                print("GAIT WARN %s: state '%s' wants clip '%s', which the build does not have"
                      % (monster, state, clip_id))
                continue
            stride = float(_STRIDE.get(clip_id, 0.0))
            # no ground contact (a harrier in flight, an idle): it plays at 1x at any speed
            clean = round(stride * ceiling / tol, 2) if stride > 0.1 else 1.0e9
            entries.append({"clip": clip_id, "stride": round(stride, 3), "clean_max": clean})
        if entries:
            out[state] = entries
    return out


def action_table(monster: str, clips: dict) -> dict:
    """Every action id the enemies unit can ask for, resolved onto a clip this type really has.

    An id that is already a clip resolves to itself and needs no entry; an entry whose target is
    missing is dropped with a warning rather than left in the table pointing at nothing (the bug the
    lead's alias fix worked around)."""
    table = {cid: cid for cid in clips}
    for asked, target in mon_types.ACTIONS.get(monster, {}).items():
        if target in clips:
            table[asked] = target
        else:
            print("ACTION WARN %s: '%s' -> '%s' but that clip does not exist"
                  % (monster, asked, target))
    return table


def build_own(monster: str) -> dict:
    """spitter / harrier: fit our own armature, weight it through a manifold voxel proxy."""
    objs = mon_lib.load_glb(mon_lib.tripo_path(monster, "model.glb"))
    body = mon_lib.only_mesh(objs, monster)
    body.name = "Body"
    body.modifiers.clear()
    tris = mon_lib.decimate(body, mon_types.TRIS[monster][0])
    scale = place(body, None, mon_types.YAW[monster], mon_types.SIZES[monster],
                  ground=monster != "harrier")
    arm, spec = (spitter_rig if monster == "spitter" else harrier_rig)(body)
    report = {"hires_tris": tris, "scale": round(scale, 4), "bones_fitted": len(spec)}
    report.update(mon_rig.rig_from_proxy(body, arm))
    mon_rig.bind_mesh(body, arm)
    weak = finish_body(monster, body)
    clips = _clips_for(monster, arm, monster, body)
    return _export(monster, arm, body, clips, weak, report, monster)


def _plant_shipped(monster: str, path: str, objects: list, arm, body, clips: dict) -> dict:
    """Correct the ground lock against the exported file until the shipped GLB really is planted.

    Lead r5 item 3: Blender's evaluation and the exported GLB do not agree everywhere — the ripper's
    `idle` came back 0.44 m below the floor with the root bone moving exactly the distance the build
    had asked for — so the build measures the file it just wrote, loads it back, and nudges the root
    keys by whatever is left.

    Every export is measured, including the one the loop exits on, and the *best* measured file is
    the one that ships: an earlier version nudged and re-exported without ever checking the result,
    and that last unchecked export is how the juggernaut's `charge_run` shipped 1.8 m under the
    floor while the log said 0.09 m."""
    bone = mon_ground.root_bone(arm)
    support = mon_ground.support_bones(arm, monster)
    best = os.path.join(mon_lib.TMP, "%s_best.glb" % monster)
    os.makedirs(mon_lib.TMP, exist_ok=True)
    best_score = float("inf")
    report = {}
    for attempt in range(mon_ground.GROUND_PASSES + 1):
        measured = mon_ground.round_trip(path, clips, support)
        worst, worst_clip = 0.0, ""
        report = {}
        for clip_id, (_times, lowest) in measured.items():
            # the gate is the *lowest* point, not how high a leap arcs
            span = abs(float(lowest.min()))
            report[clip_id] = round(span, 3)
            if span > worst:
                worst, worst_clip = span, clip_id
        print("PLANT %-11s pass %d  worst |lowest| %.3f m (%s)  gate %.2f m"
              % (monster, attempt, worst, worst_clip or "-", mon_ground.GROUND_TOL))
        if worst < best_score:
            best_score = worst
            shutil.copyfile(path, best)
        if worst <= mon_ground.GROUND_TOL:
            break
        for clip_id, (times, lowest) in measured.items():
            if abs(float(lowest.min())) <= mon_ground.GROUND_TOL:
                continue
            # a `const` clip keeps its arc, so it is corrected by one number; a pinned clip is
            # corrected frame by frame
            const = (_GROUND.get(monster, {}).get(clip_id, {}) or {}).get("mode") == "const"
            delta = np.full(len(times), -float(lowest.min())) if const else -lowest
            mon_ground.nudge(arm, bone, clips[clip_id], times, delta)
        mon_lib.export_glb(path, objects)
    if os.path.exists(best):
        shutil.copyfile(best, path)
        os.remove(best)
    print("PLANT %-11s shipped the best measured export (worst |lowest| %.3f m)" % (monster, best_score))
    return report


def _bridge_report(label: str, body, arm) -> dict:
    """Bridge triangles in the finished mesh — the build-time twin of probe_fuse.gd."""
    names = [b.name for b in arm.data.bones]
    parents = [names.index(b.parent.name) if b.parent else -1 for b in arm.data.bones]
    got = mon_skin.bridge_triangles(body, names, parents)
    top = sorted(got["pairs"].items(), key=lambda kv: -kv[1])[:5]
    print("BRIDGE %-16s tris %7d bridge %5d (%5.2f%%) pairs %3d  %s"
          % (label, got["tris"], got["bridge"], 100.0 * got["bridge"] / max(got["tris"], 1),
             len(got["pairs"]), "  ".join("%s %d" % kv for kv in top)))
    return {"tris": got["tris"], "bridge": got["bridge"],
            "pairs": {k: v for k, v in top}}


def _export(monster: str, arm, body, clips: dict, weak: list, report: dict, key: str) -> dict:
    """LOD1, glTF export and the rig JSON the Godot model script reads."""
    # lead r5 item 1: the old check_skin compared the posed bounding box, which cannot see a sheet
    # stretched between two limbs. The per-edge test and the bridge census can.
    report["stretch"] = mon_skin.stretch_report(monster, body, arm, clips)
    report["bridge"] = _bridge_report(monster, body, arm)
    report["open_edges"] = round(mon_lib.check_welded(key, body), 4)
    lod, lod_tris = make_lod1(body, mon_types.TRIS[key][1], "BodyLod1")
    if lod is not None:
        report["stretch_lod1"] = mon_skin.stretch_report(monster + "/lod1", lod, arm, clips)
        report["bridge_lod1"] = _bridge_report(monster + "/lod1", lod, arm)
    objects = [arm, body] + ([lod] if lod is not None else [])
    path = os.path.join(mon_lib.OUT_DIR, monster, "%s.glb" % monster)
    mon_lib.export_glb(path, objects)
    if monster != "harrier":
        _plant_shipped(monster, path, objects, arm, body, clips)
    lo, hi = mon_lib.mesh_bounds(body)
    gait = gait_table(key, clips)
    ceiling = speed_scale_max(key)
    report["ground"] = _GROUND.get(monster, {})
    report.update({
        "path": path, "lod0_tris": mon_lib.tri_count(body), "lod1_tris": lod_tris,
        "verts": len(body.data.vertices), "bones": len(arm.data.bones),
        "size": _size_report(monster, lo, hi),
        "clips": {cid: round(mon_lib.clip_seconds(a), 3) for cid, a in clips.items()},
        "weak_points": weak, "gait": gait, "speed_scale_max": ceiling,
    })
    write_rig_json(monster, {
        "type": monster, "size": report["size"], "lod_dist_m": mon_types.LOD_DIST_M,
        "shadow": monster in mon_types.SHADOW_CASTERS,
        "grounded": monster != "harrier",
        "bones": sorted(b.name for b in arm.data.bones),
        "sockets": socket_table(monster, arm, body, weak),
        "locomotion": {k: v for k, v in mon_types.LOCOMOTION[key].items()},
        "gait": gait,
        "actions": action_table(key, clips),
        "look": look_table(monster, key),
        "speed_scale_min": speed_scale_min(key),
        "speed_scale_max": ceiling,
        "stride_speed": dict(_STRIDE),
        "stride_detail": dict(_STRIDE_DETAIL),
        "clips": {cid: {"length": round(mon_lib.clip_seconds(a), 3), "loop": cid in LOOPING}
                  for cid, a in clips.items()},
    })
    mon_lib.report(monster, body, arm, clips)
    if monster == "titan":
        report["skyline"] = _export_skyline(arm, body, clips, weak)
    return report


def _export_skyline(arm, body, clips: dict, weak: list) -> dict:
    """The 10k-tri skyline walker: walk + roar only, scaled x1.5 (90 m) by its own Godot scene.

    SPEC §7 has the Brood Titan walking the skyline from minute one; at ring distance only the
    silhouette and two clips read, so it ships as its own model (lead note, monster-assets)."""
    keep = set(mon_types.REQUIRED["titan_skyline"])
    for clip_id in [c for c in clips if c not in keep]:
        action = clips.pop(clip_id)
        for track in list(arm.animation_data.nla_tracks):
            if track.name == clip_id:
                arm.animation_data.nla_tracks.remove(track)
        bpy.data.actions.remove(action)
    far, tris = make_lod1(body, mon_types.TRIS["titan_skyline"][0], "SkylineBody")
    body.hide_set(True)
    path = os.path.join(mon_lib.OUT_DIR, "titan_skyline", "titan_skyline.glb")
    mon_lib.export_glb(path, [arm, far])
    # The lock was solved against the 150k body; the 10k skyline copy decimates the feet, so its own
    # lowest point lands elsewhere — `walk` came out 0.17 m under the deck before this. Plant the
    # file that actually ships. The titan GLB is already written, so nudging the shared actions here
    # cannot reach back and change it.
    _plant_shipped("titan_skyline", path, [arm, far], arm, far, clips)
    skyline_m = mon_types.SIZES["titan"]["m"] * mon_types.TITAN_SKYLINE_SCALE
    write_rig_json("titan_skyline", {
        "type": "titan_skyline",
        "size": {"axis": "height", "value": skyline_m, "target": skyline_m,
                 "height": skyline_m},
        "lod_dist_m": 0.0, "shadow": False, "grounded": True,
        "scale": mon_types.TITAN_SKYLINE_SCALE,
        "bones": sorted(b.name for b in arm.data.bones),
        "sockets": socket_table("titan", arm, far, weak),
        "locomotion": dict(mon_types.LOCOMOTION["titan_skyline"]),
        "gait": gait_table("titan_skyline", clips),
        "actions": action_table("titan_skyline", clips),
        "look": look_table("titan", "titan_skyline"),
        "speed_scale_min": speed_scale_min("titan_skyline"),
        "speed_scale_max": speed_scale_max("titan_skyline"),
        "stride_speed": dict(_STRIDE),
        "stride_detail": dict(_STRIDE_DETAIL),
        "clips": {cid: {"length": round(mon_lib.clip_seconds(a), 3), "loop": cid in LOOPING}
                  for cid, a in clips.items()},
    })
    return {"path": path, "tris": tris, "clips": sorted(clips),
            "scale": mon_types.TITAN_SKYLINE_SCALE}



