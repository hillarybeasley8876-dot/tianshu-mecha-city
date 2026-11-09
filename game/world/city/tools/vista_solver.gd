extends Node
## Vista camera solver (city-build, lead r2, re-cut for lead r3). V4, V5 and V7 framed a ceiling or
## a wall of clutter, so the metrics are now strict about what fills the TOP of the frame.
##
##   tools/city/vistas.sh            solve, write data/vistas.proposed.json
##   tools/city/vistas.sh --shots    ... and capture captures/city_<id>_proposed.jpg
##
## Per `data/vistas.json` entry it keeps the subject (look point) and the general direction (the
## bearing to the subject may swing at most 35 deg), and may move the camera up to 150 m away and
## 60 m UP (25 m down). A candidate is accepted only when
##   1. it is outside all geometry (a 1 m sphere fits at eye height),
##   2. the subject is unobstructed (9 rays to a SUBJECT_R sphere around the look point all reach
##      it) and covers at least SUBJECT_GATE of the frame's solid angle,
##   3. rays through the UPPER HALF of the frustum hit geometry within CEIL_NEAR m in at most
##      CEIL_GATE of cases — the "no ceilings" rule,
##   4. nothing stands within NEAR m along the ray to the subject.
## Full-frame clutter is still measured and reported, and breaks ties. Each record carries `ok`,
## `moved_m`, `ceiling`, `near_clutter`, `subject_frac` and `subject_clear_m`.

const SOURCE := "res://../data/vistas.json"
const OUT_PATH := "res://../data/vistas.proposed.json"
const SEARCH_R := 150.0
const RISE := 60.0            ## the camera may climb this far above the declared height
const DROP := 25.0
const BEARING_SLACK_DEG := 35.0
const GRID_W := 16
const GRID_H := 9
const NEAR := 60.0            ## the opening-toward-the-subject probe
const CEIL_NEAR := 120.0      ## lead r3: ceilings are judged out to 120 m, not 60
const CEIL_GATE := 0.15       ## ... and at most this fraction of the upper half may be blocked
const SUBJECT_R := 120.0      ## the subject's assumed radius (the Crown disc is r 150)
const SUBJECT_GATE := 0.04    ## it must cover at least this much of the frame
const CLEAR_FRAC := 0.75      ## the first hit on a subject ray must be in the last quarter of the way
const SILHOUETTE_GATE := 0.55 ## ... and this share of the 9 subject rays (centre ray mandatory)
const BODY_R := 1.0
const EYE := 1.7              ## probe height: the declared positions sit on a surface
const RINGS: Array[float] = [0.0, 20.0, 40.0, 60.0, 85.0, 110.0, 150.0]
const BEARINGS := 24
const HEIGHTS: Array[float] = [-25.0, -14.0, -6.0, 0.0, 8.0, 18.0, 30.0, 44.0, 60.0]
## Lead r3 gave a starting point for the three vistas that failed the r2 gate. They are evaluated
## as candidates in their own right, so the report shows what they actually score.
const HINTS := {
	"V4": Vector3(420.0, 110.0, -520.0),   ## Blender (420, 520, 110), high in the canyon
	"V5": Vector3(420.0, 90.0, 330.0),     ## Blender (420, -330, 90), a high foundry deck
	"V7": Vector3(60.0, 50.0, 160.0),      ## Blender (60, -160, 50), above the A3 canopies
}

var city: Node3D = null
var space: PhysicsDirectSpaceState3D = null
var layout: Dictionary = {}


