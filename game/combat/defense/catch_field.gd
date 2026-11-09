class_name CatchField
extends RefCounted
## Mirror Guard's catch field (skills-catalog §4.4 S5, [TF-VS]): while the guard is held past 0.3 s,
## enemy shots entering a 12 m frontal hemisphere freeze and orbit the mech (≤24, 3 s max). Letting
## go throws them back in a 20° cone at 135 %.
##
## The field finds shots with a shape query on Layers.ENEMY_SHOT, so it works with the enemies unit's
## pooled `EnemyProjectile` without touching it: freezing is `set_physics_process(false)` and the
## orbit writes `global_position` directly. Returning uses the projectile's own `reflect()`.

var player: Node3D = null
var facing_provider: Callable = Callable()

var caught: Array[Node3D] = []
var _spin: float = 0.0
var _held: float = 0.0
## The velocity each frozen round had when it was caught, so a round let go without a throw (guard
## break, respawn) flies on instead of hanging in its orbit slot. Keyed by instance id, not shot meta:
## `EnemyProjectile.deactivate` only strips its own meta keys, so a meta would survive the pool.
var _velocities: Dictionary = {}

signal caught_one(shot: Node3D)
signal released(count: int)


func is_full() -> bool:
	return caught.size() >= DefenseTable.CATCH_MAX


func count() -> int:
	return caught.size()


func held_time() -> float:
	return _held


## One tick of the field: grab new shots inside the hemisphere, keep the held ones orbiting.
## Returns the number of shots newly caught.
func tick(delta: float) -> int:
	_spin += DefenseTable.CATCH_ORBIT_SPEED * delta
	_drop_dead()
	var gained := _capture()
	## The 3 s cap is a HOLD limit: it counts from the first catch, not from the field opening. Counting
	## from the open made a round caught after a long empty stretch bounce back on the tick it arrived.
	_held = 0.0 if caught.is_empty() else _held + delta
	_orbit()
	return gained


func _capture() -> int:
	if player == null or not is_instance_valid(player) or is_full():
		return 0
	var space := player.get_world_3d().direct_space_state
	if space == null:
		return 0
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = DefenseTable.CATCH_RADIUS
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, _center())
	params.collision_mask = Layers.ENEMY_SHOT
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var n := 0
	for r: Dictionary in space.intersect_shape(params, DefenseTable.CATCH_MAX * 2):
		var shot := _catchable(r["collider"] as Object)
		if shot == null:
			continue
		_freeze(shot)
		caught.append(shot)
		n += 1
		caught_one.emit(shot)
		if is_full():
			break
	return n


## A shot can be caught when it is reflectable, still flying at us and inside the frontal hemisphere.
func _catchable(col: Object) -> Node3D:
	if not (col is Node3D):
		return null
	var shot := col as Node3D
	if shot in caught or not is_instance_valid(shot):
		return null
	if not bool(shot.get_meta(&"reflectable", false)):
		return null
	if shot.has_method(&"is_reflected") and bool(shot.call(&"is_reflected")):
		return null
	if shot.has_method(&"is_active") and not bool(shot.call(&"is_active")):
		return null
	return shot if _in_front(shot.global_position) else null


func _freeze(shot: Node3D) -> void:
	shot.set_physics_process(false)
	var v: Variant = shot.get(&"velocity")
	if v is Vector3:
		_velocities[shot.get_instance_id()] = v as Vector3
		shot.set(&"velocity", Vector3.ZERO)


## Hands a frozen round its speed back before its physics comes on again.
func _restore(shot: Node3D) -> void:
	var id := shot.get_instance_id()
	if _velocities.has(id):
		shot.set(&"velocity", _velocities[id])
		_velocities.erase(id)


## The caught rounds spin in a disk in front of the shield, the Vortex Shield read (FEEL.md catch).
func _orbit() -> void:
	if caught.is_empty() or player == null or not is_instance_valid(player):
		return
	var centre := _center()
	var basis := _facing()
	var n := caught.size()
	for i in n:
		var shot := caught[i]
		if not is_instance_valid(shot):
			continue
		var a := _spin + TAU * float(i) / float(n)
		var offset := (basis.x * cos(a) + basis.z * sin(a)) * DefenseTable.CATCH_ORBIT_RADIUS
		shot.global_position = centre + offset \
				+ Vector3.UP * sin(a * 2.0) * DefenseTable.CATCH_ORBIT_HEIGHT * 0.35


## Throws every caught round back in a 20° cone at 135 %. Returns how many went out.
func release(towards: Vector3 = Vector3.INF) -> int:
	var n := caught.size()
	if n == 0:
		return 0
	var aim := _aim_dir(towards)
	var sent := 0
	for i in caught.size():
		var shot := caught[i]
		if not is_instance_valid(shot):
			continue
		var spread := _spread(i, n)
		var dir := aim.rotated(Vector3.UP, spread.x).rotated(_facing().x, spread.y).normalized()
		if shot.has_method(&"reflect"):
			shot.call(&"reflect", dir * DefenseTable.REFLECT_SPEED, player)
		_velocities.erase(shot.get_instance_id())
		shot.set_physics_process(true)
		sent += 1
	caught.clear()
	_velocities.clear()
	_held = 0.0
	if sent > 0:
		Feel.play(&"catch_release", _center(), 1.0)
		released.emit(sent)
	return sent


## Drops the rounds the world took away (expired, freed, or already spent).
func _drop_dead() -> void:
	var kept: Array[Node3D] = []
	var live: Dictionary = {}
	for shot in caught:
		if is_instance_valid(shot) and shot.is_inside_tree():
			kept.append(shot)
			live[shot.get_instance_id()] = true
	caught = kept
	for id: int in _velocities.keys():
		if not live.has(id):
			_velocities.erase(id)


## Lets every held round go without a throw (guard break, respawn): physics back on AND the speed the
## round had when it was caught, or it hangs at its orbit slot for the rest of its life.
func clear() -> void:
	for shot in caught:
		if is_instance_valid(shot):
			_restore(shot)
			shot.set_physics_process(true)
	caught.clear()
	_velocities.clear()
	_held = 0.0
	_spin = 0.0


## Even spread inside the release cone, alternating left/right so the volley reads as a fan.
func _spread(i: int, n: int) -> Vector2:
	if n <= 1:
		return Vector2.ZERO
	var half := deg_to_rad(DefenseTable.RELEASE_CONE_DEG) * 0.5
	var k := (float(i) / float(n - 1)) * 2.0 - 1.0
	return Vector2(k * half, sin(float(i) * 2.399) * half * 0.4)


func _aim_dir(towards: Vector3) -> Vector3:
	var centre := _center()
	var dir := towards - centre if towards != Vector3.INF else -_facing().z
	if dir.length_squared() < 0.0001:
		return -_facing().z
	return dir.normalized()


func _center() -> Vector3:
	if player == null or not is_instance_valid(player):
		return Vector3.ZERO
	return player.global_position + Vector3.UP * DefenseTable.CATCH_ORBIT_HEIGHT


func _facing() -> Basis:
	if facing_provider.is_valid():
		var b: Variant = facing_provider.call()
		if b is Basis:
			return b as Basis
	return player.global_basis if player != null and is_instance_valid(player) else Basis.IDENTITY


func _in_front(point: Vector3) -> bool:
	var to := point - _center()
	if to.length_squared() < 0.0001:
		return true
	var limit := cos(deg_to_rad(DefenseTable.CATCH_ARC_DEG * 0.5))
	return (-_facing().z).dot(to.normalized()) >= limit
