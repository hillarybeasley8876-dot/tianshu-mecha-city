"""Process a Tripo prop into a game-ready glb (city-art).

  tools/blender.sh run blender/props/process_prop.py -- --name hovercar_a
  tools/blender.sh run blender/props/process_prop.py -- --all

Steps: import (welded) -> join -> scale to the real-world size -> origin at the base centre -> weld the
UV seams -> decimate to the budget -> resize the texture set -> derive an emissive mask from the albedo
(bright saturated cyan / amber / jade pixels are the light strips) -> export to
game/world/props/meshes/<name>.glb.
"""
import os
import sys
from typing import List, Optional, Tuple

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

from lib import common, export  # noqa: E402
from mesh_repair import (HOLE_FILL_FRACTION, HOLE_FILL_M, WELD_M, fill_holes,  # noqa: E402
                          mesh_bounds, prune_floaters)
from prop_table import prop  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")
OUT_DIR = os.path.join(ROOT, "game", "world", "props", "meshes")
EMISSION_STRENGTH = 2.5
# A closed prop has no boundary edges at all; what is left after welding is genuine open geometry (a
# grille, a thin fin modelled one-sided). Above this share the decimate has torn something.
OPEN_EDGE_GATE = 0.02
# Hue windows (degrees) that count as "this prop's light strips": cyan rails, amber lamps, jade.
EMISSIVE_HUES: Tuple[Tuple[float, float], ...] = ((165.0, 205.0), (20.0, 55.0), (135.0, 165.0))
EMISSIVE_MIN_VALUE = 0.55
EMISSIVE_MIN_SAT = 0.30


def script_args() -> List[str]:
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]


def args(argv: List[str]) -> dict:
    out, pending = {}, None
    for a in argv:
        if a.startswith("--"):
            if pending:
                out[pending] = "true"
            k, _, v = a[2:].partition("=")
            out[k], pending = (v, None) if v else (None, k)
        elif pending:
            out[pending], pending = a, None
    if pending:
        out[pending] = "true"
    return out


def hue_degrees(r: np.ndarray, g: np.ndarray, b: np.ndarray, mx: np.ndarray, mn: np.ndarray) -> np.ndarray:
    d = np.maximum(mx - mn, 1e-6)
    h = np.where(mx == r, (g - b) / d % 6.0, np.where(mx == g, (b - r) / d + 2.0, (r - g) / d + 4.0))
    return h * 60.0


