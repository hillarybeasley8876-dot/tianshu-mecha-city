extends Node
## Stage scout for the trailer's combat arena (trailer unit, lead brief trailer-r2 §1).
##
##   tools/godot.sh test res://trailer/probe_stage.gd -- --stage=res://trailer/stages.json \
##       --skip-menu --stub=flow --timeout=900
##
## Loads the real game, then for every candidate stage: teleports the hero, spawns a pack on the
## navmesh around it, lets the fight start, and measures every candidate camera with TrailerFraming.
## Pure queries — headless, no rendering, so a dozen arenas cost one run.
##
## A stage passes when its best camera has bbox >= MIN_BBOX (the 16 m mech reads at 1/3 of the frame),
## an unblocked chest ray, and open >= MIN_OPEN (the frame behind the hero is sky / far city, not a
## near wall), with enemies visible. Prints "STAGE <id> <cam> bbox=.. blocked=.. foes=.. open=..".

const STAGE_DEFAULT := "res://trailer/stages.json"
const MIN_BBOX := 0.33
const MIN_OPEN := 0.50
## Physics frames to let the pack spawn, land and close on the hero before a camera is measured.
const SETTLE_FRAMES := 300
const CAM_FRAMES := 2


func _ready() -> void:
	_run()


func _run() -> void:
	var path := _arg("stage", STAGE_DEFAULT)
	var doc := _load_json(path)
	if doc.is_empty():
		get_tree().quit(1)
		return
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	add_child(main)
	if not await _wait_world():
		push_error("probe_stage: the world never became ready")
		get_tree().quit(1)
		return
	var cam := Camera3D.new()
	cam.near = 0.5
	cam.far = 6000.0
	add_child(cam)
	cam.make_current()
	var spawner := main.get_node_or_null(^"EnemySpawner")
	if spawner == null:
		push_error("probe_stage: no EnemySpawner (pass --skip-menu and leave enemies unstubbed)")
		get_tree().quit(1)
		return
	var results: Array[Dictionary] = []
	for stage: Dictionary in (doc.get("stages", []) as Array):
		results.append_array(await _score(stage as Dictionary, cam, spawner))
	_rank(results)
	get_tree().quit(0)


## Teleport, spawn the pack, let it engage, then measure every candidate camera of this stage.
func _score(stage: Dictionary, cam: Camera3D, spawner: Node) -> Array[Dictionary]:
	var id := String(stage.get("id", "?"))
	var at := _vec(stage.get("spawn", [0, 0, 0]))
	var yaw := float(stage.get("yaw", 0.0))
	Game.player.call(&"debug_teleport", [at.x, at.y, at.z], yaw)
	spawner.call(&"clear")
	var pack: Array = stage.get("foes", ["ripper", "ripper", "ripper", "mantis"])
	for i in pack.size():
		var a := TAU * float(i) / float(pack.size()) + float(stage.get("foe_phase", 0.0))
		var want := at + Vector3(cos(a), 0.0, sin(a)) * float(stage.get("foe_dist", 45.0))
		var t := Transform3D(Basis.looking_at((at - want).normalized(), Vector3.UP), want)
		spawner.call(&"spawn", StringName(pack[i]), t)
	await _frames(SETTLE_FRAMES)
	var hero := Game.player.global_position
	print("STAGE %s hero=(%.0f,%.0f,%.0f) foes=%d" % [id, hero.x, hero.y, hero.z,
			int(spawner.call(&"alive_count"))])
	var out: Array[Dictionary] = []
	var cams: Array = stage.get("cams", [])
	if cams.is_empty():
		cams = _default_cams(stage)
	for c: Dictionary in cams:
		out.append(_measure(id, c as Dictionary, cam, hero))
	return out


