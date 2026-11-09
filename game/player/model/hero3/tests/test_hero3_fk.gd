extends Node
## hero-v3: does a translation written on the Pelvis actually propagate down the chain?
## `_write_global` used to write `Transform3D(basis, rest.origin)`, which pins every bone at its rest
## ORIGIN -- the gait computed IK targets that never reached the rig. This test proves which of the
## two composition rules Godot 4.7 uses, so the rewrite can rely on it.
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_fk.gd

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const CHAIN: Array[String] = ["Pelvis", "R_Thigh", "R_Calf", "R_Foot", "R_Toe", "Spine02", "Head"]

var skeleton: Skeleton3D


func _ready() -> void:
	var model := (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	skeleton = model.get_node_or_null(^"Model/Hero3Rig/Skeleton3D") as Skeleton3D
	if skeleton == null:
		print("FAIL no skeleton")
		get_tree().quit(1)
		return
	skeleton.force_update_all_bone_transforms()
	_dump("rest")
	# 1. translate the pelvis 1 m down by writing its GLOBAL pose with an explicit origin
	var pelvis := skeleton.find_bone("Pelvis")
	var rest := skeleton.get_bone_global_rest(pelvis)
	skeleton.set_bone_global_pose(pelvis, Transform3D(rest.basis, rest.origin + Vector3(0, -1.0, 0)))
	skeleton.force_update_all_bone_transforms()
	_dump("pelvis global pose -1 m in y")
	# 2. now rotate the thigh about its own head, keeping the head where FK put it
	var thigh := skeleton.find_bone("R_Thigh")
	var cur := skeleton.get_bone_global_pose(thigh)
	var rest_t := skeleton.get_bone_global_rest(thigh)
	var swing := Quaternion(rest_t.basis.y.normalized(), Vector3(0, -1, 0).normalized())
	skeleton.set_bone_global_pose(thigh, Transform3D(Basis(swing) * rest_t.basis, cur.origin))
	skeleton.force_update_all_bone_transforms()
	_dump("thigh aimed straight down")
	_probe_pose_rotation()
	print("PASS")
	get_tree().quit(0)


## Which composition does `set_bone_pose_rotation` use? Godot's docs say "the bone's local space",
## which is ambiguous between `parent * rest * pose` and `parent * pose * rest`. The gait has to
## know: guessing wrong put the calf above the hip.
func _probe_pose_rotation() -> void:
	var thigh := skeleton.find_bone("R_Thigh")
	var parent := skeleton.get_bone_parent(thigh)
	var rest_local := skeleton.get_bone_rest(thigh)
	var p_basis := skeleton.get_bone_global_pose(parent).basis
	var q := Quaternion(Vector3.RIGHT, deg_to_rad(30.0))
	# candidate A: global = parent * rest * pose  ->  pose = rest^-1 * parent^-1 * target
	# candidate B: global = parent * pose * rest  ->  pose = parent^-1 * target * rest^-1
	var target := p_basis * rest_local.basis * Basis(q)
	skeleton.set_bone_pose_rotation(thigh, (rest_local.basis.inverse() * Basis(q))
			.get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()
	var got := skeleton.get_bone_global_pose(thigh).basis
	print("FK probe A (parent*rest*pose) err %.4f deg"
			% rad_to_deg(got.x.angle_to(target.x) + got.y.angle_to(target.y)))
	# restore, then try B
	skeleton.set_bone_global_pose(thigh, skeleton.get_bone_global_rest(thigh))
	skeleton.force_update_all_bone_transforms()
	var target_b := p_basis * Basis(q) * rest_local.basis
	skeleton.set_bone_pose_rotation(thigh, q)
	skeleton.force_update_all_bone_transforms()
	var got_b := skeleton.get_bone_global_pose(thigh).basis
	print("FK probe B (parent*pose*rest) err %.4f deg"
			% rad_to_deg(got_b.x.angle_to(target_b.x) + got_b.y.angle_to(target_b.y)))


func _dump(label: String) -> void:
	var parts: Array[String] = []
	for bone_name in CHAIN:
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			parts.append("%s MISSING" % bone_name)
			continue
		var p := skeleton.get_bone_global_pose(idx).origin
		parts.append("%s(%.2f,%.2f,%.2f)" % [bone_name, p.x, p.y, p.z])
	print("FK %s\n    %s" % [label, "  ".join(parts)])
