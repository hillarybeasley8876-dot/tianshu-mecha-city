extends Node3D
## 60 fps filmstrips of the Tianshu ACTION clips and MOVE STATES (hero-v3, lead r4 item 10).
##
##   tools/godot.sh shot --scene=res://player/model/hero3/hero3_action_strip.tscn \
##       --seq=melee_l1,melee_l2,melee_l3 --cancel --out=hero3_act_melee
##   tools/godot.sh shot --scene=res://player/model/hero3/hero3_action_strip.tscn \
##       --state=dash_f --speed=150 --fixed --out=hero3_act_dash_f
##   tools/godot.sh shot --scene=res://player/model/hero3/hero3_action_strip.tscn \
##       --seq=fire_r --aim=20,15 --out=hero3_act_fire_aim
##
## `--seq` is a comma-separated string of action ids. `--cancel` chains them at the EARLIEST cancel
## frame `melee_table.gd` allows instead of at each clip's end, which is what the game does.
## `--state`/`--speed` drive `set_locomotion` instead, for the move states the game never calls
## `play_action` for. `--walk` drives the gait underneath an upper-body clip. `--fixed` puts the camera
## in WORLD space so the feet can be judged against the floor while the stage moves. `--aim=yaw,pitch`
## sets an aim point 200 m out.
##
## Two more modes cover the brief's other capture gates:
##   --mode=turn   a lit turntable, 8 frames at 45 deg
##   --mode=poses  the four stress poses the interpenetration gate is measured on
##
## The warm-up runs the GAIT FIRST and only then starts the clip at frame 0. The first version played
## the clip and then ran 90 warm-up ticks, which consumed it -- that is why the dash and jump strips
## were identical and the melee strip's first frames did not move (lead r4 item 10).

const MODEL := "res://player/model/hero3/hero3_model.tscn"
const FRAMES := 8
const DT := 1.0 / 60.0
const CHAIN_BLEND := 0.06
const WARM := 90
const RANGE := 200.0
## The reference floor. A fixed world camera is only evidence if there is something in the world to
## judge the feet against, so the strip lays a grid down: one tile is TILE metres and the lines are
## every TILE/8, which puts a line under the foot every 2 m at the default 16 m tile.
const FLOOR_SIZE := 600.0
const TILE := 16.0
const GRID_PX := 256
const GRID_DIV := 8
const VIEWS: Dictionary = {
	"front": Vector3(0.0, 9.0, -38.0),
	"side": Vector3(38.0, 9.0, 0.0),
	"rear34": Vector3(-26.0, 12.0, 28.0),
	# close-ups for the interpenetration gate: the two places it reports a crossing
	"knee": Vector3(16.0, 3.0, 0.0),
	"head": Vector3(14.0, 16.0, 0.0),
	"headfront": Vector3(0.0, 16.0, -15.0),
	"neck": Vector3(11.0, 14.5, 9.0),
	"neckrear": Vector3(-9.0, 14.5, 11.0),
}
## How high each view aims, in metres. A close-up of the knee is useless if the camera looks at the chest.
const LOOK: Dictionary = {"knee": 3.0, "head": 15.5, "headfront": 15.5, "neck": 14.5, "neckrear": 14.5}
## The four stress poses: the ones where armour plates are most likely to pass through each other.
const POSES: Array = [
	["rest", &"", 0.0],
	["crouch", &"", 9.0],
	["guard", &"guard_up", 0.0],
	["follow", &"melee_l1", 0.0],
]

