class_name EnemyLocomotion
extends RefCounted
## Enemy movement (enemies-owned): turning, ground steering, 3D flight steering with obstacle
## avoidance. Ground types walk straight at their target (the NavigationAgent3D on the world nav map
## supplies the path — see EnemyBrain); flyers never touch the navmesh and steer in 3D with
## whisker raycasts. Held by the EnemyBase as `loco`.

const ACCEL_FACTOR := 4.0        ## × move_speed per second
const DECEL_FACTOR := 5.0
const AVOID_RANGE := 30.0        ## flyer whisker length (m)
const AVOID_STRENGTH := 1.6
const AVOID_INTERVAL := 0.15     ## whiskers are re-cast a few times a second, not every tick
const REPATH_DISTANCE := 8.0     ## metres the goal may drift before the path is recomputed
const BLOCKED_FRACTION := 0.25   ## actual speed below this share of the request = wedged
const UNSTICK_AFTER := 1.0       ## seconds wedged before the monster pushes out of the crowd
const UNSTICK_TIME := 1.1
const BIND_RETRY := 0.5         ## seconds between attempts to pick up the world's agent-class map
const LEVEL_TOLERANCE := 12.0   ## a goal this far above/below the monster is another navmesh island
const DEGENERATE_GOAL := 25.0   ## only a two-corner path at least this long is worth checking
const RAY_LIFT := 1.5           ## the failed-path ray runs this far above the navmesh surface
const NAV_RETRY_AFTER := 60.0   ## seconds of direct steering after the navmesh failed a query

## Shared by every monster, not per-instance: Godot 4.7.2 logs an engine error for EVERY path query
## between disconnected navmesh islands (`_query_task_build_path_corridor`, "It's not expect to not
## find the most reachable polygons") and answers it with a degenerate start→end path instead of an
## empty one. The city's baked navmesh is 856–2005 islands per agent class with the biggest island
## only 10–14 % of its polygons, so nearly every query there fails and one 36 s fight logged 54 of
## them (lead note 02:40). The first failure therefore silences the whole unit for a minute and the
## monsters steer straight at their target — which is what the degenerate path made them do anyway.
static var _nav_broken_until: int = 0

var host: EnemyBase
var agent: NavigationAgent3D = null
var avoid_bias: Vector3 = Vector3.ZERO   ## separation from pack members, written by the brain
var _avoid_left: float = 0.0
var _avoid_cached: Vector3 = Vector3.ZERO
var _goal: Vector3 = Vector3.INF   ## last point handed to the NavigationServer
var _blocked_for: float = 0.0
var _unstick_left: float = 0.0
var _unstick_side: float = 1.0
var _class_map_bound: bool = false
var _check_pending: bool = false  ## a goal was just handed over; test the path it produces once
var _bind_left: float = 0.0


func setup(host_: EnemyBase, use_nav: bool) -> void:
	host = host_
	if not use_nav:
		return
	agent = NavigationAgent3D.new()
	agent.name = "Nav"
	agent.radius = EnemyTypes.get_stat(host.enemy_type, "radius", 3.0)
	agent.height = host.body_height
	agent.max_speed = host.move_speed
	agent.path_desired_distance = 3.0
	agent.target_desired_distance = 4.0
	# Server-side avoidance stays OFF: the pack separation bias in EnemyBrain does the same job for
	# a fraction of the cost, and NavigationAgent3D avoidance only pays off with velocity_computed.
	agent.avoidance_enabled = false
	agent.path_max_distance = 40.0
	host.add_child(agent)
	_bind_class_map()


## CONTRACTS §7: each archetype walks the navmesh baked for its agent class (small r 1.5 m, medium
## r 4 m, large r 9 m). The sandbox and any world without class maps keep the default map, which is
## what NavigationAgent3D uses until one is set — so this is a no-op there.
func _bind_class_map() -> void:
	if EnemyTypes.nav_class(host.enemy_type) == &"" or agent == null:
		return
	# An agent that is already on some other map was pinned there deliberately (a scripted set piece,
	# a test's own geometry): leave it alone rather than dragging it back to the world map.
	if agent.get_navigation_map() != host.get_world_3d().navigation_map:
		_class_map_bound = true
		return
	var map := EnemyTypes.nav_map_for(host, host.enemy_type)
	if EnemyTypes.map_ready(map):
		agent.set_navigation_map(map)
		_class_map_bound = true


## The class map may only exist once the world has finished building, so an unbound agent retries a
## few times a second until it gets one (and never after, so this costs nothing in the steady state).
func _try_bind_class_map(dt: float) -> void:
	if _class_map_bound or EnemyTypes.nav_class(host.enemy_type) == &"":
		return
	_bind_left -= dt
	if _bind_left > 0.0:
		return
	_bind_left = BIND_RETRY
	_bind_class_map()


