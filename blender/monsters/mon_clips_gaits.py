"""The fast gaits (monster-assets, lead r3): ripper scuttle, spitter scuttle, juggernaut charge run.

The Tripo loops are marches in place authored near a human walking speed — a ripper's walk measures
0.41 m/s of foot sweep against a body the AI drives at 30 m/s, so no playback rate can make them
carry the gameplay speeds. These are authored instead, with the keyframe DSL, at the fastest cycle
that still reads: a big asymmetric leg sweep (slow gather, fast drive, hard fold on the recovery), a
body bob and pitch locked to it, and the weight in the ease curves.

`shape` curves are sampled every frame, so the stance/swing split is authored directly instead of
falling out of five fixed keys: `u` is the fraction of the cycle, and the hip/knee/ankle angles are
world-intuitive degrees (see `mon_anims.axis_signs`).
"""
import math
from typing import List, Tuple

#: one leg's cycle as (u, hip, knee, ankle) control points, looping from u=0 to u=1
SCUTTLE_SHAPE: List[Tuple[float, float, float, float]] = [
    (0.00, 46.0, -22.0, 18.0),    # reaching forward, about to plant
    (0.16, 22.0, -10.0, 4.0),     # planted ahead of the body
    (0.52, -52.0, -16.0, -12.0),  # the drive: most of the sweep happens here
    (0.64, -40.0, -74.0, -26.0),  # toe off, leg folds
    (0.82, 12.0, -88.0, 12.0),    # folded, swinging through under the body
    (1.00, 46.0, -22.0, 18.0),
]
RUN_SHAPE: List[Tuple[float, float, float, float]] = [
    (0.00, 38.0, -34.0, 14.0),    # contact, foot well ahead
    (0.22, 8.0, -22.0, 2.0),      # body passing over the planted leg
    (0.54, -34.0, -12.0, -16.0),  # toe off — the push
    (0.68, -22.0, -78.0, -20.0),  # heel folds up
    (0.86, 14.0, -82.0, 6.0),     # knee leads the swing through
    (1.00, 38.0, -34.0, 14.0),
]
#: Per-joint (hip, knee, ankle) gains. The hip carries the stride; the knee and ankle are damped on
#: the bigger animals so a 12 m and a 22 m body do not fold their legs as hard as a 6 m one.
RIPPER_GAINS = (1.0, 1.0, 1.0)
SPITTER_GAINS = (1.15, 0.55, 0.7)
JUGGERNAUT_GAINS = (1.35, 0.28, 0.45)


def _sample(shape, u: float) -> Tuple[float, float, float]:
    """Linear read of a looping shape curve at cycle fraction `u` (in 0..1)."""
    u = u % 1.0
    for i in range(len(shape) - 1):
        a, b = shape[i], shape[i + 1]
        if a[0] <= u <= b[0]:
            t = (u - a[0]) / max(b[0] - a[0], 1e-6)
            # ease the transition so the sampled keys do not read as a linear machine
            t = t * t * (3.0 - 2.0 * t)
            return tuple(a[j + 1] + (b[j + 1] - a[j + 1]) * t for j in range(3))
    return shape[-1][1], shape[-1][2], shape[-1][3]


def leg_cycle(bones: List[str], phase: float, period: int, shape, gains=(1.0, 1.0, 1.0),
              splay: float = 0.0) -> list:
    """Key one leg through a whole cycle, sampled every frame so the loop is exact.

    `gains` scales the hip, knee and ankle separately. The hip gain is the stride: it is what makes
    the foot sweep further and the clip carry more speed. The knee and ankle are scaled *down* on a
    heavy animal, because folding a 22 m leg as hard as a 6 m one curls the whole body into a ball —
    which is exactly what a single gain did to the juggernaut's charge run."""
    keys = []
    for frame in range(period + 1):
        angles = _sample(shape, frame / float(period) + phase)
        u = (frame / float(period) + phase) % 1.0
        interp, ease = ("QUAD", "EASE_OUT") if u < 0.55 else ("SINE", "EASE_IN")
        for i, angle in enumerate(angles):
            if i >= len(bones):
                break
            keys.append((bones[i], frame, (angle * gains[i], 0.0, splay), interp, ease))
    return keys


def _bob(root: str, period: int, low: float, high: float, lean: float, spine: List[str],
         pitch: float = 0.0) -> list:
    """Body bob and pitch locked to the leg cycle: down on the gather, up through the drive.

    The suspension is what sells the speed — the body is at its highest exactly when no leg is
    carrying it."""
    keys = [(root, 0, None, "QUAD", "EASE_OUT", (0.0, 0.0, low)),
            (root, int(period * 0.16), None, "SINE", "EASE_IN", (0.0, lean * 0.4, low * 0.3)),
            (root, int(period * 0.45), None, "QUAD", "EASE_OUT", (0.0, lean, high)),
            (root, int(period * 0.70), None, "SINE", "EASE_IN", (0.0, lean * 0.5, high * 0.35)),
            (root, period, None, "QUAD", "EASE_OUT", (0.0, 0.0, low))]
    for i, bone in enumerate(spine[:2]):
        keys += [(bone, 0, (pitch, 0, 0), "QUAD", "EASE_OUT"),
                 (bone, int(period * 0.45), (-pitch * 1.6, 0, 0), "QUAD", "EASE_OUT"),
                 (bone, period, (pitch, 0, 0), "SINE", "EASE_IN")]
    return keys


