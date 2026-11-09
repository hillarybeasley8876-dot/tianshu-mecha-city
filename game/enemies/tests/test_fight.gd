extends Node
## Scripted fight with a zero-engine-error assertion, plus the path-query breaker regression
## (lead note 02:40). Run: tools/godot.sh test res://enemies/tests/test_fight.gd -- --timeout=400
##
## Phase 1 — a real fight in the sandbox: the full SPEC mix spawned around a dummy player that runs
## a wide arc and then leaves the deck for twelve seconds, which is what makes the spawner's leash
## relocate monsters; three of the pack are killed outright so death → wreck → dissolve → pool runs
## inside the same window. Asserts the whole run logs ZERO engine errors and ZERO degenerate
## transforms, that the fight actually happened, and that a healthy navmesh never trips
## EnemyLocomotion's breaker.
## Phase 2 — the path-query breaker itself. Godot 4.7.2 logs an engine error for every path query
## between disconnected navmesh islands and answers it with a two-corner start→end path, so the unit
## has to tell that apart from a straight successful path and then stop asking. Checked against a
## wall: the failed-path ray must see it, and a clear line must not.

const ErrorCounter := preload("res://tools/error_counter.gd")
const SANDBOX := "res://core/sandbox/sandbox.tscn"
const MIX := [[&"ripper", 8], [&"mantis", 2], [&"spitter", 2], [&"harrier", 2], [&"juggernaut", 1]]
const RUN_SECONDS := 30.0
const LIFT_AT := 9.0          ## the player leaves the deck here…
const LIFT_FOR := 12.0        ## …for this long, which is what strands ground monsters
const LIFT_HEIGHT := 300.0
const GROUND := Vector3(0.0, 2.0, 0.0)
const BAKE_FRAMES_MAX := 60000
const DT := 1.0 / 120.0
const ISLAND_A := Vector3(2000.0, 40.0, 0.0)   ## phase 2: one side of the wall…
const ISLAND_B := Vector3(2140.0, 40.0, 0.0)   ## …and the side no path can reach
const KILL_AT := 18.0         ## the player "kills" a few monsters here…
const KILL_COUNT := 3         ## …so death → wreck → dissolve → pool runs inside the error window
const SCAN_EVERY := 8         ## physics frames between degenerate-transform scans

var _fails: int = 0
var _checks: int = 0
var _counter: ErrorCounter
var _spawner: EnemySpawner
var _player: DummyPlayer
var _t: float = 0.0
var _telegraphs: int = 0
var _closest: Dictionary = {}    ## EnemyBase -> nearest it ever got to the player
var _running: bool = false
var _killed: int = 0
var _frames: int = 0
var _degenerate: int = 0
var _first_degenerate: String = ""


func _ready() -> void:
	_counter = ErrorCounter.new()
	OS.add_logger(_counter)
	await _build_world()
	_spawner = EnemySpawner.new()
	_spawner.auto_spawn = false
	add_child(_spawner)
	_player = DummyPlayer.new()
	_player.invulnerable = true     ## the fight must last the whole window, not end in a kill
	add_child(_player)
	_player.global_position = GROUND
	Game.player = _player
	Events.enemy_telegraph.connect(_on_telegraph)
	var spawned := 0
	for row: Array in MIX:
		for i in int(row[1]):
			var at := _spawner.place_around(GROUND, float(spawned) / 15.0, row[0])
			if _spawner.spawn(row[0], EnemySpawner.face_towards(at, GROUND)) != null:
				spawned += 1
	await get_tree().physics_frame
	for e: EnemyBase in _spawner.live_enemies():
		_closest[e] = INF
		e.wreck_lifetime = 1.0   ## a 30 s wreck would never dissolve inside the test window
	print("FIGHT TEST %d monsters spawned, running %.0f s" % [spawned, RUN_SECONDS])
	_running = true


func _build_world() -> void:
	var world := (load(SANDBOX) as PackedScene).instantiate()
	world.name = "World"
	add_child(world)
	Game.world = world
	var waited := 0
	while not Game.world_built() and waited < BAKE_FRAMES_MAX:
		await get_tree().physics_frame
		waited += 1
	print("SANDBOX navmesh ready after %d physics frames" % waited)


