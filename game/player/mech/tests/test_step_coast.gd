extends "res://player/mech/tests/mech_test_base.gd"
## mech-move r8 item 1: the step-up COAST (SPEC §4 "Stepping").
##
## `MechStepping.try_step` used to move the capsule up onto a kerb in ONE tick. Measured tick by tick
## on the sandbox kerb (`probe_float.gd --case=walk_kerb --debug=1`), that is 2.01 m up and 4.24 m
## forward between two consecutive physics frames — the hip cleared the trailing foot's plant by
## 6.96 m before the gait released it, 10.4 m from a hip whose leg reaches 8.5 m, so the leg IK
## clamped and the sole floated 0.91 m above the kerb (`walk_kerb` 75 % near, worst +0.91 / -1.11).
##
## The coast walks the same displacement out over `run-up / speed` seconds, which is exactly the speed
## the mech was already doing, and holds the model node on the lower surface until the legs catch up.
## These rows are the capsule half of that gate; the leg half is hero-v3's `probe_float.gd`
## (`walk_kerb` 75 % -> 100 % near, worst +0.02 / -0.00).

## A 1 m kerb on the same lane, clear of the base range's 2 m kerb (z 0), 6 m block (-100) and
## 10 m wall (-200): the lead's "run a 2 m step and a 1 m step, up and down, at walk and at run".
const LOW_KERB := [Vector3(-120.0, 0.5, -50.0), Vector3(40.0, 1.0, 12.0)]
## The biggest single-tick move a coasting mech may make. At run speed (28 m/s, 120 Hz) the frame's
## own motion is 0.233 m, so this is 2.5x that; the old teleport was 4.24 m.
const MAX_TICK_MOVE := 0.6
## Where the measurement stops: 1 m short of the kerb's far edge, so the walk-off the far side (a
## real 2 m fall, and the only airborne part of the crossing) is never counted as a climb defect.
const MEASURE_Z := -5.0


func _run() -> void:
	await _setup()
	_build_low_kerb()
	await _test_walk_2m()
	await _test_run_2m()
	await _test_walk_1m()
	await _test_run_1m()
	await _test_step_down()
	await _test_model_lag()
	await _test_coast_cancelled()
	_report("mech-move step coast")


func _build_low_kerb() -> void:
	var body := StaticBody3D.new()
	body.name = "low_kerb"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = LOW_KERB[0] as Vector3
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = LOW_KERB[1] as Vector3
	shape.shape = box
	body.add_child(shape)
	add_child(body)


# --- the crossing --------------------------------------------------------------------------------

## Walks the mech from `from_z` to `to_z` at stick `mag` and reports everything the coast rows read:
## the biggest single-tick move, the slowest the mech ever got, how many ticks it spent coasting / off
## the floor, how high it climbed and how far the model lagged.
func _cross(mag: float, from_z: float, to_z: float) -> Dictionary:
	await _reset(Vector3(-120.0, GROUND_Y, from_z))
	Input.action_press(&"move_forward", mag)
	await _step(90)  # up to speed on the flat, well clear of the kerb
	var out := {"jump": 0.0, "slow": 99.0, "air": 0, "coast": 0, "climb": 0.0, "lag": 0.0,
			"lag_ticks": 0}
	var prev := _p.global_position
	var y0 := _p.global_position.y
	for i in 900:
		await get_tree().physics_frame
		if _p.global_position.z < to_z:
			break
		var now := _p.global_position
		out["jump"] = maxf(float(out["jump"]), Vector2(now.x - prev.x, now.z - prev.z).length())
		prev = now
		out["slow"] = minf(float(out["slow"]), _speed())
		out["lag"] = maxf(float(out["lag"]), _loco.step_lag)
		if _loco.step_lag > 0.01:
			out["lag_ticks"] = int(out["lag_ticks"]) + 1
		if _loco.coasting():
			out["coast"] = int(out["coast"]) + 1
		if not _p.is_on_floor():
			out["air"] = int(out["air"]) + 1
	Input.action_release(&"move_forward")
	out["climb"] = _p.global_position.y - y0
	return out


