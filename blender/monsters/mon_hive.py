"""The hive spire objective: three damage states plus a collision proxy (monster-assets).

The hive is static (60 m, SPEC §8 "destroy 3 Hive Spires"), so there is no rig — but the player has
to watch it come apart, so it ships three meshes in one GLB:
  * `Hive`           intact
  * `HiveCracked`    pods shrunk into the shell, glow dimmed (the Godot side scales emission)
  * `HiveDestroyed`  a collapsed stump
  * `HiveCollision`  a convex hull, for the static body the flow unit puts on it

The pods are found the same way the weak points are: through the acid mask in the albedo.
"""
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

from monsters import mon_build, mon_emit, mon_lib, mon_types

COLLISION_TRIS = 240
#: how far the cracked pods shrink into the shell, and how much shorter the stump is
POD_SHRINK = 0.78
STUMP_KEEP = 0.42
STUMP_SQUASH = 0.55
#: how far the cap of the destroyed stump sinks below the break, as a fraction of the spire height
STUMP_CAP_SINK = 0.012
#: fill passes: the source spire is not perfectly manifold, so one pass can leave a gap
CAP_PASSES = 4
#: the glowing bulbs `flow` puts its four pod Hurtboxes on (lead r3). Clustered from the acid mask
#: with a wider radius and a higher face floor than a weak point, so the veins do not claim a socket.
POD_COUNT = 4
POD_RADIUS_FRAC = 0.18
POD_MIN_FACES = 40
#: how far up the trunk a pod has to be. The spire's acid mask also glows where the roots meet the
#: rubble; a pod socket at the player's feet is not a targetable weak point (flow's own rule).
POD_MIN_HEIGHT = 0.15


def pod_sockets(body, acid: np.ndarray, height: float) -> list:
    """The four glowing bulbs, as world positions: the biggest acid clusters that sit high enough
    up the trunk to be shot at, lowest first so `pod_0..3` read bottom to top."""
    found = mon_emit.cluster_mask(body, acid, radius_frac=POD_RADIUS_FRAC, max_points=10,
                                  min_faces=POD_MIN_FACES)
    high = [p for p in found if p["pos"][2] >= height * POD_MIN_HEIGHT]
    high.sort(key=lambda p: -p["faces"])
    return sorted(high[:POD_COUNT], key=lambda p: p["pos"][2])


def pod_mask(body, clusters: list, path: str) -> dict:
    """Write `<hive>_pods.png`: one RGBA channel per pod, the UV coverage of that bulb dilated so
    the shader can boost it and switch it off without a hard edge (lead look r1, fix 3)."""
    size = mon_types.POD_MASK_PX
    chans = [mon_emit.dilate(mon_emit.rasterize_faces(body, c["face_idx"], size),
                             mon_types.POD_MASK_DILATE) for c in clusters[:4]]
    while len(chans) < 4:
        chans.append(np.zeros((size, size), dtype=np.float32))
    mon_emit.write_mask_png(path, chans)
    return {"channels": len(clusters), "cover": [round(float(c.mean()), 5) for c in chans]}


def _duplicate(mesh, name: str):
    me = mesh.data.copy()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    obj.matrix_world = mesh.matrix_world.copy()
    if mesh.data.materials:
        obj.data.materials.clear()
        obj.data.materials.append(mesh.data.materials[0])
    return obj


def _acid_faces(mesh, acid: np.ndarray) -> np.ndarray:
    """Indices of the faces whose UV centroid lands on a glowing pod."""
    scores = mon_emit._face_uv_scores(mesh, acid)
    return np.nonzero(scores > 0.45)[0]


