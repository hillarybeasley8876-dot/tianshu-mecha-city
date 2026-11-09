# Brief: post-render — the cinematic rendering pass (post-processing, grade, lens, AA, GI, shadows)

## Why
User feedback after playing: "后处理 渲染 滤镜什么的也要加强啊" (on top of "the city looks like building blocks").
Today's frame is flat: AgX at exposure 1.28 over a beige depth fog, glow threshold 1.45 so almost nothing blooms,
volumetric fog barely visible, no lens character, TAA alone (soft and smeary), no GI by default, SSR rarely
visible. The key art (`art/concept/keyart/*.png`) is filmic: deep contrast, warm highlights rolling off into
gold, cool shadows, haze layers with god rays, wet reflections, bloom halos on every light, slight lens
character. This unit owns turning the renderer into that — at 60 fps on the M1 Max (1600×900, high).

## Read first
`docs/ART.md` §3 (lighting, GI plan, fog numbers), `game/world/art/environment.gd`, `time_of_day.gd`,
`quality.gd`, `material_library.gd`, `shaders/mc_haze.gdshaderinc` (city-art's), `game/fx/screen_fx/**`
(feel's gameplay post: flash, chromatic, radial blur, speed lines, impact frame — do NOT duplicate those),
`ref/research/godot-tech.md` §4 (lights, shadows, GI, fog, culling, pitfalls), `game/project.godot`
(rendering section — lead-owned; request changes in your status with exact keys and values),
the key art, the user's screenshot `tmp/lead/user_shot_1.png`, recent captures `captures/art_V*.jpg`.

## You own
`game/world/post/**` (new): the cinematic grade and lens stack (a `Compositor` + `CompositorEffect`s), presets,
tests, `captures/post_*`. Renderer settings that live in city-art's files (`environment.gd`, `quality.gd`,
materials) or in `project.godot` (lead): write the exact changes as a patch list in your status, measured, and
the owner applies them. The environment exposes `CityEnvironment.compositor` (ask city-art) — attach your stack
there.

## Build
1. **Lens & grade stack** as a Godot 4.7 `Compositor` with `CompositorEffect`s (RenderingDevice compute,
   post-transparent), each toggleable and preset-driven (low/medium/high), in `world/post/`:
   - **Filmic grade**: a 32³ LUT built from the key art (fit the in-game V1/V2/V8 render → key-art colour
     transfer per luminance band: shadows cool teal-violet, mids neutral warm, highlights gold, a gentle S-curve),
     plus a separate storm grade (progress ≥ 0.66) blended by TimeOfDay progress.
   - **Bloom that reads**: lower the HDR threshold so windows, neon, accents, the tether, muzzle flashes and the
     sun bloom with wide soft halos (a dual-filter/Kawase bloom effect with 6+ mips and a dirt-free lens), while
     sunlit concrete never blooms.
   - **Lens**: subtle vignette (corners −15 %), very light chromatic fringe at the edges only (≤ 1 px, off in
     photosensitive), anamorphic horizontal streaks on the brightest sources (neon, tether, sun), fine film grain
     (≤ 2 %, animated), sharpening (CAS or FSR-RCAS) to undo TAA softness.
   - **Sun shafts / god rays** in screen space from the sun position (radial blur of the bright sky mask), on top
     of volumetric fog — gold shafts through the canyons as in `v2_canyon-1.png`.
   - **Depth of field** only for cinematics (drop-in, collapse, boss intro/death): bokeh far blur, never in play.
2. **Renderer tuning** (patch list for city-art / lead, measured A/B with captures, each at 60 fps):
   - AA: TAA + your sharpening; or FSR2 quality at 1.0 scale; decide by captures (moving camera + still).
   - Shadows: 4 splits, 4K, soft PCF high, contact shadows on the hero; a cascade blend so no visible seams.
   - GI: re-run the SDFGI A/B on the CITY (not the test street) at V1/V2/V8: on/off, energy, cascades; pick and
     justify. If SDFGI is too slow, VoxelGI is not an option at this scale → SSIL + reflection probes + a baked
     ambient term.
   - Volumetric fog: density, anisotropy, height falloff and sun energy so the god rays read in the canyons and
     over the canal, without the beige wash (distant towers should silhouette, not dissolve).
   - SSR on wet surfaces: a wetness parameter in the road/deck materials (city-art) with puddle masks, so the
     neon and windows reflect at street level (key art v2).
   - Exposure: physical camera or auto-exposure with tight min/max so interiors of canyons and the bright sky both
     hold; no blown-out sky.
3. **Presets + Settings**: `post_quality` follows `quality`; Settings keys `fx_film_grain`, `fx_lens` (bool),
   honoured with `photosensitive`.
4. **Perf**: budget ≤ 2.5 ms GPU for your whole stack at 1600×900 high (measure frame time with/without at V1,
   V2, V8 and in a fight); low preset ≤ 0.8 ms.

## Done when
- `tools/godot.sh check --only=res://world/post/` 0 errors; a test that every effect toggles, presets apply,
  photosensitive disables grain/fringe/streaks.
- A/B sheets `captures/post_ab_V1|V2|V8|fight.jpg` (before | after | key art) and a short honest note per sheet;
  frame times at each.
- The patch list for city-art/lead applied (coordinate via status) and re-measured.
EOF
