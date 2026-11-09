# enemies — numeric-robustness audit (lead, 2026-11-02) — 13 verified findings

A 36-agent audit read every non-test script twice (non-finite math; clocks + integrators) and a skeptic
tried to refute each finding; these survived. Fix them all (the proposed fixes were checked by the
skeptic — where it corrected one, the correction is what is written under *fix*). Add a regression check
for each high one in your suite, keep every suite green, run one scripted fight with `--nan-watch`, commit,
and report per finding: fixed (how) / not reproducible (evidence).

Clock contract reminder (CONTRACTS §3): Feel.real_delta/real_now for input, camera, UI/post and rate
limits; Feel.player_delta for player timers/anims; plain delta for world VFX; NEVER the wall clock
(movie capture renders a frame in ~70 ms of wall time). Feel now divides _process deltas by the
frame's own scale, so Feel.real_delta(delta) is correct in _process too.

## 1. [high] game/enemies/enemy_base.gd:304 (integrator)
**What**: _integrate adds the whole decaying _knockback to the persistent CharacterBody3D velocity on every tick (v += _knockback), but only decays it at 40 m/s^2. One hit of K m/s therefore injects about K^2/(2*40*dt) = 1.5*K^2 m/s of velocity before the cap, and the effect scales with the physics tick rate.

**Trigger**: Any player hit with knockback in normal combat. A MeleeTable knockback of 8-18 m/s on a ripper (mass 1) adds roughly 100-490 m/s over 0.2-0.45 s, so the ripper is flung at the 60 m/s limit_length cap and travels about 20-35 m instead of 1-4 m. A knockback with an upward component (pitched melee facing) launches ground monsters into the air. A missile hit (6 m/s) still adds about 54 m/s. At a higher tick rate the effect doubles.

**Fix**: Prefer the offset form: velocity = v + _knockback; move_and_slide(); velocity -= _knockback; then decay _knockback at 40 m/s^2. That gives about K^2/80 m of travel. A one-shot impulse would be cancelled by steer_dir (120 m/s^2 per axis on a ripper) in about 0.1 s. Also stop MeleeStrike.shove from adding knockback to receivers that handle it in take_hit (EnemyBase), so it is applied once.

**Skeptic's check**: velocity persists across ticks (enemy_base.gd:297/306), but the whole remaining _knockback is added on every tick and decays at only 40 m/s^2 (304-305). A 1/120 s simulation with ripper steering gives: K=8 injects about 100 m/s, K=14 about 300 m/s, K=18 about 495 m/s. The ripper is pushed back 14-40 m at the 60 m/s cap instead of about K^2/80 = 1-4 m. Melee is also applied twice: MeleeStrike.shove (combat/melee/melee_strike.gd:69-72) adds hit.knockback to the enemy CharacterBody3D on top of take_hit.

## 2. [high] game/enemies/enemy_base.gd:322 (other)
**What**: The wreck/dissolve timer has no latch. Once _dead_time passes wreck_lifetime + DISSOLVE_TIME, _tick_wreck calls _finish_dissolve() on every physics tick, and a reclaimed (pooled) ripper is never freed, so `dissolved` fires 120 times a second for as long as it sits in the pool (same on lines 313-314 for the model-less path).

**Trigger**: Any ripper about 31 s after it dies. EnemySpawner._on_dissolved appends the same instance to the ripper free list on every tick (no dedupe). Later spawn(&"ripper") calls (FlowSpawner.spawn_ring waves) pop the same live ripper again and again, teleporting and resetting it instead of creating new ones: a ring of 8 yields 1. The free list grows without bound and _live.erase runs every tick.

**Fix**: Same as [3], and also skip `reused.alive` entries in _take.

**Skeptic's check**: Duplicate of [3]. There is no latch on _finish_dissolve (enemy_base.gd:313-314, 322-323), the free list is appended without a dedupe (spawner.gd:134), and _take pops live rippers without checking alive (spawner.gd:108-111).

