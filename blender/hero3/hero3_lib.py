"""Shared helpers for the hero3 build (hero-v3 unit).

Deterministic: no randomness, no timestamps. Blender Z up, the mech faces +Y (CONTRACTS §2), feet at
z = 0 and 16.0 m to the helm top. Self-contained on purpose -- the hero-v3 pipeline does not import
`blender/hero/**` so a change there can never rewrite the Tianshu build.
"""
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.expanduser("~/m/mecha-city")
TMP = os.path.join(ROOT, "tmp", "hero-v3")
HERO_HEIGHT_M = 16.0
HELPER_MAX_FACES = 200


#: A welded mesh may still have real boundaries (Tripo ships open shells) but a UV seam must never
#: become one: past this fraction of all edges the build says so (lead look r1, item 1).
WELD_GATE = 0.02


def load_glb(rel_path: str) -> list:
    """Import a GLB into the current scene and drop Tripo's untextured helper specks.

    `merge_vertices` matters: glTF splits a vertex at every UV seam, so without it every seam
    arrives as an open boundary. The collapse decimator then pulls the two sides apart (hairline
    cracks that show the inner core through the plate) and `hero3_cap` fills UV-seam loops as if
    they were joint openings. Blender keeps UVs per face corner, so welding costs no UVs."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, rel_path), merge_vertices=True)
    new = [o for o in bpy.data.objects if o not in before]
    for obj in list(new):
        if obj.type == "MESH" and not obj.data.materials and len(obj.data.polygons) < HELPER_MAX_FACES:
            bpy.data.objects.remove(obj, do_unlink=True)
            new.remove(obj)
    for obj in new:
        if obj.type == "MESH":
            check_welded(os.path.basename(rel_path) + ":" + obj.name, obj)
    return new


def check_welded(label: str, obj) -> float:
    """Print a mesh's open-edge fraction -- the QA gate for the weld above. Returns the fraction."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    total = len(bm.edges)
    boundary = sum(1 for e in bm.edges if len(e.link_faces) < 2)
    bm.free()
    frac = boundary / max(total, 1)
    print("WELD %-30s %7d open / %7d edges = %5.2f%%%s"
          % (label, boundary, total, 100.0 * frac,
             "  OVER GATE %.0f%%" % (100.0 * WELD_GATE) if frac > WELD_GATE else ""))
    return frac


