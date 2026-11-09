# Brief: city-art — materials, lighting, atmosphere, props, holograms, district dressing, vistas

## Goal
Make the city look like the key art (`art/concept/keyart/v1_pier-1.png`, `v2_canyon-1.png`,
`v3_oldtown-1.png`, `v8_crown-1.png`): a golden-dusk Chinese neo-futurist megacity with layered haze, lit
windows, restrained neon, rich street/rooftop detail, distinct districts and a storm-violet crown — at 60 fps
on the M1 Max. You own every pixel of the environment that city-build's geometry does not.

## Read first
`docs/ART.md` (ALL — it is your bible), the key art images above, `ref/images/city-art-direction/` and
`ref/research/city-art-direction.md` when present, `ref/research/godot-tech.md` §4 (lights, shadows, GI,
fog, culling, pitfalls) and §6 (post recipes), `docs/MAP.md` (districts, vistas), city-build's
`status/city-build.md` (material names `mc_*`, markers), `data/props_list.json` + `art/tripo/` (prop models
the lead generated: `prop_<name>/model.glb`).

## You own
`game/world/art/**` (environment, materials, shaders, time-of-day controller, post), `game/world/props/**`
(prop scenes + placement), `blender/props/**` (prop processing), `tools/textures/library` additions via
`tools/textures/fetch.py` (CC0 only).

## Build
1. **Environment** (`world/art/environment.tscn` instanced by `world/city.tscn` — coordinate the one-line
   instancing with city-build via status): sky (physical sky or Poly Haven dusk HDRI + a skyline-ring
   gradient), sun per ART §3, fog/volumetric fog/height fog, SDFGI by quality preset, SSAO/SSIL/SSR,
   reflection probes per arena, glow, AgX + colour grade, exposure. **TimeOfDay** controller with
   `set_progress(p: float)` (0 = start, 1 = boss) driving sun elevation, haze colour, window-lit fraction,
   storm coverage + lightning around the Spire crown; quality presets low/medium/high.
2. **Materials** (replace city-build's `mc_*` by name): stone/concrete/panel/metal/bronze/terracotta PBR from
   the CC0 library with triplanar or metre-UV mapping, macro variation (noise tint, dirt by AO/height,
   rain streaks), glass (dark, sky-reflecting, roughness variation), road with lane markings + crossings
   (decals or shader), deck surfaces, water (canal: reflections, slow waves, foam at banks), `mc_window`
   emissive shader (random lit cells per building, warm/cool mix, flicker rare, `lit_fraction` uniform from
   TimeOfDay, optional interior-mapping depth), `mc_up_accent` cyan pulsing.
3. **Props**: process the lead's Tripo props (decimate to budgets: vehicles ≤ 15k, street ≤ 5k, rooftop ≤ 8k,
   statues ≤ 40k; textures 1–2K; emissive masks for their light strips), place them by rules per district
   (sidewalk furniture every 18–30 m, parked/stalled vehicles along streets, rooftop machinery on every
   tier B–D roof slot, lanterns + stalls + blossoms in Old Town, containers + cranes in Harbor, pipes +
   tanks in Foundry, statues + lions on the Spire Plaza) using MultiMesh per tile; the koi-dragon hologram
   circling Block 9 (hologram shader: additive cyan/magenta, scanlines, fresnel, flicker) + 6–10 holo
   billboards with fictional Chinese/English brand graphics you generate procedurally (no real brands).
4. **Infection creep**: decal/triplanar overlay (chitin + glowing acid-green veins) around each hive site
   and on 10–15 % of buildings near arenas; intensity parameter for the flow unit (spire destroyed → recede).
5. **Detail layers**: decals (grime, cracks, oil, scorch, road markings), cables between buildings,
   banners/laundry (Old Town), steam vents (Foundry), birds/drones flocks (cheap particles) for life,
   smoke columns from reactor stacks.
6. **Performance**: ≤ 3,500 draw calls and ≤ 16.6 ms frame at every vista on high; low preset ≥ 60 fps.

## Notes from the lead
- **Start now, in two phases.** Phase 1 (city-build is still building the kit): environment + TimeOfDay in the
  sandbox, a test street of your own in `world/art/tests/` (primitives + a few city-build kit pieces when they
  land), the `mc_*` material library by name, the window shader, the hologram and creep shaders, and the Tripo
  prop processing + prop scenes. Phase 2 (when `status/city-build.md` reports tiles): instance the environment
  in `world/city.tscn`, prop placement rules per district, the vistas, perf.
- Hooks are contracts now (CONTRACTS §7 "Environment hooks"): group `&"time_of_day"` with
  `set_progress(p)` / `set_storm(amount, s)` / `lightning_at(pos)`; group `&"infection"` with
  `set_intensity(site_id, value, s)`. The flow unit already calls `set_progress` through the group.
- Vista cameras come from `data/vistas.json` (lead-owned, Godot coordinates included). Sun, GI A/B and fog
  numbers are in ART §3 — follow them, then judge against the key art.
- Signature images to sell in dressing: the Liziba-style towers the Skyrail/Ring Viaduct pass through (D7/D5),
  the circular Crown, the Civic Quarter backdrop behind the Spire (layout r3), Block 9's rail hole + koi
  hologram, the Old Town silhouette against the NW sun.

## Done when
- `tools/godot.sh check --only=res://world/art/,res://world/props/` → 0 errors.
- Vista captures `captures/art_V1..V8.jpg` (+ the same at progress 0.5 and 1.0 for V1, V6, V8) and a 60 s
  flythrough movie. Put each next to the matching key art in a sheet and judge honestly: focal point,
  depth layers, haze, light, colour, detail density, district identity. Iterate until they read as the
  same world.
- `tools/godot.sh perf --skip-menu` numbers at each vista in status (draw calls, primitives, frame ms).