func _ready() -> void:
	city = (load("res://world/city.tscn") as PackedScene).instantiate() as Node3D
	add_child(city)
	for i in 30:
		await get_tree().physics_frame
	space = city.get_world_3d().direct_space_state
	var src := _read_json(SOURCE)
	var out: Array = []
	for v in src.get("vistas", []):
		out.append(await _solve(v))
	_write_json(OUT_PATH, {"_doc": _doc(), "vistas": out})
	var moved := 0
	var ok := 0
	for v in out:
		moved += int(float(v.get("moved_m", 0.0)) > 0.5)
		ok += int(bool(v.get("ok", false)))
		print("VISTAS %s: %s moved %.0f m, ceiling %.0f %%, subject %.1f %% of frame, clutter %.0f %%, reach %.2f, open %s"
				% [v["id"], "OK  " if bool(v.get("ok", false)) else "FAIL",
				   float(v.get("moved_m", 0.0)), float(v.get("ceiling", 1.0)) * 100.0,
				   float(v.get("subject_frac", 0.0)) * 100.0,
				   float(v.get("near_clutter", 1.0)) * 100.0,
				   float(v.get("subject_reach", 0.0)), str(v.get("subject_open", false))])
		print("VISTAS   %s subject is %.0f m away, first block at %.0f m"
				% [v["id"], float(v.get("subject_dist_m", 0.0)),
				   float(v.get("subject_block_m", -1.0))])
	print("VISTAS solved %d, %d meet the gate, %d moved -> %s"
			% [out.size(), ok, moved, ProjectSettings.globalize_path(OUT_PATH)])
	get_tree().quit(0)


func _doc() -> String:
	# The whole concatenation must be parenthesised before `%`: `%` binds tighter than `+`, so
	# only the last literal would otherwise be formatted.
	return ("city-build proposed vista cameras (lead r3 metrics): each keeps the subject and the "
		+ "bearing of data/vistas.json (within %.0f deg), may move up to %.0f m and rise %.0f m, and "
		+ "must have the subject unobstructed over %.0f %% of the frame with at most %.0f %% of the "
		+ "UPPER HALF of a %dx%d ray grid blocked within %.0f m (no ceilings). Review and adopt."
		) % [BEARING_SLACK_DEG, SEARCH_R, RISE, SUBJECT_GATE * 100.0, CEIL_GATE * 100.0,
			GRID_W, GRID_H, CEIL_NEAR]


# ------------------------------------------------------------------ solver
func _solve(v: Dictionary) -> Dictionary:
	var pos := _vec(v.get("pos_godot", [0, 0, 0]))
	var look := _vec(v.get("look_godot", [0, 0, 0]))
	var fov := float(v.get("fov", 50.0))
	var base_bearing := _bearing(pos, look)
	var declared := _score(pos, look, fov)
	var best := _rank(declared, pos, pos)
	var hint: Variant = HINTS.get(String(v.get("id", "")))
	if hint is Vector3:
		best = _rank(_score(hint, look, fov), hint, pos, best)
		print("VISTAS %s hint %s scores ceiling %.0f %%, subject %.0f %%, reach %.2f, open %s"
				% [v["id"], str(hint), float(best["score"]["ceiling"]) * 100.0,
				   float(best["score"]["subject"]) * 100.0, float(best["score"]["clear"]),
				   str(best["score"]["open"])])
	for r in RINGS:
		for b in BEARINGS:
			var ang := TAU * float(b) / float(BEARINGS)
			for dy in HEIGHTS:
				var cand := pos + Vector3(cos(ang) * r, dy, sin(ang) * r)
				if dy > RISE or dy < -DROP:
					continue
				if absf(angle_difference(base_bearing,
						_bearing(cand, look))) > deg_to_rad(BEARING_SLACK_DEG):
					continue
				best = _rank(_score(cand, look, fov), cand, pos, best)
	var p: Vector3 = best["pos"]
	var s: Dictionary = best["score"]
	var rec := v.duplicate(true)
	rec["pos_godot"] = [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)]
	rec["pos_blender"] = _blender(rec["pos_godot"])
	rec["moved_m"] = snappedf(p.distance_to(pos), 0.1)
	rec["ceiling"] = snappedf(float(s["ceiling"]), 0.001)
	rec["near_clutter"] = snappedf(float(s["clutter"]), 0.001)
	rec["subject_frac"] = snappedf(float(s["subject"]), 0.004)
	rec["subject_reach"] = snappedf(float(s["clear"]), 0.01)
	rec["subject_open"] = bool(s["open"])
	# Honest reporting: a vista whose best camera still fails a gate is the lead's to re-aim.
	rec["ok"] = bool(s["ok"])
	rec["declared_ok"] = bool(declared["ok"])
	rec["subject_block_m"] = snappedf(_subject_clear(p, look), 1.0)
	rec["subject_dist_m"] = snappedf(p.distance_to(look), 1.0)
	return rec


