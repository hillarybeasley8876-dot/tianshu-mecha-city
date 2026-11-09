extends Node3D
## Escarpment City (city-build). Instances the Blender tiles, places every marker the other
## units read (CONTRACTS 7), brings up the three navigation maps and the flyer sky graph, then
## calls Game.mark_world_built().
##
## Everything positional comes from `city/layout.json`, written by the Blender build from
## `data/map/city_layout.json`. Blender is (X east, Y north, Z up); Godot is (X, Z, -Y).

const LAYOUT := "res://world/city/layout.json"
const TILE_DIR := "res://world/city/tiles"
const SKYLINE := "res://world/city/skyline.glb"
## CONTRACTS §7 "Art integration": city-art owns sky, sun, fog, GI and the mc_* materials.
const ART_ENV := "res://world/art/environment.tscn"
## city-kit's Tripo architecture, fitted over the structures the build left unrendered
## (briefs/city-kit.md step 6). Loaded dynamically, not as an ext_resource in city.tscn: the scene
## belongs to another unit and does not exist yet, and a hard reference would break the whole
## project's script check until it does.
const KIT_PLACER := "res://world/kit/kit_placer.tscn"
## HLOD swap distance (brief 3): detail chunks end here, the tile's merged mass takes over.
const DETAIL_END := 450.0
const HLOD_BEGIN := 430.0
## Landmark chunks (`lm_*`, written by tiles.py) are exempt from the detail cut: the Spire is the
## city's hero landmark and is 561 m from V2, so at DETAIL_END it was being drawn as its own HLOD
## collision mass — a lavender pixel-block trumpet (reviews/city-build-r8.md item 1). Their range
## has to cover the whole 1.4 km map from anywhere on it.
const LANDMARK_END := 2400.0
## Object-name prefix `blender/city/tiles.py` puts on every landmark chunk.
const LANDMARK_PREFIX := "lm_"
const CityNavScript := preload("res://world/city/city_nav.gd")
## Markers, spawn zones, arenas and the breakable Crown rim (CONTRACTS §6/§7).
const CityMarkersScript := preload("res://world/city/city_markers.gd")

var layout: Dictionary = {}
var nav: Node = null
var tiles_root: Node3D = null
var _astar: AStar3D = AStar3D.new()
var _sky_ids: Dictionary = {}    ## waypoint id -> AStar point id

var _static_bodies: int = 0
var _meshes: int = 0
var _tris: int = 0
## Tiles whose `_hlod` proxy stands down because city-kit's far LOD covers them.
var _far_tiles: Dictionary = {}
var _far_hidden: int = 0
## far-LOD rows city-kit has written but not yet gated; their proxies stay up.
var _far_held: int = 0
## Landmark chunks that got the long visibility range instead of the 450 m detail cut.
var _landmark_meshes: int = 0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	layout = _load_layout()
	_far_tiles = _far_lod_tiles(layout)
	tiles_root = Node3D.new()
	tiles_root.name = "Tiles"
	add_child(tiles_root)
	_instance_tiles()
	_instance_skyline()
	# The kit BEFORE the environment: city-art's dressing is placed inside `CityArt._ready()`, and
	# since r10 it settles every rooftop unit and every street piece onto the surface the player sees
	# — which is city-kit's architecture. Built the other way round the kit did not exist yet and
	# 2 800 items were left hanging at the design box's top (city-art r10). Nothing in the placer
	# needs art's globals first: `McMaterials.kit()` calls `ensure_globals()` itself.
	_kit_placer()
	_environment()
	var mk := CityMarkersScript.new(self, layout)
	mk.markers()
	mk.crown_rim()
	nav = CityNavScript.new()
	nav.name = "Navigation"
	add_child(nav)
	var stats: Dictionary = nav.build(layout.get("nav_links", []), Callable(self, "to_godot"))
	_sky_graph()
	print("City: nav sync state %s" % str(_nav_state()))
	print("City: %d tiles, %d meshes, %d tris, %d static bodies, nav %s, built in %d ms"
			% [tiles_root.get_child_count(), _meshes, _tris, _static_bodies, str(stats),
			   Time.get_ticks_msec() - t0])
	Game.mark_world_built()
	_snap_nav_links.call_deferred()


