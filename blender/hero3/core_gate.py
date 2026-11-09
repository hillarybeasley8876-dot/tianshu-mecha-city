"""The core-exposure gate (hero-v3, lead review r1).

    tools/blender.sh run blender/hero3/core_gate.py -- --mode=render        # magenta debug GLB
    python3 blender/hero3/core_gate.py --count captures/blender/hero3_core_*.jpg

The inner volumes exist to be seen only through a joint opening. A grey tube standing proud of the
armour is the exact failure the lead stopped the line over, and it is invisible in a triangle count:
so the cores are re-materialised in pure magenta (#FF00FF, emissive, unlit), the eight preview views
are rendered, and the magenta pixels are counted.

  REST pose        : 0 px in every view. Anything else is a core outside its plate.
  STRESS poses     : report per view; only a joint gap may show, <= 0.3 % of the mech's pixels.
"""
import argparse
import os
import sys

## `bpy` and the project modules are imported inside the render path only: `--count` runs in plain
## python3 (no Blender) so the pixel gate can be re-run without opening the app.
ROOT = os.path.expanduser("~/m/mecha-city")
SRC = "game/player/model/hero3/hero3.glb"
MAGENTA = (1.0, 0.0, 1.0)
## a pixel counts as magenta when red and blue are high and green is low -- tolerant of the JPEG
## ringing the preview tool's re-encode leaves around a hard edge
MAGENTA_MIN_RB = 150
MAGENTA_MAX_G = 90
CORE_PREFIX = "H3C_"
STRESS_FRACTION = 0.003


def magenta_material():
    import bpy

    mat = bpy.data.materials.get("CoreDebug")
    if mat is not None:
        return mat
    mat = bpy.data.materials.new("CoreDebug")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    for node in list(nodes):
        if node.type != "OUTPUT_MATERIAL":
            nodes.remove(node)
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = MAGENTA + (1.0,)
    emit.inputs["Strength"].default_value = 1.0
    out = next(n for n in nodes if n.type == "OUTPUT_MATERIAL")
    mat.node_tree.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    return mat


def core_objects(roots) -> list:
    """The cores, identified by the material the build gave them (they are joined into Hero3Body in
    the shipped GLB, so the per-object marker is gone by the time it is exported).

    Takes a LIST of roots: the rig-stage GLB has no armature yet, so every plate is its own root and
    walking a single one finds nothing."""
    if not isinstance(roots, (list, tuple)):
        roots = [roots]
    out = []
    stack = list(roots)
    seen = set()
    while stack:
        node = stack.pop()
        if node in seen:
            continue
        seen.add(node)
        if node.type == "MESH" and node.data.materials:
            names = [m.name if m else "" for m in node.data.materials]
            if any(n.startswith(CORE_PREFIX) or n == "Hero3Core" for n in names):
                out.append((node, names))
        stack.extend(node.children)
    return out


def paint(roots, out_path: str) -> None:
    """Give the core material slots the magenta debug material and export."""
    import bpy

    import hero3_lib as H

    found = core_objects(roots)
    if not found:
        raise RuntimeError("core_gate: no mesh carries the core material")
    meshes = []
    for node, names in found:
        slots = [i for i, n in enumerate(names) if n.startswith(CORE_PREFIX) or n == "Hero3Core"]
        print("CORE-GATE %s has the core material in slots %s" % (node.name, slots))
        bpy.context.view_layer.objects.active = node
        for slot in slots:
            node.data.materials[slot] = magenta_material()
        meshes.append(node)
    _ = meshes
    H.export_glb(out_path, [o for o in bpy.data.objects if o.type in ("MESH", "ARMATURE")],
                 animations=False)
    print("CORE-GATE wrote %s" % out_path)


def count(paths: list) -> int:
    """Count magenta pixels in the rendered views; returns the number of failing views."""
    from PIL import Image

    worst = 0
    bad = 0
    for path in paths:
        img = Image.open(path).convert("RGB")
        px = img.load()
        mech = 0
        hits = 0
        for y in range(0, img.height, 2):
            for x in range(0, img.width, 2):
                r, g, b = px[x, y]
                if r > MAGENTA_MIN_RB and b > MAGENTA_MIN_RB and g < MAGENTA_MAX_G:
                    hits += 1
                # the studio backdrop is a flat grey gradient: anything that is not backdrop is mech
                if abs(r - g) > 12 or abs(g - b) > 12 or r < 200:
                    mech += 1
        frac = hits / max(mech, 1)
        worst = max(worst, frac)
        flag = "FAIL" if hits > 0 else "ok"
        print("CORE-GATE %-44s %6d magenta px of %6d mech px (%.3f%%) %s"
              % (os.path.basename(path), hits * 4, mech * 4, frac * 100.0, flag))
        bad += 1 if hits > 0 else 0
    print("CORE-GATE worst %.3f%% over %d views (stress allowance %.1f%%)"
          % (worst * 100.0, len(paths), STRESS_FRACTION * 100.0))
    return bad


def main() -> None:
    import bpy

    sys.path.insert(0, os.path.join(ROOT, "blender", "hero3"))
    sys.path.insert(0, os.path.join(ROOT, "blender"))
    import hero3_lib as H
    from lib import common

    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--mode", default="render", choices=["render"])
    p.add_argument("--src", default=SRC)
    p.add_argument("--out", default=os.path.join(H.TMP, "hero3_core_debug.glb"))
    args = p.parse_args(argv)
    common.reset()
    objs = H.load_glb(args.src)
    roots = [o for o in objs if o.parent is None] or objs
    paint(roots, args.out)


if __name__ == "__main__":
    if "--count" in sys.argv:
        files = [a for a in sys.argv[1:] if not a.startswith("--")]
        sys.exit(1 if count(files) else 0)
    main()
