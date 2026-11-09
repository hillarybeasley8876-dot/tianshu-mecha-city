extends Node
## city-build tests: `tools/godot.sh test res://world/city/tests/test_city.gd`
##
## Verifies the contract the other units rely on (CONTRACTS 7): the world loads and marks itself
## built, every marker group is present and populated, `to_godot` round-trips, the navigation maps
## exist and the nav links are placed, and the flyer sky graph answers `sky_path`.

const CityNavScript := preload("res://world/city/city_nav.gd")

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	var city := (load("res://world/city.tscn") as PackedScene).instantiate() as Node3D
	add_child(city)
	await get_tree().physics_frame

	_layout(city)
	_markers(city)
	_navigation(city)
	_sky(city)
	_geometry(city)

	print("TEST %s (%d checks, %d failed)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("TEST FAIL ", what)


func _layout(city: Node3D) -> void:
	var lay: Dictionary = city.get("layout")
	_ok(not lay.is_empty(), "layout.json loaded")
	_ok(Game.world_built(), "Game.mark_world_built() was called")
	_ok(lay.get("bounds", {}).get("half", 0.0) == 700.0, "bounds.half is 700")
	# Blender (x, y, z) -> Godot (x, z, -y)
	_ok(city.to_godot([1.0, 2.0, 3.0]).is_equal_approx(Vector3(1.0, 3.0, -2.0)),
			"to_godot maps (x,y,z) -> (x,z,-y)")
	var start: Dictionary = lay.get("player_start", {})
	var spawn := city.find_child("PlayerSpawn", true, false) as Marker3D
	_ok(spawn != null, "PlayerSpawn marker exists")
	if spawn != null:
		_ok(spawn.position.distance_to(city.to_godot(start["pos"])) < 4.0,
				"PlayerSpawn sits on the layout start")
	# reviews/city-build-r8.md item 3: every skyline-ring tower is exported as a slot city-kit can
	# place a far model on. Item 4's gate is enforced in the Blender build; what the Godot side can
	# see is that the held count is reported (see _geometry for the proxy count).
	var ring: Array = lay.get("skyline_ring", [])
	_ok(ring.size() > 50, "%d skyline-ring slots exported" % ring.size())
	_ok((ring.is_empty() or (ring[0] as Dictionary).has("index")),
			"a ring slot carries its index into city_layout.json[\"skyline\"]")
	var skin: Dictionary = lay.get("kit_skin", {})
	_ok(skin.has("far_tiles_held"), "kit_skin reports the held far-LOD rows")


func _markers(city: Node3D) -> void:
	var groups := {
		&"spawn_zone": 1, &"arena": 7, &"landmark": 8, &"anchor_node": 80,
		&"hive_site": 3, &"vista": 8,
	}
	for g in groups:
		var n := get_tree().get_nodes_in_group(g).size()
		_ok(n >= int(groups[g]), "group %s has %d nodes (want >= %d)" % [g, n, groups[g]])
	for arena in get_tree().get_nodes_in_group(&"arena"):
		_ok((arena as Node).has_meta(&"arena_id"), "arena node carries arena_id")
	for zone in get_tree().get_nodes_in_group(&"spawn_zone"):
		_ok((zone as Node).has_meta(&"zone_id"), "spawn zone carries zone_id")
	for anchor in get_tree().get_nodes_in_group(&"anchor_node"):
		var n := anchor as Node3D
		_ok(n.has_meta(&"normal"), "anchor node carries a normal")
		_ok((n.get_meta(&"normal") as Vector3).length() > 0.5, "anchor normal is a direction")
		break


func _navigation(city: Node3D) -> void:
	var nav := city.get("nav") as CityNav
	_ok(nav != null, "CityNav is present")
	if nav == null:
		return
	for cls in CityNav.CLASSES:
		var map: RID = city.nav_map(cls)
		_ok(map.is_valid(), "nav_map(%s) returns a live RID" % cls)
		_ok(NavigationServer3D.map_is_active(map), "nav map %s is active" % cls)
		_ok((nav.get("regions").get(cls, []) as Array).size() > 0,
				"nav class %s has a baked region" % cls)
		_ok(nav.sample_points(cls, 1).size() == 1, "nav class %s has polygons" % cls)
	var links: Array = city.get("layout").get("nav_links", [])
	_ok(links.size() > 40, "layout declares %d nav links" % links.size())
	var made := 0
	for child in nav.get_children():
		if child is NavigationLink3D:
			made += 1
	_ok(made == links.size() * CityNav.CLASSES.size(),
			"%d NavigationLink3D nodes for %d links x %d classes" % [made, links.size(),
					CityNav.CLASSES.size()])


func _sky(city: Node3D) -> void:
	var lay: Dictionary = city.get("layout")
	var want := (lay.get("sky_waypoints", []) as Array).size()
	var marks := get_tree().get_nodes_in_group(&"sky_waypoint").size()
	_ok(marks == want, "%d sky_waypoint markers for %d layout waypoints" % [marks, want])
	var a := Vector3(-500.0, 150.0, 500.0)
	var b := Vector3(400.0, 150.0, -300.0)
	var path: PackedVector3Array = city.sky_path(a, b)
	_ok(path.size() >= 2, "sky_path returns at least the endpoints")
	if path.size() >= 2:
		_ok(path[0].is_equal_approx(a) and path[path.size() - 1].is_equal_approx(b),
				"sky_path starts at `from` and ends at `to`")
	if want > 1:
		_ok(path.size() > 2, "sky_path routes through the %d-node sky graph" % want)


func _geometry(city: Node3D) -> void:
	var tiles := city.get_node_or_null("Tiles")
	_ok(tiles != null, "Tiles node exists")
	if tiles == null:
		return
	_ok(tiles.get_child_count() > 40, "%d tiles instanced" % tiles.get_child_count())
	var tally := {"bodies": 0, "meshes": 0, "hlod": 0, "props": 0, "hlod_hidden": 0,
			"landmark": 0, "landmark_short": 0}
	_walk(tiles, tally)
	_ok(int(tally["bodies"]) > 40, "%d static bodies" % int(tally["bodies"]))
	_ok(int(tally["meshes"]) > 500, "%d render meshes" % int(tally["meshes"]))
	_ok(int(tally["hlod"]) > 40, "%d HLOD proxies" % int(tally["hlod"]))
	_ok(int(tally["props"]) > 0, "%d decorative (PROPS) bodies" % int(tally["props"]))
	# r8 item 1: the landmarks are exempt from the 450 m detail cut — V2 is 561 m from the Spire.
	_ok(int(tally["landmark"]) > 50, "%d landmark chunks" % int(tally["landmark"]))
	_ok(int(tally["landmark_short"]) == 0,
			"%d landmark chunks still end at the detail cut" % int(tally["landmark_short"]))
	# r8 item 4: a proxy only stands down for a far-LOD row that passed city-kit's hole gate.
	var far: Array = (city.get("layout") as Dictionary).get("kit_skin", {}).get("far_tiles", [])
	_ok(int(tally["hlod_hidden"]) == far.size(),
			"%d hidden proxies for %d gated far-LOD rows" % [int(tally["hlod_hidden"]),
			far.size()])


func _walk(node: Node, tally: Dictionary) -> void:
	if node is StaticBody3D:
		tally["bodies"] = int(tally["bodies"]) + 1
		if (node as StaticBody3D).collision_layer == Layers.PROPS:
			tally["props"] = int(tally["props"]) + 1
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		tally["meshes"] = int(tally["meshes"]) + 1
		var n := String(mi.name)
		if n.ends_with("_hlod"):
			tally["hlod"] = int(tally["hlod"]) + 1
			if not mi.visible:
				tally["hlod_hidden"] = int(tally["hlod_hidden"]) + 1
		elif n.begins_with("lm_"):
			tally["landmark"] = int(tally["landmark"]) + 1
			if mi.visibility_range_end < 2000.0:
				tally["landmark_short"] = int(tally["landmark_short"]) + 1
	for child in node.get_children():
		_walk(child, tally)
