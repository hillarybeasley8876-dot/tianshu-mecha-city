extends "res://player/mech/tests/mech_test_base.gd"
## mech-move locomotion acceptance suite (SPEC §4): ground, dash, air, flight, boost, energy,
## landing tiers and the damage pipeline. The stepping rules live in `test_stepping.gd`.

func _run() -> void:
	await _setup()

	await _test_run_speed()
	await _test_facing()
	await _test_dash()
	await _test_dash_chain()
	await _test_dash_chain_reset()
	await _test_hop()
	await _test_ascend_and_hover()
	await _test_dive()
	await _test_flight()
	await _test_assault_pitch()
	await _test_boost_and_assault()
	await _test_assault_from_ground()
	await _test_energy_regen()
	await _test_outage()
	await _test_hard_landing()
	await _test_ramp()
	_report("mech-move locomotion")


# --- checks --------------------------------------------------------------------------------------

func _test_run_speed() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	Input.action_press(&"move_forward")
	var walk_t := -1.0
	var run_t := -1.0
	for i in 150:
		await get_tree().physics_frame
		var s := _speed()
		if walk_t < 0.0 and s >= 8.5:
			walk_t = float(i + 1) / 120.0
		if run_t < 0.0 and s >= 15.5:
			run_t = float(i + 1) / 120.0
	var top := _speed()
	Input.action_release(&"move_forward")
	_ok(_near(top, 16.0, 1.0), "run top speed 16 m/s", "v=%.2f" % top)
	await _step(4)
	_ok(_p.move_state() == &"coast", "coasting out of a run has its own state",
			String(_p.move_state()))
	_ok(walk_t > 0.0 and walk_t <= 0.4, "walk 9 m/s reached within 0.4 s", "t=%.3f" % walk_t)
	_ok(run_t > 0.0 and run_t <= 0.7, "run 16 m/s reached within 0.7 s", "t=%.3f" % run_t)


## Audit [1] (high): `face_toward` turned the body AWAY from the stick, so every steering caller ran
## the mech backwards and perfect alignment was an unstable equilibrium.
func _test_facing() -> void:
	var cases := {&"move_right": Vector3.RIGHT, &"move_left": Vector3.LEFT, &"move_back": Vector3.BACK}
	for action: StringName in cases:
		await _reset(Vector3(0.0, GROUND_Y, 60.0))
		Input.action_press(action)
		await _step(300)  # 180 deg at the 120-180 deg/s leg turn rate
		var dot := (-_p.global_basis.z).dot(cases[action] as Vector3)
		var moved := _p.velocity.normalized().dot(cases[action] as Vector3)
		Input.action_release(action)
		_ok(dot > 0.99 and moved > 0.99, "running %s faces and moves that way" % action,
				"facing=%.3f moving=%.3f" % [dot, moved])
	# The dash label is read in the mech's own frame, so it is only right when the facing is.
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	Input.action_press(&"move_right")
	await _step(300)
	await _tap(&"boost")
	_ok(_p.move_state() == &"dash_f", "a dash along the heading is labelled dash_f",
			String(_p.move_state()))
	Input.action_release(&"move_right")


func _test_dash() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	var en0 := _p.energy
	var last := _p.global_position
	var total := 0.0
	var spent := 0.0
	var iframes := 0
	var running := false
	Input.action_press(&"boost")
	for i in 90:
		await get_tree().physics_frame
		if i == 3:
			Input.action_release(&"boost")
		var d := _p.global_position.distance_to(last)
		last = _p.global_position
		if not _dashing():
			if running:
				break
			continue
		if not running:
			running = true
			spent = en0 - _p.energy
		total += d
		if _p.is_invulnerable():
			iframes += 1
	_ok(_near(total, 24.0, 2.0), "dash covers 24 m in 0.25 s", "d=%.2f" % total)
	_ok(_near(spent, 110.0, 0.01), "dash costs 110 EN on the ground", "en=%.1f" % spent)
	_ok(iframes == 12, "dash i-frames are exactly 12 physics ticks", "n=%d" % iframes)


