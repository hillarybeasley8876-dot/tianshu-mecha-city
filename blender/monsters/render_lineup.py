"""Render the monster line-up at true scale against a 16 m hero reference (monster-assets).

    tools/blender.sh run blender/monsters/render_lineup.py -- [--clip=idle] [--out=monsters_lineup]

Every built model is placed on one ground plane in its real size next to a 16 m white reference box
(the hero's crest height, CONTRACTS §2), so the scale read is checkable by eye. Writes one PNG per
view plus a hero-height ruler.
"""
import argparse
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

from monsters import mon_lib, mon_types  # noqa: E402

HERO_HEIGHT_M = 16.0
#: left-to-right order, small to large, so the escalation reads
ORDER = ["ripper", "mantis", "spitter", "harrier", "juggernaut", "hive", "titan"]
VIEWS = {"lineup": Vector((0.0, -1.0, 0.16)), "lineup_high": Vector((0.35, -1.0, 0.45))}


def reference_box() -> object:
    """A plain white 16 m box standing in for the hero mech (CONTRACTS §2 crest height)."""
    mesh = bpy.data.meshes.new("HeroRef")
    obj = bpy.data.objects.new("HeroRef", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm_verts = [(-3, -3, 0), (3, -3, 0), (3, 3, 0), (-3, 3, 0),
                (-3, -3, HERO_HEIGHT_M), (3, -3, HERO_HEIGHT_M),
                (3, 3, HERO_HEIGHT_M), (-3, 3, HERO_HEIGHT_M)]
    faces = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    mesh.from_pydata(bm_verts, [], faces)
    mesh.update()
    mat = bpy.data.materials.new("HeroRefMat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.91, 0.93, 0.95, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.5
    mesh.materials.append(mat)
    return obj


def label(text: str, at: Vector, size: float) -> None:
    """A flat caption on the ground plane, so a reviewer can read the line-up without a legend."""
    curve = bpy.data.curves.new("Label_%s" % text, type="FONT")
    curve.body = text
    curve.size = size
    curve.align_x = "CENTER"
    obj = bpy.data.objects.new("Label_%s" % text, curve)
    obj.location = at
    obj.rotation_euler = (1.5708, 0.0, 0.0)
    mat = bpy.data.materials.new("LabelMat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.85, 0.85, 0.85, 1.0)
    curve.materials.append(mat)
    common.link(obj)


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--clip", default="idle")
    p.add_argument("--out", default="monsters_lineup")
    p.add_argument("--size", default="1800x700")
    args = p.parse_args(argv)
    out_dir = os.path.join(mon_lib.TMP, "render")
    os.makedirs(out_dir, exist_ok=True)
    common.reset()

    cursor = 0.0
    gap = 14.0
    placed = []
    for monster in ORDER:
        path = os.path.join(mon_lib.OUT_DIR, monster, "%s.glb" % monster)
        if not os.path.exists(path):
            print("LINEUP skip %s (no glb)" % monster)
            continue
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        new = [o for o in bpy.data.objects if o not in before]
        for obj in list(new):
            if obj.type == "MESH" and not obj.data.materials:
                bpy.data.objects.remove(obj, do_unlink=True)
                new.remove(obj)
        root = next((o for o in new if o.parent is None), None)
        if root is None:
            continue
        bodies = [o for o in new if o.type == "MESH" and o.data.materials]
        if monster == "hive":
            # the hive GLB carries all four state meshes; only the intact one belongs in a line-up
            for extra in bodies:
                extra.hide_render = extra.name != "Hive"
            bodies = [o for o in bodies if o.name == "Hive"]
        lo, hi = mon_lib.mesh_bounds(bodies[0])
        width = hi.x - lo.x
        root.location.x += cursor - lo.x
        if monster == "harrier":
            root.location.z += 26.0   # a flyer belongs in the air
        placed.append((monster, cursor, width, hi.z - lo.z))
        arm = next((o for o in new if o.type == "ARMATURE"), None)
        action = bpy.data.actions.get(args.clip)
        if arm is not None and action is not None:
            arm.animation_data_create().action = action
            if hasattr(action, "slots") and len(action.slots):
                arm.animation_data.action_slot = action.slots[0]
            bpy.context.scene.frame_set(int(action.frame_range[0]))
        cursor += width + gap

    ref = reference_box()
    ref.location.x = cursor + 6.0
    placed.append(("hero_ref", cursor + 6.0, 6.0, HERO_HEIGHT_M))
    total = cursor + 20.0
    for monster, x, width, height in placed:
        print("LINEUP %-11s x %7.1f  width %5.1f  height %5.1f" % (monster, x, width, height))

    for name, x, width, _height in placed:
        label("%s  %.0fm" % (name, _height), Vector((x + width * 0.5, -26.0, 0.2)), 5.0)
    tallest = max(h for _, _, _, h in placed)
    centre = Vector((total * 0.5, 0.0, tallest * 0.5))
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.09, 0.10, 0.13, 1.0)
    bg.inputs[1].default_value = 1.0
    bpy.context.scene.world = world
    for i, (loc, energy) in enumerate([((0.4, -1.0, 0.55), 4.5), ((-1.0, 0.3, 0.4), 1.8)]):
        light = bpy.data.lights.new("L%d" % i, "SUN")
        light.energy = energy
        obj = bpy.data.objects.new("L%d" % i, light)
        obj.rotation_euler = Vector(loc).to_track_quat("-Z", "Y").to_euler()
        common.link(obj)
    ground_mesh = bpy.data.meshes.new("Ground")
    ground = bpy.data.objects.new("Ground", ground_mesh)
    ground_mesh.from_pydata([(-40, -400, 0), (total + 40, -400, 0), (total + 40, 400, 0),
                             (-40, 400, 0)], [], [(0, 1, 2, 3)])
    ground_mesh.update()
    gmat = bpy.data.materials.new("GroundMat")
    gmat.use_nodes = True
    gmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.16, 0.15, 0.14, 1)
    ground_mesh.materials.append(gmat)
    common.link(ground)

    cam_data = bpy.data.cameras.new("C")
    cam_data.lens = 35.0
    cam = bpy.data.objects.new("C", cam_data)
    common.link(cam)
    bpy.context.scene.camera = cam
    w, h = (int(v) for v in args.size.split("x"))
    bpy.context.scene.render.resolution_x = w
    bpy.context.scene.render.resolution_y = h
    bpy.context.scene.render.image_settings.file_format = "PNG"
    # pull back far enough that the whole 270 m line-up fits the frame with a margin
    sensor = cam_data.sensor_width
    distance = (total * 0.55) * (cam_data.lens / sensor) * 2.0
    for name, direction in VIEWS.items():
        cam.location = centre + direction.normalized() * distance
        cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.scene.render.filepath = os.path.join(out_dir, "%s_%s.png" % (args.out, name))
        bpy.ops.render.render(write_still=True)
        print("SHOT %s (camera %.0f m out)" % (bpy.context.scene.render.filepath, distance))


main()
