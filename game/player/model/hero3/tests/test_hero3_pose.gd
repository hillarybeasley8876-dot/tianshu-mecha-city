extends Node
## hero-v3: where does every bone end up after the gait has run? (the upper body vanished from the
## filmstrip; this says whether the bones moved or the plates did)
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_pose.gd

const SCENE := "res://player/model/hero3/hero3_model.tscn"

var skeleton: Skeleton3D
var model: Node3D


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
	_dump("rest")
	model.set_locomotion(&"walk", 9.0, Vector2(0.0, -1.0))
	model.gait.reset()
	for i in 240:
		model.position += Vector3(0.0, 0.0, -9.0 / 120.0)
		model.gait.update(1.0 / 120.0)
	_dump("after 2 s of walking")
	_meshes()
	get_tree().quit(0)


func _dump(label: String) -> void:
	var parts: Array[String] = []
	for i in skeleton.get_bone_count():
		var rest := skeleton.get_bone_global_rest(i).origin
		var pose := skeleton.get_bone_global_pose(i).origin
		parts.append("%s (%.1f,%.1f,%.1f)->(%.1f,%.1f,%.1f)" % [skeleton.get_bone_name(i),
				rest.x, rest.y, rest.z, pose.x, pose.y, pose.z])
	print("POSE %s\n    %s" % [label, "\n    ".join(parts)])


func _meshes() -> void:
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_node := node as MeshInstance3D
			print("MESH %-16s visible=%s aabb=%s skin=%s" % [node.name, mesh_node.visible,
					mesh_node.get_aabb(), mesh_node.skin != null])
		stack.append_array(node.get_children())