## Once the maps are queryable, pull the NavigationLink3D endpoints onto the baked navmesh and
## report how many now attach at both ends (reviews/city-build-nav.md). Deferred so the world is
## marked built first and the enemies never wait on it.
func _snap_nav_links() -> void:
	var t0 := Time.get_ticks_msec()
	while not (nav as CityNav).is_synced() and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().physics_frame
	var wait := Time.get_ticks_msec() - t0
	if not (nav as CityNav).is_synced():
		push_warning("City: navigation maps did not become queryable within 20 s; links not snapped")
		return
	var attached := (nav as CityNav).snap_links()
	var summary := {}
	for cls in CityNav.CLASSES:
		summary[String(cls)] = attached.get(String(cls), [0, 0])
	print("City: nav usable after %d ms; links enabled %s (%d off, see tools/city/nav_report.sh)"
			% [wait, str(summary), (attached.get("off", []) as Array).size()])


## True when an agent class's navigation map answers path queries with its own geometry.
## Enemies should gate their first query on this rather than assuming navigation is live at load.
func nav_ready(cls: StringName = &"medium") -> bool:
	return nav != null and (nav as CityNav).is_synced(cls)


func _nav_state() -> Dictionary:
	var out := {}
	for cls in CityNav.CLASSES:
		out[String(cls)] = nav_ready(cls)
	return out


## Blender (x, y, z) -> Godot (x, z, -y).
func to_godot(p: Variant) -> Vector3:
	var v: Array = p as Array
	return Vector3(float(v[0]), float(v[2]), -float(v[1]))


# ------------------------------------------------------------------ geometry
func _load_layout() -> Dictionary:
	var f := FileAccess.open(LAYOUT, FileAccess.READ)
	if f == null:
		push_error("City: cannot open %s — run tools/blender.sh run blender/city/build_city.py"
				% LAYOUT)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("City: %s is not a JSON object" % LAYOUT)
		return {}
	return parsed as Dictionary


