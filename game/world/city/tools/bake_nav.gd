extends Node
## Offline navmesh bake (city-build). Run with `tools/city/bake_nav.sh`.
##
## Loads the real city scene (so the bake sees the real collision, never the render mesh), parses
## STATIC_COLLIDERS on Layers.WORLD once per agent class, then bakes one NavigationMesh per
## chunk with a `filter_baking_aabb` and writes them as resources plus an index.
##
## Cell sizes are godot-tech 3.1's (small 0.5, medium 1.0, large 1.5 m — each a whole divisor of
## its agent radius). Each class is baked as one region: adjacency between many regions, not the
## polygon count, is what makes a custom map expensive to build.
##
##   tools/city/bake_nav.sh [--class=small|medium|large]

const CITY := "res://world/city.tscn"
const OUT_DIR := "res://world/city/nav"
const INDEX := "res://world/city/nav/index.json"
const CHUNKS := 1              ## one region per class: adjacency between regions, not polygon count, is what stalls the map sync
const CHUNK_BORDER := 0.0   ## exact abutment: overlapping chunks duplicate polygons and the map never syncs
const Z_LO := -70.0
const Z_HI := 420.0
const MIN_ISLAND_TRIS := 3  ## drop connected components smaller than this (unreachable crumbs)
const CLASSES: Array[StringName] = [&"small", &"medium", &"large"]
const PARAMS := {
	## `z_hi` caps the bake height. Rippers (small) fight on L0-L2, so the small map stops at +96
	## and skips the sky decks. Raising it is not free and was measured (lead r3): at +240 the small
	## ground island drops from 16.8 % to 13.9 % of the map and its extent from z 647 to z 339, and
	## socket->arena reachability FALLS from 81 % to 75 %. At +200 medium barely moves (17.8 % ->
	## 18.1 %). A taller rasterisation box costs more ground than the extra decks are worth, so the
	## cap stays; A6 (+144) and the Crown (+224) are consequently off the small map by design.
	&"small": {"radius": 1.5, "height": 6.0, "climb": 1.0, "slope": 40.0,
		"cell": 0.5, "cell_h": 0.25, "z_hi": 96.0, "part": 1},
	&"medium": {"radius": 4.0, "height": 16.0, "climb": 2.0, "slope": 40.0,
		"cell": 1.0, "cell_h": 0.5, "z_hi": Z_HI, "part": 1},
	&"large": {"radius": 9.0, "height": 22.0, "climb": 3.0, "slope": 35.0,
		"cell": 1.5, "cell_h": 0.75, "z_hi": Z_HI, "part": 0},
}

var _city: Node3D = null
var _only: String = ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--class="):
			_only = arg.trim_prefix("--class=")
	var packed := load(CITY) as PackedScene
	if packed == null:
		push_error("bake_nav: cannot load " + CITY)
		_finish(1)
		return
	_city = packed.instantiate() as Node3D
	add_child(_city)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	call_deferred("_bake")


func _bake() -> void:
	var half: float = float(_city.get("layout").get("bounds", {}).get("half", 700.0))
	var size: float = half * 2.0 / float(CHUNKS)
	var index: Dictionary = _load_index()
	var failed := 0
	for cls in CLASSES:
		if _only != "" and String(cls) != _only:
			continue
		var p: Dictionary = PARAMS[cls]
		var nm := NavigationMesh.new()
		nm.cell_size = float(p["cell"])
		nm.cell_height = float(p["cell_h"])
		nm.agent_radius = float(p["radius"])
		nm.agent_height = float(p["height"])
		nm.agent_max_climb = float(p["climb"])
		nm.agent_max_slope = float(p["slope"])
		# `part` 0 = watershed, 1 = monotone. godot-tech 3.2 measured LAYERS as ~330x slower at
		# this scale; monotone is both faster and ~1/3 fewer polygons, which is what buys the
		# small and medium maps a navigation sync measured in seconds rather than minutes.
		nm.sample_partition_type = int(p.get("part", 0))
		nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		nm.geometry_collision_mask = Layers.WORLD
		nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
		var t0 := Time.get_ticks_msec()
		var source := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(nm, source, _city)
		var rows: Array = []
		var total := 0
		for cy in CHUNKS:
			for cx in CHUNKS:
				var chunk := nm.duplicate() as NavigationMesh
				var z_hi: float = float(p["z_hi"])
				chunk.filter_baking_aabb = AABB(
						Vector3(-half + size * cx - CHUNK_BORDER, Z_LO,
								-half + size * cy - CHUNK_BORDER),
						Vector3(size + CHUNK_BORDER * 2.0, z_hi - Z_LO,
								size + CHUNK_BORDER * 2.0))
				NavigationServer3D.bake_from_source_geometry_data(chunk, source)
				var prune := _prune(chunk)
				var polys := chunk.get_polygon_count()
				if polys == 0:
					continue
				var path := "%s/nav_%s_%d_%d.res" % [OUT_DIR, cls, cx, cy]
				if ResourceSaver.save(chunk, path) != OK:
					push_error("bake_nav: cannot save " + path)
					failed += 1
					continue
				rows.append({"cx": cx, "cy": cy, "polys": polys, "path": path,
						"islands": prune["islands"], "dropped": prune["dropped"],
						"biggest_pct": prune["biggest_pct"],
					"biggest_aabb": prune["aabb"], "over_1pct": prune["over_1pct"]})
				total += polys
		index[String(cls)] = rows
		var islands := 0
		var dropped := 0
		var biggest := 0.0
		for row in rows:
			islands += int(row["islands"])
			dropped += int(row["dropped"])
			biggest = maxf(biggest, float(row["biggest_pct"]))
		print("BAKE %s: %d chunks, %d polygons, %d islands (%d over 1 %%, biggest %.1f %% at %s), %d crumbs dropped, %.1f s"
				% [cls, rows.size(), total, islands, int(rows[0].get("over_1pct", 0)) if not rows.is_empty() else 0,
				   biggest, String(rows[0].get("biggest_aabb", "")) if not rows.is_empty() else "",
				   dropped, (Time.get_ticks_msec() - t0) / 1000.0])
	_save_index(index)
	_finish(1 if failed > 0 else 0)


