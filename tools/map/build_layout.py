#!/usr/bin/env python3
"""build_layout.py - generate data/map/city_layout.json from the level graph.

Order (docs/MAP.md §3/§4): terrain (escarpment seam with climb lips, canal, plateau) ->
corridors (streets, Ring Viaduct, Skyrail, tunnels) -> connectors realising every edge ->
arenas with cover and spawn sockets -> landmarks -> buildings filling the remaining blocks ->
hives, anchors, player start, skyline ring. Seeded and deterministic: the same seed always
writes the same city. Hand fixes live in data/map/overrides.json, never in the output.

This file is the PIPELINE and nothing else: the stage order below IS the design. Every helper
it calls lives in the module that owns that piece of the city (corridors, lots, cuts, straddle,
props, zones, overrides), so a stage can be read - and changed - on its own.

Usage: uv run --with numpy --with shapely --with networkx python3 tools/map/build_layout.py
"""
from __future__ import annotations

import json
import os
import random
import sys

from shapely.geometry import Polygon
from shapely.ops import unary_union

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fill  # noqa: E402
import connectors  # noqa: E402
import corridors  # noqa: E402
import coverfield  # noqa: E402
import cuts  # noqa: E402
import streets  # noqa: E402
import vistas  # noqa: E402
import geom  # noqa: E402
import hive_rule  # noqa: E402
import hives  # noqa: E402
import keepclear  # noqa: E402
import lots  # noqa: E402
import mapconst as C  # noqa: E402
import openings  # noqa: E402
import overrides as override_stage  # noqa: E402
import route3d  # noqa: E402
import routes3d  # noqa: E402
import props  # noqa: E402
import skybridge  # noqa: E402
import skygraph  # noqa: E402
import sockets  # noqa: E402
import straddle  # noqa: E402
import towers  # noqa: E402
import supports  # noqa: E402
import terrain  # noqa: E402
import wall  # noqa: E402
import zones  # noqa: E402

from hive_rule import open_disc  # noqa: E402

VIADUCT_HALO = 50.0      # m: the elevated corridors' own right of way (see streets.build)