## 3. [high] game/enemies/enemy_base.gd:323 (other)
**What**: After a pooled ripper finishes dissolving and the spawner reclaims it, the node stays alive == false with physics processing on. _tick_wreck therefore calls _finish_dissolve() again on every tick (line 314 does the same when model is null). dissolved fires 120 times per second, and EnemySpawner._on_dissolved (spawner.gd:134) appends the same ripper to the free list each time without deduping. _take (spawner.gd:110) then returns entries without checking alive.

**Trigger**: Rippers die, and 31.2 s later each reclaimed wreck appends itself about 120 times per second. The pool grows without bound (about 430k entries per pooled ripper per hour), and each tick also costs a signal plus a _live.erase. The next FlowSpawner.spawn_ring(RIPPER, n) gets at most as many distinct rippers as are pooled. Further pops return rippers spawned moments earlier: they are teleported to the new ring, recycle() resets their HP, and the encounter director counts the duplicates in live and wave_size. Once every pooled ripper is alive, each later ripper spawn steals a live one instead of instancing a new one.

**Fix**: As proposed: latch the dissolve (a _dissolved flag or set_physics_process(false) once reclaimed, cleared or re-enabled in recycle()). In _on_dissolved, append only `if not free_list.has(enemy)`; in _take, skip entries where reused.alive.

**Skeptic's check**: After the first dissolve, alive stays false and nothing disables physics (no set_physics_process anywhere in enemies/). _tick_wreck therefore calls _finish_dissolve on every tick (enemy_base.gd:319-323, and 313-314 when there is no model). Each call emits dissolved, and spawner._on_dissolved appends the same ripper again without a dedupe (spawner.gd:133-135). _take returns any valid entry without checking alive (108-111), and spawn() then teleports and recycles a ripper that is already alive (80-81).

## 4. [high] game/enemies/locomotion.gd:93 (nonfinite)
**What**: nav_step passes steer_dir the raw offset to the next nav corner instead of a unit direction. steer_dir multiplies it by move_speed (target_v = want * speed), so a ground monster with no pack neighbour (avoid_bias == ZERO, so the value is never normalized) targets |offset| x speed and accelerates until EnemyBase._integrate's limit_length(max(2*move_speed, 60)) clamps it.

**Trigger**: Any lone ripper, mantis, spitter or juggernaut walking a nav path (approach, position, or patrol at PATROL_SPEED 0.35). With the next corner 20-200 m away, the target speed is 20-200x move_speed, so the monster runs at 60 m/s. The recorded tmp/enemies/test_ai.log shows 'juggernaut:approach@68m v60', 'mantis:approach@133m v60' and 'ripper:approach@72m v60' against tuned speeds of 20/24/30 m/s; pack members, whose bias does get normalized, show v30. The same oversized want also drowns _unstick's sideways push (want*0.4 + side*1.6), so wedged ground monsters never get unstuck.

**Fix**: Normalize inside steer_dir itself: `var want := dir.normalized() if dir.length_squared() > 1e-4 else Vector3.ZERO`, so every caller is safe. Land it together with the [1] leash fix: slower, correct approaches keep monsters outside the leash's near radius for longer.

**Skeptic's check**: nav_step passes the raw offset dir = next - pos (locomotion.gd:88-93). steer_dir only normalizes when avoid_bias != ZERO (112-113), so a lone ground monster targets |dir| x speed (123), and only the cap in _integrate stops it (enemy_base.gd:306). A Godot 4.7.2 probe on open ground returned get_next_path_position() = the final point 40 m away. tmp/enemies/test_ai.log T2.0 shows juggernaut:approach@68m v60 (tuned speed 20) and lone rippers at v60 (speed 30), while pack rippers run at v30.

## 5. [high] game/enemies/spawner.gd:64 (nonfinite)
**What**: _leash teleports a 'lost' ground monster straight to _reachable_ring_point(player, ...) without running it through _grounded(). When the player is airborne, every _paths_to test fails (the path ends on the navmesh under the player, more than 30 m from the airborne centre), so the raw fallback at line 180/192 becomes the new position: 150 m out, at the player's flight altitude, never checked against buildings or the +/-700 m map edge. An airborne player is also what marks every melee monster as lost in the first place: line 55 uses a 3D near test, and is_target_reachable() measures against an airborne target_position.

