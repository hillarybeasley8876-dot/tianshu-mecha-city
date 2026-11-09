class_name Perception
extends RefCounted
## Enemy senses (enemies-owned): sight cone + line of sight, hearing (gunfire), pack alert sharing.
## Owned by the EnemyBase that created it; `host` is that enemy.

signal target_acquired(target: Node3D)

const HEARING_RANGE := 400.0     ## Events.weapon_fired inside this range alerts the enemy
const PACK_ALERT_RANGE := 120.0  ## an alert spreads to pack members this far away
const SIGHT_INTERVAL := 0.12     ## seconds between LOS/sight tests (40 enemies stay cheap)
const LOSE_MEMORY := 10.0        ## seconds of no contact before the target is dropped
const PERIPHERAL := 0.25         ## inside sight_range × this, the cone test is skipped (awareness)

var host: Node3D
var sight_range: float = 320.0
var sight_half_angle: float = 80.0  ## degrees
var target: Node3D = null
var last_known: Vector3 = Vector3.ZERO  ## where the target was last seen — monsters hunt it

var _timer: float = 0.0
var _memory: float = 0.0
var _has_last: bool = false
var _alerted: bool = false
var _hunt_age: float = 0.0   ## seconds since `last_known` was refreshed (lead r12)


func configure(host_: Node3D, range_: float, half_angle_deg: float) -> void:
	host = host_
	sight_range = range_
	sight_half_angle = half_angle_deg


## `delta` is real seconds. Returns the current target (may be null).
func tick(delta: float) -> Node3D:
	_hunt_age += delta
	_timer -= delta
	if target != null and (not is_instance_valid(target) or not _target_alive(target)):
		target = null
	if _timer > 0.0:
		return target
	_timer = SIGHT_INTERVAL
	if target != null:
		if can_see(target):
			_memory = LOSE_MEMORY
			_remember(target.global_position)
		else:
			_memory -= SIGHT_INTERVAL
			if _memory <= 0.0:
				target = null
		return target
	var player := _player()
	if player != null and can_see(player):
		acquire(player, true)
	return target


func can_see(other: Node3D) -> bool:
	if host == null or other == null or not host.is_inside_tree():
		return false
	var to := other.global_position - host.global_position
	var dist := to.length()
	if dist > sight_range or dist < 0.001:
		return dist <= sight_range
	# Close by, a monster notices movement whatever way it is facing; far away it needs the cone.
	if dist > sight_range * PERIPHERAL:
		var fwd := -host.global_transform.basis.z
		if fwd.dot(to / dist) < cos(deg_to_rad(sight_half_angle)):
			return false
	return has_line_of_sight(other)


func has_line_of_sight(other: Node3D) -> bool:
	var space := host.get_world_3d().direct_space_state
	var from := host.global_position + Vector3.UP * 2.0
	var to := other.global_position + Vector3.UP * 2.0
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.MASK_SIGHT)
	q.exclude = [host.get_rid()]
	return space.intersect_ray(q).is_empty()


## Sets the target and optionally shouts the pack awake.
func acquire(other: Node3D, share: bool = true) -> void:
	if other == null or not is_instance_valid(other):
		return
	var fresh := target != other
	target = other
	_memory = LOSE_MEMORY
	_alerted = true
	_remember(other.global_position)
	if fresh:
		target_acquired.emit(other)
	if share:
		share_alert(other)


## Refreshes the remembered position and restarts its age. Every path that learns where the player
## is goes through here, so `hunt_age()` means one thing.
func _remember(at: Vector3) -> void:
	last_known = at
	_has_last = true
	_hunt_age = 0.0


## Seconds since the monster last knew where the player was. INF when it never has.
func hunt_age() -> float:
	return _hunt_age if _has_last else INF


## Drops the memory entirely: the brain has finished searching and goes back to its arena anchor.
## Without this the remembered point outlived the search and `_idle`'s patrol — the only thing that
## walks a monster back into view — was unreachable for the rest of the monster's life (lead r12).
func forget() -> void:
	_has_last = false
	_hunt_age = 0.0


## Where the monster should go when it cannot currently see the player (last known position).
func hunt_point() -> Vector3:
	if target != null and is_instance_valid(target):
		return target.global_position
	return last_known if _has_last else (host.global_position if host != null else Vector3.ZERO)


func has_hunt_point() -> bool:
	return target != null or _has_last


## juice §11.3 / Doom: an alert spreads to nearby pack members so a fight starts as a fight.
func share_alert(other: Node3D) -> void:
	if host == null or not host.is_inside_tree():
		return
	for n: Node in host.get_tree().get_nodes_in_group(&"enemy"):
		var e := n as Node3D
		if e == null or e == host or not is_instance_valid(e):
			continue
		if e.global_position.distance_to(host.global_position) > PACK_ALERT_RANGE:
			continue
		if e.has_method(&"on_pack_alert"):
			e.call(&"on_pack_alert", other)


## juice §11.3 / Doom: gunfire is a position fix. A monster that has never fought the player wakes
## up on it; one that is already hunting refreshes where it thinks the player is, because the shot
## it just heard came from there. The old code returned early once `_alerted`, so a monster that had
## lost the player ignored every shot the player fired behind cover and went on circling a stale
## point (lead r12).
func heard_shot(at: Vector3) -> void:
	if host == null or not host.is_inside_tree():
		return
	if host.global_position.distance_to(at) > HEARING_RANGE:
		return
	if not _alerted:
		var player := _player()
		if player != null:
			acquire(player)
		return
	if target != null and is_instance_valid(target) and can_see(target):
		return   ## it can already see them; the shot tells it nothing new
	_remember(at)


func is_alerted() -> bool:
	return _alerted


func distance_to_target() -> float:
	if target == null or not is_instance_valid(target):
		return INF
	return host.global_position.distance_to(target.global_position)


func clear() -> void:
	target = null
	_alerted = false
	_memory = 0.0
	_has_last = false
	_hunt_age = 0.0


func _player() -> Node3D:
	if Game.player != null and is_instance_valid(Game.player):
		return Game.player
	var found := host.get_tree().get_first_node_in_group(&"player") if host.is_inside_tree() else null
	return found as Node3D


func _target_alive(t: Node3D) -> bool:
	return not t.has_method(&"is_alive") or bool(t.call(&"is_alive"))
