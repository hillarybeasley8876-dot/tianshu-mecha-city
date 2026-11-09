extends RefCounted
## Marker and Crown-rim construction for `world/city.gd` (city-build).
##
## Every node built here is parented exactly where it was before the split — `Markers` and
## `CrownRim` under the City node — because other units address them by name and by group
## (CONTRACTS §7): `PlayerSpawn`, `&"spawn_zone"`, `&"arena"`, `&"landmark"`, `&"anchor_node"`,
## `&"hive_site"`, `&"vista"`, and the boss's `&"crown_rim_segment"` ring (CONTRACTS §6).

var _city: Node3D
var _layout: Dictionary


func _init(city: Node3D, layout: Dictionary) -> void:
	_city = city
	_layout = layout


# ------------------------------------------------------------------ crown rim
## CONTRACTS §6 "Crown rim": the Crown's outer guard ring as separate StaticBody3D segments in
## group `&"crown_rim_segment"` with meta `angle_deg`, so the boss can break them one by one in
## phase 2 (hide + debris + collision off). The ring is NOT in the tiles — `kit/decks.py` leaves
## the outermost rim step's parapet out for exactly this reason.
func crown_rim() -> void:
	var rim: Dictionary = _layout.get("crown_rim", {})
	if rim.is_empty():
		return
	var c: Array = rim["centre"]
	var centre := Vector3(float(c[0]), 0.0, -float(c[1]))   ## Blender plan (x, y) -> Godot (x, -y)
	var radius := float(rim["radius"])
	var height := float(rim["height"])
	var thickness := float(rim["thickness"])
	var count := int(rim["segments"])
	var z0 := float(rim["z"])
	var root := Node3D.new()
	root.name = "CrownRim"
	root.position = Vector3(centre.x, 0.0, centre.z)
	_city.add_child(root)
	var chord := TAU * radius / float(count)
	var mat := _bronze_material()
	for i in count:
		var deg := 360.0 * float(i) / float(count)
		var a := deg_to_rad(deg)
		var body := StaticBody3D.new()
		body.name = "CrownRim_%d" % i
		body.add_to_group(&"crown_rim_segment")
		body.set_meta(&"angle_deg", deg)
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		body.position = Vector3(sin(a) * radius, z0 + height * 0.5, cos(a) * radius)
		body.rotation.y = a
		root.add_child(body)
		var shape := BoxShape3D.new()
		shape.size = Vector3(chord * 0.94, height, thickness)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		var mesh := BoxMesh.new()
		mesh.size = shape.size
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		body.add_child(mi)


func _bronze_material() -> StandardMaterial3D:
	## Named `mc_bronze` so city-art's McMaterials.apply_to() swaps in the real surface.
	var m := StandardMaterial3D.new()
	m.resource_name = "mc_bronze"
	m.albedo_color = Color(0.42, 0.30, 0.18)
	m.metallic = 0.85
	m.roughness = 0.42
	return m


# ------------------------------------------------------------------ markers
func markers() -> void:
	var root := Node3D.new()
	root.name = "Markers"
	_city.add_child(root)

	var start: Dictionary = _layout.get("player_start", {})
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = _city.to_godot(start.get("pos", [0, 0, 0])) + Vector3.UP * 2.0
	spawn.rotation_degrees = Vector3(0.0, float(start.get("yaw_deg", 0.0)), 0.0)
	root.add_child(spawn)

	for zone in _layout.get("spawn_zones", []):
		var area := _zone(zone["id"], Vector3(48.0, 40.0, 48.0), _city.to_godot(zone["pos"]))
		area.set_meta(&"zone_id", StringName(zone["id"]))
		area.set_meta(&"zone_kind", StringName(zone.get("kind", "path")))
		area.add_to_group(&"spawn_zone")
		root.add_child(area)

	for arena in _layout.get("arenas", []):
		var node := _arena(arena)
		node.add_to_group(&"arena")
		root.add_child(node)

	for lm in _layout.get("landmarks", []):
		var mark := Marker3D.new()
		mark.name = "Landmark_" + String(lm["id"])
		mark.position = _city.to_godot(lm["pos"])
		mark.set_meta(&"landmark_id", StringName(lm["id"]))
		mark.set_meta(&"landmark_kind", StringName(lm["kind"]))
		mark.add_to_group(&"landmark")
		root.add_child(mark)

	for a in _layout.get("anchors", []):
		var anchor := Marker3D.new()
		anchor.name = "Anchor_%d" % root.get_child_count()
		anchor.position = _city.to_godot(a["pos"])
		anchor.set_meta(&"normal", _city.to_godot(a["normal"]).normalized())
		if a.has("arena"):
			anchor.set_meta(&"arena", StringName(a["arena"]))
		anchor.add_to_group(&"anchor_node")
		root.add_child(anchor)

	for hive in _layout.get("hives", []):
		var site := Marker3D.new()
		site.name = "Hive_" + String(hive["id"])
		site.position = _city.to_godot(hive["pos"])
		site.set_meta(&"site_id", StringName(hive["id"]))
		site.set_meta(&"arena", StringName(hive["arena"]))
		site.set_meta(&"height", float(hive["height"]))
		site.add_to_group(&"hive_site")
		root.add_child(site)

	for v in _layout.get("vistas", []):
		var cam := Camera3D.new()
		cam.name = String(v["id"])
		cam.position = _city.to_godot(v["pos"])
		cam.fov = float(v.get("fov", 55.0))
		cam.current = false
		cam.set_meta(&"vista_id", StringName(v["id"]))
		cam.set_meta(&"look", _city.to_godot(v["look"]))
		cam.look_at_from_position(cam.position, _city.to_godot(v["look"]), Vector3.UP)
		cam.add_to_group(&"vista")
		root.add_child(cam)


func _zone(id: String, size: Vector3, pos: Vector3) -> Area3D:
	var area := Area3D.new()
	area.name = "Zone_" + id
	area.position = pos + Vector3.UP * size.y * 0.5
	area.collision_layer = Layers.TRIGGER
	area.collision_mask = 0
	area.monitoring = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)
	return area


func _arena(a: Dictionary) -> Area3D:
	## One Area3D per arena, its volume decomposed into convex hulls from the layout polygon and
	## spanning the arena's tier range (plus headroom for a jump).
	var area := Area3D.new()
	area.name = "Arena_" + String(a["id"])
	area.collision_layer = Layers.TRIGGER
	area.collision_mask = 0
	area.monitoring = false
	area.set_meta(&"arena_id", StringName(a["id"]))
	area.set_meta(&"arena_name", String(a.get("name", a["id"])))
	var tiers: Array = a.get("tiers", [0.0])
	var z_lo: float = 0.0
	var z_hi: float = 0.0
	for t in tiers:
		z_lo = min(z_lo, float(t))
		z_hi = max(z_hi, float(t))
	var poly := PackedVector2Array()
	for p in a["polygon"]:
		poly.append(Vector2(float(p[0]), float(p[1])))
	var parts: Array = Geometry2D.decompose_polygon_in_convex(poly)
	var height: float = max(40.0, z_hi - z_lo + 60.0)
	var count := 0
	for part in parts:
		var shape := ConvexPolygonShape3D.new()
		var pts := PackedVector3Array()
		for p2 in part:
			pts.append(Vector3(p2.x, 0.0, -p2.y))
		if pts.size() < 3:
			continue
		shape.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(0.0, z_lo + height * 0.5, 0.0)
		cs.scale = Vector3(1.0, height, 1.0)
		area.add_child(cs)
		count += 1
	if count == 0:
		push_warning("City: arena %s has no usable polygon" % a["id"])
	return area
