"""Measure the hero3 anatomy in the framed 16 m model (hero-v3).

  tools/blender.sh run blender/hero3/diag_anatomy.py

Prints, per labelled piece, the extents in 1 m height bands -- that is what places the skeleton and
the joint cut planes. Run after segment.py --stop-after=split.
"""
import os
import sys

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/hero3"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
import bpy  # noqa: E402
import numpy as np  # noqa: E402
import hero3_lib as H  # noqa: E402
from lib import common  # noqa: E402


def bands(pts, label, lo, hi, step=1.0):
    print("--- %s" % label)
    z = lo
    while z < hi:
        sel = pts[(pts[:, 2] >= z) & (pts[:, 2] < z + step)]
        if len(sel) > 40:
            print("  z %5.1f-%5.1f n=%-6d x[%6.2f %6.2f] y[%6.2f %6.2f]" % (
                z, z + step, len(sel), sel[:, 0].min(), sel[:, 0].max(),
                sel[:, 1].min(), sel[:, 1].max()))
        z += step


common.reset()
body = H.only_mesh(H.load_glb("art/tripo/hero3_a1/model.glb"), "body")
parts = sorted([o for o in H.load_glb("art/tripo/hero3_a1p/model.glb") if o.type == "MESH"],
               key=lambda o: o.name)
import segment  # noqa: E402  (import after the GLBs are loaded: segment runs its own main)

segment.stage_body(body, parts)
H.decimate(body, 200000)
segment.stage_align(body, parts)
labels = segment.stage_label(body, parts)

import importlib  # noqa: E402
centres = segment.face_centres(body)
allpts = H.sample_points(body, 200000)
bands(allpts, "WHOLE BODY", 0.0, 16.0)
# facing check: the feet and the head band, sampled densely
feet = allpts[allpts[:, 2] < 0.5]
print("FEET n=%d x[%.2f %.2f] y[%.2f %.2f]" % (len(feet), feet[:, 0].min(), feet[:, 0].max(),
                                               feet[:, 1].min(), feet[:, 1].max()))
for pid, obj in enumerate(parts):
    sel = centres[labels == pid]
    if len(sel) < 40:
        continue
    lo, hi = float(sel[:, 2].min()), float(sel[:, 2].max())
    bands(sel, "p%d %s" % (pid, obj.name), lo, hi, max(1.0, (hi - lo) / 8.0))
_ = importlib
