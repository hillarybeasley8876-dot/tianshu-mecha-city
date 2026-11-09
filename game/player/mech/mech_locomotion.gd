class_name MechLocomotion
extends Node
## Hero mech state machine (SPEC §4). One state at a time; each writes `body.velocity` and the string
## `move_state` (SPEC §10 ids) that the model and HUD read. Horizontal movement is camera-relative
## through the CameraRig (`yaw_basis()`), or through the debug camera until that unit lands.
## The body calls `tick()` before `move_and_slide()` and `post_move()` after, because floor contact and
## therefore landing can only be read once the move has been resolved.
##
## Clocks (CONTRACTS §3): `tick()`/`post_move()` take the RAW physics delta and split it here — the
## movement clock is `Feel.locomotion_delta` (real seconds, so witch time and global hit-stops never
## slow the mech), the timers are `Feel.player_delta` (full speed in witch time, frozen by a global
## hit-stop). Input timing lives in `MechInput`, which uses real seconds too.

enum S { GROUND, DASH, SLIDE, ASSAULT, AIR, FLIGHT, LAND, LOCKED, LUNGE }

var body: CharacterBody3D
var tuning: MechTuning
var energy: MechEnergy
var model: Node3D
var debug_camera: Node3D

var input := MechInput.new()
var state: int = S.GROUND
var move_state: StringName = &"idle"
var flying: bool = false
var assault_on: bool = false        ## SPEC §3: the assault boost is a toggle, not a hold
var rdelta: float = 0.0             ## this tick's REAL seconds (movement, input, i-frame ticks)
var pdelta: float = 0.0             ## this tick's player-clock seconds (i-frames, cooldowns)
var land_kind: StringName = &"none"  ## last touchdown: none / soft / hard / outage (telemetry)
var step_events: int = 0             ## kerbs climbed by the step-up shim (telemetry, tests)
## r8 item 1: metres the MODEL still lags the capsule after a step-up (see `MechCoast`).
var step_lag: float:
	get: return coast.lag
	set(v): coast.lag = v
var hop_events: int = 0              ## obstacles cleared by the boost auto-hop (telemetry, tests)

var _pause_t: float = 0.0
var _strafe: bool = false
var _on_floor: bool = true
var _pre_vy: float = 0.0  ## velocity.y before move_and_slide, which zeroes it on contact
var _dash_t: float = 0.0
var _dash_iframes_t: float = 0.0
var _dash_dir: Vector3 = Vector3.FORWARD
var _dash_chain: int = 0
var _dash_lockout: float = 0.0
var _dash_cooldown: float = 0.0
var _chain_idle: float = 0.0
var _vernier: float = 0.0
var _assault_ignite: float = 0.0
var _skid_t: float = 0.0
var _jump_charge: float = 0.0
var _pending_jump: bool = false
var _jump_buffer: float = 0.0
var _coyote: float = 0.0
var _air_start_y: float = 0.0
var _land_t: float = 0.0
var _land_lock: float = 0.0
var _land_pose: float = 0.0
var _lock_t: float = 0.0
var _lock_turn: bool = false
var _lunge_point: Vector3 = Vector3.ZERO
var _lunge_speed: float = 0.0
var _lunge_t: float = 0.0
var _footstep_t: float = 0.0
var _gliding: bool = false
var _hop_cd: float = 0.0
## r8 item 1: the step-up coast (SPEC §4 "Stepping") -- `MechStepping.try_step` hands the whole
## displacement to it instead of teleporting the capsule onto the kerb.
var coast := MechCoast.new()


func setup(b: CharacterBody3D, t: MechTuning, e: MechEnergy, m: Node3D) -> void:
	body = b
	tuning = t
	energy = e
	model = m
	input.double_tap_window = t.flight_double_tap
	input.buffer_window = t.input_buffer
	_air_start_y = b.global_position.y


