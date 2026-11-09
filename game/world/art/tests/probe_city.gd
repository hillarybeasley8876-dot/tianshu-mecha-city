extends Node
## Diagnostic: instance city.tscn and report what geometry actually exists and where, so a vista that
## frames empty sky can be blamed on the right unit.
##   tools/godot.sh test res://world/art/tests/probe_city.gd

func _ready() -> void:
	var path := "res://world/city.tscn"
	if not ResourceLoader.exists(path):
		print("PROBE no city.tscn")
		get_tree().quit(1)
		return
	var node := (load(path) as PackedScene).instantiate() as Node3D
	add_child(node)
	await get_tree().process_frame
	await get_tree().process_frame
	var meshes: Array[MeshInstance3D] = []
	_collect(node, meshes)
	var aabb := AABB()
	var first := true
	var tris := 0
	for m in meshes:
		if m.mesh == null:
			continue
		var world := m.global_transform * m.get_aabb()
		aabb = world if first else aabb.merge(world)
		first = false
		for s in range(m.mesh.get_surface_count()):
			tris += m.mesh.surface_get_array_len(s) / 3
	print("PROBE meshes=%d tris=%d aabb pos=%s size=%s" % [meshes.size(), tris, aabb.position, aabb.size])
	for name in ["Spire", "spire", "Block9", "block9", "Tiles", "Skyline"]:
		var n := _find(node, name)
		if n != null:
			print("PROBE found node '%s' (%s)" % [name, n.get_class()])
	for child in node.get_children():
		print("PROBE child %s (%s) children=%d" % [child.name, child.get_class(), child.get_child_count()])
	_report_landmarks(meshes)
	_report_materials(meshes)
	get_tree().quit(0)


## Which material names do the tiles actually carry? The city-art contract is that every surface is
## named `mc_<role>` so it can be replaced by name; this is the check for that.
func _report_materials(meshes: Array[MeshInstance3D]) -> void:
	var names := {}
	for m in meshes:
		if m.mesh == null:
			continue
		for s in range(m.mesh.get_surface_count()):
			var mat := m.mesh.surface_get_material(s)
			var key := "<null>" if mat == null else String(mat.resource_name)
			names[key] = int(names.get(key, 0)) + 1
	print("PROBE materials: %d distinct" % names.size())
	for k in names:
		print("PROBE   mat %-24s x%d" % [k, names[k]])


## How much real geometry stands near each landmark? A vista framing empty sky is usually a
## landmark whose geometry has not been built yet, not a bad camera.
func _report_landmarks(meshes: Array[MeshInstance3D]) -> void:
	var spots := {"spire": Vector3(0.0, 0.0, -120.0), "block9": Vector3(330.0, 32.0, -250.0),
		"pagoda": Vector3(-520.0, 32.0, -430.0), "knot": Vector3(-470.0, 0.0, 40.0)}
	for name in spots:
		var near := 0
		var tallest := 0.0
		var tris := 0
		for m in meshes:
			if m.mesh == null:
				continue
			var w := m.global_transform * m.get_aabb()
			if Vector2(w.get_center().x, w.get_center().z).distance_to(
					Vector2(spots[name].x, spots[name].z)) > 150.0:
				continue
			near += 1
			tallest = maxf(tallest, w.size.y)
			for s in range(m.mesh.get_surface_count()):
				tris += m.mesh.surface_get_array_len(s) / 3
		print("PROBE near %-8s meshes=%-4d tallest=%.0fm tris=%d" % [name, near, tallest, tris])


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)


func _find(node: Node, needle: String) -> Node:
	if String(node.name).to_lower().contains(needle.to_lower()):
		return node
	for c in node.get_children():
		var r := _find(c, needle)
		if r != null:
			return r
	return null
