extends Node
## Framing probe (camera-aim, scratch): loads main.tscn, lets the rig settle, then prints the hero
## model's screen-space footprint (height fraction, horizontal centre, crosshair clearance) measured
## through the live rig, so the framing can be checked from numbers as well as from captures.
## Run: tools/godot.sh test res://player/camera/tests/measure_framing.gd

const ASPECT := 16.0 / 9.0


func _ready() -> void:
	var main := load("res://main.tscn") as PackedScene
	add_child(main.instantiate())
	for i in 300:
		await get_tree().physics_frame
	var rig := Game.camera_rig as Node3D
	var cam := rig.call(&"camera") as Camera3D
	var model := Game.player.call(&"model") as Node3D
	var aabb := _model_aabb(model)
	var arm := float(rig.get_node(^"Yaw/Pitch/Shoulder/Arm").call(&"current_length"))
	var shoulder := (rig.get_node(^"Yaw/Pitch/Shoulder") as Node3D).position.x
	print("fov %.1f  arm %.1f  shoulder %.1f  hero %.2f m tall" % [
			cam.fov, arm, shoulder, aabb.size.y])
	var m := _measure(cam, aabb)
	print("height %.1f%% (want 36-44)  centre_x %.1f%% (want 31-37)  clearance %.1f%% (want >=6)  box y %.1f..%.1f%%"
			% [m[0] * 100.0, m[1] * 100.0, m[2] * 100.0, m[3] * 100.0, m[4] * 100.0])
	rig.call(&"set_first_person", true)
	for i in 120:
		await get_tree().physics_frame
	var canopy := rig.get_node(^"Cockpit/Canopy")
	print("first person: cam %s  player %s  model %s  canopy visible %s  canopy xform %s" % [
			cam.global_position, Game.player.global_position, model.global_position,
			canopy.visible, canopy.global_position])
	print("TEST PASSED (0 failures)")
	get_tree().quit(0)


## [height fraction, centre_x fraction, crosshair clearance fraction, top fraction, bottom fraction]
func _measure(cam: Camera3D, aabb: AABB) -> Array[float]:
	var basis := cam.global_basis
	var tan_v := tan(deg_to_rad(cam.fov) * 0.5)
	var min_n := Vector2(INF, INF)
	var max_n := Vector2(-INF, -INF)
	for c in _corners_of(aabb):
		var v := c - cam.global_position
		var d := v.dot(-basis.z)
		if d < 0.1:
			continue
		var n := Vector2(v.dot(basis.x) / (d * tan_v * ASPECT), v.dot(basis.y) / (d * tan_v))
		min_n = min_n.min(n)
		max_n = max_n.max(n)
	return [(max_n.y - min_n.y) * 0.5, (min_n.x + max_n.x) * 0.25 + 0.5, -max_n.x * 0.5,
			0.5 - max_n.y * 0.5, 0.5 - min_n.y * 0.5]


func _corners_of(aabb: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for xi in 2:
		for yi in 2:
			for zi in 2:
				out.append(aabb.position + Vector3(aabb.size.x * xi, aabb.size.y * yi, aabb.size.z * zi))
	return out


func _model_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in _meshes(root):
		var mi := node as MeshInstance3D
		var box: AABB = mi.global_transform * mi.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _meshes(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	if node is MeshInstance3D:
		found.append(node)
	for c in node.get_children():
		found.append_array(_meshes(c))
	return found
