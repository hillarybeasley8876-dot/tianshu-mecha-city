# weapons — numeric-robustness audit (lead, 2026-11-02) — 7 verified findings

A 36-agent audit read every non-test script twice (non-finite math; clocks + integrators) and a skeptic
tried to refute each finding; these survived. Fix them all (the proposed fixes were checked by the
skeptic — where it corrected one, the correction is what is written under *fix*). Add a regression check
for each high one in your suite, keep every suite green, run one scripted fight with `--nan-watch`, commit,
and report per finding: fixed (how) / not reproducible (evidence).

Clock contract reminder (CONTRACTS §3): Feel.real_delta/real_now for input, camera, UI/post and rate
limits; Feel.player_delta for player timers/anims; plain delta for world VFX; NEVER the wall clock
(movie capture renders a frame in ~70 ms of wall time). Feel now divides _process deltas by the
frame's own scale, so Feel.real_delta(delta) is correct in _process too.

## 1. [high] game/combat/projectiles/projectile_manager.gd:127 (other)
**What**: ProjectileManager (tracers, :127), CasingPool (casings, casing_pool.gd:91) and MissileVisuals (hulls/flares/core ribbons/smoke, missile_visuals.gd:136/141/199/214) write WORLD-space positions into MultiMesh instance transforms, but every pool sits under WeaponSystem -> PlayerMech (player_mech.gd:162 add_child) with no top_level, so each instance is drawn at player.global_transform * world_pos, i.e. transformed twice (the exact bug saber_visual.gd:99-102 documents and fixed).

**Trigger**: Any normal play where the mech is not at the world origin with zero yaw. The sandbox PlayerSpawn (0,1,60) draws every tracer, casing and missile trail about 60 m behind (+Z) and several metres above the real rounds. The city spawn (layout offset plus yaw) puts them hundreds of metres off. They also orbit the mech whenever MechLocomotion.face_toward rotate_y's the body. Masked in tests because weapons_range.gd:27 parks the player at Vector3.ZERO. BeamPool/SparkPool slots are placed with global_* so they start in the right place, but then ride along with the body for their lifetime: blast smoke slides with an 84 m/s mech and a 500 m beam swings with yaw.

**Fix**: The proposed fix is correct. Put `top_level = true` on Beams/Sparks/Casings/Bullets/Missiles in weapon_system.tscn: a top-level node with an identity local transform enters the tree at the world origin. If you use the _ready() variant instead, keep the `global_transform = Transform3D.IDENTITY` line, because turning on top_level while the node is already in the tree keeps the player's current global transform.

**Skeptic's check**: None of the pool nodes in weapon_system.tscn:28-43 set top_level, and player_mech.gd:162 add_child's WeaponSystem under the CharacterBody3D. That body moves with move_and_slide and yaws with mech_locomotion.gd:177 body.rotate_y. MultiMesh instance transforms are local to their MultiMeshInstance3D, so the world positions written at projectile_manager.gd:127, casing_pool.gd:91 and missile_visuals.gd:136/141/199/214 get drawn at player_xf * world_pos. The Beam/SparkPool slots placed with global_* then ride along with the body. weapons_range.gd:27 parks the rig at ZERO, which hides the bug in captures.

## 2. [high] game/combat/weapons/hailstorm.gd:70 (integrator)
**What**: _paint keeps subtracting player_dt from _lock_timer every tick while _add_lock() fails, so painting with nothing lockable banks lock debt, which the while loop then pays out as a burst of locks in a single tick, defeating the 0.1 s lock_interval pacing.

**Trigger**: Hold `missiles` for 1.2 s with no target in the paint box (_lock_timer reaches -1.2), then sweep onto 3 enemies. In one physics tick the loop adds 12 locks (4 per target) and fire() triggers at once, instead of one lock every 0.1 s. The same burst happens whenever one target saturates at lock_per_target and the box moves on to new targets.

**Fix**: The proposed fix is correct. Inside the loop _lock_timer is always <= 0, so `maxf(_lock_timer, 0.0)` is the same as `_lock_timer = 0.0` before the break.

