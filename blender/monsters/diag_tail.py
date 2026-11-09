"""Where the titan's tail weights really land (monster-assets, lead r5 item 1).

    tools/blender.sh run blender/monsters/diag_tail.py -- --type=titan

Loads the SHIPPED <type>.glb, and for every vertex prints how much weight the tail chain claims,
bucketed by height and by which other bone would otherwise own it. The r5 defect was that
`add_tail`'s plane test handed 60 % of LOD0 to the tail, legs and arms included."""
import argparse
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

from monsters import mon_lib  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--type", default="titan")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    common.reset()
    path = os.path.join(mon_lib.OUT_DIR, args.type, "%s.glb" % args.type)
    mon_lib.load_glb(path)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    names = [b.name for b in arm.data.bones]
    tail = [i for i, n in enumerate(names) if n.startswith("Tail_")]
    verts = np.array([[c for c in v.co] for v in mesh.data.vertices])
    print("TAIL %s verts %d bones %d tail bones %s" % (args.type, len(verts), len(names),
                                                       [names[i] for i in tail]))
    lo, hi = verts.min(axis=0), verts.max(axis=0)
    print("TAIL bounds lo %s hi %s" % (np.round(lo, 2), np.round(hi, 2)))
    weight = np.zeros(len(verts))
    owner = np.full(len(verts), -1)
    best = np.zeros(len(verts))
    for v in mesh.data.vertices:
        for ge in v.groups:
            if ge.group in tail:
                weight[v.index] += ge.weight
            if ge.weight > best[v.index]:
                best[v.index] = ge.weight
                owner[v.index] = ge.group
    print("TAIL weight > 0.3: %d verts (%.1f%%)" % ((weight > 0.3).sum(),
                                                    100.0 * (weight > 0.3).mean()))
    print("TAIL weight > 0.05: %d verts (%.1f%%)" % ((weight > 0.05).sum(),
                                                     100.0 * (weight > 0.05).mean()))
    # who else would own those vertices
    counts = {}
    for i in np.nonzero(weight > 0.3)[0]:
        counts[names[owner[i]]] = counts.get(names[owner[i]], 0) + 1
    for name, n in sorted(counts.items(), key=lambda kv: -kv[1])[:20]:
        sel = np.array([i for i in np.nonzero(weight > 0.3)[0] if names[owner[i]] == name])
        print("TAIL   stolen from %-14s %6d verts  y %7.2f..%7.2f  z %7.2f..%7.2f"
              % (name, n, verts[sel, 1].min(), verts[sel, 1].max(),
                 verts[sel, 2].min(), verts[sel, 2].max()))
    for b in arm.data.bones:
        if b.name in ("Pelvis", "Spine", "Head", "Tail_0", "Tail_5", "L_Thigh", "L_Foot",
                      "L_Hand", "L_Upperarm", "Root", "Waist"):
            print("TAIL bone %-12s head %s tail %s" % (b.name,
                  np.round(np.array(b.head_local), 2), np.round(np.array(b.tail_local), 2)))
    # the tail's own extent: the vertices that are unambiguously tail (rearmost 5 %)
    rear = verts[:, 1] < np.percentile(verts[:, 1], 5)
    print("TAIL rearmost 5%%: y %.2f..%.2f, tail weight mean %.2f"
          % (verts[rear, 1].min(), verts[rear, 1].max(), weight[rear].mean()))


main()