func _rank(score: Dictionary, cand: Vector3, home: Vector3, best: Dictionary = {}) -> Dictionary:
	## Keep the better of `best` and this candidate.
	var move := cand.distance_to(home)
	if best.is_empty():
		return {"pos": cand, "score": score, "move": move}
	if _better(score, move, best["score"], float(best["move"])):
		return {"pos": cand, "score": score, "move": move}
	return best


func _better(a: Dictionary, a_move: float, b: Dictionary, b_move: float) -> bool:
	## Passing the gate wins outright, and among passing candidates the SHORTEST move wins: the
	## declared position is the composition the lead wants, so a camera that meets every gate 20 m
	## away is better than one that meets them 150 m away. Below the gate the order is by quality,
	## so a run where nothing passes still returns the least-bad camera rather than the first one.
	if bool(a["ok"]) != bool(b["ok"]):
		return bool(a["ok"])
	if bool(a["ok"]):
		return a_move < b_move - 1e-4
	if absf(float(a["ceiling"]) - float(b["ceiling"])) > 1e-4:
		return float(a["ceiling"]) < float(b["ceiling"])
	if absf(float(a["clear"]) - float(b["clear"])) > 1e-4:
		return float(a["clear"]) > float(b["clear"])
	if absf(float(a["subject"]) - float(b["subject"])) > 1e-4:
		return float(a["subject"]) > float(b["subject"])
	return float(a["clutter"]) < float(b["clutter"]) - 1e-4


func _score(cand: Vector3, look: Vector3, fov: float) -> Dictionary:
	## All four gates at once. `ceiling` and `clutter` are still reported for a failing candidate so
	## the lead can see which gate it missed and by how much.
	var out := {"ok": false, "ceiling": 1.0, "clutter": 1.0, "subject": 0.0, "clear": 0.0,
			"open": false}
	if not _outside(cand):
		return out
	var grid := _grid(cand, look, fov)
	out["ceiling"] = grid["ceiling"]
	out["clutter"] = grid["clutter"]
	out["subject"] = _subject_frac(cand, look, fov)
	out["clear"] = _subject_unobstructed(cand, look)
	# "Sees the subject" also needs an opening toward it: nothing within NEAR m along that ray.
	var dir := (look - cand).normalized()
	out["open"] = space.intersect_ray(PhysicsRayQueryParameters3D.create(
			cand, cand + dir * NEAR, Layers.WORLD)).is_empty()
	out["ok"] = (float(grid["ceiling"]) <= CEIL_GATE
			and float(out["subject"]) >= SUBJECT_GATE
			and float(out["clear"]) >= SILHOUETTE_GATE and bool(out["open"]))
	return out


func _subject_frac(cand: Vector3, look: Vector3, fov: float) -> float:
	## The subject's share of the frame, as solid angle: a SUBJECT_R sphere at the look point over
	## the frustum's own solid angle. Both are small-angle cones, so the ratio is stable.
	var d := cand.distance_to(look)
	if d <= SUBJECT_R:
		return 1.0
	var alpha := asin(SUBJECT_R / d)
	var subject := TAU * (1.0 - cos(alpha))
	return subject / _frustum_solid_angle(fov)


func _frustum_solid_angle(fov: float) -> float:
	var tan_v := tan(deg_to_rad(fov) * 0.5)
	var tan_h := tan_v * (16.0 / 9.0)
	return 4.0 * atan(tan_h * tan_v / sqrt(1.0 + tan_h * tan_h + tan_v * tan_v))


