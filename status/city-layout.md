# city-layout status

## Round 8 (lead r8) — IN PROGRESS, NOT PASSING. Read this section first.

**Where it stands.** The 3D route checks are built, they FAIL hard on the r7 file, and the
generator now fixes most of what they find — but `validate_layout.py` is **FAIL (56)**, not PASS.
18 of 40 swept connectors pass a-d (r7: 1 of 40). The remaining work is listed under
"Not done" below; nothing here is claimed as fixed without the re-run beside it.

### What landed
| | |
|---|---|
| **a. run vs rise** | **PASS.** 0 failures (r7: 12, all on the three zero-run stairs). |
| **b. headroom** | 25 of 40 pass. r7 had 1. |
| **c. columns** | 13 of 13 shafts placed and open; 4 top stops still land on no floor. |
| **d. rim crossings** | 47 deck holes + 59 parapet openings declared; 2 crossings left. |
| **e. hive approaches** | rewritten in 3D; it is what now fails `hive_a2` and `hive_a6` honestly. |

New: `tools/map/{route3d,checks_routes,routes3d,openings,layout_diff}.py`.
Changed: `extract_graph.py` (+`graph.extra_edges`), `overrides.json`, `level_graph.json`,
`cuts.py`, `floors.py`, `corridors.py`, `hive_rule.py`, `hives.py`, `build_layout.py`,
`validate_layout.py` (+`--layout=`).

### The rule the generator applies (all of it draws no random number)
A designed route has right of way, and what yields depends on what is in the way:
a **deck**, a **tunnel roof**, a **viaduct or rail slab** or a **building** yields a `holes`
entry; a **parapet**, an **edge barrier** or a **tunnel wall** yields an `openings` entry; a
**building lot**, an **arena crate**, a **viaduct pier** and a **deck column** are dropped or
moved by a filter; a **landmark** does not yield (see Requests). Shafts, take-offs and landings
are *placed* (`params.shaft` / `params.take_off` / `params.land_at`) inside 90 m of their nodes,
and the two `horiz 0` stairs become generated stair towers.

### Commits posted (conflict map E1 — city-build builds only from the committed file)
| commit | what |
|---|---|
| `2ede023` | the 3D solids model + the four sub-checks, FAIL(79) on HEAD; the day-one `con_F3_F4_vcat` row |
| `f124ab2` | `graph.extra_edges` lever + the `F3 -> F4` vcat edge (graph PASS, 107 edges) |
| `437e0b9` | **the layout**: `data/map/city_layout.json` md5 `615d1f71…`, `meta.revision` 8 |

`test_design_copy` is red from `437e0b9` until city-build rebuilds on r8 — that is E1's window.

### Determinism
`PY/build_layout.py` run twice: **identical md5 `615d1f7137dc9c1fc4a24075af3bce1b`**,
`meta.revision` 8, no file in `tools/map/` over 600 lines (largest `arenas.py` 546).

### Evidence (both runs on this tree)
```
PY="uv run --with numpy --with shapely --with networkx python3 tools/map"
git show 79c69d3:data/map/city_layout.json > tmp/city-layout/layout_r7.json   # md5 1567d61d...
$PY/validate_layout.py --layout=tmp/city-layout/layout_r7.json
  -> routes in 3D (r8): 1/40 connectors pass a-d · 9 deck holes, 0 parapet openings,
     0 shafts placed, 0 take-offs moved · worst headroom 1.0 m on con_A4_M3_stairs
  -> FAIL (184)
$PY/validate_layout.py
  -> routes in 3D (r8): 18/40 connectors pass a-d · 47 deck holes, 59 parapet openings,
     13 shafts placed, 3 take-offs moved · worst headroom 1.0 m on con_O1_O2_edgejump
  -> FAIL (56)
```
The r7 run names every id the lead's item 4 lists: `con_A4_M3_stairs`, `con_O4_O5_stairs`,
`con_F6_F4_stairs`, `con_W8_V6_ramp`, `con_V3_A3_ramp`, `con_A1_H3_stairs`, the four Knot ramps,
`con_F7_F4_vent`, `con_W3_W4_vcat`, `con_A5_W4_lift`, and the five mid-air lift tops
(`con_S5_S3n_lift`, `con_F3_F6_lift`, `con_M1_M5_lift`, `con_M6b_M4_lift`, `con_M3_M4_vcat`).

### Not done (honest)
1. **The Knot (item 3) is not re-designed.** Its four ramps still fail b
   (`con_K1_K2_ramp` 10.0 m, `con_K2_K3_ramp` 1.2 m, `con_K3_K4_ramp` 2.5 m,
   `con_K4_K5_ramp` 1.4 m) and `con_K1_K3_edgejump` still takes off under `via_K3_V2`.
   The decks were not re-shaped, so `hive_a2` has 2 inbound routes, not 3.
2. **Four shaft top stops still land on no floor**: `con_M1_M5_lift`, `con_M6b_M4_lift`,
   `con_M3_M4_vcat`, `con_A5_W5_vent` (the last is capped by a reactor stack).
   `con_U5_S5_lift`, `con_F7_F4_vent`, `con_A5_W4_lift` report a column cap.
3. **Ten edgejumps and two ramps still fail b**: `con_A1_V2_edgejump`, `con_O1_O2_edgejump`,
   `con_O2_O3_edgejump`, `con_V7_O1_edgejump`, `con_A3_S6_edgejump`, `con_F4_F5_edgejump`,
   `con_V5_A5_edgejump`, `con_A5_W3_edgejump`, `con_V3_A3_ramp`, `con_A4_M3_stairs`. The
   take-off search did not find an open spot for them inside 90 m of the node.
4. **C14 regressed**: 6 arenas report a sample with no full cover within 60 m, because the
   route strips took 135 of 544 crates. `cover_pass` now iterates to convergence (the r7
   two-call assert became a four-call loop) and still reports 1 pair under 6 m in A5.
5. **`hive_a6` reports 0-2 inbound routes** under the new 3D rule; the Sky Garden stairs and the
   vent are laid but the routes that use them do not pass a-d yet.

### Conflict map E7 — THE HIVES MOVED (post to flow, city-build and trailer)
| spire | r7 | r8 | why |
|---|---|---|---|
| `hive_a2` | (-476, -106, +32) | **(-440, 14, +32)** | the 3D `approaches()` re-scores every candidate site |
| `hive_a5` | (464, -160, +80) | unchanged | |
| `hive_a6` | (-48, -430, +144) | **(-72, -442, +144)** | same |

This is the one thing I could not hold: the site search sorts on the approach count, and the
new rule counts fewer routes, so the winner changed. It also re-rolls the arena cover and the
sky graph behind it (the diff shows 520 id-level changes, most of them that). If the lead wants
the spires pinned, the fix is to score the search on something stable and gate on the 3D rule
only — say the word and it is one flag in `hives.candidates`.

### Diff (lead re-runs `PY/layout_diff.py tmp/city-layout/layout_r7.json data/map/city_layout.json`)
`tmp/city-layout/diff.txt`. Summary: **520 id-level changes**. Corridors change `holes`,
`openings`, `piers` and (for the three collar viaducts) `points`; decks change `holes` and
`openings`; connectors change `path`, `params`; 79 lots and 135 crates are dropped by the route
filters; the cover is re-rolled behind the moved hives (A5 0 of 131 centres kept); the sky graph
moves with it.