var _stage: Node3D
var _model: Node3D
var _gait: Hero3Gait
var _clips: Hero3ClipPlayer
var _cam: Camera3D
var _table: GDScript
var _out: String = "hero3_act"
var _views: PackedStringArray = PackedStringArray(["front", "side"])
var _seq: Array[StringName] = []
var _walk: float = 0.0
var _speed: float = 0.0
var _state: StringName = &""
var _fixed: bool = false
var _cancel: bool = false
var _aim: Vector2 = Vector2.ZERO
var _seconds: float = 0.0
var _dist: float = 1.0
## `--then=state,speed,at` switches the locomotion mid-strip: a dash that coasts is one shot, not two.
var _then: Array = []
var _switched: bool = false
## The speed the STAGE is driven at, which follows the locomotion state rather than the `--speed` flag:
## a dash that coasts has to decelerate on the floor too, or the strip shows a 150 m/s slide.
var _drive: float = 0.0
## The warm-up runs the gait in place. Moving the stage while warming put the mech 225 m downrange
## before the first frame was ever taken.
var _warming: bool = false
var _index: int = 0
var _elapsed: float = 0.0
var _mode: String = "seq"


func _ready() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	_out = String(args.get("out", "hero3_act"))
	_views = PackedStringArray(String(args.get("views", "front,side")).split(",", false))
	_walk = float(args.get("walk", "0"))
	_speed = float(args.get("speed", "0"))
	_state = StringName(String(args.get("state", "")))
	_fixed = args.has("fixed")
	_cancel = args.has("cancel")
	_seconds = float(args.get("seconds", "0"))
	_dist = float(args.get("dist", "1"))
	_mode = String(args.get("mode", "seq"))
	var then := String(args.get("then", "")).split(",", false)
	if then.size() == 3:
		_then = [StringName(then[0]), float(then[1]), float(then[2])]
	var aim := String(args.get("aim", "")).split(",", false)
	if aim.size() == 2:
		_aim = Vector2(float(aim[0]), float(aim[1]))
	for id in String(args.get("seq", "")).split(",", false):
		_seq.append(StringName(id))
	if _seq.is_empty() and _state == &"" and _mode == "seq":
		push_error("hero3_action_strip: --seq and --state are both empty")
		get_tree().quit(1)
		return
	_table = load("res://combat/melee/melee_table.gd")
	_build()
	match _mode:
		"turn":
			_turntable.call_deferred()
		"poses":
			_poses.call_deferred()
		_:
			_shoot.call_deferred()


func _build() -> void:
	_stage = Node3D.new()
	_stage.name = "Stage"
	add_child(_stage)
	_model = (load(MODEL) as PackedScene).instantiate()
	# the strip drives the model by hand at a fixed step, so its own _physics_process must not also
	# run it: two drivers at different deltas is how the legs ended up nowhere
	_model.process_mode = Node.PROCESS_MODE_DISABLED
	_stage.add_child(_model)
	_cam = Camera3D.new()
	_cam.near = 0.1
	_cam.far = 900.0
	_cam.fov = 38.0
	# `--fixed` hangs the camera off the ROOT, so it stays in world space while the stage walks past it
	(_stage if not _fixed else self).add_child(_cam)
	_cam.current = true
	var lamp := DirectionalLight3D.new()
	lamp.light_energy = 2.2
	lamp.light_color = Color(1.0, 0.97, 0.92)
	lamp.shadow_enabled = false
	_cam.add_child(lamp)
	lamp.rotation_degrees = Vector3(-18.0, 0.0, 0.0)
	_gait = _model.gait
	_clips = _model.clips
	_floor()
	_apply_aim()
	print("ACT %s  %d clips  state '%s'  walk %.0f  speed %.0f  fixed %s  cancel %s"
			% [_out, _seq.size(), _state, _walk, _speed, _fixed, _cancel])


