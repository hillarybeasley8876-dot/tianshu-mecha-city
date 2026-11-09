"""Stage-by-stage and sweep diagnostics for the monster skin (monster-assets, lead r5 item 1).

    tools/blender.sh run blender/monsters/diag_skin_sweep.py -- --type=titan [--stages]

Two modes:

  * `--stages` reports the worst per-edge stretch after each rig-surgery step, and the same number
    for Tripo's own remesh placed at the same real-world scale — the reference line the lead's
    verifier asked for. Everything is measured *after* `place()`, because `stretch_report` samples
    edges longer than 2 cm: on an unplaced Tripo mesh almost every edge is shorter than that, so an
    unplaced measurement silently only looks at the well-behaved long edges.
  * the default mode sweeps (prune reach, smoothing steps) over one frozen copy of the weights.
"""
import argparse
import os
import sys

import bpy

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

from monsters import mon_build, mon_lib, mon_rig, mon_skin, mon_types  # noqa: E402


def _surgery(monster: str, body, arm, report: bool = True) -> None:
    """The same rig surgery `mon_build._finish_rigged` does, so the sweep measures the real thing."""
    actions = list(bpy.data.actions)
    if monster in ("mantis", "juggernaut", "titan"):
        mon_rig.collapse_claws(arm, body, actions)
        mon_rig.bind_mesh(body, arm)
        if report:
            mon_skin.stretch_report("%s/1-claws" % monster, body, arm, _CLIPS[0])
    if monster == "titan":
        print("TAIL %s" % mon_rig.add_tail(arm, body))
        mon_rig.bind_mesh(body, arm)
        if report:
            mon_skin.stretch_report("%s/2-tail" % monster, body, arm, _CLIPS[0])
        print("JAW %s" % mon_rig.add_jaw(arm, body))
        mon_rig.bind_mesh(body, arm)
        if report:
            mon_skin.stretch_report("%s/3-jaw" % monster, body, arm, _CLIPS[0])


#: set once in main() so _surgery can report without threading the dict through every call
_CLIPS: list = [{}]


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--type", default="titan")
    p.add_argument("--reach", default="0")
    p.add_argument("--steps", default="0,4,16")
    p.add_argument("--stages", action="store_true")
    args = p.parse_args(argv)
    monster = args.type
    if args.stages:
        # Tripo's own rig, in its own scene, placed at the same real-world scale: the reference line
        # the lead's verifier asked for. It has to be its own scene because `place()` moves the rig
        # as well as the mesh.
        common.reset()
        rigged = mon_lib.load_glb(mon_lib.tripo_path(monster, "rigged.glb"))
        arm = mon_lib.only_armature(rigged, monster)
        remesh = mon_lib.only_mesh(rigged, monster)
        remesh.modifiers.clear()
        mon_rig.bind_mesh(remesh, arm)
        mon_build.place(remesh, arm, mon_types.YAW[monster], mon_types.SIZES[monster])
        mon_rig.bind_mesh(remesh, arm)
        mon_skin.stretch_report("%s/tripo-placed" % monster, remesh, arm,
                                mon_lib.match_source_clips(monster, mon_lib.imported_actions()))

    common.reset()
    rigged = mon_lib.load_glb(mon_lib.tripo_path(monster, "rigged.glb"))
    arm = mon_lib.only_armature(rigged, monster)
    remesh = mon_lib.only_mesh(rigged, monster)
    remesh.modifiers.clear()
    mon_rig.bind_mesh(remesh, arm)
    hi_objs = mon_lib.load_glb(mon_lib.tripo_path(monster, "model.glb"))
    body = mon_lib.only_mesh(hi_objs, monster)
    body.name = "Body"
    mon_lib.decimate(body, mon_types.TRIS[monster][0])
    matrix, _rms, _ = mon_build.align_highres(body, remesh)
    mon_lib.transform_mesh(body, matrix)
    mon_skin.transfer_surface(remesh, body)
    body.modifiers.clear()
    bpy.data.objects.remove(remesh, do_unlink=True)

    clips = mon_lib.match_source_clips(monster, mon_lib.imported_actions())
    _CLIPS[0] = clips
    mon_build.place(body, arm, mon_types.YAW[monster], mon_types.SIZES[monster])
    mon_rig.bind_mesh(body, arm)
    if args.stages:
        mon_skin.stretch_report("%s/0-transfer" % monster, body, arm, clips)
        _surgery(monster, body, arm)
        for steps in (4, 16):
            mon_skin.smooth_weights(body, iterations=steps, lam=0.5)
            mon_skin.limit_influences(body, 4)
            mon_skin.stretch_report("%s/4-smooth%d" % (monster, steps), body, arm, clips)
        return

    _surgery(monster, body, arm, report=False)
    names, base = mon_skin.weight_matrix(body)
    for reach in [float(x) for x in args.reach.split(",")]:
        for steps in [int(x) for x in args.steps.split(",")]:
            mon_skin._write_groups(body, names, base.copy())
            if reach > 0.0:
                mon_skin.prune_distant_weights(body, arm, k=reach)
            if steps > 0:
                mon_skin.smooth_weights(body, iterations=steps, lam=0.5)
            mon_skin.limit_influences(body, 4)
            got = mon_skin.stretch_report("%s r%.1f s%d" % (monster, reach, steps),
                                          body, arm, clips)
            ratios = got["ratio"]
            print("SWEEP %-11s reach %.1f steps %2d  worst %.2fx  mean %.2fx  longest %.2f m (%.1f%%)"
                  % (monster, reach, steps, max(ratios.values()),
                     sum(ratios.values()) / max(len(ratios), 1),
                     got["longest_frac"] * got["height_m"], 100.0 * got["longest_frac"]))


main()
