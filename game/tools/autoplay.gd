extends SceneTree
## Scripted play-through for feel reviews, E2E tests and trailer capture (core-owned).
##   tools/godot.sh drive --timeline=res://path/timeline.json [--scene=res://main.tscn]
##        [--shots=1.5,4,8] [--outdir=...] [--out=name] [--log=/abs/telemetry.csv] + game options
## Timeline JSON array, events sorted by "t" (seconds after the world is ready):
##   {"t": 0.0, "press": ["move_forward"]}        hold actions        {"t": 2.0, "release": [...]}
##   {"t": 3.0, "tap": ["dodge"]}                 press for 3 frames  {"t": 9.0, "end": true}
##   {"t": 1.0, "look": [dx, dy]}                 one relative mouse motion (pixels)
##   {"t": 1.0, "look_rate": [dx, dy]}            mouse motion per second until changed ([0,0] stops)
##   {"t": 1.0, "player": {"method": "debug_teleport", "args": [[x, y, z], yaw]}}  call on Game.player
##   {"t": 1.0, "pad": {"button": "rb", "down": true}}   RAW pad button, through PadInput + the InputMap
##          buttons: a b x y lb rb l3 r3 dpad_up dpad_down dpad_left dpad_right view menu
##   {"t": 1.0, "pad": {"axis": ["rt", 1.0]}}            RAW pad axis (-1..1)
##          axes: lx ly rx ry lt rt
##   {"t": 1.0, "dpad": "right", "hold": 0.08}           the D-pad, with the left stick at rest for the press
##   {"t": 1.0, "chord": "y", "hold": 0.08}              RB held around a face button (the shift layer)
##   Raw pad steps exist because Input.action_press only drives the InputMap: nothing a drive did could
##   reach PadInput (the shift layer, the L3+R3 chord, the D-pad tap/hold), so no scripted run ever
##   exercised the pad path.
## Telemetry: Game.player.telemetry() -> Dictionary (flat, numbers/strings). Prints "DRIVE t=.. k=v .."
## every 0.5 s and writes every physics frame to --log as CSV (header = sorted keys of the first row).
## --frametimes : log WALL-clock frame deltas (drive mode only — movies have perfect pacing by design) and print
##   "FRAMETIME p50 p95 p99 max hitches>25ms" at the end, plus the load average if given via --load=.
## --nan-watch : scan the tree every frame and print the first Node3Ds with non-finite or degenerate
##   transforms ("NANWATCH ..." lines, tools/nan_watch.gd) — for engine warnings that carry no backtrace.
## Exit 1 on engine errors. For video use tools/godot.sh movie (same options + --movie=/abs/out.avi).

const ErrorCounter := preload("res://tools/error_counter.gd")
const NanWatch := preload("res://tools/nan_watch.gd")
const InputSetup := preload("res://core/input_setup.gd")
const WORLD_WAIT_MAX := 120.0
## Timeline names -> JoyButton / JoyAxis, so a drive reads like a pad diagram instead of magic numbers.
const PAD_BUTTONS: Dictionary = {
	"a": JOY_BUTTON_A, "b": JOY_BUTTON_B, "x": JOY_BUTTON_X, "y": JOY_BUTTON_Y,
	"lb": JOY_BUTTON_LEFT_SHOULDER, "rb": JOY_BUTTON_RIGHT_SHOULDER,
	"l3": JOY_BUTTON_LEFT_STICK, "r3": JOY_BUTTON_RIGHT_STICK,
	"dpad_up": JOY_BUTTON_DPAD_UP, "dpad_down": JOY_BUTTON_DPAD_DOWN,
	"dpad_left": JOY_BUTTON_DPAD_LEFT, "dpad_right": JOY_BUTTON_DPAD_RIGHT,
	"view": JOY_BUTTON_BACK, "menu": JOY_BUTTON_START,
}
const PAD_AXES: Dictionary = {
	"lx": JOY_AXIS_LEFT_X, "ly": JOY_AXIS_LEFT_Y, "rx": JOY_AXIS_RIGHT_X, "ry": JOY_AXIS_RIGHT_Y,
	"lt": JOY_AXIS_TRIGGER_LEFT, "rt": JOY_AXIS_TRIGGER_RIGHT,
}

