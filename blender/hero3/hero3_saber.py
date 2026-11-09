"""The Dawn Edge (曦刃) -- the hero3 saber, modelled on the R_Hand `saber_r` socket (hero-v3).

Two rules from the lead's r1 review:

* LENGTH AND OWNERSHIP (item 3). The model answers `has_own_blade() -> true` and `blade_length()`,
  and `SaberVisual` then draws no second blade: it sheathes THIS steel and runs an energy extension
  from the steel tip out to `MeleeTable.BLADE_LENGTH`. So the steel is measured from the SOCKET, not
  from the hand bone: `BLADE_STEEL` metres of it, starting exactly at `saber_r` and running along the
  socket's own -Z. `MeleeTable.MODEL_BLADE_LENGTH` is 12.0 and the agreed reach is 14.0, which leaves a
  2 m energy tip -- the reach stays generous and visible.
* IT MUST LOOK DESIGNED (item 2). The r1 render was a long grey prism with one cyan strip. This is a
  blade with a fuller down both faces, a flared gold guard that matches the armour trim, a bound hilt
  with a pommel, and an emissive edge that reads as the cutting surface.

  import hero3_saber; parts = hero3_saber.build()
"""
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/hero3"))
import hero3_bones  # noqa: E402
import hero3_joints  # noqa: E402
import hero3_props as P  # noqa: E402

## metres of steel, measured from the `saber_r` socket along the socket's -Z (MeleeTable agrees)
BLADE_STEEL = 12.0
## where the socket sits along R_Hand, and which way the blade leaves the fist at rest: forward and
## down, far enough forward that 12 m of steel still clears the ground (tip z ~0.9 m)
SOCKET_T = 0.95
BLADE_DIR = Vector((0.12, 0.86, -0.50))
HILT_BACK = -1.55       ## the hilt runs BEHIND the socket, so the fist is around the grip
GUARD_FRONT = 0.36


def socket_point() -> Vector:
    """The `saber_r` socket in world space at the rest pose -- the origin of the whole weapon."""
    bones = hero3_bones.bone_map()
    head, tail = Vector(bones["R_Hand"]["head"]), Vector(bones["R_Hand"]["tail"])
    return head.lerp(tail, SOCKET_T)


def socket_rotation():
    """The socket's world rotation: its +Y column is the blade direction.

    Blender is Z-up and the glTF export rotates the whole model, so a socket axis cannot be reasoned
    about in Blender terms directly. What survives the conversion is this: the socket node's -Z in
    Godot is the Blender +Y column of its rest rotation, run through the same axis swap. Building the
    rotation with `to_track_quat('Y', 'Z')` therefore points the energy sheath down the steel."""
    return BLADE_DIR.normalized().to_track_quat("Y", "Z").to_matrix().to_4x4()


def blade_profile(w: float, t: float) -> list:
    """A blade cross-section with a fuller: sharp edges, a flat face, and a groove down the middle.

    Ten points, in order around the section. `w` is the half-width (across the flat) and `t` the
    half-thickness; the groove floor sits at 0.52 t so the fuller is a real recess, not a painted
    line."""
    return [(w, 0.0), (w * 0.62, t), (w * 0.22, t * 0.52), (-w * 0.22, t * 0.52), (-w * 0.62, t),
            (-w, 0.0), (-w * 0.62, -t), (-w * 0.22, -t * 0.52), (w * 0.22, -t * 0.52),
            (w * 0.62, -t)]


def edge_profile(w: float, t: float) -> list:
    """The emissive sheath: just proud of the steel at the two edges, thin everywhere else."""
    return [(w * 1.06, 0.0), (w * 0.66, t * 0.42), (-w * 0.66, t * 0.42), (-w * 1.06, 0.0),
            (-w * 0.66, -t * 0.42), (w * 0.66, -t * 0.42)]


def fuller_profile(w: float, t: float) -> list:
    """The cyan line that runs in the fuller on both faces."""
    return [(w * 0.20, t * 0.60), (-w * 0.20, t * 0.60), (-w * 0.20, t * 0.50), (w * 0.20, t * 0.50),
            (w * 0.20, -t * 0.50), (-w * 0.20, -t * 0.50), (-w * 0.20, -t * 0.60), (w * 0.20, -t * 0.60)]


