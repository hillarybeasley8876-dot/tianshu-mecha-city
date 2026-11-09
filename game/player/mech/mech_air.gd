class_name MechAir
extends RefCounted
## Airborne and recovery states of `MechLocomotion` (SPEC §4: jump arc, ascend/hover, flight, landing,
## combat lock, melee lunge). Static helpers so each family of states stays in its own file; they
## operate on the locomotion node, which owns all of the state.

## Hop arc, ascend/hover, dive and the unpowered glide. Landing is detected in
## MechLocomotion.post_move(), which is the only place floor contact can be read.
static func air(l: MechLocomotion, delta: float) -> void:
	if l.try_flight():
		return
	if l.input.jump_pressed:
		l._jump_buffer = l.tuning.jump_buffer
	if l.input.boost_pressed and MechDash.start(l):
		return
	if l.input.boost_held and not l.energy.is_outage():
		MechBoost.start_slide(l)  # air boost: cruise 42 m/s, sink 6 m/s, no EN cost
		return
	_steer(l, delta)
	_vertical(l, delta)


static func _steer(l: MechLocomotion, delta: float) -> void:
	var wish := l.wish_dir()
	var mag := l.input.move.length()
	if mag > 0.05:
		l.face_toward(wish, l.tuning.turn_rate(l.flat_speed()), delta)
	var hv := Vector3(l.body.velocity.x, 0.0, l.body.velocity.z)
	var rate := l.tuning.accel_rate() if mag > 0.05 else l.tuning.brake_rate()
	hv = hv.move_toward(wish * l._target_speed(mag), rate * delta)
	l.body.velocity.x = hv.x
	l.body.velocity.z = hv.z


static func _vertical(l: MechLocomotion, delta: float) -> void:
	var b := l.body
	var t := l.tuning
	if l._vernier > 0.0:
		b.velocity.y = move_toward(b.velocity.y, 0.0, t.fall_gravity * delta)
		l.move_state = &"jump"
		return
	if l.input.descend_held:
		l.apply_dive(delta)
		l.move_state = &"fall"
		return
	if l.input.jump_held and not l.energy.is_outage():
		# SPEC §4: ascend 18 m/s at 100 EN/s; when that is out of reach it hovers at 40 EN/s.
		if l.energy.energy > t.hover_reserve and not l.energy.restart_locked():
			b.velocity.y = move_toward(b.velocity.y, t.ascend_speed, t.rise_gravity * delta)
			l.energy.drain(t.ascend_cost * l.pdelta, true)
		else:
			b.velocity.y = move_toward(b.velocity.y, 0.0, t.fall_gravity * delta)
			l.energy.drain(t.hover_cost * l.pdelta)
		l.move_state = &"hover"
		return
	if l.energy.is_outage():
		b.velocity.y = maxf(b.velocity.y - t.fall_gravity * t.glide_fall_scale * delta, -t.glide_sink_cap)
		l.move_state = &"glide"
		return
	l.apply_gravity(delta)
	l.move_state = &"jump" if b.velocity.y > 0.0 else &"fall"


## Free 3D flight along the camera look (SPEC §4): 50 m/s, 84 m/s with the assault boost toggled on,
## +-20 m/s vertical, 80 EN/s with no regen, soft ceiling, auto-exit into a glide at EN 0.
static func flight(l: MechLocomotion, delta: float) -> void:
	var b := l.body
	if b.is_on_floor() or (l.input.jump_pressed and l.input.double_jump):
		end_flight(l)
		return
	if l.input.assault_pressed:
		_assault_toggle(l)
	var t := l.tuning
	var vert := 0.0
	if l.input.jump_held:
		vert += 1.0
	if want_descend(l):
		vert -= 1.0
	var boosting := l.assault_on and not l.energy.is_outage()
	var speed := t.flight_boost_speed if boosting else t.flight_speed
	var look := l.look_dir().normalized()
	var want := look * speed
	if boosting:
		# SPEC §4 `assault_pitch_deg`: at assault speed the jet carves into a dive or a climb at
		# 45 deg/s instead of snapping to the crosshair, so the city reads as scale.
		want = _pitch_toward(l, look, vert, delta) * speed
	else:
		want.y += vert * t.flight_vertical
	if b.global_position.y > t.flight_ceiling:
		want.y = minf(want.y, -t.glide_sink)  # storm shield: soft push back down
	b.velocity = b.velocity.move_toward(want, speed / t.flight_accel_time * delta)
	var flat := Vector3(b.velocity.x, 0.0, b.velocity.z)
	if flat.length() > 0.5:
		l.face_toward(flat, t.turn_run_deg, delta)
	l.energy.drain((t.flight_boost_cost if boosting else t.flight_cost) * l.pdelta)
	l.move_state = &"fly"
	if l.energy.is_outage():
		end_flight(l)


## SPEC §3: on the pad B (boost) held without pushing forward descends, so a pad player never has to
## let go of the boost to lose height; `descend` (Ctrl) stays the keyboard way.
static func want_descend(l: MechLocomotion) -> bool:
	return l.input.descend_held or (l.input.boost_held and l.input.move.y < 0.05)


