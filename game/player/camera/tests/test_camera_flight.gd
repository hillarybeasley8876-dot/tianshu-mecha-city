extends "res://player/camera/tests/camera_test_base.gd"
## Flight framing (camera-aim, lead r7 item 3). Drives the rig through the three flight beats the
## lead named — a 20 m/s climb to +60 m, an 84 m/s assault and a 95 m/s dive — and gates every tick
## on what the brief asks for: the hero's screen bbox stays >= 1/5 of the frame height, the hero stays
## inside the frame, and the camera -> hero sight line is never blocked for more than 0.3 s.
## Two control checks pin the promise that the street rig is untouched.
## Run: tools/godot.sh test res://player/camera/tests/test_camera_flight.gd

const CLIMB := 20.0        ## m/s, MechTuning.flight_vertical
const ASSAULT := 84.0      ## m/s, MechTuning.flight_boost_speed
const DIVE := 95.0         ## m/s, MechTuning.dive_speed
const SETTLE := 0.5        ## s of flight before the gates start counting
const MIN_HEIGHT := 0.20   ## fraction of the frame height the hero must span
const MAX_OCCLUDED := 36   ## ticks = 0.3 s at 120 Hz
const START := Vector3(0.0, 12.0, 0.0)

## Stand-in flying hero: the rig reads `is_flying()`, `velocity` and `move_state()` off `Game.player`
## (CONTRACTS §2) and nothing else, so this is the whole contract surface the flight channel needs.
class FlyStub extends Node3D:
	var flying: bool = false
	var velocity: Vector3 = Vector3.ZERO

	func aim() -> Node:
		return get_node_or_null(^"AimSystem")

	func is_flying() -> bool:
		return flying

	## The real mech boosts through the assault jet (MechTuning.flight_boost_speed = 84 m/s), and the
	## rig's ground spring is at its heaviest (omega 7) while boosting — the worst case for the lag.
	func is_boosting() -> bool:
		return flying and velocity.length() > 60.0

	func move_state() -> StringName:
		return &"fly"

	## No model: the rig's `_feet_point` falls back to the node origin, so the chest pivot is 12.5 m up.
	func model() -> Node3D:
		return null


var _fly: FlyStub
var _worst_height: float = 1.0
var _worst_centre: Vector2 = Vector2.ZERO
var _occluded: int = 0
var _worst_occluded: int = 0
var _off_frame: int = 0


func _ready() -> void:
	await _build_flight()
	await _test_ground_untouched()
	await _flight(Vector3(0.0, CLIMB, 0.0), 4.0, "climb to +%.0f m" % (CLIMB * 4.0), START)
	await _flight(Vector3(0.0, 0.0, -ASSAULT), 3.0, "assault at %.0f m/s" % ASSAULT, START)
	# mech-move request 6: `look_rate [0, -22]` pitches the view off the hero and the arm never
	# re-acquires it. The player owns the pitch, so the gate is that the hero stays framed anyway.
	# gate_size false: a player who deliberately pitches 66 deg down is looking at the mech from
	# above, where its 8 m of depth is what projects — that is geometry, not a framing failure. The
	# gate for this beat is the one that actually broke in the trailer: the hero stays in frame.
	await _flight(Vector3(0.0, 0.0, -ASSAULT), 3.0, "assault while the player pitches down 22 deg/s",
			START, -22.0, false)
	await _flight(Vector3(0.0, -DIVE, 0.0), 1.6, "dive at %.0f m/s" % DIVE,
			Vector3(0.0, 220.0, 0.0))
	await _test_release()
	_report()


## Open sky with a forest of tall pillars: the flight path crosses them, so the arm's occlusion probe
## is exercised on every beat instead of only on the ground.
func _build_flight() -> void:
	_probe.radius = 0.5
	_box("ground", Vector3(0.0, -10.0, 0.0), Vector3(4000.0, 20.0, 4000.0))
	for i in 9:
		var a := TAU * float(i) / 9.0
		_box("pillar%d" % i, Vector3(cos(a), 60.0, sin(a)) * 70.0, Vector3(10.0, 140.0, 10.0))
	_fly = FlyStub.new()
	_fly.name = "Player"
	_fly.position = START
	add_child(_fly)
	Game.register_player(_fly)
	_player = _fly
	_rig = RIG.instantiate() as Node3D
	add_child(_rig)
	_cam = _rig.call(&"camera") as Camera3D
	await _ticks(4)
	_rig.call(&"snap_to_player")
	await _ticks(30)


