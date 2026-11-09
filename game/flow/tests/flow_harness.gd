class_name FlowTestHarness
extends RefCounted
## Builds the real `flow/game_flow.tscn` over a fake hero and a flat floor, and collects PASS/FAIL the
## way the other units' harnesses do. Run with `--sandbox --flow --spawn=0,1,60` so the three sandbox
## spires are placed and the 400 m drop is skipped:
## `tools/godot.sh test res://flow/tests/test_flow.gd -- --sandbox --flow --spawn=0,1,60`.

const FLOW_SCENE := "res://flow/game_flow.tscn"
const SETTLE_FRAMES := 4

var root: Node = null
var flow: FlowGameFlow = null
var player: FlowFakePlayer = null
## Stands in for the camera rig for the whole run, so a respawn's `snap_to_player()` is observable
## headless (r5 brief item 1). Restored by `release_all`.
var rig: FlowFakeRig = null
var _kept_rig: Node3D = null
var checks: int = 0
var failures: PackedStringArray = PackedStringArray()
var skips: PackedStringArray = PackedStringArray()
var objectives: PackedStringArray = PackedStringArray()
var encounters: PackedStringArray = PackedStringArray()


func build(host: Node) -> bool:
	root = Node3D.new()
	root.name = "FlowWorld"
	host.add_child(root)
	# The harness root stands in for the world, so `FlowWorld.player_start()` reads its marker the way
	# it reads the sandbox's or the city's.
	Game.world = root as Node3D
	_floor()
	_crown()
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = Vector3(0.0, 1.0, 60.0)
	root.add_child(spawn)
	player = FlowFakePlayer.new()
	player.name = "Player"
	player.position = Vector3(0.0, 1.0, 60.0)
	root.add_child(player)
	var packed := load(FLOW_SCENE) as PackedScene
	if packed == null:
		fail("cannot load " + FLOW_SCENE)
		return false
	var node := packed.instantiate()
	node.name = "GameFlow"
	root.add_child(node)
	flow = node as FlowGameFlow
	if flow == null:
		fail("game_flow.tscn root is not a FlowGameFlow")
		return false
	Events.objective_changed.connect(func(text: String) -> void: objectives.append(text))
	Events.encounter_started.connect(func(id: StringName) -> void:
		encounters.append("start:" + String(id)))
	Events.encounter_cleared.connect(func(id: StringName) -> void:
		encounters.append("clear:" + String(id)))
	rig = FlowFakeRig.new()
	rig.name = "FakeRig"
	root.add_child(rig)
	_kept_rig = Game.camera_rig
	Game.camera_rig = rig
	# The director would spawn real monsters as soon as the hero enters the sandbox zone; the wave
	# suite drives its own copy instead.
	flow.auto_waves = false
	flow.director.enabled = false
	return true


func _floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000.0, 4.0, 2000.0)
	shape.shape = box
	shape.position = Vector3(0.0, -2.0, 0.0)
	body.add_child(shape)
	root.add_child(body)


## A stand-in Crown deck: the gate now starts the fight on a real touchdown
## (`FlowCrownDeck.touched_down`) and the boss checkpoints save a probed point on the fighting floor,
## so the world the tests run in has to have a floor up there. Its top sits at `CENTRE.y + 16`, which
## is where `BossTuning.RIM_STEPS[2]` puts the arena's own top disc.
func _crown() -> void:
	var body := StaticBody3D.new()
	body.name = "CrownDeck"
	body.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(320.0, 8.0, 320.0)
	shape.shape = box
	shape.position = Vector3(FlowCrownDeck.CENTRE.x, FlowCrownDeck.CENTRE.y + 12.0,
			FlowCrownDeck.CENTRE.z)
	body.add_child(shape)
	root.add_child(body)


## The point on the fighting floor that the catapult lands on and every boss checkpoint saves.
func crown_landing() -> Vector3:
	return FlowCrownDeck.fight_point(root.get_tree())


## Advance `frames` physics ticks and let deferred work (GameFlow._start) run.
func settle(frames: int = SETTLE_FRAMES) -> void:
	for i in frames:
		await root.get_tree().physics_frame


func spire(index: int) -> FlowHiveSpire:
	var list := flow.spires()
	return list[index] if index < list.size() else null


## Damage a weak point the way a player weapon would, through the hurtbox part routing.
func hit(spire: FlowHiveSpire, part: StringName, amount: float) -> HitInfo:
	var info := HitInfo.make(amount, HitInfo.BALLISTIC, player, &"test")
	info.hurtbox_part = part
	spire.take_hit(info)
	return info


func burst_all_pods(spire: FlowHiveSpire) -> void:
	for i in FlowHiveSpire.PODS:
		hit(spire, StringName("pod_%d" % i), FlowHiveSpire.POD_HP)


# --- assertions -----------------------------------------------------------------------------------

func ok(condition: bool, what: String) -> bool:
	checks += 1
	if not condition:
		failures.append(what)
	return condition


func eq(got: Variant, want: Variant, what: String) -> bool:
	return ok(_same(got, want), "%s: got %s, want %s" % [what, str(got), str(want)])


func near(got: float, want: float, what: String, tol: float = 0.01) -> bool:
	return ok(absf(got - want) <= tol, "%s: got %.3f, want %.3f" % [what, got, want])


func fail(what: String) -> void:
	failures.append(what)


## A check that cannot run because a dependency outside flow is missing (another unit's model is
## mid-rebuild, say). Loud, counted and named, so a skipped check can never be read as a pass.
func skip(what: String) -> void:
	skips.append(what)
	print("TEST SKIP ", what)


func _same(a: Variant, b: Variant) -> bool:
	if a is float or b is float:
		return is_equal_approx(float(a), float(b))
	return a == b


func release_all() -> void:
	FlowEncounterWaves.reset_cache()
	# Drop the fake hero and world from the registry first: the audio listener tracks `Game.player`
	# every frame and would cast a freed node while the tree tears down.
	Game.player = null
	Game.world = null
	Game.camera_rig = _kept_rig
	if is_instance_valid(root):
		root.queue_free()
