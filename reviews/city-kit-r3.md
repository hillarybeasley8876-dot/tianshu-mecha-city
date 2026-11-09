# city-kit — review r3 (lead): the near tier is not foil anymore; it is black chrome now

## What is right (keep all of it)
- **The custom split normals are a real find.** `common.smooth()` never did anything, and every model
  shipped the collapse's per-facet normals. 58 of 58 cleared.
- **The grade is measured, and the roughness is remapped rather than clamped.** The ORM data is now
  right: t01 ORM green median 0.60, p5 0.55, p95 0.71 (lead re-measured from the shipped jpg).
- **The kit has never had a lit window** before this round, and `carve_panes` fixes that. The
  `Image.copy()` trap and the 13 MB jpeg are good catches.
- **The far gate was measuring the building, not the sky.** That is a good catch, and closing r2
  item 3 without spending credits is the right call.

## MUST-FIX — the near tier still does not read as part of the same city (impact 9)
Look at your own `kit3_AB.jpg` rows A5deck (row 5) and A3st (row 1), and at
`captures/kit3_st_A5hive.jpg`, `kit3_st_A5deck.jpg` and `kit3_st_T1fac.jpg` at full size:
- The megablocks read as **wet black chrome**: dark walls covered in bright, curved, smeared streaks.
- The cover runs (A1yard, A5deck) read as glossy black boxes with flickering highlights.
- T1fac's towers read as polished copper: hot streaks that wander across every face.

The blockout next to them reads as matte concrete. The kit now looks like a different, glossier
material from a different game.

**The lead isolated the cause by switching shader layers off one at a time, on a scratch copy of
`mc_kit_body.gdshaderinc` (restored after each run, never committed).** The composite is
`tmp/lead/kit_layers_ab.jpg`; the other A/Bs are `tmp/lead/kitglass_ab.jpg` and
`tmp/lead/kitnonorm_ab.jpg`.

| test (T1fac / A3st) | effect on the chrome streaks |
|---|---|
| window glass roughness 0.13 → 0.35, metal 0.70 → 0.10 | none |
| normal maps OFF | almost none |
| window **emission** OFF | the dark-wall streaks drop a lot; the hot copper streaks stay |
| flat grey 0.30 albedo + no windows | **the streaks are still there**: a plain grey wall still shows hot curved bands |

So two causes remain, and neither is the ORM.

### 1. The surface is still a wobbly height field. Smooth shading turned facets into ripples.
Smoothing by angle (40°) over a 0.15 collapse of a Tripo surface reconstruction keeps every bump of the
reconstruction noise. Smooth shading now interpolates across those bumps. At golden-hour grazing light
(sun at 20° → 6° over the spires), each 10 cm wobble on a 30 m wall becomes a bright or dark band, even at roughness 0.6.
That is the "flat grey albedo" row: no texture, no windows, still streaks. In r2 the facets were hard;
now they are soft ripples. Same noise, different look.

Fix, per model, in `process.py`, before the export:
- **Flatten what should be flat.** Run a planar pass on near-planar regions: `bmesh` region growing by
  normal (≤ 6°) plus least-squares plane projection of those vertices, or Blender's
  `bpy.ops.mesh.dissolve_limited(angle_limit≈5°)` followed by a re-triangulation. A wall should end up
  as one plane, not 4,000 slightly different ones. Report the share of area that ended up planar per
  model.
- **Then weighted normals** (the `WEIGHTED_NORMAL` modifier with face-area weighting and *keep sharp*,
  applied with a 30° sharp-edge mark). Normals on a planar region become exactly the plane normal, so
  the grazing sun lights the wall as one value.
- Gate: lit studio render at a **grazing key (sun 6–20° elevation, raking along the wall)** for t01,
  b01, o01, s04, k02 and k06, flat grey material. A plain wall must read as one flat value with no
  bands. Put it next to the same render of the r3 export.

### 2. The window layer lights noise, not windows.
`carve_panes` pushes the darkest 7–17 % of each atlas into the pane band. On a Tripo atlas, the darkest
texels are not windows: they are crevices, AO creases and seam noise (`tmp/lead/alb_sheet.jpg`: the
atlas is a confetti of tiny islands). The shader then lights them warm/cool at 1.7 gain, and you get
glowing scribbles that follow the mesh wobble, which reads as reflections on chrome.

Fix:
- **Rule: a pane must be a rectangle on a vertical face.** Carve panes from geometry, not darkness.
  After the planar pass, project each large vertical planar region's UV island to its real-world size.
  Keep only the dark connected components that are window-shaped, from a 0.6 m × 0.8 m minimum up to
  storey size, with aspect between 0.3 and 3. Write them to an explicit `win_mask` texture: the shader
  already supports `win_mask_from = 1`. Blobs, slivers and crevices are not windows.
- Alternative, if that costs too much: switch the kit to the shader's procedural grid
  (`win_cell_m` / `win_floor_m`) on planar vertical regions only, masked by a coarse "this face is a
  facade" mask. Mid-tone texels never become panes.
- Gate: the share of pane texels that sit in components smaller than 0.5 m² must be under 10 %. Show
  `kit3_st_A5hive` and `A5deck` before and after.

### 3. Cover kit: the colours are right, the material is not
In A1yard and A5deck the cover reads as glossy black panels. The k-series grade pushed them to a
weathered-industrial tint, but at the in-game distance they go nearly black with mirror-like
highlights. Apply both fixes above to the cover models. Also lift the cover median albedo to the
ART.md warm-concrete band (around #A9A196 at 50–60 % in the lit areas). The player fights next to
these, and they must read as dirty painted steel and concrete.

## Done means
- The street sheet (same 7 cameras) re-shot, plus the A/B with `--no-kit`. No frame reads as chrome,
  foil, or wet black glass, and the kit looks like the same material family as the blockout and
  city-art's surfaces.
- The grazing-light studio gate above passes for the six named models.
- `kit3_st_A5hive` / `A5deck` / `T1fac` re-shot from the same cameras.
- Perf at the A1 spawn: report it, and keep the kit's own cost at ≤ 98 draws (planar regions should
  lower the prim count; report that too).

## After that (unchanged order)
1. D3 old-town variants (≈ 4 models): a foundry hall and an archive in the old town is an
   art-direction bug.
2. Model backs.
3. The 2K → 1K albedo for towers/megablocks is approved if VRAM is still over 1 GB after the above.
