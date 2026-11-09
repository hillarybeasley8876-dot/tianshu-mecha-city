extends Node
## Shared harness for the mech-move acceptance tests: builds the sandbox, the stepping range and the
## player, and provides the stepping / waiting / reporting helpers. Each suite is a subclass that
## fills in `_run()`; run one with `tools/godot.sh test res://player/mech/tests/<suite>.gd`.
## Runs headless in the core sandbox at 120 Hz against the numbers of SPEC §4 (revised 2026-11-01).
## Every check prints PASS/FAIL; the suite quits 0 only when all of them pass.

const SANDBOX := preload("res://core/sandbox/sandbox.tscn")
const PLAYER := preload("res://player/player_mech.tscn")
const GROUND_Y := 7.6  ## body origin with the feet 0.1 m above the sandbox floor
const ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right",
		&"jump", &"boost", &"assault", &"descend"]

## Test range for the SPEC §4 stepping rules, added by the suites (the core sandbox is lead-owned).
## All three sit on the flat ground west of the cover field, on the mech's default -Z heading:
## a 2 m kerb at z 0, a 6 m block at z -100 and a 10 m wall at z -200, each 40 m wide in X.
const OBSTACLES: Array[Array] = [
	["kerb", Vector3(-120.0, 1.0, 0.0), Vector3(40.0, 2.0, 12.0)],
	["block", Vector3(-120.0, 3.0, -100.0), Vector3(40.0, 6.0, 12.0)],
	["wall", Vector3(-120.0, 5.0, -200.0), Vector3(40.0, 10.0, 6.0)],
]

var _p: PlayerMech
var _loco: MechLocomotion
var _enemy: Node3D
var _checks: int = 0
var _fails: int = 0
var _dodges: int = 0
var _last_impact: float = 0.0  ## downward speed of the last Events.landed, for the landing tiers


func _ready() -> void:
	_run()


## Overridden by each suite: `await _setup()`, then the checks, then `_report(<name>)`.
func _run() -> void:
	push_error("mech_test_base: _run() must be overridden by the suite")
	get_tree().quit(1)


## Sandbox + stepping range + a fake enemy + the player, wired to the two signals the suites count.
func _setup() -> void:
	var world := SANDBOX.instantiate() as Node3D
	add_child(world)
	(get_node(^"/root/Game") as Node).set(&"world", world)
	_build_obstacles()
	_enemy = Node3D.new()
	_enemy.name = "FakeEnemy"
	_enemy.add_to_group(&"enemy")
	add_child(_enemy)
	_p = PLAYER.instantiate() as PlayerMech
	add_child(_p)
	_loco = _p.get_node("Locomotion") as MechLocomotion
	Events.perfect_dodge.connect(func(_attacker: Node) -> void: _dodges += 1)
	Events.landed.connect(func(impact: float) -> void: _last_impact = impact)
	await _step(20)


func _build_obstacles() -> void:
	for o in OBSTACLES:
		var body := StaticBody3D.new()
		body.name = String(o[0])
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		body.position = o[1] as Vector3
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = o[2] as Vector3
		shape.shape = box
		body.add_child(shape)
		add_child(body)


# --- helpers -------------------------------------------------------------------------------------

## Steps `n` physics ticks. At a low time scale the engine issues far fewer ticks per real second, so
## suites that care about real seconds measure with `_real_step()` / `Feel.real_now()` instead.
func _step(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Physics ticks until `seconds` of REAL time have passed (CONTRACTS §3 clocks).
func _real_step(seconds: float) -> int:
	var t0 := Feel.real_now()
	var ticks := 0
	while Feel.real_now() - t0 < seconds and ticks < 60000:
		await get_tree().physics_frame
		ticks += 1
	return ticks


## Taps an action for three physics ticks, the shortest press a 120 Hz poller can see.
func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _step(3)
	Input.action_release(action)


## Steps until `move_state()` equals `want`; returns false on timeout.
func _until_state(want: StringName, max_ticks: int) -> bool:
	for i in max_ticks:
		if _p.move_state() == want:
			return true
		await get_tree().physics_frame
	return _p.move_state() == want


func _until_prefix(prefix: String, max_ticks: int) -> bool:
	for i in max_ticks:
		if String(_p.move_state()).begins_with(prefix):
			return true
		await get_tree().physics_frame
	return String(_p.move_state()).begins_with(prefix)


func _reset(at: Vector3, yaw: float = 0.0, wait_ground: bool = true) -> void:
	for a in ACTIONS:
		Input.action_release(a)
	_loco.debug_reset()
	# `heal`, not a bare `hp` write, so the death gate is open again on the next tick. A direct write
	# works too (`MechDamage.sync()` runs at the top of every tick and mirrors `is_alive()`, r16 B2),
	# but `heal()` also bounds hp to `hp_max`, which is what a reset wants.
	_p.heal(_p.hp_max)
	_p.debug_teleport([at.x, at.y, at.z], yaw)
	if not wait_ground:
		await _step(3)
		return
	var guard := 0
	while guard < 400:
		await get_tree().physics_frame
		guard += 1
		if _p.is_on_floor() and not String(_p.move_state()).begins_with("land"):
			break
	await _step(2)


## Double-tap jump in the air (SPEC §4): the second press inside the window starts free flight.
func _enter_flight() -> void:
	Input.action_press(&"jump")
	await _step(2)
	Input.action_release(&"jump")
	await _step(3)
	Input.action_press(&"jump")
	await _step(3)
	Input.action_release(&"jump")
	await _step(4)


## Flight path angle in degrees: 0 = level, negative = diving.
func _pitch_deg() -> float:
	return rad_to_deg(atan2(_p.velocity.y, _speed()))


func _speed() -> float:
	return Vector2(_p.velocity.x, _p.velocity.z).length()


func _dashing() -> bool:
	return String(_p.move_state()).begins_with("dash")


func _cam() -> Node3D:
	return _p.get_node("DebugCamera") as Node3D


func _wait_slowmo() -> void:
	var guard := 0
	while Engine.time_scale < 0.999 and guard < 60000:
		await get_tree().process_frame
		guard += 1


func _near(v: float, want: float, tol: float) -> bool:
	return absf(v - want) <= tol


func _ok(cond: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fails += 1
	print("%s %s%s" % ["PASS" if cond else "FAIL", label, ("  [" + detail + "]") if detail != "" else ""])


func _report(suite: String) -> void:
	print("%s %s: %d/%d checks passed"
			% ["FAIL" if _fails > 0 else "PASS", suite, _checks - _fails, _checks])
	get_tree().quit(1 if _fails > 0 else 0)
