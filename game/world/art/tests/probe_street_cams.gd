extends Node
## Find street-level cameras inside two arenas (city-art, review r3 §4: judge the canyon A4 and the
## Spire plaza A3 from the ground).
##   tools/godot.sh test res://world/art/tests/probe_street_cams.gd
## Samples a grid over each arena polygon at its lowest walkable tier, fans rays forward and keeps the
## position that sees the most open city — guessing these by hand put the first attempt inside a wall.

const CITY_SCENE := "res://world/city.tscn"
# city-art r12 §3: derived, never a literal an absolute home path path — the same file the runtime reads.
const DESIGN := "res://world/city/design_layout.json"
const WALK_M := 26.0             ## metres between samples along a street centreline
const ARENAS: Array[String] = ["A3", "A4"]
const GRID := 5                 ## samples per axis inside the polygon
const RAYS := 13
const CONE_DEG := 80.0
const EYE_STEPS: Array[float] = [5.5, 10.0, 18.0, 30.0]   ## chest height first, then standing on cover


func _ready() -> void:
	add_child((load(CITY_SCENE) as PackedScene).instantiate())
	await get_tree().physics_frame
	await get_tree().physics_frame
	var state := get_viewport().world_3d.direct_space_state
	var rows: Array = []
	for id in ARENAS:
		var arena := _arena(id)
		if arena.is_empty():
			push_error("probe_street_cams: no arena %s in the layout" % id)
			continue
		rows.append(_best(state, arena))
	var f := FileAccess.open("res://world/art/tests/cams_r3.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(rows, "  "))
	f.close()
	for r in rows:
		print("STREETCAM %-4s pos=(%.0f,%.1f,%.0f) look=(%.0f,%.0f,%.0f) open=%.0f m"
			% [r["name"], r["pos"][0], r["pos"][1], r["pos"][2],
			   r["look"][0], r["look"][1], r["look"][2], r["open"]])
	get_tree().quit(0)


func _arena(id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://world/city/layout.json"))
	for a in (parsed as Dictionary).get("arenas", []):
		if String(a.get("id", "")) == id:
			return a
	return {}


## The best open vantage in the arena, scored by mean free distance and how much sky is in frame.
func _best(state: PhysicsDirectSpaceState3D, arena: Dictionary) -> Dictionary:
	var poly: Array = arena.get("polygon", [])
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		var v := Vector2(float(p[0]), float(p[1]))
		lo = lo.min(v)
		hi = hi.max(v)
	var centre := (lo + hi) * 0.5
	# Start the drop just above the arena's own top tier: from the ceiling the ray lands on a viaduct or
	# a skyrail deck crossing the arena, and the "street" camera ends up 200 m up on a bridge.
	var tiers: Array = arena.get("tiers", [0.0])
	var top := 0.0
	for t in tiers:
		top = maxf(top, float(t))
	var best := {"name": arena.get("id", "?"), "pos": [centre.x, 6.0, -centre.y],
		"look": [0.0, 30.0, 0.0], "fov": 60.0, "open": 0.0}
	var best_score := -1.0
	var design: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DESIGN)) as Dictionary
	# Sample the STREET centre lines that cross the arena, not a grid over the arena: a grid stands on
	# whatever roof happens to be overhead, which is how the first attempt ended up 85 m up on a podium.
	for p in _street_points(design, lo, hi):
		var down := state.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(p.x, top + 14.0, -p.y), Vector3(p.x, -60.0, -p.y)))
		if down.is_empty():
			continue
		var floor_y := (down["position"] as Vector3).y
		for step in EYE_STEPS:
			var eye := Vector3(p.x, floor_y + step, -p.y)
			if not _open(state, eye):
				continue
			var look := Vector3(centre.x, floor_y + 26.0, -centre.y)
			var score := _score(state, eye, (look - eye).normalized())
			if score > best_score:
				best_score = score
				best["pos"] = [eye.x, eye.y, eye.z]
				best["look"] = [look.x, look.y, look.z]
				best["open"] = score
			break
	return best


## Every point on a street centre line inside the arena's footprint, in Blender XY.
func _street_points(design: Dictionary, lo: Vector2, hi: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var pad := 40.0
	for st in design.get("streets", []):
		var pts: Array = st.get("points", [])
		for i in range(pts.size() - 1):
			var a := Vector2(float(pts[i][0]), float(pts[i][1]))
			var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
			var seg := b - a
			var n := int(seg.length() / WALK_M)
			for k in range(n + 1):
				var p := a + seg * (float(k) / float(maxi(n, 1)))
				if p.x >= lo.x - pad and p.x <= hi.x + pad \
						and p.y >= lo.y - pad and p.y <= hi.y + pad:
					out.append(p)
	return out


## Free standing room: a clear sphere around the eye, so a camera inside a wall is rejected outright.
func _open(state: PhysicsDirectSpaceState3D, eye: Vector3) -> bool:
	# No `radius` on a point query: free air is six short rays instead, which is also what a camera
	# actually needs — nothing within 3 m in any direction.
	for dir in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT,
			Vector3.FORWARD, Vector3.BACK] as Array[Vector3]:
		if not state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + dir * 3.0)).is_empty():
			return false
	return true


func _score(state: PhysicsDirectSpaceState3D, eye: Vector3, fwd: Vector3) -> float:
	var right := fwd.cross(Vector3.UP).normalized()
	var total := 0.0
	for i in range(RAYS):
		var a := deg_to_rad(lerpf(-CONE_DEG * 0.5, CONE_DEG * 0.5, float(i) / float(RAYS - 1)))
		var dir := (fwd * cos(a) + right * sin(a)).normalized()
		var hit := state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + dir * 900.0))
		total += 900.0 if hit.is_empty() else eye.distance_to(hit["position"] as Vector3)
	return total / float(RAYS)