def _shrink_pods(mesh, acid: np.ndarray) -> dict:
    """Pull the glowing pods in toward their own centroid so the silhouette reads as 'cracked'."""
    me = mesh.data
    faces = _acid_faces(mesh, acid)
    if len(faces) < 12:
        return {"pods": 0, "verts": 0}
    centres = np.array([[c for c in (mesh.matrix_world @ me.polygons[i].center)] for i in faces])
    size = float(np.linalg.norm(centres.max(axis=0) - centres.min(axis=0)))
    radius = max(size * 0.16, 1e-3)
    taken = np.zeros(len(faces), dtype=bool)
    moved = set()
    for seed in range(len(faces)):
        if taken[seed]:
            continue
        near = np.nonzero(np.linalg.norm(centres - centres[seed], axis=1) <= radius)[0]
        near = near[~taken[near]]
        if len(near) < 6:
            taken[seed] = True
            continue
        hub = centres[near].mean(axis=0)
        for f in near:
            for vi in me.polygons[faces[f]].vertices:
                if vi in moved:
                    continue
                co = mesh.matrix_world @ me.vertices[vi].co
                me.vertices[vi].co = mesh.matrix_world.inverted() @ (
                    Vector(hub) + (co - Vector(hub)) * POD_SHRINK)
                moved.add(vi)
        taken[near] = True
    return {"pods": int(taken.sum()), "verts": len(moved)}


def _interior_material():
    """A near-black, rough material for the inside of the destroyed stump (lead r5 item 4)."""
    mat = bpy.data.materials.get("HiveInterior") or bpy.data.materials.new("HiveInterior")
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        raise RuntimeError("mon_hive: no Principled BSDF in the interior material")
    bsdf.inputs["Base Color"].default_value = (0.016, 0.020, 0.026, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.92
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def _cap(bm, cut_local: float, sink: float, slot: int) -> int:
    """Close the hole the collapse left at the top of the stump and dish it inward.

    The player mostly sees hives from above (they stand on the +32/+80/+144 tiers), and the broken
    top was an 81 m-perimeter hole with back-faced inner walls: from above you looked straight through
    the stump to the ground (lead r5 item 4). The cap gets the near-black interior material, so what
    reads through the break is a dark recess rather than the deck below."""
    total = 0
    # One pass leaves the odd gap behind: the source spire is not perfectly manifold, so the delete
    # can leave several boundary loops and `holes_fill` closes the easy ones first. Re-run until the
    # shell is closed (probe_mesh's gate is "largest hole < 1 m").
    for _ in range(CAP_PASSES):
        boundary = [e for e in bm.edges if len(e.link_faces) < 2]
        if not boundary:
            break
        faces = bmesh.ops.holes_fill(bm, edges=boundary, sides=0).get("faces", [])
        if not faces:
            faces = bmesh.ops.triangle_fill(bm, use_beauty=True, edges=boundary).get("faces", [])
        if not faces:
            break
        for vert in {v for face in faces for v in face.verts}:
            vert.co.z = min(vert.co.z, cut_local) - sink
        faces = [f for face in faces
                 for f in bmesh.ops.triangulate(bm, faces=[face]).get("faces", [face])]
        for face in faces:
            face.material_index = slot
        total += len(faces)
    if total == 0:
        raise RuntimeError("mon_hive: could not cap the destroyed stump")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return total


def _collapse(mesh) -> dict:
    """Keep the bottom of the spire, squash it into a stump and cap the broken top."""
    me = mesh.data
    lo, hi = mon_lib.mesh_bounds(mesh)
    cut = lo.z + STUMP_KEEP * (hi.z - lo.z)
    mw = mesh.matrix_world
    doomed = [v.index for v in me.vertices if (mw @ v.co).z > cut]
    interior = _interior_material()
    if interior.name not in [m.name for m in me.materials if m]:
        me.materials.append(interior)
    slot = [m.name for m in me.materials].index(interior.name)
    cut_local = (mw.inverted() @ Vector((0.0, 0.0, cut))).z
    sink = STUMP_CAP_SINK * (hi.z - lo.z)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in doomed], context="VERTS")
    capped = _cap(bm, cut_local, sink, slot)
    bm.to_mesh(me)
    bm.free()
    me.transform(Matrix.Diagonal((1.06, 1.06, STUMP_SQUASH, 1.0)))
    marked = sum(1 for poly in me.polygons if poly.material_index == slot)
    return {"capped_faces": capped, "interior_faces": marked}