func _test_dash_chain() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	var chains: Array[int] = []
	for n in 3:
		var wait := 0
		while not _p.can_cancel(&"dash") and wait < 120:  # SPEC §4: 0.38 s ground reload
			await get_tree().physics_frame
			wait += 1
		Input.action_press(&"boost")
		await _step(2)
		Input.action_release(&"boost")
		var guard := 0
		while not _dashing() and guard < 30:
			await get_tree().physics_frame
			guard += 1
		chains.append(_loco.dash_chain())
		while _dashing() and guard < 120:
			await get_tree().physics_frame
			guard += 1
	_ok(chains == [1, 2, 3], "dash chain counts 1..3", str(chains))
	_ok(not _p.can_cancel(&"dash"), "4th dash refused: 0.45 s lockout")
	await _step(70)
	Input.action_press(&"boost")
	await _step(3)
	Input.action_release(&"boost")
	_ok(_dashing(), "dash available again after the lockout")


## CONTRACTS §5: Rift Step spends the chain itself and hands it back through `reset_dash_chain()`.
func _test_dash_chain_reset() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	await _dash_now()
	await _dash_now()
	_ok(_loco.dash_chain() == 2, "two dashes put the chain at 2", "chain=%d" % _loco.dash_chain())
	_p.reset_dash_chain()
	_ok(_loco.dash_chain() == 0, "reset_dash_chain clears the chain",
			"chain=%d" % _loco.dash_chain())
	await _dash_now()
	_ok(_loco.dash_chain() == 1, "the chain counts from 1 again after the reset",
			"chain=%d" % _loco.dash_chain())


## Taps boost once the 0.38 s reload allows it and returns with the jet running, so the chain can be
## read mid-dash (a finished dash has already rolled the chain into its lockout).
func _dash_now() -> void:
	var wait := 0
	while not _p.can_cancel(&"dash") and wait < 120:
		await get_tree().physics_frame
		wait += 1
	await _tap(&"boost")
	var guard := 0
	while not _dashing() and guard < 30:
		await get_tree().physics_frame
		guard += 1


func _test_hop() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	var y0 := _p.global_position.y
	var top := y0
	var landed := &""
	Input.action_press(&"jump")
	await _step(3)
	Input.action_release(&"jump")
	for i in 240:
		await get_tree().physics_frame
		top = maxf(top, _p.global_position.y)
		if landed == &"" and String(_p.move_state()).begins_with("land"):
			landed = _p.move_state()
		if i > 40 and _p.is_on_floor():
			break
	_ok(_near(top - y0, 8.0, 0.8), "thruster hop apex 8 m", "h=%.2f" % (top - y0))
	# Lead r1: a hop touches down at ~20 m/s, which must stay a soft landing.
	_ok(landed == &"land_light" and _loco.land_kind == &"soft", "a plain hop is a soft landing",
			"%s/%s impact=%.1f" % [landed, _loco.land_kind, _last_impact])


func _test_ascend_and_hover() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	Input.action_press(&"jump")
	var guard := await _until_state(&"hover", 60)
	await _step(40)  # let the hop's upward velocity settle onto the 18 m/s ascend
	var en0 := _p.energy
	var y0 := _p.global_position.y
	await _step(120)
	var climb := _p.global_position.y - y0
	var ascend := en0 - _p.energy
	Input.action_release(&"jump")
	_ok(guard, "holding jump ascends")
	_ok(_near(ascend, 100.0, 6.0), "ascend drains 100 EN/s", "%.1f EN/s" % ascend)
	_ok(_near(climb, 18.0, 1.5), "ascend climbs 18 m/s", "%.2f m/s" % climb)

	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_p.energy = 50.0
	Input.action_press(&"jump")
	await _until_state(&"hover", 60)
	en0 = _p.energy
	await _step(120)
	var hover := en0 - _p.energy
	Input.action_release(&"jump")
	_ok(_near(hover, 40.0, 4.0), "hover (low EN) drains 40 EN/s", "%.1f EN/s" % hover)


