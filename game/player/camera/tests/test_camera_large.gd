extends "res://player/camera/tests/camera_test_base.gd"
## Large-target framing test (camera-aim). Run: tools/godot.sh test res://player/camera/tests/test_camera_large.gd
## CONTRACTS §5: a hard lock on an actor that reports `framing_height() >= 30 m` (the boss: 60) lengthens
## the arm to ≈ 64 m, raises the lock-tracked pitch by ≈ +12° and keeps BOTH the hero and the locked core
## in frame, easing back to the 42 m street shot when the lock drops. A 60 m stand-in titan 120 m out on
## open ground stands in for the boss; a 16 m dummy is the control that must NOT change the framing.

const AIM := preload("res://player/aim/aim_system.tscn")

const HERO_SIZE := Vector3(9.7, 15.4, 13.5)   ## the placeholder hero's bounds
const TITAN_HEIGHT := 60.0
const TITAN_SIZE := Vector3(26.0, 60.0, 26.0)
const STREET_ARM := 42.0
const LARGE_ARM := 64.0
const LARGE_PITCH := 12.0
const EASE_TICKS := 260          ## 0.45 s ease + the 0.25 s arm hold + the 22 m push at 48 m/s


## CONTRACTS §5: the rig reads the height off the ACTOR behind the Targetable, not off the mark.
class Titan extends StaticBody3D:
	func take_hit(_hit: HitInfo) -> void:
		pass
	func is_alive() -> bool:
		return true
	func framing_height() -> float:
		return TITAN_HEIGHT


class Dummy extends StaticBody3D:
	func take_hit(_hit: HitInfo) -> void:
		pass
	func is_alive() -> bool:
		return true


var _aim: Node
var _large: Node
var _titan_body: Node3D


func _titan() -> Node3D:
	return _titan_body


func _ready() -> void:
	await _build()
	_aim = AIM.instantiate()
	_player.add_child(_aim)
	_large = _rig.get_node(^"Large")
	_player.position = Vector3(0.0, 0.0, -160.0)      # open ground: nothing behind the 64 m arm
	await _ticks(200)
	_rig.call(&"snap_to_player")
	await _ticks(30)
	await _test_large_lock()
	await _test_high_core()
	await _test_release()
	await _test_small_target()
	_report()


## A 60 m titan with its lock point at mid-body: the boss case from CONTRACTS §5.
func _test_large_lock() -> void:
	var titan := _spawn(Titan.new(), Vector3(0.0, TITAN_HEIGHT * 0.5, -280.0), TITAN_SIZE, &"Core")
	_titan_body = titan.get_parent() as Node3D
	_check(float(_large.call(&"framing_height", titan)) == TITAN_HEIGHT,
			"the channel reads framing_height() off the target's actor")
	_aim.call(&"lock_to", titan)
	var inside := 0
	var lowest := INF
	for i in EASE_TICKS:
		await get_tree().physics_frame
		if _camera_hits_world():
			inside += 1
		lowest = minf(lowest, _cam.global_position.y)
	_check(_rig.call(&"hard_target") == titan, "the titan stays locked through the reframe")
	_check(is_equal_approx(float(_large.call(&"value")), 1.0),
			"the framing factor reaches 1 (%.2f)" % float(_large.call(&"value")))
	var arm := float(_rig.get_node(^"Yaw/Pitch/Shoulder/Arm").call(&"current_length"))
	_check(absf(arm - LARGE_ARM) < 1.0, "the arm opens to %.0f m for a %.0f m target (%.1f)" % [
			LARGE_ARM, TITAN_HEIGHT, arm])
	# The pitch is the geometric bearing to the locked core plus the contract's +12°.
	var to: Vector3 = titan.global_position - (_rig.get_node(^"Yaw/Pitch") as Node3D).global_position
	var bearing := rad_to_deg(atan2(to.y, Vector2(to.x, to.z).length()))
	var pitch := (_rig.call(&"look_angles") as Vector2).y
	_check(absf(pitch - (bearing + LARGE_PITCH)) < 1.0,
			"the view lifts %.1f° above the core's bearing (want bearing %.1f° + %.0f°)" % [
					pitch - bearing, bearing, LARGE_PITCH])
	_check(inside == 0, "the camera never enters geometry while reframing (%d ticks inside, min y %.1f)"
			% [inside, lowest])
	_check(_cam.global_position.y > 5.0, "the camera stays above the street while looking up (y %.1f)"
			% _cam.global_position.y)
	# CONTRACTS §5 "keeps BOTH the hero and the locked point in frame": whole bodies, not just a point.
	_check(_on_screen(_hero_box()), "the hero stays fully in frame (%s)" % _band(_hero_box()))
	_check(_on_screen(_titan_box()), "the whole %.0f m titan is in frame, feet to crest (%s)" % [
			TITAN_HEIGHT, _band(_titan_box())])
	var core := _project_point(titan.global_position)
	_check(core.x > 0.0 and core.x < 1.0 and core.y > 0.0 and core.y < 1.0,
			"the locked core projects inside the frame (%.2f, %.2f)" % [core.x, core.y])
	var cropped := _project_box(_titan_box())
	print("      titan spans %.0f %% of the frame height at the large framing" % [cropped[0] * 100.0])