**Trigger**: The player hovers or flies for 8 s or more (4 leash checks at 2 s). Every ripper, mantis or juggernaut more than 2x engage_range away in 3D (36/60/80 m, which is all of them once the player is that high) gets is_target_reachable() == false. Above about 30 m they are teleported to the player's altitude 150 m away (inside a tower, or into the void past the edge near the map border) and fall. Between 4 and 30 m they are pulled out to 150-250 m on the navmesh. Both repeat every 8 s while the player stays up.

**Fix**: Apply the proposed fixes: leash against the ground under the player, use a horizontal near test, and set e.global_position = _grounded(_reachable_ring_point(ground, ...), e.enemy_type). Also make reachability meaningful. In nav_step, give the agent a navmesh-projected goal (NavigationServer3D.map_get_closest_point). Or compare get_final_position() to that goal horizontally, with a height tolerance larger than the player's 7.5 m origin offset. Otherwise the leash keeps relocating monsters that are merely farther than 2x engage_range.

**Skeptic's check**: _leash uses a 3D near test (spawner.gd:55) and agent.is_target_reachable(). The agent's target is desired_point at the player's origin height (perception.gd:99, enemy_base.gd:407, locomotion.gd:86). In a 4.7.2 probe with target_desired_distance 4, a target 10 m or 50 m above the navmesh gave reachable=false (3 m gave true). Above about 30 m every _paths_to test fails (spawner.gd:210), and the raw fallback at the player's altitude (180/192) is assigned at line 64 with no _grounded(). Worse than reported: the player origin is the capsule centre, 7.5 m above the feet (CONTRACTS §5, mech_tuning.gd capsule_height 15), so reachability is false even while the player stands on the ground.

## 6. [high] game/enemies/status_component.gd:121 (integrator)
**What**: _tick_slow zeroes pull_accel at the start of every status.tick(), and EnemyBase._physics_process calls status.tick(dt) (enemy_base.gd:286) BEFORE _integrate reads status.pull_accel (enemy_base.gd:303), so the Undertow Well pull is always zero when integrated.

**Trigger**: Any Undertow Well over light monsters: UndertowWell._tick_field calls apply_pull every tick, but whichever order player and enemies process in, the value is cleared before EnemyBase._integrate uses it, so real enemies are never pulled. The skills test dummy (combat/skills/tests/dummy_enemy.gd:76-78) reads pull_accel before tick() and so hides this in tests.

**Fix**: Same as [4]. Consuming the pull before or after tick() still lets steer_dir and decelerate cancel almost all of it, so apply it as a velocity term that steering does not re-target.

**Skeptic's check**: Duplicate of [4]. status.tick() at enemy_base.gd:286 runs _tick_slow, which clears pull_accel (status_component.gd:121), before _integrate reads it at enemy_base.gd:303. The dummy_enemy.gd:76-78 workaround confirms the ordering problem.

## 7. [medium] game/enemies/brain.gd:213 (clock)
**What**: _begin_attack calls host.face_dir(..., 1.0) with a hard-coded 1 s dt, so at every attack start the monster rotates up to a full second of turn_rate in a single 8 ms tick.

**Trigger**: The player flanks a juggernaut (turn 150 deg/s; its own header says 'getting behind it is the whole fight'). At the start of each swipe or charge, the 22 m model pops up to 150 deg toward the player in one tick, cancelling the flank. Rippers and mantis (540/360 deg/s) snap fully regardless of angle.

**Fix**: Drop the call: attack_windup already turns at turn_rate on every telegraph tick (enemy_base.gd:424, juggernaut.gd:58). Alternatively, pass the think dt through.

