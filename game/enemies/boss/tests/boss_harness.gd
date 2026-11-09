class_name BossTestHarness
extends RefCounted
## Rig for the boss tests (boss unit): a Crown arena, a stand-in hero and one Brood Titan, with no
## city and no sandbox needed. Mirrors the skills unit's harness shape so the suites read the same.

const BOSS_SCENE := "res://enemies/boss/brood_titan.tscn"
const GROUND_SIZE := 900.0

var root: Node
var world: Node3D
var arena: BossArena
var player: DummyPlayer
var titan: BroodTitan

var checks: int = 0
var failures: PackedStringArray = PackedStringArray()
var phases_seen: PackedInt32Array = PackedInt32Array()
var cores_broken: PackedStringArray = PackedStringArray()

var _nodes: Array[Node] = []


func _init(owner_node: Node) -> void:
	root = owner_node


## Builds the rig. Returns false (with a readable message) when a scene is missing, so the caller
## fails the run instead of asserting on a null titan.
func build() -> bool:
	world = Node3D.new()
	world.name = "BossTestWorld"
	root.add_child(world)
	Game.world = world
	arena = BossArena.new()
	arena.name = "BossArena"
	world.add_child(arena)
	player = DummyPlayer.new()
	player.name = "DummyPlayer"
	player.position = arena.ring_point(0.25, 0.55, 2.0)
	world.add_child(player)
	Game.register_player(player)
	Game.mark_world_built()
	if not _spawn_titan():
		return false
	Events.boss_phase.connect(_on_phase)
	titan.core_broken.connect(_on_core_broken)
	return true


func _spawn_titan() -> bool:
	if not ResourceLoader.exists(BOSS_SCENE):
		fail("rig", "no boss scene at " + BOSS_SCENE)
		return false
	var packed := load(BOSS_SCENE) as PackedScene
	if packed == null:
		fail("rig", "cannot load " + BOSS_SCENE)
		return false
	titan = packed.instantiate() as BroodTitan
	if titan == null:
		fail("rig", BOSS_SCENE + " is not a BroodTitan")
		return false
	titan.name = "BroodTitan"
	world.add_child(titan)
	titan.global_position = arena.ring_point(0.62, 0.72, 1.0)
	titan.look_at_from_position(titan.global_position, player.global_position, Vector3.UP)
	titan.perception.acquire(player, true)
	return true


func _on_phase(phase: int) -> void:
	phases_seen.append(phase)


func _on_core_broken(core: BossCore) -> void:
	cores_broken.append(String(core.id))


## Puts the titan back at full health with every core whole, so each suite starts from the same state.
func reset_titan() -> void:
	titan.restore_for_checkpoint(1)
	titan.global_position = arena.ring_point(0.62, 0.72, 1.0)
	titan.perception.acquire(player, true)
	arena.restore_segments()
	phases_seen.clear()
	cores_broken.clear()


## Advances `seconds` of simulated physics and returns the elapsed time.
func step(seconds: float) -> float:
	var dt := 1.0 / 120.0
	var steps := int(seconds / dt)
	for i in steps:
		await root.get_tree().physics_frame
	return float(steps) * dt


func frame() -> void:
	await root.get_tree().physics_frame


## A synthetic player hit on `part`, applied through the titan's own pipeline.
func hit_titan(amount: float, part: StringName = &"body", weapon: StringName = &"test_shot") -> HitInfo:
	var hit := HitInfo.make(amount, HitInfo.EXPLOSIVE, player, weapon)
	hit.hurtbox_part = part
	hit.position = titan.centre()
	titan.take_hit(hit)
	return hit


## A hit on one of the cores, through the core's own hurtbox so the ×1.0 / ×2.5 split is exercised.
func hit_core(index: int, amount: float) -> void:
	if index < 0 or index >= titan.cores.size():
		fail("core", "no core %d" % index)
		return
	var core := titan.cores[index]
	var hit := HitInfo.make(amount, HitInfo.EXPLOSIVE, player, &"test_shot")
	hit.hurtbox_part = core.part
	hit.weak_point = true
	hit.position = core.global_position
	core.take_hit(hit)


func core_index(id: StringName) -> int:
	for i in titan.cores.size():
		if titan.cores[i].id == id:
			return i
	return -1


## The attack ids currently in the titan's table.
func attack_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for a: EnemyAttack in titan.attacks():
		out.append(String(a.id))
	return out


func release_all() -> void:
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()


## Tracks a node the harness spawned so `release_all` can clean it up between suites.
func track(n: Node) -> Node:
	_nodes.append(n)
	return n


# --- assertions --------------------------------------------------------------------------------------

func check(id: String, ok: bool, detail: String = "") -> bool:
	checks += 1
	if ok:
		return true
	failures.append("%s: %s" % [id, detail])
	return false


func fail(id: String, detail: String) -> void:
	checks += 1
	failures.append("%s: %s" % [id, detail])


func near(id: String, got: float, want: float, tolerance: float) -> bool:
	return check(id, absf(got - want) <= tolerance,
			"got %.4f, wanted %.4f ± %.4f" % [got, want, tolerance])
