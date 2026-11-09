extends Node
## Spawn-safety test (enemies unit). Run:
##   tools/godot.sh test res://enemies/tests/test_spawn_safety.gd -- --sandbox --no-enemies --timeout=300
##
## Lead r11 item 1: `EnemySpawner.spawn()` used to `add_child(enemy)` and only then move it, so a new
## monster was a solid body standing on the spawner's own origin for one tick. Anything resting there
## — the hero at world (0,0,0), the titan on its AddSpawner — took that body as its floor and then
## inherited the jump to the spawn point as platform velocity: the hero was thrown at ~16 km/s.
##
## Two paths are checked:
##   A. the real one — `res://main.tscn --sandbox`, the real PlayerMech standing on main's spawner
##      origin, one monster of every archetype spawned 40-60 m away, 60 ticks of watch each;
##   B. a spawner under a TRANSLATED, ROTATED parent with a plain CharacterBody3D in `move_and_slide`
##      on its origin, where every new monster's position is sampled at `SceneTree.node_added` —
##      the moment it enters the tree, before anything can move it.

const MAIN := "res://main.tscn"
const SETTLE_TICKS := 120     ## let the mech land and stop before the trial
const WATCH_TICKS := 60       ## 0.5 s of physics after each spawn
const MOVE_LIMIT := 0.1       ## metres the stander may drift
const SPEED_LIMIT := 1.0      ## m/s peak
const SPAWN_DIST := 50.0
## One monster of every archetype, each on a different bearing (normalised when it is used).
const TRIALS: Array[Array] = [
	[EnemyTypes.RIPPER, Vector3(0.0, 0.0, -1.0)],
	[EnemyTypes.RIPPER, Vector3(0.7, 0.0, 0.7)],
	[EnemyTypes.MANTIS, Vector3(1.0, 0.0, 0.0)],
	[EnemyTypes.SPITTER, Vector3(0.0, 0.0, 1.0)],
	[EnemyTypes.HARRIER, Vector3(-1.0, 0.0, 0.0)],
	[EnemyTypes.JUGGERNAUT, Vector3(-0.7, 0.0, -0.7)],
]

var _fails: int = 0
var _checks: int = 0
var _main: Node
var _spawner: EnemySpawner
var _player: Node3D
var _last_detail: String = ""


func _ready() -> void:
	if await _boot_main():
		await _real_path()
	await _transformed_parent()
	_print()


## Boots the shipping scene and finds main's own EnemySpawner (a direct child, at the origin).
func _boot_main() -> bool:
	var packed := load(MAIN) as PackedScene
	if packed == null:
		push_error("test_spawn_safety: cannot load " + MAIN)
		get_tree().quit(1)
		return false
	_main = packed.instantiate()
	_main.name = "Main"
	add_child(_main)
	var waited := 0.0
	while not Game.world_built() and waited < 120.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	for node in _main.get_children():
		if node is EnemySpawner:
			_spawner = node as EnemySpawner
	_player = Game.player as Node3D
	_check("main instances the enemy spawner", _spawner != null, "no EnemySpawner child of Main")
	_check("main has a real PlayerMech", _player != null and _player.has_method(&"debug_teleport"),
			str(_player))
	if _spawner == null or _player == null:
		return false
	_spawner.auto_spawn = false
	_spawner.leash = false   ## the leash relocates stranded monsters; this test is about placement
	return true


# --- A. the real path ---------------------------------------------------------------------------

func _real_path() -> void:
	var origin := _spawner.global_position
	print("SPAWN SAFETY spawner at %s, player %s" % [origin, _player.global_position])
	_check("a control run with no spawn leaves the hero still", await _quiet_trial(), _last_detail)
	for row: Array in TRIALS:
		var type: StringName = row[0]
		var ok := await _trial(type, (row[1] as Vector3).normalized())
		_check("a %s spawned %.0f m away does not move the hero" % [type, SPAWN_DIST], ok,
				_last_detail)


## One trial: settle the mech on the spawner's origin, watch it for WATCH_TICKS with nothing
## happening (the control), then spawn one monster and watch again. Both have to be quiet: a
## control that already drifts would make the spawn check meaningless.
func _trial(type: StringName, dir: Vector3) -> bool:
	await _place_player()
	var control := await _drift()
	var spawned := await _drift(type, dir)
	_spawner.clear()
	await get_tree().physics_frame
	_last_detail = "control[%s] spawn[%s]" % [control, spawned]
	return control == "" and spawned == ""


func _quiet_trial() -> bool:
	await _place_player()
	_last_detail = await _drift()
	return _last_detail == ""