## `kit_skin.far_tiles` — the 200 m tiles city-kit covers with its own far LOD (their r2 item 2).
## Only rows that carry `"gate": "pass"` reach this list (r8 item 4): until city-kit's far mesh
## passes their hole gate my box proxy stays up rather than leaving a hole in the far band.
func _far_lod_tiles(layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var skin: Dictionary = layout.get("kit_skin", {}) as Dictionary
	_far_held = int(skin.get("far_tiles_held", 0))
	for t in (skin.get("far_tiles", []) as Array):
		out[String(t)] = true
	return out


func _instance_tiles() -> void:
	## ResourceLoader.list_directory, never DirAccess: in an exported .app the tiles are packed
	## into the PCK and the export holds only the remapped imports, so DirAccess sees 0 files and
	## the city loads empty (reviews/city-build-lead.md, packaging).
	var found: PackedStringArray = ResourceLoader.list_directory(TILE_DIR)
	var names: PackedStringArray = []
	for file in found:
		if file.ends_with(".glb"):
			names.append(file)
	names.sort()
	if names.is_empty():
		push_error("City: no tiles under %s — run tools/blender.sh run blender/city/build_city.py"
				% TILE_DIR)
	for file in names:
		var packed := load(TILE_DIR.path_join(file)) as PackedScene
		if packed == null:
			push_error("City: cannot load tile %s" % file)
			continue
		var node := packed.instantiate()
		node.name = file.get_basename()
		tiles_root.add_child(node)
		_fix_up(node, _tile_id(node.name))
	if not _far_tiles.is_empty():
		print("City: %d of %d HLOD proxies stand down (city-kit far LOD covers them: %s)"
				% [_far_hidden, names.size(), ", ".join(_far_tiles.keys())])
	elif _far_held > 0:
		print("City: %d far-LOD rows held (no \"gate\": \"pass\" in kit_assign.json); every HLOD "
				% _far_held + "proxy stays up")
	print("City: %d landmark chunks keep their own geometry to %.0f m"
			% [_landmark_meshes, LANDMARK_END])


## "tile_-1_3" -> "t-1_3": the id `kit_assign.json` and `kit_skin.far_tiles` speak.
func _tile_id(tile_name: String) -> String:
	return "t" + tile_name.trim_prefix("tile_")


## Imported `-colonly` bodies land on the default layer; force them onto Layers.WORLD and stop
## them colliding with anything (static scenery never needs a mask).
func _fix_up(node: Node, tile_id: String = "") -> void:
	if node is StaticBody3D:
		var body := node as StaticBody3D
		# `*_props-colonly` is decoration: it blocks shots and bodies (both masks include PROPS)
		# but stays out of the navmesh bake, which reads Layers.WORLD only.
		body.collision_layer = Layers.PROPS if String(body.name).ends_with("_props") \
				else Layers.WORLD
		body.collision_mask = 0
		_static_bodies += 1
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		_meshes += 1
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				_tris += mi.mesh.surface_get_array_index_len(s) / 3
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# HLOD: the detail chunks end at DETAIL_END and the tile's merged mass takes over —
		# unless city-kit's own far LOD covers this tile, in which case my box proxy would
		# stand in front of their buildings (reviews/city-kit-r1.md item 2).
		if String(mi.name).ends_with("_hlod"):
			if _far_tiles.has(tile_id):
				mi.visible = false
				_far_hidden += 1
			else:
				mi.visibility_range_begin = HLOD_BEGIN
		elif String(mi.name).begins_with(LANDMARK_PREFIX):
			# Landmarks are themselves from every vista; their mass is cut out of the tile HLOD
			# proxy so nothing double-draws them (r8 item 1).
			mi.visibility_range_end = LANDMARK_END
			_landmark_meshes += 1
		else:
			mi.visibility_range_end = DETAIL_END
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for child in node.get_children():
		_fix_up(child, tile_id)


func _instance_skyline() -> void:
	if not ResourceLoader.exists(SKYLINE):
		return
	var packed := load(SKYLINE) as PackedScene
	if packed == null:
		push_warning("City: cannot load the skyline ring")
		return
	var node := packed.instantiate()
	node.name = "Skyline"
	add_child(node)
	_no_shadow(node)


func _no_shadow(node: Node) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		gi.visibility_range_end = 4000.0
	for child in node.get_children():
		_no_shadow(child)


# ------------------------------------------------------------------ environment
## CONTRACTS §7 "Art integration": the city owns no sky, sun or WorldEnvironment of its own —
## `world/art/environment.tscn` (city-art) is instanced as a child and owns all of it.
## `--blockout` swaps in a flat sky + sun so my own geometry checks and captures can run without
## city-art's shaders (they are its files, and it is still iterating on them).
func _environment() -> void:
	if Game.has_flag("blockout"):
		_blockout_environment()
		return
	var scene: PackedScene = load(ART_ENV)
	if scene == null:
		push_error("City: cannot load %s — falling back to the blockout environment" % ART_ENV)
		_blockout_environment()
		return
	var env_node := scene.instantiate()
	env_node.name = "ArtEnvironment"
	add_child(env_node)
	# The scene can load while its scripts do not compile (it happens while city-art is
	# iterating). Without this check the city renders with no sky, no sun and no ambient at all
	# and the failure is silent, so fall back to the blockout instead.
	if _find_world_env(env_node) == null:
		push_error("City: %s provided no WorldEnvironment — its scripts did not load; "
				% ART_ENV + "falling back to the blockout environment")
		env_node.queue_free()
		_blockout_environment()


func _find_world_env(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for child in node.get_children():
		var found := _find_world_env(child)
		if found != null:
			return found
	return null


# ------------------------------------------------------------------ kit skin
## Instance city-kit's placer. The build only drops a structure's render mesh when
## `data/map/kit_assign.json` covers it, and `layout.json` records what was dropped, so the placer
## is loaded exactly when the city was built skinned — otherwise every kit model would be doubled
## by the procedural box behind it.
##
## The node is added as a child named `KitPlacer`; if it has `setup(city, layout)` it is called
## with this node and the parsed layout, so the placer never has to re-read layout.json.
func _kit_placer() -> void:
	var skin: Dictionary = layout.get("kit_skin", {}) as Dictionary
	if not bool(skin.get("active", false)):
		return
	var skinned := (skin.get("buildings", []) as Array).size() \
			+ (skin.get("decks", []) as Array).size() \
			+ (skin.get("decks_full", []) as Array).size() \
			+ (skin.get("viaducts", []) as Array).size()
	if Game.has_flag("blockout") or Game.has_flag("no-kit"):
		push_warning("City: %d structures have no render mesh but the kit placer is off "
				% skinned + "(--blockout/--no-kit); rebuild with build_city.py --blockout "
				+ "to see the procedural city")
		return
	if not ResourceLoader.exists(KIT_PLACER):
		push_warning("City: %d structures were built skinned (%s) but %s does not exist — "
				% [skinned, str(skin.get("source", "?")), KIT_PLACER]
				+ "the city has holes where the kit models should be")
		return
	var scene := load(KIT_PLACER) as PackedScene
	if scene == null:
		push_error("City: cannot load %s; %d skinned structures stay invisible" % [KIT_PLACER,
				skinned])
		return
	var placer := scene.instantiate()
	placer.name = "KitPlacer"
	add_child(placer)
	if placer.has_method("setup"):
		placer.call("setup", self, layout)
	print("City: kit placer instanced for %d skinned structures" % skinned)


func _blockout_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.169, 0.298, 0.494)
	sky_mat.sky_horizon_color = Color(0.949, 0.722, 0.502)
	sky_mat.ground_horizon_color = Color(0.549, 0.518, 0.478)
	sky_mat.sun_angle_max = 12.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.fog_enabled = true
	env.fog_light_color = Color(0.910, 0.725, 0.541)
	env.fog_density = 0.0004
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.6
	var we := WorldEnvironment.new()
	we.name = "BlockoutEnvironment"
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-72.0, 45.0, 0.0)
	sun.light_color = Color(1.0, 0.827, 0.627)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 500.0
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.15
	sun.directional_shadow_split_3 = 0.40
	sun.directional_shadow_blend_splits = false
	add_child(sun)