func _physics_process(delta: float) -> void:
	if not _running:
		return
	_t += delta
	_drive_player()
	_frames += 1
	if _frames % SCAN_EVERY == 0:
		_scan_degenerate(get_tree().root)
	if _t > KILL_AT and _killed < KILL_COUNT:
		_kill_one()
	for e: EnemyBase in _spawner.live_enemies():
		var d: float = e.global_position.distance_to(_player.global_position)
		_closest[e] = minf(float(_closest.get(e, INF)), d)
	if _t < RUN_SECONDS:
		return
	_running = false
	_report_fight.call_deferred()


func _on_telegraph(_enemy: Node, _attack: StringName, _kind: StringName) -> void:
	_telegraphs += 1


## A wide arc at 90 m, then straight up: a mech hovering 300 m over the deck is the case that used
## to make the leash measure against a point no navmesh polygon sits under.
func _drive_player() -> void:
	var angle := _t * 0.45
	var at := GROUND + Vector3(cos(angle), 0.0, sin(angle)) * 90.0
	if _t > LIFT_AT and _t < LIFT_AT + LIFT_FOR:
		at.y = GROUND.y + LIFT_HEIGHT
	_player.global_position = at


## Kills one monster outright, the way the player's own pipeline would.
func _kill_one() -> void:
	for e: EnemyBase in _spawner.live_enemies():
		var hit := HitInfo.make(e.hp_max * 2.0, HitInfo.BEAM, _player, &"fight_test")
		hit.hurtbox_part = &"body"
		e.take_hit(hit)
		_killed += 1
		return


## What `--nan-watch` does in a capture run (a zero-determinant basis is what a scale of exactly
## (0,0,0) produces), so the fight — not just the unit test — is covered for it.
func _scan_degenerate(node: Node) -> void:
	if node is Node3D:
		var xf := (node as Node3D).global_transform
		if not xf.origin.is_finite() or absf(xf.basis.determinant()) < 1e-12:
			_degenerate += 1
			if _first_degenerate == "":
				_first_degenerate = String((node as Node3D).get_path())
	for child in node.get_children():
		_scan_degenerate(child)


