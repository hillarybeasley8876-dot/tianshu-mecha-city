class_name FlowDropIn
extends Node
## The carrier drop (brief §1, SPEC §8 step 1): the hero starts 400 m over the canal, falls under the
## mech's own gravity with the thrusters lit, the camera holds a three-shot cinematic the whole way
## down, and the landing is a `land_heavy`. The player can still see and steer — the cinematic takes
## the look input, so nothing is stolen from them that they could have used.
##
## It finishes on the first `Events.landed` (or after `FALL_TIMEOUT` if the world never gave the hero
## a floor, so the demo can never hang here). The timeout is counted from `begin()` on the unscaled
## clock the sequence runs on (`Feel.real_delta`, CONTRACTS §3) and only while the fall is running —
## a node that counted from boot would pre-finish itself while the player sat on the title screen, and
## a clock that ran through a pause would time the drop out in mid-air.

signal finished(at: Vector3, hard: bool)

const DROP_HEIGHT := 400.0        ## m above the insertion point
const FALL_TIMEOUT := 30.0        ## s of real time before the sequence gives up waiting for ground
const CINEMATIC_LEN := 40.0       ## s handed to the rig; end_cinematic() cuts it short
const HARD_LANDING := 32.0        ## m/s — the FEEL `land_heavy` threshold (SPEC §4)
const THRUSTER_LEVEL := 1.0
## Duel-frame offsets (camera-aim): with no hard target the frame's −Z is the hero's facing, so
## +Z offsets sit behind them and +Y above.
const SHOTS: Array[Dictionary] = [
	{"offset": Vector3(70.0, 26.0, 130.0), "fov": 72.0, "t": 0.0},
	{"offset": Vector3(95.0, 6.0, 10.0), "fov": 58.0, "t": 3.2},
	{"offset": Vector3(-24.0, 14.0, 52.0), "fov": 48.0, "t": 6.4},
]

var _player: Node3D = null
var _fall_t: float = 0.0
var _done: bool = true


func _ready() -> void:
	# Nothing runs until begin() arms the fall (audit #1: a live _process counted the timeout from boot).
	set_process(false)
	set_physics_process(false)


func begin(at: Transform3D) -> void:
	_player = Game.player
	if _player == null:
		push_warning("FlowDropIn: no player to drop in")
		_finish(false)
		return
	_done = false
	_fall_t = 0.0
	_player.global_transform = Transform3D(at.basis.orthonormalized(),
			at.origin + Vector3.UP * DROP_HEIGHT)
	_player.set(&"velocity", Vector3.ZERO)
	_thrusters(THRUSTER_LEVEL)
	if not Events.landed.is_connected(_on_landed):
		Events.landed.connect(_on_landed)
	FxBridge.spawn(self, &"thruster_burst", _player.global_position, Vector3.DOWN, 3.0)
	# The FEEL row carries the sound (lead note: flow never hand-picks a sound id for juice).
	Feel.play(&"boost_start", _player.global_position)
	var rig := Game.camera_rig
	if rig != null and rig.has_method(&"request_cinematic"):
		rig.call(&"request_cinematic", SHOTS, CINEMATIC_LEN)
	else:
		push_warning("FlowDropIn: no camera rig — the drop plays without a cinematic camera")
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_fall_t += Feel.real_delta(delta)
	if _fall_t > FALL_TIMEOUT:
		push_warning("FlowDropIn: no landing after %.0f s, continuing" % FALL_TIMEOUT)
		_finish(false)


func _on_landed(impact_speed: float) -> void:
	if _done:
		return
	_finish(impact_speed >= HARD_LANDING)


func _finish(hard: bool) -> void:
	if _done:
		return
	_done = true
	set_physics_process(false)
	if Events.landed.is_connected(_on_landed):
		Events.landed.disconnect(_on_landed)
	var at := _player.global_position if is_instance_valid(_player) else Vector3.ZERO
	_thrusters(0.0)
	Feel.play(&"land_heavy" if hard else &"land_light", at)
	var rig := Game.camera_rig
	if rig != null and rig.has_method(&"end_cinematic"):
		rig.call(&"end_cinematic")
	finished.emit(at, hard)


func _thrusters(level: float) -> void:
	if not is_instance_valid(_player) or not _player.has_method(&"model"):
		return
	var model := _player.call(&"model") as Node3D
	if model != null and model.has_method(&"set_thrusters"):
		model.call(&"set_thrusters", level)
