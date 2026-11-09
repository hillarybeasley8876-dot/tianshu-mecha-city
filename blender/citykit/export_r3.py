"""Write the r3 export of a model, so the flatness gate has a real baseline next to it.

    tools/blender.sh run blender/citykit/export_r3.py -- --ids t01,b01,m01,o01,k06

r3 is the pipeline as it stood before the planar pass: collapse to the band budget, clear the glTF's
custom split normals, smooth by angle at 40 degrees, no planar pass and no weighted-normal pass. The
output goes to tmp/city-kit/r3/<id>_r3.glb and is only ever read by `tools/citykit/meshqa.py`.
"""
from __future__ import annotations

import os
import sys
from typing import List

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/citykit"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/tools/citykit"))

import bpy  # noqa: E402

import clean  # noqa: E402
import process  # noqa: E402
import tripo_import  # noqa: E402
from assets import BY_ID  # noqa: E402
from lib import common, export  # noqa: E402

ROOT = os.path.expanduser("~/m/mecha-city")
SRC = os.path.join(ROOT, "art", "tripo")
OUT = os.path.join(ROOT, "tmp", "city-kit", "r3")


def args() -> List[str]:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ids = "t01,b01,m01,o01,k06"
    for i, a in enumerate(argv):
        if a == "--ids" and i + 1 < len(argv):
            ids = argv[i + 1]
        elif a.startswith("--ids="):
            ids = a.split("=", 1)[1]
    return ids.split(",")


def build(aid: str) -> str:
    a = BY_ID[aid]
    common.reset()
    tripo_import.import_glb(os.path.join(SRC, "kit_" + aid, "model.glb"))
    process.drop_bone_shapes()
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    obj = common.join(meshes, aid) if len(meshes) > 1 else meshes[0]
    obj.name = aid
    process.fix_up(obj, a)
    process.fit_native(obj, a.native_h)
    process.decimate(obj, a.tris * 3)
    obj, _kept, _dropped = clean.clean(obj, common.join)
    process.fit_native(obj, a.native_h)
    process.decimate(obj, a.tris)
    process.fit_native(obj, a.native_h)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    if getattr(obj.data, "has_custom_normals", False):
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    common.smooth(obj, angle_deg=40.0)
    os.makedirs(OUT, exist_ok=True)
    path = export.export_glb(os.path.join(OUT, "%s_r3.glb" % aid), objects=[obj], jpeg_quality=60)
    print("R3 %-4s tris=%d -> %s" % (aid, common.tri_count(obj), path))
    return path


def main() -> None:
    for aid in args():
        if not os.path.exists(os.path.join(SRC, "kit_" + aid, "model.glb")):
            print("R3 SKIP %s (no raw model)" % aid)
            continue
        build(aid)


if __name__ == "__main__":
    main()
