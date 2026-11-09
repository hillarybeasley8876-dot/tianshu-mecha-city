# feel — numeric-robustness audit (lead, 2026-11-02) — 18 verified findings

A 36-agent audit read every non-test script twice (non-finite math; clocks + integrators) and a skeptic
tried to refute each finding; these survived. Fix them all (the proposed fixes were checked by the
skeptic — where it corrected one, the correction is what is written under *fix*). Add a regression check
for each high one in your suite, keep every suite green, run one scripted fight with `--nan-watch`, commit,
and report per finding: fixed (how) / not reproducible (evidence).

Clock contract reminder (CONTRACTS §3): Feel.real_delta/real_now for input, camera, UI/post and rate
limits; Feel.player_delta for player timers/anims; plain delta for world VFX; NEVER the wall clock
(movie capture renders a frame in ~70 ms of wall time). Feel now divides _process deltas by the
frame's own scale, so Feel.real_delta(delta) is correct in _process too.

## 1. [high] game/fx/screen_fx/screen_fx.gd:152 (clock)
**What**: ScreenFx advances every flash, post pulse (chromatic/radial/vignette/desaturate/impact_bw), the witch-time tint and the speed-line `time_offset` with a wall-clock dt (Time.get_ticks_usec, clamped to 0.1 s) instead of the game clock the contract requires for UI/post timing.

**Trigger**: Movie capture (~70 ms of wall time per 1/60 s frame): a kill_large or finisher row requests a 2-frame flash and impact frame during a physics tick. ScreenFx._process then subtracts ~0.07 s before the first _apply(), so the flash and the B/W frame are never drawn. 0.12 s post pulses show for one frame at ~42 %, the witch tint snaps in within ~2 frames, and the speed lines scroll ~4x too fast. The same happens in live play on any 100 ms hitch.

**Fix**: Take dt from Feel's game clock: `var now := Feel.real_now(); var dt := now - _last_real; _last_real = now`, with `_last_real = Feel.real_now()` set in _ready. Feel measures this before it rewrites Engine.time_scale and already clamps it to 0.1 s. Do NOT use `Feel.real_delta(delta)` here: inside `_process` it returns ~0.3 s on the first frame of every global hit-stop (verified on 4.7.2), which would wipe the flash the same row just requested.

**Skeptic's check**: screen_fx.gd:151-158 takes dt from Time.get_ticks_usec. tools/godot.sh:74 records movies with --write-movie --fixed-fps 60, so wall time per frame differs from the game's 1/60 s. A 2-frame flash (kill_large, boss_stagger, shockcore and others) or finisher's 2-frame impact frame (0.033 s) loses ~0.07 s to _advance before the first _apply and is never drawn. A 100 ms live hitch does the same. The contract requires the game clock for UI/post timing, and the fix (difference of Feel.real_now(), which Feel updates first at priority -1000 and clamps to 0.1 s) is correct.

## 2. [high] game/fx/vfx/afterimage_pool.gd:83 (clock)
**What**: AfterimagePool fades ghosts by wall-clock age (`now - _born` from Time.get_ticks_usec, line 119), not the game clock.

**Trigger**: Movie capture: Rift Step streak ghosts (0.14 s), the Zenith Overdrive trail (0.25 s life, one ghost every 3 frames on the player clock) and Rift Step's fallback decoy ghost (0.6 s) fade in 2–9 rendered frames instead of 8–36. The overdrive trail shows about one ghost instead of about five. The decoy ghost disappears while the gameplay decoy, which counts down 0.6 s of player time, is still drawing Swarmers.

**Fix**: Make `_now()` return `Feel.real_now()`, the game's unscaled clock, which matches the player skills that spawn the ghosts in witch time and is correct in movie/fixed-fps runs.

**Skeptic's check**: afterimage_pool.gd:83,119 fades ghosts by Time.get_ticks_usec age. The callers are rift_step.gd:168 (0.14 s), rift_step.gd:246 (decoy) and zenith_overdrive.gd:82, so in movie capture the ghosts fade ~4x too fast relative to the player-clock skills that spawn them. Making _now() return Feel.real_now() keeps live behaviour and fixes captures.

