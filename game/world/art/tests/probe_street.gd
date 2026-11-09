extends Node
## Diagnostic: does the look-dev street actually build its geometry? Prints every child's AABB.

func _ready() -> void:
	var scene := load("res://world/art/tests/street.tscn") as PackedScene
	var node := scene.instantiate() as Node3D
	add_child(node)
	await get_tree().process_frame
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var m := mi.mesh
			print("MESH %s surfaces=%d aabb=%s mat=%s" % [child.name,
				(m.get_surface_count() if m != null else -1),
				str(mi.get_aabb()), str(mi.material_override)])
		elif child is MultiMeshInstance3D:
			var mm := child as MultiMeshInstance3D
			print("MM %s instances=%d visible=%s aabb=%s" % [child.name,
				(mm.multimesh.instance_count if mm.multimesh != null else -1),
				mm.visible, str(mm.get_aabb())])
		else:
			print("NODE ", child.name, " ", child.get_class())
	get_tree().quit(0)
