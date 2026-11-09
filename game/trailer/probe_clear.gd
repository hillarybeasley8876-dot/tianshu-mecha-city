extends Node
## Foreground-clutter scout (trailer unit, r5). Three showcase segments (g2_assault, g3_jump, g7_melee)
## filmed *under* a skybridge while every framing gate was green: `open` is a 45-ray sample that a thin
## truss barely moves, and the chest ray is never blocked by something overhead. A physics probe does
## not help either -- the bridge carries no SIGHT collider -- so this one measures the VISUAL scene:
##
##   near   fraction of a 32x18 frame grid covered by visible meshes whose nearest point is within
##          NEAR_CLUTTER metres of the lens (the deck under the mech is excluded by height)
##   by     the mesh that covers the most of those cells, with its distance
##
##   tools/godot.sh test res://trailer/probe_clear.gd -- --stage=res://trailer/stages_clear.json \
##       --skip-menu --stub=flow --timeout=900
##
## No pack and no fight: this is a geometry question, so one run scores every bearing of every stage.
##
## WHAT IT IS NOT: a camera-placement tool. It UNDER-REPORTS -- on the A6 deck it scored bearing 105 at
## 0.06 and bearing 195 at 0.00 while `tools/godot.sh shot` showed both lenses buried in a wall. It is a
## screen for gross failures (it caught g3_jump's truss at 5 m, and its ranking of the skybridge sector
## matched the render), and the authoritative answer is a rendered bearing sweep:
##   tools/godot.sh shot --cams="$(tools/trailer/bearings.py 44 3)" --out=a6 --outdir=<abs> \
##       --spawn=-60,155,450,225 --tod=0.6 --quality=high --skip-menu --stub=flow
## then a contact sheet of the stills.

const STAGE_DEFAULT := "res://trailer/stages_clear.json"
## A mesh whose nearest point is this close to the lens is foreground clutter -- a truss, a parapet.
const NEAR_CLUTTER := 80.0
## --near=<m> overrides it: a truss across the lens is clutter at 40 m and scenery at 200 m, and which
## one a shot can live with is an art call, so the radius is a flag rather than a constant.
var _near_m := NEAR_CLUTTER
## Meshes whose top is below this height above the hero's feet are the deck, not clutter.
const WALL_FLOOR := 6.0
const GRID_X := 32
const GRID_Y := 18
const SETTLE_FRAMES := 90
## A merged city tile can carry a hundred thousand triangles; rasterising all of them for 144 cameras
## is not worth it, so each mesh is decimated to at most this many and the stride is printed.
const MAX_TRIS := 6000
## A triangle whose centroid is a little past NEAR_CLUTTER can still reach into the frame, because the
## centroid is not the nearest point. Slack keeps that from being a hole in the measurement.
const TRI_SLACK := 40.0
## --csv replay: one sample every this many seconds, and a shot fails when more than NEAR_FAIL of the
## frame is clutter for longer than RUN_FAIL (a moment of truss is a cut-away, a second of it is the shot).
const SAMPLE_EVERY := 0.2
const NEAR_FAIL := 0.25
const RUN_FAIL := 0.5

var _meshes: Array[Dictionary] = []
var _face_cache: Dictionary = {}
var _main: Node = null


## The city streams its tiles around the player, so the set of visible meshes depends on where the
## hero is standing: collecting once at startup measured the blocks around the DEFAULT spawn and
## reported an empty frame for every bearing of a stage 400 m away. Collect after every teleport.
func _gather() -> void:
	_meshes.clear()
	_face_cache.clear()
	_collect(_main)
	print("MESHES %d visible parts collected" % _meshes.size())


func _ready() -> void:
	_near_m = float(_arg("near", str(NEAR_CLUTTER)))
	_run()