## 3. [high] game/fx/vfx/debris_pool.gd:113 (clock)
**What**: DebrisPool times each chunk's 6 s life and 0.6 s fade on the wall clock (`now - _born`), although the chunks are RigidBody3D simulated on the scaled world clock.

**Trigger**: Movie capture: chunks from kill_small debris, plunge_land or hive_collapse start fading at 5.4 s of wall time, which is only ~1.3 s of game time. Jolt still has them airborne and bouncing, so captured rubble vanishes in mid-air. With the pause menu open, the paused physics server freezes the bodies, but every chunk still fades and is released after 6 s, so the rubble is gone on resume.

**Fix**: Age chunks on the world clock they are simulated on. Keep a per-slot `_age` PackedFloat64Array, set it to 0 in burst(), add the plain `delta` to it in _process, and use `var age := _age[i]` instead of `_now() - _born[i]`. Combined with the PAUSABLE fix in vfx_library.gd, this also stops chunks ageing during pause.

**Skeptic's check**: debris_pool.gd:107,113 ages chunks by wall-clock `now - _born`, while the RigidBody3Ds step on the scaled physics delta. In movie capture the 6 s life and 0.6 s fade take ~1.3-1.4 s of game time. In pause, SceneTree pauses the physics server but the pool's _process still runs (ALWAYS inherited from FeelDirector), so chunks fade and are released. A per-slot age fed with plain delta is the right clock.

## 4. [high] game/fx/vfx/fireball_fx.gd:98 (clock)
**What**: FxFireball ages its layered fireball (expansion, erosion, heat pop, loop) on the wall clock, while the GPU smoke, embers and dust of the same FxBlast run on game time.

**Trigger**: Movie capture: an 8 m missile_blast fireball (0.5 s life, 0.13 s expansion) burns out in ~7 rendered frames and expands in ~2. kill_large's ~1.1 s ball lasts ~15 frames. Its own smoke and embers still play at game speed, so captured explosions are a two-frame pop followed by smoke. The fire_loop wreck flames cycle ~4x too fast, and every ball keeps burning while the game is paused.

**Fix**: Accumulate game real time instead of wall time. Set `_last_real = Feel.real_now()` in fire(); in _process do `var now := Feel.real_now(); _t += (now - _last_real) * time_scale; _last_real = now`. This keeps juice-impact rule 4 (fire keeps running through hit-stop) and is exact in movie and fixed-fps runs. Do not use Feel.real_delta(delta) in _process: it spikes to ~0.3 s on hit-stop onset.

**Skeptic's check**: fireball_fx.gd:97-99 ages _t on the wall clock. The FxBlast's GPU smoke and embers advance by RenderingServer::draw(scaled_step), the game clock, so in movie capture an 8 m missile ball (0.5 s life at FIRE_MIN, 0.127 s expansion) burns out in ~7 frames. kill_large's r = 28*1.3 = 36.4 m ball (1.09 s) lasts ~15 frames. fire_loop cycles too fast, and because the subtree inherits ALWAYS the ball also burns while paused. The proposed real_now() accumulation is correct and keeps rule 4.

## 5. [high] game/fx/vfx/shockwave_fx.gd:82 (clock)
**What**: ShockwaveFx expands and fades its ring on the wall clock (Time.get_ticks_usec).

**Trigger**: Movie capture: rings for missile_hit, shockcore and melee_heavy (0.18 s) and kill_large (0.25 s) advance ~70 ms per rendered frame. They finish in 3–4 frames instead of 11–15. Rings also keep expanding while the game is paused.

**Fix**: Use the same pattern as FxFireball: `_last_real = Feel.real_now()` in fire(); in _process add `(Feel.real_now() - _last_real) * time_scale` to `_t`, then update `_last_real`. Never use `Feel.real_delta(delta)` in `_process`: kill_large's ring is spawned in the same play() as its 0.1 s global hit-stop, so it would read 0.3 s and finish on its first frame. Also switch VfxLibrary._clock() to Feel.real_now() so `_hold`/`_take` free ring slots on the same clock. Update test_feel.gd:228-231, which times the ring with Time.get_ticks_usec.