## Ground types: follow the nav path to `point`. Returns the direction actually travelled.
## The goal is only handed to the NavigationServer when it has drifted REPATH_DISTANCE (or the path
## ran out): a path query per agent per frame costs ~0.4 ms each, which at 40 enemies is the whole
## physics budget on its own.
func nav_step(point: Vector3, speed_scale: float, dt: float) -> Vector3:
	if agent == null:
		return steer_to(point, speed_scale, dt)
	_try_bind_class_map(dt)
	agent.max_speed = host.move_speed * speed_scale * host.status.slow_factor
	# No queryable map yet (a city still syncing its class maps), or one that has just failed a
	# query: walk straight at the target rather than asking for a path the server cannot answer.
	if not nav_queryable():
		_clear_goal()
		return steer_to(point, speed_scale, dt)
	if _goal == Vector3.INF or point.distance_to(_goal) > REPATH_DISTANCE:
		_set_goal(point)
	if not has_goal():
		return steer_to(point, speed_scale, dt)
	var next := agent.get_next_path_position()
	var path := agent.get_current_navigation_path()
	if _check_pending and not path.is_empty():
		_check_pending = false
		if _path_failed(path):
			_note_nav_failure()
			_clear_goal()
			return steer_to(point, speed_scale, dt)
	var dir := next - host.global_position
	dir.y = 0.0
	if dir.length() < 0.5:
		dir = point - host.global_position
		dir.y = 0.0
	steer_dir(dir, speed_scale, dt)
	return dir.normalized() if dir.length() > 0.01 else Vector3.ZERO


## True while the world's navmesh may be asked for paths at all (see `_nav_broken_until`).
static func nav_queryable() -> bool:
	return Time.get_ticks_msec() >= _nav_broken_until


static func _note_nav_failure() -> void:
	_nav_broken_until = Time.get_ticks_msec() + int(NAV_RETRY_AFTER * 1000.0)


## A failed corridor comes back as a two-corner start→end path — which is also exactly what a
## straight successful path looks like, so the shape alone proves nothing (and
## `is_target_reachable()` calls both reachable, which is why the leash believed a monster stranded
## on another island was still fighting). Geometry separates them: a real two-corner path is a
## straight walkable tube, so scenery never crosses it. Only checked on the frame after a new goal,
## which is once per repath rather than once per tick.
func _path_failed(path: PackedVector3Array) -> bool:
	if path.size() != 2 or path[1].distance_to(path[0]) < DEGENERATE_GOAL:
		return false
	var lift := Vector3.UP * RAY_LIFT
	var q := PhysicsRayQueryParameters3D.create(path[0] + lift, path[1] + lift, Layers.MASK_SIGHT)
	q.exclude = [host.get_rid()]
	return not host.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Hands the goal to the NavigationServer, projected onto the agent's own map. Only points that sit
## on a polygon of the SAME level are ever queried: Godot 4.7.2 prints an engine error for every
## path query between disconnected navmesh islands ("It's not expect to not find the most reachable
## polygons") and returns a degenerate start→end pair instead of an empty path, so a monster
## chasing a player one deck up would spam the log once per repath (lead note 02:40). A goal on
## another level is not pathable anyway, so the monster steers straight at it instead — which is
## what the degenerate path made it do regardless, minus the error. Projection is also what makes
## `is_target_reachable()` honest: the player's origin is 7.5 m up per CONTRACTS §5, and an
## unprojected goal read as unreachable with the player standing on the deck (audit #5).
## `_goal` keeps the raw point so the repath-distance test still measures what the brain asked for.
func _set_goal(point: Vector3) -> void:
	var map := agent.get_navigation_map()
	if not EnemyTypes.nav_query_ready(host, host.enemy_type) or not EnemyTypes.map_ready(map):
		return
	var goal := NavigationServer3D.map_get_closest_point(map, point)
	var here := NavigationServer3D.map_get_closest_point(map, host.global_position)
	if absf(goal.y - here.y) > LEVEL_TOLERANCE:
		_clear_goal()
		return
	_goal = point
	_check_pending = true
	agent.target_position = goal


## Forces a repath on the next step: the spawner calls this after teleporting a leashed monster,
## whose cached path was computed from its old position.
func reset_path() -> void:
	_clear_goal()
	_blocked_for = 0.0
	_unstick_left = 0.0


## Drops the current goal so the next step asks for a fresh one (or steers directly). The agent's
## own target is left alone: an agent that is never asked for its next corner never queries.
func _clear_goal() -> void:
	_goal = Vector3.INF


## True once the agent has been given a goal. Without one `is_target_reachable()` answers about the
## default (0, 0, 0) target and is meaningless — it reported a stranded ripper as reachable.
func has_goal() -> bool:
	return _goal != Vector3.INF


