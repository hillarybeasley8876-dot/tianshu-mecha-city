# melee-defense — numeric-robustness audit (lead, 2026-11-02) — 6 verified findings

A 36-agent audit read every non-test script twice (non-finite math; clocks + integrators) and a skeptic
tried to refute each finding; these survived. Fix them all (the proposed fixes were checked by the
skeptic — where it corrected one, the correction is what is written under *fix*). Add a regression check
for each high one in your suite, keep every suite green, run one scripted fight with `--nan-watch`, commit,
and report per finding: fixed (how) / not reproducible (evidence).

Clock contract reminder (CONTRACTS §3): Feel.real_delta/real_now for input, camera, UI/post and rate
limits; Feel.player_delta for player timers/anims; plain delta for world VFX; NEVER the wall clock
(movie capture renders a frame in ~70 ms of wall time). Feel now divides _process deltas by the
frame's own scale, so Feel.real_delta(delta) is correct in _process too.

## 1. [high] game/combat/melee/execution_director.gd:142 (clock)
**What**: The Core Rend counts `_left` down on Feel.player_delta, but the camera cut it requests (`request_cinematic(shots, duration)`, line 202) advances on Feel.real_delta (camera_rig.gd:210-212 → CameraCinematic.advance). Every execution slows player time on its own, so the cinematic ends and its shot schedule runs about 0.25-0.3 s ahead of the execution.

**Trigger**: Any Core Rend. In start(), enemy_base.execute_hit plays `finisher` (non-witch slow-mo 0.3x for 0.3 s, so player_delta is the scaled delta). The victim's death also plays kill_small or kill_large (a GLOBAL hit-stop of 0.04 or 0.1 s at scale 0.05). _rupture() at 45% plays `finisher` again, which clears its 0.5 s cooldown. For a light execution (0.9 s) the execution ends at about 1.17 s real, but the camera hands control back at 0.9 s, about 16 frames early. The 'core' shot at t=0.45 s real now lands before the rupture (about 0.55 s real). The header comment's intent, 'a hit-stop during the finisher holds the shot', is not met.

**Fix**: Do not switch the rig's advance to player_delta for everything: request_cinematic is also used by drop_in.gd:48, victory_director.gd:30 and game_flow.gd:272, which are real-time presentation. Add a per-request clock instead, e.g. `request_cinematic(shots, duration, player_clock := false)`: ExecutionDirector passes true, and the rig advances that cut with Feel.player_delta(delta) while shake stays on real dt. Moving _left to real_delta instead would desync the director from the hero AnimationTree, which runs on the player clock (hero_model.gd:95-107).

**Skeptic's check**: _left counts down on Feel.player_delta (execution_director.gd:142). Outside witch time that is the scaled delta (feel.gd:125-139). CameraCinematic.advance runs on Feel.real_delta (camera_rig.gd:210-212, camera_cinematic.gd:54-58). Every Core Rend plays `finisher` through enemy_base.execute_hit (enemy_base.gd:245), and FeelDirector._time turns it into Feel.slow_mo(0.3, 0.3, ..., witch=false) (finisher.tres has no slow_witch). The victim's kill_* adds a GLOBAL hit-stop, and _rupture plays `finisher` again after its 0.5 s cooldown. For a light execution the cut therefore ends at 0.9 s real but the execution at about 1.17 s, and the core shot (0.45 s real) lands before the rupture (about 0.55 s real). Nothing links `finished` to the camera.

## 2. [medium] game/combat/defense/catch_field.gd:37 (clock)
**What**: The 3 s hold limit `_held` starts counting when the catch field opens, not when the first round is caught, and only release()/clear() reset it. Once the field has been open and empty for 3 s, every newly caught round is thrown back on the same tick it is caught, and after an auto-release the next hold is cut short by however long the field sat empty.

