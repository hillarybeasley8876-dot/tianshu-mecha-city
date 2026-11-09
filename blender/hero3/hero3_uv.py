"""Per-bone UV coverage of the exported hero3 body (hero-v3 r7).

    tools/blender.sh run blender/hero3/hero3_uv.py -- [--res=1024] [--out=<dir>]

The emission mask (`hero3_emissive.py`) has to know WHERE on the atlas the visor and the chest vent
live, and the atlas is one 4K sheet of unrelated islands -- a colour rule alone picks up every bronze
screw on the mech. This rasterises, for each bone's vertex group, the UV area its faces cover, so the
mask can say "amber inside the Head island" instead of "amber anywhere".

Writes `<out>/uv_<bone>.png` (white = this bone's faces) and `<out>/uv_regions.json`.
"""
import argparse
import json
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/hero3"))
import hero3_lib as H  # noqa: E402

GLB = os.path.join(H.ROOT, "game", "player", "model", "hero3", "hero3.glb")
DEFAULT_OUT = os.path.join(H.ROOT, "tmp", "hero-v3", "uv")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--res", type=int, default=1024)
    p.add_argument("--out", default=DEFAULT_OUT)
    return p.parse_args(argv)


def bone_of_face(mesh, poly) -> int:
    """The single vertex group a face belongs to (the body is rigid: one bone, weight 1)."""
    counts = {}
    for vi in poly.vertices:
        for g in mesh.vertices[vi].groups:
            counts[g.group] = counts.get(g.group, 0) + 1
    if not counts:
        return -1
    return max(counts.items(), key=lambda kv: kv[1])[0]


def raster(uv_tris, res):
    """Fill a res x res mask from (n, 3, 2) UV triangles in [0, 1], image row order."""
    mask = np.zeros((res, res), dtype=np.uint8)
    for tri in uv_tris:
        p = tri.copy()
        p[:, 1] = 1.0 - p[:, 1]           # Blender UVs run bottom-up, the image runs top-down
        p *= res
        lo = np.floor(p.min(0)).astype(int)
        hi = np.ceil(p.max(0)).astype(int)
        x0, y0 = max(lo[0], 0), max(lo[1], 0)
        x1, y1 = min(hi[0] + 1, res), min(hi[1] + 1, res)
        if x1 <= x0 or y1 <= y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        (ax, ay), (bx, by), (cx, cy) = p
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-9:
            continue
        l1 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / den
        l2 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / den
        l3 = 1.0 - l1 - l2
        inside = (l1 >= -1e-4) & (l2 >= -1e-4) & (l3 >= -1e-4)
        mask[y0:y1, x0:x1][inside] = 255
    return mask


def save_png(path, arr):
    img = bpy.data.images.new(os.path.basename(path), width=arr.shape[1], height=arr.shape[0],
                              alpha=False)
    rgba = np.zeros((arr.shape[0], arr.shape[1], 4), dtype=np.float32)
    for c in range(3):
        rgba[..., c] = arr.astype(np.float32) / 255.0
    rgba[..., 3] = 1.0
    img.pixels.foreach_set(rgba[::-1].ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def main() -> None:
    args = parse_args()
    os.makedirs(args.out, exist_ok=True)
    H.load_glb(GLB)
    body = next((o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("Hero3Body")),
                None)
    if body is None:
        raise RuntimeError("hero3_uv: no Hero3Body in %s" % GLB)
    mesh = body.data
    uv = mesh.uv_layers.active.data
    names = {g.index: g.name for g in body.vertex_groups}
    mesh.calc_loop_triangles()
    per_bone = {}
    for tri in mesh.loop_triangles:
        gi = bone_of_face(mesh, mesh.polygons[tri.polygon_index])
        per_bone.setdefault(gi, []).append([uv[i].uv[:] for i in tri.loops])
    regions = {}
    for gi, tris in sorted(per_bone.items()):
        name = names.get(gi, "group%d" % gi)
        arr = np.asarray(tris, dtype=np.float64)
        mask = raster(arr, args.res)
        save_png(os.path.join(args.out, "uv_%s.png" % name), mask)
        flat = arr.reshape(-1, 2)
        regions[name] = {"tris": len(tris),
                         "uv_min": [float(flat[:, 0].min()), float(flat[:, 1].min())],
                         "uv_max": [float(flat[:, 0].max()), float(flat[:, 1].max())],
                         "cover": float((mask > 0).mean())}
        print("UV %-14s %6d tris  cover %.4f  bbox %.3f,%.3f .. %.3f,%.3f"
              % (name, len(tris), regions[name]["cover"], *regions[name]["uv_min"],
                 *regions[name]["uv_max"]))
    with open(os.path.join(args.out, "uv_regions.json"), "w") as fh:
        json.dump({"res": args.res, "bones": regions}, fh, indent=1, sort_keys=True)
    print("WROTE %s (%d bones)" % (args.out, len(regions)))


if __name__ == "__main__":
    main()