def emissive_mask_from_albedo(tex: int) -> Optional[bpy.types.Image]:
    """Bright, saturated pixels inside the cyan/amber/jade hue windows = the prop's light strips."""
    src = next((i for i in bpy.data.images if i.name.startswith("Color")), None)
    if src is None:
        return None
    # The mask is mostly black, so half the albedo resolution is plenty and keeps the glb small.
    tex = max(min(tex // 2, 512), 128)
    # On a COPY: the datablock found above is the one wired to Base Color, so scaling it in place
    # exports a mask-sized albedo and every prop ships blurry (look review 2026-11-02 item 2).
    src = src.copy()
    src.scale(tex, tex)
    buf = np.empty(tex * tex * 4, dtype=np.float32)
    src.pixels.foreach_get(buf)
    px = buf.reshape(-1, 4)
    r, g, b = px[:, 0], px[:, 1], px[:, 2]
    mx, mn = px[:, :3].max(axis=1), px[:, :3].min(axis=1)
    sat = np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    hue = hue_degrees(r, g, b, mx, mn)
    in_hue = np.zeros(len(px), dtype=bool)
    for lo, hi in EMISSIVE_HUES:
        in_hue |= (hue >= lo) & (hue <= hi)
    hit = in_hue & (sat >= EMISSIVE_MIN_SAT) & (mx >= EMISSIVE_MIN_VALUE)
    out = np.zeros((len(px), 4), dtype=np.float32)
    for ch, chan in enumerate((r, g, b)):
        out[:, ch] = np.where(hit, chan, 0.0)
    out[:, 3] = 1.0
    img = bpy.data.images.new("prop_emissive", tex, tex, alpha=False)
    img.pixels.foreach_set(out.reshape(-1))
    img.pack()
    bpy.data.images.remove(src)  # the working copy, now that the mask is packed
    return img


def resize_textures(tex: int) -> None:
    """Albedo and normal keep the budget size; ORM and the emissive mask go to half of it. The normal
    is what carries panel lines and ribs at 20-40 m, so halving it defeats the point (prop_table's own
    docstring says so); the mask is mostly black and ORM is a multiplier, both tolerate half."""
    for img in bpy.data.images:
        if img.size[0] <= tex:
            continue
        keep = img.name.startswith(("Color", "NormalGL", "prop_albedo"))
        half = tex if keep else max(tex // 2, 256)
        img.scale(half, half)


def build_material(obj: bpy.types.Object) -> None:
    """Rewire the imported material: albedo + ORM (G rough, B metal) + normal + the emissive mask."""
    mat = obj.data.materials[0] if obj.data.materials else bpy.data.materials.new("prop_body")
    mat.name = "prop_body"
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    images = {}
    for img in bpy.data.images:
        images.setdefault(img.name.split("_")[0], img)

    def image_node(img, x, y):
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = img
        node.location = (x, y)
        return node

    if "ORM" in images:
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        sep.location = (-380, -200)
        nt.links.new(image_node(images["ORM"], -620, -200).outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs[2], bsdf.inputs["Metallic"])
    colour = images.get("Color")
    if colour is None:
        return
    mask = emissive_mask_from_albedo(colour.size[0])
    if mask is not None:
        bsdf.inputs["Emission Strength"].default_value = EMISSION_STRENGTH
        nt.links.new(image_node(mask, -620, 200).outputs["Color"], bsdf.inputs["Emission Color"])


def normalise(obj: bpy.types.Object, size_m: float) -> None:
    common.apply_transforms(obj)
    lo, hi = mesh_bounds(obj)
    longest = max(hi - lo)
    if longest > 1e-4:
        s = size_m / longest
        obj.scale = (s, s, s)
        common.apply_transforms(obj)
    # Origin at the base centre so placement code can drop a prop straight onto a surface. The MESH
    # DATA moves and the object keeps an identity transform: `PropScatter` draws the mesh and drops the
    # node, and `common.set_origin()` only parks the offset on the object, where the next
    # `apply_transforms` bakes it straight back (every prop shipped centred and drew half-sunk until
    # 11-03; gate: `tools/citykit/rebase_glb.py --check --set props`).
    lo, hi = mesh_bounds(obj)
    cx = (lo.x + hi.x) * 0.5
    cy = (lo.y + hi.y) * 0.5
    obj.data.transform(Matrix.Translation(-Vector((cx, cy, lo.z))))


def weld(obj: bpy.types.Object, threshold_m: float) -> Tuple[int, float]:
    """Merge vertices that share a position, and report the open-edge share afterwards.

    A Tripo glb splits a vertex at every UV seam and every hard normal, so the mesh is a pile of
    topologically disconnected shells held together by coincidence. The Decimate modifier then treats
    each side of a seam as a free boundary and collapses it independently, which tears the shell open
    along every seam — visible as cracks and flickering backfaces on a decimated prop (monster-assets
    Requests #6).

    Welding by POSITION is safe here because Blender stores UVs per LOOP, not per vertex: the loops
    that survive keep their own UVs, so a seam stays a seam in the texture and stops being one in the
    topology. `threshold_m` is in real metres because this runs after `normalise`.
    """
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=threshold_m)
    bm.verts.index_update()
    edges = len(bm.edges)
    open_edges = sum(1 for e in bm.edges if len(e.link_faces) < 2)
    bm.to_mesh(me)
    bm.free()
    me.update()
    return before - len(me.vertices), (open_edges / edges if edges else 0.0)


def decimate(obj: bpy.types.Object, budget: int) -> int:
    tris = common.tri_count(obj)
    if tris <= budget:
        return tris
    mod = obj.modifiers.new("decimate", "DECIMATE")
    mod.ratio = budget / float(tris)
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return common.tri_count(obj)


def process(name: str) -> None:
    spec = prop(name)
    src = os.path.join(ROOT, "art", "tripo", "prop_" + name, "model.glb")
    if not os.path.exists(src):
        print("PROP SKIP %s (no model.glb)" % name)
        return
    common.reset()
    # `merge_vertices` first (exact duplicates, cheapest), then the positional weld below (seams).
    bpy.ops.import_scene.gltf(filepath=src, merge_vertices=True)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        print("PROP FAIL %s (no meshes)" % name)
        return
    obj = common.join(meshes, name) if len(meshes) > 1 else meshes[0]
    obj.name = name
    resize_textures(spec.tex)
    normalise(obj, spec.size_m)
    merged, open_before = weld(obj, WELD_M)
    floaters = prune_floaters(obj)
    cap = min(HOLE_FILL_M, HOLE_FILL_FRACTION * spec.size_m)
    patched, closed = fill_holes(obj, cap)
    tris = decimate(obj, spec.budget)
    _, open_after = weld(obj, WELD_M)
    patched2, closed2 = fill_holes(obj, cap)
    patched += patched2
    closed += closed2
    if open_after > OPEN_EDGE_GATE:
        print("PROP WELD %-16s open edges %.1f%% > %.0f%% gate after decimate"
              % (name, open_after * 100.0, OPEN_EDGE_GATE * 100.0))
    common.smooth(obj, angle_deg=45.0)
    build_material(obj)
    out = export.export_glb(os.path.join(OUT_DIR, name + ".glb"), objects=[obj], jpeg_quality=90)
    kb = os.path.getsize(out) / 1024.0
    print("PROP OK %-16s tris=%-6d budget=%-6d size=%.1fm tex=%d weld=-%d open=%.1f%%>%.1f%%"
          " floaters=-%d filled=%d(%.2fm) file=%.0fkB"
          % (name, tris, spec.budget, spec.size_m, spec.tex, merged,
             open_before * 100.0, open_after * 100.0, floaters, patched, closed, kb))


def main() -> None:
    a = args(script_args())
    if a.get("all"):
        base = os.path.join(ROOT, "art", "tripo")
        names = sorted(d[5:] for d in os.listdir(base) if d.startswith("prop_"))
    else:
        names = [a.get("name", "hovercar_a")]
    for n in names:
        process(n)


if __name__ == "__main__":
    main()
