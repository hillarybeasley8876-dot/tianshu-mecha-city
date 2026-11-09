extends Node3D
## 60 fps filmstrips and the fixed-camera walk movie for the Tianshu gait (hero-v3, brief gate).
##
##   tools/godot.sh shot --scene=res://player/model/hero3/hero3_strip.tscn \
##       --strip=walk --views=front,side --out=hero3_strip_walk
##   tools/godot.sh shot --scene=res://player/model/hero3/hero3_strip.tscn \
##       --strip=walk --fixed --seconds=4 --out=hero3_walk_side
##
## The mech is driven by hand at a FIXED 1/60 s step and the Stage moves at the real ground speed, so
## a run is deterministic. The eight strip frames are PHASE-ALIGNED: the shoot waits for the gait
## phase to cross 0 and then samples one full left-right cycle (two steps) at even intervals, so the
## sheet shows one cycle rather than eight unrelated moments.
##
## `--fixed` puts the camera in WORLD space instead of on the Stage, which is the only way to see
## whether a planted foot stays put while the body passes over it.

const MODEL := "res://player/model/hero3/hero3_model.tscn"
const FRAMES := 8
const DT := 1.0 / 60.0
const WARM_STEPS := 150        ## let the crouch blend in and the gait settle into its rhythm
## speed, stick (x = strafe, y = forward; the model faces -Z), and whether the Stage also turns
const STRIPS: Dictionary = {
	"walk": {"speed": 9.0, "input": Vector2(0.0, -1.0), "state": &"walk", "turn": 0.0},
	"run": {"speed": 16.0, "input": Vector2(0.0, -1.0), "state": &"run", "turn": 0.0},
	"strafe": {"speed": 9.0, "input": Vector2(-1.0, 0.0), "state": &"walk", "turn": 0.0},
	"back": {"speed": 9.0, "input": Vector2(0.0, 1.0), "state": &"walk", "turn": 0.0},
	"turn": {"speed": 0.0, "input": Vector2.ZERO, "state": &"idle", "turn": 55.0},
}
## camera offsets in the Stage's frame: the mech faces -Z, so "front" is at -Z looking back
const VIEWS: Dictionary = {
	"front": Vector3(0.0, 8.0, -46.0),
	"side": Vector3(46.0, 8.0, 0.0),
	"rear34": Vector3(-30.0, 12.0, 34.0),
}
## The fixed world camera for the movie: far enough back that 4 s of walking stays in frame, narrow
## enough that a 16 m mech still fills half the height.
const FIXED_CAM := Vector3(58.0, 8.0, -18.0)
const FIXED_FOV := 30.0

var _stage: Node3D
var _model: Node3D
var _gait: Hero3Gait
var _cam: Camera3D
var _out: String = "hero3_strip"
var _views: PackedStringArray = PackedStringArray(["front", "side"])
var _strip: String = "walk"
var _fixed: bool = false
var _seconds: float = 0.0


func _ready() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	_strip = String(args.get("strip", "walk"))
	_out = String(args.get("out", "hero3_strip_%s" % _strip))
	_views = PackedStringArray(String(args.get("views", "front,side")).split(",", false))
	_fixed = args.has("fixed")
	_seconds = float(args.get("seconds", "0"))
	if not STRIPS.has(_strip):
		push_error("hero3_strip: unknown strip %s (have %s)" % [_strip, STRIPS.keys()])
		get_tree().quit(1)
		return
	_build()
	if _fixed:
		_shoot_movie.call_deferred()
	else:
		_shoot.call_deferred()


func _build() -> void:
	var spec: Dictionary = STRIPS[_strip]
	_stage = Node3D.new()
	_stage.name = "Stage"
	add_child(_stage)
	_model = (load(MODEL) as PackedScene).instantiate()
	# the strip drives the gait by hand at a fixed step, so the model's own _physics_process must not
	# also run it: two drivers at different deltas is how the legs ended up nowhere
	_model.process_mode = Node.PROCESS_MODE_DISABLED
	_stage.add_child(_model)
	_cam = Camera3D.new()
	_cam.near = 0.1
	_cam.far = 900.0
	_cam.fov = FIXED_FOV if _fixed else 42.0
	if _fixed:
		add_child(_cam)
	else:
		_stage.add_child(_cam)
	_cam.current = true
	# a light ON the camera: the armour is matte graphite, and without it the legs read as a silhouette
	var lamp := DirectionalLight3D.new()
	lamp.light_energy = 2.2
	lamp.light_color = Color(1.0, 0.97, 0.92)
	lamp.shadow_enabled = false
	_cam.add_child(lamp)
	lamp.rotation_degrees = Vector3(-18.0, 0.0, 0.0)
	_gait = _model.gait
	_model.set_locomotion(spec["state"], float(spec["speed"]), spec["input"])
	print("STRIP %s speed %.1f input %s turn %.0f deg/s"
			% [_strip, spec["speed"], spec["input"], spec["turn"]])


