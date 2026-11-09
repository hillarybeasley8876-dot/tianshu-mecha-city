# city-build status

## Plan (files I own)

```
blender/city/
  build_city.py    orchestrator: JSON -> scene -> tiles -> glb + layout.json, prints counts/time
  assemble.py      the assembly itself (terrain, buildings, structures) for one skin setting;
                   shared by build_city.py and probe_skin.py so the diff cannot drift
  probe_skin.py    collision diff: assemble twice (skinned / --blockout), compare every bucket
  layout.py        load + normalise data/map/city_layout.json, 2D helpers
  tiles.py         200 m tiles, <= 60 m chunks, merged per material role, per-tile glb export
  markers.py       game/world/city/layout.json: markers, arenas, anchors, hives, vistas,
                   nav links, walk edges, sky graph, prop slots, and (r9) the `floors` /
                   `blocks` rows the C18 top-face gate samples
  kit/roles.py     the 12 role materials (names are the city-art contract) + district palettes
  kit/builder.py   Kit: per-role bmesh accumulator, explicit-winding primitives, window UVs
  kit/solid.py     collision / occluder / PROPS proxies, grid decomposition for holes
  kit/boolop.py    exact boolean for the ground crust (overlapping cuts)
  kit/buildings.py 10 archetypes on the 4 m module + one shared facade-detailing pass
  kit/passage.py   corridor-through: derived holes + the lit tunnel dressing (lead r3)
  kit/corridors.py streets, viaducts (piers/capitals), skyrail, tunnels
  kit/decks.py     deck slabs, parapets, columns, trusses, the Crown
  kit/terrain.py   escarpment, plateau, canal, docks, boundary wall
  kit/connectors.py ramps, stairs, lifts, vcat, vent, lcat, take-off lips
  kit/landmarks.py Knot, cranes, stacks, Block 9, Crystal Bridge, pagoda, hologram
  kit/bridge.py    the Crystal Bridge as a glazed faceted arch: octagonal mc_glass tube swept
                   along a sin(pi t) arch, bronze mullion rings + 8 facet ribs, diagrid struts
  kit/spire.py    the Spire: trumpeted shaft, finned corners, stepped corbel rings, 10 Crown ribs
                   and the radial Crown soffit
  kit/props.py     arena cover (hard on WORLD, soft/destructible on PROPS), skyline ring, hive sockets
  preview_part.py  build ONE kit part to tmp/city-build/part_<x>.glb for tools/blender.sh preview
  probe_crust.py   ground-crust area/connectivity probe (the evidence for the scanfill fix)
  skin.py          kit skin mode: data/map/kit_assign.json -> which render meshes are dropped
                   (buildings, deck edges, whole decks, viaducts, arena cover, far-LOD tiles)
game/world/
  city.tscn  city.gd                 world root: tiles, HLOD, markers, crown rim, nav, sky graph
  city/city_nav.gd                   CityNav: one map per agent class + NavigationLink3D per edge
  city/city_markers.gd               markers, spawn zones, arenas, vistas, the breakable Crown rim
  city/tools/bake_nav.gd             offline navmesh bake (headless)
  city/tools/checks.gd               C12-C18 + C15b
  city/tools/checks_floor.gd         C18: every walkable floor has a RENDERED up-facing face
                                     at its own z, 4 m grid (lead r9)
  city/tools/probe_floor.gd          every rendered up-facing face in a vertical column, named
  city/tools/nav_report.gd           nav sync time, link gating, gameplay reachability
  city/tools/nav_probe.gd            why a socket is off-mesh: the floor under it, per class
  city/tools/vista_solver.gd         lead r3 metrics: solve the vista cameras -> vistas.proposed.json
  city/tools/skin_probe.gd           kit skin regression: a skinned building keeps its collision
  city/tests/test_city.gd            contract test (105 checks)
  city/tests/flight.json             60 s flight timeline (Ring Viaduct -> Skyrail)
  city/tiles/tile_*.glb  city/skyline.glb  city/nav/*.res  city/layout.json   (generated)
tools/city/  bake_nav.sh  checks.sh  nav_report.sh  nav_probe.sh  vistas.sh
tools/city/floor_probe.py   why is this arena cover piece in mid-air? (layout-side diagnosis)
tools/map/floors.py         the floor set as the RENDER has it + `cut_ground` (city-layout's
                            tool, edited under the lead's r9 brief)
tools/map/cuts.py           the r9 lot-over-a-ground-cut filter (lead r10 split)
tools/map/overrides.py      data/map/overrides.json applied to a built layout (lead r10 split)
tools/map/{lots,corridors,straddle,props,zones}.py
                            gained the helpers `build_layout.py` used to keep (lead r10 split)
```

## Decisions
- **Tiles 200 m, chunks 60 m**: one object per (chunk, material role) so a chunk is 1-4 draw
  calls, not one per surface. Render pieces are bisect-split (open cut faces are hidden inside
  the abutting union); collision is rebuilt per piece as closed boxes, never a cut render mesh.
- **Holes without booleans**: building holes are rects, so masses and collision use exact grid
  decomposition. The ground crust's cuts overlap, so that one slab uses Blender's exact boolean.
  A slab hole that reaches the outer boundary is a NOTCH, not a hole: scanfill returns a partial
  triangulation and the geometry silently shrinks (this cost the crust 80 % of its area). The
  plateau therefore goes through the boolean as a cutter, and `Kit.slab` clips any escaping hole
  to the outer bbox and says so. `blender/city/probe_crust.py` is the regression check.
- **Navigation**: one region per agent class and `map_set_use_edge_connections(map, false)`. The
  edge-connection margin pass tests every PAIR of free edges and, with one region per map, joins
  nothing (reviews/city-build-nav.md). Chunking the bake would need that pass back on, and it
  measured no better, so the map stays whole.
- **Cell sizes are godot-tech 3.1's** (small 0.5 / medium 1.0 / large 1.5, each a whole divisor
  of its agent radius) and identical in `city_nav.gd` and `bake_nav.gd`, so the map and its
  meshes agree and no `navmesh_cell_size_mismatch` fires.
- **Crown rim is Godot-side** (CONTRACTS 6): `kit/decks.py` leaves the outermost rim step's
  parapet out and `city.gd` builds 16 breakable `StaticBody3D` segments from `layout.json`.
- **HLOD**: each tile also exports `t<i>_<j>_hlod` — its own collision mass as one cheap mesh.
  `city.gd` sets detail chunks `visibility_range_end = 450` and the proxy `begin = 430`.
  That took V1 from 2 645 draws / 59 fps to 964 draws / 60 fps. **Landmark chunks are exempt**
  (r8 item 1): they are built into their own Kit/Solids, exported with an `lm_` name prefix, get
  `visibility_range_end = 2 400`, and their collision is bucketed separately so it never reaches
  `hlod_meshes()` — at 561 m the Spire was being drawn as its own HLOD box.
- **PROPS layer for decoration**: rooftop machinery is exported as `*_props-colonly` and put on
  `Layers.PROPS`, so it still blocks shots and bodies but the navmesh bake (WORLD only) ignores it.
  **Destructible arena cover joined it in r3** for the same reason and with the same trade: it is
  going to be blown away mid-fight, so the navmesh should not treat it as permanent. Hard cover
  stays on WORLD. C14's cover rays use `MASK_SIGHT` (WORLD|PROPS) so the cover number still counts
  the soft pieces.
- **Nav links start disabled and are gated per class** (lead r3): `snap_links()` enables a link
  only when both ends land within 4 m of that class's navmesh. An enabled link with an off-mesh end
  is worse than no link — godot-tech 3.3 hangs the end on whatever polygon is nearest, so queries
  start outside the reachable set and Godot logs `_query_task_build_path_corridor`. Gating them
  took `run main.tscn 20` from 7 of those errors to 0.
- **No image textures in the blockout** — flat PBR role colours with metre UVs, so tiles export
  as .glb. `mc_window` faces get U = 0..cells (one unit per 4 m cell) and V = 0..1, so each
  window cell is UV 0..1 for city-art's emissive shader.
- **Chamfered boxes by default** (r8, reviews/look/city-build.md item 2): `Kit.box` cuts the 12
  edges and 8 corners back by 1.5 % of the smallest side, clamped 0.1–0.6 m, for every element
  whose largest side is under 40 m. 24 verts / 26 flat faces instead of 8 / 6. Winding is decided
  per face against the outward direction rather than by a `recalc_face_normals` pass, because a
  Kit holds tens of thousands of boxes. `build_city.py --no-chamfer` is the A/B switch.
- `tools/city/*.sh` are wrappers: `tools/godot.sh` only takes `res://` paths and is lead-owned,
  so the GDScript lives under `game/world/city/tools/` (mine) and the wrappers call it.
- **A fix that touches the layout must not touch the rng stream** (lead r9, the hard-won one).
  `build_layout.py` threads ONE `random.Random` through every stage, so anything that changes how
  many draws a stage makes re-rolls everything after it. Measured: putting the connector trenches
  into the block mask reshaped every block `fabric` cuts and replaced **334 of the 354 buildings
  the user had already seen**. The rule I now follow: a late correction is a FILTER (drop rows
  from a list, draw nothing, renumber nothing) placed after the last stage that both draws and
  reads the list it would have changed. `settle_cover` and `drop_over_cut` are both built this
  way, and `settle_cover` asserts its own idempotence in `build_layout` so a second call is a
  no-op rather than a silent drift.
