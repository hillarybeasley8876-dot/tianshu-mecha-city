"""Build the hero3 armature, bind the rigid pieces and emit the socket table (hero-v3, brief step 2).

Rigid skinning, one bone per piece: every armour plate, mechanism and weapon gets exactly ONE vertex
group at weight 1.0, so a plate can never tear or bend -- which is the whole point of cutting the
mesh into plates instead of skinning one fused body to the nearest bone (the old hero's jagged seams
came from doing that).

The pieces are joined into a single mesh before binding so the mech is one draw call per material
(the Tripo atlas and the gunmetal), not 29.

  import hero3_rig; arm = hero3_rig.build_armature(); hero3_rig.bind(body, arm)
"""
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/hero3"))
import hero3_bones  # noqa: E402
import hero3_lib as H  # noqa: E402
import hero3_saber  # noqa: E402

RIG_NAME = "Hero3Rig"
BODY_NAME = "Hero3Body"


def build_armature():
    """The mech skeleton from the measured table, at the origin with the identity transform."""
    arm_data = bpy.data.armatures.new(RIG_NAME)
    arm = bpy.data.objects.new(RIG_NAME, arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    bones = hero3_bones.bone_map()
    for name, info in bones.items():
        bone = arm_data.edit_bones.new(name)
        bone.head = Vector(info["head"])
        bone.tail = Vector(info["tail"])
    for name, info in bones.items():
        if info["parent"]:
            arm_data.edit_bones[name].parent = arm_data.edit_bones[info["parent"]]
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.show_in_front = True
    print("RIG %d bones" % len(arm_data.bones))
    return arm


def join_pieces(pieces: list, name: str = BODY_NAME):
    """Join the plates into one mesh, keeping one vertex group per source plate.

    Each plate is tagged with its bone's vertex group BEFORE the join, so after the join the single
    mesh carries all 29 groups and stays rigid per group."""
    arm = bpy.context.scene.objects.get(RIG_NAME)
    for obj in pieces:
        bone = obj.get("hero3_bone") or obj.name.replace("H3_", "")
        group = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
        group.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in pieces:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = name
    body.data.name = name
    print("JOIN %d plates -> %s, %d tris, %d vertex groups" % (
        len(pieces), body.name, H.tri_count(body), len(body.vertex_groups)))
    return body, arm


def bind(body, arm) -> None:
    """Armature deform with no automatic weights: the groups are already exact and rigid."""
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    mod.use_vertex_groups = True
    body.parent = arm
    missing = [b.name for b in arm.data.bones if b.name not in body.vertex_groups]
    if missing:
        print("BIND note: %d bones carry no geometry (%s)" % (len(missing), ", ".join(missing)))
    print("BIND %s -> %s (%d groups)" % (body.name, arm.name, len(body.vertex_groups)))


def bind_parts(arm, groups: dict) -> list:
    """Join each named group of parts into one object and bind it rigidly to its bone.

    The weapons stay separate nodes (Hero3Saber / Hero3Rifle / Hero3Shield) because the model API has
    to be able to show and hide them; folding them into the body mesh would make
    `set_saber_drawn` impossible without a shader trick."""
    out = []
    for name, parts in groups.items():
        for obj in parts:
            bone = obj.get("hero3_bone")
            if bone is None:
                raise RuntimeError("%s: %s has no hero3_bone" % (name, obj.name))
            group = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
            group.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")
        bpy.ops.object.select_all(action="DESELECT")
        for obj in parts:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        if len(parts) > 1:
            bpy.ops.object.join()
        node = bpy.context.view_layer.objects.active
        node.name = name
        node.data.name = name
        bind(node, arm)
        out.append(node)
        print("PART %-14s %5d tris -> %s" % (name, H.tri_count(node), parts[0].get("hero3_bone")))
    return out


def bone_matrix(arm, name: str) -> Matrix:
    """The bone's rest matrix in world space (armature at identity)."""
    bone = arm.data.bones[name]
    return bone.matrix_local


def socket_transform(arm, bone: str, world: Matrix) -> tuple:
    """A world-space transform expressed in `bone`'s space, as (position, euler degrees).

    glTF puts the bone's local Y along the bone, and Blender's bone.matrix_local is already that
    space, so the socket table is exactly the offset the Godot BoneAttachment3D needs."""
    local = bone_matrix(arm, bone).inverted() @ world
    euler = local.to_euler("XYZ")
    return local.translation, Vector((euler.x, euler.y, euler.z)) * (180.0 / 3.141592653589793)


def socket_table(arm) -> list:
    """The HeroModel sockets (CONTRACTS §5), each anchored to the bone that actually carries it."""
    bones = hero3_bones.bone_map()
    rows = []

    def add(name: str, bone: str, world: Matrix) -> None:
        pos, rot = socket_transform(arm, bone, world)
        rows.append((name, bone, pos, rot))

    def along(bone: str, t: float, offset=(0.0, 0.0, 0.0)) -> Matrix:
        head, tail = Vector(bones[bone]["head"]), Vector(bones[bone]["tail"])
        return Matrix.Translation(head.lerp(tail, t) + Vector(offset))

    # the hands carry the rifle and the saber; +Y of the socket points down the limb
    add("hand_r", "R_Hand", along("R_Hand", 0.85))
    add("hand_l", "L_Hand", along("L_Hand", 0.85))
    # `saber_r` is the one socket whose ORIENTATION is part of the contract: SaberVisual runs its
    # energy sheath along the socket's -Z from the model's steel tip (melee-defense, review r5 item 2),
    # so the rotation has to aim -Z down the blade. hero3_saber owns both ends of that.
    add("saber_r", "R_Hand", Matrix.Translation(hero3_saber.socket_point())
        @ hero3_saber.socket_rotation())
    add("shield_l", "L_Forearm", along("L_Forearm", 0.70, (-0.55, 0.0, 0.0)))
    add("muzzle_r", "R_Hand", along("R_Hand", 0.10))
    add("cockpit", "Spine02", along("Spine02", 0.80, (0.0, 0.85, 0.0)))
    add("chest", "Spine02", along("Spine02", 0.55, (0.0, 0.95, 0.0)))
    add("back", "BackFrame", along("BackFrame", 0.20))
    add("missile_l", "L_Clavicle", along("L_Clavicle", 0.55, (-0.35, -0.55, 0.45)))
    add("missile_r", "R_Clavicle", along("R_Clavicle", 0.55, (0.35, -0.55, 0.45)))
    # the 7 blade drones split 4/3 between the two wing sockets so corona_fins.gd keeps working
    add("wing_l", "Drone_1", Matrix.Translation(Vector(bones["Drone_1"]["head"])))
    add("wing_r", "Drone_5", Matrix.Translation(Vector(bones["Drone_5"]["head"])))
    add("saber_stow", "Pelvis", along("Pelvis", 0.35, (1.05, -0.35, 0.0)))
    for name, bone, pos, rot in rows:
        print("SOCKET %-12s bone=%-12s pos=(%.3f, %.3f, %.3f) rot=(%.1f, %.1f, %.1f)" % (
            name, bone, pos.x, pos.y, pos.z, rot.x, rot.y, rot.z))
    return rows
