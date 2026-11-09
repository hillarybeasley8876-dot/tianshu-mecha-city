extends "res://player/mech/tests/mech_test_base.gd"
## mech-move stepping acceptance suite (SPEC §4 "Stepping"): the 2.5 m step-up, the auto-hop over
## obstacles up to 7 m while boosting, and the refusal to hop a taller wall.


func _run() -> void:
	await _setup()

	await _test_step_up()
	await _test_boost_hop()
	await _test_assault_hop()
	await _test_boost_wall()
	await _test_lunge_kerb()
	await _test_lunge_graze()
	await _test_lunge_head_on()
	_report("mech-move stepping")


# --- checks --------------------------------------------------------------------------------------

## SPEC §4 step-up 2.5 m: a kerb at run speed must not cost a single frame of speed.
func _test_step_up() -> void:
	await _reset(Vector3(-120.0, GROUND_Y, 60.0))
	var y0 := _p.global_position.y
	var slow := 99.0
	Input.action_press(&"move_forward")
	await _step(60)  # up to run speed before the kerb
	for i in 400:
		await get_tree().physics_frame
		if _p.global_position.z < 20.0:
			slow = minf(slow, _speed())
		if _p.global_position.z < -20.0:
			break
	Input.action_release(&"move_forward")
	var climb := _p.global_position.y - y0
	_ok(_loco.step_events >= 1, "the 2 m kerb is climbed by the step-up shim",
			"events=%d" % _loco.step_events)
	_ok(_near(climb, 2.0, 0.4) and _p.is_on_floor(), "the mech ends up standing on the kerb",
			"dy=%.2f floor=%s" % [climb, _p.is_on_floor()])
	_ok(slow > 12.0, "run speed never drops below 12 m/s over the kerb", "min=%.2f" % slow)


## SPEC §4 auto-hop: while the thrusters are lit the mech vaults anything up to 7 m tall.
func _test_boost_hop() -> void:
	# Far enough back that the tap-boost dash is spent before the block: the hop is a boost-slide move.
	await _reset(Vector3(-120.0, GROUND_Y, -20.0))
	Input.action_press(&"boost")
	await _step(60)
	var clear := false
	for i in 300:
		await get_tree().physics_frame
		if _p.global_position.z < -112.0:
			clear = true
			break
	Input.action_release(&"boost")
	_ok(_loco.hop_events >= 1, "boosting into the 6 m block auto-hops", "events=%d" % _loco.hop_events)
	_ok(clear, "the hop carries the mech over the block", "z=%.1f" % _p.global_position.z)
	_ok(_loco.land_kind != &"hard", "landing out of a boost hop is not a hard landing",
			String(_loco.land_kind))


## Audit [4]: the hop arc is solved for the boost's gravity and constant speed, so the airborne vault
## must stay in the boost. The air states use the 79 m/s² rise gravity, brake towards 16 m/s and read
## a still-rising mech's |vy| as an impact, which clipped the edge and cost a landing recovery.
func _test_assault_hop() -> void:
	await _reset(Vector3(-120.0, GROUND_Y, -20.0))
	await _tap(&"assault")
	await _until_state(&"assault", 30)
	await _step(60)  # 0.30 s ignition + spin-up: 84 m/s into the block
	var landed := false
	var clear := false
	for i in 300:
		await get_tree().physics_frame
		if String(_p.move_state()).begins_with("land"):
			landed = true
		if _p.global_position.z < -112.0:
			clear = true
			break
	_ok(_loco.hop_events >= 1, "the assault boost hops the 6 m block", "events=%d" % _loco.hop_events)
	_ok(clear and not landed, "the assault vault clears the block with no landing recovery",
			"z=%.1f landed=%s" % [_p.global_position.z, landed])
	_ok(_loco.assault_on and _p.move_state() == &"assault", "the assault jet survives the vault",
			"%s/%s" % [_p.move_state(), _loco.assault_on])
	await _tap(&"assault")


## ... but a 10 m wall is above the 7 m limit, so the boost stops instead of vaulting it.
func _test_boost_wall() -> void:
	await _reset(Vector3(-120.0, GROUND_Y, -140.0))
	Input.action_press(&"boost")
	await _step(40)
	for i in 300:
		await get_tree().physics_frame
		if _p.velocity.length() < 1.0 and _p.global_position.z < -180.0:
			break
	var stopped := _speed()
	Input.action_release(&"boost")
	_ok(_loco.hop_events == 0, "no hop into a 10 m wall", "events=%d" % _loco.hop_events)
	_ok(stopped < 8.0, "the boost is stopped by the wall", "v=%.2f" % stopped)
	_ok(_p.global_position.z > -196.0, "the mech never gets past the wall",
			"z=%.1f" % _p.global_position.z)


## A 110 m/s lunge across the 2 m kerb steps onto it and arrives (it used to stop dead at the kerb).
func _test_lunge_kerb() -> void:
	await _reset(Vector3(-120.0, GROUND_Y, 60.0))
	var events := _loco.step_events
	_p.lunge_to(Vector3(-120.0, 0.0, -40.0), 110.0, 1.5)
	await _lunge_done(240)
	_ok(_loco.step_events > events, "the lunge steps onto the kerb", "events=%d" % (_loco.step_events - events))
	_ok(_p.global_position.z < -30.0, "and arrives past it", "z=%.1f" % _p.global_position.z)


## A lunge that runs along the 10 m wall's south face at a ~4° angle grazes it (normal across the path)
## and slides along it instead of ending there.
func _test_lunge_graze() -> void:
	await _reset(Vector3(-150.0, GROUND_Y, -191.0), -90.0)
	_p.lunge_to(Vector3(-90.0, 0.0, -195.0), 110.0, 1.5)
	await _lunge_done(240)
	_ok(_p.global_position.x > -100.0, "a grazed wall does not stop the lunge", "x=%.1f" % _p.global_position.x)


## Head-on into the 10 m wall still stops it.
func _test_lunge_head_on() -> void:
	await _reset(Vector3(-120.0, GROUND_Y, -150.0))
	_p.lunge_to(Vector3(-120.0, 0.0, -260.0), 110.0, 1.5)
	await _lunge_done(240)
	_ok(_p.global_position.z > -200.0, "a head-on wall stops the lunge", "z=%.1f" % _p.global_position.z)
	_ok(_loco.move_state != &"lunge", "and ends the lunge state", String(_loco.move_state))


func _lunge_done(max_ticks: int) -> void:
	await get_tree().physics_frame
	for i in max_ticks:
		if _loco.move_state != &"lunge":
			return
		await get_tree().physics_frame
