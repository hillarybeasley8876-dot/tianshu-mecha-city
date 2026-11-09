extends Node3D
## post-render look-dev harness (`world/post/tests/lookdev.tscn`). Instances city-build's city (which
## instances city-art's environment), adds this unit's `post_stack.tscn`, and writes the vista cameras
## `tools/godot.sh shot` expects, so an A/B is one command with and one without `--no-post`:
##
##   tools/godot.sh shot --scene=res://world/post/tests/lookdev.tscn --out=post_after --env-only \
##     --cams=res://world/post/tests/cameras.json
##   tools/godot.sh shot ... --out=post_before ... --no-post
##   tools/godot.sh shot ... --out=post_storm ... --tod=1.0
##
## `--post-perf` instead walks the cameras and prints frame times, which is how the brief's 2.5 ms
## budget is measured (Metal reports 0 for GPU timings, so frame time is the only honest number).

const CITY_SCENE := "res://world/city.tscn"
const POST_SCENE := "res://world/post/post_stack.tscn"
const CAMERAS := "res://world/post/tests/cameras.json"
# r12 §3: derived from the project directory, never a literal home path (city-art's `ArtRepo`).
const VISTAS_REL := "data/vistas.json"
## ART.md §8's key-art vistas (v1_pier, v2_canyon, v8_crown); V4/V5/V6 are city-art's business.
const WANTED: Array[String] = ["V1", "V2", "V8"]
const PERF_WARM := 90
const PERF_SAMPLE := 60

var city: Node3D


func _ready() -> void:
	var post := (load(POST_SCENE) as PackedScene).instantiate()
	post.name = "PostStack"
	add_child(post)
	city = _instance_city()
	_write_cameras()
	for i in 4:
		await get_tree().physics_frame
	print("LOOKDEV city=%s post=%s" % [city != null, post.enabled])
	if Game.has_flag("post-bracket"):
		_bracket_run.call_deferred(String(Game.flag("post-bracket")), post as PostStack)
	elif Game.has_flag("post-perf"):
		_perf_run.call_deferred()


## `--post-bracket=a:tonemap_exposure:0.7,fog_depth_begin:250;b:...` renders the SAME camera under each
## candidate tune in one windowed run and writes `captures/bracket_<vista>_<name>.jpg`. Each candidate
## starts from city-art's Environment (PostStack.restore_environment), so the candidates are comparable
## and a whole sweep costs one run instead of one run per candidate.
func _bracket_run(spec: String, post: PostStack) -> void:
	# The city builds over several frames (its navmesh bake alone takes seconds), so the environment
	# this bracket re-tunes is not bound yet when _ready returns.
	for i in 600:
		if post.bound_environment != null:
			break
		await get_tree().process_frame
	if post.bound_environment == null:
		push_error("lookdev: --post-bracket never got an Environment to tune")
		get_tree().quit(1)
		return
	var cams := _cameras()
	var wanted := String(Game.flag("post-cam"))
	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 6000.0
	add_child(cam)
	for c in cams:
		if wanted != "" and String(c["name"]) != wanted:
			continue
		cam.fov = float(c["fov"])
		cam.position = _vec(c["pos"])
		cam.look_at(_vec(c["look"]), Vector3.UP)
		cam.current = true
		for entry in spec.split(";", false):
			var parts := entry.split(":", true, 1)
			var name := String(parts[0]).strip_edges()
			var tune := _tune_dict(parts[1]) if parts.size() > 1 else {}
			post.retune(tune)
			for i in PERF_WARM:
				await get_tree().process_frame
			_save("bracket_%s_%s" % [c["name"], name])
	get_tree().quit(0)


func _tune_dict(raw: String) -> Dictionary:
	var out: Dictionary = {}
	for part in raw.split(",", false):
		var kv := part.split(":")
		if kv.size() == 2:
			out[StringName(kv[0].strip_edges())] = kv[1].strip_edges()
	return out


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ArtRepo.at("captures/%s.jpg" % name)
	var err := img.save_jpg(path, 0.88)
	print("BRACKET %s err=%d" % [path, err])


func _instance_city() -> Node3D:
	if not ResourceLoader.exists(CITY_SCENE):
		push_error("lookdev: %s missing" % CITY_SCENE)
		return null
	var node := (load(CITY_SCENE) as PackedScene).instantiate() as Node3D
	add_child(node)
	return node


## Writes ART.md §8's V1/V2/V8 in the format `tools/godot.sh shot --cams=` expects.
func _write_cameras() -> void:
	if not FileAccess.file_exists(ArtRepo.at(VISTAS_REL)):
		push_error("lookdev: %s missing" % ArtRepo.at(VISTAS_REL))
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ArtRepo.at(VISTAS_REL)))
	if not (parsed is Dictionary):
		push_error("lookdev: %s is not a JSON object" % ArtRepo.at(VISTAS_REL))
		return
	var rows: Array = []
	for v in (parsed as Dictionary).get("vistas", []):
		if not WANTED.has(String(v["id"])):
			continue
		rows.append({"name": String(v["id"]), "pos": v["pos_godot"], "look": v["look_godot"],
			"fov": float(v.get("fov", 55.0))})
	var f := FileAccess.open(CAMERAS, FileAccess.WRITE)
	if f == null:
		push_error("lookdev: cannot write %s" % CAMERAS)
		return
	f.store_string(JSON.stringify(rows, "  "))
	f.close()
	print("LOOKDEV wrote %d cameras" % rows.size())


## Frame time per vista. Run it twice (with and without `--no-post`) and subtract.
func _perf_run() -> void:
	var cams := _cameras()
	if cams.is_empty():
		get_tree().quit(1)
		return
	# project.godot caps the frame rate at 60 and the window is vsynced, so a frame time of 16.67 ms
	# measures the cap and nothing else. Uncapping both is the only way to see the stack's real cost on
	# Metal, where GPU timings report 0 (godot-tech rule 2).
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 6000.0
	add_child(cam)
	print("POSTPERF %-4s %10s %10s" % ["cam", "frame_ms", "fps"])
	for c in cams:
		cam.fov = float(c["fov"])
		cam.position = _vec(c["pos"])
		cam.look_at(_vec(c["look"]), Vector3.UP)
		cam.current = true
		for i in PERF_WARM:
			await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		for i in PERF_SAMPLE:
			await get_tree().process_frame
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(PERF_SAMPLE)
		print("POSTPERF %-4s %10.2f %10.1f" % [c["name"], ms, 1000.0 / maxf(ms, 0.001)])
	get_tree().quit(0)


func _cameras() -> Array:
	if not FileAccess.file_exists(CAMERAS):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMERAS))
	return parsed if parsed is Array else []


func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
