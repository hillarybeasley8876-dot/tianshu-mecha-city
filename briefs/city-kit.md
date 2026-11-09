# Brief: city-kit — a Tripo-built architecture kit that skins the whole city (no more "building blocks")

## Why
The user played the build: "场景一点也不精致 … 现在场景和搭积木有什么区别". They are right: every building, deck,
railing and podium is a procedural box with a shader. The fix is real 3D architecture from Tripo3D (Studio web
credits, 17,131 left, expire 2026-11-29) — detailed towers, megablocks, old-town houses, civic halls, street-level
shopfronts, railings, skybridges — fitted over the blockout. **Collision, navmesh and gameplay stay exactly as
they are** (the boxes remain as invisible colliders/occluders); only what the player SEES changes.

## Read first
`docs/ART.md` (palette, district identity), `art/concept/keyart/*.png` (the target), `docs/MAP.md` §3–4 (districts,
archetypes, heights), `data/map/city_layout.json` (buildings: district, archetype, tier, size, height, rot,
base_z, fronts, holes), `tools/tripo/API.md` + `tools/tripo/studio.sh` (img2model / wait / fetch / remesh;
registry `art/tripo/jobs.json`; ONE operation per project, never retry a creating POST after a transport error),
`tools/concept/ys.py` + `batch.py` (ys-api, model `gpt4o`), memory notes in `reviews/city-kit-lead.md`,
`status/city-build.md`, `status/city-art.md`, `game/world/city.gd`, `game/world/art/material_library.gd`.

## You own
`blender/citykit/**`, `game/world/kit/**`, `tools/citykit/**`, `data/map/kit_assign.json`,
`art/concept/citykit/**`, raw Tripo downloads under `art/tripo/kit_*` (git-ignored binaries).

## Budget and safety
- Tripo: **≤ 6,000 credits this wave** (image→model ≈ 65 each). Log every call (name, task id, credits) in your
  status. Max 2 regenerations per asset. Check `tools/tripo/studio.sh balance` before and after each batch.
- Run at most 4 Tripo generations at once; never two operations on one project.

## Build
1. **Concepts** (`art/concept/citykit/`): one image per asset from the list below with `tools/concept/batch.py`
   (`--model gpt4o`, 2 candidates each, pick the best by LOOKING at them). Prompt rules for image→model: the whole
   object, isolated on a plain light-grey background, three-quarter view from slightly above, no ground plane,
   no other buildings, no people/cars, crisp edges; style: "golden-dusk Chinese neo-futurist megacity, white
   stone and pale concrete, dark glass, bronze accents, restrained cyan/red neon signs with fictional Chinese
   brands, Chongqing/Shanghai density" + the asset line. Proportions in the prompt (e.g. "height 5× its width,
   rectangular footprint, straight vertical walls") so the model fits its box with little distortion.
2. **Tripo**: `studio.sh img2model kit_<id> <image>` (default H3.1, 4K textures), `wait`, `fetch`.
3. **Blender processing** (`blender/citykit/process.py`, deterministic, ≤ 400 lines per file): Y-up, pivot at the
   footprint's base centre, unit-normalised so the kit stores the native size; delete floaters/ground plates;
   decimate to LOD0 budgets (towers/megablocks ≤ 40k tris, mid-rise ≤ 25k, old town / civic ≤ 20k, street pieces
   ≤ 12k, tileables ≤ 6k); textures 2K (towers, megablocks) / 1K (the rest); a window-emission mask derived from
   the albedo (dark glass panes → lit at the TimeOfDay lit fraction, warm/cool by hash); export
   `game/world/kit/<id>/<id>.glb` + a `kit.json` row (native size, footprint, district tags, height band, tris).
4. **QA gate per asset** (lead memory: audit mesh integrity, not only textures): 4 lit angles + top in one sheet
   `captures/kit/<id>.jpg`; reject fused/melted geometry, holes, floating junk, baked-in ground, blurry textures;
   regenerate (≤ 2) or drop. A `captures/kit/_lineup.jpg` of everything at true relative scale.
5. **Fitting** (`tools/citykit/assign.py` → `data/map/kit_assign.json`): for every layout building pick a kit model
   by district + archetype + height band + closest aspect ratio; scale to the building's box with anisotropy ≤
   1.3 per axis (else pick another variant or stack two); rotate so the model's front faces the building's
   `fronts` street; neighbours never repeat the same variant; buildings with `holes` (arcades, the rail through
   Block 9, the Liziba towers) keep their procedural mesh unless a kit model has the opening. Street pieces:
   shopfront podiums along every L1 street frontage within 150 m of an arena or the Spire plaza, railings along
   every deck/viaduct edge (replacing the brown box fence), pylons under viaducts, paifang gates at district
   entries, skybridge segments where the layout has skybridges.
