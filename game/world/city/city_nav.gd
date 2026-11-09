class_name CityNav
extends Node
## Navigation for the city (city-build). One navigation map per agent class (CONTRACTS 7), each
## holding one NavigationRegion3D per baked chunk, plus a NavigationLink3D for every non-walk
## level-graph edge.
##
## The meshes are baked OFFLINE by `tools/city/bake_nav.sh`; a missing bake is a warning, not a
## crash, so the world still loads while the city is moving.
##
## Two 4.7.2 settings matter at this scale (reviews/city-build-nav.md):
##   * `map_set_use_edge_connections(map, false)` — the builder's edge-connection margin pass
##     tests every PAIR of free edges. With one region per map that joins nothing but was 89 % of
##     the build time (126/80/26 ms -> 13/10/6 ms). Paths are identical.
##   * async iterations stay ON; turning them off is a 250 ms main-thread hitch at load.

const CLASSES: Array[StringName] = [&"small", &"medium", &"large"]
## godot-tech 3.1: radii must be whole multiples of the cell size (1.5/0.5, 4/1, 9/1.5).
const PARAMS := {
	&"small": {"radius": 1.5, "height": 6.0, "climb": 1.0, "slope": 40.0,
		"cell": 0.5, "cell_h": 0.25, "link_r": 2.25},
	&"medium": {"radius": 4.0, "height": 16.0, "climb": 2.0, "slope": 40.0,
		"cell": 1.0, "cell_h": 0.5, "link_r": 5.0},
	&"large": {"radius": 9.0, "height": 22.0, "climb": 3.0, "slope": 35.0,
		"cell": 1.5, "cell_h": 0.75, "link_r": 11.0},
}
const NAV_DIR := "res://world/city/nav/"
const SYNC_TOLERANCE := 0.5   ## a baked polygon centre must come back this close from the map
const SNAP_GATE := 4.0        ## a link end further than this from the navmesh stays off
## Lead r3: a link is only ENABLED for a class when BOTH of its ends snap within this distance of
## that class's navmesh. An enabled link with an end off-mesh is worse than no link: godot-tech 3.3
## hangs the end on whatever polygon happens to be nearest, so path queries start on a polygon that
## is not in the reachable set and Godot logs `_query_task_build_path_corridor`.

var maps: Dictionary = {}          ## class -> RID
var regions: Dictionary = {}       ## class -> Array[NavigationRegion3D]
var links_attached: int = 0        ## links whose BOTH ends sit on a navmesh polygon
var links_snapped: bool = false

var _links: Array[NavigationLink3D] = []


func build(links: Array, to_godot: Callable) -> Dictionary:
	## Create the three maps, load every baked chunk into its own region and place the nav links.
	## `links` are the marker dicts from layout.json; `to_godot` converts Blender XYZ.
	var index := _load_index()
	var stats := {}
	for cls in CLASSES:
		var p: Dictionary = PARAMS[cls]
		var map := NavigationServer3D.map_create()
		NavigationServer3D.map_set_cell_size(map, float(p["cell"]))
		NavigationServer3D.map_set_cell_height(map, float(p["cell_h"]))
		NavigationServer3D.map_set_link_connection_radius(map, float(p["link_r"]))
		# See the header: with one region per map the free-edge pairing pass joins nothing.
		NavigationServer3D.map_set_use_edge_connections(map, false)
		NavigationServer3D.map_set_active(map, true)
		maps[cls] = map
		stats[String(cls)] = _regions(cls, map, index.get(String(cls), []))
		_links_for(cls, map, links, to_godot)
	return stats


func _exit_tree() -> void:
	for cls in maps:
		NavigationServer3D.free_rid(maps[cls])
	maps.clear()


func _regions(cls: StringName, map: RID, rows: Array) -> int:
	var made: Array[NavigationRegion3D] = []
	var polys := 0
	for row in rows:
		var path := String(row.get("path", ""))
		if not ResourceLoader.exists(path):
			push_warning("CityNav: missing baked chunk " + path)
			continue
		var mesh := load(path) as NavigationMesh
		if mesh == null:
			push_error("CityNav: cannot load navmesh " + path)
			continue
		var region := NavigationRegion3D.new()
		region.name = "Nav_%s_%d_%d" % [String(cls), int(row["cx"]), int(row["cy"])]
		region.navigation_mesh = mesh
		add_child(region)
		region.set_navigation_map(map)
		region.add_to_group(&"nav_" + String(cls))
		made.append(region)
		polys += mesh.get_polygon_count()
	regions[cls] = made
	if made.is_empty():
		push_warning("CityNav: no baked chunks for %s — run tools/city/bake_nav.sh" % cls)
	return polys


