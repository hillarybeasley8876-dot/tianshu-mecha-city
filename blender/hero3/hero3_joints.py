"""Joint mechanisms for the hero3 rig (hero-v3, brief step 1).

The brief's rule: at each joint there is a MODELLED mechanism -- a cylinder hinge with end caps at
the elbow and knee, a ball-and-socket housing at the shoulder and hip, and piston pairs at the knee
and ankle -- in dark gunmetal with a gold ring. No free-floating spheres, which is exactly what the
old hero used to hide its seams and what read as "bubbles".

Every mechanism is built in world space at the rest pose and bound to the bone that drives it, so it
travels with the joint. The piston rods additionally get a Damped Track constraint onto an empty on
the far bone, so a rod stays attached to both ends when the knee bends.

  import hero3_joints; parts = hero3_joints.build(arm)
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/hero3"))
import hero3_bones  # noqa: E402
import hero3_cap  # noqa: E402

GUNMETAL = (0.055, 0.058, 0.065)
GOLD = (0.72, 0.52, 0.18)
HINGE_SEGMENTS = 20
MECH_FIT = 0.80       ## a mechanism may reach this far to the armour's inner radius at its joint


def metal(name: str, rgb, rough: float = 0.52, metallic: float = 0.88):
    """A flat PBR metal (the mechanisms do not use the Tripo atlas)."""
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = rgb + (1.0,)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    return mat


def _new(name: str, verts, faces, mats):
    """A mesh with its normals recalculated outward.

    The hand-built caps come out wound either way depending on the frame, and an inward-facing cap is
    lit from behind: it renders as a black disc. That black disc at the shoulder was the ball
    housing's end cap, not a hole in the armour."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.validate()
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for mat in mats:
        obj.data.materials.append(mat)
    return obj


def _ring(centre: Vector, axis: Vector, radius: float, offset: float = 0.0):
    """A circle of points around `centre`, perpendicular to `axis`."""
    up = Vector((0.0, 0.0, 1.0))
    if abs(axis.dot(up)) > 0.95:
        up = Vector((1.0, 0.0, 0.0))
    u = axis.cross(up).normalized()
    v = axis.cross(u).normalized()
    base = centre + axis * offset
    return [base + u * math.cos(a) * radius + v * math.sin(a) * radius
            for a in (2.0 * math.pi * i / HINGE_SEGMENTS for i in range(HINGE_SEGMENTS))]


def cylinder(name: str, a: Vector, b: Vector, radius: float, ring_at: float = 0.0,
             ring_radius: float = 0.0):
    """A capped cylinder from a to b, optionally with a gold band at `ring_at` along it."""
    axis = (b - a)
    length = axis.length
    axis = axis.normalized()
    mats = [metal("Hero3Gunmetal", GUNMETAL)]
    if ring_radius > 0.0:
        mats.append(metal("Hero3Gold", GOLD, 0.28))
    verts, faces, mat_index = [], [], []
    bands = [(0.0, radius), (length, radius)]
    if ring_radius > 0.0:
        bands = [(0.0, radius), (max(ring_at - 0.05, 0.01), radius),
                 (max(ring_at - 0.04, 0.02), ring_radius), (min(ring_at + 0.04, length - 0.02),
                                                            ring_radius),
                 (min(ring_at + 0.05, length - 0.01), radius), (length, radius)]
    for offset, rad in bands:
        verts.extend(_ring(a, axis, rad, offset))
    for band in range(len(bands) - 1):
        lo, hi = band * HINGE_SEGMENTS, (band + 1) * HINGE_SEGMENTS
        for i in range(HINGE_SEGMENTS):
            j = (i + 1) % HINGE_SEGMENTS
            faces.append((lo + i, lo + j, hi + j, hi + i))
            mat_index.append(1 if ring_radius > 0.0 and band in (1, 2, 3) else 0)
    cap_lo = len(verts)
    verts.extend(_ring(a, axis, radius * 0.98, 0.0))
    cap_hi = len(verts)
    verts.extend(_ring(a, axis, radius * 0.98, length))
    for i in range(HINGE_SEGMENTS):
        j = (i + 1) % HINGE_SEGMENTS
        faces.append((cap_lo + j, cap_lo + i, cap_hi + i, cap_hi + j))
        mat_index.append(0)
    faces.append(tuple(range(cap_lo + HINGE_SEGMENTS - 1, cap_lo - 1, -1)))
    mat_index.append(0)
    faces.append(tuple(range(cap_hi, cap_hi + HINGE_SEGMENTS)))
    mat_index.append(0)
    obj = _new(name, verts, faces, mats)
    for poly, index in zip(obj.data.polygons, mat_index):
        poly.material_index = index
    return obj


