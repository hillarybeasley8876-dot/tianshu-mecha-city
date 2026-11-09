"""The mirror shield on the left forearm (hero-v3, lead r1 item 2).

The r1 render was a plain board: a dark rectangle with one gold edge, standing off the arm. The lead's
bar is that it must look like it belongs to this armour, so it is built from the same language as the
plates -- a real hexagon, bevelled, a raised central boss, a gold rim ALL the way round, cyan seam
lines, and a visible clamp holding it ON the forearm rather than floating beside it.

  import hero3_shield; parts = hero3_shield.build()
"""
import math
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/hero3"))
import hero3_bones  # noqa: E402
import hero3_joints  # noqa: E402
import hero3_props as P  # noqa: E402

## the outline, in the plate's own (u, v): u runs back along the arm, v is world up. A hexagon with a
## flat top, angled shoulders and a flat bottom -- the r1 outline was a rectangle with two corners cut,
## which is why it read as a board.
OUTLINE = [(-1.72, 1.62), (1.72, 1.62), (2.02, 0.34), (0.98, -2.06), (-0.98, -2.06), (-2.02, 0.34)]
RIM_W = 0.30          ## how wide the gold border reads from the front
THICK = 0.34          ## the slab
FACE_OUT = 0.07       ## how far the dark face stands proud of the gold slab
BOSS_R = 0.92         ## the raised central boss
SEAM_R = 1.46         ## the cyan seam ring
MOUNT_T = 0.45        ## where along the forearm the shield is clamped
STANDOFF = 0.70       ## metres from the forearm axis out to the shield's back face


def _scaled(outline, factor: float) -> list:
    cu = sum(p[0] for p in outline) / len(outline)
    cv = sum(p[1] for p in outline) / len(outline)
    return [(cu + (u - cu) * factor, cv + (v - cv) * factor) for u, v in outline]


def _inset(outline, amount: float) -> list:
    """Shrink the outline toward its own centre by `amount` metres, per vertex."""
    cu = sum(p[0] for p in outline) / len(outline)
    cv = sum(p[1] for p in outline) / len(outline)
    out = []
    for u, v in outline:
        du, dv = u - cu, v - cv
        length = math.hypot(du, dv)
        scale = max(0.05, 1.0 - amount / max(length, 1e-6))
        out.append((cu + du * scale, cv + dv * scale))
    return out


def _ring(radius: float, sides: int = 6, phase: float = 0.0) -> list:
    return [(math.cos(phase + 2.0 * math.pi * i / sides) * radius,
             math.sin(phase + 2.0 * math.pi * i / sides) * radius) for i in range(sides)]


def build() -> list:
    """Every part of the shield, tagged to L_Forearm. Returns them in bind order."""
    gun = hero3_joints.metal("Hero3Gunmetal", hero3_joints.GUNMETAL)
    gold = hero3_joints.metal("Hero3Gold", hero3_joints.GOLD, 0.28)
    edge = hero3_joints.metal("Hero3Edge", (0.02, 0.03, 0.04), 0.2, 0.0)
    bsdf = edge.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Emission Color"].default_value = (0.30, 0.90, 1.0, 1.0)
    bsdf.inputs["Emission Strength"].default_value = 1.2

    bones = hero3_bones.bone_map()
    head = Vector(bones["L_Forearm"]["head"])
    tail = Vector(bones["L_Forearm"]["tail"])
    axis = (tail - head).normalized()
    normal = Vector((-1.0, 0.0, 0.0))
    # the plate's own frame: u across the arm, v up it (see hero3_props.plate)
    up = Vector((0.0, 0.0, 1.0))
    v_axis = (up - normal * up.dot(normal)).normalized()
    u_axis = v_axis.cross(normal).normalized()
    centre = head.lerp(tail, MOUNT_T) + normal * STANDOFF
    parts = []

    rim = P.plate("Hero3ShieldRim", centre, normal, OUTLINE, THICK, [gold], bevel=0.12)
    parts.append(rim)
    # BOTH faces are dressed. The shield hangs on the outside of the left arm, so the lead's
    # close_front34 camera -- and the player's own third-person camera whenever the mech turns left --
    # looks at its BACK; the r1 render was a bare slab from exactly that angle.
    for label, side in (("Face", 1.0), ("Back", -1.0)):
        base = centre + normal * (THICK * 0.5 + side * (THICK * 0.5 + FACE_OUT))
        facing = normal * side
        parts.append(P.plate("Hero3Shield%s" % label, base, facing, _inset(OUTLINE, RIM_W),
                             THICK * 0.5, [gun], bevel=0.07))
        parts.append(P.band("Hero3Shield%sSeam" % label, base + facing * (THICK * 0.5 * 0.80),
                            facing, _ring(SEAM_R), _ring(SEAM_R - 0.13), 0.06, [edge]))
        for i in range(6):
            angle = 2.0 * math.pi * i / 6.0
            direction = (u_axis * math.cos(angle) + v_axis * math.sin(angle)).normalized()
            start = base + facing * (THICK * 0.5 * 0.78) + direction * (BOSS_R * 1.2)
            parts.append(P.prism("Hero3Shield%sSpoke%d" % (label, i), start, direction,
                                 [(0.0, P.box_profile(0.05, 0.05)),
                                  (SEAM_R - BOSS_R * 1.2, P.box_profile(0.05, 0.05))], [edge]))
    # the boss: a gold collar with a dark dome in it, on the OUTER face only -- it is the striking
    # surface, and a dome on the inner face would sit against the arm
    outer = centre + normal * (THICK + FACE_OUT)
    parts.append(P.band("Hero3ShieldBossRing", outer, normal, _ring(BOSS_R * 1.20),
                        _ring(BOSS_R * 0.98), 0.18, [gold]))
    parts.append(P.plate("Hero3ShieldBoss", outer, normal, _ring(BOSS_R), 0.20, [gun], bevel=0.06,
                         boss=0.34))

    # the clamp: two bands round the forearm and a bracket out to the shield's back
    for i, t in enumerate((MOUNT_T - 0.26, MOUNT_T + 0.26)):
        band_centre = head.lerp(tail, t)
        parts.append(P.lathe("Hero3ShieldBand%d" % i, band_centre - axis * 0.16, axis,
                             [(0.0, 0.62), (0.32, 0.62)], [gun], segments=16, smooth=False))
    bracket = centre + normal * -0.02
    parts.append(P.prism("Hero3ShieldBracket", head.lerp(tail, MOUNT_T), normal,
                         [(0.0, P.box_profile(0.42, 0.30)),
                          (STANDOFF - 0.05, P.box_profile(0.34, 0.24))], [gun]))
    parts.append(P.prism("Hero3ShieldBracketRib", bracket, v_axis,
                         [(-1.30, P.box_profile(0.16, 0.16)), (1.30, P.box_profile(0.16, 0.16))],
                         [gold]))

    for obj in parts:
        obj["hero3_bone"] = "L_Forearm"
    print("SHIELD %d parts, hexagon %.2f x %.2f m on L_Forearm at t=%.2f"
          % (len(parts), max(p[0] for p in OUTLINE) - min(p[0] for p in OUTLINE),
             max(p[1] for p in OUTLINE) - min(p[1] for p in OUTLINE), MOUNT_T))
    return parts
