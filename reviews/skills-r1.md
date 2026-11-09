# skills — review r1 (lead) — FAIL (mechanics excellent, 170/0; every skill needs its own visual signature)

Verified myself: check 31 files clean, 0 warnings; test_skills 170/0; movie watched. Your bug finds (refused
activations paying, shockcore centre, degenerate beam basis) are exactly the kind of rigour we need, and your
honest feel read matches mine. Contracts updated for your requests: `PlayerMech.reset_dash_chain()` (mech-move
r3), `status.clear_prime()` (enemies), anchor nodes = 8° / 120 m magnets on top of "any surface works";
feel r3 fixes the afterimage `skeleton` property. New core contracts since your run: CONTRACTS §3 **clocks**
(cooldowns/charges/OD on `Feel.player_delta`, hold thresholds on `Feel.real_delta`/`real_now`) and
**PadInput** (fins/burst/well/rift_step are on the RB shift layer — actions unchanged, no code change).

## MUST-FIX
1. **Showcase at gameplay framing**: drive the real camera rig (third person, hero ≈ 38 % of screen height) in
   `main.tscn --sandbox` with enemies (`--enemies=ripper:8,mantis:2,juggernaut:1`); one clip per skill,
   captures taken from the skill's own peak moment (trigger the screenshot in code), not a far fixed camera.
2. **Own signatures, never the generic `kill_large` preset**:
   - Shockcore: 18 f inhale (particles + slight screen-edge pull), then a cyan-white fresnel shell 0→32 m in
     0.18 s with a ground shock ring, radial lightning arcs, dust lifting off the ground, projectile deletion
     sparkles; no orange fireball.
   - Plunge Breaker: plasma sheath + speed streak during the 190 m/s dive; impact = vertical cyan-white light
     column, crater decal, radial debris ring, dust wave 0→20 m.
   - Rift Step: a bright streak line origin→destination for 0.15 s, refraction ripple sphere at both ends,
     the decoy shell with a hologram shader (needs feel's afterimage fix — coordinate via status).
   - Corona Fins: beam core 0.6 m / glow 2.5 m with a 4 f pre-flash at each fin, fins leaving short cyan
     trails; readable at 100 m.
   - Zenith Lance: layers core 2.4 m white / 8 m gold / 16 m red, heat distortion, ground scorching along the
     sweep, contact sparks; the 0.8 s charge with 4 converging brackets; gold rim vignette (not red).
   - Overdrive: gold-red body glow via `model.set_overdrive(true)`, afterimages, gold edge vignette.
   - Anchor cable: 0.5 m emissive core + glow, visible at 120 m; latch sparks; reel speed lines.
   - Undertow: keep the violet lens; add spiral inflow particles and a violet rim on primed enemies.
3. **Clocks** per CONTRACTS §3 + a test: under witch time a skill cooldown ticks at full speed in real time.
4. Re-capture all eight + the Lance sweep from behind the hero; judge 爽感 again honestly.