6. **Godot** (`game/world/kit/kit_placer.gd`, instanced by `world/city.tscn` — coordinate the one line with
   city-build): MultiMeshInstance3D per (model, tile) with `visibility_range_end` and the HLOD swap at 450 m
   (Godot auto-LOD on import ON), shadows on for LOD0 only. Materials: ask city-art for `McMaterials.kit(src)` —
   their haze include + the window mask emission on your glTF textures — and use it (fallback: the imported
   StandardMaterial3D) so kit buildings sit in the same atmosphere as the rest.
7. **city-build** hides its procedural render mesh for every building in `kit_assign.json` (collision + occluder
   stay) — the lead routed that to them; until it lands, verify with `--kit-only` in your own test scene.

## Asset list (wave 1 — 40; you may add ≤ 8 if a district clearly needs it)
| id | district / use | description (add the style line) |
|---|---|---|
| t01 | D7 tower 160–240 m | glass supertall with stepped setbacks, sky-garden terraces every 40 m, a crown shaped like a stylised pagoda roof |
| t02 | D7 tower | twisted glass tower, vertical LED fins, bronze base podium |
| t03 | D7 tower | slender tower wrapped in a white diagrid exoskeleton, gold accents, antenna spire |
| t04 | D7 tower | twin cores joined by two glass skybridges near the top |
| t05 | D7 tower | tower with cantilevered sky-garden boxes and a glowing halo ring at the crown |
| t06 | D7/D4 tower 128–176 m | slab office tower, vertical fins, rooftop helipad and antenna cluster |
| m01 | D5 megablock 128–200 m | massive residential megablock: stacked balconies, AC units, laundry, vertical neon signs (Kowloon-futurist) |
| m02 | D5 megablock | megablock around a central void with skybridges and green terraces |
| m03 | D5 megablock | stepped terraced megablock with giant billboards |
| m04 | D5 Block 9 | megablock slab with a large rectangular tunnel opening through its middle for a train |
| c01 | D4 civic 40–80 m | neo-Chinese civic hall, sweeping curved roof, white colonnade |
| c02 | D4 civic | archive block with a bronze lattice screen facade |
| c03 | D4 podium tower 96–144 m | tower on a podium with a giant gate motif and setbacks |
| c04 | D4 civic | terraced museum hall with roof gardens |
| b01 | D2/D4/D7 mid-rise 48–96 m | apartment tower, balconies, rooftop water tank, neon sign |
| b02 | mid-rise | hotel tower with a tall vertical neon sign and a crown light |
| b03 | mid-rise | office mid-rise with vertical fins and a glass corner |
| b04 | mid-rise | mixed-use block, shop podium, terraces with trees |
| b05 | mid-rise | stacked capsule housing with modular pods |
| o01 | D3 old town 16–56 m | Chongqing stilt house (diaojiaolou) stacked on a slope, grey tiled roofs, red lanterns |
| o02 | D3 | terraced shop-houses with wooden balconies and red lanterns |
| o03 | D3 | narrow six-storey tenement, tiled roof, laundry lines, AC units |
| o04 | D3 | teahouse with upturned eaves and a balcony walkway |
| o05 | D3 | cluster of stacked hillside homes with stairs between them |
| o06 | D3 | market hall with tiled roof and neon signs |
| h01 | D1 harbor | port warehouse with a gantry crane rail and roller doors |
| h02 | D1 | port office tower 48–64 m with a control room top |
| h03 | D1 | customs hall with a sawtooth roof |
| f01 | D6 foundry | industrial hall with a sawtooth roof and pipe racks |
| f02 | D6 | reactor building with domes and vents |
| f03 | D6 | pipe-rack bridge structure (long, tileable) |
| f04 | D6 | cooling tower and chimney cluster |
| s01 | L1 street | shopfront podium block (2–3 floors): arcade, awnings, neon signs, shop windows |
| s02 | L1 | metro station entrance with a glass canopy |
| s03 | L1 | street-market stall row with umbrellas and signs |
| s04 | L1 | neo-futurist paifang gate (Chinese memorial arch) with lights |
| s05 | under viaducts | elevated-highway pylon with lights and cable trays |
| s06 | skybridges | glass skybridge tube segment with a steel frame (tileable, straight) |
| s07 | deck/viaduct edges | futuristic guardrail segment with light strips (tileable, straight, 12 m) |
| s08 | roofs | rooftop machinery cluster: AC units, tanks, antenna mast |

## Done when
- ≥ 36 kit assets pass QA (sheets in `captures/kit/`), `kit_assign.json` covers ≥ 90 % of buildings,
  `tools/godot.sh check --only=res://world/kit/` 0 errors, a test of the assignment rules (anisotropy, front facing,
  no repeated neighbours, holes respected).
- In the city (after city-build's skin mode): the 8 vistas + 6 street-level shots (A1, A3 plaza, A4 canyon, A5
  deck, A6 Sky Garden, the user's spot near the A5 hive) side by side with the key art, honestly judged; perf at
  every vista ≤ 3,500 draws and ≤ 16.6 ms with `--stub=flow`; VRAM reported.
