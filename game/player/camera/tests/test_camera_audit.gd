extends "res://player/camera/tests/camera_test_base.gd"
## Audit regressions (camera-aim, reviews/camera-aim-audit.md). One check per verified finding, each
## written so it FAILS on the pre-fix code: clocks (#1 stick rate, #3 cinematic clock, #8 canopy lag),
## the cinematic contract (#2 end_cinematic ends it), the cockpit (#4 rigid follow, #7 lag reseed) and
## two look-math signs (#5 vertical lock yaw, #6 invert_y on the aim assist).
## Run: tools/godot.sh test res://player/camera/tests/test_camera_audit.gd

const CockpitFrame := preload("res://player/camera/cockpit_frame.gd")
const OPEN := Vector3(0.0, 0.0, -160.0)   ## clear ground outside the base's corridor
const TURN_TICKS := 24                    ## 0.2 s of real time at 120 Hz
const ARM_MIN := 40.0                     ## the arm is fully out again after a cancelled cinematic

## Stand-in AimSystem: the rig only needs `hard_target()`, `assist_delta()` and `look_speed_scale()`
## (CONTRACTS §2), so the audit checks do not need the real scene.
class AimStub extends Node:
	var target: Node3D = null
	var assist: Vector2 = Vector2.ZERO

	func hard_target() -> Node3D:
		return target

	func assist_delta(_delta: float) -> Vector2:
		return assist

	func look_speed_scale() -> float:
		return 1.0

	func aim_point() -> Vector3:
		return Vector3.ZERO


var _aim: AimStub


func _ready() -> void:
	await _build()
	_aim = AimStub.new()
	_aim.name = "AimSystem"
	_player.add_child(_aim)
	await _settle()
	await _test_look_clock()
	await _test_end_cinematic()
	await _test_cinematic_clock()
	await _test_first_person_rigid()
	await _test_lock_vertical()
	await _test_invert_assist()
	await _test_cockpit_lag()
	_report()


## Open ground, rig seated: every check below starts from a deterministic view.
func _settle() -> void:
	_rig.call(&"set_first_person", false)
	_player.position = OPEN
	await _ticks(60)
	_rig.call(&"snap_to_player")
	await _ticks(30)


func _yaw() -> float:
	return (_rig.call(&"look_angles") as Vector2).x


func _pitch() -> float:
	return (_rig.call(&"look_angles") as Vector2).y


func _arm_node() -> Node:
	return _rig.get_node(^"Yaw/Pitch/Shoulder/Arm")


## Holds the right stick for `n` ticks and returns the yaw travelled in degrees.
func _stick_turn(n: int) -> float:
	var from := _yaw()
	Input.action_press(&"look_right")
	await _ticks(n)
	Input.action_release(&"look_right")
	return absf(wrapf(_yaw() - from, -180.0, 180.0))


## Audit #1 (high, clock): the stick rate is converted to real time ONCE. The rig already passes
## Feel.real_delta into take_delta, so a second conversion divided the turn rate by Engine.time_scale
## again — 20x too fast inside a 0.05 hit-stop.
func _test_look_clock() -> void:
	_rig.call(&"set_look", 0.0, -6.0)
	await _ticks(4)
	var normal := await _stick_turn(TURN_TICKS)
	_check(absf(normal - 300.0 * TURN_TICKS / 120.0) < 6.0,
			"a full right stick turns %.0f deg/s at 1.0 time scale (%.1f deg in %.2f s)"
			% [normal / (TURN_TICKS / 120.0), normal, TURN_TICKS / 120.0])
	# A global hit-stop at FeelDirector's 0.05: physics still ticks 120x/s of real time and each delta is
	# scaled, so the same hold must turn the same number of degrees.
	Feel.hit_stop(0.6, 0.05)
	await _ticks(2)
	_check(Engine.time_scale < 0.1, "the hit-stop is running (time scale %.2f)" % Engine.time_scale)
	_rig.call(&"set_look", 0.0, -6.0)
	var frozen := await _stick_turn(TURN_TICKS)
	_check(absf(frozen - normal) < 3.0,
			"the same hold turns the same %.1f deg inside a 0.05 hit-stop (%.1f) — real time, converted once"
			% [normal, frozen])
	await _ticks(90)                 # let the stop expire before the next check


