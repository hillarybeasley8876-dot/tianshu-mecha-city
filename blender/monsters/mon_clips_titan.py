"""Scripted Brood Titan clips (monster-assets) — the extras the lead asked for on top of Tripo's ten.

Bone names are the shared 78-joint humanoid plus the surgery in `mon_rig` (Tail_0..5 from the pelvis,
Jaw from Tripo's FacialBone, three claws per hand). Angles are world-intuitive
(`mon_anims.axis_signs`): +rx swings a bone's tip forward, +rz splays it right.
"""
HIP = "Hip"
PELVIS = "Pelvis"
SPINE = ["Waist", "Spine01", "Spine02"]
NECK = ["NeckTwist01", "NeckTwist02"]
HEAD = "Head"
JAW = "Jaw"
TAIL = ["Tail_%d" % i for i in range(6)]
ARMS = {side: ["%s_Clavicle" % side, "%s_Upperarm" % side, "%s_Forearm" % side, "%s_Hand" % side]
        for side in ("L", "R")}
CLAWS = {side: ["%s_Claw%d" % (side, i) for i in (1, 2, 3)] for side in ("L", "R")}
LEGS = {side: ["%s_Thigh" % side, "%s_Calf" % side, "%s_Foot" % side, "%s_ToeBase" % side]
        for side in ("L", "R")}


def _tail_whip(frames: list, amp: float, lag: int = 3) -> list:
    """A travelling wave down the tail: each joint repeats the one before it `lag` frames later."""
    keys = []
    for i, bone in enumerate(TAIL):
        d = i * lag
        scale = amp * (0.45 + 0.11 * i)
        keys += [(bone, 0, (0, 0, 0), "SINE", "EASE_IN"),
                 (bone, frames[0] + d, (0, 0, scale), "SINE", "EASE_IN"),
                 (bone, frames[1] + d, (0, 0, -scale * 1.35), "QUAD", "EASE_OUT"),
                 (bone, frames[2] + d, (0, 0, scale * 0.3), "SINE", "EASE_IN"),
                 (bone, frames[3] + d, (0, 0, 0), "SINE", "EASE_IN")]
    return keys


