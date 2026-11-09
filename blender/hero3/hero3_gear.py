"""Weapons for the hero3 mech: the Dawn Edge saber, the beam rifle and the mirror shield.

The brief's hard rule: the saber is a BONE-ATTACHED blade on the R_Hand socket and never leaves the
hand. The old hero had no swing animation, so a 14 m blade was teleported along a computed arc every
tick -- it spun at the feet and never followed the arm. Here the blade is bound to R_Hand from the
moment it is built, so it can only ever be where the hand is.

The saber and the shield have their own modules (hero3_saber, hero3_shield) since the lead's r1 review
asked for both to be redesigned; this file owns the rifle and the assembly.

  import hero3_gear; gear = hero3_gear.build()
"""
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/hero3"))
import hero3_bones  # noqa: E402
import hero3_joints  # noqa: E402
import hero3_props as P  # noqa: E402
import hero3_saber  # noqa: E402
import hero3_shield  # noqa: E402

RIFLE_DIR = Vector((0.10, 0.62, -0.56))   ## carried muzzle-down at rest, not held out like a plank


def build_rifle() -> list:
    """The beam rifle: a dark body with gold bands and a cyan emitter, on R_Hand."""
    gun = hero3_joints.metal("Hero3Gunmetal", hero3_joints.GUNMETAL)
    gold = hero3_joints.metal("Hero3Gold", hero3_joints.GOLD, 0.28)
    edge = hero3_joints.metal("Hero3Edge", (0.02, 0.03, 0.04), 0.2, 0.0)
    bones = hero3_bones.bone_map()
    grip = Vector(bones["R_Hand"]["tail"])
    direction = RIFLE_DIR.normalized()
    stock = grip - direction * 1.15 + Vector((0.30, 0.0, 0.10))
    parts = [
        P.prism("Hero3Rifle", stock, direction,
                [(0.0, P.box_profile(0.22, 0.22)), (1.1, P.box_profile(0.30, 0.40)),
                 (1.9, P.box_profile(0.20, 0.24)), (2.4, P.box_profile(0.13, 0.14)),
                 (4.5, P.box_profile(0.10, 0.10))], [gun]),
        P.prism("Hero3RifleScope", stock + direction * 1.9 + Vector((0.0, 0.0, 0.40)), direction,
                [(0.0, P.box_profile(0.11, 0.11)), (1.2, P.box_profile(0.09, 0.09))], [gun]),
        P.prism("Hero3RifleBand", stock + direction * 2.42, direction,
                [(0.0, P.box_profile(0.15, 0.16)), (0.22, P.box_profile(0.15, 0.16))], [gold]),
        P.prism("Hero3RifleEmitter", stock + direction * 4.42, direction,
                [(0.0, P.box_profile(0.12, 0.12)), (0.18, P.box_profile(0.09, 0.09))], [edge]),
    ]
    for obj in parts:
        obj["hero3_bone"] = "R_Hand"
    return parts


def build() -> dict:
    """The three weapons, placed at the rest pose and tagged with the bone that carries them."""
    gear = {"saber": hero3_saber.build(), "rifle": build_rifle(),
            "shield": hero3_shield.build()}
    print("GEAR %d weapon parts" % sum(len(v) for v in gear.values()))
    return gear