## One fixed step of the world: the Stage moves (and turns) at the commanded rate, then the gait runs.
func _step(spec: Dictionary) -> void:
	var speed := float(spec["speed"])
	var input: Vector2 = spec["input"]
	if speed > 0.0 and input.length() > 0.01:
		_stage.position += _stage.basis * Vector3(input.x, 0.0, input.y).normalized() * speed * DT
	var turn := float(spec["turn"])
	if turn != 0.0:
		_stage.rotate_y(deg_to_rad(turn) * DT)
	_gait.update(DT)


## Run forward until the gait phase crosses zero, so every view and every rerun samples the SAME
## eight moments of the SAME cycle.
func _align(spec: Dictionary) -> void:
	for i in WARM_STEPS:
		_step(spec)
	var last := float(_gait.report()["phase"])
	for i in 600:
		_step(spec)
		var now := float(_gait.report()["phase"])
		if now < last:
			return
		last = now


func _shoot() -> void:
	var spec: Dictionary = STRIPS[_strip]
	_align(spec)
	var period := float(_gait.report()["cycle"]) * 2.0
	var per_frame := maxf(period / float(FRAMES), DT)
	_print_metrics(period)
	for view in _views:
		_cam.position = VIEWS.get(view, VIEWS["side"])
		_cam.look_at(_stage.to_global(Vector3(0.0, 8.0, 0.0)), Vector3.UP)
		_stage.position = Vector3.ZERO
		_stage.rotation = Vector3.ZERO
		_gait.reset()
		_align(spec)
		for frame in FRAMES:
			var target := float(frame) * per_frame
			var elapsed := 0.0
			while elapsed < target:
				_step(spec)
				elapsed += DT
			await _save("%s_%s_%d" % [_out, view, frame])
	print("STRIP done")
	get_tree().quit(0)


## The lead judges the walk from a camera that does NOT travel with the mech: a planted foot has to
## visibly stay put on the ground while the body passes over it. Writes one jpg per frame; ffmpeg
## turns the sequence into the movie.
func _shoot_movie() -> void:
	var spec: Dictionary = STRIPS[_strip]
	_align(spec)
	_print_metrics(float(_gait.report()["cycle"]) * 2.0)
	# the camera is placed where the mech IS after the warm-up, then never moves again: that is the
	# whole point of the shot. (Placing it before the warm-up put the mech 30 m out of frame.)
	var start := _stage.position
	_cam.position = start + FIXED_CAM
	_cam.look_at(start + Vector3(0.0, 8.0, -18.0), Vector3.UP)
	var frames := int(_seconds / DT)
	for frame in frames:
		_step(spec)
		await _save("%s_%04d" % [_out, frame])
	print("MOVIE %d frames -> captures/%s_%%04d.jpg" % [frames, _out])
	get_tree().quit(0)


## The numbers the lead asked to read off each strip (r2 item 4): stride, cadence, double support
## and pelvis height. Sampled over two full cycles so they are the gait's, not one step's.
func _print_metrics(period: float) -> void:
	var spec: Dictionary = STRIPS[_strip]
	var ticks := int(period * 2.0 / DT)
	var double_support := 0
	var flight := 0
	var lo := INF
	var hi := -INF
	for i in ticks:
		_step(spec)
		var support := _gait.support_count()
		double_support += 1 if support == 2 else 0
		flight += 1 if support == 0 else 0
		lo = minf(lo, _gait.pelvis_height())
		hi = maxf(hi, _gait.pelvis_height())
	var rep := _gait.report()
	print(("STRIP %s  stride %.2f m  cadence %.2f steps/s  cycle %.3f s  double support %.0f%%  "
			+ "flight %.0f%%  pelvis %.2f..%.2f m  dip %.2f m  body yaw %.0f deg")
			% [_strip, float(rep["stride"]), float(rep["cadence"]), float(rep["cycle"]),
			100.0 * float(double_support) / float(ticks), 100.0 * float(flight) / float(ticks),
			lo, hi, hi - lo, float(rep["yaw"])])


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://../captures")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(name + ".jpg")
	var err := image.save_jpg(path, 0.86)
	if err != OK:
		push_error("hero3_strip: could not write %s (error %d)" % [path, err])


static func _parse(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for arg in args:
		if not arg.begins_with("--"):
			continue
		var body := arg.substr(2)
		var eq := body.find("=")
		out[body if eq < 0 else body.substr(0, eq)] = "true" if eq < 0 else body.substr(eq + 1)
	return out
