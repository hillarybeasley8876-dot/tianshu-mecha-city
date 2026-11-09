"""Shared helpers for the monster build (monster-assets unit).

Every builder starts with:
    import sys, os; sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
    from lib import common
    from monsters import mon_lib

Conventions (CONTRACTS §2): metres, Blender Z up, +Y forward (= Godot −Z), origin at the feet
(the harrier's origin is its body centre). Builds are deterministic: no randomness, no timestamps.
"""
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.expanduser("~/m/mecha-city")
TMP = os.path.join(ROOT, "tmp", "monster-assets")
TRIPO = os.path.join(ROOT, "art", "tripo")
OUT_DIR = os.path.join(ROOT, "game", "enemies", "models")
# Tripo ships an untextured 80-face Icosphere helper in every GLB; it wrecks bounds and framing.
HELPER_MAX_FACES = 200


def tripo_path(monster: str, name: str) -> str:
    return os.path.join(TRIPO, "mon_%s" % monster, name)


def load_glb(path: str) -> list:
    """Import a GLB into the current scene and drop Tripo helper objects. Returns the new objects.

    `merge_vertices` matters: glTF splits a vertex at every UV seam, so without it every seam
    arrives as an open boundary and the collapse decimator then pulls the two sides apart — the
    shipped meshes had 12k-44k open edges and read as sky-coloured cracks along every silhouette
    under TAA (lead look r1, item 3). Blender keeps UVs per face corner, so welding costs no UVs."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path, merge_vertices=True)
    new = [o for o in bpy.data.objects if o not in before]
    for obj in list(new):
        if obj.type == "MESH" and not obj.data.materials and len(obj.data.polygons) < HELPER_MAX_FACES:
            bpy.data.objects.remove(obj, do_unlink=True)
            new.remove(obj)
    return new


#: A welded mesh may still have real boundaries (Tripo ships open shells), but a UV seam must never
#: become one: past this fraction of all edges the build says so (lead look r1, item 3).
WELD_GATE = 0.02


def check_welded(label: str, obj) -> float:
    """Print a mesh's open-edge fraction — the QA gate for the weld above. Returns the fraction."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    total = len(bm.edges)
    boundary = sum(1 for e in bm.edges if len(e.link_faces) < 2)
    bm.free()
    frac = boundary / max(total, 1)
    print("WELD %-14s %6d open / %6d edges = %5.2f%%%s"
          % (label, boundary, total, 100.0 * frac,
             "  OVER GATE %.0f%%" % (100.0 * WELD_GATE) if frac > WELD_GATE else ""))
    return frac


