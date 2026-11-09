extends Node
## Launch-flag integration test (enemies unit): boots the real `res://main.tscn` — the same path the
## shipping build and `tools/godot.sh run` take — and checks that the enemy part actually boots with
## it. Run:
##   tools/godot.sh test res://enemies/tests/test_main_spawn.gd -- --sandbox --enemies=ripper:6
##   tools/godot.sh test res://enemies/tests/test_main_spawn.gd -- --sandbox --no-enemies
##   tools/godot.sh test res://enemies/tests/test_main_spawn.gd -- --sandbox --enemies=ripper:4 --stub=enemies
## The stand-off is sampled two physics frames after the ring appears: at 55 m/s the fastest monster
## has moved under a metre, so the reading is still the spawn point.

const MAIN := "res://main.tscn"
const WANT := 6
const SETTLE_FRAMES := 2

var _fails: int = 0
var _checks: int = 0
var _spawner: EnemySpawner = null


func _ready() -> void:
	var packed := load(MAIN) as PackedScene
	if packed == null:
		push_error("test_main_spawn: cannot load " + MAIN)
		get_tree().quit(1)
		return
	add_child.call_deferred(packed.instantiate())
	await _wait_for_world()
	for i in SETTLE_FRAMES:
		await get_tree().physics_frame
	_report()


func _wait_for_world() -> void:
	var waited := 0.0
	while not Game.world_built() and waited < 120.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	for node in get_child(0).get_children():
		if node is EnemySpawner:
			_spawner = node as EnemySpawner


func _report() -> void:
	var want_enemies := Game.has_flag("enemies") and not Game.has_flag("no-enemies") \
			and not Game.stubbed("enemies")
	_check("main instances the enemy part", _spawner != null or Game.stubbed("enemies"),
			"no EnemySpawner child of Main")
	var count := _spawner.alive_count() if _spawner != null else 0
	var expected := WANT if want_enemies else 0
	_check("--enemies / --no-enemies / --stub=enemies gives %d monsters" % expected,
			count == expected, "got %d" % count)
	if _spawner == null or count == 0:
		_finish()
		return
	_check("the player is real", Game.player != null and Game.player.has_method(&"telemetry"), "")
	_check("every monster spawned outside the player's 150 m bubble", _stand_off_ok(),
			_stand_off_debug())
	_check("every monster landed on the navmesh", _on_navmesh(), _navmesh_debug())
	_check("telegraphs reach the global bus", await _telegraph_reaches_events(), "")
	_finish()


func _stand_off_ok() -> bool:
	for e: EnemyBase in _spawner.live_enemies():
		if e.global_position.distance_to(Game.player.global_position) < EnemySpawner.SPAWN_MIN - 5.0:
			return false
	return true


func _stand_off_debug() -> String:
	var parts: Array[String] = []
	for e: EnemyBase in _spawner.live_enemies():
		parts.append("%.0f" % e.global_position.distance_to(Game.player.global_position))
	return " ".join(parts)


## A monster must land on the navmesh whenever the navmesh actually reaches its spawn point. The
## core sandbox bakes a small arena whose mesh stops well short of the 150–250 m ring, and there the
## spawner is *supposed* to fall back to a ground ray — so a miss only counts when a mesh polygon was
## within `_grounded`'s own 60 m snap range and it still missed it.
func _on_navmesh() -> bool:
	for e: EnemyBase in _spawner.live_enemies():
		if e.is_flyer:
			continue
		var map := EnemyTypes.nav_map_for(_spawner, e.enemy_type)
		if not EnemyTypes.map_ready(map):
			return false
		var d := NavigationServer3D.map_get_closest_point(map, e.global_position) \
				.distance_to(e.global_position)
		if d > 12.0 and d <= 60.0:
			return false
	return true


func _navmesh_debug() -> String:
	var parts: Array[String] = []
	for e: EnemyBase in _spawner.live_enemies():
		var map := EnemyTypes.nav_map_for(_spawner, e.enemy_type)
		var d := -1.0
		if EnemyTypes.map_ready(map):
			d = NavigationServer3D.map_get_closest_point(map, e.global_position) \
					.distance_to(e.global_position)
		parts.append("%s:%s/%.1fm" % [e.enemy_type, EnemyTypes.map_ready(map), d])
	return " ".join(parts)


## The HUD threat arrows and the audio cues hang off Events.enemy_telegraph (lead r1 MUST-FIX 1).
func _telegraph_reaches_events() -> bool:
	var seen: Array[StringName] = []
	var on := func(_e: Node, attack: StringName, kind: StringName) -> void:
		seen.append(attack)
		print("TELEGRAPH %s (%s)" % [attack, kind])
	Events.enemy_telegraph.connect(on)
	for e: EnemyBase in _spawner.live_enemies():
		e.begin_telegraph(e.attacks()[0])
	Events.enemy_telegraph.disconnect(on)
	return seen.size() == _spawner.alive_count()


func _check(what: String, ok: bool, detail: String) -> void:
	_checks += 1
	if ok:
		print("ok   %s" % what)
	else:
		_fails += 1
		print("FAIL %s — %s" % [what, detail])


func _finish() -> void:
	print("MAIN SPAWN TEST %d checks, %d failures (flags: %s)" % [_checks, _fails,
			", ".join(PackedStringArray(Game.flags.keys()))])
	print("PASS" if _fails == 0 else "FAIL")
	get_tree().quit(0 if _fails == 0 else 1)