## Audit #2 (high, contract): CONTRACTS §5 — end_cinematic() ENDS the cinematic. Pre-fix it restored the
## arm and look but left CameraCinematic active, so a 40 s drop-in shot kept being re-applied (arm 0,
## held FOV) for the rest of its duration.
func _test_end_cinematic() -> void:
	_rig.call(&"request_cinematic",
			[{"offset": Vector3(0.0, 8.0, 30.0), "fov": 48.0, "t": 0.0}], 30.0)
	await _ticks(4)
	_check(bool(_rig.call(&"is_cinematic")), "the long cinematic took control")
	_check(absf(_cam.fov - 48.0) < 0.5, "its shot holds FOV 48 (%.1f)" % _cam.fov)
	_rig.call(&"end_cinematic")
	await _ticks(2)
	_check(not bool(_rig.call(&"is_cinematic")), "end_cinematic() clears the shot list")
	_check(float(_arm_node().call(&"current_length")) > ARM_MIN,
			"the arm is restored at once (%.1f m)" % float(_arm_node().call(&"current_length")))
	_check(bool(_rig.get_node(^"Look").get(&"enabled")), "look input is handed back")
	await _ticks(40)
	_check(absf(_cam.fov - 55.0) < 2.0, "the held FOV is released (%.1f, want 55)" % _cam.fov)
	var settled := _cam.fov
	await _ticks(90)                 # 0.75 s: the 30 s shot would have re-applied by now
	_check(absf(_cam.fov - settled) < 1.0 and float(_arm_node().call(&"current_length")) > ARM_MIN,
			"the cancelled shot is not re-applied on later ticks (FOV %.1f, arm %.1f m)"
			% [_cam.fov, float(_arm_node().call(&"current_length"))])


## Audit #3 (clock): an execution times its shots on player time (a hit-stop holds the cut with the
## finisher, CONTRACTS §5); presentation beats stay on real time. Under a 0.3x slow-mo the same 0.2 s
## request must therefore take ~24 ticks on `&"real"` and ~80 on `&"player"`.
func _test_cinematic_clock() -> void:
	var shot: Array = [{"offset": Vector3(0.0, 8.0, 30.0), "fov": 45.0, "t": 0.0}]
	Feel.slow_mo(0.3, 4.0, 0.0, 0.0)
	await _ticks(4)
	_check(Engine.time_scale < 0.4, "the slow-mo is running (time scale %.2f)" % Engine.time_scale)
	_rig.call(&"request_cinematic", shot, 0.2, &"real")
	await _ticks(40)                 # 0.33 s of real time > 0.2 s
	_check(not bool(_rig.call(&"is_cinematic")), "a real-clock cinematic ends after 0.2 s of real time")
	_rig.call(&"request_cinematic", shot, 0.2, &"player")
	await _ticks(40)                 # only 0.1 s of player time so far
	_check(bool(_rig.call(&"is_cinematic")),
			"a player-clock cinematic is still running after the same 40 ticks")
	await _ticks(70)                 # 0.275 s of player time > 0.2 s
	_check(not bool(_rig.call(&"is_cinematic")), "and ends once its own player-time duration is up")
	await _ticks(420)                # 3.5 s: the slow-mo eases back out
	_check(Engine.time_scale > 0.99, "the slow-mo released (time scale %.2f)" % Engine.time_scale)


## Audit #4 (integrator): the cockpit view is rigid. A critically damped spring trails a moving target
## by 2v/omega (2.1 m at the 42 m/s skate, 4.2 m at assault), which slides the camera out through the
## canopy pillars pinned at the eye point. Above the canopy's 0.5 visibility the rig rides the eye point.
func _test_first_person_rigid() -> void:
	_rig.call(&"set_first_person", true)
	await _ticks(80)                 # 0.35 s blend + settle
	var worst := 0.0
	for i in 120:                    # one second at the 42 m/s boost skate
		_player.position += Vector3(0.35, 0.0, 0.0)
		await get_tree().physics_frame
		worst = maxf(worst, _rig.global_position.distance_to(CockpitFrame.eye_point(_player)))
	_check(worst < 0.5, "the rig rides the eye point at 42 m/s (worst lag %.2f m, want < 0.5)" % worst)
	_player.position = OPEN
	_rig.call(&"set_first_person", false)
	await _ticks(60)