var _opts: Dictionary = {}
var _counter: ErrorCounter
var _events: Array = []
var _next: int = 0
var _t: float = 0.0
var _end_t: float = 30.0
var _taps: Dictionary = {}  # action -> frames left
var _look_rate: Vector2 = Vector2.ZERO
var _shots: PackedFloat64Array = []
var _log: FileAccess
var _log_keys: PackedStringArray = []
var _next_print: float = 0.0
var _world_waited: float = 0.0
var _frame_us: PackedInt64Array = []
var _last_frame_us: int = 0
var _nan_watch: NanWatch = null
var _scheduled: Array = []   ## [[due_t, Callable], ...] — the halves of a dpad/chord step
var _stick: Vector2 = Vector2.ZERO


func _initialize() -> void:
	_counter = ErrorCounter.new()
	OS.add_logger(_counter)
	InputSetup.register_actions()
	# A windowed run whose window is covered or hidden stops drawing and sits at 0 % CPU, holding its
	# heavy slot until the slot timeout: macOS pauses the window's display link when the window is not
	# visible, and acceptance lost two runs to it (run_district_try1_stalled.log, feel_frames2.log).
	# With vsync off Godot paces on its own max_fps limiter instead of that display link. capture.gd,
	# smoke_run.gd and perf_probe.gd already did this; drive and movie did not, and they are the two
	# that stalled.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var eq := arg.find("=")
			_opts[arg.substr(2, eq - 2) if eq > 0 else arg.substr(2)] = arg.substr(eq + 1) if eq > 0 else "true"
	_events = _load_timeline(String(_opts.get("timeline", "")))
	for s in String(_opts.get("shots", "")).split(",", false):
		_shots.append(float(s))
	if _opts.has("log"):
		_log = FileAccess.open(String(_opts["log"]), FileAccess.WRITE)
	if _opts.has("nan-watch"):
		_nan_watch = NanWatch.new()
	if _opts.has("always-on-top"):
		# Opt-in: keeps the window above ordinary windows. It does NOT survive a full-screen movie or
		# Stage Manager (both are separate Spaces), which is why the vsync line above is the real fix.
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	var packed := load(String(_opts.get("scene", "res://main.tscn"))) as PackedScene
	if packed == null:
		push_error("drive: cannot load scene " + String(_opts.get("scene", "res://main.tscn")))
		quit(1)
		return
	root.add_child(packed.instantiate())


func _load_timeline(path: String) -> Array:
	if path == "":
		push_error("drive: --timeline=res://... required")
		return []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Array:
		push_error("drive: timeline is not a JSON array: " + path)
		return []
	for ev: Dictionary in (data as Array):
		if ev.get("end", false):
			_end_t = float(ev["t"])
	return data as Array


func _process(delta: float) -> bool:
	if not _world_ready(delta):
		return false
	_t += delta
	_track_frame()
	while _next < _events.size() and float((_events[_next] as Dictionary)["t"]) <= _t:
		_apply(_events[_next] as Dictionary)
		_next += 1
	for action: StringName in _taps.keys():
		_taps[action] = int(_taps[action]) - 1
		if int(_taps[action]) <= 0:
			Input.action_release(action)
			_taps.erase(action)
	if _look_rate != Vector2.ZERO:
		_mouse_motion(_look_rate * delta)
	if not _shots.is_empty() and _t >= _shots[0]:
		_shots.remove_at(0)
		_shot.call_deferred(_t)
	_tick_scheduled()
	_telemetry()
	if _nan_watch != null:
		_nan_watch.scan(root, _t)
	if _t >= _end_t:
		_finish()
		return true
	return false