**Skeptic's check**: shockwave_fx.gd:81-83 uses Time.get_ticks_usec. In movie capture, the 0.18 s rings (missile_hit, shockcore, melee_heavy) and kill_large's 0.25 s ring finish in 3-4 frames. They also keep running in pause, since the subtree inherits ALWAYS. The warning against real_delta in _process matches my probe of Godot 4.7.2: delta/time_scale reads 0.333 s on the hit-stop onset frame. Switching VfxLibrary._clock (line 300) as well is needed, or _take would reuse a ring slot that is still running.

## 6. [medium] game/core/feel.gd:131 (clock)
**What**: This is outside game/fx, but it decides how the fx fixes above must be written. Feel.real_delta(delta) divides by the current Engine.time_scale, but Feel rewrites the scale in its own priority -1000 _process. Any _process caller that runs after Feel therefore divides a delta scaled by the previous frame's scale by the new scale.

**Trigger**: Every global hit-stop onset (kill_small, kill_large, boss_stagger, hurt_heavy). Verified with a Godot 4.7.2 headless probe: when the scale switches from 1.0 to 0.05, a later node's `delta / Engine.time_scale` is 0.300 s instead of 0.0167 s (0.83 s at MIN_SCALE 0.02), and 0.0008 s on the release frame. _physics_process callers such as the camera rig are consistent. Today this jumps the real-time accumulators in world/art infection_field.gd, storm_crown.gd and time_of_day.gd by ~0.3 s on every kill freeze. A ScreenFx or ring fix written with real_delta in `_process` would end the effect on the frame it is spawned.

**Fix**: The proposed _frame_scale capture with an Engine.is_in_physics_frame() switch is correct. Apply the same selection in player_time_comp(): all current player_delta callers are _physics_process, so nothing breaks today, but a future _process caller would hit the same bug.

**Skeptic's check**: Main::iteration captures time_scale once per frame for both physics and process deltas (main.cpp 4.7.2: 4936, 5001, 5062). Feel rewrites Engine.time_scale in its priority -1000 _process, so later _process callers divide an old-scale delta by the new scale. My headless 4.7.2 probe gave 0.33333 s on the onset frame and 0.00083 s on release, while _physics_process stayed consistent at 0.00833. This reaches live code today: infection_field.gd:82 (_time += real), storm_crown.gd:86, time_of_day.gd:70 and prop_scatter.gd:114 all call real_delta in _process.

## 7. [medium] game/fx/decals/decal_pool.gd:88 (clock)
**What**: DecalPool's 0.25 s impact_glow fade runs on the wall clock (`_now()` = Time.get_ticks_usec).

**Trigger**: Movie capture: the heat glow left by every spark_bullet, spark_beam and spark_burst hit is gone after 3–4 rendered frames instead of 15.

**Fix**: Make `_now()` return `Feel.real_now()`. Glows still die during a hit-stop, as intended, and the timing is exact in movie capture.

**Skeptic's check**: decal_pool.gd:88,99 runs the 0.25 s impact_glow fade on Time.get_ticks_usec. Every spark_bullet, spark_beam and spark_burst spawn adds one (vfx_library.gd:112-113), and in movie capture it lasts 3-4 frames. Feel.real_now() is the right unscaled clock and still lets glows die during a hit-stop.

## 8. [medium] game/fx/feel_director.gd:68 (clock)
**What**: Per-row cooldowns, the FEEL table's rate limits ('seconds of real time'), are measured on the wall clock: `_now` comes from `_clock()` = Time.get_ticks_usec at line 248, not the game clock.

**Trigger**: Movie capture (~70 ms of wall time per frame): every cooldown of 0.07 s or less (rifle_hit 0.02; gatling_hit and melee_light 0.03; kill_small, missile_hit, rifle_fire and lunge_hit 0.05) never blocks, and 0.1–0.3 s cooldowns last only 2–5 frames. Gatling and rifle fire and chain kills therefore produce 2–4x more shakes, flash lights, VFX and audio layers per game second than in live play. In fast headless fixed-fps tests the opposite happens: the windows last many more game frames.

**Fix**: Make `_clock()` return `Feel.real_now()`, the unscaled game clock that Feel.hit_stop's own limiter already uses.

**Skeptic's check**: feel_director.gd:61,68 checks cooldowns, which feel_event.gd:81 documents as 'seconds of real time', against _clock() = Time.get_ticks_usec (line 248). In movie capture, cooldowns of 0.07 s or less only block within a single frame, and longer ones last 2-5 frames. In headless fixed-fps tests the windows last many more frames. The contract wants the game clock for rate limits, and Feel.hit_stop's limiter already uses real_now().