### Day one: the row city-build and traversal need (conflict map E3)

### Day one: the row city-build and traversal need (conflict map E3)
`con_F3_F4_vcat` is a **new graph edge** `F3 -> F4`, kind `vcat`, one-way up, added through the
new `graph.extra_edges` lever in `data/map/overrides.json` and applied by `extract_graph.py`:

| field | value |
|---|---|
| id | `con_F3_F4_vcat` |
| edge | `F3` (Tower Lift Lobby, D7, L1, `[-120, -360, 0]`) -> `F4` (Sky Garden, D7, L4, `[-60, -450, 144]`) |
| kind | `vcat` (vertical catapult) |
| bidir | **false** (up only; `F4 -> F2` / `F4 -> F6` drops are the way down) |
| width | 44 m (the palette's `vcat`), `params.pad` `[44, 44]`, `params.rise` 144 |
| why F3 | it is the only node the player can already reach on the ground that is not already an end of an F4 edge: `F2 -> F3` is a street (`st_F2_F3`), `F3 -> F6` is the lift, and F3 stands 100 m from the garden's footprint, so a 144 m column there is open sky (checked by L3c) |

**city-build: the movers count becomes 19, not 18.** **traversal: list it PENDING until
city-build's commit** (conflict map E3).

### Conflict map E1 / E7 — how this round is run
* `data/map/**` is committed in coherent steps and each commit is posted here; city-build builds
  only from the committed file. `test_design_copy` stays red from the first commit until
  city-build rebuilds on r8 — that is expected and is E1's stated window.
* The three Hive Spires are kept where they are unless a 3D fix forces a move; any move is
  posted here for flow, city-build and trailer.

## Plan (files I own)
```
tools/map/
  mapconst.py       MAP §1 constants, palettes, layer (sub-)datums, paths
  extract_graph.py  dossier §4.7/§4.8 tables -> data/map/level_graph.json
  validate_graph.py C1-C11 (port of §5.4) + the accepted-exception list
  zones.py          build zones: a district may own several (D4 = plaza + Civic Quarter)
  streets.py        per-zone street hierarchy (grid / contour / radial / spines, snapped)
  corridors.py      graph corridors, decks (incl. the circular Crown), clearances, canopies
  connectors.py     one connector per non-corridor edge
  fabric.py         block -> lot geometry: `subdivide` (perimeter + courtyard) and
                    `terrace_row` (party-wall terraces with stair-alleys, Old Town)
  lots.py           lot -> building record, biggest inscribed rectangle, the Spire cone
  fill.py           zone fill, coverage against BUILDABLE land, frontage, breaches
  wall.py           kerb street walls + podium-through blocks (MAP §4 "General")
  straddle.py       viaduct/rail-through (MAP §4 r2): towers standing over the Ring / Skyrail
  towers.py         the D7 deck carriers, planted before the fill so they have room
  skybridge.py      D5 canyon skybridges, deck-carrier raising, the D7 deck ring
  props.py          landmarks, Block 9 + its Liziba station, anchors, start, skyline
  arenas.py         arena outlines, walkable surfaces, cover per surface (r4 split)
  sockets.py        arena spawn sockets (r5): reserve the floor, then re-check it late
  hive_rule.py      the r6 assault rule (open ground, pods, routes) + `verify`, shared
  hives.py          spire siting: reserve the ground, cut the light well, re-site late (r6)
  hive_repair.py    the late half: clear the ground, flatten the lanes, put cover back (r6)
  measure_arena.py  C13/C14 proxies from the layout data (headroom, cover within 60 m)
  keepclear.py      the 12 m connector endpoint spheres and the solids that must miss them
  coverfield.py     where a cover piece may stand (r7): the MIN_GAP rule + the keep-outs
  supports.py       deck carriers: towers, columns, spans
  terrain.py        escarpment seam + lips, canal, docks, plateau
  vistas.py         lead vistas: keep-clear slots + first-hit check (L8)
  skygraph.py       sky_waypoints + sky_edges: the flyer routing graph (MAP §3 r3)
  build_layout.py   orchestrator -> data/map/city_layout.json
  validate_layout.py L1-L3, L6-L10 ; checks_arena.py L4/L5 ; checks_sockets.py L11
                    checks_hives.py the r6 hive sub-check of L4
                    layout_report.py  sight.py  geom.py
  preview.py        plan + S-N section   massing.py  iso views + Crown detail
  street_view.py    pinhole street-level renders (6 cameras)
data/map/  level_graph.json  district_rules.json  overrides.json  city_layout.json
captures/  layout_plan.png  layout_iso_{sw,ne,top}.png  layout_section_ns.png
           layout_street_{h0,skygarden,spire_ave,canyon,skygarden_up}.png
           layout_crown_north.png
```

## Done (round 7 — lead review r7, the cover field stopped standing on itself)
1. **Every placement now goes through a `coverfield.Field`** (new `tools/map/coverfield.py`).
   Two rules the arena stage never had: a piece must clear every piece already on its surface
   by **6 m** (exact axis-aligned rect distance, `rect_gap`), and it must miss a keep-out that
   is now z-aware. `Field` wraps the arena's **live** cover list, so a piece dropped later (a
   firing lane, a carrier tower) leaves the field with it. Wired into `cover_for`, `_place`,
   `_place_near`, `_top_up`, `towers_for`, `cover_pass` and `hive_repair._place_clear` — every
   path the review named.
2. **Result: 539 pieces on 539 distinct centres, 0 pairs closer than 6 m** (r6: 1,070 pieces
   on 784 centres, 4,297 pairs under 6 m). Nearest-neighbour spacing per arena went from a
   median of 0–7.6 m (A6/A5/A2, i.e. stacked) to **32.6 / 36.2 / 35.2 / 35.8 / 33.2 / 35.6 /
   48.2 m** (A1–A6, B) with a minimum of 24.8 m — inside dossier §3.2's 40–60 m band and no
   longer a cube pile.
3. **`cover_pass` is idempotent and asserted.** Two changes were needed: (a) the build ran it
   **twice** (lines 336 and 353) plus `hive_repair.recover_cover`, so there is now **one**
   top-up, on the finished city; (b) `_place_near` used to give up on a spot when the *drawn*
   box did not fit, which left the hole for the next pass to find — it now falls back to fixed
   smaller sizes, the last of which (`20 x 20 x 20`) is the smallest legal full-cover piece, so
   a spot that can hold any legal piece holds one. `build_layout` calls `cover_pass` twice and
   `raise SystemExit` if the second adds anything: it prints `a second pass added 0`.
   The oscillation with `_clear_cover` is gone too: a carrier tower's footprint joins the
   keep-out, so the top-up cannot put back what the tower stands on (4 pieces dropped).
