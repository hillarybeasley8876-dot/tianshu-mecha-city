# Brief: city-build — Escarpment City geometry, collision, navmesh, world scene

## Goal
Build the city in Blender exactly from `data/map/city_layout.json` (validated by city-layout) and assemble
it in Godot as `world/city.tscn`: every street, viaduct, rail, tunnel, deck, cliff, building and connector
as clean modular geometry with correct collision, occluders, navmeshes per agent class, navigation links,
markers, and the Godot-side checks C12–C17. Look: structurally rich and true to ART.md massing, ready for
city-art to dress (materials by role, UVs in metres, emissive-window UVs).

## Read first
`docs/MAP.md`, `data/map/city_layout.json` + `level_graph.json` + city-layout's `status/city-layout.md`,
`docs/ART.md` (§4 architecture language, §6 performance rules, key art `art/concept/keyart/`),
`ref/research/level-design-vertical.md` §3.2, §3.4, §5.1–5.5 (Godot probes), `ref/research/godot-tech.md`
§2.3, §3, §4.3–4.6 (collision suffixes, navmesh baking, culling/HLOD, chunking), `ref/research/
city-art-direction.md` (building kit, when it exists), `blender/lib/*` (export helpers).

## You own
`blender/city/**`, `game/world/city/**`, `game/world/city.tscn` (+ its script), `tools/city/**`.

## Build
1. **Kit** (`blender/city/kit/`): parametric builders, deterministic by seed, each ≤ 400 lines:
   building archetypes (slab, setback, podium_tower, twisted, megablock, industrial, terrace, warehouse,
   pagoda base, stack) on a 4 m floor module with window bands, fins, balconies, cantilevered sky gardens,
   stepped crowns, rooftop parapets 4–6 m and rooftop machinery slots (markers for city-art props);
   decks/viaducts (deck slab + barriers + pylons every 48 m + undersides with beams), skyrail beams,
   tunnels (lined, lit niches, portals), terrain (escarpment retaining walls + terraces + lips, canal with
   banks and water plane), connectors (ramps with railings, stairs as terraces, lift shafts + platforms,
   catapult pads, vent shafts — all with the cyan "up" accent material slot), landmarks per MAP §4 (the
   Spire with collar/roof/crown decks and a light tether, the Knot, Crystal Bridge, reactor Stacks, Block 9
   with the rail hole) — Tripo props/statues are placed by city-art, leave markers.
2. **Materials by role** (names exactly): `mc_stone`, `mc_concrete`, `mc_glass`, `mc_panel_white`,
   `mc_metal`, `mc_bronze`, `mc_road`, `mc_deck`, `mc_terracotta`, `mc_window` (separate faces with UVs
   0..1 per window cell for the emissive shader), `mc_up_accent`, `mc_water`; UVs in metres (box mapping)
   except `mc_window`. city-art replaces these materials in Godot by name.
3. **Export**: per district/tile chunks ≤ 60 m footprint for structures, merged per material; collision as
   simplified `-colonly` boxes/hulls (never the render mesh for buildings), `-occonly` occluders for big
   facades/decks; skyline ring as low-detail `-noimp`-free meshes without collision; HLOD proxy per 200 m
   tile (VisibilityRange swap at 450 m). Use `blender/lib/export.py` (shared texture dir for tiles).
4. **Godot world** (`world/city.tscn` + `city.gd`): instance tiles + landmarks; markers: `PlayerSpawn`,
   group `&"spawn_zone"` (Area3D + `zone_id`), `&"arena"` (Area3D + `arena_id`), `&"landmark"`,
   `&"anchor_node"` (Marker3D with normal), `&"hive_site"`, `&"vista"` (Camera3D V1–V8 placed from the lead's `data/vistas.json`); navmeshes baked OFFLINE by a tool script
   (`tools/city/bake_nav.gd`, headless) for agent classes small r 1.5 / medium r 4 / large r 9 from colliders
   only, saved as resources, each on its own navigation map; NavigationLink3D for every non-walk graph
   edge; `nav_map(class) -> RID`; `Game.mark_world_built()` when ready (< 10 s load on this Mac).
5. **Checks** (`tools/city/checks.gd`, headless where possible): C12 trajectory sweeps (capsule r 4 h 16,
   gravity 25.5), C13 headroom/width on navmesh samples, C14 sightlines/cover per arena, C15 Spire
   visibility ≥ 80 %, C16 boundary + ceiling, C17 1,000 random max-boost jumps land on mapped surfaces.
   Plus perf: `tools/godot.sh perf --skip-menu` at V1–V8 → draw calls, primitives, frame time.

## Notes from the lead
- **The layout keeps evolving while you build** (city-layout r3 runs in parallel: Civic Quarter on the D4
  plateau, viaduct/rail-through towers in D7, fewer free canopies, D3 terrace masses, a sky graph). Build ONLY
  from the JSON, never hand-place; `build_city.py` must rebuild everything from scratch, idempotently, and per
  district (`--district D5`) so a layout change costs minutes. Start with what will not change: the kit,
  terrain/escarpment/canal, the Spire + Crown, viaducts/rails/tunnels, D5, D1, D2.
- **v2 fields you must honour** (MAP §3): `podium_z` (podium top; the tower rises from it), `holes`
  (arcade / corridor-through boxes cut out of the mass: `polygon` × `z`…`z + height` — real openings with
  lit soffits and columns, collision too), `through` (corridor ids passing through), `fronts` (kerb lot:
  entrances, shopfronts and the busiest window bands face that street), `carries` / `span` / `columns` /
  `supported_by` (every deck visibly supported: pylons with capitals, brackets into facades, span trusses),
  `skybridge`, crown `rim_steps` / `fins` / `core` / `holes`, `canopy`, `under_clear`.
- **Sky graph**: export `sky_waypoints` + `sky_edges` (r3) as Marker3D in group `&"sky_waypoint"` and an
  AStar3D behind `world.sky_path(from: Vector3, to: Vector3) -> PackedVector3Array` (CONTRACTS §7); if the
  file has no sky graph yet, return `[from, to]` so callers keep working.
- **Facade language** (ART §4): base / shaft / crown on every C/D building, 4 m floor module, vertical fins and
  horizontal bands alternating by district, emissive window cells on `mc_window` only (city-art animates
  them), stepped crowns and lit parapets on towers; D3 terraces stepped with balconies that read as stairs.
  Judge each archetype in a Blender close-up render before mass-producing it.
- **Performance from day one** (ART §6): merged per material per tile, `-colonly` boxes, occluders on big
  facades/decks, VisibilityRange + HLOD per 200 m tile, skyline ring without collision or shadows; print
  tris/draws per tile.

## Done when
- `tools/blender.sh run blender/city/build_city.py` rebuilds everything from the JSON (prints counts per
  district/material, tri totals, export sizes, time).
- `tools/godot.sh check --only=res://world/` → 0 errors; `tools/godot.sh run res://main.tscn 20` loads the
  city (world built < 10 s), 0 errors; the mech-move player can walk the start pier → A1 → Knot ramps.
- Checks C12–C17 PASS (print the numbers); perf at every vista ≤ 3,500 draw calls, frame ≤ 16.6 ms with
  the default sandbox-like lighting.
- Captures `captures/city_V1..V8.jpg` + 8 aerial overviews + a 60 s flight movie along the Ring Viaduct and
  the skyrail. Compare with the layout plan and the key art massing; report honestly what looks weak.
