class_name DefenseTestHarness
extends RefCounted
## Shared rig + assertions for the Mirror Guard suite: flat ground, a MeleeRigPlayer carrying the real
## `defense_system.tscn`, a dummy attacker that builds real HitInfo packets, and live
## `EnemyProjectile` shots (the enemies unit's pooled class) so the catch field and the reflect path
## are exercised against the thing they will actually meet.

const STEP := 1.0 / 120.0
const SCENE := "res://combat/defense/defense_system.tscn"

var failures: PackedStringArray = PackedStringArray()
var checks: int = 0
var tree: SceneTree = null
var root: Node = null
var player: MeleeRigPlayer = null
var aim: MeleeRigAim = null
var system: DefenseSystem = null
var shots: Array[EnemyProjectile] = []
var attackers: Array[MeleeDummy] = []
var host: Node3D = null


func _init(root_: Node) -> void:
	root = root_
	tree = root_.get_tree()


func build() -> bool:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		check("rig.scene_loads", false, "cannot load " + SCENE)
		return false
	host = Node3D.new()
	host.name = "ShotHost"
	root.add_child(host)
	player = MeleeRigPlayer.new()
	player.name = "RigPlayer"
	root.add_child(player)
	player.global_position = Vector3(0.0, 8.0, 0.0)
	aim = player.aim_ref
	aim.look_at_point(Vector3(0.0, 8.0, -100.0))
	system = packed.instantiate() as DefenseSystem
	if system == null:
		check("rig.scene_root_is_defense_system", false,
				"defense_system.tscn root is not a DefenseSystem")
		return false
	player.add_child(system)
	return true


func fresh() -> void:
	release_all()
	clear_shots()
	clear_attackers()
	if system != null:
		system.reset()
	if player != null:
		player.reset_state()
		player.global_position = Vector3(0.0, 8.0, 0.0)
		player.global_rotation.y = 0.0
	if aim != null:
		aim.look_at_point(Vector3(0.0, 8.0, -100.0))


## A monster in front of the mech to parry: it carries the StatusComponent surface the recoil uses
## (`add_impact`) and `set_ai_enabled`, both from CONTRACTS §6.
func add_attacker(metres: float = 8.0) -> MeleeDummy:
	var d := MeleeDummy.new()
	root.add_child(d)
	d.global_position = player.global_position + Vector3(0.0, 0.0, -metres)
	d.look_at(player.global_position, Vector3.UP)
	attackers.append(d)
	return d


func clear_attackers() -> void:
	for a in attackers:
		if is_instance_valid(a):
			a.queue_free()
	attackers.clear()


## A live enemy shot flying at the player from `metres` in front (the enemies unit's pooled class,
## so the `reflectable` / `owner` / `hit` metadata the Mirror Guard reads is the real thing).
func add_shot(metres: float, damage: float = 200.0, reflectable: bool = true) -> EnemyProjectile:
	var shot := EnemyProjectile.new()
	host.add_child(shot)
	var from := player.global_position + Vector3(0.0, 2.0, -metres)
	var hit := HitInfo.make(damage, HitInfo.BALLISTIC, null, &"spitter_acid")
	hit.knockback = Vector3(0.0, 0.0, 6.0)
	shot.launch(from, Vector3(0.0, 0.0, 40.0), hit, null, reflectable, false, 0.0)
	shots.append(shot)
	return shot


func clear_shots() -> void:
	for s in shots:
		if is_instance_valid(s):
			s.queue_free()
	shots.clear()


## A HitInfo from `metres` in front of (or behind) the player.
func make_hit(metres: float, damage: float = 400.0, attacker: Node = null) -> HitInfo:
	var hit := HitInfo.make(damage, HitInfo.MELEE, attacker, &"mantis_slash")
	hit.parryable = true
	hit.position = player.global_position + Vector3(0.0, 0.0, -metres)
	return hit


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


func step(seconds: float) -> void:
	var frames := maxi(int(round(seconds / STEP)), 1)
	for _i in frames:
		await tree.physics_frame


func ticks(n: int) -> void:
	for _i in maxi(n, 0):
		await tree.physics_frame


## Holds the guard past both the perfect window and the 0.3 s catch-field threshold.
func open_catch_field() -> void:
	var need := maxi(DefenseTable.ticks(DefenseTable.MIN_GUARD_FRAMES),
			DefenseTable.ticks(DefenseTable.CATCH_HOLD * DefenseTable.REF_FPS)) + 4
	await ticks(need)


func press(action: StringName) -> void:
	Input.action_press(action)


func release(action: StringName) -> void:
	Input.action_release(action)


func release_all() -> void:
	for a: StringName in [&"guard", &"melee"]:
		Input.action_release(a)
