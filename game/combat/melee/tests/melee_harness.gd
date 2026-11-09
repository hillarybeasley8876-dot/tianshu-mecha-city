class_name MeleeTestHarness
extends RefCounted
## Shared rig + assertions for the melee suite: flat ground, a MeleeRigPlayer carrying the real
## `melee_system.tscn`, dummy enemies, and input simulated through the registered actions (the same
## path a human or tools/autoplay uses).

const STEP := 1.0 / 120.0
const SCENE := "res://combat/melee/melee_system.tscn"

var failures: PackedStringArray = PackedStringArray()
var checks: int = 0
var tree: SceneTree = null
var root: Node = null
var player: MeleeRigPlayer = null
var aim: MeleeRigAim = null
var system: MeleeSystem = null
var dummies: Array[MeleeDummy] = []
var built_frame: int = -1            ## Engine.get_physics_frames() at the system's add_child


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
	player = MeleeRigPlayer.new()
	player.name = "RigPlayer"
	player.force_stub_model = true
	root.add_child(player)
	player.global_position = Vector3(0.0, 8.0, 0.0)
	aim = player.aim_ref
	system = packed.instantiate() as MeleeSystem
	if system == null:
		check("rig.scene_root_is_melee_system", false, "melee_system.tscn root is not a MeleeSystem")
		return false
	player.add_child(system)
	## The system's `_refresh()` only runs from `_physics_process`, so a caller that reads public
	## state in this very frame sees the pre-tick state the HUD sees on a mid-frame boot.
	built_frame = Engine.get_physics_frames()
	return true


## A dummy enemy `metres` in front of the player (-Z is the mech's forward), turned to face it the
## way a live monster would (the Core Rend cone is measured from the enemy's facing).
func add_dummy(metres: float, size: float = 12.0) -> MeleeDummy:
	var d := MeleeDummy.new()
	d.size = size
	root.add_child(d)
	d.global_position = player.global_position + Vector3(0.0, 0.0, -metres)
	d.look_at(player.global_position, Vector3.UP)
	aim.look_at_point(d.global_position)
	dummies.append(d)
	return d


func clear_dummies() -> void:
	for d in dummies:
		if is_instance_valid(d):
			var parent := d.get_parent()
			if parent != null:
				parent.remove_child(d)
			d.queue_free()
	dummies.clear()
	if aim != null:
		aim.lock(null)


func fresh() -> void:
	clear_dummies()
	release_all()
	if system != null:
		system.reset()
	if player != null:
		player.reset_state()
		player.global_position = Vector3(0.0, 8.0, 0.0)
		player.global_rotation.y = 0.0
	if player.model_ref != null and player.model_ref.has_method(&"clear"):
		player.model_ref.call(&"clear")


func check(name: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS %s" % name)
		return
	failures.append("%s%s" % [name, "" if detail == "" else " — " + detail])
	print("FAIL %s %s" % [name, detail])


func near(name: String, got: float, want: float, tol: float) -> void:
	check(name, absf(got - want) <= tol, "got %.3f want %.3f ±%.3f" % [got, want, tol])


func eq(name: String, got: Variant, want: Variant) -> void:
	check(name, got == want, "got %s want %s" % [str(got), str(want)])


## Advance the simulation by `seconds` of physics time.
func step(seconds: float) -> void:
	var frames := maxi(int(round(seconds / STEP)), 1)
	for _i in frames:
		await tree.physics_frame


## Step exactly `n` physics ticks (frame-data assertions need tick precision).
func ticks(n: int) -> void:
	for _i in maxi(n, 0):
		await tree.physics_frame


func press(action: StringName) -> void:
	Input.action_press(action)


func release(action: StringName) -> void:
	Input.action_release(action)


## Tap: hold for `hold_ticks` physics ticks, then let go and settle `after` seconds.
func tap(action: StringName, hold_ticks: int = 3, after: float = 0.0) -> void:
	Input.action_press(action)
	await ticks(hold_ticks)
	Input.action_release(action)
	if after > 0.0:
		await step(after)


func hold(action: StringName, seconds: float) -> void:
	Input.action_press(action)
	await step(seconds)
	Input.action_release(action)


func release_all() -> void:
	for a: StringName in [&"melee", &"guard", &"boost", &"jump"]:
		Input.action_release(a)