func _run() -> void:
	var doc := _load_json(_arg("stage", STAGE_DEFAULT))
	if doc.is_empty():
		get_tree().quit(1)
		return
	_main = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(_main)
	if not await _wait_world():
		push_error("probe_clear: the world never became ready")
		get_tree().quit(1)
		return
	var cam := Camera3D.new()
	cam.near = 0.5
	cam.far = 6000.0
	add_child(cam)
	cam.make_current()
	var csvs := _arg("csv", "")
	if csvs != "":
		var stages: Array = doc.get("stages", []) as Array
		if stages.is_empty():
			push_error("probe_clear: --csv needs a stage to aim the lenses at")
			get_tree().quit(1)
			return
		var at := _vec((stages[0] as Dictionary).get("spawn", [0, 0, 0]))
		Game.player.call(&"debug_teleport", [at.x, at.y, at.z], 0.0)
		await _frames(SETTLE_FRAMES)
		_gather()
		for path: String in csvs.split(",", false):
			_replay(path, cam, at)
		get_tree().quit(0)
		return
	for stage: Dictionary in (doc.get("stages", []) as Array):
		await _score(stage as Dictionary, cam)
	get_tree().quit(0)


## --csv=<a.csv,b.csv> — replay the camera path a finished take actually flew and say how much of each
## frame was near clutter. The framing gate cannot see a truss overhead, so this is the check a take's
## own log cannot give: it is the recorded lens, not the lens the spec asked for.
func _replay(path: String, cam: Camera3D, look: Vector3) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("probe_clear: cannot read %s" % path)
		return
	var floor_y := look.y - TrailerFraming.HERO_H * 0.5 + WALL_FLOOR
	var id := path.get_file().get_basename()
	var samples: Array[Dictionary] = []
	var next_t := -1.0
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("#") or line.begins_with("t,") or line.is_empty():
			continue
		var p := line.split(",", false)
		if p.size() < 7:
			continue
		var t := float(p[0])
		if t < next_t:
			continue
		next_t = t + SAMPLE_EVERY
		cam.global_position = Vector3(float(p[4]), float(p[5]), float(p[6]))
		cam.look_at(look, Vector3.UP)
		var d := _near(cam, floor_y)
		samples.append({"t": t, "near": float(d["near"]), "by": String(d["by"]), "at": float(d["at"])})
	f.close()
	_report(id, samples)


## One line per take: the mean and the worst clutter, the worst moment, and the longest run above the
## threshold (which is what makes a shot unusable -- a fifth of a second of truss is a cut-away).
func _report(id: String, samples: Array[Dictionary]) -> void:
	if samples.is_empty():
		print("  CSV %-14s no samples" % id)
		return
	var total := 0.0
	var worst := {"t": 0.0, "near": -1.0, "by": "-", "at": 0.0}
	var run := 0.0
	var run_best := 0.0
	var prev := -1.0
	for s: Dictionary in samples:
		total += float(s["near"])
		if float(s["near"]) > float(worst["near"]):
			worst = s
		var dt := 0.0 if prev < 0.0 else float(s["t"]) - prev
		prev = float(s["t"])
		run = run + dt if float(s["near"]) > NEAR_FAIL else 0.0
		run_best = maxf(run_best, run)
	print("  CSV %-14s near_mean=%.2f near_max=%.2f at t=%.1f by=%-22s %.0fm run=%.2fs %s" % [
		id, total / float(samples.size()), float(worst["near"]), float(worst["t"]),
		String(worst["by"]), float(worst["at"]), run_best,
		"FAIL" if run_best > RUN_FAIL else "ok"])