func tick(delta: float) -> void:
	var rd := Feel.locomotion_delta(delta)
	rdelta = rd
	pdelta = Feel.player_delta(delta)
	input.poll(delta)
	_on_floor = body.is_on_floor()
	if coasting():
		_on_floor = true  # the coast IS a grounded move: a kerb must never read as a floor lost
	_timers(rd, pdelta)
	if is_frozen():  # local hit-stop: this mech's own motion is frozen, the world is not
		input.latch_edges()
		_pre_vy = body.velocity.y
		return
	if state != S.LOCKED and state != S.LUNGE:
		input.release_edges()  # a combat lock keeps the press buffered until it can act on it
	match state:
		S.GROUND: MechGround.ground(self, rd)
		S.DASH: MechDash.dash(self, rd)
		S.SLIDE: MechBoost.slide(self, rd)
		S.ASSAULT: MechBoost.assault(self, rd)
		S.AIR: MechAir.air(self, rd)
		S.FLIGHT: MechAir.flight(self, rd)
		S.LAND: MechAir.land(self, rd)
		S.LOCKED: MechAir.locked(self, rd)
		S.LUNGE: MechAir.lunge(self, rd)
	if not coasting() and (state == S.GROUND or state == S.SLIDE or state == S.ASSAULT
			or state == S.DASH or state == S.LUNGE):
		MechStepping.try_step(self, rd)  # SPEC §4: a kerb never costs a frame of speed
	_pre_vy = body.velocity.y


func post_move(delta: float) -> void:
	# Contact is read even while frozen: move_and_slide still runs (the attacker creeps), so a floor
	# touched or left inside a hit-stop must never be dropped — that is what strands a mech in S.AIR.
	if not _on_floor and body.is_on_floor():
		MechContact.touchdown(self)
	elif _on_floor and not body.is_on_floor():
		_air_start_y = body.global_position.y
		_coyote = tuning.coyote_time
		_gliding = false
		# A boost hop keeps its own state in the air: it is a ballistic vault solved for the boost's
		# gravity and speed (mech_stepping.gd), which the air states would not fly.
		if state == S.GROUND or (_hop_cd <= 0.0 and (state == S.SLIDE or state == S.ASSAULT)):
			_set_state(S.AIR)
	if is_frozen():
		return
	MechContact.footsteps(self, Feel.locomotion_delta(delta))
	MechContact.update_model(self)


## `rd` drives the movement and input clocks, `pd` the player timers (CONTRACTS §3).
func _timers(rd: float, pd: float) -> void:
	_pause_t = maxf(_pause_t - pd, 0.0)
	_dash_lockout = maxf(_dash_lockout - pd, 0.0)
	_dash_cooldown = maxf(_dash_cooldown - pd, 0.0)
	_land_t = maxf(_land_t - pd, 0.0)
	_land_lock = maxf(_land_lock - pd, 0.0)
	_land_pose = maxf(_land_pose - pd, 0.0)
	_lock_t = maxf(_lock_t - pd, 0.0)
	_vernier = maxf(_vernier - rd, 0.0)
	_lunge_t = maxf(_lunge_t - rd, 0.0)
	_jump_buffer = maxf(_jump_buffer - rd, 0.0)
	_hop_cd = maxf(_hop_cd - rd, 0.0)
	coast.tick(rd, flat_speed(), tuning.step_ease_speed, tuning.step_ease_ratio)
	if body.is_on_floor():
		_coyote = tuning.coyote_time
	else:
		_coyote = maxf(_coyote - rd, 0.0)
	if state != S.DASH:
		_chain_idle += pd
		if _chain_idle > tuning.dash_chain_window and _dash_lockout <= 0.0:
			_dash_chain = 0


# --- the step-up coast (r8 item 1) ----------------------------------------------------------------

## True while the capsule is being walked up onto a kerb instead of teleported there.
func coasting() -> bool:
	return coast.active()


## `MechStepping.try_step` hands over the whole displacement the capsule used to take in one tick; the
## coast walks it out at the speed the mech was already doing, so the hip never outruns the feet.
func begin_coast(move: Vector3, rise: float, speed: float) -> void:
	coast.begin(body, move, rise, speed, tuning.step_coast_min)
	step_events += 1