def ripper_scuttle(R_ROOT: str, R_SPINE: List[str], R_NECK: List[str], hind: List[List[str]],
                   fore: List[List[str]], tail: List[str], period: int = 8) -> list:
    """A bounding scuttle: the two hind legs drive together, the forelimbs gather half a cycle
    later. 8 frames at 24 fps = 0.333 s a cycle, the fastest that still reads as legs."""
    keys = _bob(R_ROOT, period, 0.0, 0.42, 0.10, R_SPINE, pitch=9.0)
    for leg, phase, splay in ((hind[0], 0.0, 5.0), (hind[1], 0.04, -5.0),
                              (fore[0], 0.5, 6.0), (fore[1], 0.54, -6.0)):
        keys += leg_cycle(leg, phase, period, SCUTTLE_SHAPE, gains=RIPPER_GAINS, splay=splay)
    # the head leads the gather and the tail whips behind it — the counter-rotation that makes a
    # bounding animal read as one body instead of four legs on a box
    keys += [(R_NECK[0], 0, (-16, 0, 0), "QUAD", "EASE_OUT"),
             (R_NECK[0], int(period * 0.45), (12, 0, 0), "QUAD", "EASE_OUT"),
             (R_NECK[0], period, (-16, 0, 0), "SINE", "EASE_IN"),
             (R_NECK[3], 0, (10, 0, 0), "SINE", "EASE_IN"),
             (R_NECK[3], int(period * 0.5), (-8, 0, 4), "SINE", "EASE_IN"),
             (R_NECK[3], period, (10, 0, 0), "SINE", "EASE_IN")]
    for i, bone in enumerate(tail):
        amp = 4.0 + i * 2.5
        keys += [(bone, 0, (0, 0, -amp), "SINE", "EASE_IN"),
                 (bone, int(period * 0.45), (0, 0, amp), "QUAD", "EASE_OUT"),
                 (bone, period, (0, 0, -amp), "SINE", "EASE_IN")]
    return keys


def spitter_scuttle(root: str, spine: List[str], launch: str, sac: str, legs: List[List[str]],
                    period: int = 12) -> list:
    """The artillery bug at 18 m/s: a four-legged skitter, diagonal pairs together, body flat and
    low, the sac and the launcher bouncing a beat behind the body."""
    keys = _bob(root, period, 0.0, 0.30, 0.06, spine, pitch=6.0)
    for leg, phase in zip(legs, (0.0, 0.5, 0.5, 0.0)):
        keys += leg_cycle(leg, phase, period, SCUTTLE_SHAPE, gains=SPITTER_GAINS, splay=7.0)
    keys += [(launch, 0, (-9, 0, 0), "SINE", "EASE_IN"),
             (launch, int(period * 0.45), (7, 0, 0), "QUAD", "EASE_OUT"),
             (launch, period, (-9, 0, 0), "SINE", "EASE_IN"),
             (sac, 0, (5, 0, 0), "SINE", "EASE_IN"),
             (sac, int(period * 0.55), (-6, 0, 0), "SINE", "EASE_IN"),
             (sac, period, (5, 0, 0), "SINE", "EASE_IN")]
    return keys


def juggernaut_charge_run(root: str, spine: List[str], legs: List[List[str]],
                          arms: List[List[str]], period: int = 20) -> list:
    """22 m of armour at 20 m/s: a heavy run, half a cycle between the legs, the body pitched
    forward over the front foot.

    The arms stay tucked — elbows in, fists up — with only a small pump against the legs. Swung
    like a human's they put the knuckle claws through the floor (`mon_stride` warns when a bone
    outside the contact set reaches the ground, and it fired on exactly these bones).

    The elbow angle is measured, not eyeballed. This animal's arms hang to the floor in the bind
    pose — the claw tips rest at y = 2.4 m against toes at 0.9 m, and they own 200 of the 400 lowest
    vertices in the mesh — so a -78 degree elbow still left the claws 0.64 m *below* the feet through
    the cycle, and no root offset can fix that: pinning the claws to the floor lifts the feet off it
    instead. Folding to -130 degrees puts the claws 4.8 m clear of the feet at every point of the
    pump, which lets the ground lock plant the feet and nothing else. `diag_glb_floor --support`
    measures the clearance on the shipped file."""
    keys = _bob(root, period, 0.0, 0.55, 0.35, spine, pitch=7.0)
    for leg, phase, splay in ((legs[0], 0.0, 3.0), (legs[1], 0.5, -3.0)):
        keys += leg_cycle(leg, phase, period, RUN_SHAPE, gains=JUGGERNAUT_GAINS, splay=splay)
    for arm, phase in ((arms[0], 0.5), (arms[1], 0.0)):
        # contralateral: each arm swings against its own leg, both centred on a tucked -30
        amp = 16.0 * math.cos(2.0 * math.pi * phase)
        keys += [(arm[0], 0, (-30.0 - amp, 0, 22), "SINE", "EASE_IN"),
                 (arm[0], int(period * 0.5), (-30.0 + amp, 0, 26), "QUAD", "EASE_OUT"),
                 (arm[0], period, (-30.0 - amp, 0, 22), "SINE", "EASE_IN"),
                 (arm[1], 0, (-138, 0, 0), "SINE", "EASE_IN"),
                 (arm[1], int(period * 0.5), (-122, 0, 0), "SINE", "EASE_IN"),
                 (arm[1], period, (-138, 0, 0), "SINE", "EASE_IN")]
    return keys
