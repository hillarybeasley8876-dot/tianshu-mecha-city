extends Node
## Navigation report (city-build). Run with `tools/city/nav_report.sh`.
##
## Answers the two questions reviews/city-build-nav.md asks of the built city:
##   * how long, in WALL time, until each agent class's map answers queries;
##   * whether the graph an enemy actually walks is connected — per lead r3, every spawn socket to
##     the centre of its own arena (gate 95 %, per class), and arena to arena for medium.
## Plus which NavigationLink3D are enabled per class after the 4 m snap gate, and the baked
## fragmentation from the navmesh index. Prints NAVREPORT PASS/FAIL.

const REACH_TOL := 1.0
const PAIR_GATE := 0.95
const CLASSES: Array[StringName] = [&"small", &"medium", &"large"]
const INDEX := "res://world/city/nav/index.json"

var city: Node3D = null
var nav: CityNav = null
var layout: Dictionary = {}
var fails: int = 0


func _ready() -> void:
	city = (load("res://world/city.tscn") as PackedScene).instantiate() as Node3D
	add_child(city)
	for i in 30:
		await get_tree().physics_frame
	nav = city.get("nav")
	layout = city.get("layout")
	_fragmentation()
	await _sync_times()
	_links()
	_pairs()
	print("NAVREPORT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _fragmentation() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("nav_report: cannot read " + INDEX)
		fails += 1
		return
	for cls in CLASSES:
		var polys := 0
		var islands := 0
		var biggest := 0.0
		for row in (parsed as Dictionary).get(String(cls), []):
			polys += int(row.get("polys", 0))
			islands += int(row.get("islands", 0))
			biggest = maxf(biggest, float(row.get("biggest_pct", 0.0)))
		print("NAVREPORT %s: %d polygons, %d islands, largest %.1f %% of the map"
				% [cls, polys, islands, biggest])


func _sync_times() -> void:
	var t0 := Time.get_ticks_msec()
	while not nav.is_synced() and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().physics_frame
	var total := Time.get_ticks_msec() - t0
	if not nav.is_synced():
		_report("nav sync", false, "maps not queryable within 30 s")
		return
	_report("nav sync", total < 10000, "all three maps queryable %d ms after the world was built"
			% total)


func _links() -> void:
	var counts: Dictionary = nav.snap_links()
	for cls in CLASSES:
		var pair: Array = counts.get(String(cls), [0, 0])
		var share := float(pair[0]) / maxf(1.0, float(pair[1]))
		print("NAVREPORT %s: links enabled %d/%d (%.0f %%)"
				% [cls, int(pair[0]), int(pair[1]), share * 100.0])
	for row in (counts.get("off", []) as Array):
		print("NAVREPORT   off %s (%s): start %.0f m, end %.0f m from the navmesh" % row)


func _pairs() -> void:
	## Lead r3: the metric that matters is GAMEPLAY reachability. Per class, every spawn socket must
	## reach the centre of its own arena (gate 95 %), and for medium every arena must reach every
	## other arena (reported). Failing sockets are listed with their off-mesh distances so
	## city-layout can move them.
	var arenas := _arena_centres()
	for cls in CLASSES:
		var map := nav.nav_map(cls)
		var s2a := _sockets(map, cls)
		_offmesh(map, arenas, "arena centre")
		var a2a := _share(map, arenas, arenas, true)
		_report("%s socket->arena" % cls, s2a >= PAIR_GATE,
				"%.0f %% of %d sockets reach their arena centre (gate %.0f %%)"
				% [s2a * 100.0, _socket_count(), PAIR_GATE * 100.0])
		if cls == &"medium":
			print("NAVREPORT medium: arena->arena %.0f %% of %d pairs"
					% [a2a * 100.0, arenas.size() * (arenas.size() - 1)])
		_control(map, cls)


func _socket_count() -> int:
	var n := 0
	for a in layout.get("arenas", []):
		n += (a.get("sockets", []) as Array).size()
	return n


## Every spawn socket of every arena -> that arena's own centre, on one class's map. Prints the
## failures with both off-mesh distances.
func _sockets(map: RID, cls: StringName) -> float:
	var ok := 0
	var total := 0
	for a in layout.get("arenas", []):
		var centre := _arena_centre(a)
		if centre == Vector3.INF:
			continue
		var sb := NavigationServer3D.map_get_closest_point(map, centre)
		for s in a.get("sockets", []):
			total += 1
			var g: Vector3 = city.to_godot(s["pos"])
			var sa := NavigationServer3D.map_get_closest_point(map, g)
			var path := NavigationServer3D.map_get_path(map, sa, sb, true)
			if not path.is_empty() and path[path.size() - 1].distance_to(sb) <= REACH_TOL:
				ok += 1
			elif cls == &"medium":
				print("NAVREPORT   socket %s of %s: socket %.0f m off-mesh, centre %.0f m, %s"
						% [String(s.get("id", "?")), String(a.get("id", "?")),
						   sa.distance_to(g), sb.distance_to(centre),
						   "no path" if path.is_empty() else "path stops short"])
	return float(ok) / maxf(1.0, float(total))


## The socket nearest an arena polygon's centroid: a real walkable point on a tier, which is what
## an enemy actually spawns on (the 2D polygon alone has no height).
func _arena_centre(a: Dictionary) -> Vector3:
	var poly: Array = a.get("polygon", [])
	if poly.is_empty():
		return Vector3.INF
	var c2 := Vector2.ZERO
	for p in poly:
		c2 += Vector2(float(p[0]), float(p[1]))
	c2 /= float(poly.size())
	var best := Vector3.INF
	var best_d := INF
	for s in a.get("sockets", []):
		var g: Vector3 = city.to_godot(s["pos"])
		var d := Vector2(g.x, g.z).distance_squared_to(Vector2(c2.x, -c2.y))
		if d < best_d:
			best_d = d
			best = g
	return best


func _control(map: RID, cls: StringName) -> void:
	## Sanity control: pairs drawn from the LARGEST island of this class must all connect. If this
	## is not 100 % the metric above is measuring the query, not the map.
	var pts := nav.largest_island_points(cls, 12)
	if pts.size() < 2:
		print("NAVREPORT %s: control skipped (island too small)" % cls)
		return
	var ok := 0
	var total := 0
	for i in pts.size():
		for j in pts.size():
			if i == j:
				continue
			total += 1
			var path := NavigationServer3D.map_get_path(map, pts[i], pts[j], true)
			if not path.is_empty() and path[path.size() - 1].distance_to(pts[j]) <= REACH_TOL:
				ok += 1
	print("NAVREPORT %s: control (largest island, %d points) %.0f %% of %d pairs"
			% [cls, pts.size(), 100.0 * float(ok) / maxf(1.0, float(total)), total])


func _offmesh(map: RID, pts: Array[Vector3], what: String) -> void:
	## How far each query point is from the navmesh: if this is large the pairs test is measuring
	## my probe points, not the map.
	var worst := 0.0
	var over := 0
	for p in pts:
		var d := NavigationServer3D.map_get_closest_point(map, p).distance_to(p)
		worst = maxf(worst, d)
		over += int(d > REACH_TOL)
	print("NAVREPORT probe %s: %d of %d further than %.1f m from the navmesh (worst %.1f m)"
			% [what, over, pts.size(), REACH_TOL, worst])


func _share(map: RID, froms: Array[Vector3], tos: Array[Vector3], skip_self: bool) -> float:
	## Both ends are snapped onto the navmesh first: the layout's arena sockets and spawn-zone
	## centres are graph points, not navmesh points, and an unsnapped target measures the probe,
	## not the map. The off-mesh distances are reported separately by _offmesh().
	var ok := 0
	var total := 0
	var no_path := 0
	for a in froms:
		var sa := NavigationServer3D.map_get_closest_point(map, a)
		for b in tos:
			if skip_self and a.distance_to(b) < 1.0:
				continue
			total += 1
			var sb := NavigationServer3D.map_get_closest_point(map, b)
			var path := NavigationServer3D.map_get_path(map, sa, sb, true)
			if path.is_empty():
				no_path += 1
			elif path[path.size() - 1].distance_to(sb) <= REACH_TOL:
				ok += 1
	print("NAVREPORT   pairs: %d ok, %d with no path at all (of %d)" % [ok, no_path, total])
	return float(ok) / maxf(1.0, float(total))


func _arena_centres() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for a in layout.get("arenas", []):
		var c := _arena_centre(a)
		if c != Vector3.INF:
			out.append(c)
	return out


func _report(id: String, ok: bool, text: String) -> void:
	if not ok:
		fails += 1
	print("NAVREPORT %s %s: %s" % [id, "PASS" if ok else "FAIL", text])