## Every visible piece of world geometry once, as a world-space AABB, its node name and a lazy handle
## on its triangles. Both shapes matter: a MeshInstance3D is one piece, but the city is mostly
## MultiMeshInstance3D -- kit_placer batches ~100 buildings into one node -- and a probe that only reads
## MeshInstance3D is blind to the very blocks that fill the frame. The hero and the enemies are skipped:
## they are the subject, not clutter.
func _collect(root: Node) -> void:
	var stack: Array[Node] = [root]
	var skip: Array[Node] = []
	if Game.player != null:
		skip.append(Game.player)
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.append(c)
		var n3 := n as Node3D
		if n3 == null or not n3.is_visible_in_tree():
			continue
		if _under(n, skip):
			continue
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			_add_part(String(mi.name), mi.mesh, mi.global_transform)
			continue
		var mm := n as MultiMeshInstance3D
		if mm != null and mm.multimesh != null and mm.multimesh.mesh != null:
			var mesh := mm.multimesh.mesh
			var local := mesh.get_aabb()
			# MultiMesh.visible_instance_count is -1 for "all of them" (the Godot 4 default), so the
			# count has to be resolved before it can be iterated.
			var count := mm.multimesh.visible_instance_count
			if count < 0:
				count = mm.multimesh.instance_count
			for i in count:
				_add_part("%s#%d" % [String(mm.name), i], mesh,
						mm.global_transform * mm.multimesh.get_instance_transform(i), local)


## The world AABB of one instance. It has to be built from the eight transformed corners: the obvious
## `AABB(xf * pos, xf.basis * size)` is only right for an axis-aligned basis, and a rotated kit instance
## gives it a negative size — whose "nearest point" is then far away, so the part is silently skipped.
## That is how the probe came to report an empty frame for a lens parked against a tower.
func _add_part(name: String, mesh: Mesh, xf: Transform3D, local: AABB = AABB()) -> void:
	var box := local if local.size != Vector3.ZERO else mesh.get_aabb()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in 8:
		var p := xf * box.get_endpoint(i)
		lo = lo.min(p)
		hi = hi.max(p)
	_meshes.append({"name": name, "box": AABB(lo, hi - lo), "mesh": mesh, "xf": xf})


func _under(node: Node, roots: Array[Node]) -> bool:
	for r: Node in roots:
		if r != null and (node == r or r.is_ancestor_of(node)):
			return true
	return false


func _score(stage: Dictionary, cam: Camera3D) -> void:
	var id := String(stage.get("id", "?"))
	var at := _vec(stage.get("spawn", [0, 0, 0]))
	Game.player.call(&"debug_teleport", [at.x, at.y, at.z], float(stage.get("yaw", 0.0)))
	await _frames(SETTLE_FRAMES)
	_gather()
	var hero := Game.player.global_position
	print("STAGE %s hero=(%.0f,%.0f,%.0f) feet=%.0f" % [id, hero.x, hero.y, hero.z,
			hero.y - TrailerFraming.HERO_H * 0.5])
	var floor_y := hero.y - TrailerFraming.HERO_H * 0.5 + WALL_FLOOR
	for c: Dictionary in _cams(stage):
		_measure(id, c as Dictionary, cam, hero, floor_y)


## Every azimuth of the stage crossed with the four lens heights the showcase kit uses. `az` is a
## Godot bearing (0 = +X, 90 = +Z) measured from the hero, so the lens sits at hero + (cos, ·, sin)*d.
func _cams(stage: Dictionary) -> Array:
	var out: Array = []
	for az: float in (stage.get("az", [225.0]) as Array):
		for spec: Array in [[44.0, 3.0, "low"], [46.0, 14.0, "mid"], [50.0, 32.0, "crane"],
				[60.0, 10.0, "wide"]]:
			var a := deg_to_rad(az)
			out.append({
				"name": "%03d_%s" % [int(az), String(spec[2])],
				"pos_hero": [cos(a) * float(spec[0]), float(spec[1]), sin(a) * float(spec[0])],
				"fov": 55.0 if String(spec[2]) == "wide" else 50.0,
			})
	return out


