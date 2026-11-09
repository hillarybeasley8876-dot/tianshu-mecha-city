class_name MechDash
extends RefCounted
## The quick boost of `MechLocomotion` (SPEC §4): a 0.25 s jet covering 24 m in any of the eight
## camera-relative directions, with i-frames over the first 6 frames. Split out of the state machine
## because four states (ground, air, boost, landing) can all start one.
## The jet runs on REAL time (CONTRACTS §3) so witch time never stretches the dodge; the i-frames run
## on the player clock, which freezes in a global hit-stop and therefore only ever lasts longer.

## Starts the jet if the chain, the cooldown and the gauge allow it. Returns false when it does not,
## so callers keep their own state.
static func start(l: MechLocomotion) -> bool:
	if l._dash_lockout > 0.0 or l._dash_cooldown > 0.0 or l._dash_chain >= l.tuning.dash_max_chain:
		return false
	var cost := l.tuning.dash_cost if l._on_floor else l.tuning.dash_air_cost
	if not l.energy.consume(cost, true):
		return false
	l.assault_on = false  # SPEC §4: a dash cancels the assault boost
	l._dash_cooldown = l.tuning.dash_reload
	l._dash_dir = direction(l)
	# The tick this runs in is already the jet's first tick: charge it here so the jet is exactly
	# `dash_time` long and its midpoint sample starts the ramp in the right place.
	l._dash_t = l.rdelta
	l._dash_iframes_t = 0.0
	l._dash_chain += 1
	l.move_state = label(l)
	l._set_state(MechLocomotion.S.DASH)
	l.body.velocity = l._dash_dir * l.tuning.dash_speed_at(l.rdelta * 0.5 / l.tuning.dash_time)
	l.body.velocity.y = 0.0
	Feel.play(&"dash", l.body.global_position)
	Events.boost_started.emit(&"quick")
	return true


## The eight boost directions, snapped in the camera's frame (no stick = straight ahead).
static func direction(l: MechLocomotion) -> Vector3:
	var m := l.input.move
	if m.length() < 0.05:
		m = Vector2(0.0, 1.0)
	var a := snappedf(atan2(m.x, m.y), PI / 4.0)
	return (l.yaw_basis() * Vector3(sin(a), 0.0, -cos(a))).normalized()


## SPEC §10 animation id: the jet direction in the mech's own frame.
static func label(l: MechLocomotion) -> StringName:
	var local := l.body.global_basis.inverse() * l._dash_dir
	if absf(local.x) > absf(local.z):
		return &"dash_r" if local.x > 0.0 else &"dash_l"
	return &"dash_f" if local.z < 0.0 else &"dash_b"


static func dash(l: MechLocomotion, delta: float) -> void:
	var span := l.tuning.dash_time
	# The speed is sampled at the MIDDLE of the tick, so the 150 -> 42 ramp integrates to exactly 24 m
	# whatever the tick rate — at time scale 0.3 the whole jet is only nine ticks long.
	var u := clampf((l._dash_t + delta * 0.5) / span, 0.0, 1.0)
	l.body.velocity = l._dash_dir * l.tuning.dash_speed_at(u)
	l.body.velocity.y = 0.0
	l._dash_t += delta
	l._dash_iframes_t += l.pdelta
	if l._dash_t >= span:
		_exit(l)
		return
	if l.input.jump_pressed and not l.is_dash_invulnerable():
		# tuning choice: dash-jump once the i-frames are spent; a double tap takes the jet into flight
		if not l.try_flight():
			l._launch()


## The jet hands over to the boost slide, the ground or the air, in that order. The label goes with it,
## so the dash pose never lingers a frame past the jet.
static func _exit(l: MechLocomotion) -> void:
	l.body.velocity = l._dash_dir * l.tuning.dash_exit
	l.body.velocity.y = 0.0
	if not l._on_floor:
		l._vernier = l.tuning.vernier_hang  # air dash only: a short float before gravity bites
	if l.input.boost_held and not l.energy.is_outage():
		MechBoost.start_slide(l)
	elif l._on_floor:
		l.move_state = &"coast"
		l._set_state(MechLocomotion.S.GROUND)
	else:
		l.move_state = &"fall"
		l._air_start_y = l.body.global_position.y
		l._set_state(MechLocomotion.S.AIR)