def titan_clips() -> dict:
    """tail_sweep / climb_over / phase_roar / core_break / death_fall."""
    # 0-18 wind up (the tail coils the wrong way), 19-30 the sweep, 31-48 settle
    tail_sweep = [
        (HIP, 0, None, "SINE", "EASE_IN", (0, 0, 0)),
        (HIP, 18, None, "QUAD", "EASE_IN", (0, -0.6, -0.3)),
        (HIP, 27, None, "QUAD", "EASE_OUT", (0, 0.5, 0.1)),
        (HIP, 48, None, "SINE", "EASE_IN", (0, 0, 0)),
        (PELVIS, 0, (0, 0, 0)), (PELVIS, 18, (0, 16, 0), "SINE", "EASE_IN"),
        (PELVIS, 27, (0, -22, 0), "QUAD", "EASE_OUT"), (PELVIS, 48, (0, 0, 0)),
        (SPINE[0], 0, (0, 0, 0)), (SPINE[0], 18, (0, 10, -4), "SINE", "EASE_IN"),
        (SPINE[0], 28, (0, -14, 5), "QUAD", "EASE_OUT"), (SPINE[0], 48, (0, 0, 0)),
        (SPINE[2], 0, (0, 0, 0)), (SPINE[2], 20, (-8, 12, 0), "SINE", "EASE_IN"),
        (SPINE[2], 30, (6, -16, 0), "QUAD", "EASE_OUT"), (SPINE[2], 48, (0, 0, 0)),
    ]
    tail_sweep += _tail_whip([18, 28, 38, 48], 26.0)
    for side in ("L", "R"):
        arm = ARMS[side]
        out = 18.0 if side == "L" else -18.0
        tail_sweep += [(arm[0], 0, (0, 0, 0)), (arm[0], 20, (0, 0, out), "SINE", "EASE_IN"),
                       (arm[0], 30, (0, 0, -out), "QUAD", "EASE_OUT"), (arm[0], 48, (0, 0, 0)),
                       (arm[2], 0, (0, 0, 0)), (arm[2], 22, (-30, 0, 0), "SINE", "EASE_IN"),
                       (arm[2], 48, (0, 0, 0))]

    # climb_over: 3.5 s haul over a deck edge — the intro shot. Reach, grip, pull, knee up, stand.
    climb = [
        (HIP, 0, None, "SINE", "EASE_IN", (0, 0, 0)),
        (HIP, 14, None, "QUAD", "EASE_IN", (0, 1.6, -1.2)),
        (HIP, 40, None, "SINE", "EASE_IN", (0, 3.4, 0.4)),
        (HIP, 64, None, "QUAD", "EASE_OUT", (0, 2.6, 2.4)),
        (HIP, 84, None, "SINE", "EASE_IN", (0, 0, 0)),
        (SPINE[1], 0, (0, 0, 0)), (SPINE[1], 14, (26, 0, 0), "SINE", "EASE_IN"),
        (SPINE[1], 40, (34, 0, 0), "SINE", "EASE_IN"), (SPINE[1], 64, (-12, 0, 0),
                                                        "QUAD", "EASE_OUT"),
        (SPINE[1], 84, (0, 0, 0)),
        (SPINE[2], 0, (0, 0, 0)), (SPINE[2], 18, (18, 0, 0), "SINE", "EASE_IN"),
        (SPINE[2], 64, (-16, 0, 0), "QUAD", "EASE_OUT"), (SPINE[2], 84, (0, 0, 0)),
    ]
    for side in ("L", "R"):
        arm, claws = ARMS[side], CLAWS[side]
        s = 1.0 if side == "L" else -1.0
        climb += [(arm[0], 0, (0, 0, 0)), (arm[0], 16, (0, 0, 12 * s), "SINE", "EASE_IN"),
                  (arm[0], 84, (0, 0, 0)),
                  (arm[1], 0, (0, 0, 0)), (arm[1], 16, (-96, 0, 16 * s), "QUAD", "EASE_OUT"),
                  (arm[1], 44, (-70, 0, 12 * s), "SINE", "EASE_IN"), (arm[1], 84, (0, 0, 0)),
                  (arm[2], 0, (0, 0, 0)), (arm[2], 18, (-52, 0, 0), "SINE", "EASE_IN"),
                  (arm[2], 44, (-20, 0, 0), "SINE", "EASE_IN"), (arm[2], 84, (0, 0, 0))]
        for c in claws:
            climb += [(c, 0, (0, 0, 0)), (c, 22, (-34, 0, 0), "QUAD", "EASE_OUT"),
                      (c, 56, (-8, 0, 0), "SINE", "EASE_IN"), (c, 84, (0, 0, 0))]
        leg = LEGS[side]
        climb += [(leg[0], 0, (0, 0, 0)), (leg[0], 30, (-52, 0, 8 * s), "SINE", "EASE_IN"),
                  (leg[0], 62, (18, 0, 0), "QUAD", "EASE_OUT"), (leg[0], 84, (0, 0, 0)),
                  (leg[1], 0, (0, 0, 0)), (leg[1], 30, (-64, 0, 0), "SINE", "EASE_IN"),
                  (leg[1], 62, (-14, 0, 0), "QUAD", "EASE_OUT"), (leg[1], 84, (0, 0, 0))]
    climb += _tail_whip([16, 34, 56, 84], 12.0)

    # phase_roar: 2.5 s, bigger than the idle roar — rears up, arms wide, jaw open, slams back down
    phase_roar = [
        (HIP, 0, None, "SINE", "EASE_IN", (0, 0, 0)),
        (HIP, 10, None, "QUAD", "EASE_IN", (0, -0.8, -1.1)),
        (HIP, 30, None, "QUAD", "EASE_OUT", (0, 0.4, 1.9)),
        (HIP, 52, None, "QUAD", "EASE_OUT", (0, 0, -0.4)),
        (HIP, 60, None, "SINE", "EASE_IN", (0, 0, 0)),
        (PELVIS, 0, (0, 0, 0)), (PELVIS, 12, (14, 0, 0), "SINE", "EASE_IN"),
        (PELVIS, 32, (-16, 0, 0), "QUAD", "EASE_OUT"), (PELVIS, 60, (0, 0, 0)),
        (SPINE[0], 0, (0, 0, 0)), (SPINE[0], 12, (16, 0, 0), "SINE", "EASE_IN"),
        (SPINE[0], 32, (-20, 0, 0), "QUAD", "EASE_OUT"), (SPINE[0], 60, (0, 0, 0)),
        (SPINE[2], 0, (0, 0, 0)), (SPINE[2], 14, (22, 0, 0), "SINE", "EASE_IN"),
        (SPINE[2], 34, (-26, 0, 0), "QUAD", "EASE_OUT"), (SPINE[2], 60, (0, 0, 0)),
        (NECK[0], 0, (0, 0, 0)), (NECK[0], 16, (-30, 0, 0), "SINE", "EASE_IN"),
        (NECK[0], 34, (-42, 0, 0), "QUAD", "EASE_OUT"), (NECK[0], 60, (0, 0, 0)),
        (HEAD, 0, (0, 0, 0)), (HEAD, 16, (-24, 0, 0), "SINE", "EASE_IN"),
        (HEAD, 34, (-34, 0, 0), "QUAD", "EASE_OUT"), (HEAD, 60, (0, 0, 0)),
        (JAW, 0, (0, 0, 0)), (JAW, 18, (6, 0, 0), "SINE", "EASE_IN"),
        (JAW, 32, (30, 0, 0), "QUAD", "EASE_OUT"), (JAW, 48, (26, 0, 0)),
        (JAW, 60, (0, 0, 0)),
    ]
    for side in ("L", "R"):
        arm = ARMS[side]
        s = 1.0 if side == "L" else -1.0
        phase_roar += [(arm[0], 0, (0, 0, 0)), (arm[0], 14, (0, 0, 26 * s), "SINE", "EASE_IN"),
                       (arm[0], 34, (0, 0, 44 * s), "QUAD", "EASE_OUT"), (arm[0], 60, (0, 0, 0)),
                       (arm[1], 0, (0, 0, 0)), (arm[1], 16, (-40, 0, 30 * s), "SINE", "EASE_IN"),
                       (arm[1], 36, (-58, 0, 46 * s), "QUAD", "EASE_OUT"), (arm[1], 60, (0, 0, 0)),
                       (arm[2], 0, (0, 0, 0)), (arm[2], 18, (-34, 0, 0), "SINE", "EASE_IN"),
                       (arm[2], 60, (0, 0, 0))]
    phase_roar += _tail_whip([14, 30, 46, 60], 16.0)

    # core_break: a sharp flinch when a shoulder/back core is destroyed
    core_break = [
        (SPINE[1], 0, (0, 0, 0)), (SPINE[1], 3, (20, 0, -16), "QUAD", "EASE_OUT"),
        (SPINE[1], 10, (-6, 0, 6), "SINE", "EASE_IN"), (SPINE[1], 20, (0, 0, 0)),
        (SPINE[2], 0, (0, 0, 0)), (SPINE[2], 3, (16, 0, 14), "QUAD", "EASE_OUT"),
        (SPINE[2], 20, (0, 0, 0)),
        (HEAD, 0, (0, 0, 0)), (HEAD, 3, (26, 0, -18), "QUAD", "EASE_OUT"),
        (HEAD, 12, (-8, 0, 6), "SINE", "EASE_IN"), (HEAD, 20, (0, 0, 0)),
        (HIP, 0, None, "QUAD", "EASE_OUT", (0, 0, 0)),
        (HIP, 3, None, "QUAD", "EASE_OUT", (0, -0.5, -0.35)),
        (HIP, 20, None, "SINE", "EASE_IN", (0, 0, 0)),
        (JAW, 0, (0, 0, 0)), (JAW, 4, (26, 0, 0), "QUAD", "EASE_OUT"), (JAW, 20, (0, 0, 0)),
    ]
    core_break += _tail_whip([4, 9, 14, 20], 10.0)

    # death_fall: 3 s, topples backwards over the deck edge (the boss death the flow unit calls)
    fall = [
        (HIP, 0, None, "SINE", "EASE_IN", (0, 0, 0)),
        (HIP, 16, None, "QUAD", "EASE_IN", (0, -1.2, -0.6)),
        (HIP, 40, None, "QUAD", "EASE_IN", (0, -3.4, -1.8)),
        (HIP, 58, None, "QUAD", "EASE_OUT", (0, -5.2, -4.6)),
        (HIP, 72, None, "SINE", "EASE_OUT", (0, -5.6, -6.4)),
        (PELVIS, 0, (0, 0, 0)), (PELVIS, 20, (22, 0, 6), "SINE", "EASE_IN"),
        (PELVIS, 48, (40, 0, 10), "QUAD", "EASE_OUT"), (PELVIS, 72, (46, 0, 12)),
        (SPINE[0], 0, (0, 0, 0)), (SPINE[0], 18, (16, 0, 0), "SINE", "EASE_IN"),
        (SPINE[0], 72, (34, 0, -6)),
        (SPINE[2], 0, (0, 0, 0)), (SPINE[2], 24, (-18, 0, 0), "SINE", "EASE_IN"),
        (SPINE[2], 72, (-30, 0, 8)),
        (HEAD, 0, (0, 0, 0)), (HEAD, 14, (-26, 0, 0), "SINE", "EASE_IN"),
        (HEAD, 40, (18, 0, 0), "QUAD", "EASE_OUT"), (HEAD, 72, (26, 0, 0)),
        (JAW, 0, (0, 0, 0)), (JAW, 10, (22, 0, 0), "QUAD", "EASE_OUT"), (JAW, 72, (14, 0, 0)),
    ]
    for side in ("L", "R"):
        arm = ARMS[side]
        s = 1.0 if side == "L" else -1.0
        fall += [(arm[0], 0, (0, 0, 0)), (arm[0], 20, (0, 0, 22 * s), "SINE", "EASE_IN"),
                 (arm[0], 72, (0, 0, 30 * s)),
                 (arm[1], 0, (0, 0, 0)), (arm[1], 24, (-46, 0, 26 * s), "SINE", "EASE_IN"),
                 (arm[1], 52, (-14, 0, 8 * s), "QUAD", "EASE_OUT"), (arm[1], 72, (-8, 0, 4 * s)),
                 (arm[2], 0, (0, 0, 0)), (arm[2], 26, (-38, 0, 0), "SINE", "EASE_IN"),
                 (arm[2], 72, (-16, 0, 0))]
        leg = LEGS[side]
        fall += [(leg[0], 0, (0, 0, 0)), (leg[0], 22, (-34, 0, 6 * s), "SINE", "EASE_IN"),
                 (leg[0], 50, (26, 0, 0), "QUAD", "EASE_OUT"), (leg[0], 72, (34, 0, 0)),
                 (leg[1], 0, (0, 0, 0)), (leg[1], 24, (-56, 0, 0), "SINE", "EASE_IN"),
                 (leg[1], 72, (-24, 0, 0))]
    fall += _tail_whip([18, 34, 52, 72], 20.0)
    return {"tail_sweep": tail_sweep, "climb_over": climb, "phase_roar": phase_roar,
            "core_break": core_break, "death_fall": fall}
