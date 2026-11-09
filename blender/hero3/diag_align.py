"""How do the hero3 body and the hero3 part segmentation actually relate? (diagnostic)

  tools/blender.sh run blender/hero3/diag_align.py

Prints each model's own bounding box, the union bbox, and a per-axis histogram of where the geometry
sits, so the normalise/align constants can be set from measurements instead of guesses.
"""
import os
import sys

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/hero3"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
import bpy  # noqa: E402
import numpy as np  # noqa: E402
import hero3_lib as H  # noqa: E402
from lib import common  # noqa: E402


def cloud(objs, per=4000):
    return np.concatenate([H.sample_n(o, per) for o in objs])


def show(label, pts):
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    print("%-12s n=%-7d lo=[%7.3f %7.3f %7.3f] hi=[%7.3f %7.3f %7.3f] size=[%6.3f %6.3f %6.3f]"
          % ((label, len(pts)) + tuple(lo) + tuple(hi) + tuple(hi - lo)))


common.reset()
body = H.only_mesh(H.load_glb("art/tripo/hero3_a1/model.glb"), "body")
parts = [o for o in H.load_glb("art/tripo/hero3_a1p/model.glb") if o.type == "MESH"]
show("body", cloud([body]))
show("parts", cloud(parts))
for obj in sorted(parts, key=lambda o: o.name):
    show("  " + obj.name, cloud([obj], 400))
# where is the mass along each axis? a mech is widest at the shoulders, so x should be bimodal
b = cloud([body], 40000)
for axis, name in enumerate("xyz"):
    hist, edges = np.histogram(b[:, axis], bins=12)
    print("HIST %s %s" % (name, " ".join("%d" % v for v in hist)))
    print("     edges %s" % " ".join("%.2f" % v for v in edges))
