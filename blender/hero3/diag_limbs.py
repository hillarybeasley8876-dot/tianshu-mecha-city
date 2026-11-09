"""Measure the limb axes and joints of the framed hero3 (hero-v3).

  tools/blender.sh run blender/hero3/diag_limbs.py

Slices each labelled limb piece along its own axis and reports, per slice, the centroid and the
radius. The joints are the local minima of the radius -- an elbow, a knee and a wrist are exactly
where a limb is thinnest -- so the skeleton table in hero3_bones.py is measured, not guessed.
"""
import os
import sys

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/hero3"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
import bpy  # noqa: E402
import numpy as np  # noqa: E402
import hero3_lib as H  # noqa: E402
from lib import common  # noqa: E402

SLICES = 26


def profile(pts, axis, label):
    """Centroid + radius along `axis` (0..1 from the lowest projection to the highest)."""
    axis = axis / np.linalg.norm(axis)
    t = pts @ axis
    lo, hi = float(t.min()), float(t.max())
    print("--- %s axis=%s t[%.2f %.2f] n=%d" % (label, np.round(axis, 3), lo, hi, len(pts)))
    rows = []
    for i in range(SLICES):
        a = lo + (hi - lo) * i / SLICES
        b = lo + (hi - lo) * (i + 1) / SLICES
        sel = pts[(t >= a) & (t < b)]
        if len(sel) < 20:
            rows.append(None)
            continue
        c = sel.mean(axis=0)
        r = float(np.sqrt(((sel - c) ** 2).sum(axis=1)).mean())
        rows.append((a, c, r, len(sel)))
        print("  t %6.2f-%6.2f n=%-5d centre=[%6.2f %6.2f %6.2f] r=%.2f" % (
            a, b, len(sel), c[0], c[1], c[2], r))
    radii = [(row[0], row[2]) for row in rows if row]
    for i in range(1, len(radii) - 1):
        if radii[i][1] < radii[i - 1][1] and radii[i][1] < radii[i + 1][1]:
            row = rows[[j for j, r in enumerate(rows) if r][i]]
            print("  WAIST at t %.2f r %.2f centre %s" % (radii[i][0], radii[i][1],
                                                          np.round(row[1], 2)))
    return rows


common.reset()
body = H.only_mesh(H.load_glb("art/tripo/hero3_a1/model.glb"), "body")
parts = sorted([o for o in H.load_glb("art/tripo/hero3_a1p/model.glb") if o.type == "MESH"],
               key=lambda o: o.name)
import segment  # noqa: E402

segment.stage_body(body, parts)
H.decimate(body, 200000)
segment.stage_align(body, parts)
labels = segment.stage_label(body, parts)
centres = segment.face_centres(body)

# name -> part index, from the sorted-by-name order the pipeline uses
NAMES = {"leg_l": "tripo_part_1", "leg_r": "tripo_part_2", "arm_r": "tripo_part_3",
         "arm_l": "tripo_part_4", "torso": "tripo_part_0", "collar": "tripo_part_5",
         "head": "tripo_part_7"}
idx = {obj.name: i for i, obj in enumerate(parts)}
for label, part_name in NAMES.items():
    sel = centres[labels == idx[part_name]]
    if len(sel) < 100:
        print("--- %s EMPTY" % label)
        continue
    axis = np.array([0.0, 0.0, 1.0])
    if label.startswith("arm"):
        axis = sel[sel[:, 2].argmin()] - sel[sel[:, 2].argmax()]
    profile(sel, axis, label)
