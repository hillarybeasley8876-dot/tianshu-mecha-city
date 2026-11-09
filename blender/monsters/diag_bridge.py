"""Bridge-triangle census for any rigged GLB (monster-assets, lead r5 item 1).

    tools/blender.sh run blender/monsters/diag_bridge.py -- --glb=<path>[,<path>]

A "bridge" triangle is one whose vertices' dominant bones are more than MAX_HOPS apart in the bone
tree — the rule `probe_fuse.gd` uses. Where two limbs touched in the source pose the shell stitches
them together, and those triangles are what stretch into sheets. Run it on Tripo's own rigged.glb
and on the shipped model to see which step introduces them."""
import argparse
import os
import sys
from collections import defaultdict

import bpy
import numpy as np

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

from monsters import mon_lib  # noqa: E402

MAX_HOPS = 3


def hops(parents: list, a: int, b: int) -> int:
    chain = []
    n = a
    while n >= 0:
        chain.append(n)
        n = parents[n]
    steps = 0
    n = b
    while n >= 0:
        if n in chain:
            return chain.index(n) + steps
        n = parents[n]
        steps += 1
    return 99


def census(path: str) -> None:
    common.reset()
    mon_lib.load_glb(path)
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not arms or not meshes:
        print("BRIDGE %s: no rig" % os.path.basename(path))
        return
    arm = arms[0]
    names = [b.name for b in arm.data.bones]
    parents = [names.index(b.parent.name) if b.parent else -1 for b in arm.data.bones]
    for mesh in meshes:
        me = mesh.data
        groups = {vg.index: vg.name for vg in mesh.vertex_groups}
        bone_of_group = {gi: (names.index(n) if n in names else -1) for gi, n in groups.items()}
        dominant = np.full(len(me.vertices), -1, dtype=np.int64)
        best = np.zeros(len(me.vertices))
        for v in me.vertices:
            for ge in v.groups:
                if ge.weight > best[v.index]:
                    best[v.index] = ge.weight
                    dominant[v.index] = bone_of_group.get(ge.group, -1)
        tris = np.array([p.vertices[:] for p in me.polygons], dtype=np.int64)
        dom = dominant[tris]
        cache = {}

        def hop(a: int, b: int) -> int:
            key = (a, b) if a < b else (b, a)
            if key not in cache:
                cache[key] = hops(parents, key[0], key[1])
            return cache[key]

        pairs = defaultdict(int)
        bridge = 0
        for t in range(len(tris)):
            worst = 0
            pa = pb = -1
            for e in range(3):
                a, b = int(dom[t, e]), int(dom[t, (e + 1) % 3])
                if a < 0 or b < 0 or a == b:
                    continue
                h = hop(a, b)
                if h > worst:
                    worst, pa, pb = h, min(a, b), max(a, b)
            if worst > MAX_HOPS:
                bridge += 1
                pairs["%s|%s" % (names[pa], names[pb])] += 1
        top = sorted(pairs.items(), key=lambda kv: -kv[1])[:8]
        print("BRIDGE %-28s %-10s tris %6d bridge %5d (%5.2f%%) pairs %d"
              % (os.path.basename(path), mesh.name, len(tris), bridge,
                 100.0 * bridge / max(len(tris), 1), len(pairs)))
        for key, n in top:
            print("BRIDGE     %-46s %5d" % (key, n))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    for path in args.glb.split(","):
        census(os.path.expanduser(path))


main()