4. **A 30 m keep-out round every vista camera** (`vistas.camera_zones` / `camera_caps`).
   Cover may not enter the sphere at all (it is small and plentiful). A building, a deck or a
   column may not *rise above the lens* within the 30 m disc — capping everything to
   `pos_z - 30` would dig a 60 m pit in the Old Town, and what matters is that the lens is
   never inside or behind a mass. Wired in as: `camera_zones` → the cover `KeepOut`;
   `camera_caps` → `vista_slots` (so the fill, the kerb walls, the podiums, the straddles, the
   carrier towers, the canopies and the D7 ring all take it), `skybridge.canyon_bridges` (a
   skydeck over V4's head is the frame) and the deck-column lattice. `vistas.in_sphere` is the
   check and **L8 now fails on it**: the finished layout reports **nothing inside any of the
   eight spheres** (r6 had V4 inside A4's piece #52 and V6 4 m over two stacked centres).
   Landmarks are exempt — a camera is deliberately placed on its own set piece (V1 stands on
   the Insertion Pier) — and so is the slab a camera stands on.
5. **The gameplay rules still hold.** `validate_layout` **PASS** (L1–L11 + the new cover-field
   sub-check of L4): C14 proxy A1/A3/A4/A5/A6 **100 %**, A2 **99.5 %** gated (10 of the 11 raw
   misses are inside the r4/r6 exemptions, which the proxy now prints), B 0 % by design. The
   three hive spires pass the r6 rule with **more** clear firing positions than before
   (8/45, **16**/48, **14**/48 against 8/9/8). 32/32 spawn sockets, 116/116 connector
   endpoints clear, Spire visible from 89.9 % of navigable samples, still the tallest thing at
   360 m (next 240 m).
6. **`measure_arena.py` now prints the exemptions** next to the raw C14 number, so the 94.5 %
   it reports for A2 explains itself instead of looking like a regression.

## Done (round 6 — lead review r6, hive spires on open firing ground)
1. **The rule is one module, `tools/map/hive_rule.py`, and both sides measure with it.** A hive
   is assaultable when (a) its 40 m of open ground on its own tier carries no solid and the 64 m
   of air over it is clear, (b) every pod in the 10–55 m band is shootable from **≥ 8** of the
   **48** positions flow's E2E bot tries (`flow_debug_assault`: 8 bearings × 70/100/140 m ×
   +8/+30 m over the pod — the grid r3 found empty), and (c) **≥ 3 approach routes** arrive on
   the tier in three different 60° sectors. `verify()` re-derives all of it from the layout dict:
   `hives.build` repairs with it, `checks_hives.check_l4_hives` gates on it, so the two cannot
   agree by construction. Pods and trunk come from `hive_visual.gd` (4 pods on the trunk's
   surface, `TRUNK_RADIUS` 13.2 m — a real solid, so a far-side pod is genuinely occluded).
2. **Siting is a reservation, then a late repair (`tools/map/hives.py`, `hive_repair.py`).**
   `reserve()` picks each site right after the arena outlines, before the canopies, the cover,
   the buildings and the deck columns exist, and returns the discs as a keep-out every later
   stage takes (cover, canopy caps, cornice caps for the fill, `keep_out` for straddle/towers,
   and the deck-column lattice mask). `punch()` then cuts the spire's **light well** through the
   decks above its tier — a hive under the Knot's flyover had no sky at all. `build()` runs last
   on the finished city: it re-measures the top 8 candidate sites, and for each one punches,
   clears, opens the firing lanes and puts cover back, committing the first that passes.
3. **Result — all three spires pass, and A2 moved 48 m to do it.** `hive_a2 (-440,-94,+32)`,
   `hive_a5 (464,-160,+80)`, `hive_a6 (-48,-430,+144)` — every tier is still the graph's own
   datum (K3, W4, the Sky Garden). Worst pod: **8 / 9 / 8 of 45–48 positions**; 3 approach
   routes each; open ground clear. Against the r5 layout the same check prints **8 failures**
   (`pod 0 at 12 m is shootable from 0 of 48 positions` at a2 and a6, 3 of 48 at a5 — exactly
   what flow r3 reported), so it has teeth.
4. **Two repairs that are only possible because the rule is measurable.**
   * `clear_lanes` flattens the cover standing in a spire's firing lanes to 8 m rubble (A2 is a
     stack of plates under 20–32 m crates; a 12 m pod was behind a wall of them from every
     bearing). It never touches a deck, a column or a building — those are reported, not cut.
   * `recover_cover` puts full cover back where the lanes opened a hole, but only where the new
     piece takes no more of a pod's kept firing lines than that pod has to spare.
