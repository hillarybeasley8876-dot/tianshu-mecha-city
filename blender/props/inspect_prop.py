"""Inspect one Tripo prop .glb: meshes, triangle counts, materials, texture sizes (city-art).

  tools/blender.sh run blender/props/inspect_prop.py -- --name hovercar_a
"""
import os
import sys

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))

import bpy  # noqa: E402

from lib import common  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")


def args(argv):
    """Parse `--key value` and `--key=value` from the args after the script (the wrapper eats `--`)."""
    out = {}
    pending = None
    for a in argv:
        if a.startswith("--"):
            if pending:
                out[pending] = "true"
            k, _, v = a[2:].partition("=")
            if v:
                out[k] = v
                pending = None
            else:
                pending = k
        elif pending:
            out[pending] = a
            pending = None
    if pending:
        out[pending] = "true"
    return out


def script_args():
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]


def main() -> None:
    a = args(script_args())
    name = a.get("name", "hovercar_a")
    path = os.path.join(ROOT, "art", "tripo", "prop_" + name, "model.glb")
    common.reset()
    bpy.ops.import_scene.gltf(filepath=path)
    tris = 0
    print("PROP %s" % name)
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        tris += common.tri_count(obj)
        print("  mesh %-28s tris=%-7d verts=%-7d dim=%.2f x %.2f x %.2f" %
              (obj.name, common.tri_count(obj), len(obj.data.vertices),
               obj.dimensions.x, obj.dimensions.y, obj.dimensions.z))
    print("  total tris=%d" % tris)
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        emission = 0.0
        if bsdf is not None:
            emission = bsdf.inputs["Emission Strength"].default_value
        print("  mat  %-28s emission=%.2f" % (mat.name, emission))
    for img in bpy.data.images:
        print("  img  %-28s %dx%d" % (img.name, img.size[0], img.size[1]))


if __name__ == "__main__":
    main()