def load(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def main() -> int:
    graph = load(C.GRAPH_JSON)
    rules = load(C.DISTRICT_RULES_JSON)
    overrides = load(C.OVERRIDES_JSON)
    nodes = {n["id"]: n for n in graph["nodes"]}
    rng = random.Random(rules["global"]["seed"])

    cons = connectors.build(graph, nodes)
    keep = keepclear.keep_out(cons)
    crest = terrain.crest_points()
    lips = connectors.crest_crossings(cons, terrain.crest_line(crest))
    terr = terrain.build(lips)
    plateau = geom.poly(terr["terrain"]["plateau"]["polygon"])
    canal = geom.poly(terr["terrain"]["canal"]["polygon"])

    parts = corridors.build_corridors(graph, nodes, rules, plateau, rng, cons)
    override_stage.apply_corridor_moves(parts, overrides)
    decks = corridors.build_decks(rules, nodes)
    # a street never runs under a low terrace: only 12 m of headroom there
    low_decks = unary_union([geom.poly(d["polygon"]) for d in decks if 0 < d["z"] <= 24.0])
    # The Ring Viaduct and the Skyrail keep their own right of way: no local street is
    # generated within 50 m of them, so the land either side is free for the towers that
    # straddle them (MAP §4 viaduct/rail-through) instead of being a parallel back street.
    halo = [geom.line(i["points"]).buffer(i["width"] / 2 + VIADUCT_HALO)
            for i in straddle.straddlable(parts)]
    parts["streets"] += streets.build(rules, plateau, canal,
                                      lots.street_mask(parts, [low_decks] + halo), crest, rng)
    vista_slots = vistas.slots(vistas.load()) + vistas.camera_caps()
    camera_caps = vistas.camera_caps()
    camera_discs = unary_union([poly for poly, _ in camera_caps])
    # The canopies go up before the arena cover: a canopy roof is a walkable surface inside
    # the arena, and C14's samples land on it (lead, r4 points 2 and 3).
    outlines = props.arena_outlines(rules, parts["streets"])
    # Hive Spires reserve their ground before anything solid exists (lead, r6): 40 m of open
    # tier round the base, a well through the decks above it, and the keep-out every later
    # stage takes. A canopy is a roof over a hive's firing ground, so it is capped out too.
    hive_sites, hive_keep = hives.reserve(rules, outlines, decks, parts, cons, nodes)
    wells_cut = hives.punch(decks, hive_sites, nodes)
    decks += corridors.canopies(parts["streets"], outlines, rng,
                                slots=vista_slots + hives.wells(hive_sites))
    # Every designed route is made to exist in 3D here, before anything reads a connector path
    # (lead, r8): the shafts, take-offs and landings are placed and the stairs that had no
    # horizontal run are re-laid. It draws no random number, so the city does not re-roll.
    landmarks = props.landmarks()
    relayed = routes3d.place(cons, decks, parts, terr["terrain"], landmarks, hive_sites)
    # Spawn sockets reserve their floor before the cover exists (lead, r5): every cover pass
    # keeps 8 m clear of a reserved socket, the same way it keeps clear of a connector.
    sites, socket_keep = sockets.reserve(rules, decks, outlines)
    # Every solid-placing stage takes the same keep-out (lead, r7): the connector spheres, the
    # socket floors, the hives' open ground and the 30 m sphere round each vista camera - the
    # last one z-banded, so a camera 176 m up does not clear the street under it.
    cover_keep = coverfield.KeepOut(keep).union(socket_keep).union(hive_keep).union(
        coverfield.KeepOut(zones=vistas.camera_zones()))
    arenas = props.build_arenas(rules, decks, rng, corridors=parts["streets"], keep=cover_keep)
    cut = corridors.perforate_decks(decks, parts, nodes)
    corridors.under_clearance(decks, parts, arenas)
    limits = fill.arena_limits(rules, arenas)

    mask = lots.street_mask(parts)
    caps = corridors.height_caps(parts) + vista_slots + hives.cornice_caps(hive_sites)
    caps_id = corridors.height_caps(parts, with_id=True)
    ring = unary_union([geom.line(v["points"]).buffer(v["width"] / 2)
                        for v in parts["viaducts"]]) if parts["viaducts"] else Polygon()
    podiums, podium_stats = wall.build_podiums(rules, parts["streets"], mask, canal,
                                               plateau, ring, vista_slots, rng)
    # Viaduct/rail-through claims its two flanks before anything else builds on them, the
    # same way a podium portal does: no ordinary lot ever spans a 64 m corridor, and once
    # the kerb walls are up there is no free ground left either side of the roadway.
    free = wall.free_land(rules, mask, canal, plateau, decks, limits)
    occ = wall.Occupancy()
    for b in podiums:
        occ.add(geom.rect(tuple(b["center"]), tuple(b["size"]), b["rot"]))
    # a rooftop arena stays open to the sky: nothing may stand over A6's own footprint
    keep_out = [poly for poly, head in limits if head > 100.0]
    keep_out += [geom.poly(a["polygon"]) for a in arenas if a["id"] == "A6"]
    # a carrier tower may not grow through a hive's open ground either (lead, r6)
    keep_out += [open_disc(s) for s in hive_sites]
    straddles: list[dict] = []
    straddled = straddle.build(parts, straddles, rules, free, occ, caps_id, vista_slots,
                               keep_out, rng)
    carrier_land = unary_union([v for v in free.values() if not v.is_empty])
    carriers_made, carrier_stats = towers.build(decks, parts, rules, carrier_land, occ,
                                                caps_id, vista_slots, keep_out, rng)
    straddles += carriers_made
    buildings, coverage = fill.generate(rules, mask, decks, limits, parts["streets"],
                                        canal, plateau, caps,
                                        podium_stats["occupied"].union(occ.union()), rng)
    buildings = podiums + straddles + buildings
    walls, wall_stats = wall.build_walls(rules, parts["streets"], buildings, mask, canal,
                                         plateau, decks, limits, caps, rng)
    buildings = walls + buildings
    # A lot may not stand over a hole in the ground crust (lead, r9). This is a pure FILTER and it
    # runs HERE, after `wall.build_walls`, for two reasons: putting the same shapes into the block
    # mask would reshape every block `fabric` cuts and re-roll the whole city from the first
    # changed block on; and filtering before `build_walls` would renumber every kerb-wall id,
    # because that stage numbers its output against the list it is handed. Nothing downstream of
    # here draws a random number, so a dropped id simply leaves a gap. The same sweep runs once
    # more at the end, when the support towers exist too.
    crust_cuts = (cuts.ground(cons, terr["terrain"], decks),
                  cuts.plateau(cons, terr["terrain"], decks))
    cut_dropped = cuts.sweep(buildings, crust_cuts, decks)
    # A lot may not stand in a designed route either (lead, r8): same pure filter, same place.
    route_bands = cuts.route_bands(cons, corridors=parts['viaducts'] + parts['rails'])
    route_dropped = cuts.route_lots(buildings, route_bands, decks)
    coverage = fill.coverage_report(rules, coverage, buildings)
    reserved_all = fill.reserved_space(rules, decks, unary_union(
        [poly for poly, head in limits if head <= 0.0]))
    share = fill.street_wall_share(parts["streets"], buildings, mask.union(reserved_all))
    buildings += supports.support_towers(rules, decks, mask, canal, arenas, rng, caps)
    decks += skybridge.canyon_bridges(rules, decks, arenas, buildings, camera_caps)
    carriers = skybridge.tower_ring(rules, decks, buildings, caps_id, vista_slots)
    carriers += skybridge.consolidate_towers(rules, decks, buildings, caps_id, vista_slots,
                                             mask)
    ring = skybridge.ring_towers(rules, decks, buildings, caps_id, vista_slots)
    # Block 9 is declared last: its `holes` are read off the corridors that claim to run
    # through it, and `straddle.declare_through` is what decides that (lead, r4 points 4 and 5).
    block9 = props.block9_building()
    buildings.append(block9)
    pierced = straddle.declare_through(parts, buildings) + straddle.loop_through(parts)
    props.declare_block9_holes(block9, parts)
    station = props.block9_station(block9)
    if station is not None:
        decks.append(station)
        straddle.rail_termini(parts["rails"], station, block9)
    quarter_tagged = zones.tag_quarters(rules, buildings)
    # One top-up, on the finished city (lead, r7 point 2): the canyon skybridges, the station
    # deck and every late tower exist by now. Whatever a carrier tower stands on goes for good
    # - its footprint joins the keep-out, so the top-up cannot put it back.
    tower_dropped = props.clear_cover_under_towers(arenas, buildings)
    cover_keep = cover_keep.union(props.tower_keep(buildings))
    # The top-up is run until it converges and the LAST pair is asserted (lead, r7 point 2).
    # r8 widened the keep-outs the pass fills around (a route's own strip joins them), so a
    # single pair can still leave one hole for the next pass to find; what must hold is that it
    # settles, not that it settles in exactly two calls.
    late_cover, again = 0, -1
    for _ in range(4):
        added = props.cover_pass(arenas, decks, rules, rng, cover_keep)
        late_cover += added
        if added == 0:
            again = 0
            break
        again = added
    if again:
        raise SystemExit(f"cover_pass did not converge: a fourth pass still added {again} pieces")
    # a column is a solid in the hive's firing ground, so the open discs join the corridor
    # core as ground no lattice point may land on (lead, r6)
    # A deck column is a solid in a route's strip, so the strips join the lattice mask the
    # columns are placed on (lead, r8): the column moves, the route does not.
    columns = supports.deck_columns(decks, corridors.navigable_core(parts)
                                    .union(hive_keep).union(camera_discs)
                                    .union(unary_union([b for b, _, _ in route_bands])),
                                    canal, plateau)
    # The Hive Spires are sited last, on the finished city: the reserved ground is re-measured
    # with `hive_rule.verify` and a spire moves if a late tower or a column landed in it
    # (lead, r6). The dict is the layout minus the props, which is all `verify` reads.
    # Cover goes onto the finished floors (lead, r9), in TWO passes, because the hive stage in
    # between both punches wells through the decks and repairs the cover round the spires.
    # Pass 1 is on the deck list as it stands; pass 2 is on the list the hive wells left, with
    # the spires' FINAL positions as the keep-out and their firing lanes as a second one - a
    # piece walked onto a floor must not walk into the open ground `hives.build` just cleared.
    # Neither pass draws a random number, so nothing except the cover moves.
    settled_1 = props.settle_cover(arenas, decks, terr["terrain"], C.HALF, cover_keep,
                                    hive_sites, cons)
    hive_base = {"arenas": arenas, "decks": decks, "buildings": buildings, "connectors": cons,
                 "streets": parts["streets"], "viaducts": parts["viaducts"],
                 "rails": parts["rails"], "tunnels": parts["tunnels"], "nodes": nodes}
    hive_records, hive_notes = hives.build(hive_sites, hive_base, nodes, rules, rng, cover_keep)
    arenas, decks = hive_base["arenas"], hive_base["decks"]
    settle_keep = cover_keep.union(
        unary_union([open_disc(h) for h in hive_records]))
    settled = props.settle_cover(arenas, decks, terr["terrain"], C.HALF, settle_keep,
                                 hive_records, cons)
    again_settled = props.settle_cover(arenas, decks, terr["terrain"], C.HALF, settle_keep,
                                       hive_records, cons)
    if again_settled["moved"] or again_settled["dropped"] or again_settled["filled"]:
        raise SystemExit(f"settle_cover is not idempotent: {again_settled}")
    # An arena crate may not stand in a designed route either (lead, r8 item 4: only the
    # endpoints were kept clear, so cover stood on the centre line of the stair that climbs
    # through its own arena). It runs HERE, after the last cover top-up and settle, because
    # both of those put pieces back; it is a pure filter and drops nothing else.
    cover_dropped = cuts.route_cover(arenas, route_bands)
    soft_share = props.set_soft(arenas, rules)
    # Spawn sockets come last: a socket needs 8 m of free floor, 16 m of clear air and a
    # navmesh island, all of which are statements about the finished layout (lead, r5).
    socket_count = sockets.build(arenas, decks, buildings, rules, sites)
    # The same pure filter once more, now that the support towers exist too. Still no random
    # number, and the same carriers are exempt.
    late_dropped = cuts.sweep(buildings, crust_cuts, decks)
    late_routes = cuts.route_lots(buildings, route_bands, decks)

    layout = {
        # `version` stays 2: r3 is additive only (city-build reads the v2 fields and the
        # existing ids keep their meaning). `revision` says which review round wrote it.
        "meta": {"units": "m", "up": "Z", "version": 2, "revision": 8,
                 "seed": rules["global"]["seed"],
                 "coverage": {d: r["coverage"] for d, r in sorted(coverage.items())},
                 "street_walls": share,
                 "r4": {"connector_keep_clear_m": C.KEEP_CLEAR,
                        "arena_canopy_z": corridors.CANOPY_Z_ARENA,
                        "block9_station": "deck_block9_platform",
                        "open_arenas": ["B"]},
                 "r5": {"socket_wall_clear_m": sockets.WALL_CLEAR,
                        "socket_air_clear_m": sockets.AIR_CLEAR,
                        "socket_floor_clear_m": sockets.FLOOR_CLEAR,
                        "socket_cover_clear_m": sockets.COVER_CLEAR,
                        "socket_agent_radius_m": C.CAPSULE_R},
                 "r6": {"hive_open_ground_m": hive_rule.OPEN_R,
                        "hive_clear_air_m": hive_rule.AIR_H,
                        "hive_pod_band_m": list(hive_rule.POD_BAND),
                        "hive_firing_positions": hive_rule.MIN_POSITIONS,
                        "hive_approach_routes": hive_rule.MIN_APPROACHES,
                        "hive_wells": sorted({h for d in decks
                                              for h in d.get("open_for", [])})},
                 "r7": {"cover_min_gap_m": coverfield.MIN_GAP,
                        "cover_surface_band_m": coverfield.BAND,
                        "vista_camera_keep_out_m": vistas.CAMERA_KEEPOUT,
                        "vista_cameras": [v["id"] for v in vistas.load()]},
                 "r8": {"route_headroom_m": route3d.CLEAR,
                        "stair_max_deg": routes3d.STAIR_DEG,
                        "stair_flight_rise_m": route3d.MAX_FLIGHT_RISE,
                        "shaft_top_air_m": route3d.TOP_AIR,
                        "jump_apex_min_m": route3d.APEX_MIN,
                        },
                 "generated_by": "tools/map/build_layout.py",
                 "source_graph": "data/map/level_graph.json"},
        "bounds": {"half": C.HALF, "ceiling": C.CEILING, "skyline_half": C.SKYLINE_HALF},
        "terrain": terr["terrain"],
        "streets": parts["streets"], "viaducts": parts["viaducts"],
        "rails": parts["rails"], "tunnels": parts["tunnels"],
        "decks": decks, "buildings": buildings, "connectors": cons,
        "arenas": arenas, "landmarks": landmarks, "hives": hive_records,
        "anchors": props.anchors(arenas, buildings, rules, rng),
        "player_start": props.player_start(nodes),
        "skyline": props.skyline(rng),
    }
    # The last pass: the finished city yields to the routes that cross it. Decks and tunnel roofs
    # gain `holes`, parapets and edge barriers gain `openings` (MAP §3, r8), and whatever may not
    # be pierced is reported. Additive only - no random number, nothing renumbered.
    route_pierce = openings.open_up(layout)
    layout["meta"]["r8"]["route_holes"] = route_pierce["holes"]
    layout["meta"]["r8"]["route_openings"] = route_pierce["openings"]
    layout["sky_waypoints"], layout["sky_edges"], sky = skygraph.build(layout, rules)
    layout["meta"]["sky"] = sky
    touched = override_stage.apply(layout, overrides)
    vista_rows, vista_problems = vistas.check(layout)
    os.makedirs(C.DATA_DIR, exist_ok=True)
    with open(C.LAYOUT_JSON, "w", encoding="utf-8") as fh:
        json.dump(layout, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    print(f"wrote {os.path.relpath(C.LAYOUT_JSON, C.ROOT)} "
          f"({os.path.getsize(C.LAYOUT_JSON) / 1e6:.2f} MB, {touched} overrides applied)")
    print("  coverage per district (built / BUILDABLE land, MAP §4 revised):")
    freed = lots.land_freed(rules, parts, plateau, canal)
    for did, row in sorted(coverage.items()):
        flag = "" if row["coverage"] >= row["target"] else "  BELOW TARGET"
        now, before = freed[did]
        print(f"    {did} {row['coverage']:5.0%} (target {row['target']:.0%}; "
              f"{row['coverage_open']:5.0%} of non-corridor land)  "
              f"{row['buildings']:4d} buildings on {row['blocks']:3d} blocks, "
              f"{row['land_ha']:5.1f} ha buildable (+{max(now - before, 0.0) / 1e4:.1f} ha "
              f"from the new widths), lots {row['lots']} "
              f"(none {row['none']}, capped {row['capped']}, "
              f"blocked {row['conflict']}){flag}")
    for row in vista_rows:
        print(f"    {row['id']}: {row['verdict']}")
    for problem in vista_problems:
        print(f"    {problem}")
    walls_only = {k: v for k, v in share.items() if not k.endswith("#unbuildable")}
    dead = [v for k, v in share.items() if k.endswith("#unbuildable")]
    if walls_only:
        avg = sum(walls_only.values()) / len(walls_only)
        worst = min(walls_only.values())
        print(f"  avenue street walls: mean {avg:.0%}, worst {worst:.0%} over "
              f"{len(walls_only)} avenues (target 50 %); "
              f"{sum(dead) / len(dead):.0%} of avenue frontage is junction/plaza/arena")
    print(f"  walls {wall_stats['wall']} kerb buildings, {podium_stats['podium']} "
          f"podium-through blocks bridging {podium_stats['bridged_m']:.0f} m of street")
    print(f"  sky graph: {sky['nodes']} waypoints, {sky['edges']} edges, one component; "
          f"per district " + "  ".join(f"{k} {v}" for k, v in sorted(sky["per_district"].items()))
          + f"; per arena " + "  ".join(f"{k} {v}" for k, v in sorted(sky["per_arena"].items()))
          + f"; Crown ring {sky['crown']}")
    for key in ("streets", "viaducts", "rails", "tunnels", "decks", "buildings",
                "connectors", "arenas", "landmarks", "hives", "anchors", "skyline",
                "sky_waypoints", "sky_edges"):
        print(f"  {key:11s} {len(layout[key]):5d}")
    print(f"  skybridges  {len([d for d in decks if d.get('skybridge')]):5d}"
          f"   deck carrier towers raised {carriers}"
          f"   viaduct/rail-through towers {straddled['pierced']} placed + "
          f"{carrier_stats['carriers']} deck carriers "
          f"({carrier_stats['straddling']} straddling a corridor)\n"
          f"  D7 deck ring: {ring['ring']} towers 128-240 m within 260 m of the Sky Garden / "
          f"Crystal Bridge, {ring['tall']} of them 200 m+ ({ring['raised']} raised this pass)")
    print(f"  cover       {sum(len(a['cover']) for a in arenas):5d} ({late_cover} added by "
          f"the late top-up, {tower_dropped} dropped under a carrier tower; "
          f"a second pass added {again})"
          f"   sockets {socket_count}"
          f"   {len(cover_dropped)} dropped on a route"
          f"   soft {' '.join(f'{k} {v:.0%}' for k, v in sorted(soft_share.items()))}"
          f"   columns {columns}  perforated decks {cut}  pierced corridors {pierced}")
    dropped = settled_1["dropped"] + settled["dropped"]
    print(f"  cover floor (r9): {settled_1['moved']} + {settled['moved']} pieces walked onto a "
          f"floor that is really there (before / after the hive wells), {len(dropped)} dropped "
          f"with nowhere to stand, {settled['filled']} put back to hold L4"
          + (f" ({', '.join(dropped[:6])})" if dropped else ""))
    all_cut = cut_dropped + late_dropped + route_dropped + late_routes
    print(f"  lots over a ground cut or a route (r8/r9): {len(all_cut)} dropped, "
          f"nothing else moved"
          + (f" ({', '.join(all_cut)})" if all_cut else ""))
    field = coverfield.audit(layout)
    print(f"  cover field (r7): {field['pieces']} pieces on {field['centres']} distinct centres, "
          f"{sum(r['pairs'] for r in field['per_arena'].values())} pairs closer than "
          f"{coverfield.MIN_GAP:.0f} m")
    print("    per arena " + "  ".join(
        f"{aid} {row['pieces']}/{row['centres']}" for aid, row in field["per_arena"].items()))
    print("  spawn sockets (fight tier, r5): " + "  ".join(
        f"{a['id']} {len(a['spawn_sockets'])}@{a['fight_tier']:+.0f}" for a in arenas))
    print(f"  routes (r8): {relayed['shaft']} shafts placed, {relayed['take_off']} take-offs "
          f"moved, {relayed['stairs']} stairs re-laid, {relayed['piers']} piers dropped; {route_pierce['holes']} deck holes + "
          f"{route_pierce['openings']} parapet openings declared"
          + (f"; {len(route_pierce['stubborn'])} left for a filter or a Request: "
             f"{route_pierce['stubborn'][:3]}" if route_pierce["stubborn"]
             else "; nothing left over"))
    print(f"  hive wells  {wells_cut:5d}   spires: " + "  ".join(
        f"{h['id']} ({h['pos'][0]:.0f},{h['pos'][1]:.0f},{h['pos'][2]:+.0f})"
        for h in hive_records))
    for note in hive_notes:
        print(f"    hive: {note}")
    print(f"  Civic Quarter: {quarter_tagged} buildings tagged quarter=d4q")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
