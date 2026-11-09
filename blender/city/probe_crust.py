"""Ground-crust probe (city-build). Reports the crust's real area and connectivity, and checks
the plateau-as-cutter fix.

    tools/blender.sh run blender/city/probe_crust.py

The crust was silently losing 80 % of its area: the plateau runs to the map edge, so passing it to
`boolop.difference` as a `base_hole` made `Kit.slab`'s scanfill treat it as a hole and return a
partial triangulation (173 642 m2 instead of 1 190 410). Passing it as a *cutter* fixes it. This
script is the evidence, and the regression check if the terrain code is touched again.
"""
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
sys.path.insert(0, _HERE)

import bmesh  # noqa: E402
import bpy  # noqa: E402

import layout as layout_mod  # noqa: E402
from kit import boolop, terrain  # noqa: E402
from lib import common  # noqa: E402

FAIL_BELOW = 0.85     ## the crust must keep at least this share of its expected area


def area(poly):
    return 0.5 * abs(sum(p[0] * q[1] - q[0] * p[1] for p, q in zip(poly, poly[1:] + poly[:1])))


def measure(name, square, cuts, holes, col):
    me = boolop.difference(name, square, -terrain.CRUST, 0.0, cuts, col, base_holes=holes)
    if me is None:
        print("CRUST %-18s -> nothing" % name)
        return 0.0, 0
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-3)
    top = [f for f in bm.faces if f.normal.z > 0.9]
    components = _components(top)
    up = sum(f.calc_area() for f in top)
    bm.free()
    bpy.data.meshes.remove(me)
    print("CRUST %-18s %9.0f m2 up-facing, %d components" % (name, up, components))
    return up, components


def _components(faces):
    parent = {f.index: f.index for f in faces}

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    first = {}
    for f in faces:
        root = find(f.index)
        for v in f.verts:
            if v.index in first:
                other = find(first[v.index])
                if other != root:
                    parent[root] = other
                    root = other
            else:
                first[v.index] = f.index
    return len({find(f.index) for f in faces})


def main():
    common.reset()
    lay = layout_mod.Layout()
    half = float(lay.bounds["half"])
    col = common.collection("probe")
    square = [(-half, -half), (half, -half), (half, half), (-half, half)]
    plateau = [tuple(p) for p in lay.terrain["plateau"]["polygon"]]
    cuts = terrain.ground_cuts(lay, -terrain.CRUST, 0.0)

    expected = (half * 2.0) ** 2 - area(plateau) - sum(area(c) for c in cuts)
    print("CRUST %d cutters, %.0f m2; plateau hole %.0f m2 touching the edge at y %.0f"
          % (len(cuts), sum(area(c) for c in cuts), area(plateau), max(p[1] for p in plateau)))
    print("CRUST expected up-facing area: %.0f m2" % expected)
    measure("as base_hole", square, cuts, [plateau], col)
    up, parts = measure("as cutter", square, cuts + [plateau], [], col)
    share = up / expected if expected > 0.0 else 0.0
    ok = share >= FAIL_BELOW and parts <= 4
    print("CRUST %s: %.1f %% of expected area in %d components"
          % ("PASS" if ok else "FAIL", share * 100.0, parts))
    sys.exit(0 if ok else 1)


main()
