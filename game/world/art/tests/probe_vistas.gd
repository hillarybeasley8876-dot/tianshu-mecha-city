extends Node
## Diagnostic: is an adopted vista camera looking at anything? (city-art, r4)
##   tools/godot.sh test res://world/art/tests/probe_vistas.gd
## For every camera in `tests/cameras.json` it fires a small ray grid over the frame and reports the
## median hit distance, how much of the frame is sky, and the nearest hit — the three numbers that
## decide whether a frame is a vista or a photograph of a wall. The cameras are lead-owned
## (data/vistas.json), so this only reports; it never moves them.

const CITY_SCENE := "res://world/city.tscn"
const CAMS := "res://world/art/tests/cameras.json"
const COLS := 11
const ROWS := 7
## A frame whose nearest hit is under this is inside or against geometry, not a vista.
const TOO_CLOSE_M := 60.0


func _ready() -> void:
	add_child((load(CITY_SCENE) as PackedScene).instantiate())
	await get_tree().physics_frame
	await get_tree().physics_frame
	var state := get_viewport().world_3d.direct_space_state
	var cams: Array = _cams()
	var eyes: Dictionary = {}
	# `--near=<m>` widens the AABB list; the default is the "what is touching the lens" radius.
	var flag := Game.flag("near")
	if flag.is_valid_float():
		_near_m = float(flag)
	for cam in cams:
		_probe(state, cam)
		eyes[String(cam.get("name", "?"))] = _vec(cam.get("pos", [0, 0, 0]))
	# Rays only reach COLLIDING geometry, and the things that fill a frame by accident (cloth banners,
	# HLOD proxies, backdrop cards, the ring) have no collider at all — so list the drawn AABBs too.
	_near(get_tree().root, eyes)
	get_tree().quit(0)


## Every drawn node whose world AABB comes within `NEAR_M` of a vista camera.
var _near_m := 45.0


func _near(node: Node, eyes: Dictionary) -> void:
	if node is VisualInstance3D:
		var vi := node as VisualInstance3D
		var box := vi.global_transform * vi.get_aabb()
		for name in eyes:
			var d := _box_distance(box, eyes[name] as Vector3)
			if d < _near_m:
				print("NEAR %s d=%.0f %s aabb=(%.0f,%.0f,%.0f) at=(%.0f,%.0f,%.0f)"
					% [name, d, String(node.name), box.size.x, box.size.y, box.size.z,
						box.get_center().x, box.get_center().y, box.get_center().z])
	for child in node.get_children():
		_near(child, eyes)


static func _box_distance(box: AABB, p: Vector3) -> float:
	return Vector3(maxf(maxf(box.position.x - p.x, p.x - box.end.x), 0.0),
		maxf(maxf(box.position.y - p.y, p.y - box.end.y), 0.0),
		maxf(maxf(box.position.z - p.z, p.z - box.end.z), 0.0)).length()


func _probe(state: PhysicsDirectSpaceState3D, cam: Dictionary) -> void:
	var eye := _vec(cam.get("pos", [0, 0, 0]))
	var look := _vec(cam.get("look", [0, 0, 0]))
	var fov := float(cam.get("fov", 50.0))
	var fwd := (look - eye).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd).normalized()
	var tan := tan(deg_to_rad(fov) * 0.5)
	var hits: Array[float] = []
	var sky := 0
	var nearest := INF
	var nearest_what := "sky"
	for r in range(ROWS):
		for c in range(COLS):
			var sx := (float(c) / float(COLS - 1) * 2.0 - 1.0) * tan * (16.0 / 9.0)
			var sy := (1.0 - float(r) / float(ROWS - 1) * 2.0) * tan
			var dir := (fwd + right * sx + up * sy).normalized()
			var hit := state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + dir * 4000.0))
			if hit.is_empty():
				sky += 1
				continue
			var d := eye.distance_to(hit["position"] as Vector3)
			hits.append(d)
			if d < nearest:
				nearest = d
				nearest_what = _what(hit)
	hits.sort()
	var total := COLS * ROWS
	var median := hits[hits.size() / 2] if not hits.is_empty() else INF
	print("%s sky=%.2f median=%dm nearest=%dm (%s) -> %s" % [cam.get("name", "?"),
		float(sky) / float(total), int(median), int(nearest), nearest_what,
		"WALL IN FRAME" if nearest < TOO_CLOSE_M else "open"])


## The collider's name is the honest attribution: the material name is often just the role.
func _what(hit: Dictionary) -> String:
	var node: Node = hit["collider"]
	var owner_name := "-"
	var n: Node = node
	while n != null:
		if n is MeshInstance3D:
			owner_name = String(n.name)
			break
		n = n.get_parent()
	return "%s<-%s" % [node.name, owner_name]


func _cams() -> Array:
	if not FileAccess.file_exists(CAMS):
		push_error("probe_vistas: no %s" % CAMS)
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMS))
	return parsed as Array if parsed is Array else []


func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