def housing(name: str, centre: Vector, axis: Vector, radius: float, depth: float):
    """A ball-and-socket housing: a short wide cylinder with a gold collar, open toward the limb."""
    a = centre - axis * depth * 0.5
    b = centre + axis * depth * 0.5
    return cylinder(name, a, b, radius, ring_at=depth * 0.72, ring_radius=radius * 1.12)


def piston(name: str, base: Vector, rod: Vector, radius: float):
    """A piston pair: a wide cylinder body and a thin rod that reaches the far anchor."""
    direction = (rod - base)
    length = direction.length
    direction = direction.normalized()
    body = cylinder(name + "_Body", base, base + direction * length * 0.55, radius,
                    ring_at=length * 0.5, ring_radius=radius * 1.15)
    shaft = cylinder(name + "_Rod", base + direction * length * 0.45, rod, radius * 0.52)
    return [body, shaft]


## joint -> (kind, radius, span). Radii sit just inside the measured limb radius at that joint
## (diag_limbs.py: knee 0.93, elbow 0.51, shoulder 0.89, hip 0.88, ankle 0.59, waist 0.99, neck 0.47)
## so the mechanism fills the gap without pushing the armour plates apart.
JOINTS = [
    ("R_Shoulder", "R_Upperarm", "R_Clavicle", "housing", 0.88, 1.50),
    ("L_Shoulder", "L_Upperarm", "L_Clavicle", "housing", 0.88, 1.50),
    ("R_Elbow", "R_Forearm", "R_Upperarm", "hinge", 0.50, 1.60),
    ("L_Elbow", "L_Forearm", "L_Upperarm", "hinge", 0.50, 1.60),
    ("R_Wrist", "R_Hand", "R_Forearm", "hinge", 0.30, 0.90),
    ("L_Wrist", "L_Hand", "L_Forearm", "hinge", 0.30, 0.90),
    ("R_Hip", "R_Thigh", "Pelvis", "housing", 0.98, 1.90),
    ("L_Hip", "L_Thigh", "Pelvis", "housing", 0.98, 1.90),
    ("R_Knee", "R_Calf", "R_Thigh", "hinge", 0.80, 1.90),
    ("L_Knee", "L_Calf", "L_Thigh", "hinge", 0.80, 1.90),
    ("R_Ankle", "R_Foot", "R_Calf", "hinge", 0.55, 1.50),
    ("L_Ankle", "L_Foot", "L_Calf", "hinge", 0.55, 1.50),
    ("Waist", "Spine01", "Pelvis", "housing", 1.05, 1.10),
    ("Neck", "Head", "Neck", "housing", 0.42, 0.70),
]

## piston -> (near bone, near fraction along it, far bone, far fraction, lateral offset, radius)
PISTONS = [
    ("R_KneePistonOut", "R_Thigh", 0.55, "R_Calf", 0.35, Vector((0.45, -0.55, 0.0)), 0.20),
    ("R_KneePistonIn", "R_Thigh", 0.60, "R_Calf", 0.45, Vector((-0.40, -0.50, 0.0)), 0.17),
    ("L_KneePistonOut", "L_Thigh", 0.55, "L_Calf", 0.35, Vector((-0.45, -0.55, 0.0)), 0.20),
    ("L_KneePistonIn", "L_Thigh", 0.60, "L_Calf", 0.45, Vector((0.40, -0.50, 0.0)), 0.17),
    ("R_AnklePiston", "R_Calf", 0.35, "R_Foot", 0.55, Vector((0.42, -0.45, 0.0)), 0.16),
    ("L_AnklePiston", "L_Calf", 0.35, "L_Foot", 0.55, Vector((-0.42, -0.45, 0.0)), 0.16),
]


