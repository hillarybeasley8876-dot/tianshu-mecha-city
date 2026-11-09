extends "res://player/camera/tests/camera_test_base.gd"
## CameraRig feel test (camera-aim). Run: tools/godot.sh test res://player/camera/tests/test_camera_feel.gd
## Shake isolation (trauma never moves the aim), Feel.kick direction and settle, FOV channels (ADS, punch,
## boost), the landing dip / footstep translate, and spring stability for long frames.

const STALL_DT := 0.1           ## s — the longest step the shake accepts (a 70 ms movie frame, a hitch)


func _ready() -> void:
	await _build()
	await _test_shake_isolation()
	await _test_fov()
	await _test_landing_dip()
	_test_shake_stability()
	_test_shake_floor()
	_report()


## Trauma must move the Shake pivot and nothing else: the aim ray direction may not wobble.
func _test_shake_isolation() -> void:
	var shake := _rig.get_node(^"Yaw/Pitch/Shoulder/Arm/Shake") as Node3D
	var before_dir: Vector3 = _rig.call(&"look_dir")
	_rig.call(&"add_trauma", 1.0)
	_step(shake, 1)
	await _ticks(2)
	_check(float(shake.get("trauma")) > 0.5, "trauma was added")
	_check(shake.rotation.length() > 0.0005, "the shake pivot rotates (%.4f rad)" % shake.rotation.length())
	_check(_rig.call(&"look_dir").distance_to(before_dir) < 0.0001, "shake does not move the aim direction")
	_rig.call(&"apply_kick", 2.0, 0.0, 0.0)
	_step(shake, 2)
	_check(absf(shake.rotation.x) > 0.001, "the kick spring rotates the view")
	_step(shake, 150)
	# Feel.kick(deg, world_dir, s) is the channel gameplay uses: firing forward (world -Z with the view
	# facing -Z) must shove the view UP, and a shot to the right must shove it LEFT.
	Feel.kick(3.0, Vector3(0.0, 0.0, -1.0), 0.2)
	_step(shake, 1)
	_check(shake.rotation.x > 0.001, "Feel.kick along the view pitches the camera up (%.4f rad)"
			% shake.rotation.x)
	_check(absf(shake.rotation.y) < 0.001, "a straight recoil does not yaw the view")
	_step(shake, 60)                        # 0.5 s: well past the requested 0.2 s settle
	_check(shake.rotation.length() < 0.001, "the Feel.kick spring settles inside its duration")
	Feel.kick(3.0, Vector3(1.0, 0.0, 0.0), 0.2)
	_step(shake, 1)
	_check(shake.rotation.y < -0.001, "a kick from the right shoves the view left (%.4f rad)"
			% shake.rotation.y)
	_step(shake, 150)                       # 1.25 s
	_check(float(shake.get("trauma")) <= 0.0, "trauma decays at 1.2/s to zero (%.3f left)"
			% float(shake.get("trauma")))
	_check(shake.rotation.length() < 0.001, "the kick settles (%.5f rad left)" % shake.rotation.length())


func _test_fov() -> void:
	Input.action_press(&"aim")
	await _ticks(40)              # SPEC §5: ADS in 0.25 s
	_check(absf(_cam.fov - 38.0) < 0.6, "ADS zooms to 38 (%.1f)" % _cam.fov)
	_check(bool(_rig.call(&"is_ads")), "is_ads() reports the zoom")
	Input.action_release(&"aim")
	await _ticks(60)              # ... and out over 0.40 s
	_check(absf(_cam.fov - 55.0) < 0.6, "FOV returns to 55 (%.1f)" % _cam.fov)
	Feel.fov_kick(3.0, 0.25)      # SPEC §5: dash punch +3°
	await _ticks(2)
	_check(_cam.fov > 57.0, "Feel.fov_kick punches the FOV out (%.1f)" % _cam.fov)
	await _ticks(60)
	_check(absf(_cam.fov - 55.0) < 0.6, "the punch returns to base (%.1f)" % _cam.fov)
	Events.boost_started.emit(&"slide")
	await _ticks(30)
	_check(absf(_cam.fov - 60.0) < 1.0, "boost holds FOV 60 (%.1f)" % _cam.fov)
	Events.boost_started.emit(&"assault")
	await _ticks(30)
	_check(absf(_cam.fov - 66.0) < 1.0, "assault boost holds FOV 66 (%.1f)" % _cam.fov)
	_check(float(_rig.get_node(^"Yaw/Pitch/Shoulder/Arm").get(&"length")) > 29.0,
			"assault boost also lengthens the arm to 30 m")
	Events.boost_ended.emit(&"assault")
	await _ticks(60)
	_check(absf(_cam.fov - 55.0) < 0.6, "boost FOV releases (%.1f)" % _cam.fov)