func _apply(ev: Dictionary) -> void:
	for a: String in ev.get("press", []):
		Input.action_press(StringName(a))
	for a: String in ev.get("release", []):
		Input.action_release(StringName(a))
	for a: String in ev.get("tap", []):
		Input.action_press(StringName(a))
		_taps[StringName(a)] = 3
	if ev.has("look"):
		_mouse_motion(Vector2(float(ev["look"][0]), float(ev["look"][1])))
	if ev.has("look_rate"):
		_look_rate = Vector2(float(ev["look_rate"][0]), float(ev["look_rate"][1]))
	if ev.has("player"):
		_call_player(ev["player"] as Dictionary)
	if ev.has("pad"):
		_pad(ev["pad"] as Dictionary)
	if ev.has("dpad"):
		_dpad(String(ev["dpad"]), float(ev.get("hold", 0.08)))
	if ev.has("chord"):
		_chord(String(ev["chord"]), float(ev.get("hold", 0.08)))


## Raw joypad event through Input.parse_input_event: PadInput sees it and turns it into actions, which
## is the whole point (the shift layer, chords and D-pad tap/hold live there).
## Runs the scheduled halves of a `dpad` / `chord` step once their time comes: those steps span frames,
## and a drive applies each timeline entry in a single one.
func _tick_scheduled() -> void:
	var i := 0
	while i < _scheduled.size():
		if _t >= float(_scheduled[i][0]):
			(_scheduled[i][1] as Callable).call()
			_scheduled.remove_at(i)
		else:
			i += 1


func _at(offset: float, fn: Callable) -> void:
	_scheduled.append([_t + offset, fn])


func _pad_button(name: String) -> int:
	return PAD_BUTTONS.get(name, JOY_BUTTON_INVALID)


func _btn(b: int, down: bool) -> void:
	if b == JOY_BUTTON_INVALID:
		return
	var e := InputEventJoypadButton.new()
	e.button_index = b as JoyButton
	e.pressed = down
	Input.parse_input_event(e)


func _axis_send(a: int, v: float) -> void:
	if a == JOY_AXIS_INVALID:
		return
	var m := InputEventJoypadMotion.new()
	m.axis = a as JoyAxis
	m.axis_value = v
	Input.parse_input_event(m)


## The left thumb has to move to the D-pad, so the stick goes to rest for the press and comes back after.
func _dpad(name: String, hold: float) -> void:
	var keep := _stick
	_stick = Vector2.ZERO
	_axis_send(JOY_AXIS_LEFT_X, 0.0)
	_axis_send(JOY_AXIS_LEFT_Y, 0.0)
	var b := _pad_button("dpad_" + name)
	_at(1.0 / 60.0, func() -> void: _btn(b, true))
	_at(1.0 / 60.0 + hold, func() -> void: _btn(b, false))
	_at(1.0 / 30.0 + hold, func() -> void:
			_axis_send(JOY_AXIS_LEFT_X, keep.x)
			_axis_send(JOY_AXIS_LEFT_Y, keep.y)
			_stick = keep)


## RB is a pure shift layer: it goes down, the face button is pressed under it, and the button keeps its
## shifted action until it is released.
func _chord(name: String, hold: float) -> void:
	var rb := _pad_button("rb")
	var b := _pad_button(name)
	_btn(rb, true)
	_at(0.03, func() -> void: _btn(b, true))
	_at(0.03 + hold, func() -> void: _btn(b, false))
	_at(0.06 + hold, func() -> void: _btn(rb, false))


func _pad(spec: Dictionary) -> void:
	if spec.has("button"):
		var b: int = PAD_BUTTONS.get(String(spec["button"]), JOY_BUTTON_INVALID)
		if b == JOY_BUTTON_INVALID:
			push_error("drive: unknown pad button '%s'" % spec["button"])
			return
		_btn(b, bool(spec.get("down", true)))
	elif spec.has("axis"):
		var a: Array = spec["axis"]
		var ax: int = PAD_AXES.get(String(a[0]), JOY_AXIS_INVALID)
		if ax == JOY_AXIS_INVALID:
			push_error("drive: unknown pad axis '%s'" % a[0])
			return
		var value := float(a[1])
		match String(a[0]):
			"lx": _stick.x = value
			"ly": _stick.y = value
		_axis_send(ax, value)
	else:
		push_error("drive: a pad step needs 'button' or 'axis': " + str(spec))


