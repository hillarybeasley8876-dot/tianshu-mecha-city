extends Node
## Enemy projectile metadata test (enemies unit). Run:
##   tools/godot.sh test res://enemies/tests/test_projectile.gd
## The `&"hit"` / `&"owner"` / `&"reflectable"` metadata is a contract with the catch field and
## Mirror Guard (melee-defense), so it has to be honest in every state: published while a shot flies,
## withdrawn the moment it is pooled, never pointing at a freed shooter, and a caught round must
## come back with the player's own packet. A released shot must also leave the physics world.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const KEYS: Array[StringName] = [&"hit", &"owner", &"reflectable", &"reflected", &"blast_radius"]

var _fails: int = 0
var _checks: int = 0
var _world: Node3D
var _shooter: Node3D
var _attack: EnemyAttack


func _ready() -> void:
	_attack = EnemyAttack.make({
		"id": &"spitter_acid_lob", "kind": EnemyAttack.RANGED, "damage": 220.0, "impact": 40.0,
		"knockback": 6.0, "projectile_speed": 90.0, "blast_radius": 14.0, "reflectable": true,
	})
	await _build_world()
	_launched_metadata()
	await _expiry_clears_metadata()
	await _dead_shooter_is_dropped()
	_reflect_rewrites_the_packet()
	await _a_lob_lands()
	_print()


func _build_world() -> void:
	_world = (load(SANDBOX) as PackedScene).instantiate() as Node3D
	_world.name = "World"
	add_child(_world)
	Game.world = _world
	while not Game.world_built():
		await get_tree().physics_frame
	_shooter = Node3D.new()
	_shooter.name = "FakeSpitter"
	_world.add_child(_shooter)


func _fire() -> EnemyProjectile:
	return EnemyProjectilePool.spawn(_world, _shooter.global_position + Vector3.UP * 8.0,
			Vector3(0.0, 8.0, -160.0), _attack, _shooter)


## Pulls a fresh shot out of the pool, checks it really flies again, and puts it straight back so
## the test never leaks one.
func _reuse(shot: EnemyProjectile) -> EnemyProjectile:
	var again := _fire()
	_check("the pool recycles the shot it was given", again == shot,
			"got %s for %s" % [again.name, shot.name])
	_check("a reused shot flies again", again.is_active(),
			"the pool handed back a dead shot")
	EnemyProjectilePool.release(again)
	return again


# --- checks ------------------------------------------------------------------------------------

func _launched_metadata() -> void:
	var shot := _fire()
	_check("a flying shot publishes its packet", shot.has_meta(&"hit")
			and shot.get_meta(&"hit") is HitInfo, "")
	_check("a flying shot publishes its shooter", shot.has_meta(&"owner")
			and shot.get_meta(&"owner") == _shooter, "")
	_check("a reflectable shot says so", bool(shot.get_meta(&"reflectable", false)), "")
	_check("a flying shot is on ENEMY_SHOT", shot.collision_layer == Layers.ENEMY_SHOT,
			str(shot.collision_layer))
	_check("the shot is active", shot.is_active() and not shot.is_reflected(), "")
	EnemyProjectilePool.release(shot)


## The lead's r1 note: nothing may read a stale `&"hit"` off a pooled shot.
func _expiry_clears_metadata() -> void:
	var shot := _fire()
	EnemyProjectilePool.release(shot)
	var left: Array[StringName] = []
	for key: StringName in KEYS:
		if shot.has_meta(key):
			left.append(key)
	_check("a pooled shot publishes nothing", left.is_empty(), ", ".join(left))
	_check("a pooled shot is off every physics layer", shot.collision_layer == 0,
			str(shot.collision_layer))
	_check("a pooled shot is inactive", not shot.is_active(), "")
	await get_tree().physics_frame
	_check("a pooled shot does not move", shot.velocity == Vector3.ZERO, str(shot.velocity))
	_reuse(shot)


## A shooter that died while its round was in the air must not leave a dangling `&"owner"`.
func _dead_shooter_is_dropped() -> void:
	var shot := _fire()
	_shooter.queue_free()
	await get_tree().process_frame
	_check("a dead shooter is withdrawn from the metadata", not shot.has_meta(&"owner"),
			str(shot.get_meta(&"owner", "gone")))
	_check("the packet survives its shooter", shot.has_meta(&"hit"), "")
	EnemyProjectilePool.release(shot)
	_shooter = Node3D.new()
	_shooter.name = "FakeSpitter2"
	_world.add_child(_shooter)


func _reflect_rewrites_the_packet() -> void:
	var player := Node3D.new()
	player.name = "FakePlayer"
	_world.add_child(player)
	var shot := _fire()
	var before := (shot.get_meta(&"hit", null) as HitInfo).amount
	shot.reflect(Vector3(0.0, 0.0, 60.0), player)
	var packet := shot.get_meta(&"hit", null) as HitInfo
	_check("a reflected round comes back at 135 %", packet != null
			and is_equal_approx(packet.amount, before * 1.35), str(packet.amount if packet else "null"))
	_check("a reflected round belongs to the player", shot.get_meta(&"owner", null) == player
			and packet.source == player, "")
	_check("a reflected round is no longer catchable",
			not bool(shot.get_meta(&"reflectable", true)), "")
	_check("a reflected round is flagged and on PLAYER_SHOT", shot.is_reflected()
			and shot.collision_layer == Layers.PLAYER_SHOT, str(shot.collision_layer))
	_check("a reflected round flies again after the catch field froze it",
			shot.is_physics_processing(), "")
	EnemyProjectilePool.release(shot)
	player.queue_free()


## End to end: a lob fired at a standing target has to arrive, damage it, and return to the pool.
## Without this the metadata checks above would all pass on a shot that never hits anything.
func _a_lob_lands() -> void:
	var target := DummyPlayer.new()
	target.name = "Target"
	target.position = Vector3(0.0, 0.0, -180.0)
	_world.add_child(target)
	await get_tree().physics_frame
	var shot := EnemyProjectilePool.spawn(_world, Vector3(0.0, 14.0, 0.0),
			target.global_position + Vector3.UP * 8.0, _attack, _shooter)
	var waited := 0.0
	while target.hits == 0 and waited < 8.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_check("a lob lands on a standing target", target.hits == 1,
			"%d hits after %.1f s" % [target.hits, waited])
	_check("the landed hit came from this attack", target.last_weapon == _attack.id
			and target.damage_taken > 0.0, "%s / %.1f" % [target.last_weapon, target.damage_taken])
	_check("the landed damage is inside the blast falloff", target.damage_taken > 0.0
			and target.damage_taken <= _attack.damage + 0.01, "%.1f" % target.damage_taken)
	_check("the shot went back to the pool after landing", not shot.is_active()
			and EnemyProjectilePool.live_count() == 0,
			"live %d" % EnemyProjectilePool.live_count())
	target.queue_free()


func _check(what: String, ok: bool, detail: String) -> void:
	_checks += 1
	if ok:
		print("ok   %s" % what)
	else:
		_fails += 1
		print("FAIL %s — %s" % [what, detail])


func _print() -> void:
	print("PROJECTILE TEST %d checks, %d failures" % [_checks, _fails])
	print("PASS" if _fails == 0 else "FAIL")
	get_tree().quit(0 if _fails == 0 else 1)
