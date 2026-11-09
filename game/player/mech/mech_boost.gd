class_name MechBoost
extends RefCounted
## Thruster states of `MechLocomotion` (SPEC §4): the boost slide / air glide (free, 42 m/s, sustained
## for as long as the button is held) and the assault boost (its own toggle, 0.30 s ignition, then
## 84 m/s at 120 EN/s). Static helpers, because the boost shares the steering and the exit with the
## ground and air states that call into it.

static func start_slide(l: MechLocomotion) -> void:
	if l.energy.is_outage():
		return
	l._gliding = not l._on_floor
	l.move_state = &"glide" if l._gliding else &"slide"
	l._set_state(MechLocomotion.S.SLIDE)
	Feel.play(&"boost_start", l.body.global_position)
	Events.boost_started.emit(&"slide")


static func slide(l: MechLocomotion, delta: float) -> void:
	if not l.input.boost_held or l.energy.is_outage():
		end_boost(l)
		return
	if l.input.assault_pressed and start_assault(l):
		return
	if l.try_flight():
		return
	if l.input.jump_pressed:
		l._launch()
		return
	_steer(l, l.tuning.boost_speed, l.tuning.boost_turn_rate_deg, l.tuning.boost_accel_time, delta)
	if l._on_floor:
		# SPEC §4 stepping: skate straight over a block up to 7 m tall instead of stopping dead.
		if not MechStepping.try_hop(l):
			l.body.velocity.y = -1.0
	else:
		l.move_state = &"glide"
		l._gliding = true
		# air boost is free too: it only trades altitude, sinking at glide_sink instead of falling
		l.body.velocity.y = maxf(l.body.velocity.y - l.tuning.fall_gravity * delta, -l.tuning.glide_sink)
	# SPEC §4: the boost costs nothing and EN keeps regenerating on the ground.
	l.energy.drain(l.tuning.boost_cost * l.pdelta)


## The boost jet points where the stick points: the velocity vector carves at the boost yaw rate and
## the body follows it. Steering the body instead would make a 180 deg turn take over a second.
static func _steer(l: MechLocomotion, speed: float, yaw_rate: float, accel_time: float,
		delta: float) -> void:
	var wish := l.wish_dir()
	var hv := Vector3(l.body.velocity.x, 0.0, l.body.velocity.z)
	var dir := hv.normalized() if hv.length() > 1.0 else -l.body.global_basis.z
	if wish != Vector3.ZERO:
		var step := deg_to_rad(yaw_rate) * delta
		var turn := clampf(angle_difference(atan2(wish.x, wish.z), atan2(dir.x, dir.z)), -step, step)
		dir = dir.rotated(Vector3.UP, -turn)
	dir = dir.normalized()
	hv = hv.move_toward(dir * speed, speed / accel_time * delta)
	l.body.velocity.x = hv.x
	l.body.velocity.z = hv.z
	l.face_toward(dir, yaw_rate * 2.0, delta)


## SPEC §3: the assault boost needs a live gauge — an Outage or the post-Outage reserve blocks it.
static func can_assault(l: MechLocomotion) -> bool:
	return not l.energy.is_outage() and not l.energy.restart_locked() and l.energy.energy > 0.0


## SPEC §3: `assault` toggles the assault boost from the ground, a boost or a flight. Returns false
## when the gauge will not pay for it, so the caller keeps its own state.
static func start_assault(l: MechLocomotion) -> bool:
	if not can_assault(l):
		return false
	l.assault_on = true
	l._skid_t = 0.0
	l._assault_ignite = l.tuning.assault_ignition
	l.move_state = &"assault"
	l._set_state(MechLocomotion.S.ASSAULT)
	Feel.play(&"assault_boost", l.body.global_position)
	Events.boost_started.emit(&"assault")
	return true


static func assault(l: MechLocomotion, delta: float) -> void:
	if not l.assault_on or l.energy.is_outage():
		end_boost(l)
		return
	if l.input.assault_pressed or _skid(l, delta):
		l.assault_on = false  # SPEC §4: the toggle or the skid brake cancels the jet
		end_boost(l)
		return
	if l.try_flight():
		return
	if l.input.jump_pressed:
		l._launch()
		return
	if l.input.boost_pressed and MechDash.start(l):
		return  # SPEC §4: the assault boost is cancelled with a dash
	l._assault_ignite = maxf(l._assault_ignite - delta, 0.0)
	var speed := l.tuning.boost_speed if l._assault_ignite > 0.0 else l.tuning.assault_speed
	_steer(l, speed, l.tuning.assault_yaw_deg, l.tuning.assault_accel_time, delta)
	if l._on_floor:
		if not MechStepping.try_hop(l):
			l.body.velocity.y = -1.0
	else:
		l.body.velocity.y = maxf(l.body.velocity.y - l.tuning.fall_gravity * delta, -l.tuning.glide_sink)
	l.energy.drain(l.tuning.assault_cost * l.pdelta)


## AC6 skid brake (SPEC §4): holding the stick against the jet for `assault_brake` drops the mech out
## of the assault boost. The timer is real time, so it is the same 0.25 s in witch time.
static func _skid(l: MechLocomotion, delta: float) -> bool:
	var wish := l.wish_dir()
	var hv := Vector3(l.body.velocity.x, 0.0, l.body.velocity.z)
	if wish == Vector3.ZERO or hv.length() < 1.0 or wish.dot(hv / hv.length()) > -0.5:
		l._skid_t = 0.0
		return false
	l._skid_t += delta
	if l._skid_t < l.tuning.assault_brake:
		return false
	l._skid_t = 0.0
	return true


static func end_boost(l: MechLocomotion) -> void:
	l.assault_on = false
	if l._on_floor:
		l._set_state(MechLocomotion.S.GROUND)
	else:
		l._air_start_y = maxf(l._air_start_y, l.body.global_position.y)
		l._set_state(MechLocomotion.S.AIR)