func _mouse_motion(rel: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.relative = rel
	mm.screen_relative = rel
	Input.parse_input_event(mm)


func _player() -> Node3D:
	# Autoloads are not compile-time identifiers inside a SceneTree script: look the node up.
	var game := root.get_node_or_null(^"Game")
	return game.get(&"player") as Node3D if game != null else null


func _call_player(spec: Dictionary) -> void:
	var p := _player()
	if p == null or not p.has_method(StringName(spec.get("method", ""))):
		push_error("drive: player has no method %s" % spec.get("method", ""))
		return
	p.callv(StringName(spec["method"]), spec.get("args", []))


func _telemetry() -> void:
	var p := _player()
	if p == null or not p.has_method(&"telemetry"):
		return
	var row: Dictionary = p.call(&"telemetry")
	if _log != null:
		if _log_keys.is_empty():
			_log_keys = PackedStringArray(row.keys())
			_log_keys.sort()
			_log.store_line("t," + ",".join(_log_keys))
		var vals: PackedStringArray = ["%.3f" % _t]
		for k in _log_keys:
			vals.append(str(row.get(k, "")))
		_log.store_line(",".join(vals))
	if _t >= _next_print:
		_next_print += 0.5
		var parts: PackedStringArray = []
		for k: String in row:
			var v: Variant = row[k]
			parts.append("%s=%s" % [k, ("%.2f" % v) if v is float else str(v)])
		print("DRIVE t=%.1f %s" % [_t, " ".join(parts)])


func _shot(at: float) -> void:
	await RenderingServer.frame_post_draw
	var dir := String(_opts.get("outdir", ProjectSettings.globalize_path("res://captures")))
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("%s_t%s.jpg" % [String(_opts.get("out", "drive")), str(snappedf(at, 0.1)).replace(".", "_")])
	root.get_viewport().get_texture().get_image().save_jpg(path, 0.85)
	print("DRIVE shot -> ", path)


func _track_frame() -> void:
	if not _opts.has("frametimes"):
		return
	var now := Time.get_ticks_usec()
	if _last_frame_us > 0:
		_frame_us.append(now - _last_frame_us)
	_last_frame_us = now


func _report_frametimes() -> void:
	if _frame_us.size() < 10:
		return
	var v := _frame_us.duplicate()
	v.sort()
	var pct := func(p: float) -> float: return float(v[mini(int(p * float(v.size())), v.size() - 1)]) / 1000.0
	var hitches := 0
	for us in v:
		if us > 25000:
			hitches += 1
	print("FRAMETIME frames=%d p50=%.1fms p95=%.1fms p99=%.1fms max=%.1fms hitches>25ms=%d %s" % [v.size(),
			pct.call(0.5), pct.call(0.95), pct.call(0.99), float(v[-1]) / 1000.0, hitches, String(_opts.get("load", ""))])


func _finish() -> void:
	_report_frametimes()
	if _log != null:
		_log.close()
	for line in _counter.first_errors:
		print("DRIVE ERROR ", line)
	print("DRIVE done t=%.1f errors=%d warnings=%d" % [_t, _counter.errors, _counter.warnings])
	quit(1 if _counter.errors > 0 else 0)


## The timeline starts once the world is built (Game.world_built()); scenes without a world start at
## once; a stuck build starts anyway after WORLD_WAIT_MAX s.
func _world_ready(delta: float) -> bool:
	if _world_waited < 0.0:
		return true
	_world_waited += delta
	var game := root.get_node_or_null(^"Game")
	if game == null or game.get(&"world") == null or bool(game.call(&"world_built")) \
			or _world_waited > WORLD_WAIT_MAX:
		print("DRIVE world ready after %.1f s" % _world_waited)
		_world_waited = -1.0
		return true
	return false
