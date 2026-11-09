"""Scripted clips for the ripper, spitter and harrier (monster-assets).

Angles are world-intuitive (see `mon_anims.axis_signs`): `rx` + swings a bone's tip forward,
`rz` + splays it right. Every clip is shaped with anticipation before the fast part and a slower
settle after it — FEEL.md / juice §2: weight comes from the slow-in, menace from the hold.
"""

from monsters import mon_clips_gaits as gaits

# --- ripper: Tripo gave us `walk` only -------------------------------------------------------
# Bone map read off the rig (status/monster-assets.md): the neck runs 0_Right_Limb_0 -> bone_8,
# the two forelimbs hang off it, the hind legs are the named 0_/1_ limb chains.
R_ROOT = "tripo::Root"
R_SPINE = ["tripo::Spine_0", "tripo::Spine_1"]
R_NECK = ["tripo::0_Right_Limb_0", "bone_4", "bone_5", "bone_6", "bone_7", "bone_8"]
R_FORE_A = ["bone_9", "bone_10", "bone_11", "bone_12"]
R_FORE_B = ["bone_24", "bone_25", "bone_26", "bone_27"]
R_HIND_A = ["tripo::1_Right_Limb_%d" % i for i in range(5)]
R_HIND_B = ["tripo::0_Left_Limb_%d" % i for i in range(5)]
R_TAIL = ["bone_48"] + ["tripo::Tail_%d" % i for i in range(6)]


def _leg_swing(bones: list, phase: float, period: int, hip: float, knee: float,
               ankle: float) -> list:
    """One leg's gait cycle, sampled so the clip loops exactly.

    `phase` is a fraction of the cycle (0.5 = half a cycle out of step). Keys are written at fixed
    frames 0, P/4, P/2, 3P/4, P with the value read at (frame/P + phase) mod 1, so every leg covers
    the whole cycle inside the clip and frame P matches frame 0."""
    def curve(u: float, a: float, b: float, c: float) -> float:
        # u in 0..1: reach forward (a) -> drive back through mid (c) -> fold on the recovery (b)
        if u < 0.35:
            return a + (b - a) * (u / 0.35)
        if u < 0.7:
            return b + (c - b) * ((u - 0.35) / 0.35)
        return c + (a - c) * ((u - 0.7) / 0.3)

    shape = [(hip, -hip * 0.2, -hip * 0.85), (-knee * 0.3, -knee, -knee * 0.25),
             (ankle, -ankle, -ankle * 0.5)]
    keys = []
    for i, bone in enumerate(bones[:3]):
        a, b, c = shape[i]
        for k in range(5):
            frame = int(round(k * period / 4.0))
            u = (k / 4.0 + phase) % 1.0
            v = curve(u, a, b, c)
            interp, ease = ("QUAD", "EASE_OUT") if 0.35 <= u < 0.7 else ("SINE", "EASE_IN")
            keys.append((bone, frame, (v, 0, 0), interp, ease))
    return keys


