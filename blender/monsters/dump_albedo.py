"""Dump the monster albedo maps and concept thumbnails into one contact sheet (monster-assets).

    tools/blender.sh run blender/monsters/dump_albedo.py
    ffmpeg ... (see the printed hint)

Writes ~/m/mecha-city/tmp/monster-assets/albedo_<type>.png at 512 px so the emissive-mask thresholds
can be chosen against the real texture instead of guessed.
"""
import os
import sys

import bpy

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")
OUT = os.path.join(ROOT, "tmp", "monster-assets")
TYPES = ["ripper", "mantis", "spitter", "harrier", "juggernaut", "titan", "hive"]


def basecolor_image(material) -> bpy.types.Image:
    if material is None or not material.node_tree:
        return None
    for node in material.node_tree.nodes:
        if node.type != "TEX_IMAGE" or node.image is None:
            continue
        name = node.image.name.lower()
        if "color" in name or "basecolor" in name or "diffuse" in name:
            return node.image
    return None


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for t in TYPES:
        common.reset()
        for name in ("rigged.glb", "model.glb"):
            path = os.path.join(ROOT, "art", "tripo", "mon_%s" % t, name)
            if os.path.exists(path):
                bpy.ops.import_scene.gltf(filepath=path)
                src = name
                break
        mesh = next((o for o in bpy.data.objects if o.type == "MESH" and o.data.materials), None)
        img = basecolor_image(mesh.data.materials[0]) if mesh else None
        if img is None:
            print("ALBEDO %s: none" % t)
            continue
        copy = img.copy()
        copy.scale(512, 512)
        copy.filepath_raw = os.path.join(OUT, "albedo_%s.png" % t)
        copy.file_format = "PNG"
        copy.save()
        print("ALBEDO %-11s <- %s %s" % (t, src, img.name))


main()
