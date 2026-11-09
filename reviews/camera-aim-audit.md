# camera-aim — numeric-robustness audit (lead, 2026-11-02) — 8 verified findings

A 36-agent audit read every non-test script twice (non-finite math; clocks + integrators) and a skeptic
tried to refute each finding; these survived. Fix them all (the proposed fixes were checked by the
skeptic — where it corrected one, the correction is what is written under *fix*). Add a regression check
for each high one in your suite, keep every suite green, run one scripted fight with `--nan-watch`, commit,
and report per finding: fixed (how) / not reproducible (evidence).

Clock contract reminder (CONTRACTS §3): Feel.real_delta/real_now for input, camera, UI/post and rate
limits; Feel.player_delta for player timers/anims; plain delta for world VFX; NEVER the wall clock
(movie capture renders a frame in ~70 ms of wall time). Feel now divides _process deltas by the
frame's own scale, so Feel.real_delta(delta) is correct in _process too.

## 1. [high] game/player/camera/camera_look.gd:61 (clock)
**What**: The right-stick look rate is converted to real time twice: the rig already passes Feel.real_delta(delta) into take_delta(), and line 61 multiplies by _real_dt(delta) = Feel.real_delta(delta) again, so the stick turn rate is divided by Engine.time_scale twice.

**Trigger**: A gamepad player holds the right stick during a global hit-stop. FeelDirector uses HITSTOP_SCALE 0.05, which makes turning 20x faster: about 50 deg per physics tick at full deflection, so the view swings 300-600 deg in a 50-100 ms freeze. At Feel.MIN_SCALE 0.02 it is 50x. Slow-mo has the same bug at smaller factors: witch time and the Zenith Lance charge (slow_mo 0.3) turn 3.3x too fast, the execution jackpot (0.2) 5x. Mouse look is unaffected because it adds raw pixels.

**Fix**: As proposed: multiply by `delta` (it is already real time) and delete _real_dt().

**Skeptic's check**: camera_rig.gd:210 already converts with dt = Feel.real_delta(delta) and passes dt through _update_look (223) to take_delta (270). camera_look.gd:61 then multiplies by _real_dt(dt) = Feel.real_delta(dt), so the stick delta is delta/ts^2 (feel.gd:131). take_delta has no other caller. Under the 0.05 global stop (feel_director.gd:23,138) a full-deflection stick turns 50 deg per tick, about 250 deg across a 0.04 s kill_small freeze.

## 2. [high] game/player/camera/camera_rig.gd:382 (other)
**What**: end_cinematic() (listed in the CONTRACTS CameraRig API) restores the arm and look but never deactivates CameraCinematic. is_cinematic() stays true, and the shot keeps being re-applied every tick until the request's own duration runs out.

**Trigger**: Every run start. FlowDropIn.begin requests the drop shots with CINEMATIC_LEN = 40 s and on Events.landed calls rig.end_cinematic(), which it documents as cutting the shot short. On the next tick _physics_process still takes the cinematic branch: _cine.advance re-applies shot 3 (arm 0, held FOV 48, _update_look skipped) until 40 s after the drop began. Because look was re-enabled, mouse motion meanwhile piles up in CameraLook._mouse, and when the cinematic finally ends the whole backlog is applied in one take_delta (big yaw jump, pitch slammed to a clamp).

**Fix**: The proposed cancel() is incomplete. It leaves CameraFov._holding = true (camera_fov.gd:95-102, 118-120), so the drop shot's held FOV 48 sticks for the rest of the run and ADS/boost FOV stop working. Use CameraCinematic `func cancel() -> void: if active: _finish()` instead. _finish releases the FOV and re-enables look. It is recursion-safe because _finish clears active before calling end_cinematic, so the nested cancel is a no-op. Call _cine.call(&"cancel") first in end_cinematic(), and call _look.call(&"flush") whenever look is re-enabled.

**Skeptic's check**: end_cinematic (camera_rig.gd:382-386) never clears CameraCinematic.active. drop_in.gd:48 requests 40 s, and the 400 m fall (fall_gravity 25.5, terminal 50 m/s) lands after about 9 s. The end_cinematic call at drop_in.gd:80 is undone on the next tick: is_cinematic() is still true (camera_rig.gd:211) and advance re-applies shot 3 for about 30 more seconds. Look was re-enabled with no flush on enable (366-369), so _mouse keeps accumulating (camera_look.gd:36) and the whole backlog lands in the first take_delta after _finish (215-217).

## 3. [medium] game/player/camera/camera_rig.gd:212 (clock)
**What**: Cinematics advance on real time, but ExecutionDirector writes its shot `t` values and duration in player time (its _left uses Feel.player_delta; its comment says 'a hit-stop during the finisher holds the shot'). The camera cut and the execution therefore drift apart whenever the execution triggers its own slow-mo or hit-stop.