**Trigger**: Hold guard for 3.3 s or more (CATCH_HOLD 0.3 + CATCH_MAX_TIME 3.0, about 440 of 1000 EN) with no enemy shot inside the 12 m hemisphere, e.g. holding through a telegraphed Spitter/Harrier volley. tick() catches the first shot, then defense_system.gd:152 sees held_time() >= 3.0 and count() > 0 and calls release() in the same tick. Rounds never freeze or orbit, and the catch becomes an instant reflector.

**Fix**: As proposed: in tick(), after _drop_dead() and _capture(), use `_held = 0.0 if caught.is_empty() else _held + delta`. If the spec's 'max 3 s' is instead meant as total field time (TF Vortex style), the field must stop catching after 3 s rather than keep insta-bouncing.

**Skeptic's check**: _held grows on every tick() (catch_field.gd:37), which runs from the moment the field opens (defense_system.gd:150-151), and is reset only by release() or clear(). The auto-release check (defense_system.gd:152-154) runs right after _catch in the same tick. So after 3 s or more of empty field, the first shot caught is frozen and thrown back on the same tick and never orbits, and a round caught t s into a cycle is held only 3-t s. That contradicts the documented 'freeze and orbit ... 3 s max' (catch_field.gd:4) and 'can only hold for 3 s' (defense_system.gd:153). The finding overstates one point: release() zeroes _held (line 131), so only the first catch after the empty stretch is bounced; later catches are held again, just cut short by any empty time.

## 3. [medium] game/combat/defense/catch_field.gd:150 (nonfinite)
**What**: clear() turns physics back on for rounds whose velocity _freeze() set to Vector3.ZERO (lines 89-93) but never restores that velocity, so the released rounds resume as projectiles that never move.

**Trigger**: Hold guard past 0.3 s so the field holds rounds, then let EN hit 0 (the catch drains 140 EN/s; easy after flying or dashing). _drain -> _break_guard() -> field.clear(). DefenseSystem.reset() on respawn takes the same path. Ballistic EnemyProjectiles (harrier bursts, ballistic=true) then hang still at their orbit slots about 9 m around the mech for the rest of their 6 s life, and hit the mech if it walks into them. Arc shots drop straight down from rest.

**Fix**: Keep each shot's velocity on the CatchField side (a Dictionary keyed by the shot, not shot meta: EnemyProjectile.deactivate only strips its own meta keys, so a 'catch_velocity' meta would stay on pooled shots). Restore it in clear() before set_physics_process(true). Or, on a guard break, return EnemyProjectiles to the pool or reflect them. Must ship together with fix [1], or the same tick re-freezes them.

**Skeptic's check**: _freeze() sets velocity to ZERO (catch_field.gd:89-93), and clear() turns physics back on without restoring it (147-153). _break_guard() (defense_system.gd:174-177) and reset() (407-418) call clear() while rounds are still held; only _end_guard releases first. EnemyProjectile._physics_process (enemy_projectile.gd:78-91) then moves them with zero velocity. Harrier strafe rounds (no blast_radius, so ballistic=true, harrier.gd:7-11) hang in their orbit slots for the rest of their life, and Spitter lobs fall from rest and blow up (12 m blast) next to the mech. The trigger is easy: the guard drains EN through MechEnergy._spend, which returns false at 0 (mech_energy.gd:53-68).

## 4. [medium] game/combat/defense/defense_system.gd:150 (other)
**What**: _guard() computes `catching` before _drain() and still calls _catch(delta) after _drain() broke the guard in the same tick, so the cleared field re-captures and freezes (physics off, velocity zero) every round in front, including about half of the rounds clear() just let go, and nothing ever services or releases them.

**Trigger**: On the tick EN runs out during the catch phase: _drain -> _break_guard() (state BROKEN, field.clear()) -> _catch -> field.tick -> _capture() grabs everything within 12 m in the front hemisphere. The just-released orbit rounds are at about 9 m, so roughly half are re-frozen. During the 1 s break _physics_process returns early. Afterwards state is IDLE, so neither _end_guard nor the 3 s auto-release runs. EnemyProjectile only ages in its own _physics_process, so these rounds hang frozen in mid-air (and stay out of the pool) until the player completes another full guard.

