# feel — review r1 (lead) — FAIL (framework excellent; look over-juiced and flat)

Verified myself: check 63 files clean; test_feel PASS; stress +0.011 ms; 10 stills + gallery reviewed.
The data-driven architecture, pools, rate limits and rumble mixer are exactly right. Core changes for you:
`Feel.rumble()` now ONLY emits `rumble_requested` (your mixer owns the pads); new core
`Feel.kick(deg, world_dir, s)` + signal `kick_requested` replaces your `FeelDirector.kick_requested`
(remove yours; camera-aim will listen to core).

The visuals break juice dossier rule 12 ("high, not extreme") and ART.md:
## MUST-FIX
1. **Screen tints are edge effects, never washes**: witch time = world desaturated 60 % + cyan EDGE
   vignette (inner radius 0.55, outer alpha ≤ 0.35) + slight cool shift — the centre stays clear;
   hurt_light/heavy = red EDGE vignette (centre alpha 0, edge 0.25/0.6), not a full-screen pink; flashes
   ≤ 0.25 alpha full-screen except the 1–2 frame B/W impact frame.
2. **Speed lines / radial blur**: only the outer 35 % of the screen (radial mask), alpha ≤ 0.3, thin
   (≤ 2 px at 1600×900), density by speed (none below 40 m/s); radial blur strength ≤ 0.04 at the edges
   and 0 at the centre. The current full-screen white streaks are unusable.
3. **Explosions** (missile_blast, kill_small, kill_large, shockcore core): replace translucent blobs with
   real fire — an animated noise fireball shader on camera-facing quads (white-yellow core → orange →
   deep red edges, alpha erosion), 2–3 layers expanding 0→R in 0.15–0.3 s, then dark smoke puffs (lit,
   soft, rising, 2–4 s), embers/sparks, ground dust ring for ground hits, scorch decal. Sizes at mech
   scale: missile R 8 m, kill_small 12 m, kill_large 28 m (3 chained), boss 60 m.
4. **Sparks**: thin velocity-stretched streaks (length ∝ speed, width 0.15–0.3 m), white-hot core fading
   to orange, short life 0.15–0.35 s, additive + bloom; beam sparks cyan-white. No flat rectangles.
5. **Debris**: textured chunks (concrete/metal material from the CC0 library: `tools/textures/fetch.py`,
   or a procedural rock shader), irregular low-poly shapes (3–4 variants), sizes 0.5–4 m, dust trails.
6. **Scale + context**: the gallery must show the events next to the 16 m placeholder mech (from
   `player/model/placeholder/`) and with WorldEnvironment glow + AgX (ART.md §3) so bloom is judged as in
   game. Re-capture the 10 stills + movie.
7. Class names must be unique project-wide: keep `ShockwaveFx`; prefix new fx classes with `Fx` if generic.

## SHOULD
- First-person VFX opacity −40 % (a global uniform the camera sets via `Feel` when first person).
- A `fire_loop` (burning wreck) and `smoke_column` (reactor stacks, burning buildings) emitter for the city.
