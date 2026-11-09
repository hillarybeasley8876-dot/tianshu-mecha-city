extends SceneTree
## Windowed screenshot tool (tools/godot.sh shot ...). Two modes, combinable:
##  static cams:  --cams=name:x,y,z:lx,ly,lz[:fov];name2:...   or  --cams=res://path/cams.json
##                ([{"name":..,"pos":[x,y,z],"look":[x,y,z],"fov":70}]) - shots from fixed cameras
##  timed (in-game camera): --times=1.5,4,8  with optional --press=accelerate,drift (held all run)
##                and --pulse=hop@3.0,nitro@5.5 (tap action at time t)
##                and --key=space@3.0,f3@1.0 (RAW key press at time t, released 3 frames later — for
##                tools that read raw events instead of actions, e.g. the F3 input quad)
## --times, --pulse and --key all count from the SAME instant: the world ready + warm-up done. The
## clock is the _process delta, i.e. game time.
## Common: --scene=res://main.tscn (default)  --out=<prefix>  --outdir=<abs dir>  --warm=60 (frames
## before each static shot)  --env-only (hide HUD CanvasLayers for art shots)  plus any game option
## (e.g. --stub=traffic --spawn=x,y,z,yaw --debug). Saves <outdir>/<out>_<name>.jpg (JPEG q85),
## prints "CAPTURE <name> fps=<mean over 30 frames>" and "CAPTURE errors=<n>"; exit 1 on errors.

const ErrorCounter := preload("res://tools/error_counter.gd")
const InputSetup := preload("res://core/input_setup.gd")
const Clock := preload("res://tools/capture_clock.gd")

var _opts: Dictionary = {}
var _counter: ErrorCounter
var _cams: Array[Dictionary] = []
var _times: PackedFloat64Array = []
var _pulses: Array[Array] = []
var _keys: Array[Array] = []
var _clock: Clock = Clock.new()
var _cam: Camera3D
var _t: float = 0.0
var _frames: int = 0
var _fps_samples: PackedFloat64Array = []
var _last_usec: int = 0


func _initialize() -> void:
	_counter = ErrorCounter.new()
	OS.add_logger(_counter)
	_opts = _parse(OS.get_cmdline_user_args())
	InputSetup.register_actions()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var scene_path := String(_opts.get("scene", "res://main.tscn"))
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("capture: cannot load " + scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())
	_cams = _parse_cams(String(_opts.get("cams", "")))
	for t in String(_opts.get("times", "")).split(",", false):
		_times.append(float(t))
	for p in String(_opts.get("pulse", "")).split(",", false):
		var parts := p.split("@")
		_pulses.append([StringName(parts[0]), float(parts[1])])
	for k in String(_opts.get("key", "")).split(",", false):
		var parts := k.split("@")
		var code := OS.find_keycode_from_string(parts[0]) as Key
		if code == KEY_NONE:
			push_error("capture: --key= wants a key name, got '%s'" % parts[0])
			quit(1)
			return
		_keys.append([code, float(parts[1])])
	for action in String(_opts.get("press", "")).split(",", false):
		Input.action_press(StringName(action))
	if _cams.is_empty() and _times.is_empty():
		_times.append(3.0)
	_run.call_deferred()


func _run() -> void:
	await _wait_world()
	await _wait_frames(int(_opts.get("warm", "60")))
	if bool(_opts.has("env-only")):
		_hide_canvas_layers(root)
	var game_cam := root.get_viewport().get_camera_3d()
	for cam in _cams:
		await _static_shot(cam)
	if _cam != null and game_cam != null:
		game_cam.make_current()
	_clock.start()
	for t in _times:
		while not _clock.due(t):
			await process_frame
		await _save(_opts.get("out", "shot") + "_t%s" % str(t).replace(".", "_"))
	for line in _counter.first_errors:
		print("CAPTURE ERROR ", line)
	print("CAPTURE errors=%d warnings=%d" % [_counter.errors, _counter.warnings])
	quit(1 if _counter.errors > 0 else 0)


