"""List the hive's acid clusters by size and height, so the pod sockets are picked from the real
glowing bulbs instead of the vein noise.

    tools/blender.sh run blender/monsters/diag_pods.py
"""
import os
import sys

import bpy

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

from monsters import mon_build, mon_emit, mon_lib, mon_types  # noqa: E402


def main() -> None:
    common.reset()
    body = mon_lib.only_mesh(mon_lib.load_glb(mon_lib.tripo_path("hive", "model.glb")), "hive")
    body.name = "Hive"
    mon_lib.decimate(body, mon_types.TRIS["hive"][0])
    mon_build.place(body, None, mon_types.YAW["hive"], mon_types.SIZES["hive"])
    mask, acid, _violet = mon_emit.build_mask(body.data.materials[0], "hive")
    for radius in (0.06, 0.10, 0.14, 0.18):
        pods = mon_emit.find_weak_points(body, acid, radius_frac=radius, max_points=10,
                                         min_faces=20)
        print("RADIUS %.2f -> %d clusters" % (radius, len(pods)))
        for p in pods:
            print("   z %6.1f  faces %5d  score %.2f  at %s"
                  % (p["pos"][2], p["faces"], p["score"],
                     [round(c, 1) for c in p["pos"]]))


main()
