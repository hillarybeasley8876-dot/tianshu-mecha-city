# feel — review r2 (lead) — FAIL (big step up; impact strength still short)

Verified myself: check 71 files clean; test_feel 34/0 PASS; r2 stills reviewed. Witch tint (edge + desaturate),
edge-only speed lines / radial blur, the large fireball shape, textured debris + crater: all fixed. Core now
has the accessibility Settings keys you asked for (`fx_flash fx_chromatic fx_radial_blur fx_speed_lines rumble
photosensitive damage_numbers hold_to_toggle`) and CONTRACTS lists the `Feel.post` ids. Read the player's
speed yourself (`Game.player.velocity`) for speed lines — no locomotion call needed.

## MUST-FIX
1. **Missile blast** (`missile_hit` / `missile_blast`): at 80–150 m it is a faint smoke wisp. Target: a bright
   fireball R 8 m (0→8 m in 0.12 s, white-yellow core HDR ≥ 4 so it blooms), 3 f flash light, then dark
   smoke 2 s, embers, a small dust ring if within 5 m of the ground. Must be unmistakable at 150 m.
2. **Fireball detail** (all kills/blasts): animated noise breakup (domain-warped fbm on the edge, alpha
   erosion over life), 2–3 overlapping layers with different sizes/delays, darker sooty rims → black smoke,
   embers flying out on arcs; brighter core (HDR 6–8 at t=0, decaying) so it blooms under AgX. Reference:
   Battlefield/Titanfall explosions, not a soft orange ball.
3. **Sparks at range**: `spark_bullet`/`spark_beam` scale size with camera distance (screen-space minimum
   2.5 px width, 25 px length at 150 m), count 12–20, a tiny flash billboard at the contact point, and a
   brief hot impact glow decal on world surfaces.
4. **Chromatic** = RGB channel split along the radial direction (red/blue fringes), no tinted vignette —
   the dash capture reads as a damage hit.
5. **Shockwave scale**: assert in the test that `shockcore` reaches 32 m radius in 0.18 s and `collapse` 20 m;
   capture at the peak frame (trigger the screenshot from the effect itself).
6. Honour the new Settings keys (photosensitive disables `bw_frame` and caps flashes at 0.1 alpha / 1 per s).

## SHOULD
- An optional 3-frame camera-facing "impact star" (white cross flare) on heavy hits — anime mech flavour.