func _prune(mesh: NavigationMesh) -> Dictionary:
	## Drop connected components of fewer than MIN_ISLAND_TRIS polygons (ledge crumbs nothing can
	## stand on) and report the island count, so fragmentation is a number we can watch.
	## Returns {"islands": int, "dropped": int}.
	var n := mesh.get_polygon_count()
	if n == 0:
		return {"islands": 0, "dropped": 0}
	var parent: Dictionary = {}
	for i in n:
		parent[i] = i
	var first_at_vertex: Dictionary = {}
	for i in n:
		var root := _find(parent, i)
		for v in mesh.get_polygon(i):
			if first_at_vertex.has(v):
				var other := _find(parent, first_at_vertex[v])
				if other != root:
					parent[root] = other
					root = other
			else:
				first_at_vertex[v] = i
	var size: Dictionary = {}
	for i in n:
		var r := _find(parent, i)
		size[r] = int(size.get(r, 0)) + 1
	var doomed: Array[int] = []
	var kept_islands := 0
	var biggest := 0
	var biggest_root := -1
	var over_1pct := 0
	for r in size:
		var c := int(size[r])
		if c < MIN_ISLAND_TRIS:
			continue
		kept_islands += 1
		if c * 100 >= n:
			over_1pct += 1
		if c > biggest:
			biggest = c
			biggest_root = r
	for i in n:
		if int(size[_find(parent, i)]) < MIN_ISLAND_TRIS:
			doomed.append(i)
	var aabb := _island_aabb(mesh, parent, biggest_root)
	if doomed.is_empty():
		return {"islands": kept_islands, "dropped": 0, "aabb": aabb, "over_1pct": over_1pct,
				"biggest_pct": 100.0 * float(biggest) / float(n)}
	# NavigationMesh has no remove_polygon in 4.7.2, so the survivors are rebuilt into a cleared
	# polygon list with their vertices compacted on the way.
	var drop := {}
	for i in doomed:
		drop[i] = true
	var verts := mesh.get_vertices()
	var kept: Array = []
	var remap: Dictionary = {}
	var new_verts := PackedVector3Array()
	for i in n:
		if drop.has(i):
			continue
		var out := PackedInt32Array()
		for v in mesh.get_polygon(i):
			if not remap.has(v):
				remap[v] = new_verts.size()
				new_verts.append(verts[v])
			out.append(remap[v])
		kept.append(out)
	mesh.clear_polygons()
	mesh.vertices = new_verts
	for poly in kept:
		mesh.add_polygon(poly)
	return {"islands": kept_islands, "dropped": doomed.size(), "aabb": aabb,
			"over_1pct": over_1pct, "biggest_pct": 100.0 * float(biggest) / float(n)}


## Extent of the biggest connected component, as "minx,miny,minz,maxx,maxy,maxz" — the fastest way
## to see whether the main walkable surface is the ground crust or one lucky rooftop.
func _island_aabb(mesh: NavigationMesh, parent: Dictionary, root: int) -> String:
	if root < 0:
		return ""
	var verts := mesh.get_vertices()
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in mesh.get_polygon_count():
		if _find(parent, i) != root:
			continue
		for v in mesh.get_polygon(i):
			lo = lo.min(verts[v])
			hi = hi.max(verts[v])
	return "%.0f,%.0f,%.0f .. %.0f,%.0f,%.0f" % [lo.x, lo.y, lo.z, hi.x, hi.y, hi.z]


func _find(parent: Dictionary, a: int) -> int:
	while int(parent[a]) != a:
		parent[a] = parent[int(parent[a])]
		a = int(parent[a])
	return a


func _load_index() -> Dictionary:
	if not FileAccess.file_exists(INDEX):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


func _save_index(index: Dictionary) -> void:
	var f := FileAccess.open(INDEX, FileAccess.WRITE)
	if f == null:
		push_error("bake_nav: cannot write " + INDEX)
		return
	f.store_string(JSON.stringify(index, "\t"))
	print("BAKE index -> %s (%d classes)" % [INDEX, index.size()])


func _finish(code: int) -> void:
	if _city != null:
		_city.queue_free()
	print("BAKE %s" % ("PASS" if code == 0 else "FAIL"))
	get_tree().quit(code)
