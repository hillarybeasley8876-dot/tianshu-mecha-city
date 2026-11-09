"""Rebuild the whole city from `data/map/city_layout.json` (city-build).

    tools/blender.sh run blender/city/build_city.py
    tools/blender.sh run blender/city/build_city.py -- --district D5
    tools/blender.sh run blender/city/build_city.py -- --blockout

Deterministic (seeded per structure id) and idempotent: the scene is reset every run and every
output file is rewritten, so a layout revision costs one command. Prints per-district counts,
material usage, triangle totals, export sizes and wall time.

Kit skin mode: unless `--blockout` is given, every structure listed in `data/map/kit_assign.json`
(city-kit) emits no render mesh — collision and occluders are unchanged (blender/city/skin.py).
"""
import os
import sys
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
sys.path.insert(0, _HERE)

import bpy  # noqa: E402

import assemble  # noqa: E402
import layout as layout_mod  # noqa: E402
import markers as markers_mod  # noqa: E402
import skin as skin_mod  # noqa: E402
import tiles as tiles_mod  # noqa: E402
from kit import props, roles  # noqa: E402
from kit import builder as builder_mod  # noqa: E402
from lib import common, export  # noqa: E402

GAME_CITY = os.path.join(common.GAME, "world", "city")


def build(district=None, blockout=False, assign=None, chamfer=True):
    t0 = time.time()
    common.reset()
    builder_mod.CHAMFER_ON = chamfer
    materials = roles.build_materials()
    mat_list = [materials[r] for r in roles.ROLE_ORDER]
    lay = layout_mod.Layout()
    half = float(lay.bounds["half"])
    ground = assemble.ground_fn(lay)
    slots = []
    podium_walls = []
    skin = skin_mod.load(blockout, assign or skin_mod.ASSIGN_PATH)
    skin.resolve(lay)
    if district is not None:
        lay = lay.by_district(district)

    render, sub, lm, solids, sub_solids, lm_solids, counts = assemble.populate(
        lay, ground, skin, slots, podium_walls, terrain=district is None)

    tiles = tiles_mod.TileSet(half)
    # `lm_` chunks are the landmarks: city.gd gives them a 2 km range instead of the 450 m detail
    # cut, and their collision stays out of the tile HLOD proxy (reviews/city-build-r8.md item 1).
    chunks = tiles.add_kit(render) + tiles.add_kit(sub) + tiles.add_kit(lm, prefix="lm_")
    tiles.add_solids(solids)
    tiles.add_solids(sub_solids)
    tiles.add_solids(lm_solids, landmark=True)
    counts["chunks"] = chunks

    out_dir = os.path.join(GAME_CITY, "tiles")
    if district is None:
        _clear_tiles(out_dir)
    report = []
    tiles_mod.export_tiles(tiles, out_dir, mat_list, report)

    sky_report = []
    if district is None:
        ring, ring_slots = props.skyline(lay, skin)
        _export_skyline(ring, mat_list, sky_report)
        markers_mod.write(lay, slots, os.path.join(GAME_CITY, "layout.json"), podium_walls, skin,
                          ring_slots)

    _report(counts, report, sky_report, materials, slots, time.time() - t0, district)


def _clear_tiles(out_dir):
    """A full rebuild must not leave tiles behind from an earlier --district run: Godot
    instances every .glb in the folder, so a stale tile is duplicated geometry."""
    if not os.path.isdir(out_dir):
        return
    for name in os.listdir(out_dir):
        if name.startswith("tile_") and name.endswith(".glb"):
            os.remove(os.path.join(out_dir, name))


def _export_skyline(ring, mat_list, report):
    """The skyline ring: one mesh, no collision, no shadows (set in city.gd)."""
    bm = ring.merged()
    if bm is None:
        return
    col = bpy.context.scene.collection
    obj = tiles_mod._emit("skyline", bm, col, mat_list, single_index=1)
    path = os.path.join(GAME_CITY, "skyline.glb")
    export.export_glb(path, objects=[obj])
    report.append((os.path.basename(path), 1, len(obj.data.loop_triangles),
                   os.path.getsize(path)))
    bpy.data.objects.remove(obj, do_unlink=True)


def _report(counts, report, sky_report, materials, slots, seconds, district):
    total_tris = sum(r[2] for r in report + sky_report)
    total_bytes = sum(r[3] for r in report + sky_report)
    print("\n=== city-build%s ===" % (" (district %s)" % district if district else ""))
    for k, v in counts.items():
        print("  %-12s %d" % (k, v))
    print("  tiles        %d  objects %d" % (len(report), sum(r[1] for r in report)))
    print("  triangles    %d  (%.2f M)" % (total_tris, total_tris / 1e6))
    print("  export size  %.1f MB" % (total_bytes / 1e6))
    print("  prop slots   %d" % len(slots))
    print("  materials    %s" % ", ".join(m.name for m in materials.values()))
    big = sorted(report, key=lambda r: -r[3])[:5]
    for name, objs, tris, size in big:
        print("    %-18s %3d obj %8d tri %7.1f MB" % (name, objs, tris, size / 1e6))
    print("  build time   %.1f s" % seconds)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    district = None
    blockout = False
    assign = None
    chamfer = True
    for i, a in enumerate(argv):
        if a == "--district" and i + 1 < len(argv):
            district = argv[i + 1]
        elif a.startswith("--district="):
            district = a.split("=", 1)[1]
        elif a in ("--blockout", "--no-skin"):
            blockout = True
        elif a == "--no-chamfer":
            chamfer = False
        elif a.startswith("--assign="):
            assign = os.path.abspath(os.path.expanduser(a.split("=", 1)[1]))
    build(district, blockout, assign, chamfer)


main()
