extends Node
## monster-assets: dump one monster's per-frame skeleton pose through a scripted cycle
## (walk -> run -> attack -> hit -> death, with a hit-pause and a flash inside it).
##
##   tools/godot.sh test res://enemies/models/tests/probe_pose_dump.gd -- \
##       --pose-out=/abs/path.txt [--pose-type=ripper]
##
## The point is a refactor gate: run it before a change, run it after, and the two dumps must be
## identical. Every physics tick it records, for every bone, the global pose (origin + the 9 basis
## numbers), plus the player's clip / position / speed scale and the visual state the shader sees —
## so a change in playback timing, blending or the hold shows up as a differing number.

## Tick counts per phase. Fixed, so two runs walk the same path.
const WALK_TICKS := 60
const RUN_TICKS := 60
const ATTACK_TICKS := 120
const HIT_TICKS := 90
const DEATH_TICKS := 120

var _model: MonsterModel
var _out: FileAccess
var _tick: int = 0
var _end: int = 0
var _phase: int = -1


func _ready() -> void:
	var type_name := &"ripper"
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pose-out="):
			path = arg.trim_prefix("--pose-out=")
		elif arg.begins_with("--pose-type="):
			type_name = StringName(arg.trim_prefix("--pose-type="))
	if path.is_empty():
		push_error("probe_pose_dump: --pose-out=/abs/path.txt is required")
		get_tree().quit(2)
		return
	_out = FileAccess.open(path, FileAccess.WRITE)
	if _out == null:
		push_error("probe_pose_dump: cannot write %s" % path)
		get_tree().quit(2)
		return
	var scene := "res://enemies/models/%s/%s_model.tscn" % [type_name, type_name]
	var packed := load(scene) as PackedScene
	if packed == null:
		push_error("probe_pose_dump: cannot load " + scene)
		get_tree().quit(2)
		return
	_model = packed.instantiate() as MonsterModel
	add_child(_model)
	_end = WALK_TICKS + RUN_TICKS + ATTACK_TICKS + HIT_TICKS + DEATH_TICKS


## The scripted cycle, driven by tick index alone so it is reproducible frame for frame.
func _drive() -> void:
	var t := _tick
	if t < WALK_TICKS:
		_enter(0, func() -> void: _model.set_locomotion(&"walk", 8.0))
	elif t < WALK_TICKS + RUN_TICKS:
		_enter(1, func() -> void: _model.set_locomotion(&"run", 30.0))
	elif t < WALK_TICKS + RUN_TICKS + ATTACK_TICKS:
		# the attack, with the brain re-asserting idle every tick around it (lead audit 1)
		_enter(2, func() -> void: _model.play_action(&"attack_1"))
		_model.set_locomotion(&"idle", 0.0)
	elif t < WALK_TICKS + RUN_TICKS + ATTACK_TICKS + HIT_TICKS:
		_enter(3, func() -> void:
			_model.play_action(&"hit")
			_model.set_hit_flash(1.0)
			_model.set_telegraph(EnemyAttack.UNBLOCKABLE, 0.7)
			_model.hit_pause(0.2))
		_model.set_locomotion(&"idle", 0.0)
	else:
		_enter(4, func() -> void:
			_model.set_stagger(true)
			_model.play_action(&"death"))
		_model.set_locomotion(&"walk", 8.0)
	if t == _end - 1:
		_model.set_hit_flash(0.0)


## Run `action` only on the tick the phase starts on.
func _enter(phase: int, action: Callable) -> void:
	if _phase != phase:
		_phase = phase
		action.call()


func _physics_process(_delta: float) -> void:
	if _model == null or _out == null:
		return
	_drive()
	_write()
	_tick += 1
	if _tick >= _end:
		_out.close()
		print("POSE %d ticks, %d bones -> %s" % [_end, _model.skeleton.get_bone_count(),
				_out.get_path()])
		print("PASS")
		get_tree().quit(0)


func _write() -> void:
	var anim := _model.animation
	var line := "%d %s %.10f %.10f %.10f %.10f %.10f" % [_tick, anim.current_animation,
			anim.current_animation_position, anim.speed_scale, _model.visual.rotation_degrees.z,
			_param(&"hit_flash"), _param(&"tell")]
	var skeleton := _model.skeleton
	for i in skeleton.get_bone_count():
		var pose := skeleton.get_bone_global_pose(i)
		line += " " + _vec(pose.origin) + " " + _vec(pose.basis.x) + " " + _vec(pose.basis.y) \
				+ " " + _vec(pose.basis.z)
	_out.store_line(line)


func _vec(v: Vector3) -> String:
	return "%.10f,%.10f,%.10f" % [v.x, v.y, v.z]


func _param(name: StringName) -> float:
	for mesh in _model.meshes:
		var value: Variant = mesh.get_instance_shader_parameter(name)
		if value != null:
			return float(value)
	return -1.0