def bone_vector(bones: dict, name: str) -> tuple:
    head = Vector(bones[name]["head"])
    tail = Vector(bones[name]["tail"])
    return head, tail, (tail - head).normalized()


## Inner volumes. A capped plate is a closed shell, so when a joint rotates you look through the
## opening straight at the INSIDE of the next plate -- the black disc that showed at the shoulder in
## the first stress pose. A dark solid core inside each limb plugs every opening from behind and is
## what the joint mechanisms sit on.
##
## The radii are NOT here: a fixed radius cannot fit a tapered, flared plate (the first pass gave
## every limb one cylinder from its outer measurement and the mech read as drain pipes). hero3_fit
## measures the armour's own inner surface per station and lofts the core through it.
CORE_BONES = ["Pelvis", "Spine01", "Spine02", "Neck", "Head", "BackFrame",
              "R_Clavicle", "R_Upperarm", "R_Forearm", "L_Clavicle", "L_Upperarm", "L_Forearm",
              "R_Thigh", "R_Calf", "R_Foot", "L_Thigh", "L_Calf", "L_Foot"]


def build_cores(plates_by_bone: dict, tree, bones: dict) -> list:
    """Fitted inner volumes -- see hero3_fit.build_cores."""
    import hero3_fit

    return hero3_fit.build_cores(plates_by_bone, tree, bones)


def build(arm=None, plates_by_bone=None) -> tuple:
    """Every joint mechanism, in world space at the rest pose. Returns (mechanisms, pistons).

    With `plates_by_bone`, every radius is clamped to MECH_FIT x the plate's own inner radius just
    inside that joint, so a mechanism can never stand outside the armour it sits in -- which is what
    put a grey disc on the shoulder and a white drum on the hip."""
    bones = hero3_bones.bone_map()
    mechanisms, pistons = [], []
    for name, bone, parent, kind, radius, span in JOINTS:
        plate = (plates_by_bone or {}).get(bone)
        if plate is not None:
            import hero3_fit

            limit = hero3_fit.joint_radius(plate, bones, bone) * MECH_FIT
            if limit < radius:
                print("JOINT %-12s radius %.2f -> %.2f m (armour is %.2f m there)"
                      % (name, radius, limit, limit / MECH_FIT))
                radius = limit
                span = min(span, limit * 2.2)
        head, _, direction = bone_vector(bones, bone)
        _, _, parent_dir = bone_vector(bones, parent)
        if kind == "housing":
            obj = housing("H3J_" + name, head + direction * span * 0.25, direction, radius, span)
        else:
            axis = parent_dir.cross(direction)
            axis = axis.normalized() if axis.length > 1e-4 else Vector((1.0, 0.0, 0.0))
            obj = cylinder("H3J_" + name, head - axis * span * 0.5, head + axis * span * 0.5,
                           radius, ring_at=span * 0.5, ring_radius=radius * 1.18)
        obj["hero3_bone"] = bone
        mechanisms.append(obj)
    for name, near, near_t, far, far_t, offset, radius in PISTONS:
        a_head, a_tail, _ = bone_vector(bones, near)
        b_head, b_tail, _ = bone_vector(bones, far)
        base = a_head.lerp(a_tail, near_t) + offset
        anchor = b_head.lerp(b_tail, far_t) + offset * 0.75
        for part in piston("H3J_" + name, base, anchor, radius):
            part["hero3_bone"] = near
            part["hero3_track"] = far
            pistons.append(part)
        _ = (a_tail, b_tail)
    print("JOINTS %d mechanisms, %d piston parts" % (len(mechanisms), len(pistons)))
    return mechanisms, pistons