## The coast IS the move, so `PlayerMech._physics_process` calls this instead of `_move()` while it
## runs -- `move_and_slide` is skipped and `is_on_floor()` keeps the last real move's answer.
func coast_move() -> void:
	coast.advance(body)


## Hold the model node `step_lag` metres low, so the gait's ground plane and every hip in the rig stay
## on the surface the trailing foot is really standing on until the legs have caught up.
func apply_step_lag() -> void:
	coast.apply_lag(model)


# --- shared helpers ------------------------------------------------------------------------------

## Horizontal camera orientation: movement, dash directions and flight are relative to it.
func yaw_basis() -> Basis:
	if Game.camera_rig != null and Game.camera_rig.has_method(&"yaw_basis"):
		return Game.camera_rig.call(&"yaw_basis") as Basis
	if debug_camera != null and debug_camera.has_method(&"yaw_basis"):
		return debug_camera.call(&"yaw_basis") as Basis
	return Basis.IDENTITY


## Full 3D look direction (flight); horizontal fallback when there is no rig.
func look_dir() -> Vector3:
	if Game.camera_rig != null and Game.camera_rig.has_method(&"look_dir"):
		return Game.camera_rig.call(&"look_dir") as Vector3
	if debug_camera != null and debug_camera.has_method(&"look_dir"):
		return debug_camera.call(&"look_dir") as Vector3
	return -body.global_basis.z


## World-space wish direction from the stick, in the camera's horizontal frame.
func wish_dir() -> Vector3:
	if input.move.length() < 0.05:
		return Vector3.ZERO
	var d := yaw_basis() * Vector3(input.move.x, 0.0, -input.move.y)
	return d.normalized() if d.length() > 0.001 else Vector3.ZERO


func flat_speed() -> float:
	return Vector2(body.velocity.x, body.velocity.z).length()


func _target_speed(mag: float) -> float:
	if mag < 0.05:
		return 0.0
	return lerpf(tuning.walk_speed, tuning.run_speed, clampf(inverse_lerp(0.5, 1.0, mag), 0.0, 1.0))


## Coasting has its own id (`coast`): the legs are still running but nothing is driving them, so the
## model can start the brake animation and the HUD can drop the thruster cue.