def ripper_clips() -> dict:
    """idle / run / leap / bite / hit / death — the swarmer's whole readable vocabulary."""
    idle_tail = []
    for i, bone in enumerate(R_TAIL[1:], start=1):
        amp = 2.0 + i * 1.6
        delay = i * 2
        idle_tail += [(bone, 0, (0, 0, 0)), (bone, 14 + delay, (0, 0, amp), "SINE", "EASE_IN"),
                      (bone, 34 + delay, (0, 0, -amp * 0.7), "SINE", "EASE_IN"),
                      (bone, 48, (0, 0, 0))]
    idle = [
        (R_SPINE[0], 0, (0, 0, 0)), (R_SPINE[0], 16, (3.5, 0, 0), "SINE", "EASE_IN"),
        (R_SPINE[0], 34, (-1.5, 0, 0), "SINE", "EASE_IN"), (R_SPINE[0], 48, (0, 0, 0)),
        (R_SPINE[1], 0, (0, 0, 0)), (R_SPINE[1], 20, (-2.5, 0, 1.5), "SINE", "EASE_IN"),
        (R_SPINE[1], 48, (0, 0, 0)),
        (R_ROOT, 0, None, "SINE", "EASE_IN", (0, 0, 0)),
        (R_ROOT, 18, None, "SINE", "EASE_IN", (0, 0, 0.06)),
        (R_ROOT, 48, None, "SINE", "EASE_IN", (0, 0, 0)),
        (R_NECK[3], 0, (0, 0, 0)), (R_NECK[3], 22, (-6, 0, 5), "SINE", "EASE_IN"),
        (R_NECK[3], 48, (0, 0, 0)),
        (R_NECK[5], 0, (0, 0, 0)), (R_NECK[5], 10, (5, 0, 0), "SINE", "EASE_IN"),
        (R_NECK[5], 26, (-4, 0, 0), "SINE", "EASE_IN"), (R_NECK[5], 48, (0, 0, 0)),
    ] + idle_tail

    run = [
        (R_ROOT, 0, None, "QUAD", "EASE_OUT", (0, 0, 0.0)),
        (R_ROOT, 4, None, "SINE", "EASE_IN", (0, 0, 0.30)),
        (R_ROOT, 9, None, "QUAD", "EASE_OUT", (0, 0, -0.05)),
        (R_ROOT, 14, None, "SINE", "EASE_IN", (0, 0, 0.0)),
        (R_SPINE[0], 0, (-7, 0, 0)), (R_SPINE[0], 5, (6, 0, 0), "QUAD", "EASE_OUT"),
        (R_SPINE[0], 10, (-5, 0, 0), "QUAD", "EASE_OUT"), (R_SPINE[0], 14, (-7, 0, 0)),
        (R_SPINE[1], 0, (4, 0, 0)), (R_SPINE[1], 6, (-6, 0, 0), "QUAD", "EASE_OUT"),
        (R_SPINE[1], 14, (4, 0, 0)),
        (R_NECK[0], 0, (-10, 0, 0)), (R_NECK[0], 7, (4, 0, 0), "QUAD", "EASE_OUT"),
        (R_NECK[0], 14, (-10, 0, 0)),
    ]
    run += _leg_swing(R_HIND_A, 0.0, 14, 34, 40, 16)
    run += _leg_swing(R_HIND_B, 0.5, 14, 34, 40, 16)
    run += _leg_swing(R_FORE_A, 0.5, 14, 30, 34, 14)
    run += _leg_swing(R_FORE_B, 0.0, 14, 30, 34, 14)

    scuttle = gaits.ripper_scuttle(R_ROOT, R_SPINE, R_NECK, [R_HIND_A, R_HIND_B],
                                   [R_FORE_A, R_FORE_B], R_TAIL[1:4])

    leap = [
        # 0-7 crouch (the 0.45 s telegraph the parry reads), 8-11 launch, 12-17 airborne, 18-24 land
        (R_ROOT, 0, None, "SINE", "EASE_IN", (0, 0, 0)),
        (R_ROOT, 7, None, "QUAD", "EASE_IN", (0, -0.35, -0.45)),
        (R_ROOT, 11, None, "QUAD", "EASE_OUT", (0, 0.2, 0.55)),
        (R_ROOT, 16, None, "SINE", "EASE_IN", (0, 0.2, 0.35)),
        (R_ROOT, 24, None, "QUAD", "EASE_OUT", (0, 0, 0)),
        (R_SPINE[0], 0, (0, 0, 0)), (R_SPINE[0], 7, (16, 0, 0), "SINE", "EASE_IN"),
        (R_SPINE[0], 11, (-18, 0, 0), "QUAD", "EASE_OUT"), (R_SPINE[0], 24, (0, 0, 0)),
        (R_SPINE[1], 0, (0, 0, 0)), (R_SPINE[1], 7, (10, 0, 0), "SINE", "EASE_IN"),
        (R_SPINE[1], 11, (-14, 0, 0), "QUAD", "EASE_OUT"), (R_SPINE[1], 24, (0, 0, 0)),
        (R_NECK[0], 0, (0, 0, 0)), (R_NECK[0], 7, (14, 0, 0), "SINE", "EASE_IN"),
        (R_NECK[0], 12, (-22, 0, 0), "QUAD", "EASE_OUT"), (R_NECK[0], 24, (0, 0, 0)),
        (R_NECK[5], 0, (0, 0, 0)), (R_NECK[5], 8, (16, 0, 0), "SINE", "EASE_IN"),
        (R_NECK[5], 12, (-26, 0, 0), "QUAD", "EASE_OUT"), (R_NECK[5], 20, (-8, 0, 0)),
        (R_NECK[5], 24, (0, 0, 0)),
    ]
    for hind in (R_HIND_A, R_HIND_B):
        leap += [(hind[0], 0, (0, 0, 0)), (hind[0], 7, (-38, 0, 0), "SINE", "EASE_IN"),
                 (hind[0], 11, (46, 0, 0), "QUAD", "EASE_OUT"), (hind[0], 18, (18, 0, 0)),
                 (hind[0], 24, (0, 0, 0)),
                 (hind[1], 0, (0, 0, 0)), (hind[1], 7, (-52, 0, 0), "SINE", "EASE_IN"),
                 (hind[1], 12, (20, 0, 0), "QUAD", "EASE_OUT"), (hind[1], 24, (0, 0, 0))]
    for fore in (R_FORE_A, R_FORE_B):
        leap += [(fore[0], 0, (0, 0, 0)), (fore[0], 7, (26, 0, 0), "SINE", "EASE_IN"),
                 (fore[0], 12, (-40, 0, 0), "QUAD", "EASE_OUT"), (fore[0], 24, (0, 0, 0)),
                 (fore[1], 0, (0, 0, 0)), (fore[1], 12, (34, 0, 0), "QUAD", "EASE_OUT"),
                 (fore[1], 24, (0, 0, 0))]

    bite = [
        (R_SPINE[1], 0, (0, 0, 0)), (R_SPINE[1], 4, (9, 0, 0), "SINE", "EASE_IN"),
        (R_SPINE[1], 8, (-11, 0, 0), "QUAD", "EASE_OUT"), (R_SPINE[1], 17, (0, 0, 0)),
        (R_NECK[1], 0, (0, 0, 0)), (R_NECK[1], 4, (12, 0, 0), "SINE", "EASE_IN"),
        (R_NECK[1], 8, (-16, 0, 0), "QUAD", "EASE_OUT"), (R_NECK[1], 17, (0, 0, 0)),
        (R_NECK[4], 0, (0, 0, 0)), (R_NECK[4], 5, (18, 0, 0), "SINE", "EASE_IN"),
        (R_NECK[4], 8, (-24, 0, 0), "QUAD", "EASE_OUT"), (R_NECK[4], 17, (0, 0, 0)),
        (R_NECK[5], 0, (0, 0, 0)), (R_NECK[5], 4, (22, 0, 0), "SINE", "EASE_IN"),
        (R_NECK[5], 8, (-34, 0, 0), "QUAD", "EASE_OUT"), (R_NECK[5], 12, (-16, 0, 0)),
        (R_NECK[5], 17, (0, 0, 0)),
    ]

    hit = [
        (R_SPINE[0], 0, (0, 0, 0)), (R_SPINE[0], 2, (14, 0, -7), "QUAD", "EASE_OUT"),
        (R_SPINE[0], 6, (-4, 0, 3), "SINE", "EASE_IN"), (R_SPINE[0], 10, (0, 0, 0)),
        (R_SPINE[1], 0, (0, 0, 0)), (R_SPINE[1], 2, (10, 0, 6), "QUAD", "EASE_OUT"),
        (R_SPINE[1], 10, (0, 0, 0)),
        (R_NECK[0], 0, (0, 0, 0)), (R_NECK[0], 2, (22, 0, -12), "QUAD", "EASE_OUT"),
        (R_NECK[0], 10, (0, 0, 0)),
        (R_ROOT, 0, None, "QUAD", "EASE_OUT", (0, 0, 0)),
        (R_ROOT, 2, None, "QUAD", "EASE_OUT", (0, -0.22, 0.05)),
        (R_ROOT, 10, None, "SINE", "EASE_IN", (0, 0, 0)),
    ]

    death = [
        (R_ROOT, 0, None, "SINE", "EASE_IN", (0, 0, 0)),
        (R_ROOT, 8, None, "QUAD", "EASE_IN", (0, 0, -0.18)),
        (R_ROOT, 18, None, "QUAD", "EASE_IN", (0, 0, -0.62)),
        (R_ROOT, 29, None, "SINE", "EASE_OUT", (0, 0, -0.70)),
        (R_SPINE[0], 0, (0, 0, 0)), (R_SPINE[0], 10, (24, 0, 10), "SINE", "EASE_IN"),
        (R_SPINE[0], 22, (34, 0, 16), "QUAD", "EASE_OUT"), (R_SPINE[0], 29, (30, 0, 14)),
        (R_SPINE[1], 0, (0, 0, 0)), (R_SPINE[1], 12, (18, 0, -8), "SINE", "EASE_IN"),
        (R_SPINE[1], 29, (26, 0, -12)),
        (R_NECK[0], 0, (0, 0, 0)), (R_NECK[0], 14, (30, 0, 0), "SINE", "EASE_IN"),
        (R_NECK[0], 29, (38, 0, 0)),
        (R_NECK[5], 0, (0, 0, 0)), (R_NECK[5], 9, (-14, 0, 0), "SINE", "EASE_IN"),
        (R_NECK[5], 16, (10, 0, 0), "SINE", "EASE_IN"), (R_NECK[5], 29, (6, 0, 0)),
    ]
    for leg in (R_HIND_A, R_HIND_B, R_FORE_A, R_FORE_B):
        death += [(leg[0], 0, (0, 0, 0)), (leg[0], 12, (-46, 0, 14), "SINE", "EASE_IN"),
                  (leg[0], 29, (-58, 0, 20)),
                  (leg[1], 0, (0, 0, 0)), (leg[1], 12, (-58, 0, 0), "SINE", "EASE_IN"),
                  (leg[1], 29, (-70, 0, 0))]
    return {"idle": idle, "run": run, "scuttle": scuttle, "leap": leap, "bite": bite, "hit": hit,
            "death": death}


