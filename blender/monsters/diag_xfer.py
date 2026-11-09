"""Old vs new weight transfer, judged by bridge triangles (monster-assets, lead r5 item 1).

    tools/blender.sh run blender/monsters/diag_xfer.py -- --type=mantis [--method=surface|nearest]

Runs the build's real stages (load, decimate, ICP align) and then transfers Tripo's weights onto the
decimated hi-res mesh both ways, printing the bridge-triangle census after each. Tripo's own rig of
the same animal is the reference line."""
import argparse
import os
import sys

import bpy

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

from monsters import mon_build, mon_lib, mon_rig, mon_skin, mon_types  # noqa: E402


def census(label: str, mesh, arm) -> None:
    names = [b.name for b in arm.data.bones]
    parents = [names.index(b.parent.name) if b.parent else -1 for b in arm.data.bones]
    got = mon_skin.bridge_triangles(mesh, names, parents)
    top = sorted(got["pairs"].items(), key=lambda kv: -kv[1])[:6]
    print("XFER %-26s tris %6d bridge %5d (%5.2f%%) pairs %d"
          % (label, got["tris"], got["bridge"], 100.0 * got["bridge"] / max(got["tris"], 1),
             len(got["pairs"])))
    for key, n in top:
        print("XFER     %-46s %5d" % (key, n))


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--type", default="mantis")
    p.add_argument("--method", default="surface")
    p.add_argument("--steps", type=int, default=mon_skin.STEPS)
    p.add_argument("--lam", type=float, default=mon_skin.LAMBDA)
    p.add_argument("--smooth", type=int, default=0)
    p.add_argument("--stretch", action="store_true")
    args = p.parse_args(argv)
    monster = args.type
    common.reset()
    rigged = mon_lib.load_glb(mon_lib.tripo_path(monster, "rigged.glb"))
    arm = mon_lib.only_armature(rigged, monster)
    remesh = mon_lib.only_mesh(rigged, monster)
    remesh.modifiers.clear()
    mon_rig.bind_mesh(remesh, arm)
    census("%s tripo remesh" % monster, remesh, arm)

    hi_objs = mon_lib.load_glb(mon_lib.tripo_path(monster, "model.glb"))
    hi = mon_lib.only_mesh(hi_objs, monster)
    hi.name = "Body"
    target = mon_types.TRIS[monster][0]
    print("DECIMATE %d -> %d tris" % (mon_lib.tri_count(hi), mon_lib.decimate(hi, target)))
    matrix, rms, _ = mon_build.align_highres(hi, remesh)
    print("ALIGN rms %.5f" % rms)
    mon_lib.transform_mesh(hi, matrix)

    if args.method in ("nearest", "both"):
        mon_lib.transfer_weights(remesh, hi)
        census("%s hires / nearest" % monster, hi, arm)
    if args.method in ("surface", "both"):
        stats = mon_skin.transfer_surface(remesh, hi, steps=args.steps, lam=args.lam)
        print("XFER stats %s" % stats)
        census("%s hires / surface" % monster, hi, arm)
        if args.smooth:
            print("XFER smooth %s" % mon_skin.smooth_weights(hi, iterations=args.smooth))
            census("%s hires / smoothed" % monster, hi, arm)
    if args.stretch:
        mon_rig.bind_mesh(remesh, arm)
        mon_rig.bind_mesh(hi, arm)
        clips = mon_lib.match_source_clips(monster, mon_lib.imported_actions())
        mon_skin.stretch_report("%s/tripo" % monster, remesh, arm, clips)
        mon_skin.stretch_report("%s/ours" % monster, hi, arm, clips)


main()