func _test_dive() -> void:
	await _reset(Vector3(0.0, 200.0, 60.0), 0.0, false)
	await _step(30)
	Input.action_press(&"descend")
	var guard := 0
	while guard < 200:
		await get_tree().physics_frame
		guard += 1
		if _p.velocity.y <= -44.0:
			break
	Input.action_release(&"descend")
	_ok(_p.velocity.y <= -44.0 and _p.velocity.y >= -46.0, "descend dives at 45 m/s",
			"vy=%.1f" % _p.velocity.y)


func _test_flight() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	_p.debug_teleport([0.0, 150.0, 60.0], 0.0)
	await _step(20)
	await _enter_flight()
	_ok(_p.is_flying(), "flight toggles on a double tap in the air")
	await _step(150)
	_ok(_near(_speed(), 50.0, 2.0), "flight cruises 50 m/s", "v=%.2f" % _speed())
	var en0 := _p.energy
	await _step(120)
	_ok(_near(en0 - _p.energy, 80.0, 6.0), "flight drains 80 EN/s", "%.1f EN/s" % (en0 - _p.energy))
	_ok(_p.is_flying(), "flight holds while EN lasts")


## Lead r1: at assault speed in flight the jet carves into a dive at `assault_pitch_deg` (45 deg/s)
## instead of snapping to the crosshair. Lead r3: the flight assault is the `assault` toggle, not boost.
func _test_assault_pitch() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	_p.debug_teleport([0.0, 200.0, 60.0], 0.0)
	await _step(20)
	await _enter_flight()
	await _step(90)  # level cruise before the jet lights
	var p0 := _pitch_deg()
	_cam().set(&"pitch", -0.6)  # look down: the jet may only carve towards it
	await _tap(&"assault")
	await _real_step(0.5)
	var rate := (_pitch_deg() - p0) / 0.5
	await _real_step(1.0)
	var speed := _p.velocity.length()
	_ok(_p.is_flying(), "the assault boost keeps the mech in flight")
	_ok(rate < -32.0 and rate > -58.0, "flight boost carves into the dive at ~45 deg/s",
			"%.1f deg/s" % rate)
	_ok(_near(speed, 84.0, 5.0), "the dive holds assault speed", "v=%.1f" % speed)
	await _tap(&"assault")
	_ok(not _loco.assault_on and _p.is_flying(), "the assault toggle switches off again")


## Lead r3: the boost is sustained for as long as it is held and never becomes the assault by itself;
## `assault` is its own toggle.
func _test_boost_and_assault() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	Input.action_press(&"boost")
	var held := await _until_state(&"slide", 90)
	_ok(held, "holding boost skates")
	var en0 := _p.energy
	await _step(60)
	_ok(_near(_speed(), 42.0, 2.0), "ground boost skates at 42 m/s", "v=%.2f" % _speed())
	_ok(_p.energy >= en0, "ground boost is free and EN regenerates", "d=%.1f" % (_p.energy - en0))
	await _step(360)  # 3 s held: SPEC §4 says the skate is sustained, it never escalates
	_ok(_p.move_state() == &"slide" and not _loco.assault_on,
			"3 s of boost is still a 42 m/s skate", String(_p.move_state()))
	_ok(_near(_speed(), 42.0, 2.0), "the sustained boost holds 42 m/s", "v=%.2f" % _speed())
	await _tap(&"assault")
	held = await _until_state(&"assault", 60)
	_ok(held, "the assault toggle lights the assault boost from a boost")
	await _step(130)  # 0.30 s ignition + spin-up to 84 m/s
	var s := _speed()
	Input.action_release(&"boost")  # SPEC §4: the assault boost is a toggle, not a hold
	await _step(60)
	_ok(_p.move_state() == &"assault" and _near(_speed(), 84.0, 3.0),
			"assault boost holds 84 m/s after the boost is released", "v=%.2f" % _speed())
	_ok(_near(s, 84.0, 3.0), "assault boost reaches 84 m/s", "v=%.2f" % s)
	await _tap(&"assault")
	await _step(6)
	_ok(not _loco.assault_on and _p.move_state() != &"assault", "the assault toggle exits",
			String(_p.move_state()))
	await _step(30)