## Audit #5: a hard-locked target near the vertical through the pivot has an ill-conditioned yaw bearing
## (atan2 of a ~0 horizontal offset flips by up to 180 deg tick to tick). The yaw step must fade out
## there; the pitch term is well conditioned and stays.
func _test_lock_vertical() -> void:
	var body := Node3D.new()
	body.name = "Overhead"
	add_child(body)
	_aim.target = body
	body.global_position = _player.global_position + Vector3(0.0, 60.0, 0.0)
	_rig.call(&"set_look", 90.0, -6.0)
	await _ticks(120)
	_check(absf(wrapf(_yaw() - 90.0, -180.0, 180.0)) < 3.0,
			"a target straight overhead leaves the yaw alone (%.1f deg, want 90)" % _yaw())
	_check(_pitch() > 60.0, "while the pitch still climbs to it (%.1f deg)" % _pitch())
	# The real trigger: the horizontal offset crosses zero (a homing dive, a Harrier passing overhead).
	var worst_step := 0.0
	var last := _yaw()
	for i in 120:
		body.global_position = _player.global_position + Vector3(2.0 - 4.0 * (i % 2), 60.0, 0.0)
		await get_tree().physics_frame
		worst_step = maxf(worst_step, absf(wrapf(_yaw() - last, -180.0, 180.0)))
		last = _yaw()
	_check(worst_step < 3.0,
			"crossing the vertical never whips the view (worst step %.2f deg/tick)" % worst_step)
	_aim.target = null
	body.queue_free()
	await _ticks(4)


## Audit #6: invert_y flips the player's own pitch, not the aim assist. `assist` is already a signed
## "turn toward the soft target" correction, so inverting it too pushed the reticle away at ~25 %/s.
func _test_invert_assist() -> void:
	_aim.assist = Vector2(0.0, -1.0)      # 1 deg/tick "turn up" in the rig's down-positive convention
	_rig.call(&"set_look", 0.0, 0.0)
	await _ticks(30)
	var plain := _pitch()
	var was := bool(Settings.get_value(&"invert_y"))
	Settings.set_value(&"invert_y", true)
	_rig.call(&"set_look", 0.0, 0.0)
	await _ticks(30)
	var inverted := _pitch()
	Settings.set_value(&"invert_y", was)
	_aim.assist = Vector2.ZERO
	_check(plain > 25.0, "the assist pulls the view up 30 deg in 30 ticks (%.1f)" % plain)
	_check(absf(inverted - plain) < 2.0,
			"invert_y does not flip the assist's sign (%.1f vs %.1f deg)" % [inverted, plain])
	await _ticks(4)


## Audit #7 + #8: the canopy's 80 ms yaw lag is only integrated while visible, so it must be reseeded on
## the hidden→visible edge (pre-fix it came back at the previous session's heading and swept into place),
## and it trails a view that turns on real time, so the lag runs on Feel.real_delta too.
func _test_cockpit_lag() -> void:
	_rig.call(&"set_first_person", false)
	await _ticks(60)
	var cockpit := _rig.get_node(^"Cockpit") as Node3D
	_rig.call(&"set_look", 120.0, -6.0)   # turn the view while the canopy is hidden
	await _ticks(10)
	_rig.call(&"set_first_person", true)
	var worst := 0.0
	for i in 60:
		await get_tree().physics_frame
		if not cockpit.visible:
			continue
		var want := deg_to_rad(_yaw())
		worst = maxf(worst, absf(wrapf(cockpit.global_rotation.y - want, -PI, PI)))
	_check(rad_to_deg(worst) < 3.0,
			"the canopy re-seeds its lag on entry (worst %.1f deg off the view)" % rad_to_deg(worst))
	# #8: 240 deg/s of turn in 0.3x slow-mo. On scaled delta the 80 ms lag stretched to 0.27 s.
	Feel.slow_mo(0.3, 2.5, 0.0, 0.0)
	await _ticks(4)
	var worst_slow := 0.0
	var yaw_now := _yaw()               # start where the view is: the check is about the lag, not a jump
	for i in 60:
		yaw_now += 2.0
		_rig.call(&"set_look", yaw_now, -6.0)
		await get_tree().physics_frame
		worst_slow = maxf(worst_slow,
				absf(wrapf(cockpit.global_rotation.y - deg_to_rad(yaw_now), -PI, PI)))
	_check(rad_to_deg(worst_slow) < 30.0,
			"the canopy lag stays at its 80 ms in 0.3x slow-mo (worst %.1f deg behind a 240 deg/s turn)"
			% rad_to_deg(worst_slow))
	await _ticks(300)                # let the slow-mo ease back out
	_rig.call(&"set_first_person", false)
	await _ticks(10)