func _subject_unobstructed(cand: Vector3, look: Vector3) -> float:
	## Nine rays: the look point and eight points around the subject's silhouette. The look point is
	## usually INSIDE the subject (the Spire's own shaft, a megablock's mass), so "unobstructed"
	## cannot mean "no hit at all" — it means the first hit along each ray is in the last quarter of
	## the way, i.e. the subject itself and not something standing in front of it.
	##
	## The centre ray must always reach; the silhouette rays are a majority, because a subject seen
	## across a city is legitimately partly occluded by the fabric in front of it. Returns the
	## fraction of rays that reach, so a near miss is a number in the report and not just a FAIL.
	var basis := Basis.looking_at((look - cand).normalized(), Vector3.UP)
	var centre := _reach_frac(cand, look) >= CLEAR_FRAC
	var good := 1 if centre else 0
	for i in 8:
		var a := TAU * float(i) / 8.0
		var off := basis * Vector3(cos(a), sin(a), 0.0) * (SUBJECT_R * 0.8)
		good += 1 if _reach_frac(cand, look + off) >= CLEAR_FRAC else 0
	# A blocked centre ray can never pass, so it is scored below every centre-clear candidate.
	return (float(good) / 9.0) * (1.0 if centre else 0.5)


func _reach_frac(from: Vector3, target: Vector3) -> float:
	## 1.0 when nothing blocks the way; otherwise how far the first hit got, as a fraction.
	var full := from.distance_to(target)
	if full < 1e-3:
		return 0.0
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, target, Layers.WORLD))
	if hit.is_empty():
		return 1.0
	return from.distance_to(hit["position"] as Vector3) / full


func _subject_clear(cand: Vector3, look: Vector3) -> float:
	## Distance to the first thing on the ray to the subject, for the report. When this is well
	## short of `subject_dist_m` it names the obstruction the lead has to move: -1 means clear.
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(cand, look, Layers.WORLD))
	if hit.is_empty():
		return -1.0
	return cand.distance_to(hit["position"] as Vector3)


func _outside(p: Vector3) -> bool:
	## Probe at eye height: the declared positions sit ON a surface, so a sphere centred there
	## would report the floor as an intersection and reject every candidate.
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = BODY_R
	q.shape = s
	q.transform = Transform3D(Basis(), p + Vector3.UP * EYE)
	q.collision_mask = Layers.WORLD
	return space.intersect_shape(q, 1).is_empty()


func _grid(p: Vector3, look: Vector3, fov: float) -> Dictionary:
	## One GRID_W x GRID_H sweep of the frustum, read twice: `ceiling` is the UPPER HALF tested out
	## to CEIL_NEAR (lead r3's "no ceilings" rule), `clutter` is the whole frame out to NEAR.
	var basis := _look_basis(p, look)
	var tan_v := tan(deg_to_rad(fov) * 0.5)
	var tan_h := tan_v * (16.0 / 9.0)
	var ceil_blocked := 0
	var ceil_total := 0
	var blocked := 0
	for j in GRID_H:
		var upper := j >= GRID_H / 2   ## +V is up in the frustum basis, so the top rows are the sky
		for i in GRID_W:
			var u := (float(i) + 0.5) / float(GRID_W) * 2.0 - 1.0
			var w := (float(j) + 0.5) / float(GRID_H) * 2.0 - 1.0
			var dir := (basis * Vector3(u * tan_h, w * tan_v, -1.0)).normalized()
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(
					p, p + dir * NEAR, Layers.WORLD)).is_empty():
				blocked += 1
			if upper:
				ceil_total += 1
				if not space.intersect_ray(PhysicsRayQueryParameters3D.create(
						p, p + dir * CEIL_NEAR, Layers.WORLD)).is_empty():
					ceil_blocked += 1
	return {"ceiling": float(ceil_blocked) / maxf(1.0, float(ceil_total)),
			"clutter": float(blocked) / float(GRID_W * GRID_H)}


func _look_basis(p: Vector3, look: Vector3) -> Basis:
	var fwd := (look - p)
	if fwd.length_squared() < 1e-6:
		fwd = Vector3.FORWARD
	return Basis.looking_at(fwd.normalized(), Vector3.UP)


func _bearing(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(d.z, d.x)


# ------------------------------------------------------------------ io
func _vec(a: Variant) -> Vector3:
	var arr: Array = a if a is Array else [0.0, 0.0, 0.0]
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func _blender(godot: Variant) -> Array:
	var v := _vec(godot)
	return [snappedf(v.x, 0.1), snappedf(-v.z, 0.1), snappedf(v.y, 0.1)]


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("vista_solver: cannot read %s" % path)
		return {}
	return JSON.parse_string(f.get_as_text()) as Dictionary


func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("vista_solver: cannot write %s" % path)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