def only_mesh(objs: list, label: str):
    meshes = [o for o in objs if o.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError("%s: expected 1 mesh, got %d" % (label, len(meshes)))
    return meshes[0]


def tri_count(obj) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def transform_mesh(obj, matrix: Matrix) -> None:
    """Bake a world-space matrix into the mesh data and leave the object at identity."""
    obj.data.transform(matrix @ obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)


def bbox(obj) -> tuple:
    """(lo, hi) world-space corners of a mesh object."""
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    return (Vector([min(p[i] for p in pts) for i in range(3)]),
            Vector([max(p[i] for p in pts) for i in range(3)]))


def centroid(obj) -> Vector:
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    return sum(pts, Vector()) / len(pts)


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


def sample_n(obj, count: int) -> np.ndarray:
    """Exactly `count` world-space vertices, evenly strided (wrapping). Deterministic."""
    verts = obj.data.vertices
    n = len(verts)
    mw = obj.matrix_world
    idx = [(i * n) // count for i in range(count)]
    return np.array([list(mw @ verts[i].co) for i in idx])


def sample_points(obj, count: int) -> np.ndarray:
    """Deterministic even subsample of a mesh's world-space vertices."""
    verts = obj.data.vertices
    step = max(1, len(verts) // count)
    mw = obj.matrix_world
    return np.array([list(mw @ verts[i].co) for i in range(0, len(verts), step)])


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


def similarity(src: np.ndarray, dst: np.ndarray) -> Matrix:
    """Similarity transform (rotation + uniform scale + translation) mapping src onto dst."""
    cs, cd = src.mean(axis=0), dst.mean(axis=0)
    u, s, vt = np.linalg.svd((src - cs).T @ (dst - cd))
    d = np.sign(np.linalg.det(vt.T @ u.T))
    r = vt.T @ np.diag([1.0, 1.0, d]) @ u.T
    var = float(((src - cs) ** 2).sum())
    scale = float((s[0] + s[1] + d * s[2]) / var) if var > 0.0 else 1.0
    m = Matrix.Identity(4)
    for i in range(3):
        for j in range(3):
            m[i][j] = float(r[i][j]) * scale
    m.translation = Vector(cd - scale * (r @ cs))
    return m


def fit_similarity(src: np.ndarray, dst: np.ndarray, iterations: int = 20) -> tuple:
    """Similarity ICP: repeatedly match every src point to its nearest dst point and refit.

    Returns (matrix, rms). Use after a rough bounding-box or yaw seed -- it has no correspondence
    information of its own, so a bad seed converges to a bad fit."""
    tree = kdtree_of(dst)
    pts = src.copy()
    total = Matrix.Identity(4)
    rms = float("inf")
    for _ in range(iterations):
        probe = Vector()
        pairs = np.empty_like(pts)
        dists = np.empty(len(pts))
        for i, p in enumerate(pts):
            probe[0], probe[1], probe[2] = p[0], p[1], p[2]
            _, j, d = tree.find(probe)
            pairs[i] = dst[j]
            dists[i] = d
        step = similarity(pts, pairs)
        total = step @ total
        pts = np.array([list(step @ Vector(p)) for p in pts])
        new_rms = float(np.sqrt((dists ** 2).mean()))
        if abs(rms - new_rms) < 1e-5:
            rms = new_rms
            break
        rms = new_rms
    return total, rms


def seed_from_bbox(src: np.ndarray, dst: np.ndarray) -> Matrix:
    """Rough similarity seed: match the bounding-box centre and the bounding-box diagonal length."""
    cs = (src.min(axis=0) + src.max(axis=0)) / 2.0
    cd = (dst.min(axis=0) + dst.max(axis=0)) / 2.0
    scale = float(np.linalg.norm(dst.max(axis=0) - dst.min(axis=0))
                  / max(np.linalg.norm(src.max(axis=0) - src.min(axis=0)), 1e-9))
    m = Matrix.Identity(4)
    for i in range(3):
        m[i][i] = scale
    m.translation = Vector(cd - scale * cs)
    return m


def kdtree_of(points) -> "object":
    """Balanced KDTree over an (n, 3) array of world-space points."""
    from mathutils.kdtree import KDTree

    tree = KDTree(len(points))
    for i, p in enumerate(points):
        tree.insert(Vector((float(p[0]), float(p[1]), float(p[2]))), i)
    tree.balance()
    return tree


def resize_images(max_px: int, only: set = None) -> list:
    """Downscale the named images so the long side is at most max_px and re-encode them as JPEG."""
    out = []
    for img in bpy.data.images:
        if only is not None and img.name not in only:
            continue
        w, h = img.size
        if max(w, h) > max_px:
            s = max_px / max(w, h)
            img.scale(max(1, int(w * s)), max(1, int(h * s)))
        if img.file_format != "JPEG":
            img.file_format = "JPEG"
        img.pack()
        out.append((img.name, img.size[0], img.size[1]))
    return out


def image_names(obj) -> set:
    """Names of the images a mesh's materials use."""
    names = set()
    for mat in obj.data.materials:
        if mat and mat.use_nodes:
            for node in mat.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image:
                    names.add(node.image.name)
    return names


def export_glb(path: str, objects: list, jpeg_quality: int = 88, animations: bool = True) -> str:
    """glTF export for the hero: JPEG textures, +Y up, tangents, optimisation on."""
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
        args.update(export_optimize_animation_size=True,
                    export_optimize_animation_keep_anim_armature=False,
                    export_optimize_animation_keep_anim_object=False)
    os.makedirs(TMP, exist_ok=True)
    tmp = os.path.join(TMP, "%d_%s" % (os.getpid(), os.path.basename(path)))
    bpy.ops.export_scene.gltf(filepath=tmp, export_format="GLB", **args)
    os.replace(tmp, path)
    print("EXPORT %s (%d objects, %.1f MB)" % (path, len(objects), os.path.getsize(path) / 1e6))
    return path


def yaw(deg: float) -> Matrix:
    return Matrix.Rotation(math.radians(deg), 4, "Z")


def extract_faces(obj, face_indices) -> "bpy.types.Object":
    """A new mesh object holding only the listed faces of `obj`, keeping UVs and material slots.

    Vertices are remapped, so each extracted piece is its own watertight-ish shell with no loose
    geometry from the faces that were left behind."""
    src = bmesh.new()
    src.from_mesh(obj.data)
    src.faces.ensure_lookup_table()
    uv = src.loops.layers.uv.active
    out = bmesh.new()
    out_uv = out.loops.layers.uv.new("UVMap") if uv is not None else None
    vmap = {}
    for fi in face_indices:
        face = src.faces[fi]
        verts = []
        for v in face.verts:
            if v.index not in vmap:
                vmap[v.index] = out.verts.new(v.co)
            verts.append(vmap[v.index])
        try:
            new_face = out.faces.new(verts)
        except ValueError:
            continue                      # duplicate face from a degenerate Tripo polygon
        new_face.material_index = face.material_index
        if uv is not None:
            for dst, s in zip(new_face.loops, face.loops):
                dst[out_uv].uv = s[uv].uv
    out.verts.ensure_lookup_table()
    mesh = bpy.data.meshes.new(obj.name + "_part")
    out.to_mesh(mesh)
    out.free()
    src.free()
    new_obj = bpy.data.objects.new(obj.name + "_part", mesh)
    bpy.context.scene.collection.objects.link(new_obj)
    new_obj.matrix_world = obj.matrix_world.copy()
    for mat in obj.data.materials:
        new_obj.data.materials.append(mat)
    return new_obj


def flat_material(name: str, rgb) -> "bpy.types.Material":
    """A matte debug material (the label sheets render with these)."""
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Roughness"].default_value = 0.55
    return mat


def bm_of(obj) -> bmesh.types.BMesh:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    return bm