def only_mesh(objs: list, label: str):
    meshes = [o for o in objs if o.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError("%s: expected 1 mesh, got %d" % (label, len(meshes)))
    return meshes[0]


def only_armature(objs: list, label: str):
    arms = [o for o in objs if o.type == "ARMATURE"]
    if len(arms) != 1:
        raise RuntimeError("%s: expected 1 armature, got %d" % (label, len(arms)))
    return arms[0]


def tri_count(obj) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def decimate(obj, target_tris: int) -> int:
    """Collapse-decimate to ~target_tris (UVs kept). Returns the resulting triangle count."""
    tris = tri_count(obj)
    if tris <= target_tris:
        return tris
    mod = obj.modifiers.new("dec", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = min(1.0, target_tris / tris)
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return tri_count(obj)


def transform_mesh(obj, matrix: Matrix) -> None:
    """Bake a world-space matrix into the mesh data and leave the object at identity."""
    obj.data.transform(matrix @ obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)


def transform_rig(arm, matrix: Matrix) -> None:
    """Bake a world-space matrix into the armature's rest bones; the object ends at identity.

    Actions are stored relative to the rest pose, so this carries the whole rig and its clips."""
    mw = matrix @ arm.matrix_world
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for bone in arm.data.edit_bones:
        bone.head = mw @ bone.head
        bone.tail = mw @ bone.tail
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.matrix_world = Matrix.Identity(4)


def vertex_positions(obj, matrix: Matrix = None) -> np.ndarray:
    """World-space vertex positions as an (n, 3) array (matrix defaults to the object's own)."""
    mw = (matrix @ obj.matrix_world) if matrix is not None else obj.matrix_world
    buf = np.empty(len(obj.data.vertices) * 3, dtype=np.float64)
    obj.data.vertices.foreach_get("co", buf)
    pts = buf.reshape(-1, 3)
    m = np.array(mw)
    return pts @ m[:3, :3].T + m[:3, 3]


def mesh_bounds(obj, matrix: Matrix = None) -> tuple:
    """World-space (lo, hi) of a mesh object.

    Read from the vertices, not `obj.bound_box`: baking a matrix into the mesh data leaves the cached
    bound_box stale, and a stale bound_box silently mis-scales the model."""
    pts = vertex_positions(obj, matrix)
    return Vector(pts.min(axis=0)), Vector(pts.max(axis=0))


def resize_images(max_px: int, only: set = None, jpeg: bool = True) -> list:
    """Downscale (and JPEG-encode) images so the exported GLB stays a committable size."""
    out = []
    for img in bpy.data.images:
        if only is not None and img.name not in only:
            continue
        w, h = img.size
        if max(w, h) > max_px:
            s = max_px / max(w, h)
            img.scale(max(1, int(w * s)), max(1, int(h * s)))
        elif img.file_format == "JPEG":
            continue
        if jpeg and img.file_format != "JPEG":
            img.file_format = "JPEG"
        img.pack()
        out.append((img.name, img.size[0], img.size[1]))
    return out


# --- rigid alignment (high-res onto the rigged remesh) ------------------------------------------

def sample_points(obj, count: int) -> np.ndarray:
    """Deterministic even subsample of a mesh's world-space vertices."""
    verts = obj.data.vertices
    step = max(1, len(verts) // count)
    mw = obj.matrix_world
    return np.array([[c for c in (mw @ verts[i].co)] for i in range(0, len(verts), step)], dtype=float)


def kabsch(src: np.ndarray, dst: np.ndarray) -> Matrix:
    """Rigid transform (rotation + translation) mapping src onto dst."""
    cs, cd = src.mean(axis=0), dst.mean(axis=0)
    u, _, vt = np.linalg.svd((src - cs).T @ (dst - cd))
    d = np.sign(np.linalg.det(vt.T @ u.T))
    r = vt.T @ np.diag([1.0, 1.0, d]) @ u.T
    m = Matrix.Identity(4)
    for i in range(3):
        for j in range(3):
            m[i][j] = float(r[i][j])
    m.translation = Vector(cd - r @ cs)
    return m


def icp(src: np.ndarray, dst: np.ndarray, iterations: int = 20) -> tuple:
    """Rigid ICP of src onto dst. Returns (matrix, rms) in the units of the points."""
    from mathutils.kdtree import KDTree

    tree = KDTree(len(dst))
    for i, p in enumerate(dst):
        tree.insert(Vector((float(p[0]), float(p[1]), float(p[2]))), i)
    tree.balance()
    pts = np.array(src, dtype=float)
    total = Matrix.Identity(4)
    for _ in range(iterations):
        pairs = [tree.find(Vector((float(p[0]), float(p[1]), float(p[2])))) for p in pts]
        step = kabsch(pts, np.array([dst[i] for _, i, _ in pairs]))
        total = step @ total
        pts = np.array([[c for c in (step @ Vector((float(p[0]), float(p[1]), float(p[2]))))]
                        for p in pts])
    rms = float(np.sqrt(np.mean(np.square([d for _, _, d in
                                           (tree.find(Vector((float(p[0]), float(p[1]), float(p[2]))))
                                            for p in pts)]))))
    return total, rms


def surface_rms(src: np.ndarray, dst_obj, count: int = 6000) -> float:
    """RMS distance from src points to the nearest point on dst_obj's surface."""
    from mathutils.kdtree import KDTree

    dst = sample_points(dst_obj, count)
    tree = KDTree(len(dst))
    for i, p in enumerate(dst):
        tree.insert(Vector((float(p[0]), float(p[1]), float(p[2]))), i)
    tree.balance()
    d = [tree.find(Vector((float(p[0]), float(p[1]), float(p[2]))))[2] for p in src]
    return float(np.sqrt(np.mean(np.square(d))))


# --- skin weights --------------------------------------------------------------------------------

def transfer_weights(src_obj, dst_obj) -> int:
    """Copy vertex groups from src_obj onto dst_obj (nearest face interpolated) and apply.

    Used everywhere instead of heat weighting: the Tripo shells are not reliably manifold, so
    `parent_set(ARMATURE_AUTO)` fails on them (lead note, monster-assets)."""
    for vg in list(dst_obj.vertex_groups):
        dst_obj.vertex_groups.remove(vg)
    for vg in src_obj.vertex_groups:
        dst_obj.vertex_groups.new(name=vg.name)
    mod = dst_obj.modifiers.new("xfer", "DATA_TRANSFER")
    mod.object = src_obj
    mod.use_vert_data = True
    mod.data_types_verts = {"VGROUP_WEIGHTS"}
    # Blender 5 renamed "nearest face interpolated" to POLYINTERP_NEAREST
    mod.vert_mapping = "POLYINTERP_NEAREST"
    mod.mix_mode = "REPLACE"
    mod.mix_factor = 1.0
    bpy.context.view_layer.objects.active = dst_obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return len(dst_obj.vertex_groups)


def voxel_proxy(obj, voxel_size: float, name: str):
    """A manifold copy of `obj` via voxel remesh — the surface heat weighting CAN solve.

    UVs and materials are lost on purpose: the proxy only exists to carry skin weights."""
    me = obj.data.copy()
    proxy = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(proxy)
    proxy.matrix_world = obj.matrix_world.copy()
    proxy.data.remesh_voxel_size = voxel_size
    proxy.data.remesh_voxel_adaptivity = 0.0
    bpy.context.view_layer.objects.active = proxy
    proxy.select_set(True)
    bpy.ops.object.voxel_remesh()
    proxy.select_set(False)
    return proxy


def heat_weight(mesh_obj, arm) -> bool:
    """Blender automatic (heat) weights. Only call this on a manifold proxy. Returns success."""
    bpy.ops.object.select_all(action="DESELECT")
    mesh_obj.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    try:
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    except RuntimeError as exc:
        print("HEAT FAIL %s: %s" % (mesh_obj.name, exc))
        return False
    return len(mesh_obj.vertex_groups) > 0


# --- clips --------------------------------------------------------------------------------------

#: The Tripo text motions share their opening words and Blender truncates the rest to fit 63 bytes,
#: so this prefix plus the .00N de-duplication suffix is what tells them apart.
NAME_PREFIX = 40


def _jobs() -> dict:
    import json
    with open(os.path.join(TRIPO, "jobs.json")) as fh:
        return json.load(fh)


def motions_table(monster: str) -> dict:
    """data/monster_motions/<type>.json: {'presets': {id: clip}, 'motions': [[id, secs, prompt]]}."""
    import json
    path = os.path.join(ROOT, "data", "monster_motions", "%s.json" % monster)
    if not os.path.exists(path):
        return {"presets": {}, "motions": []}
    with open(path) as fh:
        return json.load(fh)


def source_clip_ids(monster: str) -> list:
    """The ordered clip ids Tripo exported, straight from the job record."""
    job = _jobs().get("mon_%s" % monster, {})
    for path, info in (job.get("exports") or {}).items():
        if path.endswith("rigged.glb"):
            return list(info.get("anims") or [])
    return list(job.get("anims") or [])


def action_fcurves(action) -> list:
    """Blender 5 slotted actions keep their fcurves in a channelbag, not on the action."""
    try:
        return list(action.fcurves)
    except AttributeError:
        out = []
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    out.extend(bag.fcurves)
        return out


def clip_seconds(action) -> float:
    """A clip's length in seconds, at the scene's frame rate.

    `mon_anims.bake_fps` sets that rate to 30 to match Godot's importer, so this must read it rather
    than assume: a hard-coded 24 reported every clip 25 % short, and the rig JSON's lengths are what
    `MonsterPlayback` holds a one-shot action open for."""
    lo, hi = action.frame_range
    return (hi - lo) / float(bpy.context.scene.render.fps)


def imported_actions() -> dict:
    """name -> action for every action in the file."""
    return {a.name: a for a in bpy.data.actions}


def match_source_clips(monster: str, actions: dict) -> dict:
    """Map our clip ids onto the imported action names.

    Presets match by the name in `motions_table['presets']`. The Tripo text motions all share their
    first 40 characters and Blender truncates the rest to fit 63 bytes with a `.00N` de-duplication
    suffix, so they are matched by that shared prefix and ordered by suffix — which is the order of
    `source_clip_ids`. Every match is checked against the requested duration."""
    table = motions_table(monster)
    presets = table.get("presets") or {}
    motions = {m[0]: (float(m[1]), m[2]) for m in (table.get("motions") or [])}
    text_actions = []
    if motions:
        prefix = next(iter(motions.values()))[1][:NAME_PREFIX]
        text_actions = sorted(
            ((_suffix_number(name), a) for name, a in actions.items() if name.startswith(prefix)),
            key=lambda pair: pair[0])
        text_actions = [a for _, a in text_actions]
    out, index = {}, 0
    for src_id in source_clip_ids(monster):
        action = None
        if src_id in presets:
            action = actions.get(presets[src_id]) or next(
                (a for n, a in actions.items() if n.rsplit(":", 1)[-1] == presets[src_id]), None)
        elif src_id in motions:
            action = text_actions[index] if index < len(text_actions) else None
            index += 1
        else:
            # presets arrive as `preset:<rig>:<name>` (e.g. preset:quadruped:walk)
            action = actions.get(src_id) or next(
                (a for n, a in actions.items() if n.rsplit(":", 1)[-1] == src_id), None)
        if action is None:
            print("CLIP MISS %s: no action for source id '%s'" % (monster, src_id))
            continue
        want = motions.get(src_id, (0.0, ""))[0]
        got = clip_seconds(action)
        if want > 0.0 and abs(got - want) / want > 0.12:
            print("CLIP WARN %s/%s: %.2fs but the job asked for %.2fs" % (monster, src_id, got, want))
        out[src_id] = action
    return out


def _suffix_number(name: str) -> int:
    """0 for an unsuffixed action, N for `....00N` (Blender's duplicate-name suffix)."""
    tail = name.rsplit(".", 1)[-1]
    return int(tail) if tail.isdigit() else 0


# --- export -------------------------------------------------------------------------------------

#: Blender's glTF "optimize animation size" folds a *constant* animated channel into the node's rest
#: transform and then still writes the channel, so a clip whose root offset is the same in every
#: frame gets the offset twice: the ripper's idle came back 0.85 m below the floor instead of on it
#: (lead r5 item 3). Every ground-locked clip has a nearly constant root offset, so the optimisation
#: has to go; `mon_ground` writes dense keys anyway.
OPTIMIZE_ANIM = False
#: Never bake the animation onto the scene's integer frame grid: `mon_ground` keys the root at
#: 30 Hz against a 24 fps scene, and sampling throws every one of those sub-frame keys away.
FORCE_SAMPLING = False


def export_glb(path: str, objects: list, jpeg_quality: int = 88, animations: bool = True) -> str:
    """glTF export with the project settings (CONTRACTS §2), textures re-encoded as JPEG.

    Animation size optimisation is off and forced sampling is off. Sampling is the default, and it
    bakes every track onto the scene's integer frame grid — which silently throws away the ground
    lock, because `mon_ground` keys the root at 30 Hz against a 24 fps scene and every one of its
    sub-frame keys is resampled away. The shipped clip then carries the lock only at 24 Hz while the
    pose it has to correct moves faster than that, and the build's own correction loop chases a
    residual it can never close (juggernaut `ground_slam`: 1.22 -> 0.88 -> 0.73 -> 0.63 m over four
    passes). Exporting the authored keys keeps the fractional times, and glTF carries them exactly.
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_set(False)
        obj.select_set(True)
    args = dict(use_selection=True, export_apply=True, export_yup=True, export_tangents=True,
                export_cameras=False, export_lights=False, export_extras=True,
                export_image_format="JPEG", export_jpeg_quality=jpeg_quality, export_texcoords=True,
                export_normals=True, export_materials="EXPORT")
    if animations:
        args.update(export_optimize_animation_size=OPTIMIZE_ANIM,
                    export_optimize_animation_keep_anim_armature=False,
                    export_optimize_animation_keep_anim_object=False,
                    export_force_sampling=FORCE_SAMPLING)
    os.makedirs(TMP, exist_ok=True)
    tmp = os.path.join(TMP, "%d_%s" % (os.getpid(), os.path.basename(path)))
    bpy.ops.export_scene.gltf(filepath=tmp, export_format="GLB", **args)
    os.replace(tmp, path)
    print("EXPORT %s (%.1f MB)" % (path, os.path.getsize(path) / 1e6))
    return path


def report(label: str, mesh_obj, arm=None, clips: dict = None) -> None:
    """One block of the numbers the brief asks build_all.py to print."""
    verts = len(mesh_obj.data.vertices)
    print("REPORT %-11s tris %7d verts %7d bones %3d clips %2d" % (
        label, tri_count(mesh_obj), verts, len(arm.data.bones) if arm else 0,
        len(clips or {})))
    for cid in sorted(clips or {}):
        print("    clip %-14s %.2fs" % (cid, clip_seconds(clips[cid])))


def posed_extent(mesh_obj, arm, action, frame: int) -> float:
    """Largest world-space extent of the mesh with `action` evaluated at `frame`.

    A rigged mesh that explodes (double skinning, a bad weight transfer) is obvious here, and it is
    cheaper to catch in the build than in a screenshot."""
    data = arm.animation_data_create()
    data.action = action
    if hasattr(action, "slots") and len(action.slots):
        data.action_slot = action.slots[0]
    bpy.context.scene.frame_set(frame)
    deps = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh_obj.evaluated_get(deps).to_mesh()
    mw = mesh_obj.matrix_world
    pts = [mw @ v.co for v in evaluated.vertices]
    span = (max(p.x for p in pts) - min(p.x for p in pts),
            max(p.y for p in pts) - min(p.y for p in pts),
            max(p.z for p in pts) - min(p.z for p in pts))
    mesh_obj.evaluated_get(deps).to_mesh_clear()
    data.action = None
    bpy.context.scene.frame_set(0)
    return max(span)


def check_skin(label: str, mesh_obj, arm, clips: dict, limit: float = 1.6) -> dict:
    """Every clip must keep the mesh inside `limit` x its rest size at its most extreme frame."""
    lo, hi = mesh_bounds(mesh_obj)
    rest = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
    worst = {}
    for clip_id, action in clips.items():
        start, end = action.frame_range
        frames = sorted({int(start), int((start + end) * 0.5), int(end)})
        extent = max(posed_extent(mesh_obj, arm, action, f) for f in frames)
        worst[clip_id] = round(extent / max(rest, 1e-6), 3)
        if extent > rest * limit:
            print("SKIN FAIL %s/%s: posed extent %.2f m against a rest size of %.2f m"
                  % (label, clip_id, extent, rest))
    print("SKIN %-11s rest %.2f m, worst stretch ratio %.2f (%s)"
          % (label, rest, max(worst.values()) if worst else 1.0,
             max(worst, key=worst.get) if worst else "-"))
    return worst