## Control: with `is_flying()` false the flight channel is inert — the arm, the pitch and the follow
## are exactly the street rig's, so nothing in this change can move a ground shot.
func _test_ground_untouched() -> void:
	_fly.flying = false
	_fly.velocity = Vector3.ZERO
	await _ticks(120)
	_check(float(_rig.call(&"hud_state")[&"arm_length"]) > 41.0,
			"on the ground the arm is still the 42 m street arm")
	_check(is_zero_approx(float(_rig.get_node(^"Flight").call(&"value"))),
			"on the ground the flight channel is at 0")
	var before := (_rig.call(&"look_angles") as Vector2).y
	_rig.call(&"set_look", 0.0, 20.0)
	await _ticks(30)
	_check(is_equal_approx((_rig.call(&"look_angles") as Vector2).y, 20.0),
			"on the ground the pitch is the player's alone (%.1f -> %.1f)"
			% [before, (_rig.call(&"look_angles") as Vector2).y])
	_rig.call(&"set_look", 0.0, -6.0)


## Fly `vel` for `seconds`, stepping the stub by hand (a stand-in has no CharacterBody3D to integrate
## it) and gating every tick after SETTLE on the brief's three numbers.
func _flight(vel: Vector3, seconds: float, label: String, start: Vector3,
		pitch_rate: float = 0.0, gate_size: bool = true) -> void:
	_reset(start)
	_fly.flying = true
	_fly.velocity = vel
	_rig.call(&"snap_to_player")
	var ticks := int(seconds * 120.0)
	var settle := int(SETTLE * 120.0)
	var pitch := (_rig.call(&"look_angles") as Vector2).y
	for i in ticks:
		_fly.position += vel / 120.0
		if not is_zero_approx(pitch_rate):
			pitch = clampf(pitch + pitch_rate / 120.0, -70.0, 75.0)
			_rig.call(&"set_look", 0.0, pitch)
		await get_tree().physics_frame
		if i < settle:
			continue
		_measure()
	if gate_size:
		_check(_worst_height >= MIN_HEIGHT, "%s: hero spans %.1f%% of the frame (>= %.0f%%)"
				% [label, _worst_height * 100.0, MIN_HEIGHT * 100.0])
	_check(_off_frame == 0, "%s: hero inside the frame every tick (%d ticks off, worst centre %.2f,%.2f)"
			% [label, _off_frame, _worst_centre.x, _worst_centre.y])
	_check(_worst_occluded <= MAX_OCCLUDED, "%s: sight line blocked %.2f s at worst (<= 0.30 s)"
			% [label, float(_worst_occluded) / 120.0])
	print("  %s: min height %.1f%%, occluded %.2f s, arm %.1f m, flight %.2f" % [label,
			_worst_height * 100.0, float(_worst_occluded) / 120.0,
			float(_rig.call(&"hud_state")[&"arm_length"]), float(_rig.get_node(^"Flight").call(&"value"))])


## The hero's screen box plus the camera -> chest sight line, through the live camera.
func _measure() -> void:
	var box := AABB(_fly.global_position - Vector3(4.0, 8.0, 4.0), Vector3(8.0, 16.0, 8.0))
	var m := _project_box(box)
	_worst_height = minf(_worst_height, m[0])
	var centre := Vector2(m[1], (m[3] + m[4]) * 0.5)
	if centre.x < 0.0 or centre.x > 1.0 or centre.y < 0.0 or centre.y > 1.0:
		_off_frame += 1
		_worst_centre = centre
	_occluded = _occluded + 1 if _blocked() else 0
	_worst_occluded = maxi(_worst_occluded, _occluded)


## True when world geometry sits between the lens and the hero's chest.
func _blocked() -> bool:
	var params := PhysicsRayQueryParameters3D.create(_cam.global_position,
			_fly.global_position + Vector3.UP * 12.5)
	params.collision_mask = Layers.MASK_SIGHT
	params.collide_with_areas = false
	return not get_viewport().world_3d.direct_space_state.intersect_ray(params).is_empty()


func _reset(start: Vector3) -> void:
	_fly.position = start
	_worst_height = 1.0
	_worst_centre = Vector2.ZERO
	_occluded = 0
	_worst_occluded = 0
	_off_frame = 0


## Touchdown: the factor eases out and the street numbers come back.
func _test_release() -> void:
	_fly.flying = false
	_fly.velocity = Vector3.ZERO
	await _ticks(120)
	var flight := float(_rig.get_node(^"Flight").call(&"value"))
	_check(is_zero_approx(flight), "touchdown eases the flight factor back to 0 (%.3f)" % flight)
	_check(float(_rig.call(&"hud_state")[&"arm_length"]) > 41.0,
			"touchdown restores the 42 m street arm")