**Skeptic's check**: brain.gd:213 passes dt = 1.0, so face_dir's step equals the full turn_rate in degrees (enemy_base.gd:480-482): up to 150 deg in one tick for the juggernaut, and a full snap for rippers and mantis. _ready_to_attack has no facing check (brain.gd:188-197), so a flanked juggernaut pops around and its 160 deg swipe connects, when the 0.45 s windup at 150 deg/s would turn it only 67.5 deg.

## 8. [medium] game/enemies/status_component.gd:121 (other)
**What**: _tick_slow zeroes pull_accel at the start of every status.tick(). EnemyBase._physics_process runs status.tick(dt) (line 286) before _integrate reads status.pull_accel (line 303). The pull that the Undertow well sets through apply_pull from its own tick, whether that runs before or after the enemy, is therefore always wiped before it is used.

**Trigger**: An Undertow well field over rippers or any other non-heavy, non-boss monster. undertow_well.gd calls apply_pull(to.normalized()*speed*4, 0.1) every tick, but v += status.pull_accel * dt always adds zero, so the swarm is never pulled. _slow_amount also stays at 1.0, so those monsters are not slowed either; the well only primes them.

**Fix**: Consume, then clear, in _integrate. That alone is not enough: each tick, steer_dir and decelerate move velocity back toward the brain's target by up to 120 m/s^2 per axis on a ripper, against a pull of at most 72 m/s^2, so the net drift is only about 0.6 m/s. Apply the pull as a term steering cannot cancel. Either add a pull velocity to steer_dir's target_v, or use a move-only offset in _integrate as in the [2] fix.

**Skeptic's check**: _tick_slow zeroes pull_accel (status_component.gd:121) inside status.tick at enemy_base.gd:286, before _integrate reads it at 303, and nothing can write it in between. combat/skills/tests/dummy_enemy.gd:76-78 even reads it before tick() for exactly this reason. The well pulls only non-heavy targets, i.e. ripper and harrier (undertow_well.gd:191-198; skill_context.is_heavy is mass >= 3). Those monsters not being slowed is by design.

## 9. [medium] game/enemies/status_component.gd:220 (other)
**What**: apply_pull extends _slow_left without setting _slow_amount, and _slow_amount is never reset (not when the slow expires, not in reset()), so every pull re-applies the last slow factor the monster ever received.

**Trigger**: A ripper hit by a Skyhook yank or a Plunge air-lock (apply_slow(0.0, ...) -> _slow_amount 0.05), or a pooled ripper recycled after one, later enters an Undertow Well. apply_pull on every tick keeps _slow_left > 0, _tick_slow sets slow_factor = 0.05, and the ripper crawls at 5 % speed for the whole field.

**Fix**: As proposed: give the pull its own timer, and reset _slow_amount = 1.0 on expiry and in reset().

**Skeptic's check**: apply_pull extends _slow_left without setting _slow_amount (status_component.gd:218-220). _tick_slow then applies whatever _slow_amount was last set (127-128). Neither the expiry (126) nor reset() (59-73) restores it to 1.0. Skyhook yank and Plunge air-lock call apply_slow(0.0, ...), which leaves _slow_amount at 0.05 (skyhook_anchor.gd:311, plunge_breaker.gd:234). A later well, or the ripper's next pooled life, therefore crawls at 5 % speed.

## 10. [low] game/enemies/mantis/mantis.gd:80 (integrator)
**What**: The aimed-shot sidestep calls loco.dash_along(side, move_speed * 1.6, delta) for a single physics tick. dash_along moves velocity by at most speed*6*dt (about 1.9 m/s), and the brain's steering pulls it back over the next few ticks. The mantis plays the sidestep clip but moves only about 3 cm.

**Trigger**: The player aims straight at a mantis ((-facing.z).dot(to_me) >= 0.93). There is one dash_along call per 2.6 s cooldown, adding about 1.9 m/s that decays at 0.8 m/s per tick.

**Fix**: Store the side direction and a short sidestep window (about 0.3 s), and call dash_along every tick while it runs, suppressing brain steering during it. Alternatively, set the lateral velocity directly once.

