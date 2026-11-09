# city-art r14 — lead brief: value structure. Match the key art's contrast, and stop the city bleaching

## Why now
The trailer job is shooting the city, and every frame it makes is washed out. In
`captures/trailer/sheets/tod_ab.jpg` (the same drop at `--tod` 0 / 0.35 / 0.6 / 0.85) and
`s02_city.jpg` (a night crane toward the Spire):
- the sky toward the sun clips to a white-gold field;
- the far city is a pale pink-white mush;
- the midground towers glitter with lit windows in daylight;
- there are no dark silhouettes anywhere.

The key art (`art/concept/keyart/v1_pier`, `v2_canyon`, `v3_oldtown`, `v8_crown`) is the same palette,
but with a value structure:
- dark, saturated midground masses with SPARSE warm lit windows at golden hour;
- a hazy-bright far skyline whose silhouettes still read against the sky;
- neon accents (magenta, cyan) that pop because the walls around them are dark;
- wet dark foreground reflections.

What the user asked for, from the start, is 爽感 and a "炫酷" look; the user's words were
"后处理 渲染 滤镜什么的也要加强". This round is the frame's tonal structure.

## Already fixed by the lead (cef764a, read it)
A dissolved facade pane counted as a wall of glass (`pane_t = mix(1.0, …)`), so every far tower,
including the whole skyline ring, emitted at the full lit fraction. It is now the family's own
`pane_w × pane_h`. Measured at `--tod=0.85`, pixels over 0.90: V5 3.8 % → 0.9 %. The far field is
still pale after it, so the rest is yours.

## Do
1. **Measure first.** V1–V8 and the 7 street cameras at `--tod` 0, 0.5 and 1.0, at the shipping
   default. Per frame, print:
   - the share of clipped pixels (> 0.97), excluding the sun disc and the Spire beam;
   - the luma p5 / p50 / p95;
   - the far-field contrast: the luma of the skyline silhouettes against the sky just above them. Your
     `ArtSurfaces` or the depth buffer can mask them; define the metric and print it.

   Then the same three numbers for the four key-art images. Put the result in a table, so the gap is
   numbers, not adjectives.
2. **Lit windows by time of day.** At golden hour a sunlit wall shows few lit windows, and they read as
   warm points in the shadowed faces. Today 45 % of cells are lit at progress 0 and they glitter on
   sunlit walls.
   - Ramp `mc_lit_fraction` and/or the window gain with the sun, so day is sparse and night is dense
     (`time_of_day.gd` LIT_START / LIT_END are yours).
   - Weight emission by how much SUN the face gets: a sunlit face's lit windows almost vanish, a
     shaded face's read.
3. **Far haze value.** The far field may go hazy, but it must stay a separate VALUE from the sky behind
   it.
   - Pick a target from the key art: e.g. the silhouettes 15–25 % darker than the sky band, or lighter
     where they are sun-lit toward the sun, as in v1.
   - Tune `mc_haze` / `layered_haze` so that holds at every vista and time.
4. **Bloom, shafts and exposure.**
   - The bright sky must not bloom across the city. Raise the bloom threshold, or soften the knee,
     until only true emitters bloom: windows, neon, beams, muzzle flashes, the sun disc.
   - Take the sun shafts down where they flatten the frame.
   - Look at the tonemapper's white point and exposure. These are post-render's rows
     (`world/post/post_presets.gd`); post-render is idle and you may tune them.
5. **Accents and depth.**
   - Check that the neon signage, the cyan rails, the Spire beam and the creep's acid green stay
     saturated and bright against a darker surround.
   - A gentle global S-curve in the grade is allowed.
   - Do not desaturate the golden palette.

## Gates
- **Clipping.** Clipped share (as defined above) at most 1.5 % on every vista and street camera at all
  three times.
- **Silhouettes.** Far-field contrast within the key-art band you defined, at every vista.
- **Side by side.** V1 next to v1_pier, V2 next to v2_canyon, V3 next to v3_oldtown, and V8 next to
  v8_crown (at `--tod=1.0`): r13 / r14 / key art, as one sheet each.
- **Night.** A `--tod=1.0` T1fac frame, r13 against r14: the lit-window runs read better than before,
  not worse.
- **Unchanged.**
  - Shimmer on the T1 dolly: the same metric as r11 / r12.
  - Frame time: the matched arms, the same method as r13.
  - `test_art`, `test_settle_cache` and `test_no_abs_paths`.

## Coordination
- **The trailer worker is shooting right now** (`status/trailer.md`, `tools/trailer/render_all.sh`).
  - Its shots are re-rendered from one command after your round, so you do not need to protect its
    footage.
  - Do not rename or remove flags it uses: `--tod`, `--render-scale`, `--stub`, `--no-enemies`,
    `--trailer-*`.
  - Do not touch `game/trailer/` or `tools/trailer/`.
- Do not rebuild the city tiles or the kit.

Commit per step with an explicit path list. Report in `status/city-art.md` (an r14 section).