## SPEC §4: the assault boost also lights straight from the ground, and the 0.25 s skid brake drops it.
func _test_assault_from_ground() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	await _tap(&"assault")
	var lit := await _until_state(&"assault", 30)
	_ok(lit, "the assault toggle works from a standstill")
	await _step(150)
	_ok(_near(_speed(), 84.0, 3.0), "ground assault boost reaches 84 m/s", "v=%.2f" % _speed())
	Input.action_press(&"move_back")  # stick against the jet: AC6 skid brake
	var braked := false
	for i in 90:
		await get_tree().physics_frame
		if not _loco.assault_on:
			braked = true
			break
	Input.action_release(&"move_back")
	_ok(braked, "the 0.25 s skid brake cancels the assault boost")
	await _step(30)


func _test_energy_regen() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_p.energy = 500.0
	_p.consume_energy(1.0)
	var e0 := _p.energy
	await _step(66)  # 0.55 s: still inside the 0.6 s ground delay
	_ok(absf(_p.energy - e0) < 0.5, "no EN regen before the 0.6 s ground delay",
			"d=%.2f" % (_p.energy - e0))
	await _step(60)  # 1.05 s total -> 0.45 s of regen at 500/s
	var gained := _p.energy - e0
	_ok(gained > 180.0 and gained < 280.0, "ground EN regen 500/s after the delay", "d=%.1f" % gained)


func _test_outage() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_p.energy = 50.0
	var drained := _p.drain_energy(1000.0)
	_ok(not drained and _p.energy <= 0.0, "EN 0 starts the Outage")
	_ok(not _p.consume_energy(10.0), "no EN spending during the Outage")
	await _step(168)  # 1.4 s
	_ok(_p.energy <= 0.001, "Outage pauses regen for 1.5 s", "en=%.2f" % _p.energy)
	await _step(18)  # 1.55 s: the instant +250 has landed, dash still needs 300
	_ok(_p.energy >= 249.0 and _p.energy <= 300.0, "instant +250 EN when the Outage ends",
			"en=%.1f" % _p.energy)
	_ok(not _p.can_cancel(&"dash"), "dash stays locked until 300 EN after an Outage")
	await _step(60)
	_ok(_p.can_cancel(&"dash"), "dash unlocks once EN is back over 300", "en=%.1f" % _p.energy)


func _test_hard_landing() -> void:
	await _reset(Vector3(-295.0, 47.5, 0.0), 0.0, false)
	var got := await _until_prefix("land", 600)
	_ok(got and _p.move_state() == &"land_heavy", "a 40 m drop off the deck is a hard landing",
			String(_p.move_state()))
	# Lead r1: `land_heavy` feel only from 32 m/s down, which a 40 m drop clears with room to spare.
	_ok(_loco.land_kind == &"hard" and _last_impact >= _p.tuning.heavy_feel_speed,
			"the deck drop is a hard landing with the land_heavy feel",
			"%s impact=%.1f" % [_loco.land_kind, _last_impact])
	await _step(60)
	_ok(not String(_p.move_state()).begins_with("land"), "hard landing recovers",
			String(_p.move_state()))


func _test_ramp() -> void:
	await _reset(Vector3(-220.0, GROUND_Y, 118.0))
	var y0 := _p.global_position.y
	Input.action_press(&"move_forward")
	await _step(600)
	Input.action_release(&"move_forward")
	var dy := _p.global_position.y - y0
	_ok(dy > 15.0 and _p.is_on_floor(), "the 19 deg deck ramp is climbable at run speed",
			"dy=%.1f y=%.1f" % [dy, _p.global_position.y])