# ------------------------------------------------------------------ flyers
func _sky_graph() -> void:
	## AStar3D over the layout sky graph (MAP 3 r3). Absent in the current layout, so
	## sky_path() falls back to a straight pair.
	for wp in layout.get("sky_waypoints", []):
		var id: int = _astar.get_available_point_id()
		_astar.add_point(id, to_godot(wp["pos"]))
		_sky_ids[String(wp["id"])] = id
		var mark := Marker3D.new()
		mark.name = "Sky_" + String(wp["id"])
		mark.position = to_godot(wp["pos"])
		mark.add_to_group(&"sky_waypoint")
		add_child(mark)
	for edge in layout.get("sky_edges", []):
		var a: String = String(edge[0])
		var b: String = String(edge[1])
		if not (_sky_ids.has(a) and _sky_ids.has(b)):
			push_warning("City: sky edge %s-%s has no waypoint" % [a, b])
			continue
		# are_points_connected is DIRECT adjacency (not reachability), which is what a duplicate
		# edge check needs; sky_path() asks get_point_path for reachability instead.
		if not _astar.are_points_connected(_sky_ids[a], _sky_ids[b]):
			_astar.connect_points(_sky_ids[a], _sky_ids[b])
	print("City: sky graph %d waypoints, %d edges"
			% [_astar.get_point_count(), layout.get("sky_edges", []).size()])


## Flyer route (CONTRACTS 7): A* over the sky waypoints, or [from, to] without a sky graph.
func sky_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if _astar.get_point_count() < 2:
		return PackedVector3Array([from, to])
	var a: int = _astar.get_closest_point(from)
	var b: int = _astar.get_closest_point(to)
	var route := _astar.get_point_path(a, b) if a != b else PackedVector3Array()
	if route.is_empty():
		return PackedVector3Array([from, to])
	var out := PackedVector3Array([from])
	out.append_array(route)
	out.append(to)
	return out


## Navigation map RID for an agent class (CONTRACTS 7).
func nav_map(cls: StringName) -> RID:
	if nav == null:
		return RID()
	return (nav as CityNav).nav_map(cls)
