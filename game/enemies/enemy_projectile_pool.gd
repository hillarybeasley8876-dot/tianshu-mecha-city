class_name EnemyProjectilePool
extends RefCounted
## Pooled enemy shots (enemies-owned). CONTRACTS §2 allows 600 live projectiles; spawning a node per
## acid arc would churn the scene, so shots are reused. The pool parent is the world (or wherever the
## firing enemy lives), which keeps shots alive when their shooter dies.

const MAX_SHOTS := 128
const ARC_GRAVITY := EnemyProjectile.GRAVITY

static var _free: Array[EnemyProjectile] = []
static var _made: int = 0


## Fires `attack` from `from` at `to`. Arcing shots solve a ballistic elevation angle; flat shots
## aim straight. Returns the shot (already flying) or null when the pool is exhausted.
static func spawn(parent: Node, from: Vector3, to: Vector3, attack: EnemyAttack,
		shooter: Node) -> EnemyProjectile:
	if parent == null or not is_instance_valid(parent):
		push_error("EnemyProjectilePool: no parent for '%s'" % attack.id)
		return null
	var shot := _acquire(parent)
	if shot == null:
		return null
	var arc := attack.blast_radius > 0.0
	var vel := _arc_velocity(from, to, attack.projectile_speed) if arc \
			else (to - from).normalized() * attack.projectile_speed
	var hit := attack.build_hit(shooter)
	hit.position = from
	hit.knockback = vel.normalized() * attack.knockback
	shot.launch(from, vel, hit, shooter, attack.reflectable, arc, attack.blast_radius)
	return shot


static func _acquire(parent: Node) -> EnemyProjectile:
	while not _free.is_empty():
		var reused: EnemyProjectile = _free.pop_back()
		if is_instance_valid(reused):
			return reused
	if _made >= MAX_SHOTS:
		push_warning("EnemyProjectilePool: %d shots live, dropping the request" % _made)
		return null
	var shot := EnemyProjectile.new()
	shot.name = "EnemyShot%d" % _made
	_made += 1
	parent.add_child(shot)
	shot.tree_exited.connect(_on_exited.bind(shot))
	return shot


static func release(shot: EnemyProjectile) -> void:
	if shot == null or not is_instance_valid(shot) or not shot.is_active():
		return
	shot.deactivate()
	if not _free.has(shot):
		_free.append(shot)


static func live_count() -> int:
	var n := 0
	for s: EnemyProjectile in _free:
		if is_instance_valid(s):
			n += 1
	return _made - n


static func clear() -> void:
	_free.clear()
	_made = 0


static func _on_exited(shot: EnemyProjectile) -> void:
	_free.erase(shot)
	_made = maxi(_made - 1, 0)


## Ballistic lob: picks the flat trajectory that still reaches `to` at `speed`.
static func _arc_velocity(from: Vector3, to: Vector3, speed: float) -> Vector3:
	var delta := to - from
	var flat := Vector3(delta.x, 0.0, delta.z)
	var x := flat.length()
	var y := delta.y
	var s2 := speed * speed
	var disc := s2 * s2 - ARC_GRAVITY * (ARC_GRAVITY * x * x + 2.0 * y * s2)
	if disc < 0.0 or x < 0.01:
		return (delta.normalized() if delta.length() > 0.01 else Vector3.FORWARD) * speed
	var angle := atan((s2 - sqrt(disc)) / (ARC_GRAVITY * x))
	return flat.normalized() * speed * cos(angle) + Vector3.UP * speed * sin(angle)
