extends Node
## Where do the legs go? (hero-v3 debug)
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_ik.gd

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const BONES: Array[String] = ["Root", "Pelvis", "R_Thigh", "R_Calf", "R_Foot", "R_Toe",
		"Spine02", "Head"]

var model: Node3D
var skeleton: Skeleton3D


func _ready() -> void:
	model = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	skeleton = model.get_node_or_null(^"Model/Hero3Rig/Skeleton3D") as Skeleton3D
	if skeleton == null:
		print("FAIL no skeleton")
		get_tree().quit(1)
		return
	skeleton.force_update_all_bone_transforms()
	_report("rest")
	model.set_locomotion(&"walk", 9.0, Vector2(0.0, -1.0))
	model.gait.reset()
	_report("after reset")
	for i in 3:
		model.position += Vector3(0.0, 0.0, -9.0 / 120.0)
		model.gait.update(1.0 / 120.0)
	_report("after 3 steps")
	print("IK feet world %s" % str(model.gait.foot_targets()))
	print("IK planted %s" % str(model.gait.planted_feet()))
	get_tree().quit(0)


func _report(label: String) -> void:
	var parts: Array[String] = []
	for name in BONES:
		var idx := skeleton.find_bone(name)
		if idx < 0:
			parts.append("%s MISSING" % name)
			continue
		var rest := skeleton.get_bone_global_rest(idx).origin
		var pose := skeleton.get_bone_global_pose(idx).origin
		parts.append("%s rest(%.2f,%.2f,%.2f) pose(%.2f,%.2f,%.2f)" % [name, rest.x, rest.y,
				rest.z, pose.x, pose.y, pose.z])
	print("IK %s\n    %s" % [label, "\n    ".join(parts)])
