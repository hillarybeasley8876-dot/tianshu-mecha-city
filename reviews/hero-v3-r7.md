# hero-v3 r7 — lead brief: the hero must read. Emissive accents, gold that is gold, a silhouette

## Why
In the trailer (`captures/trailer/sheets/TIANSHU_trailer_v1_shots.jpg`; lead frames in
`tmp/lead/r15/grid.jpg` and `combat.jpg`) the Tianshu hero is a **black silhouette in every shot**:
the cold open, the drop, all of the combat, and even against the boss's bright pink sky.

The concept (`art/concept/hero/v3/a1-1.png`; side-by-side with the A1 spawn in
`tmp/lead/r15/hero_vs.jpg`) reads because of three things:
1. **cyan emissive accent lines** along the armour seams and on the blade-drone tips;
2. **gold trim** that catches the light;
3. a **glowing gold chest vent** and a lit visor.

In game, the body is a single Tripo material (`tripo_material_0ce34ee2…`: Color / NormalGL / ORM,
no emission). The cyan lines are only albedo pixels in `hero3_Color_*.jpg`, so on the shaded side
they go black. Only `Hero3Edge` (the weapon edges) and the eyes emit. The user's last word on the old
hero was that the rig looked broken; this round is about the hero looking like the concept.

## Do
1. **Build an emission mask from the atlas.** Write a `blender/hero/` or `tools/` script that derives
   `hero3_Emission.png` from the Color atlas (and the same for `hero3_lod1`).
   - Select the cyan accent pixels by hue / saturation / value. Measure the thresholds on the atlas;
     a start is hue 175–200°, S > 0.4, V > 0.35.
   - Add the chest-vent and visor glow regions. Find them by UV island or by the vent's part in the
     22-part `art/tripo/hero3_a1p` set.
   - Clean the mask: remove speckle, keep the lines continuous. Look at the mask laid over the
     atlas, not just at the pixel count.
   - Wire it into the hero's material, keeping the import pipeline re-runnable from one command.
     The material may become a small ShaderMaterial or a StandardMaterial3D with an emission texture;
     your call.
   - Give the lines and the vents separate controls:
     - the lines are steady;
     - the vents pulse with the hero's state: boost, overdrive and the charge. Use the signals the rig
       already has.
   - Keep the overdrive tint working (`_apply_tint` today only touches surfaces that already glow).
2. **Gold must be gold.** Check the ORM atlas on the gold trim and on the black armour against what a
   golden-hour city should put on them.
   - Gold trim: metallic ≈ 1, roughness 0.25–0.4.
   - Black armour: albedo not pure black (≥ 0.04 linear); metallic and roughness that give a readable
     sheen.
   - Fix the atlas channels if Tripo baked them wrong. Look at the result in the CITY, not in the
     strip's ProceduralSky.
3. **Separate the silhouette from a dark background.** Use a subtle view-dependent rim: fresnel,
   tinted from the sky's horizon colour or a fixed cool tone.
   - A/B it: it must lift the outline without flattening the form or reading as a cartoon outline.
   - It must be off in first person: the cockpit view must not glow.
4. **Weapons and drones.** The blade drones, the saber and the rifle carry the same accent language
   (the concept's cyan drone tips). Extend the mask or the materials to them.

## Gates
- **Lit close-ups:** 4 angles plus top, at `--tod` 0, 0.5, 0.85 and 1.0, **in the city**. Put them on a
  sheet beside the concept, `captures/hero3_look_vs_concept.jpg`.
- **In-game readability at the trailer's cameras.** Use the s01 cold-open, s03 drop and s04 combat
  spawn/look from `game/trailer/tl_*.json`.
  1. Render the hero's screen mask (hide everything else, or use a matte pass) and measure inside it.
     Report the baseline first, then after:
     - the share of hero pixels with luma < 0.03 (today it looks like most of them);
     - the hero's mean luma against a 24 px ring around the mask.
  2. The targets:
     - dark pixels ≤ 40 %;
     - the hero visibly separated from the ring, with the ratio reported.
  3. Show the frames.
- **No blow-out:** ≤ 0.3 % of hero pixels clip, except the accent cores. The post bloom threshold is
  2.6 linear since city-art r14; the lines may bloom a little, the armour must not.
- **No regression:** every `hero3/tests/` suite, `player/mech/tests/test_damage.gd` and
  `tools/godot.sh check` pass. The hero shader costs ≤ +0.2 ms at the A1 spawn.

## Coordination
- **city-art r15 runs in parallel** and is changing the sky, the ambient colour and the reflections.
  - Do the material work against the current environment.
  - When their status file reports done, re-shoot your gate frames on their light.
  - Do not edit `game/world/art/**`; if you need something from the environment, put it in Requests.
- **trailer r2** reads your hero at its new cameras later. You do not need to coordinate with it.