**Skeptic's check**: hailstorm.gd:68 subtracts player_dt every painting tick. When _add_lock() fails (no target in the box, no line of sight, or every target already at lock_per_target), the `break` at :70-71 leaves _lock_timer negative, so the debt grows until the paint_auto_fire limit (3 s). Once targets enter the box, the while loop at :69 pays the debt out as up to lock_max (12) locks in one tick, and :73 fires the salvo right away. Nothing in AimSystem.targets_in_view (aim_system.gd:77-94) paces this.

## 3. [high] game/combat/weapons/weapon_system.gd:136 (clock)
**What**: The gatling's timers (heat cooling, VENT needle sweep, 3.2 s jam, 0.8 s good-vent delay, belt reload, 4 s Superheated) only advance inside `gatling.update()`. `_swap` calls that only while the gatling is the current weapon and no swap is running, so the timers freeze for every 0.35 s swap (the early return at 133-135) and for as long as the rifle is out. This contradicts gatling.gd:203 ("Heat, jam and Superheated timers keep running"), and the reticle keeps drawing the frozen heat arc and needle while the rifle is equipped.

**Trigger**: Fire the gatling to heat ≈ 60, or overheat it or miss the vent, then press weapon_next. With the rifle out, the reticle's heat arc (drawn whenever hud_state has "heat", which WeaponSystem always includes) never cools, the overheat blink and vent needle stay frozen mid-sweep, and the jam and reload never finish. Superheated can be banked indefinitely. On swapping back, everything resumes exactly where it stopped.

**Fix**: Before the early return in `_swap`, add `if current != GATLING or _swap_left > 0.0: gatling.update(player_dt, false, false, false)`; the existing active-weapon call stays, so nothing is ticked twice. One side effect: a VENT sweep left running while holstered will auto-jam and play gatling_jam at muzzle_r (gatling.gd:111-117) while the rifle is out. If that Feel row is unwanted, add a tick_holstered() that runs the timers and cooling but resolves VENT silently.

**Skeptic's check**: Only gatling.update() advances superheated_left, _vent_t, the VENT_GOOD/JAM/RELOAD _timer and the cooling (gatling.gd:60-82, 124-126). weapon_system.gd:133-141 calls it only when current == GATLING and no swap is running, so everything freezes while the rifle is out, despite the 'timers keep running' comment at gatling.gd:203. weapon_system.gd:177-179 always publishes the frozen heat and needle, and reticle.gd:126-136 draws them. One correction: the overheat blink runs on the HUD's own clock and keeps blinking; what never clears is the overheated state.

## 4. [low] game/combat/projectiles/beam_pool.gd:171 (other)
**What**: ring() makes the slot visible and stores `life` as its countdown. With life <= 0, _fade_ring returns early on `_ring_left[i] <= 0.0` (line 246) and never fades or hides it, so the ring stays frozen at 15 % size and full brightness until a later ring() call reuses the slot.

**Trigger**: RifleTuning.shock_ring_time set to 0 (a tuning duration of 0, e.g. to disable the stage-2 shock ring). Every stage-2 shot then leaves a static bright ring at its muzzle position until the next shot.

**Fix**: Add `if life <= 0.0: return -1` before `node.visible = true`, so a duration of 0 disables the ring. `maxf(life, 0.001)` also works.

**Skeptic's check**: ring() (beam_pool.gd:165-172) makes the node visible and stores life without checking it. _fade_ring returns at :246 on `_ring_left <= 0` before it ever reaches the hide at :252-253, so with life <= 0 the ring stays at 15 % scale and full alpha until _free() (:197-201) hands that slot to a later ring(). With current data this can only happen through tuning: rifle.gd:190 passes a constant 0.14, and shock_ring_time (rifle_tuning.gd:45, default 0.12) is an unconstrained @export. The muzzle ring takes the lower free slot first, so under plain fire the frozen shock ring can stay up indefinitely.

