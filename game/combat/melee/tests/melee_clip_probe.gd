class_name MeleeClipProbe
extends Node3D
## Measures the SHIPPED hero clips' blade sweep against `melee_table.gd`'s active windows (review r4
## item 2): where a clip's swing and the gameplay window disagree by more than 3 frames, that is a
## note for hero-v3 — gameplay is never retimed to fit a bad clip.
##
## Method: play the clip on the real rig, sample the `saber_r` socket's blade axis every physics
## tick, convert to 60 fps frames, and take the contiguous run where the angular speed is at least
## a quarter of the clip's peak as "the sweep". Prints one CLIP line per move.
## The same run also measures review r4 item 3 against the REAL model: a local `hit_pause` has to
## hold the melee move clock for its whole span, so the arm and the blade freeze together.
## `tools/godot.sh run res://combat/melee/tests/melee_clip_probe.tscn 90`

const HERO_MODEL := "res://player/model/hero3/hero3_model.tscn"
const MELEE := "res://combat/melee/melee_system.tscn"
## The local hit-stop a landed light hit applies (MeleeTable L1 hitstop 5 f).
const STOP := 0.083
## A frame counts as part of the swing while the blade turns at ≥ this fraction of the peak rate.
const SWEEP_FRACTION := 0.25
## Frames of disagreement the review calls out.
const REPORT_FRAMES := 3.0
## Ticks dropped from the front: the pose snaps from idle into the clip over the 0.06 s blend, and
## that cut is not the swing.
const SKIP_TICKS := 8
const MOVES: Array[StringName] = [MeleeTable.L1, MeleeTable.L2, MeleeTable.L3, MeleeTable.LUNGE,
	MeleeTable.CHARGE_SLASH, MeleeTable.AIR_L1, MeleeTable.AIR_L2, MeleeTable.RETURN_CUT,
	MeleeTable.RAM_KICK]

var _player: MeleeRigPlayer = null
var _model: Node3D = null
var _melee: MeleeSystem = null


func _ready() -> void:
	_player = MeleeRigPlayer.new()
	_player.name = "RigPlayer"
	if ResourceLoader.exists(HERO_MODEL):
		_player.model_scene = HERO_MODEL
	add_child(_player)
	_player.global_position = Vector3(0.0, 8.0, 0.0)
	_model = _player.model_ref
	_melee = (load(MELEE) as PackedScene).instantiate() as MeleeSystem
	_player.add_child(_melee)
	_run.call_deferred()


func _run() -> void:
	if _model == null or not _model.has_method(&"play_action"):
		push_error("MeleeClipProbe: no model with play_action")
		get_tree().quit(1)
		return
	await _wait(20)
	for id: StringName in MOVES:
		await _probe(id)
	await _hit_stop()
	get_tree().quit(0)


## [item 3] `Feel.local_hit_stop` reaches the model through PlayerMech.hit_pause; while the model
## reports `paused()` the melee move clock must not advance, and the hand must not move either.
func _hit_stop() -> void:
	_melee.reset()
	await _wait(10)
	_melee._begin(MeleeTable.L1)
	await _wait(4)
	var socket := _model.call(&"socket", &"saber_r") as Node3D
	_model.call(&"hit_pause", STOP, 0.0)
	await get_tree().physics_frame
	## Measured from the first held tick: before it the pose is still moving into the clip, after it
	## the animation resumes, and neither is part of the stop.
	var tick := int(_melee.get(&"_tick"))
	var axis := _axis(socket)
	var drift := 0.0
	var slip := 0
	var held := 0
	while bool(_model.call(&"paused")) and held < 240:
		await get_tree().physics_frame
		## The frame the stop expires on is the resume, not part of the hold.
		if not bool(_model.call(&"paused")):
			break
		held += 1
		drift = maxf(drift, rad_to_deg(axis.angle_to(_axis(socket))))
		slip = maxi(slip, absi(int(_melee.get(&"_tick")) - tick))
	print("STOP %.3f s | held %d ticks | move clock slipped %d ticks | hand drifted %.2f deg | %s"
			% [STOP, held, slip, drift, "OK" if slip == 0 and drift < 1.0 else "FAILED"])


## One clip: sample the blade axis, then compare the sweep it draws with the table's active window.
func _probe(id: StringName) -> void:
	var length: float = float(_model.call(&"play_action", id, 0.06))
	var frames := maxi(int(round(length * MeleeTable.PHYSICS_HZ)), 24)
	var socket := _model.call(&"socket", &"saber_r") as Node3D
	if socket == null:
		print("CLIP %s — no saber_r socket" % id)
		return
	var axes: Array[Vector3] = []
	for _i in frames:
		await get_tree().physics_frame
		axes.append(_axis(socket))
	_report(id, axes, length)


## The blade axis (the socket's −Z) in the mech's own frame, so the reading does not move when the
## mech turns.
func _axis(socket: Node3D) -> Vector3:
	return (_player.global_basis.inverse() * (-socket.global_basis.z)).normalized()


func _report(id: StringName, axes: Array[Vector3], length: float) -> void:
	var speeds := _speeds(axes)
	var peak := 0.0
	for i in range(SKIP_TICKS, speeds.size()):
		peak = maxf(peak, speeds[i])
	var run := _longest_run(speeds, peak * SWEEP_FRACTION)
	if run.x < 0.0 or peak <= 0.01:
		print("CLIP %-13s clip %.2fs — NO SWING (peak %.2f deg/frame)" % [id, length, peak])
		return
	var hz := MeleeTable.REF_FPS / MeleeTable.PHYSICS_HZ
	var sweep_from := (run.x + 1.0) * hz
	var sweep_to := (run.y + 2.0) * hz
	var act_from := MeleeTable.field(id, "startup") + 1.0
	var act_to := MeleeTable.field(id, "startup") + MeleeTable.field(id, "active")
	var lead := sweep_from - act_from
	var tail := sweep_to - act_to
	var flag := "OK" if absf(lead) <= REPORT_FRAMES and absf(tail) <= REPORT_FRAMES else "MISMATCH"
	print("CLIP %-13s clip %.2fs | swing f%.0f-f%.0f (%.0f deg, peak %.1f deg/f) | active f%.0f-f%.0f | lead %+.0f tail %+.0f | %s"
			% [id, length, sweep_from, sweep_to, _travel(axes, int(run.x), int(run.y)), peak,
			act_from, act_to, lead, tail, flag])


## The longest contiguous run of frames turning at ≥ `floor`, as (first, last) tick indices. The
## pose snaps when a clip starts and again when it hands back to locomotion, so the run that
## matters is the longest one, not the first-to-last span.
func _longest_run(speeds: Array[float], floor_: float) -> Vector2:
	var best := Vector2(-1.0, -1.0)
	var start := -1
	for i in range(SKIP_TICKS, speeds.size()):
		if speeds[i] >= floor_:
			if start < 0:
				start = i
			if i - start > best.y - best.x:
				best = Vector2(start, i)
		else:
			start = -1
	return best


## How far the blade turns per tick, in degrees (the whole 3D turn, not just its yaw).
func _speeds(axes: Array[Vector3]) -> Array[float]:
	var out: Array[float] = []
	for i in axes.size() - 1:
		out.append(rad_to_deg(axes[i].angle_to(axes[i + 1])))
	return out


func _travel(axes: Array[Vector3], from: int, to: int) -> float:
	return rad_to_deg(axes[from].angle_to(axes[mini(to + 1, axes.size() - 1)]))


func _wait(ticks: int) -> void:
	for _i in ticks:
		await get_tree().physics_frame
