extends Node
## Shared fixture for the CameraRig tests (camera-aim): a stand-in mech in a 24 m corridor (wall on one
## side, a deck overhead), the live rig, and the check/report helpers. Extended by test_camera.gd (framing,
## collision, modes, cinematics, cockpit) and test_camera_feel.gd (shake, FOV, landing dip).

const RIG := preload("res://player/camera/camera_rig.tscn")


## Stand-in hero: the rig reaches the AimSystem through `Game.player.aim()` (CONTRACTS §2).
class PlayerStub extends Node3D:
	func aim() -> Node:
		return get_node_or_null(^"AimSystem")


var _fails: int = 0
var _rig: Node3D
var _cam: Camera3D
var _player: Node3D
var _mode_events: Array[bool] = []
var _probe := SphereShape3D.new()


func _build() -> void:
	_probe.radius = 0.5
	_box("ground", Vector3(0.0, -10.0, 0.0), Vector3(400.0, 20.0, 400.0))
	# The south wall's inner face at z = 14 and the deck's underside at y = 15 both force the 42 m arm in,
	# while the chest pivot (12.5 m) stays clear of the deck so the camera never has to sit inside it.
	_box("wall_n", Vector3(0.0, 30.0, -14.0), Vector3(400.0, 60.0, 4.0))
	_box("wall_s", Vector3(0.0, 30.0, 16.0), Vector3(400.0, 60.0, 4.0))
	_box("deck", Vector3(0.0, 17.0, 0.0), Vector3(60.0, 4.0, 28.0))
	_player = PlayerStub.new()
	_player.name = "Player"
	_player.position = Vector3(-80.0, 0.0, 0.0)
	add_child(_player)
	Game.register_player(_player)
	_rig = RIG.instantiate() as Node3D
	add_child(_rig)
	_cam = _rig.call(&"camera") as Camera3D
	Events.camera_mode_changed.connect(func(fp: bool) -> void: _mode_events.append(fp))
	await _ticks(4)


func _box(box_name: String, centre: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = box_name
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = centre
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Advance the shake springs by n × 1/120 s: the rig drives them with Feel.real_delta every physics tick,
## and stepping them explicitly keeps a check independent of how many ticks the harness happened to run.
func _step(shake: Node3D, n: int) -> void:
	for i in n:
		shake.call(&"advance", false, 1.0 / 120.0)


func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		_fails += 1


func _report() -> void:
	print("TEST %s (%d failures)" % ["FAILED" if _fails > 0 else "PASSED", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


# --- measuring through the live camera ------------------------------------------------------------

## One world point -> screen fractions (0..1, y down); NaN when it is at or behind the camera plane.
func _project_point(world: Vector3) -> Vector2:
	var basis := _cam.global_basis
	var tan_v := tan(deg_to_rad(_cam.fov) * 0.5)
	var v := world - _cam.global_position
	var d := v.dot(-basis.z)
	if d < 0.1:
		return Vector2(NAN, NAN)
	return Vector2(v.dot(basis.x) / (d * tan_v * (16.0 / 9.0)) * 0.5 + 0.5,
			0.5 - v.dot(basis.y) / (d * tan_v) * 0.5)


func _corners_of(box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for xi in 2:
		for yi in 2:
			for zi in 2:
				out.append(box.position + Vector3(box.size.x * xi, box.size.y * yi, box.size.z * zi))
	return out


## Screen fractions of a world-space box through the live camera:
## [height, centre_x, crosshair clearance, top, bottom, left, right]. Computed analytically for a 16:9
## frame, so the numbers match the 1600x900 captures and do not depend on the headless window size.
func _project_box(box: AABB) -> Array[float]:
	var basis := _cam.global_basis
	var tan_v := tan(deg_to_rad(_cam.fov) * 0.5)
	var min_n := Vector2(INF, INF)
	var max_n := Vector2(-INF, -INF)
	for c in _corners_of(box):
		var v := c - _cam.global_position
		var d := v.dot(-basis.z)
		if d < 0.1:
			continue
		var n := Vector2(v.dot(basis.x) / (d * tan_v * (16.0 / 9.0)), v.dot(basis.y) / (d * tan_v))
		min_n = min_n.min(n)
		max_n = max_n.max(n)
	return [(max_n.y - min_n.y) * 0.5, (min_n.x + max_n.x) * 0.25 + 0.5, -max_n.x * 0.5,
			0.5 - max_n.y * 0.5, 0.5 - min_n.y * 0.5, min_n.x * 0.5 + 0.5, max_n.x * 0.5 + 0.5]


## Small sphere overlap at the camera: catches a camera buried in a wall, a deck or the street.
func _camera_hits_world() -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _probe
	params.transform = Transform3D(Basis.IDENTITY, _cam.global_position)
	params.collision_mask = Layers.MASK_SIGHT
	params.collide_with_areas = false
	return not get_viewport().world_3d.direct_space_state.intersect_shape(params, 1).is_empty()