## 5. [low] game/combat/projectiles/beam_pool.gd:171 (clock)
**What**: `ring()` makes the node visible and stores `life` unchecked. With life ≤ 0, `_fade_ring` returns early on its `_ring_left <= 0` guard and never hides the ring, so it stays frozen on screen at 15 % size until that slot happens to be reused. `beam()` already guards its life with `maxf(life, FADE + HOLD)`; `ring()` has no such guard.

**Trigger**: An exported tuning of 0, e.g. `RifleTuning.shock_ring_time = 0`. Every stage-2 shot then leaves a bright 1.8 m torus hanging at the old muzzle position until the next ring call reuses that slot, which can be indefinitely if the player stops firing the rifle.

**Fix**: Same as [4]: `if life <= 0.0: return -1` before making the node visible.

**Skeptic's check**: Duplicate of [4]: the same path (beam_pool.gd:171 stores life unchecked, and the :246 early return means the ring is never hidden) with the same tuning-only trigger (shock_ring_time <= 0; default 0.12, and the other caller passes 0.14). beam() guards its life with maxf(life, FADE + HOLD) at :136; ring() has no such guard.

## 6. [low] game/combat/projectiles/beam_pool.gd:241 (other)
**What**: The After (afterglow) layer is a child of the core cylinder, so `_beams[i].visible = false` at the end of the core's life also hides the afterglow. A charged shot's afterglow_time (0.4 s) is cut to the 0.14 s beam life, and _free(_beam_left) hands the slot to the next beam while _after_left is still counting.

**Trigger**: Every stage-1/stage-2 rifle shot: rifle.gd:186-188 passes beam_life 0.14 s and afterglow 0.4 s.

**Fix**: The proposed fix works. The core alpha is already 0 at :238, so keeping the core visible draws nothing. Move the core hide into the afterglow-end branch (hide when both timers are <= 0), and make beam() take a slot only when both _beam_left and _after_left are <= 0. Otherwise a reused slot moves the fading afterglow.

**Skeptic's check**: beam_pool.gd:84 parents the Glow and After layers under the core MeshInstance3D. :240-241 hides the core when _beam_left runs out (0.14 s, from rifle.gd:187 and the maxf at :136), and in Godot that hides the After child too, while _after_left (0.4 s for charged shots, rifle.gd:188) is still fading at :227-233. The afterglow pops off at 0.14 s.

## 7. [low] game/combat/projectiles/missile_visuals.gd:189 (other)
**What**: _trail calls _smoke_at for all SAMPLES history slots, including ones the current missile never wrote. Those still hold the resize() defaults (time 0.0, position Vector3.ZERO), so while _now < SMOKE_LIFE they render as up to 19 smoke puffs at the pool origin. Only the core ribbon has the `s >= _filled[i]` guard.

**Trigger**: A Hailstorm salvo within the first 1.5 s after MissileManager starts ticking (cooldown starts at 0), e.g. a range/integration test or an early capture that fires immediately. The unfilled samples have age = _now <= 1.5 and are drawn as a grey blob at the local origin.

**Fix**: Use the `_times[i].fill(-1.0e9)` initialisation in _ready(). The alternative `s >= _filled[i]` smoke guard is worse: missile_manager.gd:94-98 reuses the lowest free slot, so a slot freed mid-salvo gets reused, and the guard would then hide the retired missile's lingering smoke, which retire() is supposed to leave behind.

**Skeptic's check**: missile_visuals.gd:42-51 leaves _pts/_times at ZERO/0.0, launch() (:108-113) writes only sample 0, and _trail (:185-189) passes every sample to _smoke_at, whose only guard is `age > SMOKE_LIFE`. While _now <= 1.5 s (it starts at 0 and only advances in begin()), each launched missile's 19 unwritten samples are drawn as puffs at the pool origin. This only shows when a salvo fires in the first 1.5 s of world time. That can happen in --sandbox free play, where the hero acts immediately and the Hailstorm cooldown starts at 0, or in a capture that taps `missiles` early. The normal title/drop-in lasts longer than that.
