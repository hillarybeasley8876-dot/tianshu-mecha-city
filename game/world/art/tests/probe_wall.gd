extends Node
## Diagnostic: what is the big flat mass behind the city? (city-art, review r3 §3)
##   tools/godot.sh test res://world/art/tests/probe_wall.gd
## Fires a grid of rays from a vista camera and prints, per hit, the node path, the mesh surface index
## and the material NAME, so a "flat orange band" can be attributed instead of guessed at.

const CITY_SCENE := "res://world/city.tscn"
const EYE := Vector3(-458.8, 120.0, 556.0)
const LOOK := Vector3(-380.1, 64.3, 167.8)
const FOV := 50.0
const COLS := 9
const ROWS := 5


func _ready() -> void:
	add_child((load(CITY_SCENE) as PackedScene).instantiate())
	await get_tree().physics_frame
	await get_tree().physics_frame
	var state := get_viewport().world_3d.direct_space_state
	var fwd := (LOOK - EYE).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd).normalized()
	var tan := tan(deg_to_rad(FOV) * 0.5)
	for r in range(ROWS):
		var line := ""
		for c in range(COLS):
			var sx := (float(c) / float(COLS - 1) * 2.0 - 1.0) * tan * (16.0 / 9.0)
			var sy := (1.0 - float(r) / float(ROWS - 1) * 2.0) * tan
			var dir := (fwd + right * sx + up * sy).normalized()
			var hit := state.intersect_ray(PhysicsRayQueryParameters3D.create(EYE, EYE + dir * 4000.0))
			line += _label(hit) + "  "
		print("row %d: %s" % [r, line])
	get_tree().quit(0)


func _label(hit: Dictionary) -> String:
	if hit.is_empty():
		return "sky"
	var node: Node = hit["collider"]
	var mesh_name := "-"
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			mesh_name = mi.mesh.surface_get_material(0).resource_name
			if mesh_name.is_empty():
				mesh_name = "?"
	var d := EYE.distance_to(hit["position"] as Vector3)
	return "%s/%s@%dm" % [node.name, mesh_name, int(d)]
