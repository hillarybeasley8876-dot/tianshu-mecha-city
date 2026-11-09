extends Node
## Diagnostic: find vista cameras that actually see something (city-art).
##   tools/godot.sh test res://world/art/tests/probe_cams.gd -- --out=res://world/art/tests/look_cams.json
##
## Guessing camera positions by hand puts them inside city-build's blockout — six tries, five walls.
## This walks candidate positions (street midpoints, arena centres) at four heights, fans nine rays over
## a 50 deg cone at five yaws around the Spire, and scores each by how far it can see and how much sky
## is in frame. The best camera per height band is written in the `tools/godot.sh shot --cams=` format.

const CITY_SCENE := "res://world/city.tscn"
# city-art r12 §3: derived, never a literal an absolute home path path — the same file the runtime reads.
const DESIGN := "res://world/city/design_layout.json"
const SPIRE := Vector3(0.0, 200.0, 120.0)
const RAYS := 9
const FOV := 50.0
const MAX_DIST := 2000.0
const HEIGHTS: Array[float] = [8.0, 40.0, 120.0, 240.0]

var _out := "res://world/art/tests/look_cams.json"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.split("=", 1)[1]
	var city := (load(CITY_SCENE) as PackedScene).instantiate() as Node3D
	add_child(city)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var state := get_viewport().world_3d.direct_space_state
	var found := _search(state, _candidates())
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	# Take the best camera per height band in turn: an all-240 m set is six rooftop panoramas and says
	# nothing about how the city reads from the street, which is where the player is.
	var picked: Array = []
	for h in HEIGHTS + [HEIGHTS[1]]:
		for row in found:
			if not is_equal_approx((row["pos"] as Vector3).y, h) or _too_close(row, picked):
				continue
			picked.append(row)
			break
	_write(picked)
	get_tree().quit(0)


## Candidate camera spots: every street midpoint, every arena centre and the Spire plaza ring.
func _candidates() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var design := _json(DESIGN)
	for s in design.get("streets", []):
		var pts: Array = s.get("points", [])
		if pts.size() < 2:
			continue
		var mid: Array = (pts[0] as Array).duplicate()
		mid[0] = (float(pts[0][0]) + float(pts[pts.size() - 1][0])) * 0.5
		mid[1] = (float(pts[0][1]) + float(pts[pts.size() - 1][1])) * 0.5
		out.append(Vector3(float(mid[0]), 0.0, -float(mid[1])))
	for a in design.get("arenas", []):
		var poly: Array = a.get("polygon", [])
		if poly.is_empty():
			continue
		var c := Vector3.ZERO
		for p in poly:
			c += Vector3(float(p[0]), 0.0, -float(p[1]))
		out.append(c / float(poly.size()))
	return out


func _search(state: PhysicsDirectSpaceState3D, spots: Array[Vector3]) -> Array:
	var rows: Array = []
	for spot in spots:
		var to_spire := (SPIRE - spot)
		to_spire.y = 0.0
		var base_yaw := atan2(to_spire.x, to_spire.z)
		for h in HEIGHTS:
			var eye := spot + Vector3.UP * h
			for step in range(-2, 3):
				var yaw := base_yaw + deg_to_rad(35.0 * float(step))
				var score := _score(state, eye, yaw)
				rows.append({"score": score, "pos": eye,
					"look": eye + _dir(yaw, -8.0) * 400.0, "fov": FOV})
	return rows


## Mean ray distance inside the cone, plus a bonus for sky (rays that hit nothing) and a penalty for
## anything closer than 25 m — a wall in the near field ruins the frame whatever the rest sees.
func _score(state: PhysicsDirectSpaceState3D, eye: Vector3, yaw: float) -> float:
	var total := 0.0
	var sky := 0.0
	var near := 0.0
	for i in range(RAYS):
		var t := (float(i) / float(RAYS - 1) - 0.5) * FOV
		var pitch := -6.0 + 9.0 * float(i % 3)
		var dir := _dir(yaw + deg_to_rad(t), deg_to_rad(pitch))
		var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * MAX_DIST, Layers.WORLD)
		q.collide_with_areas = false
		var hit := state.intersect_ray(q)
		if hit.is_empty():
			total += MAX_DIST
			sky += 1.0
			continue
		var d := eye.distance_to(hit["position"] as Vector3)
		total += d
		if d < 25.0:
			near += 1.0
	return total / float(RAYS) + sky * 60.0 - near * 400.0


func _dir(yaw: float, pitch_deg: float) -> Vector3:
	var p := deg_to_rad(pitch_deg)
	return Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)).normalized()


func _too_close(row: Dictionary, picked: Array) -> bool:
	for p in picked:
		if (p["pos"] as Vector3).distance_to(row["pos"] as Vector3) < 160.0:
			return true
	return false


func _write(rows: Array) -> void:
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f == null:
		push_error("probe_cams: cannot write %s" % _out)
		return
	var out: Array = []
	for r in rows:
		var pos: Vector3 = r["pos"]
		var look: Vector3 = r["look"]
		out.append({"name": "probe%d" % out.size(),
			"pos": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), snappedf(pos.z, 0.1)],
			"look": [snappedf(look.x, 0.1), snappedf(look.y, 0.1), snappedf(look.z, 0.1)],
			"fov": r["fov"]})
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("PROBE_CAMS wrote %d cameras to %s" % [out.size(), _out])
	for r in rows:
		print("PROBE_CAMS score=%.0f pos=%s" % [r["score"], r["pos"]])


func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("probe_cams: %s missing" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}