## The four rows every crossing owes: no teleport, no stall, no air, and the mech is on the kerb.
func _cross_rows(r: Dictionary, id: String, rise: float, min_speed: float) -> void:
	_ok(float(r["jump"]) < MAX_TICK_MOVE,
			"%s: the capsule is never teleported onto the kerb" % id,
			"max tick move %.3f m (was 4.24 m as one teleport)" % float(r["jump"]))
	_ok(int(r["coast"]) >= 1, "%s: the climb is a coast, not a jump" % id,
			"coasting %d ticks" % int(r["coast"]))
	_ok(int(r["air"]) == 0, "%s: the mech never leaves the floor over the kerb" % id,
			"airborne %d ticks" % int(r["air"]))
	_ok(float(r["slow"]) > min_speed, "%s: the kerb costs no speed" % id,
			"min %.2f m/s" % float(r["slow"]))
	_ok(_near(float(r["climb"]), rise, 0.3) and _p.is_on_floor(),
			"%s: the mech ends up standing on the %.0f m kerb" % [id, rise],
			"dy=%.2f floor=%s" % [float(r["climb"]), _p.is_on_floor()])
	_ok(float(r["lag"]) > rise - 0.3, "%s: the model holds the lower surface while it climbs" % id,
			"max lag %.2f m" % float(r["lag"]))


func _test_walk_2m() -> void:
	_cross_rows(await _cross(0.5, 60.0, -5.0), "2 m at a walk", 2.0, 6.0)


func _test_run_2m() -> void:
	_cross_rows(await _cross(1.0, 60.0, -5.0), "2 m at a run", 2.0, 12.0)


func _test_walk_1m() -> void:
	_cross_rows(await _cross(0.5, -20.0, -55.0), "1 m at a walk", 1.0, 6.0)


func _test_run_1m() -> void:
	_cross_rows(await _cross(1.0, -20.0, -55.0), "1 m at a run", 1.0, 12.0)


## The other half of "up and down": walking OFF the kerb's far edge is a real 2 m fall, and it must
## land soft and keep its speed — the coast must not leave a lip the mech trips on.
func _test_step_down() -> void:
	for row: Array in [[0.5, "a walk", 6.0], [1.0, "a run", 12.0]]:
		var mag := float(row[0])
		await _reset(Vector3(-120.0, GROUND_Y, 60.0))
		Input.action_press(&"move_forward", mag)
		await _step(90)
		var slow := 99.0
		var landed := false
		for i in 900:
			await get_tree().physics_frame
			if _p.global_position.z < -6.0 and _p.global_position.z > -30.0:
				slow = minf(slow, _speed())
			if _p.is_on_floor() and _p.global_position.z < -8.0:
				landed = true
				break
		Input.action_release(&"move_forward")
		_ok(landed, "walking off the kerb at %s lands on the road" % String(row[1]),
				"z=%.1f" % _p.global_position.z)
		_ok(_loco.land_kind != &"hard", "and it is not a hard landing at %s" % String(row[1]),
				String(_loco.land_kind))
		_ok(slow > float(row[2]), "the step down at %s costs no speed" % String(row[1]),
				"min %.2f m/s" % slow)


## The model lag is the half that lets the legs follow: the node is held on the lower surface for the
## whole climb and is back on the body by the time the mech has walked the kerb out.
func _test_model_lag() -> void:
	var r := await _cross(0.5, 60.0, -5.0)
	var rest := _p.get_node("Model") as Node3D
	_ok(int(r["lag_ticks"]) >= 1 and float(r["lag"]) > 1.7,
			"the model node lags the capsule by the kerb's rise while it climbs",
			"%d ticks, max %.2f m" % [int(r["lag_ticks"]), float(r["lag"])])
	var back := false
	Input.action_press(&"move_forward", 0.5)
	for i in 600:
		await get_tree().physics_frame
		if _loco.step_lag <= 0.001:
			back = true
			break
	Input.action_release(&"move_forward")
	_ok(back, "and the lag is fully unwound before the mech is off the kerb",
			"lag %.3f z=%.1f" % [_loco.step_lag, _p.global_position.z])
	_ok(rest.position.y > -_p.tuning.capsule_height * 0.5 - 0.01,
			"the model node is back on the body origin", "y=%.3f" % rest.position.y)


## A coast owns the body, so anything that changes state has to take it back: a jump half way up a
## kerb must end the coast and hand the mech to the air, not leave it gliding on a dead curve.
func _test_coast_cancelled() -> void:
	await _reset(Vector3(-120.0, GROUND_Y, 20.0))
	Input.action_press(&"move_forward", 1.0)
	var caught := false
	for i in 900:
		await get_tree().physics_frame
		if _loco.coasting():
			caught = true
			break
	_ok(caught, "a run into the kerb reaches the coast", "z=%.1f" % _p.global_position.z)
	Input.action_press(&"jump")
	await _step(4)
	Input.action_release(&"jump")
	await _step(10)
	Input.action_release(&"move_forward")
	_ok(not _loco.coasting(), "a jump during the coast ends it", "coasting=%s" % _loco.coasting())
	_ok(not _p.is_on_floor(), "and the mech is in the air", "floor=%s" % _p.is_on_floor())