5. **One conflict with C14, resolved and flagged.** A 12 m pod is only shootable if the lanes are
   clear out to where the player stands (flow's nearest candidate is 70 m out); C14 wants a 20 m
   piece within 60 m of the same spot. Inside the **70 m assault ring on the spire's own tier**
   the lead's r6 note wins: `checks_arena` exempts those samples the way it already exempts a
   connector's keep-clear sphere, prints how many (96 this run), and `recover_cover` leaves the
   ring bare. See Requests 8.
6. **New L4 sub-check** `checks_hives.check_l4_hives` (own file, like `checks_sockets`), wired
   into `validate_layout` and printed in the summary: `hive spires: hive_a2 A2@(-440,-94,+32)
   open y pods 8/45 routes 3 …`. Failure messages carry the spire id, its coordinates and the
   ids of the solids in the way.
7. **Previews** draw each spire's 40 m open ground (solid) and 70 m assault ring (dotted), named
   with its tier. `captures/layout_plan.png` regenerated and checked.

## Done (round 5 — lead review r5, spawn sockets on the arena's top walkable surface)
1. **Sockets are their own stage (`tools/map/sockets.py`).** They were a 10-line perimeter
   ring inside `build_arenas`, placed before the cover, the buildings and the decks existed.
   Now: `sockets.reserve()` runs right after the arena outlines and the canopies, picks each
   arena's sites on its **fight tier** (the main tier as `arenas.surfaces` defines it: the
   polygon minus the arena's own lower tiers and the voids of its own floor deck) and returns
   an 8 m disc per site as a keep-out; every cover pass then fills in *around* them, exactly
   the way it already worked around the r4 connector keep-clear spheres. `sockets.build()`
   runs last — after the late cover top-up, the tower clear-out and the deck columns — and
   re-checks every reserved site against the finished solids, replacing only the ones
   something late landed on.
   Rules enforced per socket: on the fight tier, **16 m off the wall** (the surface boundary,
   holes included), **16 m of clear air** above the 4 m agent, **12 m of free floor** around
   it with **no solid within 8 m**, on the walkable **island that reaches the arena centre**
   (the surface eroded by the agent's own radius), and ≥ 56 m apart where the arena has the
   room (40/28 m steps for a long thin one). Result: **32 sockets, every arena at its full
   count** — A1 4@+0, A2 5@+0, A3 5@+0, A4 6@+32, A5 5@+0, A6 4@+144, B 3@+224.
2. **New check L11** (`tools/map/checks_sockets.py`, split out of `validate_layout.py` the
   way `checks_arena.py` is, so both stay under 500 lines). It re-derives the surfaces and the
   solids from the written JSON — `sight.arena_surfaces` + `sight.blockers`, never the
   generator's own geometry — and fails on a socket off its fight tier, off the surface,
   inside 16 m of an edge, with less than 12 m of free floor, with a solid inside 8 m, with
   anything in the 16 m of air above it, off the centre's island, or two sockets closer than
   28 m. Run against the r4 layout it reports **55 failures** (wall 10-14 m, solids at 0 m),
   so it has teeth; against the new layout it prints per arena
   `A1 4@+0 wall 18 cover 8 sep 84 … B 3@+224 wall 16 cover 35 sep 151` and passes.
3. **Two latent bugs found while doing it, both fixed.**
   * `arenas._top_up` started its 24 m grid on the surface's own bounds, so a 24 m wide
     surface (every canyon skybridge) only ever offered its boundary rows — which are not
     inside it — and got **no cover at all**. Offsetting the grid half a step in gave A4's
     bridges their own cover and took the C14 proxy for A4 from 99.5 % to **100 %**;
     arena cover 756 → **803** pieces.
   * The socket "no cover within 8 m" rule was being tested against a 4 m query disc, so it
     could only ever catch a solid the agent was already standing in. Both the placer and L11
     now query with the full 8 m radius.
4. **Plan preview** draws the sockets as green triangles inside their arenas and names the
   count in the legend.

## Done (round 4 — lead review r4, the five city-build C12-C14 data fixes + the boss note)
0. **`props.py` split** (it had grown past 600 lines while I worked on it): `arenas.py` now owns
   the arena machinery (outline, surfaces, cover, sockets) and `geom.py` owns
   `shape_by_streets` and its edge helpers; `props.py` is the set dressing (landmarks, Block 9,
   hives, anchors, start, skyline) and re-exports `build_arenas` / `arena_outlines` /
   `cover_pass` / `set_soft` so the orchestrator is unchanged. Dead `chamfered()` removed.
   No file in `tools/map/` is over 490 lines now.
1. **Connector keep-clear (point 1).** New `keepclear.py`: a 12 m sphere at every connector
   `from`/`to`, built from the graph nodes *before* the corridors and arenas, and taken as a
   keep-out by every stage that places a solid — arena cover (`arenas.cover_for` tests the
   piece's own box, not a circle around it), viaduct piers (`corridors.build_corridors` drops
   a pier inside a sphere; `con_K1_K3_edgejump` sat on `via_K3_V2`'s first pier) and the
   cover top-up, which now searches outward for a legal site instead of leaving a hole.
   New **L2 sub-check** `check_l2_keepclear` tests buildings, arena cover, piers and deck
   slabs against all 116 endpoints and prints the count: **116/116 clear** (was 35/48 inside
   built mass). Connectors that share a node are exempt — a node is a junction — and the deck
   an endpoint stands *on* is its floor, not an obstruction.
2. **Arena under-deck clear ≥ 32 m (point 2).** A canopy that roofs arena ground now sits at
   **+40** (36 m clear on a 4 m slab) instead of +32 (28 m): **37 of 45 canopies**, the other
   8 stay at +32 outside the arenas. New **L3 sub-check** fails any deck with less than 32 m
   under it inside an arena polygon (`over_water` decks and an arena's own tier decks are
   exempt), and `arena_headroom()` *measures and reports* the tiers the dossier pins below
   that: 13 tiers, worst A1 +40 (4 m under the crane cab), A2 +0/+16 (12 m — the Knot's tiers
   are 16 m apart in the graph), A5 +0 (28 m under the Foundry deck). Measured C13 proxy:
   **2.1 % of 1,400 arena samples under 32 m** (A1 0, A3 0, A4 0, B 0, A2 1.0, A5 4.5,
   A6 9.5 %) and **3.5 % of 724 nav samples under 24 m**, against C13's 5 % gate.
3. **A1 Container Yard (point 3).** `district_rules.arenas.A1.towers` + `arenas.towers_for`:
   **4 `container_stack` pieces 24-28 m tall**, spread ≥ 105 m apart, never destructible.
   Cover is now placed per *walkable surface* instead of per tier, which is what was really
   wrong in A1: its cover stood at +0 over the dock floor at −12 (floating 12 m up) and none
   of it was on the canopy roofs at +40 where C14's downward ray actually lands. A1 now has
   110 pieces on three surfaces (dock −12, ground 0, canopy roofs +40) and the C14 proxy is
   **100 % of samples with full cover within 60 m** (city-build measured 22 %).
4. **Block 9 `holes` (point 4).** `props.declare_block9_holes` gives the building one MAP §3
   v2 `holes` entry per corridor that claims `through` it — **7 holes for 7 corridors**: the
   Ring Viaduct (40 m clear) and four plateau roads `st_V6_M1`, `st_M1_S5`, `st_M1_A4`,
   `st_M3_M5` (32 m) through the ground arcade, and both Skyrail halves (32 m) through the
   station hall. Each carries `polygon`, `z`, `height`, `clear`, `corridor`.
5. **Rails into Block 9 (point 5).** New deck **`deck_block9_platform`** at +80 inside the
   rail hole (77 m long, 46 m clear under it, `supported_by: ["D5_block9"]`, a `platform`
   record naming both rails), and both `rail_W4_M5` and `rail_M5_S3e` now carry
   `terminus: {deck, node: M5}`. The M1→M5 lift lands on that platform, not in mass.
6. **The Crown stays open (boss note).** `district_rules.arenas.B.open_cover` builds the
   allowed zone from the deck's own `rim_steps` and `fins`: **22 low pieces, every one 8 m**,
   at r 49-66 (core drum + the four fins) and r 95-150 (the three rim steps); the middle ring
   r 67-94 is empty floor. B's `cover_soft` is 0 (a boss arena has no destructible crates).
   New L4 rule: an arena marked `open_cover` may not carry a piece over 8 m, and it is exempt
   from "full cover within 60 m" — reported as a NOTE, because C14's blanket
   `worst_cover >= 0.999` cannot hold for a deliberately open boss arena (see Requests).
7. **Soft cover is now exact** (`arenas.set_soft`): a Bresenham step over each arena's final
   piece list instead of a dice roll per piece, so the MAP 30-40 % band is hit by
   construction: A1 34, A2 32, A3 38, A4 29, A5 35, A6 32 %, B 0 % by design.
8. **Checks made honest.** `checks_arena` had a module-level `FAIL` that did not exist, so an
   L4/L5 failure raised `NameError` instead of reporting (it only ever passed by luck); it now
   has its own `FAIL`/`NOTE` and `validate_layout` merges both. L4 samples each arena on the
   surface it really stands on (topmost deck under the point, exactly like C13/C14's ray from
   +320 m) and counts any ≥ 20 m collider as cover, as C14 does; the 26 samples that stand
   inside a connector keep-clear sphere are exempt and reported.


## Done (round 3 — lead review r2)
1. **Civic Quarter (point 1).** New build-zone concept (`zones.py`): D4 owns two zones — its
   plaza ground (z 0) and the **Civic Quarter** on the plateau (x −160…250, y 450…680, z +32).
   The quarter has its own grid on +32 (spacing 110 m) plus two hand-drawn spines — the Civic
   Axis continuing the Forum's north edge (S5) and a link east to the Ring Viaduct's M1 leg —
   civic archetypes (setback, podium tower, colonnade) and a `north_rise` ramp that lifts the
   cornice from 48 m at the Forum to 144 m at the plateau edge, inside the Spire view cone.
   Buildings still carry `district: "D4"` plus a new `quarter: "d4q"` tag: the schema and
   city-build are untouched. D4 coverage 30 % → **79 %** of buildable land.
2. **Viaduct/rail-through + D7 skyline (point 2).** `straddle.py` places towers standing over
   the Ring Viaduct (+32) and the Skyrail (+80): a hole = corridor width + 2 × 4 m, 40 m clear
   over a viaduct deck / 32 m over the rail, declared as `holes` + `through` on the building
   and `through` on the corridor, and the corridor stops capping the mass it pierces. A
   straddle pierces *every* straddlable corridor its box opens onto, because in D7 the ring
   and the rail run 35 m apart. `towers.py` plants the Sky Garden / Crystal Bridge / F6
   carriers **before** the fill — that is the only stage where there is still free ground
   beside the corridor. The elevated corridors also keep a 50 m right of way with no local
   street in it (`VIADUCT_HALO`).
   Result: **8 towers 128–240 m within 260 m of the two decks, 3 of them ≥ 200 m**, A6 open
   to the sky above its deck, 2 straddling towers piercing 3 corridors, 6 deck carriers.
3. **Overhead cover (point 3).** Free-standing canopies exist only inside arenas and within
   100 m of their outline (`corridors.canopies`), each on columns at ≤ 48 m or spanning the
   two facing frontages. Measured and checked in two bands: **54 % of 9,102 m inside/near the
   arenas (want 40–60 %), 1 % of 1,365 m elsewhere by architecture (want ≤ 25 %)**.
4. **Sky graph (point 4).** `skygraph.py` → `sky_waypoints` + `sky_edges`: +80…+240 m, nodes
   ≥ 12 m and edges ≥ 8 m clear of every building/deck/rail box, one connected component,
   **225 waypoints / 664 edges**, ≥ 24 per district (D1 29, D2 25, D3 24, D4 59, D5 27, D6 37,
   D7 24), ≥ 6 within 150 m of every arena centre (A1 19 … B 6), 12 ringing the Crown at
   +240. New check **L10**; drawn in the plan as thin violet lines.
5. **D3 Old Town (point 5).** `fabric.terrace_row`: contiguous party-wall terraces along every
   frontage (no 3 m gap), broken by a ≥ 24 m stair-alley every 60–90 m, heights 16–72 m on the
   4 m module. D3 coverage 50 % → **67 %** of buildable land, and it reads as one hillside
   town against the NW sun instead of rows of boxes.
6. **Coverage measured against BUILDABLE land** (the lead's answer 2), both numbers printed.
   Targets all met: **D1 55 (≥40), D2 65 (≥50), D3 67 (≥65), D4 79 (≥50), D5 90 (≥75),
   D6 68 (≥50), D7 84 (≥60).** The fix that moved every district was a fast path in
   `largest_inscribed_rect` — a lot that already *is* its bounding rectangle was being
   re-found by trial and error at half its area.
7. **Previews (point 6).** `captures/layout_crown_north.png` (Crown north rim +232 looking over
   the Civic Quarter) and `captures/layout_street_skygarden_up.png` (D7 street at 22 m looking
   up at the Sky Garden). Plan now draws the sky graph in violet and keeps its legend inside
   the frame (it was being clipped).

## How to verify (exact commands)
```
uv run --with networkx python3 tools/map/extract_graph.py
uv run --with networkx python3 tools/map/validate_graph.py                 # PASS
uv run --with numpy --with shapely --with networkx python3 tools/map/build_layout.py
uv run --with numpy --with shapely --with networkx python3 tools/map/validate_layout.py  # PASS
uv run --with numpy --with shapely --with matplotlib python3 tools/map/preview.py
uv run --with numpy --with shapely --with matplotlib python3 tools/map/street_view.py
uv run --with shapely python3 tools/map/measure_arena.py      # C13/C14 proxies, 200 samples/arena
```

## Evidence (numbers from the last full run — r7)
- Graph: nodes 60, directed edges 185, loops 37, dead ends 7 (12 %); C11 A4->A5 an accepted
  NOTE; start coverage worst 55.9 s, arena->arena worst 36.9 s median 18.9 s. **PASS**
  (unchanged this round — no graph or connector moved).
- Layout (`meta.revision` 7): 104 streets, 11 viaducts, 5 rails, 5 tunnels, 77 decks,
  392 buildings, 58 connectors, 7 arenas, **539 cover pieces**, 93 anchors, 96 skyline towers,
  225 sky waypoints, 668 sky edges. Byte-identical across two runs
  (md5 `cf76d464baa87396b92c6a3eb9898467`).
- **Cover field (r7, the lead's r7 ask)**: 539 pieces / **539 distinct centres** / **0 pairs
  closer than 6 m**; per arena `A1 80/80 · A2 145/145 · A3 88/88 · A4 51/51 · A5 131/131 ·
  A6 25/25 · B 19/19`. Against the r6 file the same audit prints 1,070 / 784 / 4,297.
  Nearest-neighbour centre distance, median per arena: A1 32.6, A2 36.2, A3 35.2, A4 35.8,
  A5 33.2, A6 35.6, B 48.2 m (r6: 24.8 / 7.6 / 28.0 / 24.7 / 4.0 / 0.0 / 46.8 m).
- **Idempotence**: `cover       539 (17 added by the late top-up, 4 dropped under a carrier
  tower; a second pass added 0)`. The build raises if that number is not 0.
- **Vista cameras (r7)**: no solid inside any of the eight 30 m spheres (`L8` clean);
  every vista reads its subject first (`V3` has nothing on the ray at all, `V8` is the
  panorama). Nearest cover in 3D: V4 30.4 m in plan at +80 (60 m below the lens), V6 37.0 m.
- **Hive spires (r6 rule)**: `hive_a2 A2@(-464,-106,+32) open y pods 8/45 routes 3 ·
  hive_a5 A5@(464,-160,+80) open y pods 16/48 routes 3 · hive_a6 A6@(-48,-430,+144) open y
  pods 14/48 routes 3`. `hive_a2` moved 27 m for open ground; 2 wells cut.
- **Spawn sockets 32/32** — `A1 4@+0 · A2 5@+0 · A3 5@+0 · A4 6@+32 · A5 5@+0 · A6 4@+144 ·
  B 3@+224`; worst wall 16 m (gate 16), nearest solid 8 m (gate 8), separation 57–151 m.
- **Connector keep-clear 116/116 endpoints** (12 m, against buildings + cover + piers).
- **Arena cover** (C14 proxy: a ≥ 20 m collider within 60 m, per surface): A1–A6 100 % raw
  except A2 94.5 % raw / **99.5 % gated** (10 of 11 misses inside a connector sphere or a
  hive's 70 m assault ring), **B 0 % by design**. 117 arena samples are exempt this round.
- Cover per arena / soft share: A1 80 / 35 %, A2 145 / 32 %, A3 88 / 38 %, A4 51 / 29 %,
  A5 131 / 36 %, A6 25 / 32 %, B 19 / 0 %; long sightlines 0 % everywhere (gate 5 %).
- **Arena headroom** (C13 proxy): 36/1400 = 2.6 % of samples under 32 m (gate 5 %), worst
  A1 +40 4 m — all dossier datums, reported as NOTEs.
- Block 9: 7 `holes`, `deck_block9_platform` +80, both rails `terminus` on it.
- Coverage of buildable land: D1 55, D2 65, D3 66, D4 79, D5 98, D6 68, D7 79 % — all targets met.
- Overhead cover: 53 % of 9,102 m inside/near the arenas, 1 % of 1,365 m elsewhere.
- Spire crown visible from 89.9 % of 813 navigable samples; tallest thing is the Spire at
  360 m (next: 240 m `D7_car01`).
- Checks: validate_graph PASS, validate_layout PASS (L1–L11, the L2/L3/L4 sub-checks and the
  new r7 cover-field sub-check).


## Known issues (honest)
0. **(r5) The "navmesh island" test is a 2.5D approximation.** L11 erodes the fight surface by
   the 4 m agent radius and asks the socket to share a component with the arena centre; it
   does not path-find, and it cannot see a ramp or a lift that would connect two islands at
   different z. Every socket is on the same *floor polygon* as its arena's centre, which is
   what city-build's navmesh bake will see for that tier.
1. **Only 2 viaduct/rail-through towers exist**, both in D7/D4, and the D7 deck ring reaches
   its 8 towers mostly through `towers.py` and `skybridge.ring_towers` rather than through
   straddles. The reason is geometric and I could not design around it: in D7 the Ring Viaduct
   and the Skyrail run ~35 m apart, so a box that straddles one is inside the other's band,
   and the free ground either side is a 100 m ribbon between two district streets. I handled
   it the MAP way (a straddle pierces every corridor it opens onto) and by giving the
   elevated corridors a 50 m right of way, which took the count from 0 to 2. If the lead wants
   the Liziba image to be a *feature* of the skyline rather than an incident, the Ring
   Viaduct's SE leg and the Skyrail need to be 80–120 m apart through D7 — that is a corridor
   decision, so it goes in Requests.
2. **`sky_edges` are undirected pairs in one connected component** but the graph is not
   guaranteed to be planar or to avoid crossing itself in plan; edges are clearance-tested
   individually, not against each other. Fine for steering, worth knowing for animation.
3. **A4's soft share is 30 %** — the bottom of the 30–40 % band. It is the arena with the
   least cover of its own (51 pieces, and the skybridges carry their own), so the Bresenham
   step rounds to exactly 29–30 %. Not a check failure.
10. **(r7) The cover field is half the size it was, and that is the point — but read the
   per-arena numbers before calling it thin.** 1,070 → 539 pieces. 286 of the old ones were
   exact duplicates and another ~250 stood within 6 m of a neighbour, so the *visible* field
   lost nothing; the nearest-neighbour median went **up** in every arena (A5 4.0 → 33.2 m,
   A6 0.0 → 35.6 m). A6 is the one to look at: 93 → 25 pieces, because its deck is small and
   now carries a 30 m camera sphere (V6) *and* the hive's 40 m open ground and 70 m assault
   ring on the same plate. C14 still measures 100 % there. A2 is the other: 330 → 145.
11. **(r7) The vista keep-out is a lens rule for mass, a sphere rule for cover.** A building
   under a camera is allowed (V7 stands 52 m over A3's cover and looks straight up); a
   building *above* the lens within 30 m is not. That is the reading I took of "a 30 m keep-out
   for cover and any other solid you place" — the alternative (nothing at all inside the
   sphere) would mean a 60 m pit round V3 in the middle of the Old Town terraces. Say the word
   and it is a one-line change (`vistas.camera_caps`).
4. **13 arena tiers have under 32 m of headroom** and they are the dossier's datums, not
   mine: the Knot's tiers are 16 m apart (12 m under `K2_knot_l1`/`K3_knot_l2` — less than
   the 16 m mech capsule C12 sweeps), the Foundry deck at +32 leaves 28 m over the tier-0
   foundry floor, and a canopy roof at +40 passes 4 m under the crane cab and the Knot
   flyover. Measured, printed by `arena_headroom()` and listed in Requests: fixing it means
   moving graph node z values, which is the dossier's call.
5. **D3 block interiors** still leave ragged slivers the inscribed-rectangle search rejects
   (17 of 151 lots). They cost build time, not coverage.
6. **V6** still frames past the Crystal Bridge (accepted in r2, unchanged).
7. **A6 has 9.0 % of its samples under 32 m**, all under the podium towers that carry the Sky
   Garden over its own rim — the deck has to land on something, and the towers are it.
8. **(r6) The hive firing-line test is 2.5D**, like every other sight test here: a ray is blocked
   only where its own z crosses a box. It also assumes the pods sit on the trunk's surface at the
   rig's `POD_HEIGHT` (18 m) and `TRUNK_RADIUS`; if monster-assets moves the pods to model sockets
   the band is unchanged (12/30/48 m covers 10–55 m) but the exact rays move. The trunk is
   modelled as a solid, so far-side pods are correctly unreachable from the near side.
9. **(r6) `hive_a2` moved 48 m SE of the dossier's own position** (-470,-40 → -440,-94): every
   site in A2 with 40 m of the K3 plate under it sits inside 20 m of the plate a graph node
   stands on (K4 at +56, K5 at +80), and the well may not eat a node's platform. The chosen
   site is the one with the least of that overlap and the fewest square metres to cut. The tier
   is unchanged (+32, node K3's own datum), so no graph or connector moved.


## Tuning choices
- Viaduct/rail-through: hole margin 4 m, clear 40 m (viaduct) / 32 m (rail), stations every
  48 m, box 48–88 m along × 96–200 m across, slid ±26 m along and ±46 m across, and clipped
  to the buildable envelope when it overhangs a kerb. TALL_SHARE 0.5, ring cap 240 m.
- Carrier planting: a bearing sweep outward from each deck (0.70–2.41 × the deck's reach,
  32 bearings), footprint 64/72/56 m; A6's own arena is a keep-out for everything *except* its
  carriers, which may not touch the plate.
- D7 ring: 8 towers 128–240 m, 3 of them ≥ 200 m; a ring member may be raised from C to D
  band, slenderness 7× the narrow side (MAP sets no rule for the D7 band).
- Overhead cover: arena reach 100 m, canopy chunk 64 m every 118 m, columns at 48 m; a canopy
  over arena ground sits at +40 (C13 wants 32 m under it), elsewhere at +32.
- Sockets (r5): fight tier = the arena's `main_tier` surface; wall clear 16 m (12/8 m only if
  a tier is too small, and it prints when that happens); air clear 16 m; free floor 12 m;
  nearest solid 8 m; separation 56/40/28 m; candidates on a 12 m lattice swept twice, rim
  first; sites reserved before the cover and re-checked after everything else is placed.
- Cover (r4): one surface per walkable floor inside the outline (ground minus the arena's own
  lower tiers, plus every deck over 1,500 m² and every canopy roof); Poisson at the arena's
  spacing, 28 m on a canopy roof; top-up grid 24 m, three passes, and a blocked grid point
  searches outward 16/24/32/44/56/68 m in 8 directions before it gives up.
- Cover (r7): **MIN_GAP 6 m** between any two pieces on one surface (z band ±1 m), the search
  falls back to `26x28x24` then `20x20x20` when the drawn box does not fit the gap, one top-up
  only, and a carrier tower's footprint is a permanent keep-out. Keep-outs are now z-banded
  where they have to be: the **30 m vista camera sphere** (cover may not enter it at all;
  mass may not rise above `pos_z - 2` inside it; a slab within 6 m under the lens is the
  floor, and a landmark is the camera's own set piece).
- The Crown's open zone (r4): rim bands 30 m wide on each `rim_steps` radius (104/126/150), a
  40 m band on the 40 m core, 18° wedges on the four fins; cover spacing 44 m, low only.
- A1's container stacks: 4 pieces, 24–32 m tall, 26–34 m square, ≥ 105 m apart, never soft.
- Sky graph: levels 80/112/144/176/208/240, grid 118 m, node clear 12 m, edge clear 8 m, hop
  ≤ 205 m, prefer the 144 m band; a district under 24 nodes gets an offset pass at 73 m.
- D7 streets: no avenue of its own, streets every 280 m — a tower district needs blocks, and
  the old 140 m grid left 3.5 ha buildable out of 15.
- Old Town: terrace lot 26 × 56 m, stair-alley 24 m every 60–90 m, D3 footprint inset to ±688.
- Hive spires (r6): open ground 40 m, clear air 64 m, well cut 4 m wider than the ground; pod
  band 12/30/48 m on four bearings; firing grid = flow's own (8 bearings × 70/100/140 m ×
  +8/+30 m), gate 8 clear positions per pod; approach ring 40–130 m on the tier, 60° sectors,
  gate 3. Site search: 12 m lattice, disc inside both the arena and the tier surface, scored
  (routes met, node-plate overlap, deck to cut, distance from the dossier's position), top 8
  tried in the late repair. Node plate: 20 m, falling back to 34 m if a node would be left with
  under 10 m of deck. Lane repair: at most 24 pieces flattened to 8 m; cover recovery re-checks
  C14's 60 m on a 24 m grid outside the 70 m assault ring only.

## Requests (r8 — read these before city-build's round)
1. **city-build — the `openings` field (MAP §3, additive).** Every deck and every viaduct, rail
   and tunnel now carries an optional `openings` list:
   `{"poly": [[x,y], ...], "for": ["con_..."], "clear_m": 24.0}` — a plan polygon. Your
   `kit/decks.py::_parapet` (L18-30) walls EVERY rim today: skip a rim segment whose midpoint
   falls inside any opening polygon. Same rule for `kit/corridors.py`'s edge barriers
   (`solids_from_path`, L110) and a tunnel's lining walls. 59 openings on decks, plus the ones
   on corridors. `route3d._openings` is the reference implementation.
2. **city-build — `holes` on corridors, tunnels and buildings.** A viaduct or rail slab now
   carries `holes` (bare plan rings, same shape as a deck's) where an off-ramp or a jump leaves
   it, and a tunnel carries `holes` for its roof. `kit/corridors.py::_ribbon` must cut them.
   Buildings keep the MAP §3 v2 record (`polygon`/`z`/`height`); `route3d.building_solids` is
   the reference (a hole is cut only over its own z band).
3. **city-build — the span truss must follow the holes.** `kit/decks.py::_truss` (L101) is the
   polygon's bounding box with no holes, so a light well cut for a route is a hole in the slab
   with a ceiling 3 m under it. That is the z 33 ceiling the r15 verifier wedged under at the
   +40 canopies. Cut the truss with the deck's `holes` too.
4. **city-build — three landmark openings this round cannot make.** Each is one collider:
   * the **Stilt Pagoda's base tier** (`landmarks.py::pagoda` L151-172, 53.8 m wide, z 32-46):
     node O4 stands inside it with 13.7 m of headroom, so `con_O4_O5_stairs` cannot start. Open
     it on the stair's side. The stair itself is generated, climbs outside every tier and lands
     on the crown rim.
   * the **reactor stack** at (600, -80): `con_A5_W5_vent` has nowhere to stand that is both off
     the stack and on `W5_stack_perch` (x 574-626). Either widen the perch or move the stack.
   * **Crown rib j = 2** over the S3n shaft and the S4 pad — already yours (r11 item 3); my sweep
     exempts `con_S3n_S4_lift` and `con_S4_B1_vcat` with a pointer.
   The H3 crane cab (yours, r11) is exempt the same way for `con_A1_H3_stairs`.
5. **city-build / traversal — new connector params.** `params.shaft` `[x, y]` is where a lift,
   vent or vcat column is really built (default: the `from` node) — `kit/connectors.py::_shaft`
   must read it, and so must the crust cut (`kit/terrain.py::ground_cuts`). `params.take_off`
   and `params.land_at` are the same for an edgejump's two ends. `params.walk_m` is how far the
   pad is from its node. 13 shafts and 3 take-offs are placed this round.
6. **city-build — `usable: false`.** `con_B1_A3_lift` carries it (your r11 decision) with
   `unusable_why`; every stage and every check skips it.
7. **flow / trailer — the spires moved** (conflict map E7): `hive_a2` 125 m to (-440, 14, +32)
   and `hive_a6` 27 m to (-72, -442, +144). `hive_a5` is unchanged. flow's E2E stands and the
   trailer's A6 stage both need re-running after city-build rebuilds.
8. **lead — `docs/MAP.md` §3** needs the `openings` line (granted at dispatch) and the
   `holes`-on-corridors line; both are spelled out in Requests 1 and 2.
9. **lead — the layout is NOT PASSING this round** (FAIL 56). The three items above (Knot,
   four shaft tops, ten edgejumps) are the remaining work; they are geometry, not machinery.

## Requests (earlier rounds, still open)
1. **Corridor decision (issue 1)**: to make viaduct/rail-through a skyline feature rather than
   an incident, the Ring Viaduct SE leg (V2–V3–V4) and the Skyrail (F6–S3s / F6–W4) need to
   run 80–120 m apart through D7 instead of ~35 m. With that, D7 can carry 6–8 Liziba towers
   instead of 2. Everything else in r3 is done without it.
2. **Lead — C13 vs the dossier's arena datums (issue 4).** C13 asks for 32 m of headroom under
   anything inside an arena polygon and samples in 2D, but the graph puts the Knot's tiers
   16 m apart (12 m clear — less than the 16 m capsule C12 sweeps) and the Foundry's L2 deck
   at +32 (28 m clear over its own tier 0). I can only move what I own: the canopies are now at
   +40 and everything I generate clears 32 m. Three ways out, all yours: (a) accept it and let
   C13's 5 % tolerance carry the 2.1 % I measured, (b) change the graph's arena node z values
   (K2 16 → 24, K3 32 → 48, W3 32 → 40) and I regenerate, or (c) exempt an arena's own tier
   decks from C13 the way `under_clearance` already does. My measurement says (a) passes today.
3. **city-build — C14 needs the Crown exempted.** `checks.gd` C14 gates on
   `worst_cover >= 0.999` over all arenas; the Crown is now an open boss arena by your own note
   (low cover on the rim steps, the fins and the core only), so it reports 0 % full cover and
   C14 cannot pass. `layout.arenas[B].open_cover = true` marks it — please skip that arena (or
   gate it on its own rule: the middle ring must be *empty*).
4. **city-build — new r4 fields** (all additive; `meta.version` stays 2, `meta.revision` = 4):
   * buildings: `D5_block9` now declares `through` (7 corridor ids) and `holes` in the MAP §3
     v2 shape — one opening per corridor, `z`/`clear` = 40 m over the Ring Viaduct, 32 m over
     the plateau roads and the rail. `derived_holes` should now find nothing left to derive
     for Block 9;
   * decks: `deck_block9_platform` (+80, inside the rail hole, `platform.serves` = both rails,
     `supported_by: ["D5_block9"]`) — the station the Skyrail terminates on;
   * rails: `terminus: {deck, node}` on `rail_W4_M5` and `rail_M5_S3e`;
   * decks: `over_arena` on a canopy, and 37 of them are at `z: 40` (not 32) for C13;
   * arenas: `main_tier`, `open_cover` (B) and `cover[].kind` ("container_stack" on A1's four
     24–28 m towers — they are meant to read as stacked containers, not plain boxes);
   * `meta.r4` names the four numbers this round turned on.
5. **city-build — new r5 socket fields** (additive again; `meta.version` 2, `meta.revision` 5).
   `arenas[].spawn_sockets[]` keeps MAP §3's `id`/`pos`/`kind` and adds, per socket:
   `surface_z` (the fight tier it stands on), `wall_clear`, `air_clear`, `floor_clear`,
   `min_separation` — all metres, all the values the socket was placed with. New
   `arenas[].fight_tier` is the z every socket of that arena stands on (= `main_tier`).
   32 sockets in total, 3–6 per arena, ids `<arena>_sp1…`. The rule behind them: 16 m off any
   wall, 16 m of clear air, 12 m of free floor, no collider within 8 m, and the same navmesh
   island as the arena centre — so a 4 m-radius agent can spawn and walk in. Please measure
   reachability against the baked navmesh; my island test is 2.5D (see Known issues 0).
   Arena cover also moved (the r5 top-up fix gave the canyon skybridges their own cover:
   756 → 803 pieces, A4's C14 proxy 99.5 % → 100 %).
6. **city-build — rebuild notes.** The r3 `sky_waypoints`/`sky_edges`, `quarter`, `straddles`,
   `carries`, `holes[].corridor` and `column_spacing` fields are unchanged; the graph is
   untouched, so only the layout side of your build needs to re-run. Buildings/decks/anchors
   shifted slightly this round (the socket stage no longer draws from the shared RNG, so every
   later stage re-rolled): 392 buildings, 81 decks, 91 anchors, 227 sky waypoints.
7. **`data/vistas.json` V6** (unchanged): the Crystal Bridge crosses the Sky Garden -> Spire
   ray at 193 m; the canyon walls either side are now 120 m. Say if you want it clean instead.
8. **Lead — r6 decision to confirm: C14 yields inside a hive's 70 m assault ring.** A pod 12 m
   up a trunk is only shootable if the lanes are clear out to where the player stands, and flow's
   nearest candidate is 70 m out; C14 asks for a 20 m piece within 60 m of the same ground. I
   resolved it the way r4's connector keep-clear was resolved: inside the ring **on the spire's
   own tier** the cover rule is not applied, the validator prints how many samples that is (96
   this run), and the cover is rebuilt outside the ring. If you would rather have the cover and
   a lower pod count, say so — the constant is `hive_rule.ASSAULT_R` and everything else follows.
9. **flow — the r3 blocker is fixed, please re-run the E2E.** All three spires now have open
   ground, open sky and ≥ 8 clear firing positions per pod on your own 48-candidate grid
   (`_firing_spot`). `hive_a2` moved 48 m to (-440,-94,+32) and `hive_a5`/`hive_a6` to
   (464,-160,+80) / (-48,-430,+144); the tiers are unchanged (K3/W4/the Sky Garden). The bot's
   ray starts at the mech's muzzle and the trunk is a 26 m cylinder, so a pod on the far side of
   the trunk is still correctly unreachable from the near side — that is by design, not a bug.
10. **city-build — new r6 fields** (additive again; `meta.version` 2, `meta.revision` 6):
   * `hives[]` gained `tier`, `open_r` (40 m) and `assault_r` (70 m) — keep props, decals and
     the infection field off that disc;
   * decks gained `open_for: ["hive_a2"]` on the four plates its light well was cut through
     (`K4_knot_flyover`, `K5_knot_crown` + its island, `canopy_st_K1_A3_1`) — the polygon is the
     cut plate, so nothing else is needed to build it;
   * `arenas[].cover[]` gained `kind: "rubble"` on the pieces flattened to 8 m in a firing lane;
   * `meta.r6` names the six numbers (open ground, clear air, pod band, positions, routes, wells).
   Cover count is up (803 → 1,070) because the hive keep-outs re-rolled the shared RNG and the
   late top-up refilled every surface to C14; buildings 391, decks 77, anchors 93, sockets 32.
11. **city-kit / city-art — the r7 cover field has landed, regenerate your rows.** The layout
   is rewritten (`meta.revision` 7, md5 `cf76d464baa87396b92c6a3eb9898467`). Cover ids are
   `<arena>#<index>` in layout order, so **every id changed**: 1,070 → **539** pieces, and the
   per-arena counts are now A1 80, A2 145, A3 88, A4 51, A5 131, A6 25, B 19. A third of the
   old rows were invisible duplicates stacked on 82 shared centres, which is what the lead's
   r7 review was about — none of them are left (539 pieces on 539 distinct centres, 0 pairs
   closer than 6 m). The pieces themselves are unchanged in shape (`center`/`size`/`soft`/
   `kind`), so the kit fitting code needs no change, only a re-run.
12. **city-build — rebuild notes for r7.** `meta.version` stays 2, `meta.revision` 7; `meta.r7`
   names the four numbers this round turned on (`cover_min_gap_m` 6, `cover_surface_band_m` 1,
   `vista_camera_keep_out_m` 30, `vista_cameras`). The graph, the corridors and the connectors
   are untouched; buildings 392, decks 77, anchors 93, sockets 32, hives 3 (`hive_a2` moved
   27 m to (-464,-106,+32), tiers unchanged). Two things you can now rely on that you could
   not before: **no two cover colliders on a surface are within 6 m** (so a 16 m mech fits
   between any two of them), and **no solid stands in a 30 m sphere round any vista camera**
   (`vistas.in_sphere` is enforced as part of L8).
13. **Lead — one judgement call to confirm (Known issues 11).** For cover the 30 m camera
   keep-out is the whole sphere; for buildings, decks and columns it is "nothing may rise
   above the lens within 30 m", because the strict reading would delete the Old Town fabric
   V3 stands in. If you want the strict sphere everywhere, it is one function
   (`vistas.camera_caps`) and a rebuild.
