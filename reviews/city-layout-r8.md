# city-layout r8 — lead brief: the vertical connections must exist in 3D, not only in plan

## Why
The r15 acceptance pass drove the mech up every designed route onto the A2 and A6 Hive Spire tiers, and an
adversarial verifier reproduced it (`map-hive-a6-a2-routes-dead`, `layout-zero-run-stairs`):
- **A2's tier (K3 +32) has no working way in; A6's (Sky Garden +144) is reached only by an undesigned thruster
  climb.** MAP §2 wants ≥ 3 approach routes per hive tier; ACCEPTANCE §1 needs all three spires in play (A2's pods
  are probably still shootable from the viaduct, which is why this is major, not a blocker).
- **Two stairs are walls.** `con_A4_M3_stairs` is an invisible 3 × 28 × 48 m collision slab on the A4 arena floor
  (the mech stops dead at x 465, the reticle reads "BLOCKED 19m" at open air); `con_O4_O5_stairs` is a 96 m slab
  buried in the pagoda.
- **`validate_layout.py` PASSes on all of it.** L3 skips every connector kind but `ramp` (`validate_layout.py:258`)
  and reads one overall `grade_deg`; L1 counts a record, not a walkable route; `hive_rule.approaches` counts outbound
  drops, a canopy roof and straight from→to lines in plan. Every check is 2D or reads a declared number.

The findings were made at b5d26d4 (frozen copy `~/m/mc-accept`); `git log b5d26d4..HEAD -- data/map tools/map
blender/city game/world/city` is empty, but re-check each item on HEAD first and write what you saw in your status
file. If one is already fixed, say so with the evidence.

You own `tools/map/**` and `data/map/{level_graph,district_rules,overrides,city_layout}.json`. The geometry (built
openings, stair/helix solids, the Knot and pagoda landmark builders, the in-engine C12) is city-build's, in the round
after yours, on your file. You do not run Godot this round.

## 1. Two stairs have no horizontal run (major)
- **Defect:** A4 and M3 both stand at (460, 420), O4 and O5 both at (−520, 430) (dossier §4.8: "horiz 0").
  `tools/map/connectors.py::_stair_path` (L78–91) sets ux = uy = 0 for a zero run, so the ±26 m landing jog (L86)
  multiplies a zero normal and every point keeps one x, y; city-build's `ramp_solid` stands each flight on end.
- **Repro (HEAD):** `python3 -c "import json;d=json.load(open('data/map/city_layout.json'));print([(c['id'],c['path']) for c in d['connectors'] if c['kind']=='stairs'])"`
- **Done:** real flights round the stacked nodes, made by the generator, not an `overrides.json` `move`
  (`overrides.apply`, L28, runs after every stage that reads the connectors). A4→M3 lands on the `M3_bridge_mid`
  edge. O4→O5 climbs outside the pagoda's solid tiers (`blender/city/kit/landmarks.py::pagoda` L151–172 stacks boxes
  53.8 m wide at the base, and the 56 m `O5_pagoda_crown` deck overhangs them all) and lands on the crown rim. Every
  flight passes item 4: ≤ 20°, rise ≤ 32 m (C8), landings ≥ 8 m deep, 24 m clear over the whole path.
- **Gate:** item 4 names both on the HEAD file and passes them on yours; a section of each (Gates).

