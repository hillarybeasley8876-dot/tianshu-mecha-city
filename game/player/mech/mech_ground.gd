class_name MechGround
extends RefCounted
## The grounded state (SPEC §4 "Ground movement"): idle, walk, run and the coast between them, the
## accel/brake curves, the 540 deg/s turn and the 4 frame jump knee-dip. Split out of
## `MechLocomotion` so that file stays the state machine and the shared helpers, exactly like
## `MechDash`, `MechBoost`, `MechAir` and `MechStepping`.


static func ground(l: MechLocomotion, delta: float) -> void:
	var b := l.body
	var wish := l.wish_dir()
	var mag := l.input.move.length()
	var hv := Vector3(b.velocity.x, 0.0, b.velocity.z)
	var rate := l.tuning.accel_rate() if mag > 0.05 else l.tuning.brake_rate()
	hv = hv.move_toward(wish * l._target_speed(mag), rate * delta)
	b.velocity.x = hv.x
	b.velocity.z = hv.z
	_turn(l, wish, mag, delta)
	if l._on_floor:
		b.velocity.y = -1.0  # keeps the 0.6 m floor snap alive on the ramps
	elif l._coyote <= 0.0:
		l._air_start_y = b.global_position.y
		l._set_state(MechLocomotion.S.AIR)
		return
	else:
		l.apply_gravity(delta)
	l.move_state = &"land_light" if l._land_pose > 0.0 else _label(l, mag, l._target_speed(mag))
	if l.input.boost_pressed and MechDash.start(l):
		return
	if l.input.assault_pressed and MechBoost.start_assault(l):
		return
	# SPEC §3: the flight toggle outranks the knee-dip, which is only 4 frames long and would
	# otherwise swallow the second press of a fast tap-tap.
	if l.try_flight():
		return
	# SPEC §4: the 4 frame knee-dip never swallows another input, so it is checked after the dash.
	if l._pending_jump:
		l.move_state = &"jump"
		l._jump_charge -= delta
		if l._jump_charge <= 0.0:
			l._launch()
		return
	if l.input.jump_pressed or l._jump_buffer > 0.0:
		l._jump_buffer = 0.0
		l._pending_jump = true
		l._jump_charge = l.tuning.jump_dip
		l.move_state = &"jump"
		return
	if l.input.boost_held and not l.energy.is_outage():
		MechBoost.start_slide(l)


## Coasting has its own id (`coast`): the legs are still running but nothing is driving them, so the
## model can start the brake animation and the HUD can drop the thruster cue.
static func _label(l: MechLocomotion, mag: float, target: float) -> StringName:
	if mag < 0.05:
		return &"idle" if l.flat_speed() < 1.0 else &"coast"
	return &"run" if target > l.tuning.run_speed * 0.95 else &"walk"


## The lower body follows the stick; under `strafe_aim` it holds the camera's heading instead.
static func _turn(l: MechLocomotion, wish: Vector3, mag: float, delta: float) -> void:
	if l._strafe:
		l.face_toward(-l.yaw_basis().z, l.tuning.strafe_turn_rate_deg, delta)
	elif mag > 0.05:
		l.face_toward(wish, l.tuning.turn_rate(l.flat_speed()), delta)
