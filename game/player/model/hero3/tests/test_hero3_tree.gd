extends Node
## hero-v3: print the imported hero3.glb tree so hero3_model.gd resolves its nodes from evidence.
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_tree.gd

func _ready() -> void:
	var packed := load("res://player/model/hero3/hero3.glb") as PackedScene
	if packed == null:
		print("FAIL: hero3.glb did not load")
		get_tree().quit(1)
		return
	var root := packed.instantiate()
	add_child(root)
	_walk(root, 0)
	var skel := _find(root, "Skeleton3D") as Skeleton3D
	if skel == null:
		print("FAIL: no Skeleton3D in hero3.glb")
		get_tree().quit(1)
		return
	print("BONES %d" % skel.get_bone_count())
	var names: Array[String] = []
	for i in skel.get_bone_count():
		names.append(skel.get_bone_name(i))
	print("BONE NAMES %s" % ", ".join(names))
	var anim := _find(root, "AnimationPlayer") as AnimationPlayer
	print("ANIM %s" % ("none" if anim == null else str(anim.get_animation_list())))
	var mesh := _find(root, "MeshInstance3D") as MeshInstance3D
	if mesh != null:
		print("MESH surfaces=%d aabb=%s" % [mesh.mesh.get_surface_count(), mesh.mesh.get_aabb()])
	print("PASS")
	get_tree().quit(0)


func _walk(node: Node, depth: int) -> void:
	print("%s%s [%s]" % ["  ".repeat(depth), node.name, node.get_class()])
	for child in node.get_children():
		_walk(child, depth + 1)


func _find(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for child in node.get_children():
		var found := _find(child, cls)
		if found != null:
			return found
	return null