## 9. [medium] game/fx/feel_director.gd:138 (clock)
**What**: A GLOBAL row whose falloff factor is 0, or small enough to make the freeze shorter than a frame, still calls Feel.hit_stop(hitstop_seconds * f). Feel.hit_stop records a start even for a 0 s request, so these invisible freezes spend the 150 ms / 3-per-second global hit-stop budget.

**Trigger**: Normal play, where the player often fights from altitude: a missile salvo or COLLAPSE kills a swarmer more than 120 m from the camera (kill_small falloff is 120 m, so f = 0). It lands in the same tick as, or within 150 ms before, a nearby kill_large or boss_stagger. The far kill's hit_stop(0.0) is recorded and the near event's freeze is dropped by the limiter. Three distant kills block every global hit-stop for a full second.

**Fix**: The f == 0 path is the real defect. In _hitstop return when `ev.hitstop_seconds * f <= 0.0`; better, make Feel.hit_stop return false before appending to _stop_starts when seconds <= 0.0. A positive sub-frame request is NOT invisible: Feel._process sets time_scale = _stop_scale for the whole next frame whenever _stop_left > 0, so it is a 1-frame freeze. Dropping requests below FeelEvent.FRAME is a design choice that removes that freeze for kill_small kills at about 70-120 m; it is not a bug fix.

**Skeptic's check**: kill_small (enemy_base.gd:267) is a GLOBAL row with falloff 120 m, and missiles lock to 300 m (missile_tuning.gd:9), so f = 0 is common. _hitstop still calls Feel.hit_stop(0.0). feel.gd:63-66 appends a start before checking seconds, so the far kill consumes the 150 ms / 3-per-second budget. A nearby kill_large or boss_stagger in the same window is then dropped, because now - last < 0.15 returns false.

## 10. [medium] game/fx/screen_fx/screen_fx.gd:158 (clock)
**What**: ScreenFx decrements every timed pulse (`_advance(dt)`) before drawing it (`_apply()`), so an N-frame flash or impact frame gets only N−1 rendered frames.

**Trigger**: Normal play: kill_small's 1-frame flash and the 1-frame B/W impact frame of boss_stagger and jackpot are requested in a physics tick. ScreenFx._process subtracts 1/60 s, the pulse reaches 0 and is erased, and is_idle() hides the layer, so they are never drawn. The 2-frame impact frames of finisher and lance_fire show once at 0.425, below the 0.5 hard threshold, so they draw as a soft grey frame instead of the hard B/W one.

**Fix**: In _process, call `_apply()` and set `visible = enabled and not is_idle()` before calling `_advance(dt)`: draw this frame's state first, then age it. An N-frame pulse is then drawn on N frames, whichever phase requested it.

**Skeptic's check**: screen_fx.gd:158-159 runs _advance(dt) before _apply(), so a pulse requested in any phase is aged one frame before it is first drawn. kill_small's flash_frames = 1, and the impact_frames = 1 of boss_stagger and jackpot, reach ~0 and are erased or hidden by is_idle(). finisher's and lance_fire's impact_frames = 2 first draw at 0.85*0.5 = 0.425, below post.gdshader's step(0.5, impact_bw) hard threshold. This happens in normal play. Drawing first and then ageing fixes it.

## 11. [medium] game/fx/screen_fx/screen_fx.gd:217 (clock)
**What**: The photosensitivity flash limiter (0.5 s, or 1.0 s in photosensitive mode) compares Time.get_ticks_usec timestamps, so measured in game time it lets through several times more flashes than intended.

**Trigger**: Movie capture of a crowd fight with repeated kill_large, parry_perfect or finisher flashes: 0.5 s of wall time passes every ~7 rendered frames. The video can therefore show ~8 full-screen flashes per game second (~4 in photosensitive mode), above the WCAG cap this code is meant to enforce. The wall-clock dt finding above currently hides this; it appears as soon as that is fixed.

**Fix**: Store `_last_flash_t: float = -1000.0`. In _on_flash use `var now := Feel.real_now()`, return early if `now - _last_flash_t < interval`, then set `_last_flash_t = now`.

