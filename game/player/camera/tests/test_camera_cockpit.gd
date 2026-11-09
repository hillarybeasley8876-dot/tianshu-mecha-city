extends "res://player/camera/tests/camera_test_base.gd"
## First-person cockpit contract (camera-aim, lead r7 item 1). Three things the r7 brief asks for:
## the 1st<->3rd blend is SPEC §5's 0.35 s, it HOLDS the aim point so the crosshair never jumps, and
## the pilot does not see their own chassis — `CameraHeroCull` puts the hero's visual instances on one
## dedicated visual layer and the first-person camera clears it from its `cull_mask`.
## Run: tools/godot.sh test res://player/camera/tests/test_camera_cockpit.gd

const CockpitFrame := preload("res://player/camera/cockpit_frame.gd")
const HIDE_BIT := 1 << 18        ## camera_hero_cull.gd's layer; kept in step by hand (both are mine)
const BLEND_TICKS := 42          ## 0.35 s at 120 Hz
const RETICLE_BAND := 0.06       ## fraction of the frame the held aim point may drift off centre
const OPEN := Vector3(0.0, 0.0, -160.0)

## Stand-in hero with a real model subtree, so the cull has something to tag.
class ModelPlayer extends Node3D:
	var model_node: Node3D = null

	func _ready() -> void:
		model_node = Node3D.new()
		model_node.name = "Model"
		add_child(model_node)
		var mesh := MeshInstance3D.new()
		mesh.name = "Body"
		mesh.mesh = BoxMesh.new()
		model_node.add_child(mesh)
		Game.register_player(self)

	func aim() -> Node:
		return get_node_or_null(^"AimSystem")

	func model() -> Node3D:
		return model_node

	func is_flying() -> bool:
		return false

	func is_boosting() -> bool:
		return false


func _ready() -> void:
	await _build_cockpit()
	await _test_blend_holds_aim()
	await _test_chassis_cull()
	await _test_eye_cap()
	_report()


func _build_cockpit() -> void:
	_probe.radius = 0.5
	_box("ground", Vector3(0.0, -10.0, 0.0), Vector3(2000.0, 20.0, 2000.0))
	var hero := ModelPlayer.new()
	hero.name = "Player"
	hero.position = OPEN
	add_child(hero)
	_player = hero
	_rig = RIG.instantiate() as Node3D
	add_child(_rig)
	_cam = _rig.call(&"camera") as Camera3D
	await _ticks(4)
	_rig.call(&"snap_to_player")
	await _ticks(30)


## SPEC §5: the cross-fade is 0.35 s and keeps the aim point, so the reticle never leaves the target.
func _test_blend_holds_aim() -> void:
	_rig.call(&"set_look", 0.0, 0.0)
	await _ticks(30)
	var held := (_rig.call(&"aim_origin") as Vector3) + (_rig.call(&"look_dir") as Vector3) * 300.0
	var worst := 0.0
	var ticks := 0
	_rig.call(&"set_first_person", true)
	while float(_rig.call(&"first_person_blend")) < 1.0 and ticks < 120:
		await get_tree().physics_frame
		ticks += 1
		worst = maxf(worst, _off_centre(held))
	_check(absi(ticks - BLEND_TICKS) <= 2, "the 1st-person blend takes 0.35 s (%d ticks, want %d)"
			% [ticks, BLEND_TICKS])
	_check(worst < RETICLE_BAND,
			"the held aim point stays on the reticle through the blend (worst %.3f, band %.2f)"
			% [worst, RETICLE_BAND])
	# And back again, the same two promises.
	worst = 0.0
	ticks = 0
	_rig.call(&"set_first_person", false)
	while float(_rig.call(&"first_person_blend")) > 0.0 and ticks < 120:
		await get_tree().physics_frame
		ticks += 1
		worst = maxf(worst, _off_centre(held))
	_check(absi(ticks - BLEND_TICKS) <= 2, "the blend back to third person takes 0.35 s (%d ticks)"
			% ticks)
	_check(worst < RETICLE_BAND,
			"and it holds the aim point on the way out too (worst %.3f)" % worst)


func _off_centre(world: Vector3) -> float:
	var uv := _project_point(world)
	if is_nan(uv.x):
		return 1.0
	return (uv - Vector2(0.5, 0.5)).length()


## The pilot does not see their own chassis: the hero's meshes move to one dedicated visual layer and
## the first-person camera clears it. Third person, the trailer's cinematic cameras, the canopy HUD's
## SubViewport and the debug camera all keep the default mask, so nothing else loses the mech.
func _test_chassis_cull() -> void:
	var body := (_player.call(&"model") as Node3D).get_node(^"Body") as MeshInstance3D
	await _ticks(40)
	_check(body.layers == HIDE_BIT, "the hero's meshes are on the cull layer (layers %d, want %d)"
			% [body.layers, HIDE_BIT])
	_check((_cam.cull_mask & HIDE_BIT) != 0, "in third person the camera still renders that layer")
	_rig.call(&"set_first_person", true)
	await _ticks(60)
	_check((_cam.cull_mask & HIDE_BIT) == 0, "in the cockpit the camera culls the chassis layer")
	_check(float(_rig.call(&"first_person_blend")) > 0.99, "and the blend finished")
	# The cockpit itself is the rig's own geometry, so it must NOT be on that layer.
	var dash := _rig.get_node_or_null(^"Cockpit")
	_check(dash != null and not _on_hide_layer(dash),
			"the canopy is not on the cull layer — the pilot still sees it")
	_rig.call(&"set_first_person", false)
	await _ticks(60)
	_check((_cam.cull_mask & HIDE_BIT) != 0, "and third person gets the chassis back")


## Lead r7 item 1 gate: the eye never wanders off the model's `cockpit` socket. The blend's bob filter
## damps the gait's step bob, and its correction is capped, so travel (a climb, a fall) is passed
## through almost whole instead of dragging the camera metres behind the socket.
func _test_eye_cap() -> void:
	_rig.call(&"set_first_person", true)
	await _ticks(60)
	var worst := 0.0
	for i in 120:
		_player.position.y += (30.0 if i < 60 else -30.0) / 120.0
		await get_tree().physics_frame
		worst = maxf(worst, float(_rig.call(&"eye_residual")))
	_check(worst <= 0.2, "the eye stays within 0.2 m of the cockpit socket at 30 m/s of travel (%.3f m)"
			% worst)
	_rig.call(&"set_first_person", false)
	await _ticks(60)
	_check(is_zero_approx(float(_rig.call(&"eye_residual"))),
			"and the residual is not recorded in third person")


func _on_hide_layer(node: Node) -> bool:
	if node is VisualInstance3D and ((node as VisualInstance3D).layers & HIDE_BIT) != 0:
		return true
	for c in node.get_children():
		if _on_hide_layer(c):
			return true
	return false