## One camera: park it, then read how much of the frame near meshes cover.
func _measure(id: String, c: Dictionary, cam: Camera3D, hero: Vector3, floor_y: float) -> void:
	var pos := hero + _vec(c.get("pos_hero", [0, 10, -50]))
	cam.global_position = pos
	cam.fov = float(c.get("fov", 50.0))
	cam.look_at(hero, Vector3.UP)
	var s := TrailerFraming.sample(cam, false)
	var d := _near(cam, floor_y)
	print("  CLR %s %-10s near=%.2f by=%-22s at=%4.0fm bbox=%.2f blocked=%-5s pos=%.0f,%.0f,%.0f" % [
		id, String(c.get("name", "?")), float(d["near"]), String(d["by"]), float(d["at"]),
		float(s["bbox"]), str(s["blocked"]), pos.x, pos.y, pos.z])


## Rasterise the TRIANGLES of every near mesh onto the frame grid and report the covered fraction plus
## the worst offender. A mesh's AABB is useless here -- a city tile is 300 m across, so its box covers
## the whole frame from 77 m away while the tile itself is the skyline we WANT behind the mech. So the
## faces are read once per mesh (lazily, only for meshes some camera gets close to) and each triangle is
## tested on its own: a triangle whose highest vertex is below `floor_y` is the deck the mech stands on,
## a triangle further than NEAR_CLUTTER from the lens is the city, and the rest is clutter.
func _near(cam: Camera3D, floor_y: float) -> Dictionary:
	var size := cam.get_viewport().get_visible_rect().size
	var cover := PackedInt32Array()
	cover.resize(GRID_X * GRID_Y)
	var owner := PackedInt32Array()
	owner.resize(GRID_X * GRID_Y)
	var dists: Array[float] = []
	var tris: Array[float] = []
	var names: Array[String] = []
	var origin := cam.global_position
	for mi in _meshes.size():
		var m: Dictionary = _meshes[mi]
		var box: AABB = m["box"]
		if box.end.y <= floor_y:
			continue
		var d := _box_distance(box, origin)
		if d > _near_m:
			continue
		var idx := names.size()
		names.append(String(m["name"]))
		dists.append(d)
		var hit := _raster(cam, _faces(mi), origin, floor_y, size, idx + 1, d, dists, cover, owner)
		if hit < _near_m + TRI_SLACK:
			tris.append(hit)
		else:
			tris.append(d)
	var n := 0
	var tally: Dictionary = {}
	for i in cover.size():
		if cover[i] == 0:
			continue
		n += 1
		tally[owner[i]] = int(tally.get(owner[i], 0)) + 1
	var worst := 0
	var worst_n := 0
	for k: int in tally:
		if int(tally[k]) > worst_n:
			worst_n = int(tally[k])
			worst = k
	return {"near": float(n) / float(cover.size()),
		"by": "-" if worst == 0 else names[worst - 1],
		"at": 0.0 if worst == 0 else tris[worst - 1]}


## World-space triangle soup of one mesh, read once and kept. Big merged tiles are decimated by
## TRI_STRIDE sampling rather than dropped, and the stride is printed so the coverage is never a
## silently truncated number.
func _faces(mi: int) -> PackedVector3Array:
	var cached: Variant = _face_cache.get(mi)
	if cached != null:
		return cached as PackedVector3Array
	var m: Dictionary = _meshes[mi]
	var mesh := m["mesh"] as Mesh
	var xf := m["xf"] as Transform3D
	var src := mesh.get_faces()
	var stride := maxi(1, int(ceil(float(src.size()) / float(MAX_TRIS * 3))))
	if stride > 1:
		print("  CLR note: %s decimated %d->%d tris (stride %d)" % [String(m["name"]),
				src.size() / 3, src.size() / 3 / stride, stride])
	var out := PackedVector3Array()
	for i in range(0, src.size() - 2, 3 * stride):
		out.append(xf * src[i])
		out.append(xf * src[i + 1])
		out.append(xf * src[i + 2])
	_face_cache[mi] = out
	return out