func _links_for(cls: StringName, map: RID, links: Array, to_godot: Callable) -> void:
	var radius: float = float(PARAMS[cls]["link_r"])
	for entry in links:
		var a: Vector3 = to_godot.call(entry["from"])
		var b: Vector3 = to_godot.call(entry["to"])
		var link := NavigationLink3D.new()
		link.name = "%s_%s" % [String(cls), String(entry["id"])]
		add_child(link)
		link.set_navigation_map(map)
		link.start_position = a
		link.end_position = b
		link.bidirectional = not bool(entry.get("oneway", false))
		link.travel_cost = 3.0
		link.enter_cost = 1.0
		# Off until snap_links() has proved both ends sit on THIS class's navmesh (lead r3).
		link.enabled = false
		_links.append(link)
		if a.distance_to(b) < radius:
			push_warning("CityNav: link %s is shorter than its connection radius" % link.name)


## Once the maps are queryable, pull every link endpoint onto its own class's baked navmesh and
## gate the link on the result (lead r3): ENABLED only when both ends land within SNAP_GATE, off
## otherwise, with the losers listed so city-layout can move the connector. The layout's endpoints
## are graph points, not navmesh points (reviews/city-build-nav.md: 2 of 48 attached).
## Returns {class: [enabled, total], "off": [[name, d_start, d_end, class], ...]}.
func snap_links() -> Dictionary:
	var out := {}
	var off: Array = []
	links_attached = 0
	for cls in CLASSES:
		if not is_synced(cls):
			continue
		var map: RID = maps[cls]
		var enabled := 0
		var total := 0
		for link in _links:
			if not String(link.name).begins_with(String(cls) + "_"):
				continue
			total += 1
			var a: Vector3 = link.start_position
			var b: Vector3 = link.end_position
			var sa: Vector3 = NavigationServer3D.map_get_closest_point(map, a)
			var sb: Vector3 = NavigationServer3D.map_get_closest_point(map, b)
			var da := sa.distance_to(a)
			var db := sb.distance_to(b)
			if da <= SNAP_GATE and db <= SNAP_GATE:
				link.start_position = sa
				link.end_position = sb
				link.enabled = true
				enabled += 1
			else:
				link.enabled = false
				off.append([link.name, da, db, String(cls)])
		out[String(cls)] = [enabled, total]
		links_attached += enabled
	links_snapped = true
	out["off"] = off
	return out


func _load_index() -> Dictionary:
	## Chunks are discovered with ResourceLoader, not from the index JSON: an exported .app packs
	## only imported resources, and a side-car .json next to them is not guaranteed to ship
	## (reviews/city-build-lead.md, packaging). `nav_<class>_<cx>_<cy>.res` is self-describing.
	var out: Dictionary = {}
	for cls in CLASSES:
		var rows: Array = []
		var prefix := "nav_%s_" % String(cls)
		for file in ResourceLoader.list_directory(NAV_DIR):
			if not (file.begins_with(prefix) and file.ends_with(".res")):
				continue
			var parts := file.get_basename().split("_")
			if parts.size() < 4:
				push_warning("CityNav: unexpected navmesh name " + file)
				continue
			rows.append({"path": NAV_DIR.path_join(file),
					"cx": int(parts[parts.size() - 2]), "cy": int(parts[parts.size() - 1])})
		rows.sort_custom(func(a, b): return String(a["path"]) < String(b["path"]))
		out[String(cls)] = rows
		if rows.is_empty():
			push_warning("CityNav: no baked navmesh for %s — run tools/city/bake_nav.sh" % cls)
	return out


## RID of the navigation map for an agent class (CONTRACTS 7).
func nav_map(cls: StringName) -> RID:
	if not maps.has(cls):
		push_error("CityNav: unknown agent class '%s'" % cls)
		return RID()
	return maps[cls]