func _place_player() -> void:
	_spawner.clear()
	await get_tree().physics_frame
	var at := _spawner.global_position + Vector3.UP * 8.0
	_player.call(&"debug_teleport", [at.x, at.y, at.z], 0.0)
	for i in SETTLE_TICKS:
		await get_tree().physics_frame


## Watches the mech for WATCH_TICKS, spawning `type` on the first tick when one is given. Returns
## "" when it stayed put, else a readable description of how it did not.
func _drift(type: StringName = &"", dir: Vector3 = Vector3.ZERO) -> String:
	var p0: Vector3 = _player.global_position
	var peak := 0.0
	for i in WATCH_TICKS:
		if i == 0 and type != &"":
			var at := p0 + dir * SPAWN_DIST
			_spawner.spawn(type, EnemySpawner.face_towards(at, p0))
		await get_tree().physics_frame
		peak = maxf(peak, (_player as CharacterBody3D).velocity.length())
	var moved := _player.global_position.distance_to(p0)
	if moved <= MOVE_LIMIT and peak < SPEED_LIMIT:
		return ""
	return "moved %.3f m at up to %.2f m/s" % [moved, peak]


# --- B. a transformed parent ----------------------------------------------------------------------

## A plain CharacterBody3D resting on the spawner's origin, in `move_and_slide` like the hero. It is
## the stand-in for "whatever is standing where the spawner is" — the hero at world (0,0,0), the
## titan on its AddSpawner.
class Stander:
	extends CharacterBody3D

	func _physics_process(delta: float) -> void:
		if not is_on_floor():
			velocity.y -= 56.0 * delta
		move_and_slide()


## The spawner under a translated, rotated parent: a monster must land where it was sent whatever
## the spawner's own transform is, and it must be there from the moment it enters the tree.
func _transformed_parent() -> void:
	var root := Node3D.new()
	root.name = "SpawnRig"
	root.transform = Transform3D(Basis.from_euler(Vector3(0.0, deg_to_rad(37.0), 0.0)),
			Vector3(120.0, 0.0, -80.0))
	add_child(root)
	var spawner := EnemySpawner.new()
	spawner.name = "RigSpawner"
	spawner.auto_spawn = false
	spawner.leash = false
	root.add_child(spawner)
	var stander := Stander.new()
	stander.name = "Stander"
	stander.collision_layer = Layers.PLAYER
	stander.collision_mask = Layers.MASK_CHARACTER
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 5.0
	cap.height = 16.0
	shape.shape = cap
	shape.position = Vector3.UP * 8.0
	stander.add_child(shape)
	root.add_child(stander)
	for i in SETTLE_TICKS:
		await get_tree().physics_frame
	var at_entry: Array[Vector3] = []
	var on_added := func(node: Node) -> void:
		if node is EnemyBase and node.get_parent() == spawner:
			at_entry.append((node as EnemyBase).global_position)
	get_tree().node_added.connect(on_added)
	var ok := true
	var detail := ""
	for row: Array in TRIALS:
		var type: StringName = row[0]
		var dir: Vector3 = (row[1] as Vector3).normalized()
		var p0 := stander.global_position
		var peak := 0.0
		at_entry.clear()
		var at := root.global_position + dir * SPAWN_DIST
		var e := spawner.spawn(type, EnemySpawner.face_towards(at, p0))
		var landed: Vector3 = e.global_position if e != null else Vector3.INF
		var entry: Vector3 = at_entry[0] if at_entry.size() == 1 else Vector3.INF
		if entry.distance_to(landed) > 0.01:
			ok = false
			detail = "%s entered the tree at %s (%d samples), not at its spawn point %s" \
					% [type, entry, at_entry.size(), landed]
		for i in WATCH_TICKS:
			await get_tree().physics_frame
			peak = maxf(peak, stander.velocity.length())
		var moved := stander.global_position.distance_to(p0)
		if moved > MOVE_LIMIT or peak >= SPEED_LIMIT:
			ok = false
			detail = "%s moved the stander %.3f m at up to %.2f m/s" % [type, moved, peak]
		spawner.clear()
		await get_tree().physics_frame
	get_tree().node_added.disconnect(on_added)
	_check("a spawner under a translated, rotated parent places every monster at its spawn point",
			ok, detail)
	root.queue_free()


func _check(what: String, ok: bool, detail: String) -> void:
	_checks += 1
	if ok:
		print("ok   %s" % what)
	else:
		_fails += 1
		print("FAIL %s — %s" % [what, detail])


func _print() -> void:
	print("SPAWN SAFETY TEST %d checks, %d failures" % [_checks, _fails])
	print("PASS" if _fails == 0 else "FAIL")
	get_tree().quit(0 if _fails == 0 else 1)
