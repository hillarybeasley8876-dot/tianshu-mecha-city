class_name EnemyVisuals
extends RefCounted
## Everything EnemyBase does to its model (enemies-owned): locomotion/action calls, the telegraph
## tell, the hit-stop vibration and the hit flash. Split out of EnemyBase so the monster root stays
## readable; it talks to the model only through the CONTRACTS §6 API, so a real monster model drops
## in unchanged.

## juice §2.3: A0 = 0.04 × body height, offset on the local X axis, sign alternating each frame.
const VIBRATION_PER_HEIGHT := 0.04

var host: EnemyBase
var _flash: float = 0.0
var _vib_left: float = 0.0
var _vib_total: float = 0.0
var _vib_sign: float = 1.0
var _tell_left: float = 0.0
var _tell_total: float = 0.0
var _tell_kind: StringName = &""


func setup(host_: EnemyBase) -> void:
	host = host_


## juice §2.3: offset only the visual root, never the collision shapes; A(t) = A0·(1 − t/T).
func tick_vibration(delta: float) -> void:
	var model := host.model
	if model == null:
		return
	if _vib_left <= 0.0:
		model.position.x = 0.0
		return
	_vib_left -= delta
	var amp := VIBRATION_PER_HEIGHT * host.body_height \
			* clampf(_vib_left / maxf(_vib_total, 0.001), 0.0, 1.0)
	# Alternates per RENDERED frame, not per physics tick: at 120 Hz physics against 60 fps a
	# per-tick flip lands on the same side twice in a row, so the shake read as a one-sided lurch
	# (audit #13).
	_vib_sign = 1.0 if Engine.get_process_frames() % 2 == 0 else -1.0
	model.position.x = _vib_sign * amp


func start_vibration(seconds: float) -> void:
	_vib_left = maxf(_vib_left, seconds)
	_vib_total = maxf(_vib_total, seconds)


func clear_vibration() -> void:
	_vib_left = 0.0
	_vib_total = 0.0
	_vib_sign = 1.0


## White glint = parryable, red glow = unblockable (SPEC §7). juice §11.1: the windup ramps so the
## tell builds over the whole anticipation instead of snapping on.
func begin_telegraph(attack: EnemyAttack) -> void:
	_tell_kind = attack.kind
	_tell_total = maxf(attack.telegraph, EnemyTypes.PHASE_MIN_TELEGRAPH)
	_tell_left = _tell_total


func end_telegraph() -> void:
	_tell_left = 0.0
	_apply(0.0)


func tick_telegraph(dt: float) -> void:
	if _tell_left <= 0.0:
		return
	_tell_left -= dt
	_apply(1.0 - clampf(_tell_left / maxf(_tell_total, 0.001), 0.0, 1.0))


func set_hit_flash(v: float) -> void:
	_flash = maxf(_flash, clampf(v, 0.0, 1.0))
	_push()


func tick_flash(dt: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(0.0, _flash - dt * 6.0)
	_push()


func reset() -> void:
	_flash = 0.0
	_tell_left = 0.0
	clear_vibration()


func _apply(tell: float) -> void:
	if host.model != null and host.model.has_method(&"set_telegraph"):
		host.model.call(&"set_telegraph", _tell_kind, tell)


func _push() -> void:
	if host.model != null and host.model.has_method(&"set_hit_flash"):
		host.model.call(&"set_hit_flash", _flash)
