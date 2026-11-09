extends Node
## Arena floor probe (city-build). Run with `tools/city/nav_probe.sh`.
##
## For every arena it answers the question the nav report cannot: WHY is a socket or an arena
## centre off the navmesh? For each probe point it casts down and prints the surface actually
## there (collider name, height, normal) and how much navmesh each class has within 30 m. A point
## whose floor exists but has no navmesh is an agent-box problem (cover density, headroom); a
## point with no floor at all is a geometry hole.

const PROBE_UP := 60.0
const PROBE_DOWN := 120.0
const NEAR := 30.0
const CLASSES: Array[StringName] = [&"small", &"medium", &"large"]

var city: Node3D = null
var nav: CityNav = null
var layout: Dictionary = {}
var space: PhysicsDirectSpaceState3D = null


func _ready() -> void:
	city = (load("res://world/city.tscn") as PackedScene).instantiate() as Node3D
	add_child(city)
	for i in 30:
		await get_tree().physics_frame
	nav = city.get("nav")
	layout = city.get("layout")
	space = get_viewport().world_3d.direct_space_state
	var t0 := Time.get_ticks_msec()
	while not nav.is_synced() and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().physics_frame
	if not nav.is_synced():
		push_error("nav_probe: maps never became queryable")
		get_tree().quit(1)
		return
	for a in layout.get("arenas", []):
		_arena(a)
	get_tree().quit(0)


func _arena(a: Dictionary) -> void:
	var poly: Array = a.get("polygon", [])
	if poly.is_empty():
		return
	var c2 := Vector2.ZERO
	for p in poly:
		c2 += Vector2(float(p[0]), float(p[1]))
	c2 /= float(poly.size())
	print("PROBE arena %s centroid (%.0f, %.0f), %d sockets, %d cover"
			% [String(a.get("id", "?")), c2.x, c2.y,
			   (a.get("sockets", []) as Array).size(), (a.get("cover", []) as Array).size()])
	for s in a.get("sockets", []):
		_point(String(s.get("id", "?")), city.to_godot(s["pos"]))


func _point(id: String, at: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(
			at + Vector3.UP * PROBE_UP, at + Vector3.DOWN * PROBE_DOWN, Layers.WORLD)
	var hit := space.intersect_ray(q)
	var floor_txt := "NO FLOOR"
	if not hit.is_empty():
		var p: Vector3 = hit["position"]
		var n: Vector3 = hit["normal"]
		floor_txt = "floor %+.1f m (%s) n=(%.2f,%.2f,%.2f) %s" % [p.y - at.y,
				String((hit["collider"] as Node).name), n.x, n.y, n.z,
				String((hit["collider"] as Node).get_parent().name)]
	var nav_txt := ""
	for cls in CLASSES:
		var d := NavigationServer3D.map_get_closest_point(nav.nav_map(cls), at).distance_to(at)
		nav_txt += " %s %.0f m" % [cls, d]
	print("PROBE   %-10s at (%.0f, %.0f, %.0f): %s | off-mesh%s"
			% [id, at.x, at.y, at.z, floor_txt, nav_txt])