## The standard candidate set: four side cameras at 44–60 m around the hero plus a top-down, at the
## stage's azimuths. 225 deg is the sun-behind-camera bearing at --tod=0.6 (status/trailer.md), so the
## default spread brackets it and finds out whether a stage is only good from one side.
func _default_cams(stage: Dictionary) -> Array:
	var azs: Array = stage.get("az", [225.0])
	var out: Array = []
	for az: float in azs:
		for spec: Array in [[44.0, 3.0, 0.0, 50.0], [46.0, 14.0, 90.0, 50.0], [50.0, 32.0, 180.0, 50.0],
				[60.0, 10.0, 270.0, 55.0]]:
			var a := deg_to_rad(az + float(spec[2]))
			out.append({
				"name": "%03d_%s" % [int(az), ["low", "mid", "crane", "wide"][int(spec[2]) / 90]],
				"pos_hero": [cos(a) * float(spec[0]), float(spec[1]), sin(a) * float(spec[0])],
				"look_hero": [0.0, 0.0, 0.0],
				"fov": float(spec[3]),
			})
	out.append({"name": "top", "pos_hero": [0.0, 130.0, 0.5], "look_hero": [0.0, 0.0, 0.0], "fov": 60.0})
	return out


func _measure(stage_id: String, c: Dictionary, cam: Camera3D, hero: Vector3) -> Dictionary:
	var pos := hero + _vec(c.get("pos_hero", [0, 10, -50]))
	var look := hero + _vec(c.get("look_hero", [0, 0, 0]))
	cam.global_position = pos
	cam.fov = float(c.get("fov", 50.0))
	if pos.distance_squared_to(look) > 0.01:
		cam.look_at(look, Vector3.UP)
	var s := TrailerFraming.sample(cam, true)
	var ok: bool = float(s["bbox"]) >= MIN_BBOX and not bool(s["blocked"]) \
			and float(s["open"]) >= MIN_OPEN and int(s["foes"]) > 0
	var by := "-"
	if bool(s["blocked"]):
		var hit := TrailerFraming.sight_hit(cam, Game.player.global_position + Vector3.UP, Game.player)
		by = String((hit.get("collider") as Node).name) if hit.has("collider") else "?"
	print("  CAM %s %-10s d=%4.0f bbox=%.2f blocked=%-5s by=%-16s foes=%d open=%.2f med=%4.0f %s pos=%.0f,%.0f,%.0f look=%.0f,%.0f,%.0f fov=%.0f" % [
		stage_id, String(c.get("name", "?")), pos.distance_to(hero), float(s["bbox"]),
		str(s["blocked"]), by, int(s["foes"]), float(s["open"]), float(s["med"]),
		"PASS" if ok else "fail", pos.x, pos.y, pos.z, look.x, look.y, look.z, cam.fov])
	return {"stage": stage_id, "cam": String(c.get("name", "?")), "ok": ok, "s": s,
		"pos": pos, "look": look, "fov": cam.fov}


## Stages ranked by their best camera, so the pick is the top line and not an opinion.
func _rank(results: Array[Dictionary]) -> void:
	var best: Dictionary = {}
	for r: Dictionary in results:
		var id := String(r["stage"])
		var score := float((r["s"] as Dictionary)["open"]) * 2.0 + float((r["s"] as Dictionary)["bbox"])
		if bool(r["ok"]):
			score += 1.0
		if not best.has(id) or score > float((best[id] as Dictionary)["score"]):
			best[id] = {"score": score, "r": r}
	var ids: Array = best.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return float((best[a] as Dictionary)["score"]) > float((best[b] as Dictionary)["score"]))
	print("RANK")
	for id: String in ids:
		var r: Dictionary = (best[id] as Dictionary)["r"]
		var p: Vector3 = r["pos"]
		var l: Vector3 = r["look"]
		print("  %-14s score=%.2f cam=%-10s bbox=%.2f open=%.2f foes=%d pos=%.0f,%.0f,%.0f look=%.0f,%.0f,%.0f"
			% [id, float((best[id] as Dictionary)["score"]), String(r["cam"]),
			float((r["s"] as Dictionary)["bbox"]), float((r["s"] as Dictionary)["open"]),
			int((r["s"] as Dictionary)["foes"]), p.x, p.y, p.z, l.x, l.y, l.z])


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
		push_error("probe_stage: %s is not a JSON object" % path)
		return {}
	return data as Dictionary


func _vec(v: Variant) -> Vector3:
	var a := v as Array
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
