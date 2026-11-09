class_name EnemyBrainSearch
extends RefCounted
## The "I lost the player" half of EnemyBrain (enemies-owned, lead r12).
##
## Perception holds a target for `Perception.LOSE_MEMORY` after the last sighting and the monster
## chases the real position for all of it. What used to follow was the bug: with the target gone the
## brain kept steering at the remembered point's stand-off ring and circled it — moving, silent and
## blind — for the rest of the monster's life (Request 21: a spitter in the sandbox trench stayed
## silent for the rest of the run, and an arena that waits to be cleared never clears).
##
## This module is what happens instead: walk to where the player was, sweep the horizon from there,
## widen the search in rings until SEARCH_TIME runs out, then give up — drop the memory and walk
## back to the arena anchor, where the ordinary patrol takes over.

## EnemySpawner.LEASH_AFTER: the same "it is out of the fight" tolerance the spawner applies, so the
## brain and the director agree on how long a lost player is worth hunting.
const SEARCH_TIME := 8.0
const SEARCH_ARRIVE := 14.0      ## "I am standing where it was"
const SEARCH_LOOK := 2.0         ## seconds spent sweeping the horizon from a probe point
const SEARCH_SPEED := 0.85
const SWEEP_RATE := 1.7          ## rad/s the monster turns while looking around
## Probe radii around the last known position: the point itself, then rings that reach past the
## cover a player can hide behind. Six bearings each, so a search crosses its own ground.
const RINGS: Array[float] = [0.0, 45.0, 90.0, 150.0]
const BEARINGS := 6
const ANCHOR_ARRIVE := 16.0      ## home is Patrol's own arrive band, doubled

var brain: EnemyBrain
var host: EnemyBase
var origin: Vector3 = Vector3.ZERO
var point: Vector3 = Vector3.ZERO

var _left: float = 0.0
var _index: int = 0
var _look_left: float = 0.0
var _sweep: float = 0.0


func setup(brain_: EnemyBrain, host_: EnemyBase) -> void:
	brain = brain_
	host = host_


## Starts a fresh search from wherever the player was last seen.
func begin() -> void:
	origin = host.perception.hunt_point()
	_left = SEARCH_TIME
	_index = -1
	_look_left = 0.0
	_sweep = host.rotation.y
	_next_probe()


func reset() -> void:
	_left = 0.0
	_index = 0
	_look_left = 0.0


## One tick of either half. `searching` is true while the monster is still hunting and false once it
## has given up and is walking home. Returns the state the brain should be in afterwards.
func tick(dt: float, searching: bool) -> StringName:
	if host.target() != null:
		return EnemyBrain.APPROACH
	return _search(dt) if searching else _walk_home(dt)


func _search(dt: float) -> StringName:
	if not host.perception.has_hunt_point():
		return EnemyBrain.RETURN
	_left -= dt
	if _left <= 0.0:
		return _give_up()
	var to := point - host.global_position
	if flat(host.global_position, point) > SEARCH_ARRIVE:
		host.face_dir(to, dt)
		brain.go_to(point, SEARCH_SPEED, dt)
		host.set_locomotion(&"run")
		if host.is_flyer:
			host.face_dir_3d(host.velocity, dt)
		return EnemyBrain.SEARCH
	# Standing on the spot: look around. A monster that walks to the last known position and stares
	# at the wall in front of it is exactly the statue this state exists to remove.
	_look_left += dt
	host.loco.decelerate(dt)
	host.set_locomotion(&"idle")
	_sweep += dt * SWEEP_RATE
	var look := Vector3(-sin(_sweep), 0.0, -cos(_sweep))
	host.face_dir(look, dt)
	if host.is_flyer:
		host.face_dir_3d(Vector3(look.x, -0.15, look.z), dt)
	if _look_left >= SEARCH_LOOK:
		_next_probe()
	return EnemyBrain.SEARCH


## Probe 0 is the last known position itself; after that, rings of RINGS radii at BEARINGS bearings
## each, rotated by the monster's own flank offset so two pack members searching the same spot do
## not trace the same circle.
func _next_probe() -> void:
	_index += 1
	_look_left = 0.0
	if _index <= 0:
		point = origin
		return
	var i := _index - 1
	var ring: float = RINGS[1 + (i / BEARINGS) % (RINGS.size() - 1)]
	var bearing := TAU * float(i % BEARINGS) / float(BEARINGS) + brain.flank
	point = on_ground(origin + Vector3(cos(bearing), 0.0, sin(bearing)) * ring)


## Out of time. The memory goes with the search: keeping it is what made `_idle`'s patrol — the only
## thing that walks a monster back into view — unreachable once a fight had started.
func _give_up() -> StringName:
	host.perception.forget()
	return EnemyBrain.RETURN


func _walk_home(dt: float) -> StringName:
	var to := brain.home - host.global_position
	if flat(host.global_position, brain.home) <= ANCHOR_ARRIVE:
		return EnemyBrain.IDLE
	host.face_dir(to, dt)
	brain.go_to(brain.home, EnemyBrain.PATROL_SPEED, dt)
	host.set_locomotion(&"walk")
	if host.is_flyer:
		host.face_dir_3d(host.velocity, dt)
	return EnemyBrain.RETURN


## Horizontal distance: a flyer's probes and its anchor are on the ground, and a 3D test against a
## 45 m cruise height would mean it never "arrives" anywhere.
static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Snaps a probe to the archetype's own agent-class navmesh when the world has one (CONTRACTS §7),
## so a search point is somewhere the monster can actually stand.
func on_ground(at: Vector3) -> Vector3:
	var map := EnemyTypes.nav_map_for(host, host.enemy_type)
	if EnemyTypes.map_ready(map):
		return NavigationServer3D.map_get_closest_point(map, at)
	return at
