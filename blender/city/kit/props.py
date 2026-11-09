"""Arena cover, the skyline ring and the hive sockets.

Cover is the layout's `arenas[].cover` verbatim: hard pieces are concrete, soft (destructible)
pieces read as clad steel so the fight-space palette separates them. The skyline ring is scenery
beyond the soft wall: no collision, no shadows, low detail.
"""
from .builder import Kit, MutedKit


def cover(kit, solids, layout, slots, skin=None):
    """Every arena cover piece; soft pieces also leave a breakable prop slot for city-art.

    Soft (destructible) cover is collidable on the PROPS layer, not WORLD: it stops shots, bodies
    and sightlines (MASK_SIGHT is WORLD|PROPS) but the navmesh bake reads WORLD only, so the
    walkable arena floor survives the fight that is going to blow the cover away anyway. Hard
    cover is permanent architecture and stays on WORLD. Arena cover runs 41-64 % of the polygon
    footprint per tier; as WORLD geometry it left a 4 m-radius agent no connected free space at
    all (medium arena centres 16 m off-mesh).

    Kit skin mode (city-kit r2 item 1): a `cover` row names one piece as "<arena>#<index>" and a
    Tripo prop stands in its place, so BOTH render boxes go (the mass and the white cap) while the
    collider and the breakable slot stay exactly as they are — the piece still blocks the fight.
    """
    for arena in layout.arenas:
        for i, c in enumerate(arena.get("cover", [])):
            x, y, z = (float(v) for v in c["center"])
            w, d, h = (float(v) for v in c["size"])
            role = "mc_metal" if c.get("soft") else "mc_concrete"
            cid = "%s#%d" % (arena["id"], i)
            rkit = MutedKit(cid) if skin is not None and skin.cover_piece(arena["id"], i) else kit
            dropped = rkit is not kit
            rkit.box(role, (x, y, z + h * 0.5), (w, d, h))
            rkit.box("mc_panel_white", (x, y, z + h + 0.4), (w * 0.94, d * 0.94, 0.8))
            slots.append({"kind": "arena_cover", "id": cid, "arena": arena["id"], "index": i,
                          "soft": bool(c.get("soft")), "pos": [x, y, z], "size": [w, d, h],
                          "yaw_deg": round(float(c.get("rot", 0.0)), 2), "dropped": dropped})
            if c.get("soft"):
                solids.prop((x, y, z + h * 0.5), (w, d, h))
                slots.append({"kind": "breakable_cover", "arena": arena["id"], "index": i,
                              "pos": [x, y, z], "size": [w, d, h]})
            else:
                solids.box((x, y, z + h * 0.5), (w, d, h), 0.0, False)
        for sock in arena.get("spawn_sockets", []):
            slots.append({"kind": "spawn_socket", "arena": arena["id"], "id": sock["id"],
                          "socket": sock["kind"], "pos": [float(v) for v in sock["pos"]]})


def hives(kit, solids, layout, slots):
    """Hive spires are monster assets (monster-assets/city-art): leave the socket only."""
    for hive in layout.hives:
        x, y, z = (float(v) for v in hive["pos"])
        kit.cylinder("mc_concrete", (x, y, z + 1.5), 26.0, 3.0, 20)
        solids.box((x, y, z + 1.5), (44.0, 44.0, 3.0), 0.0, False)
        slots.append({"kind": "hive_spire", "id": hive["id"], "arena": hive["arena"],
                      "pos": [x, y, z], "height": float(hive["height"])})


def skyline(layout, skin=None):
    """A separate Kit for the ring: merged low-detail masses, exported without collision.

    Returns `(kit, slots)`. A `ring` row in `kit_assign.json` (reviews/city-build-r8.md item 3)
    drops that box from the mesh because a city-kit far model stands there instead; every box —
    dropped or not — also leaves a slot so the placer knows where the ring towers are without
    re-reading the design layout.
    """
    kit = Kit("skyline")
    slots = []
    for i, s in enumerate(layout.skyline):
        x, y = (float(v) for v in s["center"])
        w, d = (float(v) for v in s["size"])
        h = float(s["height"])
        dropped = skin is not None and skin.ring_box(i)
        slots.append({"kind": "skyline_ring", "index": i, "center": [x, y], "size": [w, d],
                      "height": h, "base_z": 0.0, "dropped": dropped})
        if dropped:
            continue
        kit.box("mc_concrete", (x, y, h * 0.5), (w, d, h))
        kit.box("mc_panel_white", (x, y, h + 4.0), (w * 0.7, d * 0.7, 8.0))
        if h > 140.0:
            kit.box("mc_concrete", (x, y, h * 1.08), (w * 0.5, d * 0.5, h * 0.16))
    return kit, slots