**Skeptic's check**: The sidestep is one dash_along call per 2.6 s cooldown (mantis.gd:80-82). Its rate is 24*1.6*6/120 = 1.92 m/s. On the next ticks, steer_dir (0.8 m/s per tick) or decelerate (1.0 m/s per tick) cancel it, so the mantis moves about 1-3 cm while playing the sidestep clip.

## 11. [low] game/enemies/spawner.gd:67 (integrator)
**What**: _leash calls e.loco.steer_to(player, 1.0, step) with step = LEASH_INTERVAL (2.0 s) as dt. In one call that applies 8x move_speed of acceleration and adds 2 s to _blocked_for, which immediately trips the unstick logic.

**Trigger**: A monster relocated after 8 s unreachable. Its velocity was just zeroed, so _unstick counts it 'blocked' for 2 s (>= UNSTICK_AFTER) and returns the sideways unstick direction. The teleported monster leaves its new spot at full speed, about 76 deg off the player direction, and veers back over the next 0.3-0.5 s.

**Fix**: Remove the steer_to call. The brain steers on the next physics tick.

**Skeptic's check**: spawner.gd:67 passes step = 2.0 s as dt. steer_dir's accel becomes 8x move_speed (locomotion.gd:124). _unstick sees zero velocity right after line 66, adds 2 s to _blocked_for and trips unstick (139-146). The relocated monster leaves at full speed, 76 deg off (or along a stale avoid_bias), for about 0.25 s. Low impact, and reached whenever [1] relocates a monster.

## 12. [low] game/enemies/strike.gd:91 (nonfinite)
**What**: Projectile attacks aim at host.target_centre(), which falls back to the shooter's own global_position when perception.target is null (enemy_base.gd:467-468). A ranged attack started against a remembered hunt point therefore fires from the muzzle back at the monster's own origin.

**Trigger**: The player stays out of sight longer than LOSE_MEMORY (10 s), or dies or is freed mid-telegraph, while the brain keeps attacking last_known (_ready_to_attack uses the hunt distance). Harrier strafe bolts then fly from the head down and back through its own body into the ground, and spitter acid lobs splash at its own feet. A model without a muzzle socket (socket() falls back to the model root) would give an exactly zero direction from EnemyProjectilePool.spawn, leaving a stationary shot hanging for 6 s.

**Fix**: Do not start attacks without a live target: in _ready_to_attack, return false when host.target() == null. Also make target_centre() fall back to perception.hunt_point() + Vector3.UP * 4.0 instead of the shooter's own position, which fixes the other callers too (juggernaut choose_attack distance, harrier steer_to).

**Skeptic's check**: When the target is null, target_centre() returns the shooter's own global_position (enemy_base.gd:466-468). The brain starts attacks against last_known with no target check (brain.gd:161-164, 188-197; it never leaves APPROACH or POSITION while _has_last is set). strike.gd:91-92 then fires from the muzzle at the monster's own origin, and the shot passes through it because MASK_ENEMY_ATTACK has no enemy layers. The zero-direction sub-case cannot happen: all five shipped rig JSONs define a 'muzzle' socket.

## 13. [low] game/enemies/visuals.gd:36 (clock)
**What**: tick_vibration flips _vib_sign on every physics tick, but physics runs at 120 Hz against 60 rendered fps with physics_interpolation=false. The sign flips twice per frame, so every rendered frame shows the same side, and the hit-stop vibration (juice §2.3, 'sign alternating each frame') renders as a one-sided lurch that decays instead of a shake.

**Trigger**: Any local hit_pause (melee or explosive hits) in normal play and in movie capture, both of which run 2 physics ticks per rendered frame.

**Fix**: Alternate per rendered frame: _vib_sign = 1.0 if Engine.get_process_frames() % 2 == 0 else -1.0, or move the model.position.x write into _process.

**Skeptic's check**: project.godot sets physics_ticks_per_second=120, max_fps=60 and physics_interpolation=false. tick_vibration runs once per physics tick (enemy_base.gd:283) and flips _vib_sign every call (visuals.gd:36). Two flips per rendered frame mean every frame, in play and in fixed-fps movie capture, shows the same side of a decaying offset.