# --- spitter: everything is scripted, Tripo refused to rig it -----------------------------------
S_ROOT = "Root"
S_SPINE = ["Spine_0", "Spine_1", "Spine_2"]
S_LAUNCH = ["Launcher_0", "Launcher_1"]
S_SAC = "Sac"
S_LEGS = [["Leg%s_%d" % (n, i) for i in range(3)]
          for n in ("FL", "FR", "BL", "BR")]


def spitter_clips() -> dict:
    """idle / walk / fire / hit / death. `fire` is the readable one: crouch, sac contracts, launcher
    recoils (SPEC §7 artillery; the lob arc is timed off this clip's length)."""
    idle = [
        (S_ROOT, 0, None, "SINE", "EASE_IN", (0, 0, 0)),
        (S_ROOT, 20, None, "SINE", "EASE_IN", (0, 0, 0.07)),
        (S_ROOT, 44, None, "SINE", "EASE_IN", (0, 0, 0)),
        (S_SPINE[1], 0, (0, 0, 0)), (S_SPINE[1], 22, (2.5, 0, 0), "SINE", "EASE_IN"),
        (S_SPINE[1], 44, (0, 0, 0)),
        (S_SPINE[2], 0, (0, 0, 0)), (S_SPINE[2], 16, (-3, 0, 2), "SINE", "EASE_IN"),
        (S_SPINE[2], 44, (0, 0, 0)),
        (S_LAUNCH[0], 0, (0, 0, 0)), (S_LAUNCH[0], 18, (4, 0, -3), "SINE", "EASE_IN"),
        (S_LAUNCH[0], 44, (0, 0, 0)),
        (S_SAC, 0, (0, 0, 0)), (S_SAC, 24, (3, 0, 0), "SINE", "EASE_IN"),
        (S_SAC, 44, (0, 0, 0)),
    ]

    walk = [(S_ROOT, 0, None, "QUAD", "EASE_OUT", (0, 0, 0.0)),
            (S_ROOT, 7, None, "SINE", "EASE_IN", (0, 0, 0.16)),
            (S_ROOT, 16, None, "QUAD", "EASE_OUT", (0, 0, -0.03)),
            (S_ROOT, 24, None, "SINE", "EASE_IN", (0, 0, 0.0)),
            (S_SPINE[1], 0, (0, 0, 0)), (S_SPINE[1], 8, (3, 0, 2.5), "SINE", "EASE_IN"),
            (S_SPINE[1], 18, (-2, 0, -2.5), "SINE", "EASE_IN"), (S_SPINE[1], 24, (0, 0, 0)),
            (S_LAUNCH[0], 0, (0, 0, 0)), (S_LAUNCH[0], 12, (-3, 0, 0), "SINE", "EASE_IN"),
            (S_LAUNCH[0], 24, (0, 0, 0))]
    for leg, phase in zip(S_LEGS, (0.0, 0.5, 0.5, 0.0)):
        walk += _leg_swing(leg, phase, 24, 22, 26, 10)

    scuttle = gaits.spitter_scuttle(S_ROOT, S_SPINE, S_LAUNCH[0], S_SAC, S_LEGS)

    fire = [
        # 0-9 settle and draw the sac in (telegraph), 10-13 spit, 14-24 recover
        (S_ROOT, 0, None, "SINE", "EASE_IN", (0, 0, 0)),
        (S_ROOT, 9, None, "QUAD", "EASE_IN", (0, -0.15, -0.42)),
        (S_ROOT, 13, None, "QUAD", "EASE_OUT", (0, 0.1, 0.18)),
        (S_ROOT, 24, None, "SINE", "EASE_IN", (0, 0, 0)),
        (S_SPINE[0], 0, (0, 0, 0)), (S_SPINE[0], 9, (14, 0, 0), "SINE", "EASE_IN"),
        (S_SPINE[0], 13, (-8, 0, 0), "QUAD", "EASE_OUT"), (S_SPINE[0], 24, (0, 0, 0)),
        (S_SPINE[2], 0, (0, 0, 0)), (S_SPINE[2], 9, (16, 0, 0), "SINE", "EASE_IN"),
        (S_SPINE[2], 13, (-20, 0, 0), "QUAD", "EASE_OUT"), (S_SPINE[2], 24, (0, 0, 0)),
        (S_SAC, 0, (0, 0, 0)), (S_SAC, 9, (26, 0, 0), "SINE", "EASE_IN"),
        (S_SAC, 12, (-14, 0, 0), "QUAD", "EASE_OUT"), (S_SAC, 24, (0, 0, 0)),
        (S_LAUNCH[0], 0, (0, 0, 0)), (S_LAUNCH[0], 9, (26, 0, 0), "SINE", "EASE_IN"),
        (S_LAUNCH[0], 13, (-30, 0, 0), "QUAD", "EASE_OUT"), (S_LAUNCH[0], 24, (0, 0, 0)),
        (S_LAUNCH[1], 0, (0, 0, 0)), (S_LAUNCH[1], 9, (18, 0, 0), "SINE", "EASE_IN"),
        (S_LAUNCH[1], 12, (-22, 0, 0), "QUAD", "EASE_OUT"), (S_LAUNCH[1], 20, (6, 0, 0)),
        (S_LAUNCH[1], 24, (0, 0, 0)),
    ]
    for leg in S_LEGS:
        fire += [(leg[0], 0, (0, 0, 0)), (leg[0], 9, (-20, 0, 6), "SINE", "EASE_IN"),
                 (leg[0], 13, (6, 0, 0), "QUAD", "EASE_OUT"), (leg[0], 24, (0, 0, 0)),
                 (leg[1], 0, (0, 0, 0)), (leg[1], 9, (-30, 0, 0), "SINE", "EASE_IN"),
                 (leg[1], 24, (0, 0, 0))]

    hit = [
        (S_SPINE[1], 0, (0, 0, 0)), (S_SPINE[1], 2, (10, 0, -8), "QUAD", "EASE_OUT"),
        (S_SPINE[1], 12, (0, 0, 0)),
        (S_SPINE[2], 0, (0, 0, 0)), (S_SPINE[2], 2, (14, 0, 9), "QUAD", "EASE_OUT"),
        (S_SPINE[2], 12, (0, 0, 0)),
        (S_LAUNCH[0], 0, (0, 0, 0)), (S_LAUNCH[0], 2, (20, 0, -14), "QUAD", "EASE_OUT"),
        (S_LAUNCH[0], 12, (0, 0, 0)),
        (S_ROOT, 0, None, "QUAD", "EASE_OUT", (0, 0, 0)),
        (S_ROOT, 2, None, "QUAD", "EASE_OUT", (0, -0.25, 0.04)),
        (S_ROOT, 12, None, "SINE", "EASE_IN", (0, 0, 0)),
    ]

    death = [
        (S_ROOT, 0, None, "SINE", "EASE_IN", (0, 0, 0)),
        (S_ROOT, 14, None, "QUAD", "EASE_IN", (0, 0, -0.30)),
        (S_ROOT, 34, None, "SINE", "EASE_OUT", (0, 0, -0.86)),
        (S_SPINE[0], 0, (0, 0, 0)), (S_SPINE[0], 16, (22, 0, 12), "SINE", "EASE_IN"),
        (S_SPINE[0], 34, (30, 0, 18)),
        (S_SPINE[2], 0, (0, 0, 0)), (S_SPINE[2], 18, (26, 0, -10), "SINE", "EASE_IN"),
        (S_SPINE[2], 34, (34, 0, -14)),
        (S_LAUNCH[0], 0, (0, 0, 0)), (S_LAUNCH[0], 20, (30, 0, 0), "SINE", "EASE_IN"),
        (S_LAUNCH[0], 34, (40, 0, 0)),
        (S_SAC, 0, (0, 0, 0)), (S_SAC, 10, (-18, 0, 0), "QUAD", "EASE_OUT"),
        (S_SAC, 22, (14, 0, 0), "SINE", "EASE_IN"), (S_SAC, 34, (10, 0, 0)),
    ]
    for leg in S_LEGS:
        death += [(leg[0], 0, (0, 0, 0)), (leg[0], 16, (-52, 0, 16), "SINE", "EASE_IN"),
                  (leg[0], 34, (-64, 0, 22)),
                  (leg[1], 0, (0, 0, 0)), (leg[1], 16, (-62, 0, 0), "SINE", "EASE_IN"),
                  (leg[1], 34, (-76, 0, 0))]
    return {"idle": idle, "walk": walk, "scuttle": scuttle, "fire": fire, "hit": hit,
            "death": death}


