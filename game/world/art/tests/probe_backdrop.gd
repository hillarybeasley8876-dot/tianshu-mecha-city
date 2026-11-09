extends Node
## Diagnostic: find the big flat masses that close the vistas (city-art, review r3 §3).
##   tools/godot.sh test res://world/art/tests/probe_backdrop.gd
## The `mc_*` roles cover a whole 200 m tile, so a shader cannot tell a tower from the map-edge skirt —
## both are `mc_concrete`. This lists every mesh whose world AABB is far larger than a building, with
## the role its surfaces carry, which is what the skyline/backdrop material has to key off.

const CITY_SCENE := "res://world/city.tscn"
const MIN_EXTENT := 300.0        ## metres in one horizontal axis
const MIN_HEIGHT := 90.0         ## metres tall
## The `look_cams.json` "high" camera, and the normalised screen box the flat mass occupies in it.
const EYE := Vector3(-458.8, 120.0, 556.0)
const LOOK := Vector3(-380.1, 64.3, 167.8)
const BOX := Rect2(0.10, 0.26, 0.45, 0.22)

var _cam: Camera3D


func _ready() -> void:
	add_child((load(CITY_SCENE) as PackedScene).instantiate())
	for i in 3:
		await get_tree().physics_frame
	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)
	_cam.global_position = EYE
	_cam.look_at(LOOK, Vector3.UP)
	await get_tree().process_frame
	var rows: Array[String] = []
	_walk(get_tree().root, rows)
	rows.sort()
	print("BACKDROP candidates (horizontal extent > %d m, height > %d m):" % [int(MIN_EXTENT), int(MIN_HEIGHT)])
	for line in rows:
		print("  " + line)
	if rows.is_empty():
		print("  (none)")
	get_tree().quit(0)


## Normalised screen box of a world AABB, or an empty rect when it is entirely behind the camera.
func _screen_box(aabb: AABB) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(8):
		var corner := aabb.get_endpoint(i)
		if _cam.is_position_behind(corner):
			continue
		var p := _cam.unproject_position(corner) / _cam.get_viewport().get_visible_rect().size
		lo = lo.min(p)
		hi = hi.max(p)
	return Rect2(lo, hi - lo) if lo.x < INF else Rect2()


func _walk(node: Node, out: Array[String]) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var aabb := mi.global_transform * mi.get_aabb()
			var size := aabb.size
			var flat := maxf(size.x, size.z)
			if flat > MIN_EXTENT and size.y > MIN_HEIGHT:
				var box := _screen_box(aabb)
				out.append("%s  centre=(%.0f,%.0f,%.0f) size=(%.0f,%.0f,%.0f) roles=%s%s"
					% [_path(node), aabb.get_center().x, aabb.get_center().y, aabb.get_center().z,
					   size.x, size.y, size.z, str(_roles(mi)),
					   "  <<< COVERS THE MASS (%.2f,%.2f %.2fx%.2f)"
					   % [box.position.x, box.position.y, box.size.x, box.size.y]
					   if box.intersects(BOX) else ""])
	for child in node.get_children():
		_walk(child, out)


func _roles(mi: MeshInstance3D) -> Array[String]:
	var out: Array[String] = []
	for s in range(mi.mesh.get_surface_count()):
		var mat := mi.get_surface_override_material(s)
		if mat == null:
			mat = mi.mesh.surface_get_material(s)
		out.append("%s(%s)" % [String(mat.resource_name), mat.get_class()] if mat != null else "null")
	return out


func _path(node: Node) -> String:
	var parts: Array[String] = []
	var n: Node = node
	while n != null and n != get_tree().root:
		parts.push_front(String(n.name))
		n = n.get_parent()
	return "/".join(parts)