func _check(what: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("ok   %s" % what)
	else:
		_fails += 1
		print("FAIL %s — %s" % [what, detail])


func _report_fight() -> void:
	var errors := _counter.errors
	print("FIGHT telegraphs=%d errors=%d warnings=%d alive=%d"
			% [_telegraphs, errors, _counter.warnings, _spawner.alive_count()])
	for line in _counter.first_errors:
		print("FIGHT ERROR ", line)
	_check("a scripted fight logs 0 engine errors", errors == 0, "%d errors" % errors)
	_check("the pack actually attacks", _telegraphs >= 10, "%d telegraphs" % _telegraphs)
	_check("%d monsters died and dissolved" % _killed, _killed == KILL_COUNT and _degenerate == 0,
			"%d killed, %d degenerate transforms (first: %s)"
			% [_killed, _degenerate, _first_degenerate])
	var engaged := 0
	var stranded: Array[String] = []
	var map := _spawner.get_world_3d().navigation_map
	for e: EnemyBase in _closest:
		var near: float = _closest[e]
		if is_instance_valid(e) and near <= e.engage_range * 2.5:
			engaged += 1
		else:
			stranded.append("%s near %.0fm, now %.0fm off-mesh %.0fm goal=%s"
					% [e.enemy_type, near, e.global_position.distance_to(_player.global_position),
					NavigationServer3D.map_get_closest_point(map, e.global_position)
							.distance_to(e.global_position), e.loco.has_goal()])
	# The AI test's own bar is a stationary player; here the mech runs a 90 m arc and then leaves
	# the deck for ten seconds, so one straggler circling back is in spec, two is a lost monster.
	_check("the pack reaches the fight (at most one straggler)", engaged >= _closest.size() - 1,
			"%d of %d engaged; stranded: %s" % [engaged, _closest.size(), str(stranded)])
	_check("the leash never duplicates a monster", _spawner.alive_count() == 15 - _killed,
			"%d alive after %d kills" % [_spawner.alive_count(), _killed])
	_check("a healthy navmesh never trips the path-query breaker", EnemyLocomotion.nav_queryable(),
			"breaker is on after a fight on a 518-polygon navmesh")
	_off_mesh_placement()
	await _shattered_navmesh()
	_finish()


## The leash's own placement path with an off-mesh centre (the hovering player): the ring search
## may fall back to a raw bearing, but `spawn` must still put the monster on the ground.
func _off_mesh_placement() -> void:
	var map := _spawner.get_world_3d().navigation_map
	var high := GROUND + Vector3.UP * LIFT_HEIGHT
	var at := _spawner.place_around(high, 0.3, EnemyTypes.RIPPER)
	var e := _spawner.spawn(EnemyTypes.RIPPER, EnemySpawner.face_towards(at, high))
	await get_tree().physics_frame
	if e == null:
		_check("an off-mesh centre still spawns on the ground", false, "spawn returned null")
		return
	var on_mesh := NavigationServer3D.map_get_closest_point(map, e.global_position)
	_check("an off-mesh centre still spawns on the ground",
			on_mesh.distance_to(e.global_position) < EnemySpawner.GROUND_SNAP_MAX,
			"%.1f m off the navmesh" % on_mesh.distance_to(e.global_position))
	e.queue_free()


## Phase 2: the breaker's own logic, against a wall the failed-path ray has to see. Godot answers a
## query between disconnected islands with a two-corner start→end path — indistinguishable by shape
## from a straight successful one — so the corroboration is the scenery ray, and both halves of that
## decision are checked here.
func _shattered_navmesh() -> void:
	_wall_between()
	await get_tree().physics_frame   ## the new static body only enters the physics server next tick
	var e := _spawner.spawn(EnemyTypes.RIPPER, EnemySpawner.face_towards(ISLAND_A, ISLAND_B))
	if e == null:
		_check("the breaker fixture spawns", false, "spawn returned null")
		return
	e.set_ai_enabled(false)
	e.set_physics_process(false)
	e.global_position = ISLAND_A
	var across := PackedVector3Array([ISLAND_A, ISLAND_B])
	var clear := PackedVector3Array([ISLAND_A, ISLAND_A + Vector3(0.0, 0.0, 60.0)])
	_check("a two-corner path through a wall reads as a failed corridor", e.loco._path_failed(across),
			"the blocked straight line was accepted as a path")
	_check("a two-corner path across open ground is left alone", not e.loco._path_failed(clear),
			"a straight walkable path tripped the breaker")
	_check("a real multi-corner path is never a failure",
			not e.loco._path_failed(PackedVector3Array(
					[ISLAND_A, ISLAND_A + Vector3(40.0, 0.0, 0.0), ISLAND_B])),
			"a three-corner path was treated as a failed corridor")
	_check("a short hop is never a failure",
			not e.loco._path_failed(PackedVector3Array([ISLAND_A, ISLAND_A + Vector3(10.0, 0.0, 0.0)])),
			"a 10 m path was treated as a failed corridor")
	EnemyLocomotion._note_nav_failure()
	_check("one failed query silences the unit's path queries",
			not EnemyLocomotion.nav_queryable(), "breaker did not trip")
	for i in 30:
		e.loco.nav_step(ISLAND_B, 1.0, DT)
	_check("a silenced monster holds no goal and steers straight at its target",
			not e.loco.has_goal()
					and Vector3(e.velocity.x, 0.0, e.velocity.z).length() > e.move_speed * 0.5,
			"goal=%s |v|=%.1f m/s" % [e.loco.has_goal(),
			Vector3(e.velocity.x, 0.0, e.velocity.z).length()])
	e.queue_free()


## Scenery across the gap: the corroboration that tells a failed corridor from a straight path.
func _wall_between() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 60.0, 200.0)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = (ISLAND_A + ISLAND_B) * 0.5


func _finish() -> void:
	print("FIGHT TEST %d checks, %d failures" % [_checks, _fails])
	print("PASS" if _fails == 0 else "FAIL")
	get_tree().quit(0 if _fails == 0 else 1)