## The `assault` toggle (SPEC §3) also works in flight, where it lights the 84 m/s jet.
static func _assault_toggle(l: MechLocomotion) -> void:
	l.assault_on = not l.assault_on and MechBoost.can_assault(l)
	if l.assault_on:
		Feel.play(&"assault_boost", l.body.global_position)
		Events.boost_started.emit(&"assault")
	else:
		Events.boost_ended.emit(&"assault")


## Flight-boost direction whose pitch may only change at `assault_pitch_deg`; the yaw still follows
## the view freely. `vert` folds the ascend / descend keys into the target pitch.
static func _pitch_toward(l: MechLocomotion, look: Vector3, vert: float, delta: float) -> Vector3:
	var b := l.body
	var hv := Vector3(b.velocity.x, 0.0, b.velocity.z)
	var flat_look := Vector3(look.x, 0.0, look.z)
	if hv.length() < 1.0 or flat_look.length() < 0.001:
		return look
	var target := atan2(look.y + vert * 0.5, flat_look.length())
	var current := atan2(b.velocity.y, hv.length())
	var step := deg_to_rad(l.tuning.assault_pitch_deg) * delta
	var pitch := current + clampf(angle_difference(current, target), -step, step)
	var dir := flat_look.normalized() * cos(pitch)
	return Vector3(dir.x, sin(pitch), dir.z)


static func start_flight(l: MechLocomotion) -> void:
	l.set_flying(true)
	l._gliding = false
	l._vernier = 0.0
	l._set_state(MechLocomotion.S.FLIGHT)
	l.move_state = &"fly"
	Feel.play(&"boost_start", l.body.global_position)


static func end_flight(l: MechLocomotion) -> void:
	l.set_flying(false)
	l.assault_on = false
	l._air_start_y = maxf(l._air_start_y, l.body.global_position.y)
	l._set_state(MechLocomotion.S.AIR)
	l.move_state = &"glide"


## Touchdown recovery (SPEC §4): soft 0.20 s (cancel from frame 6), hard 0.38 s (cancel from frame 14),
## landed on an empty gauge 0.70 s with no cancel at all. `_land_t` / `_land_lock` run on the player
## clock in MechLocomotion._timers().
static func land(l: MechLocomotion, delta: float) -> void:
	var rate := l.tuning.brake_rate()
	l.body.velocity.x = move_toward(l.body.velocity.x, 0.0, rate * delta)
	l.body.velocity.z = move_toward(l.body.velocity.z, 0.0, rate * delta)
	if l._land_t <= 0.0:
		l._set_state(MechLocomotion.S.GROUND)
		return
	if l._land_lock > 0.0:
		return
	if l.input.boost_pressed and MechDash.start(l):
		return
	if l.input.boost_held and not l.energy.is_outage():
		MechBoost.start_slide(l)
		return
	if l.try_flight():
		return
	if l.input.jump_pressed:
		l._set_state(MechLocomotion.S.GROUND)
		l._launch()


## Combat root: `lock_movement(s, allow_turn)` holds the mech in place while an attack plays out.
static func locked(l: MechLocomotion, delta: float) -> void:
	var b := l.body
	var rate := l.tuning.brake_rate()
	b.velocity.x = move_toward(b.velocity.x, 0.0, rate * delta)
	b.velocity.z = move_toward(b.velocity.z, 0.0, rate * delta)
	if b.is_on_floor():
		b.velocity.y = -1.0
	else:
		l.apply_gravity(delta)
	if l._lock_turn:
		var wish := l.wish_dir()
		if wish != Vector3.ZERO:
			l.face_toward(wish, l.tuning.turn_rate(l.flat_speed()), delta)
	l.move_state = &"locked"
	if l._lock_t <= 0.0:
		l._set_state(MechLocomotion.S.GROUND if b.is_on_floor() else MechLocomotion.S.AIR)


## Melee lunge: straight run at the target point, stopping on head-on contact, on arrival or on the time
## cap. Kerbs are stepped onto by the locomotion's step-up and grazed walls are slid along.
static func lunge(l: MechLocomotion, delta: float) -> void:
	var b := l.body
	var to := l._lunge_point - b.global_position
	to.y = 0.0
	var dist := to.length()
	if dist < l.tuning.lunge_arrive or l._lunge_t <= 0.0 \
			or _lunge_blocked(b, to / dist, l.tuning.lunge_block_dot):
		b.velocity.x = 0.0
		b.velocity.z = 0.0
		l._set_state(MechLocomotion.S.GROUND if b.is_on_floor() else MechLocomotion.S.AIR)
		return
	var dir := to / dist
	b.velocity.x = dir.x * l._lunge_speed
	b.velocity.z = dir.z * l._lunge_speed
	if b.is_on_floor():
		b.velocity.y = -1.0
	else:
		l.apply_gravity(delta)
	l.face_toward(dir, l.tuning.lunge_turn_rate_deg, delta)
	l.move_state = &"lunge"


## True when the last move ran into a wall that faces the lunge (head-on), not one it merely grazed.
static func _lunge_blocked(b: CharacterBody3D, dir: Vector3, block_dot: float) -> bool:
	if not b.is_on_wall():
		return false
	var n := b.get_wall_normal()
	n.y = 0.0
	return n.length_squared() > 0.01 and n.normalized().dot(dir) < block_dot
