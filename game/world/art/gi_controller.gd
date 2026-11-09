class_name GiController
extends Node
## SDFGI fade at speed (city-art, ART.md §3). Godot warns that SDFGI degrades with fast cameras and
## ours run 42-190 m/s, so ART asks for a fade-out above 60 m/s over 0.5 s.
## The fade is applied to `sdfgi_energy`, NOT to `sdfgi_enabled`: toggling SDFGI (or MSAA, or adding
## the first ReflectionProbe) mid-game triggers a pipeline compile, which is a visible stutter
## (godot-tech §4.6). Energy ramps to zero with no recompile, and the cascades stay warm.
## No-op unless the run was started with `--gi=sdfgi`.

const FADE_SPEED := 60.0         ## m/s above which GI starts fading
const FADE_SECONDS := 0.5
const MIN_ENERGY := 0.0

var speed: float = 0.0           ## last camera speed read, m/s (evidence/debug)

var _env: Environment
var _base_energy: float = 1.0
var _current: float = 1.0
var _active: bool = false
var _last_pos := Vector3.ZERO
var _last_time: float = 0.0


func _ready() -> void:
	_active = ArtQuality.sdfgi_enabled()
	set_process(_active)


## Called by TimeOfDay once the Environment exists; also used by the tests.
func bind(env: Environment) -> void:
	_env = env
	if _env == null or not _env.sdfgi_enabled:
		_active = false
		set_process(false)
		return
	_base_energy = _env.sdfgi_energy
	_current = _base_energy
	_active = ArtQuality.sdfgi_enabled()
	set_process(_active)


func _process(delta: float) -> void:
	if _env == null:
		return
	var real := Feel.real_delta(delta)
	speed = _camera_speed()
	var target := _base_energy * (1.0 - clampf((speed - FADE_SPEED) / FADE_SPEED, 0.0, 1.0))
	_current = move_toward(_current, target, _base_energy * real / FADE_SECONDS)
	_env.sdfgi_energy = maxf(_current, MIN_ENERGY)


## The player mech's speed when there is one; otherwise how fast the active camera is moving.
func _camera_speed() -> float:
	var player := Game.player as Node3D
	if player != null:
		return (player.get(&"velocity") as Vector3).length()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var now := Feel.real_now()
	var moved := cam.global_position.distance_to(_last_pos) / maxf(now - _last_time, 1e-4)
	_last_pos = cam.global_position
	_last_time = now
	return moved
