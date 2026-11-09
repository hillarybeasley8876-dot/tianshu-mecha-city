"""Check the albedo grade measurement: UV coverage, and whether the raster is the right way up.

    tools/blender.sh run blender/monsters/diag_luma.py -- --type=hive
"""
import argparse
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

from monsters import mon_emit, mon_lib  # noqa: E402


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    args = argparse.ArgumentParser()
    args.add_argument("--type", default="hive")
    monster = args.parse_args(argv).type
    common.reset()
    objs = mon_lib.load_glb(mon_lib.tripo_path(monster, "model.glb"))
    body = mon_lib.only_mesh(objs, monster)
    mat = body.data.materials[0]
    px = 256
    src = mon_emit.albedo_image(mat)
    work = src.copy()
    work.scale(px, px)
    buf = mon_emit._pixels(work)
    luma = buf[..., 0] * 0.2126 + buf[..., 1] * 0.7152 + buf[..., 2] * 0.0722
    cov = mon_emit.rasterize_faces(body, range(len(body.data.polygons)), px)
    hot = cov > 0.5
    print("LUMA %s uv coverage %.1f%% of the atlas" % (monster, 100.0 * hot.mean()))
    print("LUMA %s median used %.4f  flipped %.4f  whole %.4f"
          % (monster, float(np.median(luma[hot])), float(np.median(luma[::-1][hot])),
             float(np.median(luma))))
    print("LUMA %s albedo size %s colorspace %s"
          % (monster, tuple(src.size), src.colorspace_settings.name))
    bpy.data.images.remove(work)


main()