## 2. A6 Sky Garden: no designed approach works (major)
- **Defect:** `con_F6_F4_stairs` runs node to node, from F6 (60, −360, +80) on the garden's east edge to F4 at the
  garden's centre, so the whole climb is under the `A6_sky_garden` slab (9.9 m clear on the upper flight, and it ends
  inside the slab), at 22°. `con_F7_F4_vent`'s pad (−170, −500) is under `canopy_st_H5_F2_1` (+40) and inside the
  garden's footprint: capped twice, and no vent runtime exists anywhere in `game/`. Only two graph edges into F4
  start anywhere else: F5 (the edgejump's far end) is reachable only from F4, and both drops lead out.
- **Repro (HEAD):** `cd tools/map && uv run --with numpy --with shapely --with networkx python3 -c "import json,hive_rule as h;d=json.load(open('../../data/map/city_layout.json'));[print(x['id'],[[i for i,_ in g] for g in h.sectors(h.approaches(d,x))]) for x in d['hives']]"`
  prints for A6 (ids less `con_`) `[F4_F2_drop, F6_F4_stairs, F4_F6_drop] [F4_F5_edgejump] [F7_F4_vent]`.
- **Done:** the stairs climb outside every slab above them and top out at the garden's edge through a declared
  parapet opening (a new additive deck field: specify it in Requests for city-build and for the lead's MAP §3). The
  vent column is open from the pad to +160 (declared deck holes, or a pad beside the garden's edge) and lands on the
  garden. A third inbound route on the edge the lead names at dispatch, added through a new `graph.extra_edges` lever
  in `overrides.json` (beside `edge_tags`) that `extract_graph.py` applies.
- **Gate:** `hive_a6` passes the new `approaches()` (4e) with ≥ 3 inbound routes in ≥ 3 sectors.

## 3. A2 Knot: K3 cannot be entered (major)
- **Defect:** the Knot decks in `data/map/district_rules.json` overlap in plan, 16–24 m apart: `K2_knot_l1` a solid
  r 105 disc at +16 (L274), `K3_knot_l2` a solid r 108 disc at +32 (L291), `K4_knot_flyover` a ring r 70–132 at +56
  (L308), `K5_knot_crown` 230 × 90 at +80 (L325). That is 12 m clear under K2 and K3 and 18 m under K4 and K5,
  against a 3.5 × 15 m capsule (`mech_tuning.gd:13–14`) and MAP L3's 24 m. So:
  - both Ring Viaduct W legs (`via_K3_V2`, `via_K3_V7`) join K3 under K4, ~15 m over a 5 m parapet: the mech wedges;
  - the helices spiral round (−470, −40) onto nodes 0–50 m from it (all but K4, 120 m; K3 and K5 sit on it; `_helix`
    L25–55 clamps r to 6 m at L46–47; dossier §3.2 says r 60–90 m) and run into the slabs (in engine: K2→K3 5.8 m
    clear mid-way, K3→K4 0.6 m, K4→K5 0.4 m; K1→K2 ends 12 m under K3 in the data), with 24–26° segments where r
    collapses;
  - `con_K1_K3_edgejump` takes off under the K3 disc;
  - `approaches()` counts `canopy_d2_street_4_1` (a +40 canopy roof), and the five real routes arrive in two sectors;
  - city-build's `landmarks.py::knot` (L30–55) builds a second Knot the layout never declares: four ring slabs at
    +16/32/56/80 with 5 m barriers on both rims, helices, and four flyovers.
- **Done:** ≥ 3 inbound routes onto K3 from ≥ 3 sectors, each reachable without passing K3 and each passing item 4
  (24 m over every sample and every rim crossing, declared parapet openings, helices at r ≥ 60 m clear of the slabs
  above, edgejump take-offs in the open). Keep every graph node where it is (x, y, z) and re-shape the decks and
  paths round them: K3 stays +32, where the Ring Viaduct W runs. Your sweep models the landmark's solids from its
  params until city-build removes them. If K3 cannot reach 3 sectors, report the numbers; do not relax the rule.
- **Gate:** `hive_a2` passes the new `approaches()` and keeps its 40 m of open ground and ≥ 8 firing positions a pod.

## 4. Make the checks 3D (major)
New sub-checks in their own module (`validate_layout.py` is 509 lines), reading the written JSON the way L11 and
`hive_rule` do, never the generator's geometry:
- **a. Run vs rise** (MAP §5 L3, dossier C8), on every ramp and stairs segment: plan run ≥ rise / tan 20° (a climbing
  segment with no plan length fails); a stairs flight rises ≤ 32 m.
- **b. Headroom:** sample every ramp/stairs path, and every edgejump from its take-off through the jump at the upper
  rim, at ≤ 4 m along and across the width minus the capsule radius; floor → lowest solid ≥ 24 m
  (`mapconst.UNDER_DECK_CLEAR`). Solids: decks minus holes, buildings minus `holes`, viaducts, rails, cover, columns,
  the 4 m truss collider under every `span` deck (`blender/city/kit/decks.py::_truss` L101: the polygon's bounding
  box, from 3 m under the slab to 1 m into it; it is the z 33 ceiling the verifier hit under the +40 canopies), and
  the landmark solids the builder makes.
- **c. Columns** (lift/vent/vcat): the pad column from `from` to `to.z` + 16 m crosses no slab without a declared
  hole, and its top lands on, or at the edge of, the `to` floor. FAIL on hive routes (`con_F7_F4_vent`, and A5's
  `con_W3_W4_vcat`, capped by `W4_foundry_l3`); NOTE with the id and the slab for every other up-shaft.
- **d. Rim crossings:** where a corridor or connector enters a deck: 24 m clear over it and a declared parapet opening.
- **e. `hive_rule.approaches`** (L198–220) counts only inbound routes (`to` on the tier, or bidirectional), on their
  real path, that pass a–d and whose start is reachable from H0 without the tier's own nodes; a deck counts only
  where a route joins it. `hives.candidates` sorts sites on this (`hives.py:101`) at `build_layout.py:98`: item 5.
  A5 is measured by the same rule; if it drops under 3, fix it the same way.
- L1's "realised" becomes "realised by a connector that passes a–d".
- Expect on HEAD (my rough 2.5D measure; confirm it): everything in items 1–3, plus three the same rule catches:
  `con_A1_H3_stairs` (its upper flight runs through `canopy_d1_street_6_1` (+40), whose truss is the z 33 ceiling the
  verifier's control wedged under, then climbs into `H3_crane_cab` from below; the H3 node itself is under the crane's
  48–56 m cab collider, `landmarks.py::cranes` L111), `con_W8_V6_ramp` (0.8 m under `via_V5_V6`; its first flight
  also runs through warehouses `D6_b016` and `D6_b025`), `con_V3_A3_ramp` (21.9 m under `canopy_st_A3_F2_1`). Fix
  them too: one root cause, paths built node to node, blind to the slabs above. A second shows in the cover term:
  only the endpoints are kept clear (`keepclear.py`), so arena cover stands on runs (hard `A1#0` and soft `A1#42` on
  `con_A1_H3_stairs`'s centre line; pieces on the Knot helices, `con_A3_S2_ramp` and `con_V3_A3_ramp`).
- **Gate:** each sub-check FAILs on the HEAD file naming those ids and PASSes on yours (`validate_layout.py --layout=<file>`,
  a flag you add: today `main()` reads only `data/map/city_layout.json` and ignores its arguments, so the r7 run in
  Gates would silently check your file).

## 5. Do not re-roll the city: a per-key diff with every layout change (process)
`build_layout.py` threads one `random.Random` (L67) through every stage, and the spires are sited at L98, before the
canopies (L100), the arena cover (L110) and the fill (L141) draw from it. Putting the crust cuts into the block mask
once re-rolled 334 of 354 buildings and broke every pinned street camera (`cuts.py` docstring). So write each 3D fix
as a cut or filter that draws nothing, placed after the last stage that both draws and reads what it changes, the
way `cuts.sweep` and `settle_cover` are. If a fix cannot be written that way, stop and put it in Requests first.
- **Done:** a new `tools/map/layout_diff.py <old> <new>`: per top-level key, the ids added, removed and changed, with
  the changed fields; cover matched per arena by content (its ids are positional), hives by position. Allowed: the
  re-laid connectors, the decks they touch, those arenas' cover and sockets, moved hives, the sky graph near them.
  Every changed building, anchor or skyline row is listed with its reason.
- **Gate:** the diff in your status file; the lead re-runs it.

## Gates (the lead re-runs all of these; `PY` = `uv run --with numpy --with shapely --with networkx python3 tools/map`)
- Graph, if it changed: `uv run --with networkx python3 tools/map/extract_graph.py`, then `validate_graph.py` → PASS.
- `PY/build_layout.py` twice: identical md5, `meta.revision` 8, both idempotence asserts quiet.
- `git show 79c69d3:data/map/city_layout.json > tmp/city-layout/layout_r7.json` (md5 1567d61d…), then
  `PY/validate_layout.py --layout=tmp/city-layout/layout_r7.json` → FAIL listing item 4's ids, and
  `PY/validate_layout.py` → PASS, its hive line printing the inbound routes per sector.
- `PY/layout_diff.py tmp/city-layout/layout_r7.json data/map/city_layout.json`.
- `preview.py`, `street_view.py`, `measure_arena.py` re-run; the HEAD file's numbers hold or are explained (cover per
  arena, C14 proxy, 32/32 sockets, pods ≥ 8 positions, 0 cover pairs under 6 m). Not the r7 evidence in
  `status/city-layout.md`: city-build r9 rewrote the file since (358 buildings, 544 cover). These tools read only
  `data/map/city_layout.json`, so measure HEAD before your first build; to put HEAD back later, copy yours aside and
  `git show HEAD:data/map/city_layout.json > data/map/city_layout.json` (never `git stash`: the stack is shared).
- Captures the lead looks at: per re-laid connector a plan crop plus an unrolled section along its path (floor, lowest
  solid above, 24 m envelope, openings), `captures/layout_r8_<id>.png`; the Knot and Sky Garden/F6/F7, HEAD vs yours.
- No `tools/map` file over 600 lines (one that would cross it is split first, in its own commit; `arenas.py` is 546);
  commits with an explicit path list; a round 8 section in `status/city-layout.md` with the diff and the HEAD
  re-check. No dead code (the 2D `approaches()` is replaced, not kept beside). Never write "fixed" without the re-run.
- After city-build rebuilds (the lead, not you): copy `verify-layout-zero-run-stairs/` and
  `verify-map-hive-a6-a2-routes-dead/` from `~/m/mc-accept/game/tmp_accept/` to `game/tmp_accept/` (uncommitted;
  repoint `stairs_probe.gd`'s `OUT`, and both probes' hard-coded HEAD routes to the new paths: `stairs_probe.gd`
  `pa`/`po` (L349–350), `vprobe.gd` `HIVE_A2`/`HIVE_A6` and its `stairs`, `via_*`, `parapet_*` and `helix` waypoints),
  then `tools/godot.sh drive --scene=res://tmp_accept/<dir>/<probe>.tscn
  --timeline=res://tmp_accept/<dir>/end.json --skip-menu --god --no-enemies --stub=flow,boss --tod=0 --quality=low`
  (`vprobe.tscn`: split its tests with `--vtest=`; `drive`'s heavy slot times out at 600 s).
  Pass: real-input climbs end grounded within 5 m of +80 at M3 and +128 at O5; no vertical slab at (460, 420) or
  (−520, 430); no-teleport drives from the Ring Viaduct and F6/L1 reach K3 and the garden by ≥ 3 routes each,
  grounded within 5 m of the tier.

## Coordination
- **city-build** runs after you, on your file, and takes the geometry half: parapet openings from your new field
  (`blender/city/kit/decks.py::_parapet` L18–30 walls every edge); `kit/connectors.py::stairs` (L52) fails the build
  on a flight over 40° instead of emitting an invisible wall; C12 sweeps stairs and ramps along their paths
  (`game/world/city/tools/checks.gd:182` never sweeps the 3-point "walk" arc of L207; ARC_MODE at L160 has no ramps);
  `landmarks.py::knot`/`pagoda` collision matched to what you declare; the lift/vent/vcat runtime if the lead puts it
  there. Spell out the new fields in Requests as r4–r7 did; name the connectors of city-build's Requests 1/3 you closed.
- **city-kit** (r10, props, in flight) regenerates `data/map/kit_assign.json` once your file lands (cover ids are
  `<arena>#<index>`); do not touch it. **trailer:** A6 is its combat stage and the part B re-records are held, so
  name anything that moved on A6. **flow** r5 reworks the hive hull and pods (its item 7): keep `hive_rule`'s pod
  model, and say in Requests if a spire moved. No other unit in flight touches `tools/map` or the layout files.
- No ownership exceptions: do not edit `blender/**`, `game/**`, `docs/**` or the dossier. Requests channel: the
  Requests section of `status/city-layout.md`.

## Lead decisions (read first)
`reviews/r16-lead-decisions.md` holds the lead's dispatch decisions. Read its "Shared" section, and every section that names this unit, including those under "Round 2". Where a decision and this brief differ, the decision wins.
