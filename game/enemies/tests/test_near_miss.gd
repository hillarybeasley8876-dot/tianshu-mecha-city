extends Node
## Near-miss test (enemies unit). Run:
##   tools/godot.sh test res://enemies/tests/test_near_miss.gd -- --timeout=300
##
## juice-impact §11.3: enemy fire that passes close without touching the player gets one
## `Feel.play(&"near_miss")` at the closest point of its path. Every case below goes in through
## `EnemyProjectilePool.spawn` — the same call `EnemyStrike.spawn` makes — and is counted on
## `Feel.event_requested`, i.e. BEFORE the director's own 0.25 s row cooldown, so the count is the
## unit's calls and nothing else.
##
## Distances are measured from the player's hurtbox SURFACE (a 6 m-radius capsule), so a "0.5 R"
## pass is a round whose surface clears the mech's by 3 m.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const SHOT_SPEED := 90.0
const STANDOFF := 60.0      ## metres up-range the shots start and end
const AIM_Y := 8.0          ## the dummy's hurtbox centre
const FLIGHT_MAX := 2.5     ## seconds to wait for a shot to end
const EPS := 0.05

var _fails: int = 0
var _checks: int = 0
var _world: Node3D
var _player: DummyPlayer
var _shooter: Node3D
var _near: int = 0                 ## Feel.play(&"near_miss") calls since the last _take()
var _flat: EnemyAttack
var _lob: EnemyAttack


func _ready() -> void:
	_flat = EnemyAttack.make({
		"id": &"harrier_strafe", "kind": EnemyAttack.RANGED, "damage": 120.0, "impact": 20.0,
		"knockback": 4.0, "projectile_speed": SHOT_SPEED, "reflectable": true,
	})
	_lob = EnemyAttack.make({
		"id": &"spitter_acid_lob", "kind": EnemyAttack.RANGED, "damage": 220.0, "impact": 40.0,
		"knockback": 6.0, "projectile_speed": SHOT_SPEED, "blast_radius": 14.0, "reflectable": true,
	})
	Feel.event_requested.connect(_on_feel)
	await _build_world()
	await _flat_pass_inside_the_radius()
	await _flat_pass_outside_the_radius()
	await _direct_hit()
	await _lob_that_damages()
	await _reflected_round()
	await _caught_round()
	await _a_pooled_shot_counts_afresh()
	await _two_passes_in_a_row()
	await _a_moving_player_is_read_fresh()
	_print()


func _build_world() -> void:
	_world = (load(SANDBOX) as PackedScene).instantiate() as Node3D
	_world.name = "World"
	add_child(_world)
	Game.world = _world
	while not Game.world_built():
		await get_tree().physics_frame
	_player = DummyPlayer.new()
	_player.name = "Target"
	_world.add_child(_player)
	_shooter = Node3D.new()
	_shooter.name = "FakeHarrier"
	_world.add_child(_shooter)
	EnemyNearMiss.reset()
	await get_tree().physics_frame


func _on_feel(event: StringName, _at: Vector3, _strength: float) -> void:
	if event == &"near_miss":
		_near += 1


## Lateral offset that puts the round's SURFACE `factor * RADIUS` metres off the hurtbox surface.
func _offset(factor: float) -> float:
	return factor * EnemyNearMiss.RADIUS + _player.radius + EnemyProjectile.RADIUS


func _fire_flat(offset: float) -> EnemyProjectile:
	return EnemyProjectilePool.spawn(_world, Vector3(offset, AIM_Y, STANDOFF),
			Vector3(offset, AIM_Y, -STANDOFF), _flat, _shooter)


## Waits for the round to end (pooled, expired or detonated), then hands back the near-miss calls.
## A round still flying at the deadline is put back in the pool, so the next case starts clean.
func _settle(shot: EnemyProjectile) -> int:
	var waited := 0.0
	while shot != null and is_instance_valid(shot) and shot.is_active() and waited < FLIGHT_MAX:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	if shot != null and is_instance_valid(shot):
		EnemyProjectilePool.release(shot)
	var n := _near
	_near = 0
	return n


func _drain() -> Array[Dictionary]:
	return EnemyNearMiss.take_log()


func _check(what: String, ok: bool, detail: String) -> void:
	_checks += 1
	if ok:
		print("ok   %s" % what)
	else:
		_fails += 1
		print("FAIL %s — %s" % [what, detail])


# --- cases --------------------------------------------------------------------------------------

## The beat itself: a round that clears the mech by half the radius, and it fires within a tick of
## its closest approach rather than when the round finally expires.
func _flat_pass_inside_the_radius() -> void:
	var before := Time.get_ticks_msec()
	var shot := _fire_flat(_offset(0.5))
	var n := await _settle(shot)
	var rows := _drain()
	var ms := Time.get_ticks_msec() - before
	_check("a flat pass at 0.5 R plays one near miss", n == 1, "%d calls" % n)
	_check("the near miss is reported at the closest point (%.1f m)" % (EnemyNearMiss.RADIUS * 0.5),
			rows.size() == 1 and absf(float(rows[0]["distance"]) - EnemyNearMiss.RADIUS * 0.5) < 0.6,
			str(rows))
	_check("the near miss names the attack that fired it",
			rows.size() == 1 and StringName(rows[0]["attack"]) == &"harrier_strafe", str(rows))
	_check("the flyby plays while the round is still in the air, not on expiry",
			rows.size() == 1 and rows[0]["at"].distance_to(Vector3(_offset(0.5), AIM_Y, 0.0)) < 2.0,
			"%s after %d ms" % [str(rows), ms])


