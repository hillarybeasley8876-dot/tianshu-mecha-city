"""Collision diff: kit skin mode must change what the player SEES and nothing else (city-build).

    tools/blender.sh run blender/city/probe_skin.py

Runs the same assembly twice — once with `data/map/kit_assign.json`, once as `--blockout` — and
compares the collision it produced, role by role, on verts / faces / closed-box volume. Any
difference is a structure whose collider moved when its render mesh was dropped, which is the one
thing skin mode is not allowed to do (lead r7 item 1).

The render side is reported too, so the run also proves the skin is actually doing something: the
triangle count must FALL when the assignment is honoured.
"""
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
sys.path.insert(0, _HERE)

import assemble  # noqa: E402
import layout as layout_mod  # noqa: E402
import skin as skin_mod  # noqa: E402
from lib import common  # noqa: E402

BUCKETS = ("col", "occ", "props", "curtain")


def _fingerprint(solids_list) -> dict:
    """{bucket: {role: (verts, faces, volume)}} over every Solids the assembly produced."""
    out = {}
    for bucket in BUCKETS:
        merged: dict = {}
        for s in solids_list:
            for role, stat in getattr(s, bucket).stats().items():
                v, f, vol = merged.get(role, (0, 0, 0.0))
                merged[role] = (v + stat[0], f + stat[1], round(vol + stat[2], 3))
        out[bucket] = merged
    return out


def _tris(kits) -> int:
    """Render triangles: every primitive this kit writes is a quad or a triangle fan, so faces*2
    is close enough to show that the skin dropped geometry."""
    return sum(stat[1] * 2 for kit in kits for stat in kit.stats().values())


def _run(lay, ground, skin) -> tuple:
    common.reset()
    slots, walls = [], []
    render, sub, lm, solids, sub_solids, lm_solids, counts = assemble.populate(
        lay, ground, skin, slots, walls)
    return (render, sub, lm), [solids, sub_solids, lm_solids], counts


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    assign = None
    for a in argv:
        if a.startswith("--assign="):
            assign = os.path.abspath(os.path.expanduser(a.split("=", 1)[1]))

    lay = layout_mod.Layout()
    ground = assemble.ground_fn(lay)
    skinned = skin_mod.load(False, assign or skin_mod.ASSIGN_PATH)
    skinned.resolve(lay)
    plain = skin_mod.Skin(False, "--blockout")

    kits_on, solids_on, counts_on = _run(lay, ground, skinned)
    fp_on = _fingerprint(solids_on)
    tris_on = _tris(kits_on)
    kits_off, solids_off, counts_off = _run(lay, ground, plain)
    fp_off = _fingerprint(solids_off)
    tris_off = _tris(kits_off)

    fails = 0
    for bucket in BUCKETS:
        a, b = fp_on[bucket], fp_off[bucket]
        va = round(sum(v[2] for v in a.values()), 3)
        vb = round(sum(v[2] for v in b.values()), 3)
        ok = a == b
        fails += 0 if ok else 1
        print("%s: %s  %d roles, %d boxes, %.1f m3 skinned vs %.1f m3 blockout"
              % ("PASS" if ok else "FAIL", bucket, len(a),
                 sum(v[1] // 6 for v in a.values()), va, vb))
        for role in sorted(set(a) | set(b)):
            if a.get(role) != b.get(role):
                print("    %-14s skinned %s  blockout %s" % (role, a.get(role), b.get(role)))
    drew = tris_off - tris_on
    ok_render = drew > 0 if skinned.count() else tris_on == tris_off
    fails += 0 if ok_render else 1
    print("%s: render triangles %d skinned vs %d blockout (%d dropped for %d skinned structures)"
          % ("PASS" if ok_render else "FAIL", tris_on, tris_off, drew, skinned.count()))
    print("  skinned: %d buildings, %d deck edges, %d whole decks, %d viaducts, %d cover pieces, "
          "%d far-LOD tiles (%d held), %d ring boxes; built %d/%d buildings"
          % (len(skinned.buildings), len(skinned.decks), len(skinned.decks_full),
             len(skinned.viaducts), len(skinned.cover), len(skinned.far), skinned.far_held,
             len(skinned.ring), counts_on["skinned"], counts_off["buildings"]))
    print("SKIN DIFF %s (%d failed)" % ("PASS" if fails == 0 else "FAIL", fails))
    if fails:
        sys.exit(1)


main()