func steer_to(point: Vector3, speed_scale: float, dt: float) -> Vector3:
	var to := point - host.global_position
	if not host.is_flyer:
		to.y = 0.0
	if to.length() < 0.05:
		decelerate(dt)
		return Vector3.ZERO
	var dir := to.normalized()
	steer_dir(dir, speed_scale, dt)
	return dir


## Flyers avoid scenery with three whiskers; ground types get the pack separation bias only.
## `dir` is normalised HERE, not by the callers: nav_step hands over a raw offset to the next corner
## (10–200 m long), and an unnormalised want made a lone ground monster target |offset| × move_speed
## and run at the 60 m/s cap (audit #4).
func steer_dir(dir: Vector3, speed_scale: float, dt: float) -> void:
	var want := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.ZERO
	if avoid_bias != Vector3.ZERO:
		want = (want + avoid_bias * AVOID_STRENGTH).normalized()
	if host.is_flyer:
		_avoid_left -= dt
		if _avoid_left <= 0.0:
			_avoid_left = AVOID_INTERVAL
			_avoid_cached = _avoidance(dir)
		if _avoid_cached != Vector3.ZERO:
			want = (want + _avoid_cached).normalized()
	want = _unstick(want, speed_scale, dt)
	var speed := host.move_speed * speed_scale * host.status.slow_factor
	var target_v := want * speed
	var accel := host.move_speed * ACCEL_FACTOR * dt
	host.velocity.x = move_toward(host.velocity.x, target_v.x, accel)
	host.velocity.z = move_toward(host.velocity.z, target_v.z, accel)
	if host.is_flyer:
		host.velocity.y = move_toward(host.velocity.y, target_v.y, accel)


## A monster that wants to move but is not moving is wedged on geometry — a trench wall, a crate, or
## (most often) the rest of the pack crushed around the player. After UNSTICK_AFTER seconds it stops
## steering at its goal and pushes out of the crowd instead: away from its neighbours if it has any,
## otherwise sideways along the obstacle. Enemies collide with each other per the brief's
## MASK_CHARACTER, so without this a pack can wall its own members in permanently.
func _unstick(want: Vector3, speed_scale: float, dt: float) -> Vector3:
	var requested := host.move_speed * speed_scale
	var actual := Vector3(host.velocity.x, 0.0, host.velocity.z).length()
	if requested > 1.0 and actual < requested * BLOCKED_FRACTION:
		_blocked_for += dt
	else:
		_blocked_for = maxf(0.0, _blocked_for - dt * 2.0)
	if _blocked_for >= UNSTICK_AFTER:
		_blocked_for = 0.0
		_unstick_left = UNSTICK_TIME
		_unstick_side = 1.0 if randf() < 0.5 else -1.0
	if _unstick_left <= 0.0:
		return want
	_unstick_left -= dt
	if avoid_bias.length_squared() > 0.0001:
		return (avoid_bias.normalized() * 2.0 + want * 0.3).normalized()
	var side := want.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	return (want * 0.4 + side.normalized() * _unstick_side * 1.6).normalized()


## Charge / leap movement at a fixed speed, ignoring steering.
func dash_along(dir: Vector3, speed: float, dt: float) -> void:
	var want := dir.normalized() * speed * host.status.slow_factor
	var rate := speed * 6.0 * dt
	host.velocity.x = move_toward(host.velocity.x, want.x, rate)
	host.velocity.z = move_toward(host.velocity.z, want.z, rate)
	if host.is_flyer:
		host.velocity.y = move_toward(host.velocity.y, want.y, rate)


func decelerate(dt: float) -> void:
	var rate := host.move_speed * DECEL_FACTOR * dt
	host.velocity.x = move_toward(host.velocity.x, 0.0, rate)
	host.velocity.z = move_toward(host.velocity.z, 0.0, rate)
	if host.is_flyer:
		host.velocity.y = move_toward(host.velocity.y, 0.0, rate)


## Casts ahead and to both sides; returns a push away from whatever is close (3D steering only).
func _avoidance(dir: Vector3) -> Vector3:
	var space := host.get_world_3d().direct_space_state
	var from := host.global_position
	var push := Vector3.ZERO
	var side := dir.cross(Vector3.UP).normalized()
	for offset: Vector3 in [Vector3.ZERO, side * 0.5, -side * 0.5, Vector3.DOWN * 0.3]:
		var to := from + (dir + offset).normalized() * AVOID_RANGE
		var q := PhysicsRayQueryParameters3D.create(from, to, Layers.MASK_SIGHT)
		q.exclude = [host.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit.get("normal", Vector3.UP)
		push += n * (1.0 - from.distance_to(hit["position"]) / AVOID_RANGE)
	return push