# --- juggernaut: Tripo's clips are all attacks and idles; the charge gait is ours ---------------
J_ROOT = "BoneRoot"
J_SPINE = ["Spine01", "Spine02"]
J_LEGS = [["L_Thigh", "L_Calf", "L_Foot"], ["R_Thigh", "R_Calf", "R_Foot"]]
J_ARMS = [["L_Upperarm", "L_Forearm"], ["R_Upperarm", "R_Forearm"]]


def juggernaut_clips() -> dict:
    """The charge run only — Tripo's `charge` is a wind-up-and-hit attack the enemies unit plays
    as an action, so the looping gait that carries 20 m/s has to be authored (lead r3)."""
    return {"charge_run": gaits.juggernaut_charge_run(J_ROOT, J_SPINE, J_LEGS, J_ARMS)}


# --- harrier: everything is scripted; the wings carry the whole read ------------------------------
H_ROOT = "Root"
H_SPINE = ["Spine_0", "Spine_1", "Spine_2"]
H_HEAD = ["Head_0", "Head_1"]
H_TAIL = ["Tail_0", "Tail_1", "Tail_2"]
H_LEGS = [["LegL_0", "LegL_1"], ["LegR_0", "LegR_1"]]
H_WINGS = [["WingL_%d" % i for i in range(3)], ["WingR_%d" % i for i in range(3)]]


