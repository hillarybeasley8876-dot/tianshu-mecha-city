# weapons — review r1 (lead) — FAIL (good functional base; visuals + integration open)

Verified myself: check 28 files clean; test_weapons 70/0; captures + movie watched. Rifle/gatling/missile
logic and perf (1.75 ms) are good. The look is not yet at the bar (ART.md, FEEL.md): beams are thin with no
bloom, missile trails are flat ribbons, impacts are tiny orange orbs, and debug lines show in captures.

## MUST-FIX
1. **Beam look**: normal shot core 0.5 m / glow 1.6 m; stage 1 core 1.0 / glow 3.5 m; stage 2 core 2.2 m /
   glow 7 m + a muzzle shock ring (0→12 m in 0.12 s) + 0.4 s heat-haze/afterglow trail; every beam fades
   over 0.12 s (no hard pop); emissive energy high enough to bloom with Glow on (HDR threshold 1.2);
   cyan muzzle OmniLight3D 3 frames (use the fx `FlashLightPool` when present). Enable WorldEnvironment glow
   + ART.md tonemap in your range scene so captures show the real look.
2. **Missiles (Itano circus)**: engine flare sprite at each head (bright, additive); tapered additive core
   ribbon (wide at the missile → thin) PLUS a soft lit grey-white smoke trail that lingers 1.5 s and widens
   ×3; bloom phase reads as a burst (staggered launch puffs). Impacts: until the fx VfxLibrary exists, your
   fallback is a real blast (fireball sphere 0→10 m in 0.15 s, flash, smoke puff) — no small orbs. When
   `fx/vfx/vfx_library.gd` exists, call it (`missile_blast`, `spark_beam`, `scorch`) and drop the fallback.
3. **No debug geometry by default**: the long white line(s) in the captures (aim ray?) only with `--debug`.
4. **API alignment** (CONTRACTS §4 updated): marks via `enemy.status.add_mark_hit(n)`; stage-2 / missile
   COLLAPSE detonation via `get_tree().call_group(&"prime_detonators", &"detonate_primes", center, radius,
   self_player)`; `hud_state()` adds `last_hit_usec`, `last_hit_kind` (normal/weak/kill/stagger).
5. **Real player integration**: mech-move is done (`player/player_mech.tscn` loads your component). Add a
   timeline that runs in `main.tscn --sandbox` with the real PlayerMech (and camera-aim's rig if present):
   fire rifle at 120/300 m, charge stage 2, swap, gatling burst, paint + 12-missile salvo; capture 6 frames
   + movie. Fix anything that only worked with your stand-in.

## SHOULD
- Gatling tracers 0.35 m thick and brighter; small hit spark per round on world surfaces.
- Keep files ≤ 400 lines.