## Every polygon of every region baked for a class, as a NavigationMesh-free sample list.
## Returns PackedVector3Array of polygon centres (used by the checks and by the AI's sampler).
func sample_points(cls: StringName, limit: int = 0) -> PackedVector3Array:
	var out := PackedVector3Array()
	for region in regions.get(cls, []):
		var mesh: NavigationMesh = (region as NavigationRegion3D).navigation_mesh
		if mesh == null:
			continue
		var verts := mesh.get_vertices()
		for i in mesh.get_polygon_count():
			var idx := mesh.get_polygon(i)
			if idx.is_empty():
				continue
			var c := Vector3.ZERO
			for v in idx:
				c += verts[v]
			out.append(c / float(idx.size()))
			if limit > 0 and out.size() >= limit:
				return out
	return out


## Up to `want` polygon centres drawn from the largest connected island of a class's baked
## meshes. Used by the nav report as a control: pairs inside one island must always connect, so a
## failure there means the query is wrong rather than the map.
func largest_island_points(cls: StringName, want: int) -> PackedVector3Array:
	var centres := PackedVector3Array()
	var meshes: Array[NavigationMesh] = []
	for region in regions.get(cls, []):
		var mesh: NavigationMesh = (region as NavigationRegion3D).navigation_mesh
		if mesh != null and mesh.get_polygon_count() > 0:
			meshes.append(mesh)
	var parent: Dictionary = {}
	var index_of: Dictionary = {}
	for mesh in meshes:
		var verts := mesh.get_vertices()
		for i in mesh.get_polygon_count():
			var key := "%d_%d" % [meshes.find(mesh), i]
			index_of[key] = centres.size()
			parent[centres.size()] = centres.size()
			var idx := mesh.get_polygon(i)
			var c := Vector3.ZERO
			for v in idx:
				c += verts[v]
			centres.append(c / float(idx.size()))
	var first_at_vertex: Dictionary = {}
	for mesh in meshes:
		var mi := meshes.find(mesh)
		for i in mesh.get_polygon_count():
			var a: int = index_of["%d_%d" % [mi, i]]
			var root := _find(parent, a)
			for v in mesh.get_polygon(i):
				var vk := "%d_%d" % [mi, v]
				if first_at_vertex.has(vk):
					var other := _find(parent, first_at_vertex[vk])
					if other != root:
						parent[root] = other
						root = other
				else:
					first_at_vertex[vk] = a
	var size: Dictionary = {}
	var members: Dictionary = {}
	for i in centres.size():
		var r := _find(parent, i)
		size[r] = int(size.get(r, 0)) + 1
		if not members.has(r):
			members[r] = PackedInt32Array()
		members[r].append(i)
	var best := -1
	for r in size:
		if best < 0 or int(size[r]) > int(size[best]):
			best = r
	var out := PackedVector3Array()
	if best < 0:
		return out
	var list: PackedInt32Array = members[best]
	var step := maxi(1, list.size() / maxi(1, want))
	for k in range(0, list.size(), step):
		out.append(centres[list[k]])
		if out.size() >= want:
			break
	return out


func _find(parent: Dictionary, a: int) -> int:
	while int(parent[a]) != a:
		parent[a] = parent[int(parent[a])]
		a = int(parent[a])
	return a


## True once a class's map answers queries with its own baked geometry (godot-tech 3.4).
##
## The iteration id alone is not enough: it goes non-zero a frame before the map's polygons are
## queryable, so a path query on the first "synced" frame returns an empty path. So we also ask
## for the closest point to a known polygon centre and require it back within 0.5 m
## (reviews/city-build-nav.md: fires on the first real-path frame in 7 of 7 variants).
## Callers gate their first path query on this.
func is_synced(cls: StringName = &"") -> bool:
	var want: Array[StringName] = []
	if cls == &"":
		want.assign(CLASSES)
	else:
		want.append(cls)
	for c in want:
		if not maps.has(c):
			return false
		if NavigationServer3D.map_get_iteration_id(maps[c]) <= 0:
			return false
		if not _answers(c):
			return false
	return true


func _answers(cls: StringName) -> bool:
	## A sample polygon centre must come back from the map within SYNC_TOLERANCE.
	for region in regions.get(cls, []):
		var mesh: NavigationMesh = (region as NavigationRegion3D).navigation_mesh
		if mesh == null or mesh.get_polygon_count() == 0:
			continue
		var verts := mesh.get_vertices()
		var idx := mesh.get_polygon(mesh.get_polygon_count() / 2)
		if idx.is_empty():
			continue
		var c := Vector3.ZERO
		for v in idx:
			c += verts[v]
		c /= float(idx.size())
		return NavigationServer3D.map_get_closest_point(maps[cls], c).distance_to(c) <= SYNC_TOLERANCE
	return false