func _test_landing_dip() -> void:
	var shake := _rig.get_node(^"Yaw/Pitch/Shoulder/Arm/Shake") as Node3D
	Events.landed.emit(10.0)                  # soft: SPEC §5 −0.35 m
	_step(shake, 1)
	_check(absf(shake.position.y + 0.35) < 0.03, "a soft landing dips 0.35 m (%.2f)" % shake.position.y)
	_step(shake, 120)
	_check(absf(shake.position.y) < 0.02, "the dip springs back (%.3f m)" % shake.position.y)
	Events.landed.emit(80.0)                  # terminal velocity: −1.2 m
	_step(shake, 1)
	_check(absf(shake.position.y + 1.2) < 0.05, "a terminal-velocity landing dips 1.2 m (%.2f)"
			% shake.position.y)
	_step(shake, 120)
	Events.footstep.emit(_player.global_position, true)
	_step(shake, 1)
	_check(absf(shake.position.y + 0.12) < 0.03, "a heavy footstep translates 0.12 m (%.3f)"
			% shake.position.y)
	_check(absf(shake.rotation.x) < 0.02, "the footstep does not rotate the view")
	_step(shake, 120)
	_check(absf(shake.position.y) < 0.02, "the step spring settles (%.3f m)" % shake.position.y)


## Regression (lead, movie-mode NaN flood): the strongest kick (ω 45 from a 0.13 s Feel.kick) stepped by
## stalled frames must stay finite and settle; one explicit 70 ms step used to diverge to NaN.
func _test_shake_stability() -> void:
	var shake := _rig.get_node(^"Yaw/Pitch/Shoulder/Arm/Shake") as Node3D
	shake.call(&"add_kick", 4.0, 2.0, 1.0, 0.13)
	shake.call(&"add_trauma", 1.0)
	var worst := 0.0
	for i in 30:
		shake.call(&"advance", false, STALL_DT if i % 2 == 0 else 0.0)
		worst = maxf(worst, shake.rotation.length())
	_check(shake.transform.is_finite(), "stalled 100 ms steps keep the shake finite")
	_check(worst < deg_to_rad(12.0), "and bounded (worst %.2f°)" % rad_to_deg(worst))
	_check(shake.rotation.length() < 0.001, "and the kick settles (%.5f rad left)" % shake.rotation.length())


## Feel.shake_floor holds trauma at its floor for the requested real time, then lets it decay.
func _test_shake_floor() -> void:
	var shake := _rig.get_node(^"Yaw/Pitch/Shoulder/Arm/Shake") as Node3D
	shake.call(&"reset")
	Feel.shake_floor(0.3, 0.5)
	_step(shake, 30)                        # 0.25 s: inside the hold
	_check(float(shake.get("trauma")) >= 0.299, "a shake floor holds trauma at 0.3 (%.3f)"
			% float(shake.get("trauma")))
	_step(shake, 60)                        # 0.75 s: the hold ended 0.25 s ago
	_check(float(shake.get("trauma")) < 0.3, "and releases it after its time (%.3f)"
			% float(shake.get("trauma")))