## A grid floor in WORLD space. A fixed camera is only evidence if the world has something in it to
## judge the feet against, and the first strips had the mech floating in a void.
func _floor() -> void:
	var image := Image.create(GRID_PX, GRID_PX, false, Image.FORMAT_RGB8)
	image.fill(Color(0.16, 0.17, 0.19))
	var step := GRID_PX / GRID_DIV
	for i in GRID_DIV:
		var shade := Color(0.34, 0.35, 0.38) if i % 2 == 0 else Color(0.24, 0.25, 0.28)
		for j in GRID_PX:
			image.set_pixel(i * step, j, shade)
			image.set_pixel(j, i * step, shade)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(image)
	mat.uv1_scale = Vector3(FLOOR_SIZE / TILE, FLOOR_SIZE / TILE, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.95
	var plane := PlaneMesh.new()
	plane.size = Vector2(FLOOR_SIZE, FLOOR_SIZE)
	var mesh := MeshInstance3D.new()
	mesh.mesh = plane
	mesh.material_override = mat
	add_child(mesh)


## One fixed step, in the order `Hero3Model._physics_process` uses: the clip clock, then the gait
## (which reads the clip's root and foot targets), then the clip's own bones.
func _step() -> void:
	if not _warming and _drive > 0.0:
		_stage.position += Vector3(0.0, 0.0, -1.0) * _drive * DT
	# `_warming` matters here: the warm-up ticks advance `_elapsed` too, so without it a `--then` at
	# 0.30 s fired on warm-up tick 18 and the strip showed the coast and never the dash.
	if _then.size() == 3 and not _switched and not _warming and _elapsed >= float(_then[2]):
		_switched = true
		_drive = float(_then[1])
		_model.set_locomotion(_then[0], _drive,
				Vector2(0.0, -1.0) if _drive > 0.0 else Vector2.ZERO)
	_clips.update(DT)
	_gait.update(DT)
	_clips.apply()
	_model.rig.update(DT)
	_elapsed += DT
	if _cancel:
		_cancel_step()
	elif _index < _seq.size() - 1 and _elapsed >= _clips.length_of(_seq[_index]):
		_index += 1
		_elapsed = 0.0
		_model.play_action(_seq[_index], CHAIN_BLEND)


## The game chains a combo at the earliest frame `melee_table.gd` allows, not at the clip's end.
func _cancel_step() -> void:
	if _index >= _seq.size() - 1:
		return
	var id := _seq[_index]
	if not _table.has_move(id):
		if _elapsed >= _clips.length_of(id):
			_index += 1
			_elapsed = 0.0
			_model.play_action(_seq[_index], CHAIN_BLEND)
		return
	if _elapsed * 60.0 >= _table.field(id, "cancel_from"):
		_index += 1
		_elapsed = 0.0
		_model.play_action(_seq[_index], CHAIN_BLEND)


func _apply_aim() -> void:
	if _aim == Vector2.ZERO:
		_model.set_aim(Vector3.ZERO, 0.0)
		return
	var dir := Vector3(0.0, 0.0, -1.0).rotated(Vector3.RIGHT, deg_to_rad(_aim.y)) \
			.rotated(Vector3.UP, deg_to_rad(-_aim.x))
	_model.set_aim(Vector3(0.0, 12.0, 0.0) + dir * RANGE, 1.0)


## Warm the GAIT up first, and only then start the clip at frame 0.
func _restart() -> void:
	_stage.position = Vector3.ZERO
	_index = 0
	_elapsed = 0.0
	_switched = false
	_model.stop_action()
	_apply_aim()
	_drive = _speed if _state != &"" else _walk
	if _state != &"":
		_model.set_locomotion(_state, _speed, Vector2(0.0, -1.0) if _speed > 0.0 else Vector2.ZERO)
	elif _walk > 0.0:
		_model.set_locomotion(&"walk", _walk, Vector2(0.0, -1.0))
	else:
		_model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	_gait.reset()
	_warming = true
	for i in WARM:
		_step()
	_warming = false
	_stage.position = Vector3.ZERO
	_elapsed = 0.0
	if not _seq.is_empty():
		_model.play_action(_seq[0], 0.0)
		_step()
		_elapsed = 0.0


## How long the whole sequence runs, in seconds.
func _total() -> float:
	if _seconds > 0.0:
		return _seconds
	if _state != &"":
		return 1.2
	if _walk > 0.0:
		return 1.2
	var total := 0.0
	for i in _seq.size():
		var id := _seq[i]
		if _cancel and _table.has_move(id) and i < _seq.size() - 1:
			total += _table.field(id, "cancel_from") / 60.0
		else:
			total += _clips.length_of(id)
	return total


func _shoot() -> void:
	var total := _total()
	for view in _views:
		_cam.position = VIEWS.get(view, VIEWS["side"]) * _dist
		_cam.look_at(_cam.get_parent().to_global(Vector3(0.0, LOOK.get(view, 8.0), 0.0)), Vector3.UP)
		_restart()
		for frame in FRAMES:
			var target := total * float(frame) / float(FRAMES)
			while _sequence_time() < target:
				_step()
			if not _fixed:
				_cam.look_at(_stage.to_global(Vector3(0.0, LOOK.get(view, 8.0), 0.0)), Vector3.UP)
			print("ACT   %s frame %d  t=%.2f  stage z=%.1f  cam=%s" % [view, frame, _sequence_time(),
					_stage.position.z, _cam.position])
			await _save("%s_%s_%d" % [_out, view, frame])
	print("ACT done")
	get_tree().quit(0)


## How far into the whole sequence we are, in seconds.
func _sequence_time() -> float:
	if _state != &"" or _seconds > 0.0:
		return _elapsed
	var done := 0.0
	for i in _index:
		var id := _seq[i]
		done += (_table.field(id, "cancel_from") / 60.0) if (_cancel and _table.has_move(id)) \
				else _clips.length_of(id)
	return done + _elapsed


## A lit turntable: eight frames, 45 deg apart, camera fixed on the mech.
func _turntable() -> void:
	_model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	_model.set_aim(Vector3.ZERO, 0.0)
	_gait.reset()
	for i in 60:
		_step()
	_cam.position = Vector3(0.0, 9.0, -40.0)
	_cam.fov = 34.0
	for frame in FRAMES:
		_cam.position = Vector3(0.0, 9.0, -40.0).rotated(Vector3.UP, TAU * float(frame) / float(FRAMES))
		_cam.look_at(_stage.to_global(Vector3(0.0, 8.0, 0.0)), Vector3.UP)
		await _save("%s_%d" % [_out, frame])
	print("TURN done")
	get_tree().quit(0)


## The four stress poses, front and side: the stills the interpenetration gate is read from.
func _poses() -> void:
	_cam.fov = 34.0
	for pose: Array in POSES:
		for view in _views:
			_cam.position = VIEWS.get(view, VIEWS["side"]) * _dist
			_cam.look_at(_stage.to_global(Vector3(0.0, LOOK.get(view, 8.0), 0.0)), Vector3.UP)
			_model.set_locomotion(&"walk" if float(pose[2]) > 0.0 else &"idle", float(pose[2]),
					Vector2(0.0, -1.0) if float(pose[2]) > 0.0 else Vector2.ZERO)
			_model.set_aim(Vector3.ZERO, 0.0)
			_gait.reset()
			_model.stop_action()
			for i in 150:
				_step()
			if String(pose[1]) != "":
				_model.play_action(pose[1], 0.0)
				# hold the pose at its most extreme: the end of the active window for a melee clip,
				# the middle of the hold for a guard
				var hold: float = 0.65 if pose[1] == &"melee_l1" else 0.35
				for i in int(hold * 60.0):
					_step()
			await _save("%s_%s_%s" % [_out, pose[0], view])
	print("POSES done")
	get_tree().quit(0)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://../captures")
	DirAccess.make_dir_recursive_absolute(dir)
	image.save_jpg(dir.path_join(name + ".jpg"), 0.92)


func _parse(argv: PackedStringArray) -> Dictionary:
	var out := {}
	for arg in argv:
		if not arg.begins_with("--"):
			continue
		var body := arg.substr(2)
		var eq := body.find("=")
		if eq < 0:
			out[body] = "1"
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out