**Trigger**: Any Core Rend execution. At 45 % the rupture plays `finisher` (slow_mo 0.3x for 0.3 s, not witch time) and the kill plays kill_small or kill_large (global stop 0.04 or 0.1 s at 0.05x; kill_large also adds 0.35x for 0.35 s). Player time falls about 0.12-0.2 s behind real time, so the rig's real-time _left hits zero first: _finish() -> end_cinematic() snaps the camera back behind the hero while the finisher is still playing (about 15-20 % of a 0.9 s light execution), and every shot after the rupture cuts early by the same amount.

**Fix**: Proposed per-request clock is fine: store a player_clock flag in CameraCinematic.request and have the rig pass Feel.player_delta(delta) (raw delta) to advance() for those requests; ExecutionDirector passes true; flow cinematics stay on real time.

**Skeptic's check**: The rig advances _cine on real dt (camera_rig.gd:210-212). ExecutionDirector._left counts down on Feel.player_delta (execution_director.gd:142), which is the scaled delta outside witch time (feel.gd:125-139). execute_hit kills the light victim at t=0, which fires the kill_small 0.04 s global stop (kill_large: 0.1 s), and also plays `finisher` (non-witch slow 0.3 for 0.3 s, enemy_base.gd:244-245,267). The rupture replays `finisher` about 0.55 s later, past its 0.5 s cooldown. Player time ends roughly 0.15-0.27 s behind, so _finish -> end_cinematic snaps the camera back while the execution is still running.

## 4. [medium] game/player/camera/camera_rig.gd:249 (integrator)
**What**: In first person the camera is still pulled toward the eye point by a critically damped spring (omega 40). That spring trails a moving target by 2v/omega, while cockpit_frame pins the canopy exactly to eye_point(player) every tick, so at speed the camera leaves the cockpit (contradicting 'the cockpit view is rigid').

**Trigger**: First person while boosting. At the 42 m/s skate the camera sits 2.1 m behind the eye; at 84 m/s (assault or flight boost) it sits 4.2 m behind. The struts, tuned at 1.45 m in front of the eye, recede to 3.5-5.7 m and shrink to about 25-40 % of their tuned size: the pillars slide from 75 % of the half-width toward the centre. A sideways dash puts the camera outside the 1.16 m pillar line; boosting backwards above about 30 m/s puts it in front of the glass. Raising omega cannot fix it: the 120 Hz stability limit (omega*h < 0.83) still leaves 1.7 m or more at 84 m/s.

**Fix**: The rigid-follow option must not zero _follow_vel and must not wait for _fp_t == 1: the canopy is visible from 0.5, so snapping at 1 jumps up to 4 m, and leaving FP restarts from rest. Instead, after the spring step blend the position onto the target with smoothstep(0.5, 1.0, _fp_t) and set _follow_vel to the target's velocity. Alternatively, add velocity feed-forward (2*omega*(v_target - _follow_vel)) in FP.

**Skeptic's check**: _follow (camera_rig.gd:249-250) is a pure spring with no velocity feed-forward, so in steady state it trails by 2v/omega. With omega = 40 in first person that is 2.1 m at boost_speed 42 and 4.2 m at assault/flight 84 (mech_tuning.gd:50,59,81). Up to about 7 m sideways at the 150 m/s dash peak, if the spring reaches steady state within the 0.25 s dash. In FP the arm and shoulder are 0, so the camera sits at that lagged rig position, while cockpit_frame.gd:38 pins the canopy (pillars at x ±1.16, z -1.45; cockpit_build.gd:30-31) to eye_point(). The finding's stability bound omega*h < 0.828 for this symplectic step is also correct.

## 5. [medium] game/player/camera/camera_rig.gd:288 (nonfinite)
**What**: _track_lock takes the lock yaw from atan2(-to.x, -to.z) with only a 1 m length guard. When the hard target is nearly straight above or below the pivot, that bearing comes from a near-zero horizontal offset and can flip by up to 180 deg from tick to tick. The view chases it at k = 1 - exp(-9/120) = 0.072 of the error per tick, about 13 deg per tick for a 180 deg flip, so the camera whips or orbits around the hero.

**Trigger**: A hard-locked target nearly vertical from the hero: Plunge Breaker's homing dive (kept within 30 deg of vertical, horizontal offset shrinking to 0 at impact), hovering above a locked ground enemy, or a locked Harrier diving from overhead. Pitch is clamped to -70/+75 deg, so a target at about -90 deg is only about 10-20 deg off the view. That is inside the hard lock's keep cone (22.5 deg pitch), so the lock is never dropped and the yaw keeps chasing the jittering bearing; the player's own look input fights it.

**Fix**: As proposed: scale the yaw step by smoothstep(0.15, 0.35, flat / to.length()) and keep the pitch term.

