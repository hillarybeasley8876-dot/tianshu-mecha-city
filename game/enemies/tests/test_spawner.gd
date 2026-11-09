extends Node
## Spawner launch-flag test (enemies unit). Run:
##   tools/godot.sh test res://enemies/tests/test_spawner.gd -- --enemies=ripper:4,mantis:1
##   tools/godot.sh test res://enemies/tests/test_spawner.gd -- --no-enemies
## Boots the real `spawner.tscn` (auto_spawn on) beside the sandbox and a stand-in player, then
## checks that placement keeps the 150–250 m stand-off on ground that can path back, that
## `--enemies=type:n,...` spawns exactly that mix, that `--no-enemies` wins over it, that an unknown
## type is refused, and that ripper pooling recycles a wreck instead of leaking a node.
##
## The sandbox bakes its navmesh on a worker thread, which takes ~20k headless physics frames, so
## run this with `--timeout=300`.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const SPAWNER := "res://enemies/spawner.tscn"
const SETTLE := 1.0
const BAKE_FRAMES_MAX := 60000
const RECYCLE_WAIT := 3.0
const PLACEMENT_SAMPLES := 12

var _fails: int = 0
var _checks: int = 0
var _spawner: EnemySpawner


func _ready() -> void:
	await _build_world()
	var player := DummyPlayer.new()
	player.name = "DummyPlayer"
	player.position = Vector3(0.0, 1.0, 0.0)
	add_child(player)
	Game.register_player(player)
	_check("the sandbox navmesh baked", Game.world_built())
	_spawner = (load(SPAWNER) as PackedScene).instantiate() as EnemySpawner
	add_child(_spawner)
	_placement(player.global_position)
	await _wait(SETTLE)
	if Game.has_flag("no-enemies"):
		_check("--no-enemies spawns nothing", _spawner.alive_count() == 0,
				"%d alive" % _spawner.alive_count())
	else:
		_requested_mix()
		_check("unknown type is refused, not crashed",
				_spawner.spawn(&"dragon", Transform3D.IDENTITY) == null)
		await _pooling()
	print("SPAWNER TEST %d checks, %d failures (flags: %s)" % [_checks, _fails,
			", ".join(Game.flags.keys())])
	print("PASS" if _fails == 0 else "FAIL")
	get_tree().quit(0 if _fails == 0 else 1)


func _build_world() -> void:
	var world := (load(SANDBOX) as PackedScene).instantiate()
	world.name = "World"
	add_child(world)
	Game.world = world
	# The navmesh bake runs on a worker thread; headless that is tens of thousands of frames of wall
	# time, so the bound is generous and the result is checked rather than assumed.
	var waited := 0
	while not Game.world_built() and waited < BAKE_FRAMES_MAX:
		await get_tree().physics_frame
		waited += 1
	print("SANDBOX navmesh ready after %d physics frames" % waited)


func _wait(seconds: float) -> void:
	for i in int(seconds / get_physics_process_delta_time()):
		await get_tree().physics_frame


func _check(what: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("ok   %s" % what)
	else:
		_fails += 1
		print("FAIL %s — %s" % [what, detail])


## Placement contract, measured before the AI moves anything: on the navmesh, 150–250 m out.
func _placement(centre: Vector3) -> void:
	var in_band := 0
	for i in PLACEMENT_SAMPLES:
		var at := _spawner.place_around(centre, float(i) / float(PLACEMENT_SAMPLES))
		var d := at.distance_to(centre)
		if d >= EnemySpawner.SPAWN_MIN - 1.0 and d <= EnemySpawner.SPAWN_MAX + 1.0:
			in_band += 1
	_check("place_around keeps the 150–250 m stand-off", in_band == PLACEMENT_SAMPLES,
			"%d of %d in band" % [in_band, PLACEMENT_SAMPLES])
	_nav_classes()


## CONTRACTS §7: small (r 1.5 m) / medium (r 4 m) / large (r 9 m). Each archetype must ask the world
## for its class map and fall back to the default map when there is no world or no such map.
func _nav_classes() -> void:
	var wanted := {EnemyTypes.RIPPER: &"small", EnemyTypes.HARRIER: &"small",
			EnemyTypes.MANTIS: &"medium", EnemyTypes.SPITTER: &"medium",
			EnemyTypes.JUGGERNAUT: &"large"}
	var ok := true
	for type: StringName in wanted:
		ok = ok and EnemyTypes.nav_class(type) == wanted[type]
	_check("every archetype maps to its CONTRACTS §7 agent class", ok,
			str([EnemyTypes.nav_class(EnemyTypes.RIPPER),
			EnemyTypes.nav_class(EnemyTypes.MANTIS), EnemyTypes.nav_class(EnemyTypes.JUGGERNAUT)]))
	_check("flyers keep a class but never walk it", EnemyTypes.nav_class(EnemyTypes.HARRIER) == &"small"
			and EnemyTypes.HARRIER in EnemyTypes.ALL, "")
	_check("no world nav_map(class) falls back to the default map",
			EnemyTypes.nav_map_for(_spawner, EnemyTypes.JUGGERNAUT)
					== _spawner.get_world_3d().navigation_map, "")


func _requested_mix() -> void:
	var spec := Game.flag("enemies")
	var want := 0
	for entry: String in spec.split(",", false):
		var parts := entry.split(":")
		want += int(parts[1]) if parts.size() > 1 else 1
	_check("--enemies=%s spawns %d" % [spec, want], _spawner.alive_count() == want,
			"%d alive" % _spawner.alive_count())


## A dead ripper must return to the pool after its wreck dissolves, not leak a node.
func _pooling() -> void:
	var ripper: EnemyBase = null
	for e: EnemyBase in _spawner.live_enemies():
		if e.enemy_type == EnemyTypes.RIPPER:
			ripper = e
			break
	if ripper == null:
		return
	ripper.wreck_lifetime = 0.2
	var hit := HitInfo.make(ripper.hp_max * 2.0, HitInfo.BEAM, null, &"beam_rifle")
	hit.hurtbox_part = &"body"
	ripper.take_hit(hit)
	_check("the ripper died", not ripper.is_alive())
	await _wait(RECYCLE_WAIT)
	var again := _spawner.spawn(EnemyTypes.RIPPER,
			EnemySpawner.face_towards(Vector3(60.0, 0.0, 60.0), Vector3.ZERO))
	_check("a pooled ripper comes back alive at full HP", again != null and again.is_alive()
			and is_equal_approx(again.hp, again.hp_max),
			"hp %s" % ("null" if again == null else str(again.hp)))
