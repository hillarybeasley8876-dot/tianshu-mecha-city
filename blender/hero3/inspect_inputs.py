"""Report the raw shape of the hero3 Tripo inputs (read-only diagnostic).

  tools/blender.sh run blender/hero3/inspect_inputs.py -- [--parts]

Prints, for every mesh object: triangle count, bounding box, materials, image sizes, and the
object-space extents. Used to fix the normalisation constants in `hero3_lib.py` and to sanity-check
that the parts model really is the same image in the same pose.
"""
import os
import sys

sys.path.append(os.path.join(os.path.expanduser("~/m/mecha-city"), "blender", "hero"))
import bpy  # noqa: E402
import hero_lib  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")
SRC_BODY = "art/tripo/hero3_a1/model.glb"
SRC_PARTS = "art/tripo/hero3_a1p/model.glb"


def describe(obj, label: str) -> dict:
    verts = obj.data.vertices
    xs = [v.co.x for v in verts]
    ys = [v.co.y for v in verts]
    zs = [v.co.z for v in verts]
    info = {
        "name": obj.name,
        "tris": hero_lib.tri_count(obj),
        "verts": len(verts),
        "bbox": (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)),
        "size": (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)),
        "materials": [m.name if m else "<none>" for m in obj.data.materials],
        "uv_layers": len(obj.data.uv_layers),
        "images": sorted(hero_lib.prop_images(obj)),
    }
    print("%-8s %-24s tris=%-9d verts=%-8d size=(%.2f, %.2f, %.2f) bbox=(%.2f..%.2f, %.2f..%.2f, "
          "%.2f..%.2f) uvs=%d" % ((label, info["name"], info["tris"], info["verts"]) + info["size"]
                                + info["bbox"] + (info["uv_layers"],)))
    print("         materials=%s images=%s" % (info["materials"], info["images"]))
    return info


def main() -> None:
    want_parts = "--parts" in sys.argv
    body = describe(hero_lib.only_mesh(hero_lib.load_glb(SRC_BODY), "body"), "body")
    for img in bpy.data.images:
        if img.size[0] > 1:
            print("  image %-40s %dx%d %s" % (img.name, img.size[0], img.size[1], img.file_format))
    if not want_parts:
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objs = hero_lib.load_glb(SRC_PARTS)
    meshes = [o for o in objs if o.type == "MESH"]
    meshes.sort(key=lambda o: -hero_lib.tri_count(o))
    print("PARTS: %d mesh objects" % len(meshes))
    for i, obj in enumerate(meshes):
        info = describe(obj, "part%02d" % i)
        _ = info


main()