**Fix**: As proposed: after `_drain(delta, catching)` add `if state == State.BROKEN: return`, so both _catch and the auto-release are skipped. Combine with fix [0].

**Skeptic's check**: `catching` is computed before _drain (defense_system.gd:147-151). _drain -> _break_guard sets BROKEN and calls field.clear(), but _catch(delta) still runs field.tick -> _capture (catch_field.gd:45-70). That re-freezes every reflectable shot within 12 m in the front hemisphere, including the front half of the 9 m orbit disk it just released. _held is then only one delta, so there is no auto-release. During the break, _physics_process returns at line 75-76. Afterwards state is IDLE, so _guard returns at line 140 and _end_guard cannot run (line 101 needs state != IDLE). The rounds stay frozen with physics off and never age until the next guard press.

## 5. [low] game/combat/defense/defense_system.gd:294 (clock)
**What**: The parry-recoil SceneTreeTimer is created with the default process_always=true, so the attacker's 0.6 s AI lockout keeps counting while the tree is paused.

**Trigger**: Perfect-parry a melee attacker (hit.parryable), then open the pause menu within 0.6 s. The timer expires during the pause (Feel even forces time_scale to 1.0 while paused), and on resume the attacker's AI is already back, so the recoil reward is lost.

**Fix**: `get_tree().create_timer(DefenseTable.PARRY_RECOIL, false, true)`: pausable, ticked on physics frames, still on scaled world time.

**Skeptic's check**: `get_tree().create_timer(DefenseTable.PARRY_RECOIL)` (defense_system.gd:294) uses the default process_always=true, so it keeps counting while the tree is paused. The pause menu really pauses the tree (menu_root.gd:266), and Feel forces time_scale to 1.0 while paused (feel.gd:164). EnemyBase.set_ai_enabled exists (enemy_base.gd:166) and gates the brain (line 288), and parryable melee hits carry the enemy as source (enemy_attack.gd:56-65). So pausing within 0.6 s of a perfect parry re-enables the AI during the pause, and the recoil reward is gone on resume.

## 6. [low] game/combat/melee/saber_visual.gd:151 (clock)
**What**: The 0.2 s `_swing_hold` that keeps the blade on its arc pose after each active tick counts down on scaled _process delta (world clock), and so do `_fade` and `_hum`. The swing it belongs to is stepped on Feel.player_delta (melee_system.gd:94), so in witch time the hold drifts from the player's move.

**Trigger**: A perfect dodge (witch time 0.3x for 0.35 s), then L1/L2. After the active window the blade stays parked at the arc-end pose for about 0.4 s real instead of 0.2 s, while the full-speed recovery and the next move's startup play. The blade does not return to the saber_r socket between swings.

**Fix**: `_swing_hold = maxf(_swing_hold - Feel.player_delta(delta), 0.0)`. _fade and _hum are VFX and can stay on plain delta per CONTRACTS.

**Skeptic's check**: _swing_hold is re-armed on every active tick of a swing stepped on Feel.player_delta (melee_system.gd:94, melee_strike.gd:37). The saber_r socket it falls back to is moved by the hero AnimationTree on player_delta (hero_model.gd:95-107). But the hold decays on the scaled _process delta (saber_visual.gd:151), so the two drift in witch time (player_mech.gd:213: 0.3x, 0.35 s, witch=true). The finding overstates the size. An L1 pressed when witch time starts ends its active window at about 0.21 s, when the slow-mo is already easing out, so the hold lasts about 0.25 s real instead of 0.2 s (worst case about 0.37 s). The L1->L2 chain skips the socket even at 1.0x, because L2's startup is 0.133 s, shorter than the 0.2 s hold. Low impact, but it is a real clock mismatch.

## Lead decision for the Core Rend clock finding
camera-aim is adding `request_cinematic(shots, duration, clock := &"player")` (CONTRACTS §5). Pass `&"player"`
for executions once it lands (check `get_method_argument_count` or wait for camera-aim's commit — it is in the
same audit round); keep your own `_left` on `Feel.player_delta`.
