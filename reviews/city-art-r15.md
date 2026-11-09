# city-art r15 — lead brief: colour, not just value. A real sky, cool shadows, wet ground

## Why now
r14 did what it set out to do. 37 of 45 frames are now under the clip gate (r13 had eleven frames
over 10 %), and the five attributions in your table are good engineering.

The result is a frame with **one hue**. Look at the trailer's re-record on r14 (`tmp/lead/r15/grid.jpg`,
`combat.jpg`, `captures/trailer/sheets/TIANSHU_trailer_v1_shots.jpg`) and at
`captures/sheets/art_r14_V1.jpg`:
- at `--tod=0.6` (the city and combat takes) the frame is orange-brown from the sky to the street;
- the sky is a flat brown field with no cloud structure in it;
- the shadows crush to black;
- the hero and the enemies read as black blobs, because the shaded side of everything is
  near-black orange.

The key art (`art/concept/keyart/*`, sheet `tmp/lead/r15/keyart.jpg`) is the same palette, but it is
built from **colour contrast** as much as from value:
- a sky that runs from blue/violet at the top to gold at the horizon, with lit cloud structure (warm
  undersides, violet-grey bodies);
- shadows that are cool (v2's street is deep teal / blue-grey) against warm sunlit faces and warm
  points of lit windows;
- magenta and cyan neon;
- a **wet foreground that mirrors** the lights and the sky (v1's pier, v2's street).

This round is the colour structure. The user asked for "炫酷" and for stronger
"后处理 渲染 滤镜". That reads as colour, not just as contrast.

## Do
1. **Measure colour, the way r14 measured value.** Extend `values.py` (and the probe if needed). The
   probe already renders A (shipping) and B (bare sky); add a third pass with the sun disabled, so
   `A − C` is a sun-visibility mask. Per frame, report:
   - the hue and chroma of the sunlit surfaces, of the shaded surfaces, of the sky band just above
     the horizon, and of the sky at 30–60° elevation;
   - the **shadow-vs-light hue difference** and the shadow chroma;
   - shadow luma p5 / p50, so crushed shadows are a number;
   - inside the sky mask, the luma standard deviation and the zenith-vs-horizon hue difference, so a
     flat sky is a number.

   Then the same numbers for the four key-art plates. Hand masks are fine, as `KEY_BAND` was. **Set
   the targets from the key art and write them down before you tune anything.**
2. **The sky.** It must read as the key art's sky at golden hour, at dusk, and in the storm (v8's
   purple vortex).
   - **First find out why it is a flat brown field at `--tod=0.6`.** Suspects: `fog_sky_affect`
     (0.22 → 0.45 with progress), the layered haze drawn over the sky, aerial perspective, the dome's
     exposure under the new post exposure 0.56, and the cloud band's contrast.
   - Then make the cloud structure real: lit edges toward the sun, foreshortened bands toward the
     horizon, a visible sun disc and halo that stay inside the r14 clip rule.
   - **A/B the hand-built dome against a CC0 HDRI sky** (Poly Haven, `https://api.polyhaven.com`: a
     golden-hour or sunset sky with real clouds, 4k).
     - If the HDRI wins at golden hour, blend the two: the panorama gives the cloud field, and your
       ramp, sun and storm cover keep TimeOfDay control. Tint the panorama by the ramp and rotate it
       so its sun sits on `sun_dir`.
     - Assets go under `game/world/art/sky/`, with the licence and source URL in a README there.
       Credit it in the credits list (hud owns the screen; put the line in Requests and the lead
       routes it).
     - Decide on side-by-side sheets, not on preference.
3. **The colour of the light.**
   - Shaded surfaces take the sky's cool ambient (blue/violet from the zenith), not the fog's orange.
     Today `ambient_light_color` (#93a0bd) and `sky_contribution` 0.45 should already do that.
     Measure why they don't: is the ambient energy too low after r14's cuts, is SSIL re-tinting it
     orange, are the reflection probes stale, or is the grade's lift warm?
   - Shadows must stay readable, not black. Target the key art's shadow luma (§1).
   - The sun stays warm.
   - Fog/haze colour: warm toward the sun, cool/violet away from it.
   - **Re-run the r14 clip gate after every lever.**
4. **Wet ground.** Decks, streets and plazas get a wetness layer: darker albedo, low roughness in
   world-space puddle masks, and a little everywhere, so that SSR picks up the neon, the lit windows
   and the sky.
   - Measure the SSR cost with r13's paired method at `cams_budget5`.
   - If SSR is too expensive at shipping quality, find a cheaper reflection for the big flat decks and
     say what it costs.
5. **Accents.** Neon signage, the cyan rails, the Spire beam and the creep's acid green stay saturated
   against the darker, cooler surround. Check that they still carry after the colour change.

## Gates
- **The colour table (§1)** for V1–V8, the 7 street cams and the trailer's combat cameras, at
  `--tod` 0 / 0.5 / 0.6 / 1.0, against the key-art targets. Mark each target met or missed, with the
  number.
  - The trailer's combat cameras: take the spawn and look from `game/trailer/tl_s04_*.json`; the
    trailer worker is building new ones in parallel, so add theirs if they exist when you measure.
- **The r14 clip gate:** no regression on the 37 frames that pass now.
- **The frame budget:** ≤ +1.0 ms per camera at `cams_budget5`, paired A/B as in r13.
- **Side-by-side sheets** (r14 | r15 | key art) for V1, V2, V3 and V8, plus the trailer's s02 and s04
  cameras at `--tod=0.6`.
- **The hero and the enemies:** report the shaded-side luma of the hero at the s04 cameras, before and
  after. The ambient fix alone should lift it off black.

## Not yours / coordination
- **hero-v3 r7 runs in parallel.** It adds emissive accents and a rim to the hero, and it lights the
  hero with your environment. Do not change the Environment's public API; tell them through your
  status file what changed in the light.
- **trailer r2 runs in parallel.** It builds its own cameras. The trailer re-records on your round
  once you report done.
- The hero, enemy and VFX materials are not yours.
