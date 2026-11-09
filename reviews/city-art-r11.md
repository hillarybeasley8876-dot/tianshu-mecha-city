# city-art r11 — lead brief: the near kit walls read as crumpled copper foil, and the cause is the ATLAS

## What the player sees
At play distance, the big near walls of the Tripo buildings look like crumpled copper foil: smooth
light and dark wedges that run along the triangles. Storeys and panels do not read. Any street camera
shows it; it is worst at T1fac and A5deck.

city-kit r6 fixed the white sheets (the emission mask) and the speckle, and wrote plane normals into
every wall region. It believes the foil left over is your specular term washing out its 4 m grid.
**That diagnosis is wrong.**

## What the lead measured (in the game, T1fac and A5deck, `--quality=high`)
Each row turns one thing off and re-shoots the same camera.

| what was switched off | does the foil go away? | evidence in `captures/` |
|---|---|---|
| sun shadows | no | `lead_r11_shadow_ao_T1fac_A5deck.jpg` |
| sun shadows + SSAO + SSIL | no | same sheet |
| automatic mesh LOD (`mesh_lod_threshold = 0`) | no | `lead_r11_lod0_T1fac_A5deck.jpg` |
| the kit normal map + ORM (`use_normal` / `use_orm` / `use_rough` = 0) | no | `lead_r11_kit_flatmat_T1fac.jpg` |
| your window / glass layer (pane = 0 everywhere) | no | `lead_r11_kit_layers_T1fac.jpg` |
| the kit emission | no | same sheet |
| **the albedo texture** (plain white, base colour only) | **yes: one flat wall** | same sheet, last panel |
| the whole kit material (an untextured StandardMaterial3D) | **yes** | `lead_r11_kit_flatmat_T1fac.jpg` |

So the geometry, its normals, the shadows and the specular are all fine. **The foil is painted into
the albedo atlas.**

A Tripo atlas is thousands of confetti islands (look at `game/world/kit/m04/m04_m04_albedo.jpg`).
Each island carries its own value and its own baked shading. On a 140 m wall at 50 m, each texel is
about 9 screen pixels, so every triangle shows its island's patch, and the seams between islands
draw the wedges.

city-kit tried twice to repaint a facade INTO this atlas (r5 and r6). At 0.06–0.49 m per texel, cut
into islands, the atlas cannot hold a 4 m storey grid. The probes are `game/tmp_lead/kitlayer_ab.gd`
and `kitmat_ab.gd`; adopt them (step 4).

## The fix: walls take their albedo from an object-space facade in `mc_kit_body`, not from the atlas
Your shader already has the machinery. The window block (`mc_kit_body.gdshaderinc` ~line 136) builds
`u` and `y` in object space, a per-(bay, storey) cell id `cid`, the lit, tone and cool hashes, and a
pixel- and distance-based `fade`. Build the facade on that same grid.

1. **Where.** Near-tier kit surfaces where `vert > 0.35`, i.e. the walls. Roofs, soffits, ornament
   and curved parts (domes, tanks, the t01 crown) keep the atlas.
2. **Tint, not texture.** Sample the atlas at a coarse mip so each model keeps its colour identity
   without the confetti, e.g. `textureLod(tex_albedo, uv, 6.0)`. Measure which mip kills the island
   pattern.
   - Clamp the wall value to the r6 range: linear 0.15–0.30.
   - Add ±8 % per storey and a per-building offset from the `b_var` hash you already have.
3. **Structure, in metres.**
   - Slab edges every `win_floor_m` (4.0 m), 0.4 m tall, about 15 % darker.
   - Mullions every `win_cell_m` (3.4 m), 0.15 m wide.
   - In each cell, a pane rectangle inset to about 70 % × 55 %. It is the glass: dark `win_glass`,
     rough 0.13, and lit by your existing `lit` / `tone` / `cool` logic, so the night lighting keeps
     its runs and density.
   - On these walls this REPLACES `window_mask(uv, …)`, so the windows stop following the atlas
     blobs.
   - Draw the lines with `fwidth` antialiasing. Dissolve them with the same `fade` you already use,
     so nothing shimmers at distance.
4. **Metres, not model units.** `v_local` is in the mesh's own units, and the kit placer scales
   instances non-uniformly: D4_p002's m04 is scaled [1.336, 1.344, 1.0]. Carry the instance scale
   from `MODEL_MATRIX` in `vertex()`, so a storey is 4.0 m on every building.
5. **Podium.** Below `win_podium_m`, use a shopfront band: taller glazing, one dark sign band, no
   lit-window runs. Keep it simple.
6. **One switch per model.** Add a `facade_mix` uniform (0..1) and set it from `kit.json`'s band, so
   the industrial, cover and tileable bands can stay 0. Default the building bands to 1.

## Not this round
- The arena cover pieces (k01–k12, A5deck). They show the same atlas problem, but their geometry is
  also faceted. city-kit takes them next.
- `kit_placer.gd` and the glbs. Nothing here changes a glb, so your work does not touch the settle
  bake.
- `world/art/settle_cache.json`: do not re-bake or commit it this round.
  - **city-build r9 is still running.** It is rebuilding the city's tiles and will re-bake the cache
    at the end of its round.
  - If `test_settle_cache.gd` goes stale under you, that is the re-bake it still owes, not your
    bug. Note it in your status.

## Gates
1. **The flatness floor.** Re-run the lead's probe on T1fac: as shipped against the plain-albedo
   panel.
   - Low-pass both near-wall crops (Gaussian σ = 12 px) and compare the luminance std.
   - Yours must be at most 1.5× the plain-albedo version; today it is far more. Print both numbers.
   - The facade grid is high-frequency and does not count against this; the wedges do.
2. **The read.**
   - In 2× crops of the T1fac and A4st near third, storeys and windows read, and no wedges are left.
   - The same crop at the night setting, if `TimeOfDay` has one: the lit runs look like a building,
     not confetti.
3. **No shimmer.** A 4 s camera dolly past T1fac (`tools/godot.sh movie` or `drive`) shows no crawling
   lines.
4. **Cost.**
   - Frame time at the A1 spawn: `tools/godot.sh perf --skip-menu --no-enemies --warm=40
     --spawn=-583,16,640,-37.5`, the same draws.
   - The vistas `--art-perf`, against r10b.
   - Note the machine load next to each number; another project's iOS simulator is sometimes running.
5. **Evidence for the user.** The 7 street cameras, before and after, as one sheet.
6. **Adopt the probe.** Move `game/tmp_lead/kitlayer_ab.gd` / `kitmat_ab.gd` into
   `world/art/tests/probe_kit_layers.gd` (one script).
   - Restore every material between cameras: the lead's version does not, so only the FIRST camera
     of a run is valid.
   - Delete `game/tmp_lead/` in the same commit.

Commit per step with an explicit path list. Report in `status/city-art.md` (an r11 section).