**Skeptic's check**: screen_fx.gd:214-219 limits flashes by Time.get_ticks_usec. In movie capture, wall time runs ~4x faster than video time, so the 0.5 s / 1.0 s interval allows ~4x more flashes per video second than intended. This is latent: today finding 4 wipes most captured flashes, and it shows up once that is fixed. The proposed real_now() limiter is correct.

## 12. [medium] game/fx/vfx/flash_lights.gd:42 (clock)
**What**: FlashLightPool turns frame-specified light pops into wall-clock deadlines (Time.get_ticks_usec + frames/60).

**Trigger**: Movie capture: every row with light_frames 2–4 (rifle_fire, missile_hit, kill_small, kill_large, finisher, and others) gets a 33–67 ms wall-clock deadline. The next rendered frame arrives ~70 ms of wall time later, so every pooled OmniLight3D pop shows for exactly 1 frame.

**Fix**: The proposed fix is acceptable. Note that a light flashed from a _process after Feel would get N+1 frames with the +0.5 margin. A deadline in rendered frames (Engine.get_process_frames() + frames, compared in _process) is exact in both phases, because Godot increments the counter only at the end of the iteration (main.cpp).

**Skeptic's check**: flash_lights.gd:42 sets wall-clock deadlines of frames/60 (33-67 ms for light_frames 2-4). In movie capture the next _process is ~70 ms later, so every pop shows for exactly one frame. The half-frame margin is right for requests made in a physics tick, which is the usual case, because real_now() only advances in Feel._process.

## 13. [medium] game/fx/vfx/flash_pop.gd:87 (clock)
**What**: FxFlashPop runs its contact flash and cross flare on the wall clock.

**Trigger**: Movie capture: the 0.075 s pop that FxImpact fires on every spark_bullet, spark_beam and spark_burst hit, and impact_star's 0.13 s flare, are drawn for 1–2 frames instead of 4–8. Distant hits rely on the pop to read at 150 m, so they nearly disappear in captured footage.

**Fix**: Set `_last_real = Feel.real_now()` in pop(). In _process do `var now := Feel.real_now(); _t += (now - _last_real) * time_scale; _last_real = now`. Do not use Feel.real_delta(delta) in _process.

**Skeptic's check**: flash_pop.gd:86-88 advances on the wall clock. FxImpact fires a 0.075 s pop (impact_fx.gd:35) and impact_star a 0.13 s one (vfx_presets.gd:76). With ~70 ms of wall time per movie frame these are drawn for 1-2 frames. The proposed real_now() accumulation is correct.

