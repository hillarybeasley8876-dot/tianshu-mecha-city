class_name SkillTestHarness
extends RefCounted
## Shared rig + assertions for the skills suites: flat ground, a SkillRigPlayer carrying the real
## `skill_system.tscn`, dummy enemies and input simulated through the registered actions (the same
## path a human or `tools/godot.sh drive` uses). Independent of the weapons unit's harness.

const STEP := 1.0 / 120.0
const SCENE := "res://combat/skills/skill_system.tscn"

var failures: PackedStringArray = PackedStringArray()
var checks: int = 0
var tree: SceneTree = null
var root: Node = null
var player: SkillRigPlayer = null
var aim: SkillRigAim = null
var system: SkillSystem = null
var enemies: Array[SkillDummyEnemy] = []
var walls: Array[StaticBody3D] = []


func _init(root_: Node) -> void:
	root = root_
	tree = root_.get_tree()


## Builds ground at y = 0, the rig player and the real skill component.
func build() -> bool:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		check("rig.scene_loads", false, "cannot load " + SCENE)
		return false
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = Layers.WORLD
	ground.collision_mask = 0
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(4000.0, 40.0, 4000.0)
	gs.shape = gb
	ground.add_child(gs)
	ground.position = Vector3(0.0, -20.0, 0.0)
	root.add_child(ground)
	player = SkillRigPlayer.new()
	player.name = "RigPlayer"
	root.add_child(player)
	player.global_position = Vector3(0.0, 8.0, 0.0)
	system = packed.instantiate() as SkillSystem
	if system == null:
		check("rig.scene_root_is_skill_system", false, "skill_system.tscn root is not a SkillSystem")
		return false
	player.add_child(system)
	aim = player.rig_aim
	return true


func add_enemy(at: Vector3, heavy: bool = false) -> SkillDummyEnemy:
	var e := SkillDummyEnemy.new()
	if heavy:
		e.make_heavy()
	root.add_child(e)
	e.global_position = at
	enemies.append(e)
	return e


## A dummy that survives anything, for damage-total assertions.
func add_target(at: Vector3, heavy: bool = false) -> SkillDummyEnemy:
	var e := add_enemy(at, heavy)
	e.invincible = true
	return e


## `body_height` must be set BEFORE the node enters the tree: the collision capsule is built in
## _ready, and a 90 m colossus capsule shoves the player across the arena.
func add_boss(at: Vector3, body_height: float = 90.0) -> SkillDummyEnemy:
	var e := SkillDummyEnemy.new()
	e.make_boss()
	e.body_height = body_height
	root.add_child(e)
	e.global_position = at
	enemies.append(e)
	return e


## A wall between two points, for the line-of-sight gated tests.
func add_wall(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Wall"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	root.add_child(body)
	body.global_position = at
	walls.append(body)
	return body


## Removes the scenery too: a wall left over from the line-of-sight tests would silently block the
## next suite's grapple arcs and lobs.
func clear_walls() -> void:
	for w in walls:
		if is_instance_valid(w):
			var parent := w.get_parent()
			if parent != null:
				parent.remove_child(w)
			w.queue_free()
	walls.clear()


func clear_enemies() -> void:
	clear_walls()
	for e in enemies:
		if is_instance_valid(e):
			var parent := e.get_parent()
			if parent != null:
				parent.remove_child(e)
			e.queue_free()
	enemies.clear()


## Fresh state for the next suite: full gauge, empty OD, no cooldowns, no field effects.
func reset() -> void:
	system.reset()
	player.energy = player.energy_max
	player.overdrive = 0.0
	player.overdrive_active = false
	player.cancellable = true
	player.locked_for = 0.0
	player.velocity = Vector3.ZERO
	player.stick = Vector2.ZERO
	aim.locked = null
	aim.soft = null
	player.rig_model.actions.clear()


func check(name: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS %s" % name)
		return
	failures.append("%s%s" % [name, "" if detail == "" else " — " + detail])
	print("FAIL %s %s" % [name, detail])


# --- input-path instrumentation -------------------------------------------------------------------

## `Events.skill_used` with the physics frame it fired on, so a suite can measure the latency between
## a real press and the activation (r4 items 1 and 3 drive the registered actions, not `try_*`).
var _used: Dictionary = {}
var _watching: bool = false


func watch_skill_used() -> void:
	if _watching:
		return
	_watching = true
	Events.skill_used.connect(_on_skill_used)


func _on_skill_used(id: StringName) -> void:
	if not _used.has(id):
		_used[id] = [] as Array[int]
	(_used[id] as Array).append(Engine.get_physics_frames())


func used_count(id: StringName) -> int:
	return (_used.get(id, []) as Array).size()


## Physics frame of the `n`-th `skill_used(id)`, or -1.
func used_frame(id: StringName, n: int) -> int:
	var list: Array = _used.get(id, []) as Array
	return int(list[n]) if n >= 0 and n < list.size() else -1


## Physics frames since the `n`-th activation, measured from `f0`; -1 when it never fired.
func used_latency(id: StringName, n: int, f0: int) -> int:
	var f := used_frame(id, n)
	return f - f0 if f >= 0 else -1


## `Events.overdrive_changed` tallies, the same two mech-move's `test_death` counts: audio stops its
## Overdrive loop on the `false`, so a death has to deliver exactly one of them and no more.
var od_on: int = 0
var od_off: int = 0
var _od_watching: bool = false


func watch_overdrive() -> void:
	if _od_watching:
		return
	_od_watching = true
	Events.overdrive_changed.connect(func(on: bool) -> void:
		if on:
			od_on += 1
		else:
			od_off += 1)


func near(name: String, got: float, want: float, tol: float) -> void:
	check(name, absf(got - want) <= tol, "got %.3f want %.3f ±%.3f" % [got, want, tol])


func step(seconds: float) -> void:
	var frames := maxi(int(round(seconds / STEP)), 1)
	for i in frames:
		await tree.physics_frame


## Steps until `cond` returns true or `timeout` seconds of game time pass. Use this instead of a
## guessed sleep: the ignition and the lance charge run at 0.3x time (FEEL rows overdrive_ignite and
## lance_fire), so their wall-clock length is not their game-time length.
func wait_until(cond: Callable, timeout: float) -> bool:
	var frames := maxi(int(round(timeout / STEP)), 1)
	for i in frames:
		if bool(cond.call()):
			return true
		await tree.physics_frame
	return bool(cond.call())


func press(action: StringName) -> void:
	Input.action_press(action)


func release(action: StringName) -> void:
	Input.action_release(action)


## Tap: hold for 3 physics ticks (the autoplay tool's convention), then let go and settle `after`.
func tap(action: StringName, after: float = 0.0) -> void:
	Input.action_press(action)
	await step(3.0 * STEP)
	Input.action_release(action)
	if after > 0.0:
		await step(after)


func hold(action: StringName, seconds: float) -> void:
	Input.action_press(action)
	await step(seconds)
	Input.action_release(action)


func release_all() -> void:
	for a: StringName in [&"rift_step", &"anchor", &"fins", &"burst", &"well", &"melee",
			&"overdrive", &"jump", &"boost", &"guard", &"fire", &"lock_on"]:
		Input.action_release(a)


## Lift the mech to `height` above the ground and give it a tick to register as airborne.
func lift(height: float) -> void:
	player.global_position = Vector3(player.global_position.x, height, player.global_position.z)
	player.velocity = Vector3.ZERO
	player.grounded = false
	await step(2.0 * STEP)