## (along, half-width, half-thickness) from the socket to the tip
SECTIONS = [(0.00, 0.50, 0.165), (1.40, 0.49, 0.160), (6.00, 0.455, 0.142),
            (9.60, 0.415, 0.122), (11.30, 0.34, 0.092), (12.00, 0.045, 0.020)]


def build() -> list:
    """Every part of the saber, tagged to R_Hand. Returns them in bind order."""
    gun = hero3_joints.metal("Hero3Gunmetal", hero3_joints.GUNMETAL)
    gold = hero3_joints.metal("Hero3Gold", hero3_joints.GOLD, 0.28)
    edge = hero3_joints.metal("Hero3Edge", (0.02, 0.03, 0.04), 0.2, 0.0)
    bsdf = edge.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Emission Color"].default_value = (0.30, 0.90, 1.0, 1.0)
    bsdf.inputs["Emission Strength"].default_value = 5.0

    origin = socket_point()
    direction = BLADE_DIR.normalized()
    parts = []

    hilt = P.prism("Hero3SaberHilt", origin, direction,
                   [(HILT_BACK + 0.20, _octagon(0.30, 0.25)),
                    (HILT_BACK + 0.55, _octagon(0.27, 0.23)),
                    (-0.30, _octagon(0.26, 0.22)),
                    (-0.12, _octagon(0.30, 0.25))], [gun])
    parts.append(hilt)
    for i, along in enumerate((HILT_BACK + 0.62, HILT_BACK + 1.02)):
        parts.append(P.prism("Hero3SaberRing%d" % i, origin, direction,
                             [(along, _octagon(0.32, 0.27)), (along + 0.13, _octagon(0.32, 0.27))],
                             [gold]))
    parts.append(P.lathe("Hero3SaberPommel", origin + direction * HILT_BACK, direction,
                         [(0.0, 0.10), (0.10, 0.30), (0.22, 0.33), (0.30, 0.22)], [gold]))

    # a flared gold guard: wide at the blade, tapering back to the grip, so the hand reads as holding
    # something with a real hand-stop rather than a stick
    guard = P.prism("Hero3SaberGuard", origin, direction,
                    [(-0.16, _guard(0.62, 0.20)), (0.06, _guard(1.48, 0.30)),
                     (0.22, _guard(1.30, 0.26)), (GUARD_FRONT, _guard(0.66, 0.19))], [gold])
    parts.append(guard)
    parts.append(P.prism("Hero3SaberGuardSeam", origin, direction,
                         [(0.08, _guard(1.50, 0.31)), (0.15, _guard(1.44, 0.29))], [edge]))

    blade = P.prism("Hero3SaberBlade", origin, direction,
                    [(a, blade_profile(w, t)) for a, w, t in SECTIONS], [gun])
    parts.append(blade)
    parts.append(P.prism("Hero3SaberEdge", origin, direction,
                         [(a, edge_profile(w, t)) for a, w, t in SECTIONS], [edge]))
    parts.append(P.prism("Hero3SaberFuller", origin, direction,
                         [(a, fuller_profile(w, t)) for a, w, t in SECTIONS[:-1]], [edge]))

    for obj in parts:
        obj["hero3_bone"] = "R_Hand"
    tip = origin + direction * BLADE_STEEL
    print("SABER %d parts, %.1f m of steel from the saber_r socket, tip (%.2f, %.2f, %.2f)"
          % (len(parts), BLADE_STEEL, tip.x, tip.y, tip.z))
    return parts


def _octagon(w: float, t: float) -> list:
    """A rounded-off rectangle: the grip's cross-section."""
    k = 0.42
    return [(w, t * k), (w * k, t), (-w * k, t), (-w, t * k),
            (-w, -t * k), (-w * k, -t), (w * k, -t), (w, -t * k)]


def _guard(w: float, t: float) -> list:
    """The guard's cross-section: a flattened hexagon, so its edges catch the light like the trim."""
    return [(w, 0.0), (w * 0.55, t), (-w * 0.55, t), (-w, 0.0), (-w * 0.55, -t), (w * 0.55, -t)]
