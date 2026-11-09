extends Node
## Diagnostic: frame a single dressing unit that the float audit named (city-art r16a).
##   tools/godot.sh test res://world/art/tests/probe_floater_cams.gd -- \
##       --at=-129.0,11.7,-10.6 --out=res://world/art/tests/cams_r16a.json
##
## Guessing a camera by hand put it inside the building beside the unit — twice. The units the audit
## names are small objects on roofs in a dense city, so the camera has to be found, not chosen: this
## fans rays out of the unit over a dome, keeps the directions with a clear line of sight, and writes
## the best one as a `tools/godot.sh shot --cams=` camera looking back at the unit.
##
## `--at=` takes one or more `x,y,z` points separated by `;`. Names come from `--names=` in the same
## order. `--dist=` is how far out the camera sits (default 16 m) and `--fov=` its field of view.

const CITY_SCENE := "res://world/city.tscn"
## The dome the camera is searched over: 16 azimuths x these elevations, in degrees.
const ELEVATIONS: Array[float] = [-8.0, 4.0, 16.0, 30.0, 45.0]
const AZIMUTHS := 16
## A direction is only a camera if nothing is hit within this far along it.
const CLEAR_M := 14.0
const PROBE_M := 60.0

var _out := "res://world/art/tests/cams_r16a.json"
var _dist := 16.0
var _fov := 32.0


func _ready() -> void:
	var at := ""
	var names := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.split("=", 1)[1]
		elif a.begins_with("--at="):
			at = a.split("=", 1)[1]
		elif a.begins_with("--names="):
			names = a.split("=", 1)[1]
		elif a.begins_with("--dist="):
			_dist = float(a.split("=", 1)[1])
		elif a.begins_with("--fov="):
			_fov = float(a.split("=", 1)[1])
	var points := at.split(";", false)
	if points.is_empty():
		push_error("probe_floater_cams: --at=x,y,z[;x,y,z] is required")
		get_tree().quit(1)
		return
	var city := (load(CITY_SCENE) as PackedScene).instantiate() as Node3D
	add_child(city)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var state := get_viewport().world_3d.direct_space_state
	var labels := names.split(";", false)
	var cams: Array[Dictionary] = []
	for i in points.size():
		var p := _parse(points[i])
		var label := String(labels[i]) if i < labels.size() else "p%d" % i
		var cam := _best(state, p, label)
		if cam.is_empty():
			push_warning("probe_floater_cams: nothing at %s has a clear line of sight" % p)
			continue
		cams.append(cam)
	_write(cams)
	get_tree().quit(0)


## The camera with the longest clear line of sight out of `p`, preferring a slight downward look: a
## unit seen from just above its own roof shows the gap under it, which is the whole point.
func _best(state: PhysicsDirectSpaceState3D, p: Vector3, label: String) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1.0
	for ai in AZIMUTHS:
		var az := TAU * float(ai) / float(AZIMUTHS)
		for el: float in ELEVATIONS:
			var dir := Vector3(cos(az) * cos(deg_to_rad(el)), sin(deg_to_rad(el)),
					sin(az) * cos(deg_to_rad(el)))
			var to := p + dir * PROBE_M
			var q := PhysicsRayQueryParameters3D.create(p + dir * 1.2, to)
			q.collide_with_areas = false
			var hit := state.intersect_ray(q)
			var reach := PROBE_M
			if not hit.is_empty():
				reach = p.distance_to(hit["position"] as Vector3)
			if reach < maxf(CLEAR_M, _dist + 1.0):
				continue
			# A camera just above the roof sees the gap; one looking up from below sees the underside.
			var score := minf(reach, 40.0) - absf(el - 20.0) * 0.6
			if score <= best_score:
				continue
			best_score = score
			best = {"name": label, "pos": p + dir * _dist, "look": p, "fov": _fov}
	if not best.is_empty():
		print("FLOATER CAM %-14s at %s -> pos %s (clear %.0f m)"
				% [label, p, best["pos"], best_score])
	return best


func _write(cams: Array[Dictionary]) -> void:
	var rows: Array = []
	for c: Dictionary in cams:
		rows.append({"name": c["name"], "pos": _xyz(c["pos"] as Vector3),
				"look": _xyz(c["look"] as Vector3), "fov": c["fov"]})
	var file := FileAccess.open(_out, FileAccess.WRITE)
	if file == null:
		push_error("probe_floater_cams: cannot write %s (error %d)"
				% [_out, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(rows, "  "))
	file.close()
	print("FLOATER CAM wrote %d cameras to %s" % [rows.size(), _out])


static func _xyz(v: Vector3) -> Array:
	return [snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1)]


static func _parse(text: String) -> Vector3:
	var p := text.split(",")
	if p.size() != 3:
		push_error("probe_floater_cams: --at wants x,y,z; got '%s'" % text)
		return Vector3.ZERO
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
