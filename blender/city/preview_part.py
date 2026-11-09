"""Build one city-kit part on its own and export it for `tools/blender.sh preview` (city-build).

    tools/blender.sh run blender/city/preview_part.py -- --part spire

The brief asks for every archetype to be judged in a close-up before it is mass-produced; this
renders the part with the same kit code the full build uses, so what you see is what ships.
Output: tmp/city-build/part_<name>.glb (render roles only, no collision).
"""
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
sys.path.insert(0, _HERE)

import bpy  # noqa: E402

import layout as layout_mod  # noqa: E402
from kit import landmarks, roles  # noqa: E402
from kit.builder import Kit  # noqa: E402
from kit.solid import Solids  # noqa: E402
from lib import common, export, uv  # noqa: E402

OUT = os.path.join(common.ROOT, "tmp", "city-build")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    part = argv[argv.index("--part") + 1] if "--part" in argv else "spire"
    return part


def build_part(part):
    """Return a Kit holding just `part` (spire, bridge)."""
    lay = layout_mod.Layout()
    kit = Kit(part)
    solids = Solids()
    slots = []
    if part == "spire":
        lm = next(l for l in lay.landmarks if l["kind"] == "spire")
        centre = (lm["pos"][0], lm["pos"][1])
        landmarks.spire_mod.spire(kit, solids, lm, slots,
                                  landmarks.deck_ring_radii(lay, centre))
        _ring_decks(kit, solids, lay)
    elif part == "bridge":
        lm = next(l for l in lay.landmarks if l["kind"] == "crystal_bridge")
        landmarks.crystal_bridge(kit, solids, lm, slots)
    else:
        raise SystemExit("city-build: no preview for part %r" % part)
    return kit


def clip_tether(kit, z_max=400.0):
    """The 600 m light tether would make the preview frame the whole 960 m and shrink the Spire
    to a dot; the framing only needs the built shaft."""
    import bmesh
    for bm in kit._bm.values():  ## noqa: SLF001 - the Kit is mine
        doomed = [f for f in bm.faces if f.calc_center_median().z > z_max]
        bmesh.ops.delete(bm, geom=doomed, context="FACES")


def _ring_decks(kit, solids, lay):
    """The three decks the Spire carries, so the preview shows the joints and not a bare shaft."""
    from kit import decks
    for d in lay.decks:
        if d["id"] in ("S3_collar", "S4_roof_ring", "B1_crown"):
            decks.deck(kit, solids, d, lambda x, y: 0.0)


def main():
    part = parse_args()
    common.reset()
    materials = roles.build_materials()
    kit = build_part(part)
    clip_tether(kit)
    bm = kit.merged()
    if bm is None:
        raise SystemExit("city-build: part %r produced no geometry" % part)
    obj = builder_object(part, bm, materials)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "part_%s.glb" % part)
    export.export_glb(path, objects=[obj])
    obj.data.calc_loop_triangles()
    print("city-build preview: %s -> %s (%d tris, %.1f kB)"
          % (part, path, len(obj.data.loop_triangles), os.path.getsize(path) / 1024.0))


def builder_object(part, bm, materials):
    from kit.builder import object_from_bmesh
    obj = object_from_bmesh("preview_%s" % part, bm, bpy.context.scene.collection,
                            [materials[r] for r in roles.ROLE_ORDER])
    uv.box_uv(obj, 1.0)
    from kit.builder import tag_windows
    tag_windows(obj.data)
    return obj


main()
