extends "res://player/mech/tests/mech_test_base.gd"
## mech-move clock + input suite (lead r3, CONTRACTS §3): the mech's movement runs on
## `Feel.locomotion_delta` (real seconds), its timers on `Feel.player_delta` and its tap/hold windows
## on real time, so witch time and global hit-stops slow the world and never the player.
## Every duration below is measured with `Feel.real_now()`, the unscaled game clock.


func _run() -> void:
	await _setup()
	await _test_dash_in_witch_time()
	await _test_hit_stop_during_boost()
	await _test_double_tap_in_slow_mo()
	await _test_pad_descend()
	await _test_en_drain_in_hit_stop()
	_report("mech-move clocks")


# --- checks --------------------------------------------------------------------------------------

## A dash is a 0.25 s jet of REAL time: witch time must not stretch it or shorten its 24 m.
func _test_dash_in_witch_time() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	Feel.slow_mo(0.3, 2.0, 0.0, 0.0, true)
	await _real_step(0.2)
	_ok(_near(Engine.time_scale, 0.3, 0.01), "witch time is running at 0.3",
			"scale=%.2f" % Engine.time_scale)
	var start := _p.global_position
	var t0 := Feel.real_now()
	Input.action_press(&"boost")
	await _real_step(0.05)
	Input.action_release(&"boost")
	while _dashing() and Feel.real_now() - t0 < 1.0:
		await get_tree().physics_frame
	var secs := Feel.real_now() - t0
	var dist := Vector2(_p.global_position.x - start.x, _p.global_position.z - start.z).length()
	_ok(_near(dist, 24.0, 2.0), "the dash still covers 24 m in witch time", "d=%.2f" % dist)
	_ok(_near(secs, 0.25, 0.02), "the dash still lasts 0.25 s of real time", "t=%.3f" % secs)
	await _wait_slowmo()


## A global hit-stop freezes the world, not the boost: over 1 real second the mech must cover the
## same ground with a 40 ms stop in the middle as it does without one.
func _test_hit_stop_during_boost() -> void:
	var clean := await _boost_run(-1.0)
	var stopped := await _boost_run(0.35)
	_ok(stopped > clean - 1.0, "a 40 ms hit-stop costs the boost less than 1 m",
			"clean=%.2f stopped=%.2f" % [clean, stopped])


## Boost skate for 1 real second and return the ground covered; `hit_at` < 0 runs it clean.
func _boost_run(hit_at: float) -> float:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	await _wait_slowmo()
	Input.action_press(&"boost")
	await _until_state(&"slide", 90)
	await _real_step(0.4)  # up to 42 m/s before the clock starts
	var start := _p.global_position
	var t0 := Feel.real_now()
	var fired := false
	while Feel.real_now() - t0 < 1.0:
		if not fired and hit_at >= 0.0 and Feel.real_now() - t0 >= hit_at:
			fired = true
			Feel.hit_stop(0.04, 0.05)
		await get_tree().physics_frame
	Input.action_release(&"boost")
	var d := Vector2(_p.global_position.x - start.x, _p.global_position.z - start.z).length()
	await _real_step(0.2)
	return d


## The flight double tap is a real-time window. At time scale 0.3 a 0.60 s real gap is only 0.18 s of
## *scaled* time — inside a scaled-time window and outside a real one, so the pair below pins the
## clock down. (0.26 s is used for the inside case: one 120 Hz tick is 28 ms of real time at this
## scale, so the exact 0.30 s boundary cannot be sampled reliably.)
func _test_double_tap_in_slow_mo() -> void:
	_ok(await _double_tap_flies(0.26), "a 0.26 s real double tap enters flight at time scale 0.3")
	_ok(not await _double_tap_flies(0.60), "a 0.60 s real gap is outside the 0.30 s window")


## Teleports the mech into the air, runs witch time and double taps jump with a real-time `gap`
## between the two presses. Returns whether flight started.
func _double_tap_flies(gap: float) -> bool:
	await _wait_slowmo()
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	_p.debug_teleport([0.0, 150.0, 60.0], 0.0)
	await _real_step(0.2)
	Feel.slow_mo(0.3, 3.0, 0.0, 0.0, true)
	await _real_step(0.2)
	Input.action_press(&"jump")
	await _real_step(0.02)
	Input.action_release(&"jump")
	await _real_step(gap - 0.02)
	Input.action_press(&"jump")
	await _real_step(0.05)
	Input.action_release(&"jump")
	await _real_step(0.1)
	var flying := _p.is_flying()
	await _wait_slowmo()
	return flying


## SPEC §3: on the pad, B (boost) held without pushing forward descends in flight; Ctrl does on KB.
func _test_pad_descend() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	_p.debug_teleport([0.0, 150.0, 60.0], 0.0)
	await _step(20)
	await _enter_flight()
	await _real_step(0.6)
	Input.action_press(&"boost")  # pad B with no forward on the stick
	await _real_step(0.5)
	var vy := _p.velocity.y
	Input.action_release(&"boost")
	_ok(vy < -5.0, "B held without move-forward descends in flight", "vy=%.1f" % vy)
	await _real_step(0.6)
	_ok(_p.velocity.y > -5.0, "releasing B stops the descent", "vy=%.1f" % _p.velocity.y)
	await _real_step(0.3)


## Audit [7]: EN is a player-clock meter (CONTRACTS §3) like the regen and the Outage behind it, so a
## global hit-stop must not drain the gauge at the full real rate while that regen is frozen.
func _test_en_drain_in_hit_stop() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	await _wait_slowmo()
	_p.energy = 1000.0
	Input.action_press(&"jump")
	await _until_state(&"hover", 60)
	await _step(40)  # settled onto the 18 m/s ascend at 100 EN/s
	Feel.hit_stop(0.15, 0.05)
	var en0 := _p.energy
	await _real_step(0.15)
	var spent := en0 - _p.energy
	Input.action_release(&"jump")
	_ok(spent < 4.0, "a 0.15 s global hit-stop drains almost no EN (100 EN/s -> 15 EN)",
			"%.2f EN" % spent)
	await _real_step(0.3)