## Mark every grid cell a triangle's screen bounding box touches. Triangles that straddle the near plane
## are clipped against it first — without that, one 300 m tile quad with a vertex behind the lens paints
## the whole frame and every bearing reads as a wall.
func _raster(cam: Camera3D, faces: PackedVector3Array, origin: Vector3, floor_y: float, size: Vector2,
		idx: int, dist: float, dists: Array[float], cover: PackedInt32Array,
		owner: PackedInt32Array) -> float:
	var inv := cam.global_transform.affine_inverse()
	var nearest := _near_m + TRI_SLACK
	for i in range(0, faces.size() - 2, 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		# Only a HORIZONTAL face below the mech's feet is the ground it stands on. Filtering by height
		# alone threw away the deck's own vertical faces, which is how a lens parked off the edge of the
		# sky garden -- looking straight at the side of the deck -- measured as an empty frame.
		if maxf(a.y, maxf(b.y, c.y)) <= floor_y and absf((b - a).cross(c - a).normalized().y) > 0.7:
			continue
		var mid := (a + b + c) / 3.0
		var dm := origin.distance_to(mid)
		if dm > NEAR_CLUTTER + TRI_SLACK:
			continue
		var poly := _clip_near(PackedVector3Array([inv * a, inv * b, inv * c]), cam.near)
		if poly.size() < 3:
			continue
		var x0 := GRID_X
		var x1 := 0
		var y0 := GRID_Y
		var y1 := 0
		for v: Vector3 in poly:
			var s := _project(cam, v, size)
			x0 = mini(x0, int(floor(s.x / size.x * GRID_X)))
			x1 = maxi(x1, int(ceil(s.x / size.x * GRID_X)))
			y0 = mini(y0, int(floor(s.y / size.y * GRID_Y)))
			y1 = maxi(y1, int(ceil(s.y / size.y * GRID_Y)))
		x0 = maxi(x0, 0)
		y0 = maxi(y0, 0)
		x1 = mini(x1, GRID_X)
		y1 = mini(y1, GRID_Y)
		if x0 >= x1 or y0 >= y1:
			continue
		nearest = minf(nearest, dm)
		for gy in range(y0, y1):
			for gx in range(x0, x1):
				var k := gy * GRID_X + gx
				cover[k] = 1
				if owner[k] == 0 or dist < dists[owner[k] - 1]:
					owner[k] = idx
	return nearest


## Sutherland-Hodgman against the single near plane, in camera space (Godot looks down -Z, so a vertex
## is in front when -z >= near). Returns the clipped polygon, 0-4 vertices.
func _clip_near(tri: PackedVector3Array, near: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in tri.size():
		var p := tri[i]
		var q := tri[(i + 1) % tri.size()]
		var pin := -p.z >= near
		var qin := -q.z >= near
		if pin:
			out.append(p)
		if pin != qin:
			var t := (-near - p.z) / (q.z - p.z)
			out.append(p.lerp(q, t))
	return out


## A camera-space point to screen pixels: the same projection the viewport uses, without needing the
## point to be a real world position.
func _project(cam: Camera3D, v: Vector3, size: Vector2) -> Vector2:
	var tan := tan(deg_to_rad(cam.fov) * 0.5)
	var z := maxf(-v.z, 0.001)
	return Vector2(size.x * 0.5 * (1.0 + v.x / (z * tan * (size.x / size.y))),
			size.y * 0.5 * (1.0 - v.y / (z * tan)))



func _box_distance(box: AABB, p: Vector3) -> float:
	var d := Vector3(maxf(box.position.x - p.x, maxf(0.0, p.x - box.end.x)),
			maxf(box.position.y - p.y, maxf(0.0, p.y - box.end.y)),
			maxf(box.position.z - p.z, maxf(0.0, p.z - box.end.z)))
	return d.length()


func _wait_world() -> bool:
	for i in 6000:
		if Game.world != null and Game.world_built() and Game.player != null:
			await _frames(30)
			return true
		await get_tree().physics_frame
	return false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return def


func _load_json(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("probe_clear: %s is not a JSON object" % path)
		return {}
	return data as Dictionary


func _vec(v: Variant) -> Vector3:
	var a := v as Array
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
