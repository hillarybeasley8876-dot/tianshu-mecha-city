"""How far a limb hangs below the feet, and what lift clears it (monster-assets, lead r6).

The ground lock plants whatever is lowest, so a limb that swings *below* the feet gets planted
instead of them and the whole animal floats — the juggernaut stood 2.3 to 3.5 m above the deck for
the whole of its `idle`, resting on its knuckle claws, and nothing reported it because the lowest
point was by construction 0.

This measures that gap on the shipped `.glb` and, given a set of bones to lift, sweeps a constant
rotation composed onto the clip's existing keys and reports the clearance each one buys. The two
numbers this round shipped came out of here: the juggernaut's `idle` shoulders at +45 degrees
(claws 2.8 m clear) and `charge_run`'s elbow at -130 degrees (claws 4.8 m clear).

    python3 blender/monsters/diag_clearance.py --type=juggernaut --clip=idle \\
        --lift=L_Upperarm,R_Upperarm --sweep=0,60,10
    python3 blender/monsters/diag_clearance.py --type=titan --clip=tail_sweep
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from monsters.diag_glb_floor import (accessor, animation_tracks, buffers, clip_names,  # noqa: E402
                                     globals_from, read_glb, sample_locals, Skin)
from monsters.mon_types import FOOT_BONES  # noqa: E402

HZ = 30.0


def qmul(a, b) -> np.ndarray:
    x1, y1, z1, w1 = a
    x2, y2, z2, w2 = b
    return np.array([w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
                     w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
                     w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2,
                     w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2])


def axis_signs(skin: Skin) -> dict:
    """`mon_anims.axis_signs(arm, "forward")`, recomputed from the file's rest matrices.

    Blender works in Z-up, so the node rest is converted before reading `col[2].y` and `col[0].x` —
    the same columns `axis_signs` reads off `bone.matrix_local`."""
    yup_to_zup = np.array([[1.0, 0, 0, 0], [0, 0, -1, 0], [0, 1, 0, 0], [0, 0, 0, 1]])
    rest = globals_from(skin.rest, skin.parents, skin.order)
    out = {}
    for node in skin.joints:
        m = yup_to_zup @ rest[node]
        out[skin.names[node]] = (1.0 if m[1, 2] >= 0.0 else -1.0, 1.0,
                                 -1.0 if m[0, 0] >= 0.0 else 1.0)
    return out


def lifted(skin: Skin, tracks: dict, bones: list, degrees: float, signs: dict) -> dict:
    """`tracks` with a constant rotation about local X composed onto every key of `bones`.

    That is what `mon_anims.lift` does in Blender: the clip keeps its authored motion and the limb
    is simply carried higher, which is why a 15 s Tripo idle can be fixed without re-authoring it."""
    out = {k: dict(v) for k, v in tracks.items()}
    for bone in bones:
        node = skin.names.index(bone)
        half = np.radians(degrees * signs[bone][0]) / 2.0
        delta = np.array([np.sin(half), 0.0, 0.0, np.cos(half)])
        times, values, interp = out[node]["rotation"]
        out[node]["rotation"] = (times, np.array([qmul(v, delta) for v in values]), interp)
    return out


def clearance(skin: Skin, tracks: dict, length: float, limb: np.ndarray,
              feet: np.ndarray) -> tuple:
    """(worst metre the limb drops below the feet, worst metre the feet drop below the floor)."""
    steps = max(int(np.ceil(length * HZ)), 1)
    worst, foot_low = 0.0, 1e9
    for s in range(steps):
        posed = skin.pose(tracks, length * s / steps)
        worst = min(worst, float(posed[limb, 1].min() - posed[feet, 1].min()))
        foot_low = min(foot_low, float(posed[feet, 1].min()))
    return worst, foot_low


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--type", required=True)
    parser.add_argument("--clip", default="")
    parser.add_argument("--lift", default="", help="comma-separated bones to carry higher")
    parser.add_argument("--sweep", default="", help="degrees: start,end,step")
    parser.add_argument("--limb", default="", help="bones to report on (default: the lifted ones)")
    args = parser.parse_args(argv)

    path = "game/enemies/models/%s/%s.glb" % (args.type, args.type)
    gltf, binary = read_glb(path)
    bufs = buffers(gltf, binary)
    skin = Skin(gltf, bufs)
    signs = axis_signs(skin)
    names = clip_names(gltf)
    dominant = skin.jidx[np.arange(len(skin.pos)), skin.jw.argmax(axis=1)]
    keep = np.nonzero(skin.keep)[0]
    feet = keep[np.isin(dominant[keep], list(skin.support_joints(FOOT_BONES[args.type])))]
    lifted_bones = [b for b in args.lift.split(",") if b]
    limb_bones = [b for b in args.limb.split(",") if b] or lifted_bones
    limb = keep[np.isin(dominant[keep], list(skin.support_joints(limb_bones, hops=1)))] \
        if limb_bones else keep
    wanted = [c for c in names if args.clip in c] if args.clip else names
    if not wanted:
        print("no clip matches '%s'; have %s" % (args.clip, names))
        return 1
    for name in wanted:
        anim = gltf["animations"][names.index(name)]
        tracks = animation_tracks(gltf, bufs, anim)
        length = max(float(accessor(gltf, bufs, s["input"])[:, 0].max())
                     for s in anim["samplers"])
        if not lifted_bones:
            gap, foot = clearance(skin, tracks, length, limb, feet)
            print("CLEAR %-11s %-14s limb %+.3f m below the feet | feet %+.3f m"
                  % (args.type, name, gap, foot))
            continue
        start, end, step = (float(v) for v in args.sweep.split(",")) if args.sweep \
            else (0.0, 0.0, 1.0)
        angle = start
        while angle <= end + 1e-6:
            gap, foot = clearance(skin, lifted(skin, tracks, lifted_bones, angle, signs),
                                  length, limb, feet)
            print("CLEAR %-11s %-14s lift %+6.1f deg -> limb %+.3f m below the feet | feet %+.3f m"
                  % (args.type, name, angle, gap, foot))
            angle += step
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