**Skeptic's check**: _track_lock (camera_rig.gd:284-289) only rejects |to| < 1 m, so the yaw target atan2(-to.x,-to.z) is ill-conditioned when the hard target is near the vertical through the pivot. Hovering over a locked enemy or a Harrier overhead reaches this. With the view clamped at -70 deg, a target straight below the pivot sits about 8-18 deg pitch and 5-14 deg yaw off the arm-tip view at any yaw, which is inside the 22.5/30 deg keep cone (aim_system.gd:181, target_query.gd:84-89). So the lock holds while the yaw chases a bearing that flips when the target passes underneath. Values stay finite, so the 'nonfinite' label is wrong, but the whip is real and movement input (yaw_basis) rotates with it.

## 6. [low] game/player/camera/camera_rig.gd:273 (other)
**What**: invert_y multiplies the aim-assist pitch correction as well as the player's input. With invert on, the vertical assist pushes the reticle away from the soft target: a feedback loop with the wrong sign.

**Trigger**: Settings invert_y = true, aim_assist > 0, and a soft target inside the 7/10 deg cone. assist_delta returns -angles.y*pull (turn toward the target), but `(d.y + assist.y) * invert` flips it, so the vertical error grows at about 25 %/s until the target leaves the cone.

**Fix**: As proposed: _pitch_deg = clampf(_pitch_deg - d.y * invert - assist.y, PITCH_MIN_DEG, PITCH_MAX_DEG).

**Skeptic's check**: assist_delta returns -angles.y*pull in the 'down positive' convention (aim_system.gd:241-242), so it turns toward the target uninverted. camera_rig.gd:273 multiplies (d.y + assist.y) by invert, so with the menu toggle invert_y on (menu_root.gd:23) and the default aim_assist 1.0 (settings.gd:25), the vertical error grows at 0.25*strength per second. This is clearest in first person or under a soft lock, where _track_lock does not pull the pitch back.

## 7. [low] game/player/camera/cockpit_frame.gd:32 (integrator)
**What**: The canopy's yaw-lag state is not reset when it becomes visible. _physics_process returns early while hidden, so on entering first person the lag starts from the heading of the previous first-person session (or 0 rad the first time).

**Trigger**: Turn in third person (or spawn facing any world yaw other than 0), then press camera_toggle. When the blend passes 0.5 the canopy appears up to 180 deg off the view and sweeps into place over about 0.2 s, longer in slow-mo because of the scaled-delta problem on line 36.

**Fix**: As proposed: on the hidden-to-visible edge set _yaw = want and _damage = 0.0 before applying the lag. An equivalent alternative is to keep _yaw = want while hidden.

**Skeptic's check**: _yaw is only integrated while visible (cockpit_frame.gd:31-36) and is never reseeded. want is a world yaw (camera_rig.gd:410, look_angles). So on entering FP after any third-person turn, the canopy appears at blend 0.5 at the old heading (0 the first time) and sweeps back at 10.4 % per tick, with roughly 10 % of the error still left when the 0.35 s blend ends.

## 8. [low] game/player/camera/cockpit_frame.gd:36 (clock)
**What**: The canopy's 80 ms yaw lag (line 36) and the damage-knock decay (line 34) run on plain scaled delta, but the view they trail turns on Feel.real_delta. The canopy therefore freezes during hit-stops and lags 3-5x further in slow-mo.

**Trigger**: First person, turning during a global hit-stop: at scale 0.05 the canopy struts stop while the view keeps turning, then snap back when the freeze ends. In witch time (0.3) the effective lag becomes 0.27 s, so a 300 deg/s stick turn leaves the canopy about 80 deg behind instead of the designed 24 deg, which is most of the ~97 deg horizontal FOV.

**Fix**: As proposed: var dt := Feel.real_delta(delta), used in both the damage decay and the lag factor.

**Skeptic's check**: cockpit_frame.gd:34,36 use the scaled physics delta, but the yaw it trails (look_angles().x) is integrated on Feel.real_delta (camera_rig.gd:210-227), and CONTRACTS §2 puts camera springs on real time. During the Zenith Lance charge (slow_mo 0.3 for 0.8 s, zenith_lance.gd:92) the 80 ms lag becomes 0.27 s, and in a 0.05 global stop the canopy all but freezes while mouse or stick keeps turning the view.

## Lead decisions that go with findings on `end_cinematic` and the execution clock (CONTRACTS §5 updated)
- `end_cinematic()` must END the cinematic: cancel CameraCinematic (active = false, shots cleared), release the
  held FOV, restore arm + look — one call, no recursion through `_finish()`. Flow's drop-in, the victory director
  and melee executions rely on exactly that.
- `request_cinematic(shots, duration, clock := &"real")`: `&"player"` advances the shot timeline on
  `Feel.player_delta` (melee executions); `&"real"` (default) stays for presentation. Add tests for both.