func face_toward(dir: Vector3, rate_deg: float, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var f := -body.global_basis.z
	var step := deg_to_rad(rate_deg) * delta
	# yaw a -> forward (-sin a, 0, -cos a): atan2(x, z) runs with the yaw, so the wanted yaw step is
	# the target's angle minus the current one, i.e. angle_difference(current, target).
	var turn := angle_difference(atan2(f.x, f.z), atan2(dir.x, dir.z))
	body.rotate_y(clampf(turn, -step, step))


## SPEC §4: rising uses the hop curve's gravity, falling `fall_gravity` (80 m/s^2) to `terminal_speed`.
## `scale_` damps it for the glide and the air boost.
func apply_gravity(delta: float, scale_: float = 1.0) -> void:
	var g := tuning.rise_gravity if body.velocity.y > 0.0 else tuning.fall_gravity
	body.velocity.y = maxf(body.velocity.y - g * scale_ * delta, -tuning.terminal_speed)


## `descend` held in the air: dive at up to `dive_speed` (SPEC §4).
func apply_dive(delta: float) -> void:
	body.velocity.y = maxf(body.velocity.y - tuning.fall_gravity * delta, -tuning.dive_speed)


func _set_state(s: int) -> void:
	if s == state:
		return
	coast.stop()  # r8: any state change drops the step coast; gravity takes over from here
	if state == S.DASH:
		Events.boost_ended.emit(&"quick")
		_dash_chain = mini(_dash_chain, tuning.dash_max_chain)
		if _dash_chain >= tuning.dash_max_chain:
			_dash_lockout = tuning.dash_lockout
			_dash_chain = 0
	if state == S.SLIDE and s != S.ASSAULT:
		Events.boost_ended.emit(&"slide")
	if state == S.ASSAULT and s != S.SLIDE:
		Events.boost_ended.emit(&"assault")
	state = s
	_chain_idle = 0.0


## SPEC §3: a double tap of `jump` toggles free 3D flight. Every state that can act on a jump press
## asks here FIRST, so the toggle is never answered with a plain hop: it used to live in
## `MechAir.air()` alone, which lost it during a boost, a dash, a landing and the ground knee-dip.
## Returns true when flight started, so the caller stops handling the press.
func try_flight() -> bool:
	if not input.jump_pressed or not input.double_jump:
		return false
	if energy.is_outage():
		return false  # SPEC §4 Outage: no thrusters, so the toggle cannot light the jet
	# SPEC §3: from the ground the first tap's hop is what puts the mech in the air, so a pair that
	# lands inside the 4 frame knee-dip still has to fly — launch first, then toggle.
	if _on_floor:
		_launch()
	MechAir.start_flight(self)
	return true


## SPEC §4: thruster hop to +8 m in 0.45 s. Facing is never changed by a dash.
func _launch() -> void:
	_pending_jump = false
	body.velocity.y = tuning.jump_speed()
	_air_start_y = body.global_position.y
	_coyote = 0.0
	_set_state(S.AIR)
	move_state = &"jump"
	Feel.play(&"jump", body.global_position)
	Events.jumped.emit()
	if model != null and model.has_method(&"play_action"):
		model.call(&"play_action", &"jump")


# --- presentation and external control -------------------------------------------------------------

func set_flying(on: bool) -> void:
	if on == flying:
		return
	flying = on
	Events.flight_changed.emit(on)


# --- queries and external control ----------------------------------------------------------------

## Half a tick of slack on the comparison: the window ends on the tick whose midpoint crosses it, which
## makes it exactly 12 physics ticks at 120 Hz instead of drifting with float accumulation.
func is_dash_invulnerable() -> bool:
	return state == S.DASH and _dash_iframes_t + pdelta * 0.5 < tuning.dash_iframes


func is_boosting() -> bool:
	return state == S.SLIDE or state == S.ASSAULT


func dash_chain() -> int:
	return _dash_chain


## True when the mech may start another action now. `&"dash"` asks specifically for the dodge.
func can_cancel(tag: StringName = &"any") -> bool:
	if state == S.LOCKED or state == S.LUNGE:
		return false
	if state == S.LAND and _land_lock > 0.0:
		return false
	if tag == &"dash":
		return _dash_lockout <= 0.0 and _dash_cooldown <= 0.0 \
				and _dash_chain < tuning.dash_max_chain \
				and not energy.is_outage() and not energy.restart_locked()
	return true


func hit_pause(seconds: float) -> void:
	_pause_t = maxf(_pause_t, seconds)


## A local hit-stop freezes the mech's OWN motion (CONTRACTS §4) — but only where the mech is not
## driving itself: FEEL.md and juice §2.2 say a player-started boost, dash or landing never freezes,
## because a 6-tick halt in the middle of a 24 m jet reads as a hitch and carries the body on.
func is_frozen() -> bool:
	return _pause_t > 0.0 and (state == S.LOCKED or state == S.LUNGE)


## Rift Step (CONTRACTS §5): the chain is spent by the blink, not by a dodge, so give it back.
func reset_dash_chain() -> void:
	_dash_chain = 0
	_dash_lockout = 0.0
	_chain_idle = 0.0


func lock_movement(seconds: float, allow_turn: bool) -> void:
	_lock_t = maxf(_lock_t, seconds)
	_lock_turn = allow_turn
	_set_state(S.LOCKED)


func lunge_to(point: Vector3, speed: float, max_time: float) -> void:
	_lunge_point = point
	_lunge_speed = maxf(speed, 1.0)
	_lunge_t = maxf(max_time, 0.05)
	_set_state(S.LUNGE)


func set_strafe_aim(on: bool) -> void:
	_strafe = on


func apply_impulse(v: Vector3) -> void:
	body.velocity += v
	if v.y > 0.0 and state != S.LOCKED and state != S.LUNGE:
		_air_start_y = body.global_position.y
		_set_state(S.AIR)


## Tools/tests/timelines: drop every timer and state so a scripted run starts from a known pose.
func debug_reset() -> void:
	MechDebug.reset(self)