def _flap(period: int, up: float, down: float, sweep: float, lag: int = 2) -> list:
    """One flap cycle for both wings. The outer joints lag the inner ones — that lag is what makes a
    membrane wing look like a wing instead of a plank."""
    keys = []
    for side, wing in enumerate(H_WINGS):
        for j, bone in enumerate(wing):
            scale = 1.0 - 0.18 * j
            d = j * lag
            keys += [
                (bone, 0, (down * scale, 0, sweep * 0.3), "SINE", "EASE_IN"),
                (bone, period // 4 + d, (up * scale, 0, -sweep * 0.4), "QUAD", "EASE_OUT"),
                (bone, period // 2 + d, (up * scale * 0.5, 0, 0), "SINE", "EASE_IN"),
                (bone, (period * 3) // 4 + d, (down * scale, 0, sweep * 0.5), "QUAD", "EASE_OUT"),
                (bone, period, (down * scale, 0, sweep * 0.3), "SINE", "EASE_IN"),
            ]
    return keys


def harrier_clips() -> dict:
    """fly / glide / dive / strafe / hit / death (SPEC §7 flyer: strafing runs, dive bombs)."""
    fly = [(H_ROOT, 0, None, "SINE", "EASE_IN", (0, 0, 0.0)),
           (H_ROOT, 4, None, "QUAD", "EASE_OUT", (0, 0, 0.28)),
           (H_ROOT, 9, None, "SINE", "EASE_IN", (0, 0, -0.12)),
           (H_ROOT, 14, None, "SINE", "EASE_IN", (0, 0, 0.0)),
           (H_SPINE[0], 0, (-6, 0, 0)), (H_SPINE[0], 7, (2, 0, 0), "SINE", "EASE_IN"),
           (H_SPINE[0], 14, (-6, 0, 0)),
           (H_SPINE[2], 0, (4, 0, 0)), (H_SPINE[2], 7, (-3, 0, 0), "SINE", "EASE_IN"),
           (H_SPINE[2], 14, (4, 0, 0)),
           (H_HEAD[0], 0, (-4, 0, 0)), (H_HEAD[0], 14, (-4, 0, 0))]
    fly += _flap(14, 46, -34, 14)
    for i, bone in enumerate(H_TAIL):
        fly += [(bone, 0, (0, 0, 3 + i * 2)), (bone, 7, (0, 0, -(3 + i * 2)), "SINE", "EASE_IN"),
                (bone, 14, (0, 0, 3 + i * 2))]

    glide = [(H_ROOT, 0, None, "SINE", "EASE_IN", (0, 0, 0.0)),
             (H_ROOT, 24, None, "SINE", "EASE_IN", (0, 0, 0.10)),
             (H_ROOT, 48, None, "SINE", "EASE_IN", (0, 0, 0.0)),
             (H_SPINE[0], 0, (-3, 0, 0)), (H_SPINE[0], 26, (-6, 0, 2), "SINE", "EASE_IN"),
             (H_SPINE[0], 48, (-3, 0, 0)),
             (H_SPINE[2], 0, (3, 0, 0)), (H_SPINE[2], 26, (5, 0, -2), "SINE", "EASE_IN"),
             (H_SPINE[2], 48, (3, 0, 0))]
    for side, wing in enumerate(H_WINGS):
        for j, bone in enumerate(wing):
            lift = 12.0 - 3.0 * j
            glide += [(bone, 0, (lift, 0, -6 - 2 * j), "SINE", "EASE_IN"),
                      (bone, 26, (lift + 5, 0, -10 - 2 * j), "SINE", "EASE_IN"),
                      (bone, 48, (lift, 0, -6 - 2 * j), "SINE", "EASE_IN")]
    for i, bone in enumerate(H_TAIL):
        glide += [(bone, 0, (0, 0, 0)), (bone, 26, (0, 0, 4 + i * 2), "SINE", "EASE_IN"),
                  (bone, 48, (0, 0, 0))]

    dive = [
        # 0-6 spread and screech (the 0.5 s unblockable telegraph), 7-16 fold and drop, 17-26 pull out
        (H_ROOT, 0, None, "SINE", "EASE_IN", (0, 0, 0)),
        (H_ROOT, 7, None, "QUAD", "EASE_IN", (0, 0.2, 0.35)),
        (H_ROOT, 16, None, "QUAD", "EASE_OUT", (0, 0.2, -0.25)),
        (H_ROOT, 26, None, "SINE", "EASE_IN", (0, 0, 0)),
        (H_SPINE[0], 0, (0, 0, 0)), (H_SPINE[0], 6, (-16, 0, 0), "SINE", "EASE_IN"),
        (H_SPINE[0], 14, (30, 0, 0), "QUAD", "EASE_OUT"), (H_SPINE[0], 26, (0, 0, 0)),
        (H_SPINE[2], 0, (0, 0, 0)), (H_SPINE[2], 6, (14, 0, 0), "SINE", "EASE_IN"),
        (H_SPINE[2], 14, (-26, 0, 0), "QUAD", "EASE_OUT"), (H_SPINE[2], 26, (0, 0, 0)),
        (H_HEAD[1], 0, (0, 0, 0)), (H_HEAD[1], 6, (-24, 0, 0), "SINE", "EASE_IN"),
        (H_HEAD[1], 12, (16, 0, 0), "QUAD", "EASE_OUT"), (H_HEAD[1], 26, (0, 0, 0)),
    ]
    for wing in H_WINGS:
        for j, bone in enumerate(wing):
            dive += [(bone, 0, (0, 0, 0)), (bone, 6, (34 - 6 * j, 0, -26), "SINE", "EASE_IN"),
                     (bone, 13, (-16 + 4 * j, 0, 58), "QUAD", "EASE_OUT"),
                     (bone, 20, (6, 0, 22), "SINE", "EASE_IN"), (bone, 26, (0, 0, 0))]

    strafe = [(H_ROOT, 0, None, "SINE", "EASE_IN", (0, 0, 0)),
              (H_ROOT, 12, None, "SINE", "EASE_IN", (0, 0, 0.16)),
              (H_ROOT, 24, None, "SINE", "EASE_IN", (0, 0, 0)),
              (H_SPINE[1], 0, (0, 0, 0)), (H_SPINE[1], 12, (0, 14, 0), "SINE", "EASE_IN"),
              (H_SPINE[1], 24, (0, 0, 0))]
    for side, wing in enumerate(H_WINGS):
        inner, outer = (26, -12) if side == 0 else (-14, 30)
        for j, bone in enumerate(wing):
            bank = inner if j == 0 else outer
            strafe += [(bone, 0, (8, 0, 0), "SINE", "EASE_IN"),
                       (bone, 8 + j * 2, (bank, 0, -14), "QUAD", "EASE_OUT"),
                       (bone, 18 + j * 2, (bank * 0.6, 0, -8), "SINE", "EASE_IN"),
                       (bone, 24, (8, 0, 0), "SINE", "EASE_IN")]
    for i, bone in enumerate(H_TAIL):
        strafe += [(bone, 0, (0, 0, 0)), (bone, 12, (0, 0, -8 - i * 3), "SINE", "EASE_IN"),
                   (bone, 24, (0, 0, 0))]

    hit = [
        (H_SPINE[1], 0, (0, 0, 0)), (H_SPINE[1], 2, (16, 0, -12), "QUAD", "EASE_OUT"),
        (H_SPINE[1], 12, (0, 0, 0)),
        (H_HEAD[0], 0, (0, 0, 0)), (H_HEAD[0], 2, (22, 0, 16), "QUAD", "EASE_OUT"),
        (H_HEAD[0], 12, (0, 0, 0)),
        (H_ROOT, 0, None, "QUAD", "EASE_OUT", (0, 0, 0)),
        (H_ROOT, 2, None, "QUAD", "EASE_OUT", (0, -0.3, 0.12)),
        (H_ROOT, 12, None, "SINE", "EASE_IN", (0, 0, 0)),
    ]
    for wing in H_WINGS:
        for j, bone in enumerate(wing):
            hit += [(bone, 0, (0, 0, 0)), (bone, 2, (-24 - 6 * j, 0, 18), "QUAD", "EASE_OUT"),
                    (bone, 12, (0, 0, 0))]

    death = [
        (H_ROOT, 0, None, "SINE", "EASE_IN", (0, 0, 0)),
        (H_ROOT, 10, None, "QUAD", "EASE_IN", (0, 0, -0.2)),
        (H_ROOT, 30, None, "SINE", "EASE_OUT", (0, 0, -1.0)),
        (H_SPINE[0], 0, (0, 0, 0)), (H_SPINE[0], 14, (34, 0, 18), "SINE", "EASE_IN"),
        (H_SPINE[0], 30, (46, 0, 26)),
        (H_SPINE[2], 0, (0, 0, 0)), (H_SPINE[2], 16, (-28, 0, -14), "SINE", "EASE_IN"),
        (H_SPINE[2], 30, (-36, 0, -20)),
        (H_HEAD[1], 0, (0, 0, 0)), (H_HEAD[1], 18, (30, 0, 0), "SINE", "EASE_IN"),
        (H_HEAD[1], 30, (42, 0, 0)),
    ]
    for wing in H_WINGS:
        for j, bone in enumerate(wing):
            death += [(bone, 0, (0, 0, 0)),
                      (bone, 8 + j * 3, (-40 - 8 * j, 0, 30), "QUAD", "EASE_OUT"),
                      (bone, 22 + j * 3, (24, 0, 46), "SINE", "EASE_IN"),
                      (bone, 30, (16, 0, 40))]
    for i, bone in enumerate(H_TAIL):
        death += [(bone, 0, (0, 0, 0)), (bone, 16, (0, 0, -14 - i * 5), "SINE", "EASE_IN"),
                  (bone, 30, (0, 0, -20 - i * 6))]
    for leg in H_LEGS:
        for bone in leg:
            death += [(bone, 0, (0, 0, 0)), (bone, 14, (36, 0, 0), "SINE", "EASE_IN"),
                      (bone, 30, (48, 0, 0))]
    return {"fly": fly, "glide": glide, "dive": dive, "strafe": strafe, "hit": hit,
            "death": death}
