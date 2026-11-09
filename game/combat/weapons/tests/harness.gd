class_name WeaponTestHarness
extends RefCounted
## Shared rig + assertions for the weapon test suites: a flat ground, a RigPlayer carrying the real
## `weapon_system.tscn`, dummy hurtboxes and input simulation through the registered actions (the
## same path a human or the autoplay tool uses).

const STEP := 1.0 / 120.0
const SCENE := "res://combat/weapons/weapon_system.tscn"

var failures: PackedStringArray = PackedStringArray()
var checks: int = 0
var tree: SceneTree = null
var root: Node = null
var player: RigPlayer = null
var aim: RigAim = null
var system: WeaponSystem = null
var targets: Array[DummyTarget] = []


func _init(root_: Node) -> void:
	root = root_
	tree = root_.get_tree()


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
	gb.size = Vector3(4000.0, 4.0, 4000.0)
	gs.shape = gb
	ground.add_child(gs)
	ground.position = Vector3(0.0, -2.0, 0.0)
	root.add_child(ground)
	player = RigPlayer.new()
	player.name = "RigPlayer"
	root.add_child(player)
	player.global_position = Vector3.ZERO
	system = packed.instantiate() as WeaponSystem
	if system == null:
		check("rig.scene_root_is_weapon_system", false, "weapon_system.tscn root is not a WeaponSystem")
		return false
	player.add_child(system)
	aim = player.aim_system
	return true


func add_target(at: Vector3, size: float = 10.0) -> DummyTarget:
	var t := DummyTarget.new()
	t.size = size
	root.add_child(t)
	t.global_position = at
	targets.append(t)
	return t


## Put the crosshair on `p` and give the physics world a tick to notice.
func aim_at(p: Vector3) -> void:
	aim.point = p


## Detach at once (queue_free alone would keep the node — and its group membership — alive for the
## rest of the frame, and the paint scan would still see it).
func clear_targets() -> void:
	for t in targets:
		if is_instance_valid(t):
			var parent := t.get_parent()
			if parent != null:
				parent.remove_child(t)
			t.queue_free()
	targets.clear()


func check(name: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS %s" % name)
		return
	failures.append("%s%s" % [name, "" if detail == "" else " — " + detail])
	print("FAIL %s %s" % [name, detail])


func near(name: String, got: float, want: float, tol: float) -> void:
	check(name, absf(got - want) <= tol, "got %.3f want %.3f ±%.3f" % [got, want, tol])


## Advance the simulation by `seconds` of physics time.
func step(seconds: float) -> void:
	var frames := maxi(int(round(seconds / STEP)), 1)
	for i in frames:
		await tree.physics_frame


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
	for a: StringName in [&"fire", &"aim", &"reload", &"missiles"]:
		Input.action_release(a)
