class_name BossBrain
extends EnemyBrain
## The Brood Titan's combat loop (boss unit). EnemyBrain is built for a crowd: a shared attack-token
## economy, pack separation and a navmesh path per monster. A colossus is alone on a flat circular
## deck, so this subclass keeps the telegraph → active → recover machinery and replaces the rest:
##
##   - no attack tokens: it IS the pressure, and the swarm's 3-melee budget is not its budget
##   - no pack separation: its own adds must stay free to run under it
##   - direct steering instead of navmesh queries (one 60 m actor on a disc needs no path)
##   - its own rhythm: PHASE_CHAIN attacks back to back, then PHASE_REST (SPEC §7.1 uptime targets)

const STANDOFF := 70.0     ## metres it tries to keep from the player between attacks
const CIRCLE_SPEED := 0.22 ## rad/s it orbits at while it waits — the deck is a disc, so it circles

var titan: BroodTitan
var chain_left: int = 0
var rest_left: float = 0.0


func setup(host_: EnemyBase) -> void:
	super.setup(host_)
	titan = host_ as BroodTitan
	chain_left = _chain()


func _chain() -> int:
	return BossTuning.PHASE_CHAIN[clampi(_phase() - 1, 0, BossTuning.PHASE_CHAIN.size() - 1)]


func _rest() -> float:
	return BossTuning.PHASE_REST[clampi(_phase() - 1, 0, BossTuning.PHASE_REST.size() - 1)]


func _phase() -> int:
	return titan.phase if titan != null else 1


## No separation: the titan's own adds are supposed to be under it, and pushing a 400-tonne body
## around because a 6 m ripper is nearby would read as a bug.
func _separation(_dt: float) -> void:
	host.loco.avoid_bias = Vector3.ZERO


## In range and off cooldown, without touching the shared token pool.
func _ready_to_attack(dist: float) -> bool:
	if state == ATTACK or rest_left > 0.0 or host.status.is_staggered():
		return false
	for a: EnemyAttack in host.attacks():
		if dist < a.range_min or dist > a.range_max:
			continue
		if float(_cooldowns.get(a.id, 0.0)) > 0.0:
			continue
		return true
	return false


## Direct steering toward a point on the ring around the player; no navmesh, no path query.
func _approach(dt: float) -> void:
	if not _hunt_ok():
		state = IDLE
		return
	flank += dt * CIRCLE_SPEED
	_steer(_ring_point(), 1.0, dt)
	host.set_locomotion(&"walk")
	var dist := host.global_position.distance_to(host.perception.hunt_point())
	if dist <= host.engage_range * ARRIVE_TOLERANCE:
		if _ready_to_attack(dist):
			_begin_attack()
		else:
			state = POSITION
	elif _ready_to_attack(dist):
		# The beam, the summon and the storm all reach across the deck: it does not have to walk in
		# to use them, so a titan that never closes is still a titan that fights.
		_begin_attack()


func _position(dt: float) -> void:
	if not _hunt_ok():
		state = IDLE
		return
	flank += dt * CIRCLE_SPEED
	_steer(_ring_point(), 0.55, dt)
	host.face_dir(host.perception.hunt_point() - host.global_position, dt)
	host.set_locomotion(&"walk")
	if _ready_to_attack(host.global_position.distance_to(host.perception.hunt_point())):
		_begin_attack()


## After a chain the titan backs off and rests — the window of opportunity the player is meant to use
## to break a core (juice §11.1: "recovery length IS the window of opportunity").
func _reposition(dt: float) -> void:
	if not _hunt_ok():
		state = IDLE
		return
	flank += dt * CIRCLE_SPEED
	_steer(_ring_point(), 0.7, dt)
	host.face_dir(host.perception.hunt_point() - host.global_position, dt)
	host.set_locomotion(&"walk")
	rest_left -= dt
	_state_left -= dt
	if _state_left > 0.0:
		return
	if chain_left > 0 and _ready_to_attack(host.global_position.distance_to(
			host.perception.hunt_point())):
		_begin_attack()
	elif rest_left <= 0.0:
		chain_left = _chain()
		state = APPROACH


func _finish_attack() -> void:
	if current != null:
		_cooldowns[current.id] = current.cooldown
	current = null
	chain_left = maxi(chain_left - 1, 0)
	if chain_left <= 0:
		rest_left = _rest()
	# No token to release: BossBrain never takes one (see _ready_to_attack).
	state = REPOSITION
	_state_left = REPOSITION_TIME


func _begin_attack() -> void:
	super._begin_attack()
	rest_left = 0.0


func restart() -> void:
	super.restart()
	chain_left = _chain()
	rest_left = 0.0


func _hunt_ok() -> bool:
	return host.perception.has_hunt_point()


## The point on the ring around the player it wants to stand on, kept on the crown. The limit is the
## outer rim, NOT the top step: a 60 m body with an 18 m radius cannot circle a Ø80 core on a Ø208
## ring without being permanently hidden behind it, so it uses the whole deck and the core becomes
## the cover the PLAYER chooses to break line of sight with.
func _ring_point() -> Vector3:
	var hunt := host.perception.hunt_point()
	var point := hunt + Vector3(cos(flank), 0.0, sin(flank)) * STANDOFF
	var arena := host.get_tree().get_first_node_in_group(&"boss_arena") as BossArena
	if arena == null:
		return point
	var flat := Vector2(point.x - arena.global_position.x, point.z - arena.global_position.z)
	var limit := BossTuning.DECK_RADIUS - BossTuning.RADIUS
	if flat.length() > limit:
		flat = flat.normalized() * limit
		point.x = arena.global_position.x + flat.x
		point.z = arena.global_position.z + flat.y
	point.y = arena.floor_y_at(point)
	return point


func _steer(point: Vector3, speed_scale: float, dt: float) -> void:
	host.loco.steer_to(point, speed_scale, dt)
	if host.global_position.distance_to(host.perception.hunt_point()) > STANDOFF * 2.0:
		host.face_dir(host.velocity, dt)
	else:
		host.face_dir(host.perception.hunt_point() - host.global_position, dt)
