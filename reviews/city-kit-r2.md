# city-kit — review r2 (lead) — far tier PASS; the near tier reads as crumpled foil

## Verdict: far tier, weld, perf, cover fit: PASS
- The weld diagnosis went one level deeper than the lead's (the shredding was already in the detail tier: 3,700 UV
  islands per model; the importer's own option does not weld a Blender-written glb, so an explicit `remove_doubles`
  is needed). All 57 models are reprocessed with `open=0, kept=1`.
- The silhouette gate measures the far mesh against the detail mesh, not against zero: right for open galleries and
  tunnels. The three failing models draw no far batch rather than a bad one.
- Perf: **26 fps with the kit vs 22 without** at the A1 spawn (was 16), prims 10.9 M → 6.6 M, with each of the four
  cuts measured. Good work.
- Cover: 539/539 boxes covered on the new layout, both fit rules asserted (0 violations).

## MUST-FIX — the near tier reads as crumpled silver foil (impact 9: it is what the player stands next to)
Evidence: your own `captures/kit2_street_sheet.jpg` (A3plaza, A4canyon: sheets of shattered chrome-white
triangles), the lead's `tmp/lead/lk.jpg` (`lk_kit_A3st` / `lk_kit_A4st`, same cameras with `--no-kit`), and studio
renders of the most-used cover models `tmp/lead/kit_cover2.jpg` (k06 truck, k02 tanks, k11 rubble, k07 transformer):
- **Colour**: everything is near-white/silver. The cover models, u01 fascia and much of the kit are pale grey-white
  with faint grime, where the city palette is warm concrete, rust, dark steel and the key-art amber. At dusk, white
  sheets bloom and read as foil.
- **Roughness**: your models' ORM medians are glossy: k02 0.19, t01 0.11, k06 0.28, k07 0.36 roughness. A glossy
  white Tripo surface with faceted geometry mirrors the bright sky in every facet, which is the "shattered chrome"
  look. Weathered concrete and painted steel should sit at 0.55–0.85.
- **Faceting**: the welded collapse leaves large flat facets with hard shading on curved forms (the tank, the truck
  cab, the rubble). Smooth shading with an auto-smooth/weighted-normal angle (~40°) would read as forms, not origami.
Fix (per model, in the processing step, verified with lit close-ups like `captures/kit/<id>.jpg` plus an in-game
street pair):
1. **Roughness floor** in `process.py`: remap ORM.g to `max(g, 0.55)` (glass/neon masks may stay glossy if you can
   isolate them; most of these models have no glass), metallic capped at 0.3 except clearly metal props.
2. **Albedo grade toward the palette**: measure each model's median albedo luminance and saturation. Pale models get
   a per-model grade (darken to the city's median value, multiply toward a warm-grey/rust tint by band: cover =
   weathered industrial, street = painted/dirty), so a white truck becomes a dirty off-white truck in shadow, not a
   bloom source. Report before/after medians like monster-assets did (`mon_emit.median_luma`).
3. **Normals**: weighted normals / smooth by angle after the collapse.
4. Re-shoot the street sheet (same 6 cameras) and the A3/A4 pairs (`--cams="A3st:-40,14,170:30,20,90:60;A4st:420,46,-380:500,50,-460:60"`)
   with and without the kit. Done when no frame reads as foil or paper, and the kit looks like part of the same city
   as city-art's materials.

## Next, in order
1. The near-tier fix above (all models: buildings, pieces and cover).
2. D3 old-town variants (~4 models): a foundry hall and an archive in the old town is an art-direction bug.
3. l01/s02/m05 far meshes via voxel remesh + bake.
4. Model backs (item 5).
Budget remains: 13,101 credits; stay inside the 4,500 wave budget (1,170 spent).