## 14. [medium] game/fx/vfx/spark_process.gdshader:29 (other)
**What**: start() never rotates the emit cone into the emitter's frame, so the surface-facing basis is ignored. local_coords is false, and Godot's particles.glsl inserts custom START code without applying EMISSION_TRANSFORM (only ParticleProcessMaterial's generated code does that). So `axis = normalize(emit_direction)` is a fixed world direction, and the basis that VfxLibrary.spawn / FxImpact.fire set via VfxPresets.facing(normal) has no effect.

**Trigger**: Any spark_bullet / spark_beam / spark_burst / muzzle_ring / thruster_burst / blast-ember burst in normal play. The sparks always fly toward world (0, 0.29, -0.96) whatever the hit normal or muzzle direction. For example, a beam hit on a wall whose normal is +Z sprays its sparks into the wall, and ground hits never get the random yaw that facing() picks.

**Fix**: `vec3 axis = normalize(mat3(EMISSION_TRANSFORM) * emit_direction);` is right. Note that FxBlast's embers get an identity basis (vfx_library.gd:101), so after the fix their cone still points sideways at world -Z. Give them emit_direction = UP, or a facing basis.

**Skeptic's check**: I checked Godot 4.7.2 particles.glsl: the START code is pasted in raw and nothing applies frame_history emission_transform to the particle. Only ParticleProcessMaterial's generated code does `TRANSFORM = EMISSION_TRANSFORM * TRANSFORM` and multiplies the velocity by EMISSION_TRANSFORM (particle_process_material.cpp:978,1009). spark_process.gdshader:29 uses the raw uniform, which is set once at build time (vfx_presets.gd:169) and never per shot. With local_coords = false (vfx_presets.gd:347), the facing(normal) basis set in impact_fx.gd:31 and vfx_library.gd:105 has no effect, and sparks always fly toward world (0, 0.29, -0.96).

## 15. [medium] game/fx/vfx/spark_process.gdshader:41 (nonfinite)
**What**: The spark cone sampler computes tan(radians(spread_deg) * 0.5), which hits its pole for the three presets built with spread 180. Sparks then leave at ~90 degrees from the axis (a flat disc, not the intended hemisphere). On GPU math modes where cos(1.5707964f) rounds to 0, tan is +/-inf and normalize(axis + perp * m) at line 43 (or inf * sqrt(0) when r2 == 0) gives a NaN VELOCITY.

**Trigger**: Every spark_burst (spread 180 at vfx_presets.gd:73-74; used by the parry_perfect, melee_heavy, finisher, charge_slash, catch_release, collapse and stagger_enemy rows and by most skill hits). Every missile_blast / kill_small / kill_large, through FxBlast's embers (blast_fx.gd:36-37, spread 180). Every muzzle_ring (vfx_presets.gd:78). In float32, radians(180.0) * 0.5 = 1.5707964, which is 4.4e-8 past pi/2, so tan = -2.29e7 and m = -2.29e7 * sqrt(r2). Every spark with r2 > ~1e-14 is thrown at 89.99997 degrees off the emit axis. A fast-math tan/cos (Metal) can return +/-inf there instead, giving NaN particle velocities and positions.

**Fix**: The proposed cap sampling is correct: ct = mix(1, cos(h), r2), st = sqrt(max(1 - ct*ct, 0)), VELOCITY = (axis*ct + perp*st)*sp. Note that muzzle_ring may currently depend on the accidental disc for its 'ring' look. If a ring is wanted, give it an explicit flat or ring mode rather than relying on the tan pole.

**Skeptic's check**: spark_process.gdshader:41 evaluates tan(radians(180)*0.5). In float32 that argument is 1.5707964, so tan is about -2.29e7 and m is about -2.29e7*sqrt(r2). Every spark with r2 > ~6e-12 leaves within 1 degree of 90 deg from the axis, so spark_burst (vfx_presets.gd:73-74), muzzle_ring (:78) and the FxBlast embers (blast_fx.gd:36-37) all fly out as a flat disc. That contradicts the r2 review's 'embers flying out on arcs'. The NaN outcome is only plausible: it needs a GPU fast-math tan that returns inf (cos rounding to exactly 0), which I could not verify. The disc is certain.

## 16. [medium] game/fx/vfx/spark_process.gdshader:70 (other)
**What**: Streaks are always drawn vertical, never along the spark's velocity. process() pins every particle's Y axis to vec4(0.0, len, 0.0, 0.0), and GPUParticles3D.transform_align is left at DISABLED (it is never set in build_sparks). spark.gdshader:34-36 takes MODEL_MATRIX[1] as the streak direction, so the 'velocity-aligned' streaks always point along world +Y.

**Trigger**: Every spark kind in normal play. For example, a spark_bullet spark flying horizontally at 40 m/s draws as a ~2 m vertical dash sliding sideways instead of a tracer along its path.

**Fix**: Build the basis from the velocity in process(), with a guarded fallback: `vec3 yd = CUSTOM.x > 1e-4 ? VELOCITY / CUSTOM.x : vec3(0.0, 1.0, 0.0); vec3 xd = normalize(cross(abs(yd.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0), yd)); TRANSFORM[0] = vec4(xd * wid, 0.0); TRANSFORM[1] = vec4(yd * len, 0.0); TRANSFORM[2] = vec4(cross(xd, yd) * wid, 0.0);` Do not use transform_align = Y_TO_VELOCITY instead: its normalize(cross(v, z)) has no zero guard.

**Skeptic's check**: process() writes TRANSFORM[1] = (0, len, 0) at spark_process.gdshader:70, and transform_align is never set anywhere, so it stays at DISABLED. particles_copy.glsl leaves the basis untouched in that mode. For non-local particles the instance transform is identity (render_forward_clustered.cpp:4475 store_transform = false), so MODEL_MATRIX is the particle xform. spark.gdshader:34-36 therefore always gets world +Y as the streak axis: the streaks are vertical, not aligned with velocity.

## 17. [medium] game/fx/vfx/vfx_library.gd:54 (clock)
**What**: The whole world-VFX subtree (VfxLibrary and its pools, GPUParticles3D, FxBlast/FxFireball, debris) inherits PROCESS_MODE_ALWAYS from FeelDirector (feel_director.gd:44), and FlashLightPool (flash_lights.gd:16) and DecalPool (decal_pool.gd:30) set it explicitly. As a result, world VFX keep their clock running in the pause menu.

**Trigger**: Normal play: open the pause menu (menu_root.gd:266 sets get_tree().paused) within 0.35 s of a kill_large, or with explosions or debris on screen. Feel forces Engine.time_scale = 1.0 while paused, so the `_pending` chain (line 220) keeps counting down plain delta and the 0.15 s and 0.35 s blasts detonate behind the 82 %-opaque pause page. GPUParticles3D keep simulating, and the wall-clock pools (debris, lights, ghosts, glows, rings, pops) expire. On resume the explosions are over and the rubble is gone.

**Fix**: Set `process_mode = Node.PROCESS_MODE_PAUSABLE` at the top of VfxLibrary._ready(), and remove the explicit ALWAYS in FlashLightPool._ready() and DecalPool._ready(). Age effects with per-frame steps (the dt fixes above) and clamp the first step after resume to 0.1 s; effects timed by absolute timestamps would otherwise expire across the pause anyway.

**Skeptic's check**: FeelDirector sets PROCESS_MODE_ALWAYS (feel_director.gd:44), and VfxLibrary and its pools inherit it. FlashLightPool (:16) and DecalPool (:30) also set ALWAYS explicitly. Feel forces time_scale = 1.0 while paused (feel.gd:164). So when menu_root.gd:266 pauses, the _pending chain (vfx_library.gd:220) still counts down plain delta and fires kill_large's 0.15 s / 0.35 s blasts. GPUParticles3D keep speed_scale because can_process() is true (gpu_particles_3d.cpp:599-606), and the wall-clock pools expire behind the 82% pause page (menu_screen.gd:139).

## 18. [low] game/fx/vfx/spark_process.gdshader:58 (integrator)
**What**: Spark position is integrated twice per tick. Godot's particles.glsl already runs `PARTICLE.xform[3].xyz += PARTICLE.velocity * local_delta` before the user process() unless the shader declares `render_mode disable_velocity;`. This shader declares no render_mode, and line 58 adds `VELOCITY * DELTA` again, so every spark travels twice its tuned distance.

**Trigger**: Every spark kind. For example, spark_bullet (vmax 42 m/s, damping 4/s) ends ~21 m out instead of ~10.5 m. Its visibility_aabb (vmax * life + 4 = 16.6 m, set in node space) was sized for 1x travel. It is also shrunk by the node scale that FxImpact.fire / VfxLibrary.spawn apply: 0.48 for gatling bullet hits (spark_pool.gd:94), down to 0.05. The particles ignore that scale, so they leave their culling box and pop off when the impact point is just outside the view.

**Fix**: Delete line 58 and let the engine integrate VELOCITY (or add `render_mode disable_velocity;` and keep the line). Also stop scaling the spark GPUParticles3D node in FxImpact.fire / VfxLibrary.spawn: pass k through the existing `size_mul` uniform, so the culling box stays matched to the real throw.

**Skeptic's check**: particles.glsl (4.7.2) runs `PARTICLE.xform[3].xyz += PARTICLE.velocity * local_delta` under `#if !defined(DISABLE_VELOCITY)` before #CODE : PROCESS. This shader declares no render_mode, while ParticleProcessMaterial declares disable_velocity and integrates once itself. Line 58 adds VELOCITY*DELTA again, so every frame after the spawn frame moves the spark twice. The 21 m / 10.5 m figures ignore the 0.3 s life: the real figures are about 14.7 m vs 7.3 m, but the 2x is right. The node-space visibility_aabb is scaled by k (0.3-0.48 for bullet hits, spark_pool.gd:94). Because non-local draws ignore the node transform, sparks.scale = k currently only shrinks the culling box; it does not resize the sparks.
