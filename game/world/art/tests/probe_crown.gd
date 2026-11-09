extends Node
## Diagnostic: what is near the Spire crown? (city-art — the lead reports a black blob under it in
## city-build's S2/S4 captures.)
##   tools/godot.sh test res://world/art/tests/probe_crown.gd
## Lists every node city-art added, with its world position, distance from the Crown centre and — for
## anything that draws — its global AABB size, so a stray emitter or shell is attributed instead of
## guessed at.

const CITY_SCENE := "res://world/city.tscn"
const CROWN := Vector3(0.0, 260.0, -120.0)
const RADIUS := 260.0


func _ready() -> void:
	add_child((load(CITY_SCENE) as PackedScene).instantiate())
	for i in 4:
		await get_tree().physics_frame
	var found: Array[String] = []
	_walk(get_tree().root, found)
	found.sort()
	print("CROWN nodes within %d m of %s:" % [int(RADIUS), CROWN])
	for line in found:
		print("  " + line)
	if found.is_empty():
		print("  (none)")
	get_tree().quit(0)


func _walk(node: Node, out: Array[String]) -> void:
	if node is Node3D:
		var n3 := node as Node3D
		var p := n3.global_position
		if p.distance_to(CROWN) <= RADIUS and not _is_city_geometry(node):
			out.append("%s  pos=(%.0f,%.0f,%.0f) d=%.0f  %s"
				% [_path(node), p.x, p.y, p.z, p.distance_to(CROWN), _size(node)])
	for child in node.get_children():
		_walk(child, out)


## The city's own tiles are not interesting here; everything else near the crown is dressing.
func _is_city_geometry(node: Node) -> bool:
	var n := String(node.name)
	return n.begins_with("t") and n.contains("_") and (node.get_parent() == null
		or String(node.get_parent().name) == "Tiles")


func _size(node: Node) -> String:
	if node is VisualInstance3D:
		var aabb := (node as VisualInstance3D).get_aabb().size
		return "aabb=(%.0f,%.0f,%.0f) visible=%s" % [aabb.x, aabb.y, aabb.z,
			str((node as VisualInstance3D).visible)]
	return node.get_class()


func _path(node: Node) -> String:
	var parts: Array[String] = []
	var n: Node = node
	while n != null and n != get_tree().root:
		parts.push_front(String(n.name))
		n = n.get_parent()
	return "/".join(parts)