def _convex(mesh) -> object:
    proxy = _duplicate(mesh, "HiveCollision")
    # only the proxy may be in edit mode: object.mode_set(EDIT) enters edit mode on every selected
    # mesh, and convex_hull would then rewrite the intact hive too
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = proxy
    proxy.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.convex_hull()
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    mon_lib.decimate(proxy, COLLISION_TRIS)
    proxy.data.materials.clear()
    return proxy


def build_hive() -> dict:
    """Intact + cracked + destroyed + collision, in one GLB."""
    monster = "hive"
    objs = mon_lib.load_glb(mon_lib.tripo_path(monster, "model.glb"))
    body = mon_lib.only_mesh(objs, monster)
    body.name = "Hive"
    tris = mon_lib.decimate(body, mon_types.TRIS[monster][0])
    print("HIVE decimate -> %d tris" % tris)
    scale = mon_build.place(body, None, mon_types.YAW[monster], mon_types.SIZES[monster])
    mat = body.data.materials[0]
    mask, acid, violet = mon_emit.build_mask(mat, monster)
    mon_emit.wire_emission(mat, mask)
    mon_build.MEDIAN_LUMA[monster] = mon_emit.median_luma(body, mat)
    print("LUMA %-11s median %.4f -> albedo gain %.3f"
          % (monster, mon_build.MEDIAN_LUMA[monster],
             mon_build.look_table(monster, monster)["albedo_gain"]))
    weak = mon_emit.find_weak_points(body, violet)
    pod_marks = pod_sockets(body, acid, mon_types.SIZES[monster]["m"])
    print("HIVE pod sockets %d %s" % (len(pod_marks),
                                      [[round(c, 1) for c in p["pos"]] for p in pod_marks]))
    pods_png = os.path.join(mon_lib.OUT_DIR, monster, "%s_pods.png" % monster)
    pod_cover = pod_mask(body, pod_marks, pods_png)

    open_edges = round(mon_lib.check_welded(monster, body), 4)

    cracked = _duplicate(body, "HiveCracked")
    pods = _shrink_pods(cracked, acid)
    destroyed = _duplicate(body, "HiveDestroyed")
    collapse = _collapse(destroyed)
    collision = _convex(body)
    albedo_px, other_px = mon_types.TEX[monster]
    mon_lib.resize_images(albedo_px, only={mon_emit.albedo_image(mat).name})
    mon_lib.resize_images(other_px, only=None)

    path = os.path.join(mon_lib.OUT_DIR, monster, "%s.glb" % monster)
    objects = [body, cracked, destroyed, collision]
    mon_lib.export_glb(path, objects, animations=False)
    lo, hi = mon_lib.mesh_bounds(body)
    sockets = mon_build.socket_table(monster, None, body, weak)
    for i, pod in enumerate(pod_marks):
        sockets["pod_%d" % i] = {"bone": "", "pos": mon_build.to_godot(pod["pos"]),
                                 "score": pod["score"], "faces": pod["faces"]}
    report = {"path": path, "hires_tris": tris, "scale": round(scale, 4),
              "lod0_tris": mon_lib.tri_count(body), "verts": len(body.data.vertices),
              "bones": 0, "clips": {}, "pods": pods, "weak_points": weak,
              "pod_sockets": len(pod_marks), "pod_cover": pod_cover,
              "open_edges": open_edges, "collapse": collapse,
              "states": {o.name: mon_lib.tri_count(o) for o in objects},
              "size": mon_build._size_report(monster, lo, hi)}
    mon_build.write_rig_json(monster, {
        "type": monster, "size": report["size"], "lod_dist_m": 0.0,
        "shadow": True, "grounded": True, "static": True, "bones": [],
        "look": mon_build.look_table(monster, monster),
        "pod_mask": "res://enemies/models/%s/%s_pods.png" % (monster, monster),
        "pod_cover": pod_cover,
        "states": {"intact": "Hive", "cracked": "HiveCracked", "destroyed": "HiveDestroyed",
                   "collision": "HiveCollision"},
        "sockets": sockets,
        "locomotion": {}, "gait": {}, "actions": {}, "clips": {},
    })
    print("REPORT hive        tris %7d states %s" % (report["lod0_tris"], report["states"]))
    return report