func _process(delta: float) -> bool:
	_t += delta
	_clock.advance(delta)
	_frames += 1
	for p in _pulses:
		if p.size() == 2 and _clock.due(float(p[1])):
			Input.action_press(p[0])
			p.append(_frames)
			print("CAPTURE pulse %s at t=%.2f" % [p[0], _clock.now()])
		elif p.size() == 3 and _frames > int(p[2]) + 2:
			Input.action_release(p[0])
			p.append(true)
	for k in _keys:
		if k.size() == 2 and _clock.due(float(k[1])):
			_key(k[0] as Key, true)
			k.append(_frames)
			print("CAPTURE key %s at t=%.2f" % [OS.get_keycode_string(k[0] as Key), _clock.now()])
		elif k.size() == 3 and _frames > int(k[2]) + 2:
			_key(k[0] as Key, false)
			k.append(true)
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		_fps_samples.append(1e6 / float(maxi(now - _last_usec, 1)))
		if _fps_samples.size() > 30:
			_fps_samples.remove_at(0)
	_last_usec = now
	return false


## A raw key event, so a tool that reads InputEventKey (the F3 input quad) sees it. Input.action_press
## only drives the InputMap and never reaches _input().
func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _static_shot(spec: Dictionary) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.near = 0.05
		_cam.far = 6000.0
		root.add_child(_cam)
	_cam.fov = float(spec.get("fov", 70.0))
	_cam.global_position = spec["pos"]
	_cam.look_at(spec["look"], Vector3.UP)
	_cam.current = true
	await _wait_frames(int(_opts.get("warm", "60")))
	await _save(String(_opts.get("out", "shot")) + "_" + String(spec["name"]))


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var dir := String(_opts.get("outdir", ProjectSettings.globalize_path("res://captures")))
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(name + ".jpg")
	var err := img.save_jpg(path, 0.85)
	var fps := 0.0
	for f in _fps_samples:
		fps += f
	fps /= maxf(float(_fps_samples.size()), 1.0)
	print("CAPTURE %s at t=%.2f fps=%.0f -> %s%s"
			% [name, _clock.now(), fps, path, "" if err == OK else " (SAVE FAILED %d)" % err])


## The real world builds for several seconds; shots before that show an empty map. Scenes without a
## world (unit demo scenes) do not wait.
func _wait_world() -> void:
	var game := root.get_node_or_null("Game")
	if game == null or game.get("world") == null:
		return
	var waited := 0.0
	while not bool(game.call("world_built")) and waited < 120.0:
		await process_frame
		waited += root.get_process_delta_time()
	print("CAPTURE world ready after %.1f s" % waited)


func _wait_frames(n: int) -> void:
	for i in n:
		await process_frame


func _hide_canvas_layers(node: Node) -> void:
	for child in node.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
		_hide_canvas_layers(child)


func _parse_cams(spec: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if spec.ends_with(".json"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(spec))
		for item: Dictionary in (data as Array):
			var p: Array = item["pos"]
			var l: Array = item["look"]
			out.append({"name": item["name"], "pos": Vector3(p[0], p[1], p[2]),
					"look": Vector3(l[0], l[1], l[2]), "fov": float(item.get("fov", 70.0))})
		return out
	for entry in spec.split(";", false):
		var parts := entry.split(":")
		var p := parts[1].split(",")
		var l := parts[2].split(",")
		out.append({"name": parts[0], "pos": Vector3(float(p[0]), float(p[1]), float(p[2])),
				"look": Vector3(float(l[0]), float(l[1]), float(l[2])),
				"fov": float(parts[3]) if parts.size() > 3 else 70.0})
	return out


static func _parse(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for arg in args:
		if not arg.begins_with("--"):
			continue
		var body := arg.substr(2)
		var eq := body.find("=")
		out[body if eq < 0 else body.substr(0, eq)] = "true" if eq < 0 else body.substr(eq + 1)
	return out