- **The gate reads the RENDER, everything else reads collision** (r9). `ArtSurfaces` (city-art's)
  is the one index of what the player sees, and C18 queries its `GROUND` kind only. That is not a
  second opinion of the world — it is the same class the load-time settle pass and `float_audit`
  use, so the gate cannot measure a city nobody ships.

## Done
### Round 1 (structure, reviewed PASS)
1. **Blender pipeline** rebuilds the whole city from `data/map/city_layout.json` in ~36 s;
   `--district D5` rebuilds one district; a full run clears stale tiles first.
2. **Kit**: 10 archetypes on a 4 m module with base/shaft/crown, window bands, fins, floor bands,
   parapets, rooftop machinery + prop slots; decks with parapets, soffit beams, columns and span
   trusses; escarpment with terraces and lips; canal, docks, plateau; the Knot's loops and helices.
3. **Corridor-through passages (lead r3)** (`kit/passage.py`): lit throat, cyan soffit strips,
   bronze portal frames at both mouths. `captures/city_pass_P1..P4.jpg`.
4. **Godot world**: tiles, HLOD, every CONTRACTS 7 marker, sky graph, `Game.mark_world_built()`.

### Round 2
5. **Navigation, per reviews/city-build-nav.md** — all six items:
   - `map_set_use_edge_connections(map, false)` before `map_set_active`, async iterations kept on.
     **The three maps are queryable 19–41 ms after the world is built** (was reported as
     15 s / 40 s / 65 s — those were frame counts under `--fixed-fps 120`, and the build cost was
     the O(F^2) free-edge pairing pass, not the map size).
   - `is_synced()` now needs `map_get_iteration_id > 0` AND a baked polygon centre to come back
     from `map_get_closest_point` within 0.5 m, so it fires on the first real-path frame.
   - `checks.gd` and `city.gd` wait on `Time.get_ticks_msec()`, never frames/120.
   - the three map RIDs are freed in `CityNav._exit_tree()`.
   - bakes re-cut at godot-tech 3.1 cell sizes (0.5 / 1.0 / 1.5), `z_hi` per class is now actually
     applied (it read the module constant, so small's +96 cap never happened), and connected
     components under 3 polygons are dropped with the island count reported.
   - `CityNav.snap_links()` pulls link ends onto the navmesh and reports attachment per class.
6. **The ground crust was 80 % missing** — the real cause of the fragmented navmesh, and of a
   lot of C12/C13/C17. The plateau runs to the map edge, so as a `base_hole` it is a NOTCH, and
   `Kit.slab`'s scanfill returned a partial triangulation: **173 642 m2 of crust instead of
   1 190 410**. Passing it to the exact boolean as a cutter gives 921 824 m2 (expected 890 233,
   the difference is overlapping cutters). Largest navmesh island 5.7 % -> 11.5 % (medium),
   large-agent link attachment 58 % -> 79 %, C14 sightlines 0.0 % everywhere (were up to 8.3 %).
   `Kit.slab` now clips any escaping hole to the outer bbox and prints it; that caught a second
   case, `K4_knot_flyover`, whose hole pokes 29 m outside its own deck.
7. **Spire silhouette (lead r2 3)**: no more mushroom. A tapered 16-facet shaft (Ø 88 -> 56)
   with 16 corner fins, emissive strips between them and a 16 m bronze band rhythm; the collar
   (+80) and roof (+160) rings carried on 5- and 4-step cantilevered corbels; the Crown disc
   (+224) carried on **10 radiating brackets, 4 stepped layers each, splaying from +168 out to
   r 140** against a 150 m rim; a lit edge on every ring. Same data contract. New
   `blender/city/preview_part.py` renders one kit part on its own for `tools/blender.sh preview`,
   which is how the silhouette was judged before the full rebuild.
8. **Art integration (CONTRACTS 7)**: `world/city.tscn` instances
   `res://world/art/environment.tscn` and owns no sky/sun/WorldEnvironment; `--blockout` keeps a
   flat sky + sun for my own geometry captures. city-art's `mc_*` materials arrive on the tiles
   (verified in `captures/city_spire_r2_S1.jpg`).
9. **Export-safe asset discovery (lead, packaging)**: tiles via
   `ResourceLoader.list_directory(TILE_DIR)`, not `DirAccess`; navmesh chunks the same way, so
   `city_nav.gd` no longer depends on the `index.json` side-car shipping at all.
10. **Crown rim (CONTRACTS 6)**: 16 `StaticBody3D` segments in group `&"crown_rim_segment"` with
    meta `angle_deg`, built by `city.gd` from a new `crown_rim` block in `layout.json`;
    `kit/decks.py` leaves the outermost rim step's parapet out so nothing is duplicated.
11. **C15 re-measured** as the lead specified: any of crown +224 / Spire top +360 / tether +600
    with a clear ray, gate 60 %, L1 streets and L2+ reported separately.
12. **C14 exempts `open_cover` arenas** (the Crown) from the cover half of the check; the flag
    is exported through `layout.json`.
13. **Vista solver (lead r2 1)**: `game/world/city/tools/vista_solver.gd` + `tools/city/vistas.sh`.
    Keeps the subject, the ±20 m band and a ±30° bearing; searches 7 rings x 16 bearings x
    7 heights inside 80 m for a camera outside geometry, with an opening toward the subject and
    under 30 % of a 16x9 ray grid blocked within 60 m. Writes `data/vistas.proposed.json` (same
    schema, plus `ok` / `moved_m` / `near_clutter` / `subject_clear_m`) and
    `captures/city_V1..V8_proposed.jpg`. **All 8 now meet the gate; the moves are 8–69 m.**

### Round 3
14. **Spire, "still a disc on a stick" (lead r3 1)** — `kit/spire.py` rewritten around the key art
    (`art/concept/keyart/v8_crown-1.png`), four changes:
    - **The shaft is a trumpet.** `SHAFT` became two profiles: `TRUMPET` tapers from Ø 88 at +26
      to a **waist of Ø 68 at +110** and then flares out to a **Ø 120 mouth at +218**, right under
      the Crown soffit; `NECK` pulls back to Ø 72 to pass through the Crown's 40 m hole and the
      `core` mass, then tapers to the needle at +360. The 16 fins deepen from 4.5 m to 9.5 m as
      the shaft flares, so at the top they read as blades carrying the disc.
    - **The 10 brackets are massive ribs now.** They leave the shaft at its **+120 waist** (was
      +168) as 24 m wide blades and step out in **8 layers** (was 4) to **r 152**, 2 m past the
      150 m rim so their ends are visible at the edge. Each step carries a lit `mc_up_accent`
      strip along its outer soffit corner.
    - **The Crown's underside is dressed**: `_crown_soffit()` adds 20 radial `mc_metal` beams on
      the half-pitch between the ribs, a lit strip under each, three concentric lit rings
      (r 72/106/140) and a lit lip at the hole. It is structure and light from any angle below,
      never a black plate.
    - **The bbox beam grid is gone from the Crown.** `decks.py` used the rectangular `_soffit()`
      on every raised deck, which on a disc **pokes out past the rim** — those were the loose tabs
      floating around the Crown edge in the r2 shots. `kind == "crown"` now skips it and
      `kit/spire.py` does the soffit radially.
    Captures: `captures/spire_r3S1..S4.jpg` (mid-distance, the framing the lead called out) plus
    `captures/spire_r3S1b.jpg` in `--blockout`, where the ten ribs and the flare read cleanest.
15. **The black blob under the Crown was not mine.** It is absent from every r3 frame and absent
    from `--blockout` (no art environment at all), so it was environment-side: either city-art's
    volumetric fog or one of the four `smoke_plume` slots. All four of my plume slots are at the
    reactor stacks (x 540–650), none is near the Spire — see Requests 5.
16. **Navigation for gameplay (lead r3 3)**:
    - **Links are gated per class and start disabled.** `NavigationLink3D.enabled = false` at
      creation; `CityNav.snap_links()` enables a link only when **both** ends land within
      `SNAP_GATE = 4 m` of that class's navmesh, and reports every link left off with both
      distances. Enabled: **small 18/48, medium 20/48, large 6/48** (100 ends off).
    - **`run res://main.tscn 20` now logs 0 `path_corridor` errors** — 0 errors over 4 runs, was 7.
      An enabled link with an off-mesh end is what raised them (godot-tech 3.3 hangs the end on
      whatever polygon is nearest, so queries start outside the reachable set).
    - **Destructible arena cover moved to the PROPS layer** (`kit/props.py`). Arena cover runs
      41–64 % of a tier's footprint, and as WORLD geometry it left a 4 m-radius agent no connected
      free space (medium arena centres 16 m off-mesh). Soft cover is going to be blown away
      mid-fight, so the navmesh bake (WORLD only) now ignores it while it still stops shots,
      bodies and sightlines (`MASK_SIGHT` is WORLD|PROPS, and C14's cover rays were switched to it
      so the cover number stays honest). Hard cover stays on WORLD.
    - **`z_hi` measured, not assumed** (lead r9's "report islands before/after"): raising small
      from +96 to +240 **shrinks** the ground island from 16.8 % to 13.9 % of the map and its
      extent from z 647 to z 339, and socket→arena reachability **falls from 81 % to 75 %**.
      Medium at +200 barely moves (17.8 % → 18.1 %). A taller rasterisation box costs more ground
      than the extra decks are worth, so the caps stay as they were. Recorded in `bake_nav.gd`.
    - **Islands before/after** (lead r9): **2 005 / 856 / 260 → 1 735 / 754 / 256**, biggest
      island **14.0 / 11.5 / 10.0 % → 16.8 / 17.8 / 14.4 %** (small/medium/large). One region per
      class was already true (`CHUNKS = 1`), so the chunk-seam theory is excluded; the crust is
      the largest island and spans x -692..693, the rest are roofs, decks and terraces.
    - **The gameplay metric** (`nav_report.sh`, per the lead): every spawn socket → its own arena
      centre. **small 81 % · medium 62 % · large 41 %** against the 95 % target; arena→arena for
      medium **14 %**. Failing sockets are listed individually with both off-mesh distances.
    - **New `tools/city/nav_probe.sh`** answers *why* a socket is off-mesh: it casts down at every
      socket and prints the floor (collider, height, normal) beside the off-mesh distance per
      class. **Every socket has a floor** — there are no geometry holes; the failures are agent
      box (16 m headroom under a deck), cover density, or a socket that is not on the tier its
      arena polygon implies. That is layout data — see Requests 1–3.
17. **Vistas V4/V5/V7 re-solved to the lead's stricter metrics (lead r3 2)** —
    `vista_solver.gd` re-cut: rays through the **upper half** of the frustum hitting geometry
    within **120 m** must be **≤ 15 %** (no ceilings), the subject must cover **≥ 4 %** of the
    frame's solid angle and be unobstructed (9 rays, centre ray mandatory, ≥ 55 % reaching the last
    quarter of the way), the camera may move **150 m** and rise **60 m**, bearing within 35°.
    Among candidates that pass every gate the **shortest move wins**, so a declared position that
    already works is kept. The lead's three hints are evaluated as candidates and their scores
    printed. Writes `data/vistas.proposed.json` + `captures/city_V1..V8_proposed.jpg`.
    **V1/V2/V3/V6/V8 pass; V4/V5/V7 do not** — see Known issues 5.
18. **C15b added** — the lead's r2 decision that replaces the global C15 gate: every arena centre
    at its **top tier** must see the Spire top (+360) or the tether (+600). **4 of 7 pass.**
19. **The flat wall in every vista was my HLOD proxy (city-art r3)** — the biggest visual bug of
    the round. The C16 no-fly curtain is four **1 400 × 260 m** collision cards with no render mesh
    of their own, and `hlod_meshes()` copied each tile's whole collision mass into its distant
    stand-in — so `t-1_3_hlod` was a planar 0 × 260 × 1 406 m card that filled the frame from every
    camera beyond the 430 m swap. Fix: `Solids.curtain_box()` writes to a fourth accumulator that
    `tiles.py` buckets separately; the export merges it back into the same `-colonly` object (so
    C16 collision is unchanged and still PASSes) but `hlod_meshes()` never sees it. Verified in the
    .glb: `t-1_3_hlod` is now 4 verts at y 0..60 — the visible parapet only — while `t-1_3-colonly`
    still carries the 260 m curtain. **The wall is gone from all eight vista frames**, and the
    skyline ring behind it now reads as a skyline instead of a backdrop card. This also retires my
    own r3 Known issue about the ring looking like a billboard.
20. **A4's podium walls now have footprints (city-art r3)** — the escarpment retaining wall is what
    a player reads as the district podium (a continuous 32 m face with terraces on it around the A4
    megablock quarter), but it is terrain, not a building, so it has no row in the design layout and
    city-art's facade mask gives it no windows at eye level. `_escarpment()` now also records every
    wall segment and `markers.py` exports **55 of them** as `layout.json["podium_walls"]`: a rotated
    footprint in the same shape as a `buildings` row, plus `base_z`, `height` and `outward` (the
    face normal away from the plateau) so a shader knows which side is facade. Merge them into the
    mask input alongside `design["buildings"]` — see Requests 8.
21. **Crown rim profile (boss r2)** — the probe read 226/234/241/**248** m at r 0.92/0.72/0.55/0.80,
    and the non-monotonic entry was the four `fins`: they were placed at a hardcoded **r 120**,
    between the r 126 and r 104 rim steps, so their tops (z 224 + 24) stood on the walkable rim the
    boss breaks in phase 2. They now sit **outboard of the rim** at `outer_r + reach/2` (r ≈ 162),
    reading as blades radiating from the rim edge, and nothing stands on the steps. `rim_steps`
    itself was already built as authored.

### Round 4 (kit skin mode — lead PRIORITY 12:10)
22. **Kit skin mode** (`blender/city/skin.py`, new). `data/map/kit_assign.json` (city-kit) names the
    structures a Tripo model is fitted over. For every one of them the build emits **no render
    mesh** and keeps **collision, occluders, prop slots and the navmesh identical**, so gameplay is
    untouched and only what the player sees changes:
    - `Kit.muted` primitives: `MutedKit` (kit/builder.py) swallows every render write. The builders
      already write render and solids through separate objects, so handing them a `MutedKit`
      removes exactly the visible geometry — no `if skinned:` branch in any builder.
    - Row kinds: `building` (whole building), `deck_edge` / `parapet` / `railing` (deck parapet
      ring only), `deck` / `platform` (whole deck slab), `viaduct_edge` / `barrier` / `pylon`
      (viaduct barriers + piers; the drivable slab always stays).
    - `Skin.resolve(layout)` sorts railing rows onto decks or viaducts and **reports every id that
      matches nothing in the layout** instead of silently ignoring it (a silent drop leaves a
      procedural box where a kit model is standing).
    - `build_city.py --blockout` (alias `--no-skin`) ignores the file and emits everything;
      `--assign=<path>` points at another assignment file (used by my own tests).
    - The parser is deliberately tolerant (list / `assign` / `assignments` / `entries` / `rows` /
      `buildings` dict-of-rows, id under `building` / `target_id` / `structure` / `target` / `id`,
      `"hide": false` opts a row out) because the file belongs to another unit and is being
      written right now. A file that is missing or unreadable prints why and skins nothing.
23. **Deck / viaduct edges exported for railings** (`layout.json["edges"]`, 96 rows): every deck
    parapet ring (74 of 77 decks have a parapet) and both barrier polylines of every viaduct, as
    `{id, points [[x, y], ...], z, kind, closed, height, thickness, deck|viaduct}` in Blender
    metres, taken from the same helpers that build the geometry (`decks.edge_rings`,
    `corridors.viaduct_edges`) so the line and the railing can never drift apart.
24. **`layout.json["kit_skin"]`** records what was dropped (`active`, `source`, and the four id
    lists) so the Godot side knows whether the city on disk is skinned.
25. **One instancing line for city-kit** (`city.gd::_kit_placer`): `res://world/kit/kit_placer.tscn`
    is added as a child named `KitPlacer`, and `setup(city, layout)` is called when the node has it.
    It is a **dynamic load, not an `ext_resource` in `city.tscn`**: that scene is city-kit's and does
    not exist yet, and a hard reference would break the whole project's script check until it does.
    Loaded only when `kit_skin.active` (otherwise every kit model would be doubled by the box behind
    it); `--blockout` / `--no-kit` skip it and warn that the city on disk has holes.
26. **`skin_probe.gd`** (`tools/godot.sh test res://world/city/tools/skin_probe.gd`) is the regression
    test: for every skinned building it raycasts down onto the roof slot and fails if the collision
    is gone, and prints the navmesh polygon counts per class to compare against an unskinned build.
27. **`city.gd` split** (526 -> 349 lines): markers, spawn zones, arenas, vistas and the breakable
    Crown rim moved verbatim to `world/city/city_markers.gd` (a `RefCounted` helper). The nodes are
    parented exactly where they were, because other units address them by name and group.
28. **Navmesh re-baked for layout r6** — the baked `.res` files were from 03:38, before r5/r6 landed
    at 12:09, so the nav report and C13/C17 were mixing a stale navmesh with new collision.

### Round 5 (lead r7 — skin mode live, kit wave 2)
29. **The two "lost collision" roofs were never a skin regression (lead r7 1).** `D1_b003`
    (stack, breaches e/s) and `D1_b011` (slab, breach e) have a breach that reaches **above the top
    of the mass**: `D1_b003`'s `stack` top segment ends at z 30.7 and its breach runs z 28→60;
    `D1_b011`'s breach runs z 20→52 on a 52 m slab with `width` 24 on a 19.6 m face, so it takes
    the whole plan. `mass_boxes` therefore returns **no box at the segment's own top**, and the
    rooftop machinery slot was being placed in mid-air over the opening. Collision is byte-identical
    skinned vs blockout — now proven, see 30. What was wrong is the *slot*, not the collider:
    - `kit/buildings.py` now computes the **surviving roof cells** (`_roof_cells`, from the new
      `solid.mass_cells`) and only dresses those: the parapet ring is clipped to the spans where a
      roof cell still reaches that edge, the machinery lands inside a surviving cell (picked by
      area), the lit parapet line follows the cells, and the crown cornice is dropped on a cut roof
      instead of bridging the opening. A building whose whole roof is gone gets no roof dressing
      and **no slot** — which is exactly what `D1_b003`/`D1_b011` now do.
    - `solid.mass_boxes` was refactored into `mass_cells` (local plan cells) + a thin world-space
      wrapper, so the geometry and the dressing read the same decomposition.
30. **Collision diff, exact rather than sampled** (`blender/city/probe_skin.py`, new):
    `tools/blender.sh run blender/city/probe_skin.py` runs the whole assembly twice — once with
    `kit_assign.json`, once as `--blockout` — and compares every collider bucket by
    (verts, faces, closed-box volume) per material role. On the live assignment:
    **col 5 511 boxes / 65 448 499.9 m3 · occ 258 / 11 716 568.4 · props 1 173 / 5 421 127.1 ·
    curtain 4 / 8 773 440.0 — identical to the last decimal, skinned and blockout**, while the
    render falls 493 820 → 137 520 triangles. `SKIN DIFF PASS`.
31. **`skin_probe.gd` covers every skinned building (lead r7 1).** It used to stop at 24 buildings
    and only look at roof slots; it now walks `kit_skin.probe` (a footprint row per skinned
    building, exported by `markers.py`) with a 5-ray fan per building, plus **every** rooftop slot.
    Slot rays start 8 m above the slot, not 60: casting from high up found the skydeck standing
    OVER a roof (`D2_b014` read +47 m) and called somebody else's geometry a missing roof.
    **PASS: 358 / 358 footprints collide (1 790 rays), 736 / 736 slots collide, navmesh polys
    unchanged at 18 183 / 9 564 / 3 795.**
32. **`cover` rows (city-kit r1 item 1).** `kit_assign.json` may now name one arena cover piece as
    `{"kind": "cover", "arena": "A1", "index": 3, "model": ...}` (or `"id": "A1#3"` / `"A1:3"`).
    `kit/props.py::cover` hands those two render boxes (the mass and the pale cap) to a `MutedKit`
    and keeps the collider, the PROPS/WORLD layer and the `breakable_cover` slot untouched. Every
    cover piece — hard ones included — now also exports an `arena_cover` prop slot
    (`id`, `arena`, `index`, `soft`, `pos`, `size`, `yaw_deg`) so a kit model can be fitted without
    reading the design layout. Verified: 448 rows (A1+A2) drop **4 376 Godot triangles** with the
    collision fingerprint unchanged, and in the exported tile the chunk mesh
    `t1_1_c3_4_0_panel_white` (228 verts) disappears while `t1_1-colonly` keeps all 2 411.
33. **Far field (city-kit r1 item 2).** A `far_lod` row (`{"kind": "far_lod", "id": "t0_0", ...}`)
    puts a tile id in `kit_skin.far_tiles`; `city.gd::_fix_up` then **hides that tile's `_hlod`
    proxy** instead of giving it `visibility_range_begin = 430`, and prints the list. Nothing was
    hidden while the list was empty; city-kit has since written 29 rows and the city now prints
    `City: 29 of 77 HLOD proxies stand down`. Their side is live too — all 40 kit models carry a
    `far` glb and `kit_placer.gd` places the far tier, so the band past 450 m is theirs.
34. **`pieces` rows were being ignored — 100 structure rows never reached the build.** Wave 1 put
    its railings, viaduct edges, pylons and skybridges under a top-level `pieces` key, which was
    not in `skin.py::_ROW_KEYS`, so the SKIN line reported 0 and every one of those structures kept
    its procedural parapet UNDER city-kit's railing. `_ROW_KEYS` now reads `pieces`, `cover` and
    `far_lod`; `deck_full` / `skybridge` / `skydeck` are accepted as whole-deck kinds; and the
    additive kinds city-kit uses (`roof`, `street`, `market`, `pipe_rack`) are recognised and
    counted as deliberately-ignored rather than "unreadable". The live file now resolves to
    **358 buildings, 74 deck edges, 5 whole decks, 11 viaducts, 0 cover, 29 far tiles, 0 skipped,
    0 stale** (it was 353 / 0 / 0 / 0 with 5 rows skipped).
35. **Why the cover A/B looks like nothing happened — it is city-art, not the hook.** With all
    1 070 cover pieces dropped the city loses **35 776 Godot triangles** and the frames change by
    0.1–0.7 %. The reason is `game/world/art/detail/cargo_blocks.gd`: city-art draws its own cargo
    skin **2 cm proud of every cover box**, reading the rows straight from
    `data/map/city_layout.json`, so removing my box leaves their skin standing. A kit cover model
    would therefore be placed *inside* city-art's skin. See Requests 19.



### Round 6 (lead r8 — the far field, the look items, the ring)
36. **Landmarks are themselves from every vista (lead r8 1).** V2 is the Spire vista and 561 m
    from the Spire, and there the Spire was its own HLOD collision mass in the skyline shader — a
    lavender pixel-block trumpet — because `city.gd::_fix_up` gave every non-HLOD mesh
    `visibility_range_end = 450`, the landmark's own render chunks included.
    - `assemble.populate()` now builds the landmarks (and the **Crown disc**, `LANDMARK_DECKS`)
      into their **own `Kit` and `Solids`**, separate from `structures`.
    - `tiles.py::add_kit(kit, prefix="lm_")` prefixes every exported chunk name, and
      `city.gd::_fix_up` gives `lm_*` meshes `visibility_range_end = LANDMARK_END (2 400 m)`
      instead of `DETAIL_END`. **135 landmark chunks** get the long range.
    - `tiles.py::add_solids(solids, landmark=True)` buckets landmark collision into `col_lm`,
      which is merged back into the same `-colonly` object on export (so collision is byte-for-byte
      unchanged) but is **excluded from `hlod_meshes()`**, so the proxy cannot double-draw the
      landmark. Proven in the .glb: `tile_3_4` `-colonly` is **6 023 verts both before and after**,
      while `t3_4_hlod` falls from 6 004 verts / top y 360 to **2 940 verts / top y 232** — the
      Spire mass is out of the proxy and nothing else moved.
    - Landmark render cost measured at **62 682 tris of 347 928** (18 % of the city), so no extra
      far tier was added: the lead's "cheap LOD if the triangle cost is high" does not apply.
37. **The Crystal Bridge is an arch, not a fence (look item 1).** `kit/bridge.py` (new) replaces
    13 stations of 3 × 3 m metal posts and 4 × 36 m glass slabs with:
    - an **octagonal `mc_glass` tube** (R 11, ~20 m across flats over the 36 m deck) lofted along a
      `sin(pi t)` arch of the layout's own `height` (28 m), springing 13 m above the deck;
    - a **0.6 m `mc_bronze` mullion ring every 4 m** standing 0.3 m proud of the glass, and
      **eight 0.55 m bronze ribs** running the eight facet edges with end caps;
    - **two `mc_up_accent` light lines** (0.3 m) along the lower flanks;
    - **tapered diagrid struts** (1.2 m at the deck → 0.6 m at the tube) in a V every 12 m, with
      bronze node caps at the top joints, and bronze abutment blocks at both springings;
    - a **10-segment deck slab** (30 m each, so each is under the chamfer threshold and the joints
      read as expansion joints) with chamfered `mc_metal` kerbs and a lit underside;
    - the **maglev guideway inside the glass**, and the `maglev_car` slot moved with it
      (z 186 → z 211) so city-art's capsule rides inside the tube.
    Same layout envelope, same prop-slot kind, still no collision (the fence had none either, and
    a walkable deck would move the navmesh every other unit measures against).
    **15 040 tris** for the part. `captures/blender/bridge_r8_studio.jpg` (the part on its own),
    `captures/cb8b_a6.jpg` (the lead's A6 hive framing), `captures/cb8b_side.jpg` (the arch
    elevation with the Spire behind it).
38. **Every kit box is chamfered (look item 2).** `Kit.box` takes an optional `chamfer`; the
    default rule is 1.5 % of the smallest side clamped to 0.1–0.6 m, applied to every element whose
    largest side is under 40 m (`CHAMFER_MAX_SIDE`), so interiors, the 300 m bridge deck as a whole
    and the skyline ring stay raw. 24 verts / 26 flat faces instead of 8 / 6. Winding is decided
    per face by comparing the face normal against the outward direction from the box centre — a
    `recalc_face_normals` pass per box would be far too slow at this box count.
    **Triangle delta, shipped build: 264 860 → 547 308 Blender tris (+107 %), 25.4 → 58.0 MB.**
    Blockout build: 717 180 → 1 357 706. `build_city.py --no-chamfer` is the A/B switch.
    **Measured cost: none in load time** — `built in 7 723–9 426 ms` without the chamfer against
    `7 584–7 984 ms` with it, i.e. inside the machine-load noise on a box averaging load 14–22.
    A/B close-ups: `captures/cb8_chamfer_lip.jpg`, `captures/cb8_chamfer_a1b.jpg` (chamfer off
    left, on right — the tower corner gains a lit vertical band and the slab lips a highlight).
39. **`ring` rows (lead r8 3).** `kit_assign.json` may now name one of the 96 skyline-ring boxes:
    ```json
    {"kind": "ring", "index": 12, "model": "far01"}
    {"kind": "ring", "id": "12", "model": "far01"}
    ```
    `props.skyline(layout, skin)` drops that box from `skyline.glb` exactly like a `cover` row
    (nothing else — the ring has no collision to keep), and an index past the end of
    `city_layout.json["skyline"]` is reported by name and dropped. Every box, dropped or not, is
    exported as a `skyline_ring` slot in `layout.json` with `index`, `center`, `size`, `height`,
    `base_z` and `dropped`, so city-kit can place a far model without reading the design layout.
    Verified on a synthetic assignment: 3 rows dropped, `skyline.glb` 358 476 → 347 460 bytes,
    96 slots exported with `dropped` set on exactly `[0, 5, 95]`, the stale `999` reported, and the
    row with no index counted as skipped.
40. **Far tiles are held behind the gate (lead r8 4).** A `far_lod` row now only stands my HLOD
    proxy down when it carries `"gate": "pass"` (or `hole_gate` / `status`); anything else is
    counted in `kit_skin.far_tiles_held`, printed by the build and by `city.gd`, and that tile
    keeps its proxy. On the file as it stood when the gate landed, **41 rows were held and 0
    proxies stood down**; city-kit then added the field and it went back to 36 standing down.
    `test_city.gd` asserts `hidden proxies == len(far_tiles)`.
41. **Stale `cover` rows are reported and skipped, never misapplied (lead, layout r7).** r7 cut
    arena cover from 1 070 pieces on 784 centres to **539 on 539**. `Skin._stale_cover()` drops any
    `<arena>#<index>` whose arena is unknown or whose index is past that arena's piece count, and
    the SKIN line names every one. Proven on `tmp/city-build/kit_assign_stale_test.json`
    (8 rows: 3 valid, 4 stale, 1 unreadable):
    ```
    SKIN ...: 0 buildings, ..., 7 cover pieces, ... (1 rows skipped)
    SKIN: 4 assignment ids match nothing in the layout and were dropped: A1#80, A1#9999, A2#200, A9#0
    ```
    and the exported `arena_cover` slots (now carrying a `dropped` flag) are `A1#79`, `A2#144`,
    `A6#0` — whose `pos`/`size` match `city_layout.json` rows 79 / 144 / 0 exactly, so no
    off-by-one and no wrong piece. `probe_skin.py --assign=` on that file: **SKIN DIFF PASS**,
    collision identical to the last decimal, 312 render triangles dropped for the 3 pieces
    (2 chamfered boxes each).

### Round 7 (lead r9 — walkable floors with no rendered top face)
42. **Diagnosis first, one cause per case.** `tools/city/floor_probe.py` reads only
    `data/map/city_layout.json` and answers, for one cover row, which decks contain its centre,
    which contain its whole footprint, and how far the highest one under it is. Paired with
    `game/world/city/tools/probe_floor.gd` (every rendered up-facing face in a whole vertical
    column, named by mesh — `world/art/tests/probe_support.tscn` only slices +-6 m, which is the
    wrong window when the question is "48 m up"), the 30 rows in the lead's table came out as:
    | cause | rows | what it is |
    |---|---|---|
    | (b) footprint overhangs the deck | 20 | the centre is on the slab, the corners are not |
    | (b) deck island taken by `perforate_decks` | 8 | the arena stage runs BEFORE the perforation |
    | (c) no deck at that tier at all | 2 | `A1#45` over the dock water, `A2#129` over a cut |
    | (a) render lost its top face | 0 | `deck_edge` never touched the slab — see 44 |
    Verified per row in `tmp/city-build/float_audit_r9_before.log` + `floor_probe.py`.
43. **`tools/map/floors.py` (new) — the floor set as the RENDER has it.** `arenas.surfaces()`
    answered the same question from the deck list as it stood when the arena stage ran, and only
    ever asked whether a piece's CENTRE was inside. `Floors` is the crust at 0 (plateau, canal,
    dock trench, sunken plazas and — r9 — every connector trench cut out of it), the plateau, the
    dock floor and every deck minus its holes, and it asks about the whole footprint.
    `cut_ground()` lives here too, so `build_layout` and `Floors` cannot disagree about what is a
    hole. Measured on r8's layout: **220 of 539 pieces had no floor under their footprint.**
44. **`deck_full` keeps its slab (the one real case (a)).** `kit_assign.json`'s `deck_full` rows
    place city-kit's `s06` TUBE down the deck centreline: `s06_lod.glb` is **6.7 m wide, 6 m tall,
    29 m long**, and `kit_placer._segment` only ever scales a segment along its LENGTH — so the
    tube stayed 6.7 m wide on a 24-30 m deck polygon while `skin.py` muted my whole slab. Three
    quarters of every one of those skybridges had no render at all, which is what put A4#41-#49
    48 m over the nearest drawn surface. `deck_full` now mutes the parapet and nothing else,
    exactly like `deck_edge`; the slab, its soffit beams and its columns stay and city-kit's tube
    stands on the deck. (`deck_edge` was already correct — it only ever handed the parapet to a
    `MutedKit`, and `kit.slab` was always called on the unmuted kit.)
45. **`arenas.settle_cover()` — every piece onto a floor, no random numbers.** Runs last, on the
    finished deck list, and walks each wrong piece onto the nearest floor it fits on: same height
    and size first, then a smaller footprint (C14 counts HEIGHT, not plan), then the nearest floor
    below. Reach-major, not size-major, so the nearest legal spot wins whatever size it needs; the
    ring ladder is 4 m near home because the crust between two ramp trenches is a narrow ledge.
    It also refuses any spot that would block a hive's firing lane (`HiveLanes`: 12 pods x 48
    firing positions per spire as segments) or stand in its 40 m of open ground, and it runs twice
    — before the hive stage and again after it, the second time with the spires' FINAL positions,
    because `hives.build` both punches wells through the decks and repairs the cover round them.
46. **Lots may not stand over a hole in the ground crust — as a FILTER (lead nudge).** The first
    attempt put the trench shapes into the block mask; `fabric` then cut different blocks and from
    the first changed block on the one shared `rng` stream re-rolled the city — **334 of the 354
    buildings the user has already seen changed archetype, height or tier**, 38 ids gone, 22 new,
    and every pinned street camera broke. `drop_over_cut()` is now a pure filter that runs after
    `wall.build_walls` (so the kerb-wall ids are numbered against r8's list and do not renumber)
    and again on the final list; a tower a named deck stands on, and a straddle tower a corridor
    runs through, are exempt. The cut is the canal, the dock trench, every sunken plaza and every
    connector trench, each shrunk by the 3 m quay lip that IS rendered floor.
47. **C18 — the gate the lead asked for** (`world/city/tools/checks_floor.gd`). Every walkable
    floor the layout declares must have a RENDERED up-facing face within 0.3 m of its own z,
    sampled on a 4 m grid, `deck_full` decks exempt. It is the only city check that reads the
    render: every other one reads collision, and the collision was always right. The index is
    `ArtSurfaces`, the same class the settle pass and `float_audit` use, so it measures the world
    the game ships. Samples: every deck polygon, the three terrain surfaces, and every building
    footprint at its `base_z` (the D4_b034 case). A sample under a building or a cover box is
    skipped — a crate on a deck is the float audit's business, not the floor's.
48. **What C18 found, and what each finding was** — this is the gate earning its keep:
    | finding | samples | what it turned out to be |
    |---|---|---|
    | building footings over a hole | 29 | the trench filter (46) |
    | crust beside a descending ramp | 14 | `_trench_poly` built ONE mitred outline, which self-intersects at a bend; Blender's exact boolean resolves that by the winding rule and even-odd point-in-polygon does not, and the two disagreed by up to 1.6 m. It emits one rectangle per segment plus a joint square now, which both agree on |
    | the whole Crown "missing" at 224 | 7 | its outermost rim step sits ON the datum, so the walkable surface (collider included) is 225.5. `markers.py` exports the finish floor |
    | edges of holes in `W3_foundry_l2` | 11 | the 4 m grid landed exactly on 2 m hole coordinates; even-odd is undefined on an edge |
    | one `x = -80` line on the Crown | 7 | the grid landed exactly on a chunk seam; a ray fired at the seam between two abutting faces hits neither |
    | the escarpment crest | 3 | the ray stopped on a city-kit tower's sloped base — a facade at ground level is a wall, not a floor; the gate queries the tile meshes only |
    The grid is offset 0.37 m so it never lands on a round coordinate, and a sample within 0.25 m
    of a polygon edge is dropped.
49. **The layout survives the fix (the lead's gate).** Diff of the shipped layout against r8
    (`ffdf9f7^`), measured per key:
    | key | result |
    |---|---|
    | buildings | 392 -> 358; **all 358 kept are byte-identical**, 34 dropped, 0 new, 0 changed |
    | streets, connectors, landmarks, anchors, player_start, bounds, terrain, viaducts, rails, tunnels | **identical** |
    | sky graph | 225 waypoints and 668 edges, **all identical** |
    | skyline | identical (pinned in `overrides.json`: it is the last draw on the shared stream, and without the pin dropping 33 lots re-rolled all 96 by 590 m on average) |
    | decks | 77 -> 77, 75 identical; `K4_knot_flyover` and `K5_knot_crown` carry hive_a2's well |
    | hives | hive_a2 -464 -> -476 (12 m); `hives.build` re-sites on the finished layout and the cover moved. a5 and a6 identical |
    | arenas | the cover, which is the point of the round |
    The 34 dropped ids are listed by the build: `lots over a ground cut (r9): 34 dropped`.
50. **Cover pieces are no longer shrunk below 16 m.** C14 casts 8 rays 45 deg apart; a 12 m box at
    40 m falls between them, which cost A6 28 points of cover. Worst cover is back at 70 %.

### Round 8 (lead r10 brief: split `tools/map/build_layout.py`, output-identical)
51. **`build_layout.py` is 605 -> 346 lines and is now only the pipeline.** `main()` keeps the
    stage order and the prints, unchanged; every helper moved to the module that owns that piece
    of the city:
    | was | now | why there |
    |---|---|---|
    | `_mask` | `lots.street_mask` | the ground a lot may stand on: the streets with their setback |
    | `land_freed` | `lots.land_freed` | the per-district measure of what the MAP §4 widths gave back |
    | `height_caps` | `corridors.height_caps` | what a flying corridor caps above it |
    | `_core` | `corridors.navigable_core` | the part of a corridor traffic actually uses |
    | `_declare_through` | `straddle.declare_through` | `through` on a corridor that pierces a mass |
    | `_loop_through` | `straddle.loop_through` | the Ring Viaduct's `through` = its segments' |
    | `_rail_termini` | `straddle.rail_termini` | a rail that ends inside Block 9 ends on the platform |
    | `_cut_plateau` | `cuts.plateau` | the crust cut taken at the plateau slab, clipped to it |
    | `_carriers` | `cuts.carriers` | the towers a named deck stands on (never dropped) |
    | `drop_over_cut` | `cuts.drop_lots` / `cuts.sweep` | the r9 filter, swept twice from one pair of polygons |
    | `_clear_cover` | `props.clear_cover_under_towers` | cover a declared carrier tower stands on |
    | `_tower_keep` | `props.tower_keep` | the same footprints as a keep-out for the top-up |
    | `_tag_quarters` | `zones.tag_quarters` | `quarter=d4q`, the one thing zones.py knows about buildings |
    | `_apply_corridor_moves` | `overrides.apply_corridor_moves` | `layout.move` lands before the stages read the corridors |
    | `apply_overrides` | `overrides.apply` | the other four levers, applied to the finished layout |
    New files `tools/map/cuts.py` (80 lines) and `tools/map/overrides.py` (60). `_trench_mask` from
    the brief no longer exists (it is `floors._trench_polys`, already in `floors.py`). `_avenues`
    had **no call site anywhere in the repo**, so it is deleted rather than moved.
52. **Sizes.** `build_layout.py` 346, `cuts.py` 80, `overrides.py` 60, `lots.py` 221, `zones.py`
    85, `props.py` 228, `straddle.py` 347, `corridors.py` 397 — every touched file is under 400.
    `arenas.py` (546) was not touched. `pyflakes` reports no new finding on any of them.
53. **Byte-identical output, and identical stdout.** `data/map/city_layout.json` has the same
    sha256 before and after the split, and so does every other file in `data/map/`; the 60-line
    run log is identical too (so not one count, position or print moved):
    ```
    3bf1971770fe76cf4830bae60bf553c7a638f5a5737a00778ed51b121fa5f9e2  data/map/city_layout.json
    b2b060a2fbc98a2d03c7cb6bae7c4bcea5488064de9aba7d20b71e8713844444  data/map/district_rules.json
    2e93afc7dcdaa8c2f81499c8f1907b89243af2653aeb2292fb44400a7283af76  data/map/kit_assign.json
    138207c2ceb5af03b1f72e12abbc673a50eaa35081a49d3f7eec5eba1f736062  data/map/level_graph.json
    4326bc35163f7f8d407da6b56ca97c8b9e6cd99aa16d37a19d92d11b1652c2e4  data/map/overrides.json
    ```
    (The committed file was already identical to a fresh run before the split, so this is a real
    before/after and not a no-op.) Logs: `tmp/city-build/{hash_before,hash_after,run_before,run_after}.txt`.
54. **Validators.** `validate_graph.py` PASS (C11 A4->A5 the accepted NOTE) and
    `validate_layout.py` PASS (four L3 headroom NOTEs and the L4 keep-clear exemption, all
    pre-existing). Logs: `tmp/city-build/validate_{graph,layout}.txt`.
55. **Nothing downstream was rebuilt**: no `build_city.py`, no navmesh bake, no settle cache, no
    capture. Commit `71da3a2`, eight paths, `git diff --cached --stat` checked before it.

## How to verify (exact commands)
```
tools/blender.sh run blender/city/build_city.py                    # full rebuild (~42 s)
tools/blender.sh run blender/city/build_city.py -- --district D5   # one district
tools/blender.sh run blender/city/build_city.py -- --blockout      # ignore kit_assign.json
tools/blender.sh run blender/city/build_city.py -- --no-chamfer    # A/B the box chamfer
tools/blender.sh run blender/city/build_city.py -- --assign=<json> # test another assignment
uv run --with numpy --with shapely --with networkx \
    python3 tools/map/build_layout.py                              # regenerate the layout (r9)
uv run --with numpy --with shapely --with networkx \
    python3 tools/map/validate_layout.py                           # PASS (r10 split check)
uv run --with networkx python3 tools/map/validate_graph.py         # PASS (r10 split check)
python3 tools/citykit/assign.py                                    # re-fit the kit to it (r9)
python3 tools/city/floor_probe.py A4#49 A3#36                      # why is this cover in mid-air?
PROBE_AT="465,80,-570;11,-20,150" \
    tools/godot.sh run res://world/city/tools/probe_floor.tscn 60  # what IS under it, named
PROBE_ALLKIT=1 PROBE_AT=... \
    tools/godot.sh run res://world/city/tools/probe_floor.tscn 60  # ... counting kit pieces too
SETTLE_BAKE=1 tools/godot.sh run res://tools/float_audit.tscn 600  # re-bake the settle cache (r9)
tools/city/bake_nav.sh                                             # offline navmeshes
tools/godot.sh check --only=res://world/city/,res://world/city.gd   # 4 files, 0 errors
tools/godot.sh test res://world/city/tests/test_city.gd            # 105 checks
tools/godot.sh run res://main.tscn 20                              # errors=0
tools/city/checks.sh                                               # C12-C17 (~25 s now)
tools/city/nav_report.sh                                           # nav sync, links, reachability
tools/city/nav_probe.sh                                            # why a socket is off-mesh
tools/godot.sh test res://world/city/tools/skin_probe.gd            # skin keeps collision
tools/blender.sh run blender/city/probe_skin.py                   # collision diff, skinned vs blockout
tools/blender.sh run blender/city/probe_skin.py -- --assign=<json>  # ... for another assignment
tools/city/vistas.sh                    # solve the vistas -> data/vistas.proposed.json
tools/city/vistas.sh --shots            # ... and capture captures/city_Vn_proposed.jpg
tools/blender.sh run blender/city/probe_crust.py                   # ground-crust regression
tools/blender.sh run blender/city/preview_part.py -- --part spire  # one kit part -> tmp/
tools/blender.sh run blender/city/preview_part.py -- --part bridge # ... or the Crystal Bridge
tools/blender.sh preview tmp/city-build/part_bridge.glb bridge_r8 --views front34,side,front,under,close_front34
tools/godot.sh perf --skip-menu --no-enemies --warm=90 --spawn=-583,14,640,-37.5
tools/godot.sh perf --skip-menu --no-enemies --no-kit --warm=90 --spawn=-514.5,112,105.1,-66.4
tools/godot.sh shot --scene=res://main.tscn --out=city --cams=<vistas> --env-only --skip-menu \
    --stub=player,camera,enemies,flow [--blockout]
tools/godot.sh movie --movie=$PWD/captures/city_flight.avi \
    --timeline=res://world/city/tests/flight.json --skip-menu --no-enemies --stub=camera,flow
# the four Spire mid-distance frames the r2 review called out (all look at the shaft at +170):
tools/godot.sh shot --scene=res://main.tscn --out=spire --warm=90 --env-only --skip-menu \
    --stub=player,camera,enemies,flow --blockout \
    --cams="r3S1:-380,45,280:0,170,-120:50;r3S2:330,90,420:0,170,-120:50;\
r3S3:-520,120,-60:0,170,-120:50;r3S4:400,60,-400:0,170,-120:55"
```

## Evidence (round 7, layout r9 — CURRENT)
- **The lead's gate, `float_audit` STRUCTURE** (`tools/godot.sh run res://tools/float_audit.tscn 600`):
  ```
  before (r8 build):  STRUCTURE 46 of 3992 judged instances off their surface by more than 0.5 m
                      STRUCTURE cover 1126 judged, 45 off, 2 with no floor, worst 48.0 m
                      STRUCTURE street 200 judged,  1 off (D4_b034_podium, +14.0 m)
  after  (r9 build):  STRUCTURE  0 of 3823 judged instances off their surface by more than 0.5 m
                      FLOAT      0 instances floating more than 0.5 m
  ```
  Logs: `tmp/city-build/float_audit_r9_before.log`, `tmp/city-build/float_audit_r9_final.log`.
- **C18, the new top-face gate** (`tools/city/checks.sh`):
  `C18 PASS: 137 335 samples on a 4 m grid, 0 with no rendered face within 0.3 m, 5 deck_full
  decks exempt` — 1 510 render supports indexed, 5.6 s. It was 538 failures on the first run; the
  path from 538 to 0 is item 48 above, one cause at a time.
- **The floor under the lead's worst rows, before and after** (`probe_floor.tscn`):
  | point (godot) | r8 | r9 |
  |---|---|---|
  | (465, 80, -570) — A4#44 | `ground y 32.2`, gap 47.8 m | `ground y 80.00 normal (0,1,0) mesh t5_4_c17_14_0_deck` |
  | (513, 80, -570) — A4#45 | `ground y 32.2`, gap 47.8 m | `ground y 80.00 ... _deck` |
  | (417, 80, -370) — A4#41 | `ground y 32.25`, gap 47.8 m | `ground y 80.00 ... _deck` |
  | (227, 0, 207.8) — D4_b034 | `ground y -14.0`, gap 14.0 m | the lot is gone; the crust is there |
- **The layout diff against r8** — see Done 49 for the per-key table. Reproduce with:
  `git show ffdf9f7^:data/map/city_layout.json > tmp/city-build/city_layout_r8.json` then the
  per-key comparison in `Done 49`. **359 of 392 buildings kept, every one byte-identical.**
- **Layout gates**: `validate_layout` **PASS**, `validate_graph` **PASS** (both were run after
  every layout change this round; `validate_layout` failed twice mid-round — once on a hive
  firing lane the settle had blocked, once on an L4 sample taken over a ramp trench — and both
  fixes are in Done 45 and 48).
- **Godot gates**: `tools/godot.sh check --only=res://world/city/,res://world/city.gd` ->
  **12 files, 0 failed, 0 engine errors, 0 warnings**; `test_city.gd` -> **TEST PASS (111 checks,
  0 failed)**; `run res://main.tscn 20` -> **errors=0, warnings=1**, 74 tiles, 1 196 meshes,
  342 710 tris, 115 static bodies, **world built in 6.2-8.7 s** (gate 10 s).
- **Settle cache** (the lead's step 4): `SETTLE_BAKE=1 ... float_audit.tscn 600` ->
  `SETTLE CACHE wrote res://world/art/settle_cache.json: 133 batches`;
  `test_settle_cache.gd` **PASS (0 failures)**, `test_float.gd` **PASS (0 failures, 0 floating)**,
  `test_settle.gd` **PASS (0 failures)**.
- **Navmesh re-baked for the new layout** (`tools/city/bake_nav.sh` -> **BAKE PASS**):
  | | polys | islands | biggest |
  |---|---|---|---|
  | small | 17 181 | 1 239 | 21.4 % |
  | medium | 9 513 | 574 | 20.3 % |
  | large | 4 010 | 226 | 22.1 % |
  `nav_report.sh`: sync **PASS at 26 ms**; links enabled small 17/48 · medium 12/48 · large 11/48;
  socket->arena **small 91 % · medium 88 % · large 59 %**; medium arena->arena **14 %**;
  control 100 % for all three. See Known issues 8.
- **City checks** (`tools/city/checks.sh`, 6 failed — the same informational set as r8):
  **C16 PASS** (0 exposed edge samples, 0 arcs leaving the square) · C12 41/48 arcs blocked,
  32 starts inside geometry · C13 108/600 (18.0 %) under headroom · C14 cover A1 90 % A2 72 %
  A3 80 % A4 82 % A5 75 % A6 70 %, **worst 70 %**, sightlines 0.0 % in every arena · C15 47.6 %
  (L1 26.0 %, L2+ 57.9 %) · C15b 6/7 (blind A4) · C17 57.2 % off the medium navmesh ·
  **C18 PASS**.
- **Captures** (before = the r8 layout + the r8 `decks.py`, rebuilt; after = shipped):
  `captures/cb9before_a4t80.jpg` / `cb9after_a4t80.jpg` and `cb9before_a3t20.jpg` /
  `cb9after_a3t20.jpg`, plus the `--blockout` pairs `cb9beforeblk_*` / `cb9afterblk_*`. All at a
  player height (deck + 6 m). **Honest reading: the pairs are not dramatic** — see Known
  issues 17; the numeric column evidence above is the decisive one.

## Evidence (round 6, layout r7 + live kit_assign.json — superseded)
- **Build**: `SKIN ... 382 buildings, 74 deck edges, 5 whole decks, 11 viaducts, 539 cover pieces,
  35 far-LOD tiles (0 held), 0 ring boxes (0 rows skipped)`; **547 308 tris, 58.0 MB, 12.7 s**.
  Godot: 77 tiles, 1 251 meshes, 347 928 tris, 118 static bodies, **world built in 7.8–8.8 s**.
- **Landmark range (lead r8 1)**: `City: 135 landmark chunks keep their own geometry to 2400 m`;
  `City: 35 of 77 HLOD proxies stand down`. In the .glb, `tile_3_4` `-colonly` is 6 023 verts
  before and after (collision untouched) while `t3_4_hlod` falls 6 004 → 2 940 verts and its top
  from y 360 to y 232 — the Spire is out of the proxy. Landmark render cost **62 682 of 347 928
  tris (18 %)**, so no extra far tier was needed.
  A/B: `captures/cb8_landmark_V2.jpg` (the lead's `far_layers_V2` sheet on top, V2 after below),
  `captures/cb8_V2.jpg`, `captures/cb8_V5.jpg`, `captures/cb8_V8.jpg`.
- **Crystal Bridge**: `captures/blender/bridge_r8_studio.jpg` (the part alone, 5 views),
  `captures/cb8b_a6.jpg` (the lead's A6 hive framing — an arch silhouette with a diagrid instead
  of the fence), `captures/cb8b_side.jpg` (the arch elevation, Spire behind), `captures/cb8b_v34.jpg`.
- **Chamfer**: `captures/cb8_chamfer_lip.jpg` and `captures/cb8_chamfer_a1b.jpg` (off left, on
  right). Shipped build **264 860 → 547 308 tris (+107 %)**, 25.4 → 58.0 MB; load time
  **7 723–9 426 ms without vs 7 584–7 984 ms with**, i.e. no measurable cost.
- **`ring` rows**: on `tmp/city-build/kit_assign_r8_test.json` — 3 boxes dropped,
  `skyline.glb` 358 476 → 347 460 bytes, `layout.json` carries 96 `skyline_ring` slots with
  `dropped` on exactly `[0, 5, 95]`, `skyline[999]` reported stale, the index-less row skipped.
- **Far-LOD gate**: with the field absent, `City: 41 far-LOD rows held ... every HLOD proxy stays
  up` and `0 of 77` stood down; with `"gate": "pass"` on one row, `City: 1 of 77 HLOD proxies
  stand down (t0_0)`. city-kit has since gated all of them (35–36 standing down).
- **Stale cover rows (layout r7)**: see Done 41 — 4 stale ids named, 1 skipped, exactly
  `A1#79 / A2#144 / A6#0` dropped, `SKIN DIFF PASS` with collision identical.
- `tools/godot.sh check --only=res://world/city/,res://world/city.gd` → **9 files, 0 failed,
  0 engine errors, 0 warnings**; `test_city.gd` → **TEST PASS (111 checks, 0 failed)** (6 new:
  ring slots, the held-row report, landmark chunk count, no landmark left on the detail cut,
  hidden proxies == gated rows); `run res://main.tscn 20` → **errors=0**.
- `probe_skin.py` → **SKIN DIFF PASS**: col 14 509 boxes / 59 883 161.0 m3 · occ 349 /
  11 831 407.0 · props 4 290 / 2 475 297.6 · curtain 4 / 8 773 440.0, **identical skinned vs
  blockout**; render 918 600 → 207 128 triangles.
- `skin_probe.gd` → **SKIN PROBE PASS (0 failed)**: 382 / 382 footprints (1 910 rays),
  784 / 784 roof slots, navmesh polys `{small 17 642, medium 9 251, large 3 873}`.
- **Navmesh re-baked for layout r7** — the cover respacing helped a lot:
  | | polys | islands | biggest | socket→arena | arena→arena |
  |---|---|---|---|---|---|
  | small | 18 183 → **17 642** | 1 617 → **1 351** | 18.1 → **21.1 %** | 88 → **91 %** | — |
  | medium | 9 564 → **9 251** | 750 → **609** | 14.8 → **20.8 %** | 72 → **94 %** | 14 → **29 %** |
  | large | 3 795 → **3 873** | 251 → **231** | 14.6 → 12.2 % | 50 → **62 %** | — |
  `nav_report.sh`: sync **PASS at 28 ms**; links enabled small 19/48 · medium 12/48 ·
  large **14/48** (was 8/48); control 100 % for all three.
- **Checks on r7** (`tools/city/checks.sh`): **C16 PASS** (0 exposed edge samples, 0 arcs leaving
  the square) · C12 41/48 arcs blocked, 32 starts inside geometry · C13 **86/600 (14.3 %)** under
  headroom (was 17.2 %) · **C14 cover A1 78 % A2 72 % A3 85 % A4 80 % A5 82 % A6 88 %, worst 72 %
  (was 60 %), sightlines 0.0 % in every arena** · C15 **48.9 %** (L1 28.1 %, L2+ 60.5 %) ·
  C15b 6/7 (blind A4) · C17 60.8 % off the medium navmesh.
- **Perf at four vista cameras** (`tools/godot.sh perf --skip-menu --no-enemies --warm=90`),
  machine load 14–22 with other units running:
  | vista | draws | objects | prims | fps |
  |---|---|---|---|---|
  | V1 | 1 174 | 1 379 | 7 325 672 | 21 |
  | V2 (the Spire vista) | 1 241 | 1 454 | 11 845 574 | 11 |
  | V5 | 834 | 1 047 | 9 784 189 | 13 |
  | V8 | 539 | 815 | 3 116 091 | 7 |
  **Draw calls are 539–1 241 against the 3 500 budget.** fps does not track either number —
  V8 has the fewest draws and the lowest prims and the worst frame time — so the frame cost is
  not my geometry. Attribution at V2, same camera, same warm-up:
  | V2 | draws | prims | fps |
  |---|---|---|---|
  | with city-kit's placer | 1 241 | 11 845 574 | 11 |
  | `--no-kit` (my tiles only) | 1 084 | **3 025 757** | 15 |
  So city-kit's ~5 000 instanced meshes are **8.8 M of the 11.8 M prims (74 %) at a cost of 157
  draw calls**, and my tiles sit at 3.03 M prims — the same 1.77–3.03 M band r3 measured before
  the kit city existed. And the same eight cameras shot with the gameplay systems stubbed
  (`--stub=player,camera,enemies,flow`) read **V1 28 · V2 34 · V3 31 · V4 36 · V5 28 · V6 33 ·
  V7 41 · V8 39 fps, errors=0** — so the gap between 28–41 fps and the probe's 7–21 fps is the
  player/enemy/boss simulation and the post stack, not the city. See Known issues 14.
- **Captures on r7**: `captures/cb8_V1..V8.jpg` (all eight, errors=0),
  `captures/cb8_landmark_V2.jpg` (the lead's `far_layers_V2` sheet above, V2 after below),
  `captures/cb8_bridge_a6.jpg` (the lead's `user_shot_1.png` A6 frame above, the same view after
  below), `captures/cb8b_a6.jpg`, `captures/cb8b_side.jpg`, `captures/cb8b_v34.jpg`,
  `captures/cb8_chamfer_lip.jpg`, `captures/cb8_chamfer_a1b.jpg`,
  `captures/blender/bridge_r8_studio.jpg`.

## Evidence (round 5, layout r6 + live kit_assign.json — superseded)
- **Skin probe over every skinned building: `SKIN PROBE PASS (0 failed)`** —
  `358 / 358 skinned footprints still collide (1 790 rays)` · `736 / 736 skinned roof slots still
  collide (highest hit +8.0 m over the slot, gate -2.0..+8.0)` · navmesh polys
  `{small 18 183, medium 9 564, large 3 795}`, unchanged from the unskinned build.
- **Collision diff (`probe_skin.py`): `SKIN DIFF PASS (0 failed)`** — col 5 511 boxes /
  65 448 499.9 m3, occ 258 / 11 716 568.4 m3, props 1 173 / 5 421 127.1 m3, curtain 4 /
  8 773 440.0 m3, **identical skinned vs blockout**; render 493 820 → 137 520 triangles.
- **Cover hook**: 448 `cover` rows (A1+A2) → Blender 324 006 → 306 562 tris, Godot
  240 750 → 223 306 tris, collision fingerprint unchanged; in `tile_1_1.glb` the chunk
  `t1_1_c3_4_0_panel_white` (228 verts) is present with the rows and gone without them while
  `t1_1-colonly` keeps all 2 411 verts. Capture pair `captures/cover_hook_before_after.jpg`
  (A2 upper deck, cover on / cover off) and `captures/cover_hook_A2_before_after.jpg`.
- **Far field**: `City: 29 of 77 HLOD proxies stand down (city-kit far LOD covers them: t0_0 …)`.
- Build: **324 006 tris, 20.8 s**, `skinned 448 structures`. Godot: 77 tiles, 1 290 meshes,
  240 750 tris, 118 static bodies, **world built in 6.0–6.3 s** (was 2.2–2.4 s before city-kit's
  5 137 instances and the far tier landed — still inside the 10 s gate).
- `tools/godot.sh check --only=res://world/city/,res://world/city.gd` → **9 files, 0 failed,
  0 engine errors, 0 warnings**; `test_city.gd` → **TEST PASS (105 checks, 0 failed)**;
  `run res://main.tscn 20` → **errors=0, warnings=0**, fps_mean 38 (fps_min 13).
- `tools/city/checks.sh` → **C16 PASS**; C12 41/48 arcs blocked · C13 103/600 (17.2 %) ·
  C14 cover 60–80 %, sightlines 0.0 % · C15 46.2 % (L1 27.7 %, L2+ 56.9 %) · C15b 6/7 ·
  C17 62.9 % off the medium navmesh. **Every number is identical to round 4**, so the roof-cell
  change moved nothing that the checks measure.

## Evidence (round 4, layout r6 — superseded)
- Build: **712 455 tris, 68.7 MB, 40.4 s**, `skinned 0` (no `data/map/kit_assign.json` yet).
  Godot: 76 tiles, 1 765 meshes, 628 935 tris, 118 static bodies, **world built in 2.2-2.4 s**.
- `tools/godot.sh check` -> **552 files, 0 failed, 0 engine errors, 0 warnings**;
  `test_city.gd` -> **TEST PASS (105 checks, 0 failed)** (also after the `city_markers.gd` split);
  `run res://main.tscn 20` -> **errors=0**, fps_mean 59.
- **Skin mode, measured on a 14-building + 3-deck-edge test assignment**
  (`tmp/city-build/kit_assign_test.json`, `--assign=`):
  | | unskinned | skinned |
  |---|---|---|
  | Blender tris | 712 455 | 693 868 |
  | export size | 68.7 MB | 66.8 MB |
  | Godot meshes / tris | 1 765 / 628 935 | 1 667 / 610 348 |
  | **static bodies** | **118** | **118** |
  | **navmesh polys s/m/l** | **18 183 / 9 564 / 3 795** | **18 183 / 9 564 / 3 795** |
  `skin_probe.gd` on that build -> **SKIN PROBE PASS**: 14/14 skinned roofs still collide
  (highest hit +4.8 m over the slot — the warehouse/industrial archetypes' own roof cap).
  `captures/shot_skin_off.jpg` vs `captures/shot_skin_on.jpg` is the same camera with the
  procedural towers present and absent.
- Both placer branches run: with a scene at the `KIT_PLACER` path, Godot prints
  `City: kit placer instanced for 17 skinned structures` and calls `setup(city, layout)`; with
  `--blockout` it warns `17 structures have no render mesh but the kit placer is off`.
- `layout.json` now carries **96 `edges`** (74 deck rims + 22 viaduct barrier lines) and
  `kit_skin`; `meta.revision` (6) is exported too, so a consumer can see the layout it came from.
- **Navmesh re-baked for r6**: `small 18 183 polys / 1 617 islands / largest 18.1 %` ·
  `medium 9 564 / 750 / 14.8 %` · `large 3 795 / 251 / 14.6 %`.
  `nav_report.sh`: sync PASS at **28 ms**; links enabled **small 19/48 · medium 15/48 · large 8/48**;
  socket -> arena **small 88 % · medium 72 % · large 50 %** (gate 95 %; r4 was 81/62/41 %);
  control (largest island) 100 % for all three.
- Checks on r6 with the r6 navmesh: **C16 PASS** (0 exposed edge samples, 0 arcs leaving the
  square) · C12 41/48 arcs blocked, 32 starts inside geometry · C13 103/600 (17.2 %) under headroom
  · C14 cover 60-80 %, sightlines 0.0 % · C15 46.2 % (L1 27.7 %, L2+ 56.9 %) · C15b 6/7 (blind A4)
  · C17 62.9 % off the medium navmesh. The drift from the r4 numbers is layout r5/r6 (sockets
  moved onto the arena tops, hive spires), not this round's work — nothing is skinned in the
  shipped build.
- Vistas re-shot on r6 in one run: `captures/city_V1..V8.jpg`, **errors=0, warnings=0, 60 fps at
  all eight**. Perf at V1: **825 draws, 1.85 M prims, 60 fps** (budget 3 500).

## Evidence (round 3, layout r4 — final)
- Build: 692 459 tris, 39.4 s. Godot: 76 tiles, 1 726 meshes, 615 423 tris, 119 static bodies,
  **world built in 1.2–1.6 s**; `run res://main.tscn 20` -> 54–60 fps mean, **errors=0** (was 7
  `path_corridor`), 0 `path_corridor` lines in the log.
- `check --only=res://world/city/` -> **7 files, 0 failed, 0 engine errors, 0 warnings**.
  `test_city.gd` -> **TEST PASS (105 checks, 0 failed)**.
- Navmesh bake: `small 19 128 / 1 735 islands / largest 16.8 %` · `medium 9 532 / 752 / 17.8 %` ·
  `large 3 767 / 257 / 14.4 %`, PASS. Islands before/after r2: **2 005/856/260 -> 1 735/752/257**,
  biggest **14.0/11.5/10.0 % -> 16.8/17.8/14.4 %**.
- `nav_report.sh` -> **nav sync PASS: all three maps queryable 39 ms after the world was built**.
  Links enabled **small 18/48, medium 20/48, large 6/48**. Socket -> arena centre
  **small 81 % · medium 62 % · large 41 %** (gate 95 %); medium arena->arena 14 %.
  Control (largest island) **100 %** for all three.
- `nav_probe.sh` -> every one of the 32 sockets has a floor under it; no geometry holes.
- Checks: **C16 PASS** (0 exposed edge samples, 0 arcs leaving the square — the curtain still
  collides after being taken out of the HLOD). C12 40/48 blocked · C13 17.3 % under headroom ·
  C14 cover 60–90 %, **sightlines 0.0 % in every arena** · C15 49.0 % (L1 23.1 %, L2+ 62.4 %) ·
  C15b 4/7 · C17 66.9 % off-mesh (informational).
- HLOD fix verified in the .glb itself: `t-1_3_hlod` 4 verts, y 0..60 (the visible parapet);
  `t-1_3-colonly` 8 verts, y 0..260 (the no-fly curtain, collision unchanged).
- `layout.json` now carries **55 `podium_walls`** footprints (MARKERS line prints the count).
- Spire: `captures/spire_r3S1..S4.jpg`, `captures/spire_r3S7.jpg` (art environment) and
  `captures/spire_r3S1b.jpg` (`--blockout`, where the 10 ribs and the flare read cleanest).
- Vistas: `data/vistas.proposed.json` + `captures/city_V1..V8_proposed.jpg`, all re-shot after the
  HLOD fix — the flat backdrop wall is gone from every frame.
- Perf: draws at the eight proposed cameras **V1 1 083 · V2 993 · V3 738 · V4 595 · V5 667 ·
  V6 753 · V7 870 · V8 863** — max 1 083 of the 3 500 budget; primitives 1.77–3.03 M. Frame time at
  `--warm=6` is pipeline-compilation bound (four spots read 8–27 fps at 6 warm frames, the rest read
  60 at the same primitive counts), and one spot still read 13 fps at `--warm=240`, so I have NOT
  confirmed 60 fps at every camera this round — see Known issues 14.

## Evidence (round 2, layout r4, after the crust fix) — kept for the before/after
- Navmesh bake: `small 20 403 polygons / 2 005 islands / largest 14.0 %` ·
  `medium 9 567 / 856 / 11.5 %` · `large 3 353 / 260 / 10.0 %`.
- `nav_report.sh` -> links attached small 19/48, medium 30/48, large 38/48;
  arena -> arena small 29 %, medium 14 %, large 5 %.
- Ground crust (`tools/blender.sh run blender/city/probe_crust.py`):
  `CRUST PASS: 103.5 % of expected area in 2 components` — 921 824 m2 up-facing against an
  expected 890 233 (cutters overlap, so >100 % is correct). Before the fix: **173 642 m2**.
- Perf (1600x900, high, layout r4, HLOD on): V1 1 112 draws / 60 fps · V2 1 383 / 60 ·
  V3 1 129 / 60 · V4 482 / 60 · V5 690 / 60 · V6 1 090 / 60 · V7 716 / 60 · V8 775 / 61.
  Round 1's aerials, passage shots and the 60 s flight movie are unchanged and still in
  `captures/`.

## Known issues (honest)
**Items 17-19 are this round. Items 0-16 are r8's and are kept for the history — where a number
there differs from the Evidence (round 7) block, the round-7 number is the current one.**

17. **(r9) The before/after captures at A4 tier 80 and A3 tier -20 are honest but not dramatic.**
    The lead asked for both from a player height and they exist
    (`captures/cb9before_a4t80.jpg` / `cb9after_a4t80.jpg`, `cb9before_a3t20.jpg` /
    `cb9after_a3t20.jpg`, plus the `--blockout` pairs), but framing them cost more than the round
    itself: the Megablock Canyon is 200-300 m towers at 40-60 m spacing, so a hand-picked camera
    is inside a wall as often as not, and the A3 offenders turned out to be in a **50 m slot
    between `A3_court` and `A3_court_b1` that the crust roofs over at z 0** — the floating crates
    were never visible from outside the slot. What I did instead, and what I would defend as the
    better evidence: the `probe_floor` column at each of the lead's own coordinates, before and
    after (Evidence, round 7). If the lead wants the picture, the camera has to come from the
    layout — say the word and I will add a `cams` entry per offender to the shot tool.
18. **(r9) Cover density moved, mostly for the better and once for the worse.** `settle_cover`
    walks a homeless piece onto the nearest floor it fits on, which sometimes means a lower tier;
    7 pieces had nowhere legal to stand at all and are gone. C14's worst cover is **70 %** (was
    72 % on r8) and A1 actually went UP to 90 %, but **A5 fell from 82 % to 75 %** and **A6 from
    88 % to 70 %** — those two arenas put pieces on canopy roofs and sky-garden plates whose
    polygons do not hold a 16 m box, so the pieces went down to the street under them. It is the
    truth about the geometry, not a bug in the settle, but it is a real loss of cover and
    city-layout may want to widen those two decks.
19. **(r9) The layout is 34 buildings smaller than r8.** They all stood over a hole in the ground
    crust (a descending ramp's trench, the dock trench, the canal). Nothing was renumbered and
    every surviving building is byte-identical, but a few street frontages now have a gap in them
    where a lot used to be. `D4_plaza_tower2` is one of them and it was a named landmark-adjacent
    tower — if that gap reads badly in a capture, the fix is a wider trench rule in
    `connectors.py` (cut `width + 8` is 8 m wider than the ramp it carries), not a re-roll.
0. **(r5) The cover hook is proven numerically but has no dramatic before/after capture**, because
   city-art's `cargo_blocks.gd` redraws every cover piece from the design layout (Requests 19).
   The evidence I do have: the collision fingerprint is unchanged, `tile_1_1.glb` loses the
   `t1_1_c3_4_0_panel_white` chunk, Godot loses 4 376 triangles for 448 A1+A2 rows, and the
   close-range pair `captures/cover_hook_before_after.jpg` shows the pale caps gone.
1. **C12 FAIL: 40 of 48 connector arcs blocked, 33 starts inside geometry.** Unchanged across
   r3 and r4 — no connector `from`/`to` has moved since, so the keep-clear did not reach them.
   Worst: the Knot helix (`con_O1_O2`, `con_O2_O3`, `con_V7_O1`), `con_H3_A1_drop` and
   `con_U4_O7_lift` (inside the tunnel lining). Informational per the lead; layout data —
   see Requests 1.
2. **C13 FAIL: 14.3 % of navmesh samples under the headroom minimum** (86 of 600, worst 15.8 m
   against 32 m in arenas / 24 m elsewhere). Down from 17.2 % on r6 — layout r7's cover respacing
   opened lanes. Almost all inside arenas where the gate is 32 m. Informational per the lead.
3. **C14 FAIL: cover 72–88 % per arena** (A2 72 %, A1 78 %, A4 80 %, A5 82 %, A3 85 %, A6 88 %)
   where the gate is 100 %. **Up from 60–90 % on r6** — layout r7's 539 well-spaced pieces cover
   more of each arena than r6's 1 070 overlapping ones did, which is the intent.
   **Sightlines are 0.0 % in every arena** (gate 5 %). The Crown is exempt as `open_cover`.
4. **C15 FAIL: 48.9 % of navigable samples see the Spire** against the 60 % gate — **L1 streets
   28.1 %**, **L2+ 60.5 %**. The lead accepted 48 % in r2 on the grounds that the compass
   carries the canyons.
5. **C15b FAIL: 6 of 7 arena top tiers see the Spire top or the tether** (was 4/7). Blind: **A4**
   (487, 32, -602). A2 and A3 came back with layout r7. See Requests 4.
6. **V4, V5 and V7 still fail the subject-reach gate.** Ceilings are fixed — 0 % of the upper
   half blocked within 120 m at all three, and the frames are legible now (V4 frames Block 9 with
   the skyrail curving in, V7 looks up the Spire past a lit Crown soffit). What fails is that the
   DECLARED LOOK POINT is not reachable: V4's subject is 225 m away with the first block at
   134 m, V7's 414 m with a block at 277 m, V5's 413 m with a block at 317 m. The lead's three
   hints score worse than the search result (V4 hint: 81 % ceiling, V5 hint: 57 % ceiling — both
   are under a deck). My read: these three need a re-aimed `look_godot`, not a moved camera —
   see Requests 6.
7. **C17 (informational per the lead): 60.8 % of 1 000 max-boost jumps land off the medium
   navmesh** (worst 150 m). The hero out-flies ground enemies by design.
8. **The navmesh is still fragmented, but layout r7 moved it a long way.** Medium is now
   609 islands (was 750) with the biggest at 20.8 % (was 14.8 %). Socket -> arena centre
   **small 91 %, medium 94 %, large 62 %** against the 95 % target (was 81/72/50 %); arena ->
   arena medium **29 %** (was 14 %). The remaining cause is measured, not guessed:
   `nav_probe.sh` shows every socket HAS a floor, so the failures are (a) the medium agent's
   16 m headroom under decks and (b) sockets that sit on a different tier from the arena polygon
   they belong to. Both are layout data — see Requests 1–3.
9. **Only 12 of 48 medium links are enabled** under the 4 m snap gate (small 19, large 14);
   link ends across the three classes are further than 4 m from any navmesh. `nav_report.sh`
   prints every one with both distances.
10. **A `navmesh_edge_merge_errors` warning fires** ("consider lowering
   `navigation/3d/merge_rasterizer_cell_scale`"), 4 errors per sync. Map and mesh cell sizes
   match exactly and the control test is 100 %, so queries are correct; the message is about edge
   merging quality. It is a project setting, so it is the lead's to change.
11. **`small` is capped at +96 m** so Rippers do not reach the sky decks, which leaves A6 (+144)
    and the Crown (+224) off the small map by design. Raising the cap was measured and is worse
    (see Done 16).
12. **One run of `main.tscn 20` out of six reported `errors=1`** with no `ERROR` line in the log
    and no `path_corridor`; the other five reported 0. It did not reproduce, so I cannot name it —
    flagging it rather than claiming it is gone.
13. **The old Known issue "the skyline ring reads as a flat billboard wall" is RETIRED** — that
    wall was the HLOD no-fly curtain, not the ring (Done 19). With the curtain out of the proxy the
    ring reads as a skyline in all eight frames.
14. **I have not confirmed 60 fps at any camera, and the frame cost is not my geometry.** On
    layout r7 the four measured vistas read **21 / 11 / 13 / 7 fps** at 539–1 241 draws and
    3.1–11.8 M prims under `tools/godot.sh perf` (the full game: player, enemies, boss, post).
    fps does not track either number: **V8 has the fewest draws (539) and the lowest prims
    (3.1 M) and the worst frame time (7 fps)**, while V1 has twice the draws and 2.4× the prims
    at 21 fps. Three measurements localise it away from the tiles:
    (a) the same eight cameras with `--stub=player,camera,enemies,flow` read **28–41 fps**;
    (b) at V2, `--no-kit` drops prims from 11.8 M to **3.03 M** (city-kit's instances are 74 % of
    them) and gains 4 fps;
    (c) the chamfer is free in load time and inside the draw budget.
    Draw calls are 539–1 241 of the 3 500 budget everywhere. The machine is shared
    (`vm.loadavg` 14–22 with other units building). What is left is city-art's post stack /
    volumetrics and the gameplay simulation — see Requests 21.
15. **Two `CAPTURE ERROR` lines in one shot run came from `res://world/kit/kit_placer.gd:67`**
    (`Parse Error: Identifier "_gate_failed" not declared`) — city-kit's file, mid-edit while I was
    capturing. Not mine; flagging it because it makes `CAPTURE errors=2` in that one log.
16. **The chamfer more than doubles the tile payload** (25.4 → 58.0 MB, 264 860 → 547 308 tris).
    It measured free in load time and in draw calls, but it is the number to watch if the export
    size or the .app download ever matters; `build_city.py --no-chamfer` turns it off in one flag.

## Requests (to the lead / other units)
24. **lead — two r9 decisions I need, both small.**
    - **The trench rule.** `kit/terrain.py::ground_cuts` cuts the crust for a descending ramp at
      `width + 8`, and the ramp inside it is only `width` wide, so there is a **4 m band of
      nothing on each side of every descending ramp** — the C18 gate found it, and it is why 34
      lots had to go. Either the cut becomes `width + 1` (and the ramp's railings move inboard) or
      the ramp's rendered slab widens to fill the trench with the collider left at `width`. I did
      neither, because both move geometry other units have measured. Say which.
    - **The 34 gaps.** The dropped lots leave holes in the street frontage. If that reads badly,
      the cheapest fix is a `fill.generate` retry that only re-offers the dropped lots after the
      filter — but that draws random numbers, so it needs your call on whether the churn is worth
      it (it would not be: the filter is deliberately churn-free).
25. **city-kit — `deck_full` now means "your model stands ON my slab", not "your model replaces
    it".** `s06` is 6.7 m wide and `kit_placer._segment` only scales a segment along its LENGTH,
    so on a 24-30 m skybridge the tube covered 28 % of the deck and muting my slab left the rest
    of the bridge with no render at all. If you want the slab gone for a particular deck, the row
    needs a `"slab": false` flag and a model that is as wide as the deck — tell me and I will add
    it. Everything else about the row is unchanged: the parapet is still muted, your tube is still
    placed, the collision is still mine.
26. **city-art — C18 uses `ArtSurfaces` and queries the `GROUND` kind only.** It does NOT count
    your kit `detail` buildings as floors, because a facade at ground level is a wall: three
    samples along the escarpment crest were stopping on a tower's sloped base and reading as a
    missing street. If a kit building ever IS a floor (a podium you walk on), it needs to be in
    the tile mesh, not only in the kit batch.
27. **boss — the Crown's finish floor is 225.5, not 224, and the gate now knows it.** The
    outermost `rim_steps` entry sits ON the deck datum and `kit/decks.py::_crown` draws each step
    as a disc from `z` to `z + 1.5`, so the whole Crown floor is 1.5 m above the datum — collider
    included. Your rim profile (226/234/241 at r 0.92/0.72/0.55) is unchanged and still correct;
    `markers.py` just exports 225.5 as the walkable z so the gate does not call the Crown a hole.
1. **city-layout — connector endpoints must land on a surface the AGENT can stand on, not just
   outside geometry.** Still the sharpest problem and still unfixed: with the 4 m snap gate
   (lead r3) **100 of 144 link ends across the three classes are further than 4 m from any
   navmesh**, so only 20/48 medium links are enabled and arena -> arena stays at 14 %.
   `tools/city/nav_report.sh` prints every link left off with both distances. A medium agent
   needs 8 m of clear width and 16 m of headroom at the landing; a landing pad at each graph node
   that satisfies the agent box closes C12 and the arena graph together.
2. **city-layout — arena sockets are off the navmesh for a measurable reason, and it is the
   tier, not a hole.** `tools/city/nav_probe.sh` shows **every one of the 32 sockets has a floor
   under it**, so there is no missing geometry. What fails is:
   - **headroom**: the medium agent is 16 m tall, and sockets under a deck 8–20 m up
     (`A1_sp1` +40 m, `A2_sp5` +8 m, `A3_sp4` +16.1 m on a ramp) have no medium navmesh;
   - **tier mismatch**: `A3`'s polygon centroid lands between its sockets rather than on the
     arena floor, so the "centre" is 16 m off-mesh while `A3_sp2` is 1 m from the navmesh;
   - **hard cover**: hard cover is still 25–50 % of a tier's footprint, and at 4 m agent radius
     that closes the lanes.
   Socket -> arena centre is **small 81 % · medium 62 % · large 41 %** (gate 95 %). Sockets that
   stand on their arena's own top surface with 16 m of clear air would move this the most.
3. **city-layout — the connector keep-clear still has not moved any endpoint.** 40 of 48 arcs
   blocked, 33 starts inside built mass. Worst: the Knot helix (`con_O1_O2_edgejump`,
   `con_O2_O3_edgejump`, `con_V7_O1_edgejump`), `con_H3_A1_drop` (-520,48,330 -> -451,68,399),
   `con_U4_O7_lift` (-580,-40,-300), `con_O4_O5_stairs` (-520,32,-430). A 12 m keep-out sphere at
   each endpoint against buildings, cover, piers and tunnel linings is what closes it.
4. **Lead — C15b needs a massing decision.** 4 of 7 arena top tiers see the Spire top or the
   tether; **A2** (the Knot helix decks wrap the sightline), **A3** (-66, 40, 34) and **A4**
   (419, 32, -305) are blind. Either cap heights along those three sightlines or nominate a
   different tier as the datum for them. C15 itself is unchanged at 48.4 % (L1 29.1 %, L2+ 58.1 %),
   which you accepted in r2.
5. **city-art — the "black blob under the Crown" is yours, and it is gone from my frames.** It
   does not appear in any r3 capture and does not appear with `--blockout` (no art environment at
   all), so it came from the environment: volumetric fog or a smoke plume. For the record, my four
   `smoke_plume` slots are all at the reactor stacks (x 540–650) and none is near the Spire.
   If it was a plume, the puff-scale fix you already noted in `city_life.gd` is what removed it.
6. **Lead — V4/V5/V7 need a re-aimed `look_godot`, not a moved camera.** The ceiling problem is
   solved (0 % of the upper half blocked within 120 m at all three) and the frames are legible,
   but the declared subject is unreachable from anywhere inside the allowed search volume:
   V4's subject is 225 m away with the first block at 134 m, V7's 414 m / block 277 m, V5's
   413 m / block 317 m. Your three hints score worse than the solver's answer (V4 hint 81 %
   ceiling, V5 hint 57 % — both sit under a deck). `data/vistas.proposed.json` carries
   `subject_block_m` and `subject_dist_m` per vista so the obstruction is a number.
   V1/V2/V3/V6/V8 pass every r3 gate, with V2/V3/V6 unchanged from your adopted positions.
7. **enemies — `world.nav_ready(cls)` is true within ~30 ms of the world being built** and
   `world.nav_map(cls)` returns the per-class RID. Note the new contract: **a NavigationLink3D is
   only enabled when both its ends are within 4 m of that class's navmesh**, so a class whose
   links are mostly off (large: 6 of 48) genuinely has no lift/drop chain — plan for a snapped
   spawn rather than a path across layers. `tools/city/nav_report.sh` lists what is off.
8. **flow — `game/flow/flow_world.gd` reads `../data/map/city_layout.json` directly and logs
   `expected [x, y, z], got [-598.3, -520.0]` for every arena polygon.** It is reading 2D
   polygon points as 3D. Everything the world contract exposes is in
   `game/world/city/layout.json` (and the live nodes/groups), which may be easier to consume.
9. **boss — the Crown rim profile is fixed and the rim segments are ready.** Your probe read
   226/234/241/**248** m at r 0.92/0.72/0.55/0.80; the non-monotonic entry was the four `fins`,
   which sat at a hardcoded r 120 — between the r 126 and r 104 rim steps — so their tops stood on
   the walkable rim you break in phase 2. They are now outboard of the rim at r ~162 and nothing
   stands on the steps. The breakable ring itself is unchanged: 16 `StaticBody3D` in group
   `&"crown_rim_segment"`, each with meta `angle_deg` (0, 22.5, ... 337.5) and its own
   `MeshInstance3D`, under a `CrownRim` node at the Crown centre. Radius 150 m, z 225.5-230.5,
   material named `mc_bronze`.
10. **city-art — the podium walls you asked for are exported.** `layout.json` now carries
   `podium_walls`: 55 escarpment retaining-wall segments, each a rotated footprint in the same
   shape as a `buildings` row (`center`, `size`, `yaw_deg`) plus `base_z`, `height` and `outward`
   (the face normal away from the plateau, so a shader knows which side is facade). Merge them
   into the mask input alongside `design["buildings"]` and the A4 megablock podium gets windows at
   eye level. Caveat: the wall is `WALL_T` (6 m) thick, which is ~2 texels of your 512² mask over
   1.4 km — if that is too thin to rasterise, widen it in `FacadeMask` rather than in my geometry,
   because the 6 m is the real wall.
11. **city-art — the flat wall in every vista was mine, and it is fixed.** The C16 no-fly curtain
   (four 1 400 × 260 m collision cards) was being merged into each tile's HLOD proxy, so
   `t-1_3_hlod` was a planar 0 × 260 × 1 406 m card standing in for the city beyond 430 m. The
   curtain now collides exactly as before (C16 still PASSes) but is excluded from the proxy; the
   remaining 4-vert proxy is the visible 60 m parapet. All eight vista frames are re-shot and the
   wall is gone.
12. **city-art — two warnings per run come from `world/art/detail/city_life.gd:158-159`**:
   `Godot 3.x SpatialMaterial remapped parameter not found: distance_fade_begin` /
   `distance_fade_length`, raised from `_billboard()` for every `smoke_column`. They are 10 of the
   11 warnings in `run main.tscn 20`.
13. **city-art — `McMaterials.apply_to()` is not called anywhere.** CONTRACTS 7 says the
   environment root applies the materials to its parent's tiles on ready; nothing in
   `game/world/art/**` calls it. It works today only because `world/art/environment.tscn` has an
   `ArtIntegration` node that appeared mid-session — please confirm that is the intended owner,
   since a city with no art environment (or a failed load of one) silently falls back to flat
   blockout colours with no error.
14. **city-kit — the skin side of `data/map/kit_assign.json` is live; these are the row shapes I
    accept** (all optional except the id):
    ```json
    {"assign": [
      {"building": "D7_w000", "kit": "t01", "yaw_deg": 0, "scale": [1,1,1], "pos": [x,y,z]},
      {"kind": "deck_edge", "id": "A3_court",   "kit": "rail_a"},
      {"kind": "platform",  "id": "deck_block9_platform", "kit": "station"},
      {"kind": "railing",   "target": "via_K3_V2", "kit": "rail_b"}
    ]}
    ```
    - the id may be under `building` / `target_id` / `structure` / `target` / `id`; the kind under
      `kind` / `target_kind` / `type`, defaulting to `building`;
    - kinds I act on: `building`/`tower`/`block`, `deck_edge`/`parapet`/`railing` (parapet only),
      `deck`/`platform` (whole slab), `viaduct_edge`/`viaduct`/`barrier`/`pylon` (barriers+piers);
    - `"hide": false` opts a row out; anything I cannot read is counted and printed as skipped,
      and any id that matches nothing in the layout is printed by name — **check the SKIN line**;
    - the file is read from `data/map/kit_assign.json`; I never write it.
15. **city-kit — `res://world/kit/kit_placer.tscn` is instanced for you** by `city.gd::_kit_placer()`
    as a child named `KitPlacer`, and `setup(city: Node, layout: Dictionary)` is called if the root
    has it. It is loaded **only when `layout.json["kit_skin"]["active"]` is true**, i.e. only when
    the build actually dropped render meshes — so until `kit_assign.json` exists nothing is
    instanced and nothing is hidden. Your assign step must therefore write the file and I must
    rebuild (`tools/blender.sh run blender/city/build_city.py`) for a kit model to appear.
16. **city-kit — railings: the polylines are in `layout.json["edges"]`** (96 rows). Deck rims are
    closed rings at the deck's top `z` with `height` = the layout `parapet`; viaduct rows are the
    two open barrier lines at the deck `z` with `height` 5.0, `thickness` 2.5. Coordinates are
    Blender metres (x east, y north); `city.gd::to_godot()` converts. A row in `kit_assign.json`
    naming that deck/viaduct hides the procedural parapet so your railing replaces it.
17. **city-kit — street frontages are NOT in `layout.json`.** `edges` covers decks and viaducts
    only (what the lead asked for). For shopfront placement along L1 streets, read
    `data/map/city_layout.json["streets"]` (id, points, width, z) directly from your Python — it is
    outside `res://` and Godot cannot see it. Tell me if you want a `streets` block exported.
18. **lead — V6 is the weakest of the eight adopted vistas on r6** (`captures/city_V6.jpg`): the
    bottom half of the frame is bare deck floor, the Spire is small and hazy behind a colonnade of
    bare posts. It passes the ceiling/reach gates but reads as an empty plaza. A lower camera with
    the Spire off-centre, or foreground cover on that deck, would fix it — say which and I will
    re-solve it.
19. **city-art — your `cargo_blocks.gd` skin stands 2 cm proud of every arena cover box, so a
    `cover` row in `kit_assign.json` cannot be seen.** I now drop the render box (and its pale cap)
    for every covered piece and keep the collider and the breakable slot; with **all 1 070** pieces
    dropped the city loses 35 776 triangles and the frames change by 0.1–0.7 %, because your skin
    is drawn at the same footprint from `data/map/city_layout.json`. When city-kit's container /
    barrier models land they would be placed **inside** your skin. Please skip a piece when the
    runtime layout's `kit_skin.cover` list contains `"<arena>#<index>"` (e.g. `"A1#3"`); every
    piece also now carries an `arena_cover` prop slot with `id`, `soft`, `pos`, `size`, `yaw_deg`
    if you would rather read that than the design layout.
20. **city-kit — the cover hook is live and measured; the row shapes I accept are**
    ```json
    {"kind": "cover", "arena": "A1", "index": 3, "model": "container_stack"}
    {"kind": "cover", "id": "A1#3", "model": "container_stack"}
    {"kind": "far_lod", "id": "t0_0", "tile": [0, 0], "range": [450, 1600]}
    ```
    `cover` drops the piece's render boxes and nothing else; `far_lod` hides that 200 m tile's
    `_hlod` proxy (`City: 29 of 77 HLOD proxies stand down` today). Your `pieces` rows were being
    ignored until this round — `skin.py` did not read that key — so **74 deck parapets, 11 viaduct
    edges and 5 skybridges had a procedural box standing under your railing**. They are honoured
    now; check the SKIN line after each rebuild.
21. **lead — the perf number, honestly, on layout r7.** The world builds in **7.8–8.8 s** (gate
    10 s; it read 6.0–6.3 s in r5 on a quieter machine — the box now averages `vm.loadavg` 14–22
    with other units building, and the same build reads 7.6 s at load 14 and 10.9 s at load 22).
    Draw calls at the four measured vistas are **539–1 241 of the 3 500 budget**. Frame rate does
    NOT track them: V8 has the fewest draws (539) and the lowest prims (3.1 M) and the worst frame
    time (7 fps); V1 has twice the draws and 2.4× the prims at 21 fps. So the remaining frame cost
    is not the tiles. The chamfer was measured and is free in load time (7 723–9 426 ms without it
    vs 7 584–7 984 ms with it).
22. **city-kit — the two r8 hooks are live.**
    - `ring`: `{"kind": "ring", "index": 12, "model": "far01"}` (or `"id": "12"`) drops that box
      from `skyline.glb`. All 96 ring towers are exported in `layout.json["skyline_ring"]` as
      `{index, center, size, height, base_z, dropped}` in Blender metres, so you can place a far
      model on any of them without reading the design layout. An index past the end of
      `city_layout.json["skyline"]` is reported by name and dropped.
    - `far_lod`: a row only stands my HLOD proxy down when it carries `"gate": "pass"`
      (`hole_gate` / `status` are accepted too). Anything else is counted in
      `kit_skin.far_tiles_held` and printed by both the build and `city.gd`, and that tile keeps
      its proxy. Your 35–36 gated rows are live now.
23. **city-art — two things from the Crystal Bridge rebuild.** The bridge is now a glazed
    octagonal `mc_glass` tube (R 11, ~20 m across flats) with `mc_bronze` mullion rings every 4 m,
    eight bronze facet ribs and two `mc_up_accent` light lines along the lower flanks. In the
    blockout it reads as a dark tube; it needs your glass (transmission + a sky-catching
    fresnel) to become the "prismatic Crystal Bridge" of ART.md §4, and the bronze wants to be the
    gold of the key art. Also: the `maglev_car` slot moved from z 186 to **z 211** so the capsule
    rides inside the glass — please re-read the slot rather than the old height.