func _flat_pass_outside_the_radius() -> void:
	var shot := _fire_flat(_offset(1.5))
	var n := await _settle(shot)
	_drain()
	_check("a flat pass at 1.5 R plays none", n == 0, "%d calls" % n)


## A hit is a hit, whatever the hurtbox then does with it (i-frames, perfect dodge, --god).
func _direct_hit() -> void:
	var hits := _player.hits
	var shot := EnemyProjectilePool.spawn(_world, Vector3(0.0, AIM_Y, STANDOFF),
			Vector3(0.0, AIM_Y, 0.0), _flat, _shooter)
	var n := await _settle(shot)
	_drain()
	_check("a direct hit plays no near miss", n == 0, "%d calls" % n)
	_check("the direct hit actually landed on the dummy", _player.hits == hits + 1,
			"%d hits" % (_player.hits - hits))


## A lob whose burst reaches the player is a hit, not a miss.
func _lob_that_damages() -> void:
	var hits := _player.hits
	var shot := EnemyProjectilePool.spawn(_world, Vector3(0.0, 14.0, STANDOFF),
			Vector3(0.0, AIM_Y, 0.0), _lob, _shooter)
	var n := await _settle(shot)
	_drain()
	_check("a lob whose blast damages the player plays no near miss", n == 0, "%d calls" % n)
	_check("the lob's blast really did damage the dummy", _player.hits == hits + 1,
			"%d hits" % (_player.hits - hits))


## A caught round thrown back is the player's own shot now.
func _reflected_round() -> void:
	var shot := _fire_flat(_offset(0.5))
	for i in 12:
		await get_tree().physics_frame
	shot.reflect(Vector3(0.0, 0.0, -SHOT_SPEED), _player)
	var n := await _settle(shot)
	_drain()
	_check("a reflected round plays no near miss", n == 0, "%d calls" % n)


## A round the catch field held never counts, even after the field lets it go again: the field
## freezes it with set_physics_process(false) and writes its position directly (catch_field.gd:96).
func _caught_round() -> void:
	var shot := _fire_flat(_offset(0.5))
	for i in 12:
		await get_tree().physics_frame
	var held := shot.global_position
	shot.set_physics_process(false)
	shot.velocity = Vector3.ZERO
	await get_tree().process_frame
	await get_tree().process_frame
	shot.set_physics_process(true)
	shot.velocity = Vector3(0.0, 0.0, -SHOT_SPEED)
	var n := await _settle(shot)
	_drain()
	_check("a round the catch field held plays no near miss", n == 0, "%d calls" % n)
	_check("the held round really was frozen", held.distance_to(Vector3(_offset(0.5), AIM_Y,
			STANDOFF)) > 1.0, str(held))


## The pool hands the same node back for the next shot, and that flight gets its own beat.
func _a_pooled_shot_counts_afresh() -> void:
	var first := _fire_flat(_offset(0.5))
	await _settle(first)
	_drain()
	_near = 0
	var again := _fire_flat(_offset(0.5))
	_check("the pool reuses the round", again == first, "%s vs %s" % [again.name, first.name])
	var n := await _settle(again)
	_drain()
	_check("a reused round counts its near miss afresh", n == 1, "%d calls" % n)


## No second limiter on this side: two passes 0.1 s apart are two calls, and the row's own 0.25 s
## cooldown is the director's business.
func _two_passes_in_a_row() -> void:
	_near = 0
	var a := _fire_flat(_offset(0.5))
	for i in 12:
		await get_tree().physics_frame
	var b := _fire_flat(-_offset(0.5))
	var n := await _settle(a)
	n += await _settle(b)
	var rows := _drain()
	var inside := true
	for row: Dictionary in rows:
		inside = inside and float(row["distance"]) <= EnemyNearMiss.RADIUS + EPS
	_check("two passes 0.1 s apart are two calls", n == 2, "%d calls" % n)
	_check("every reported distance is inside the radius", inside and rows.size() == 2, str(rows))


func _print() -> void:
	print("NEAR MISS TEST %d checks, %d failures" % [_checks, _fails])
	print("PASS" if _fails == 0 else "FAIL")
	get_tree().quit(0 if _fails == 0 else 1)


## The hurtbox transforms must be read every tick, not cached with the node references: a mech at
## 60 m/s covers 15 m inside the cache window. The round here passes 1.5 R from where the dummy
## STARTS and 0.5 R from where it is when the round arrives, so a stale reading reports no miss.
func _a_moving_player_is_read_fresh() -> void:
	_player.global_position = Vector3.ZERO
	await get_tree().physics_frame
	var shot := _fire_flat(_offset(1.5))
	for i in 72:                      ## 0.6 s: the round is 6 m short of the dummy
		await get_tree().physics_frame
	_player.global_position = Vector3(_offset(1.5) - _offset(0.5), 0.0, 0.0)
	var n := await _settle(shot)
	var rows := _drain()
	_check("a player that moves into the round's path still gets its near miss", n == 1,
			"%d calls, %s" % [n, str(rows)])
	_player.global_position = Vector3.ZERO
	await get_tree().physics_frame
