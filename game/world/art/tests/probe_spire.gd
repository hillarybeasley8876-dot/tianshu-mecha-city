extends Node
## Diagnostic: where did the Spire's light language actually land (city-art)?
##   tools/godot.sh test res://world/art/tests/probe_spire.gd
##
## The tether, the shaft strips and the ring edges are placed from the layout, not from geometry, so
## this reports each one's world position and bounding box and says whether the line of sight from the
## V1 pier camera to the tether is clear — "it is not in the shot" and "it is behind a building" are
## different bugs.

const CITY_SCENE := "res://world/city.tscn"
const PIER_EYE := Vector3(-575.0, 14.0, 640.0)

var _city: Node3D


func _ready() -> void:
	_city = (load(CITY_SCENE) as PackedScene).instantiate() as Node3D
	add_child(_city)
	for i in 4:
		await get_tree().physics_frame
	var found: Array[GeometryInstance3D] = []
	_collect(_city, found)
	var state := get_viewport().world_3d.direct_space_state
	for n in found:
		var key := String(n.name)
		if not (key.begins_with("tether") or key.begins_with("Spire")):
			continue
		var box := n.global_transform * (n.get_aabb() if n is MeshInstance3D else AABB())
		if n is MultiMeshInstance3D:
			box = n.global_transform * (n as MultiMeshInstance3D).get_aabb()
		print("SPIRE %-16s pos=%s visible=%s box=%s size=%s" %
			[key, n.global_position, n.visible, box.position, box.size])
		if key.begins_with("tether"):
			_sight(state, n.global_position + Vector3.UP * 200.0)
	_spire_geometry(found)
	get_tree().quit(0)


func _sight(state: PhysicsDirectSpaceState3D, target: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(PIER_EYE, target, Layers.WORLD)
	q.collide_with_areas = false
	var hit := state.intersect_ray(q)
	print("SPIRE tether sight from the pier camera: %s" %
		("BLOCKED at %.0f m by %s" % [PIER_EYE.distance_to(hit["position"] as Vector3),
			str(hit.get("collider"))] if not hit.is_empty() else "clear"))


## How tall is the built Spire, and how wide at the collar? The strips follow whatever this reports.
func _spire_geometry(meshes: Array[GeometryInstance3D]) -> void:
	var top := 0.0
	var widest := 0.0
	var n := 0
	for m in meshes:
		if not (m is MeshInstance3D):
			continue
		var box := m.global_transform * (m as MeshInstance3D).get_aabb()
		var c := Vector2(box.get_center().x, box.get_center().z)
		if c.distance_to(Vector2(0.0, -120.0)) > 120.0:
			continue
		n += 1
		top = maxf(top, box.position.y + box.size.y)
		widest = maxf(widest, maxf(box.size.x, box.size.z) * 0.5)
	print("SPIRE built: %d meshes within 120 m, top=%.0f m, widest half-extent=%.0f m" % [n, top, widest])


func _collect(node: Node, out: Array[GeometryInstance3D]) -> void:
	if node is GeometryInstance3D:
		out.append(node as GeometryInstance3D)
	for c in node.get_children():
		_collect(c, out)