## A lock point at the titan's crest is the case a flat +12° cannot serve: 64 m of arm pitched that
## high would put the camera under the street. The rig clamps the offset instead of burying the shot.
func _test_high_core() -> void:
	var titan := _titan()
	var crest := Targetable.new()
	crest.name = "Crest"
	crest.priority = 2.0
	titan.add_child(crest)
	crest.position = Vector3(0.0, TITAN_HEIGHT * 0.5, 0.0)      # world y 60: the head
	_aim.call(&"lock_to", crest)
	await _ticks(EASE_TICKS)
	_check(_rig.call(&"hard_target") == crest, "the crest stays locked")
	var to: Vector3 = crest.global_position - (_rig.get_node(^"Yaw/Pitch") as Node3D).global_position
	var bearing := rad_to_deg(atan2(to.y, Vector2(to.x, to.z).length()))
	var pitch := (_rig.call(&"look_angles") as Vector2).y
	_check(pitch - bearing < LARGE_PITCH - 0.5,
			"the +%.0f° offset is clamped for a high core (%.1f°)" % [LARGE_PITCH, pitch - bearing])
	_check(_cam.global_position.y > 3.0, "the camera stays above the street at the crest (y %.1f)"
			% _cam.global_position.y)
	_check(not _camera_hits_world(), "and out of the geometry (%s)" % _cam.global_position)
	crest.queue_free()


## Easing back: the lock drops and the street shot has to come back on its own.
func _test_release() -> void:
	_aim.call(&"lock_to", null)
	# The rig does NOT snap the view back — the tracked pitch is the player's to own once the lock is
	# gone. The crest lock left it 19° up, where a 42 m arm would bury the camera, so the arm is
	# geometry-limited until the view comes down. Look back at the street first, as a player would.
	await _ticks(60)
	var mid := float(_large.call(&"value"))
	_check(mid > 0.0 and mid < 1.0, "the framing eases back instead of snapping (%.2f after 0.5 s)" % mid)
	_rig.call(&"set_look", 0.0, -6.0)
	await _ticks(200)
	_check(is_zero_approx(float(_large.call(&"value"))),
			"the factor eases back to 0 (%.2f)" % float(_large.call(&"value")))
	var arm := float(_rig.get_node(^"Yaw/Pitch/Shoulder/Arm").call(&"current_length"))
	_check(absf(arm - STREET_ARM) < 1.0, "the arm returns to the %.0f m street shot (%.1f)" % [
			STREET_ARM, arm])
	_check(is_zero_approx(float(_large.call(&"pitch_offset"))), "the pitch offset is gone")
	var pivot := (_rig.get_node(^"Yaw/Pitch") as Node3D).global_position.y
	_check(absf(pivot - 12.5) < 0.5, "the pivot is back at 12.5 m (%.1f)" % pivot)


## A 16 m street target declares no framing height: the lock must not touch the framing at all.
func _test_small_target() -> void:
	var dummy := _spawn(Dummy.new(), Vector3(0.0, 9.0, -240.0), Vector3(12.0, 18.0, 12.0), &"Mark")
	_aim.call(&"lock_to", dummy)
	await _ticks(EASE_TICKS)
	_check(float(_large.call(&"framing_height", dummy)) == 0.0,
			"an actor without framing_height() reports 0")
	_check(is_zero_approx(float(_large.call(&"value"))),
			"a street-sized target leaves the framing alone (%.2f)" % float(_large.call(&"value")))
	var arm := float(_rig.get_node(^"Yaw/Pitch/Shoulder/Arm").call(&"current_length"))
	_check(absf(arm - STREET_ARM) < 1.0, "the arm stays at %.0f m for a street target (%.1f)" % [
			STREET_ARM, arm])
	_aim.call(&"lock_to", null)


# --- helpers --------------------------------------------------------------------------------------

func _spawn(body: StaticBody3D, centre: Vector3, size: Vector3, mark_name: StringName) -> Targetable:
	body.collision_layer = Layers.ENEMY
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mark := Targetable.new()
	mark.name = mark_name
	body.add_child(mark)
	add_child(body)
	body.global_position = centre
	return mark


func _hero_box() -> AABB:
	# The stand-in's origin is at its feet, so the box hangs off it rather than around it.
	return AABB(_player.global_position - Vector3(HERO_SIZE.x * 0.5, 0.0, HERO_SIZE.z * 0.5), HERO_SIZE)


func _titan_box() -> AABB:
	return AABB(_titan().global_position - TITAN_SIZE * 0.5, TITAN_SIZE)


func _on_screen(box: AABB) -> bool:
	var m := _project_box(box)
	return m[3] > 0.0 and m[4] < 1.0 and m[5] > 0.0 and m[6] < 1.0


func _band(box: AABB) -> String:
	var m := _project_box(box)
	return "x %.2f–%.2f, y %.2f–%.2f" % [m[5], m[6], m[3], m[4]]
