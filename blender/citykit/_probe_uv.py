"""Probe: does `average_islands_scale` + `pack_islands` turn the Tripo confetti atlas into a DENSE
one, and what texel density does that buy?

The island COUNT cannot be fixed — a 12 k-tri collapse of a photogrammetry shell really does have
~9 000 distinct surface patches, and every angle-based projection finds them. But once each island is
flat-filled with its own mean colour the count stops mattering: neighbouring islands of one part hold
nearly the same colour, so the seams vanish. What the new layout has to buy is DENSITY, because the
procedural layer draws a 45 mm seam and the Tripo atlas spends 91 % of itself on padding.

  tools/blender.sh run blender/citykit/_probe_uv.py
"""
import os
import sys
import time

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/citykit"))

import bpy  # noqa: E402
import numpy as np  # noqa: E402

import covertex  # noqa: E402
import planar  # noqa: E402
import tripo_import  # noqa: E402
from lib import common  # noqa: E402

SRC = os.path.expanduser("~/m/mecha-city/art/tripo/kit_k07/model.glb")
SIDE = 1024


def measure(obj, tag, secs):
    st = covertex.islands(obj, SIDE)
    g = covertex.geom(obj, SIDE)
    cov = g["cov"]
    m = g["mpt"][cov]
    # The area-weighted mean is the honest number: the median hides a 46x spread on the raw atlas.
    print("PROBE %-24s %5.1fs islands=%-5d fill=%5.2f%% cover=%5.2f%%  mpt med=%.4f mean=%.4f "
          "p95=%.4f  seam45mm=%.2f texel"
          % (tag, secs, st["uv_islands"], st["uv_fill_pct"], 100.0 * cov.mean(),
             float(np.median(m)) if cov.any() else 0.0, float(m.mean()) if cov.any() else 0.0,
             float(np.percentile(m, 95)) if cov.any() else 0.0,
             0.045 / max(float(m.mean()), 1e-9) if cov.any() else 0.0))


def run(obj, tag, fn):
    t0 = time.time()
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.context.scene.tool_settings.use_uv_select_sync = True
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    fn()
    bpy.ops.object.mode_set(mode="OBJECT")
    measure(obj, tag, time.time() - t0)


common.reset()
tripo_import.import_glb(SRC)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
obj = common.join(meshes, "k07") if len(meshes) > 1 else meshes[0]
mod = obj.modifiers.new("decimate", "DECIMATE")
mod.ratio = 12000.0 / common.tri_count(obj)
mod.use_collapse_triangulate = True
bpy.context.view_layer.objects.active = obj
bpy.ops.object.modifier_apply(modifier=mod.name)
for _ in range(3):
    planar.flatten(obj)
print("PROBE tris", common.tri_count(obj))
measure(obj, "tripo atlas", 0.0)

for margin in (0.008, 0.003):
    def go(margin=margin):
        bpy.ops.uv.average_islands_scale()
        bpy.ops.uv.pack_islands(rotate=True, scale=True, margin=margin,
                                margin_method="FRACTION")
    run(obj, "avg+pack m=%.3f" % margin, go)

run(obj, "pack only m=0.003", lambda: bpy.ops.uv.pack_islands(
    rotate=True, scale=True, margin=0.003, margin_method="FRACTION"))
print("PROBE done")
