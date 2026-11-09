class_name EnemyBrain
extends RefCounted
## Enemy AI (enemies-owned): a small hierarchical state machine every archetype shares.
##
##   idle → alert → approach → (position ⇄) attack(telegraph → active → recover) → reposition → …
##   approach/position/reposition → search (it lost the player) → return (gave up) → idle
##   any  → staggered (stability broken) → dead
##
## Fairness (juice §11.3, brief): at most AttackTokenPool.LIMIT_MELEE monsters swing at the player
## and LIMIT_RANGED lob at once; the rest circle at their stand-off distance. Every attack announces
## itself with a telegraph of ≥ 350 ms before its active window (juice §11.1) — the brain never
## damages anything inside the telegraph.

const IDLE := &"idle"
const ALERT := &"alert"
const APPROACH := &"approach"
const POSITION := &"position"
const ATTACK := &"attack"
const REPOSITION := &"reposition"
const SEARCH := &"search"
const RETURN := &"return"
const STAGGERED := &"staggered"
const DEAD := &"dead"

const TELEGRAPH := &"telegraph"
const ACTIVE := &"active"
const RECOVER := &"recover"

const ALERT_TIME := 0.25       ## the "it saw you" beat before it commits
const REPOSITION_TIME := 0.9   ## back off after a swing (window of opportunity for the player)
const SEPARATION_INTERVAL := 0.2
const SEPARATION_RADIUS := 1.8  ## × body radius
const ARRIVE_TOLERANCE := 1.2    ## "in range" band, so a monster on the ring line still commits
const PATROL_RADIUS := 70.0      ## how far an idle monster wanders from where it was spawned
const PATROL_LEG := 9.0          ## seconds before it picks a new patrol point
const PATROL_ARRIVE := 8.0
const PATROL_SPEED := 0.35       ## fraction of move_speed


var host: EnemyBase
var home: Vector3 = Vector3.ZERO    ## the arena anchor: where it was spawned, and where it walks back to
var flank: float = 0.0              ## this monster's own bearing around the player
var state: StringName = IDLE
var phase: StringName = RECOVER
var current: EnemyAttack = null

var _phase_left: float = 0.0
var _state_left: float = 0.0
var _hit_done: bool = false
var _spawned: bool = false
var _token: StringName = &""
var _cooldowns: Dictionary = {}
var _options: Array[EnemyAttack] = []   ## rows _ready_to_attack cleared this tick
var _sep_left: float = 0.0
var _patrol_point: Vector3 = Vector3.ZERO
var _patrol_left: float = 0.0
var _search: EnemyBrainSearch

## Optional self-profiler (the AI test turns it on): microseconds spent inside think() across all
## monsters. Wall-clock physics monitors move with machine load; this number does not.
static var profiling: bool = false
static var think_us: int = 0
static var think_calls: int = 0


func setup(host_: EnemyBase) -> void:
	host = host_
	flank = randf() * TAU
	home = host.global_position
	_patrol_point = host.global_position
	_search = EnemyBrainSearch.new()
	_search.setup(self, host)


func think(dt: float) -> void:
	if profiling:
		var t0 := Time.get_ticks_usec()
		_think(dt)
		think_us += Time.get_ticks_usec() - t0
		think_calls += 1
	else:
		_think(dt)


func _think(dt: float) -> void:
	_tick_cooldowns(dt)
	_separation(dt)
	if host.status.is_staggered():
		_enter_staggered()
	elif state == STAGGERED:
		state = APPROACH
	match state:
		IDLE: _idle(dt)
		ALERT: _alert(dt)
		APPROACH: _approach(dt)
		POSITION: _position(dt)
		ATTACK: _attack(dt)
		REPOSITION: _reposition(dt)
		SEARCH, RETURN: state = _search.tick(dt, state == SEARCH)
		STAGGERED: _staggered(dt)
		_: pass


func _idle(dt: float) -> void:
	host.loco.decelerate(dt)
	host.set_locomotion(&"idle")
	_patrol(dt)
	if host.target() != null:
		state = ALERT
		_state_left = ALERT_TIME
	elif host.perception.has_hunt_point():
		state = APPROACH   ## it remembers where the player was: go look


## Idle monsters walk a slow circuit around where they were spawned, so nothing in the world is
## ever a statue and a monster that starts behind cover eventually walks into view.
func _patrol(dt: float) -> void:
	_patrol_left -= dt
	if _patrol_left <= 0.0 \
			or EnemyBrainSearch.flat(host.global_position, _patrol_point) < PATROL_ARRIVE:
		_patrol_point = _pick_patrol_point()
		_patrol_left = PATROL_LEG
		return
	go_to(_patrol_point, PATROL_SPEED, dt)
	host.set_locomotion(&"walk")


## Ground types follow the navmesh to `point`, flyers steer at it. The one place the brain asks for
## locomotion, so patrol, search and the walk home cannot drift apart.
func go_to(point: Vector3, speed: float, dt: float) -> void:
	if host.is_flyer:
		host.loco.steer_to(point, speed, dt)
	else:
		host.loco.nav_step(point, speed, dt)


func _pick_patrol_point() -> Vector3:
	var angle := randf() * TAU
	var probe := home + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(20.0, PATROL_RADIUS)
	var map := EnemyTypes.nav_map_for(host, host.enemy_type)
	if EnemyTypes.map_ready(map):
		return NavigationServer3D.map_get_closest_point(map, probe)
	return probe


func _alert(dt: float) -> void:
	host.loco.decelerate(dt)
	host.set_locomotion(&"idle")
	host.face_dir(host.target_centre() - host.global_position, dt)
	_state_left -= dt
	if _state_left <= 0.0:
		state = APPROACH


## In combat range a monster watches the player, not its feet; far away it faces where it is going.
## The far threshold is the larger of three engage rings and half its sight range: a juggernaut
## (engage 40 m, sight 400 m) used to look at its own feet from 120 m out, which is how a monster
## that was still closing lost the player it was closing on (lead r12).
func _face_sensibly(dt: float) -> void:
	var to_target := host.perception.hunt_point() - host.global_position
	var dist := to_target.length()
	if dist <= maxf(host.engage_range * 3.0, host.perception.sight_range * 0.5):
		host.face_dir(to_target, dt)
	else:
		host.face_dir(host.velocity if host.velocity.length() > 1.0 else to_target, dt)


## Every fighting state starts here: with no live target there is nothing to fight, so the monster
## either goes looking (it still remembers where the player was) or, with no memory at all, falls
## back to its patrol. Returning false means "this state is done, the caller must stop".
func _check_blind() -> bool:
	if host.target() != null:
		return true
	if host.perception.has_hunt_point():
		state = SEARCH
		_search.begin()
	else:
		state = IDLE
	return false


func _approach(dt: float) -> void:
	if not _check_blind():
		return
	var hunt := host.perception.hunt_point()
	flank += dt * host.circle_speed * 0.5   ## drift around the ring instead of parking on it
	var point := host.desired_point(flank)
	_face_sensibly(dt)
	host.approach(point, dt)
	host.set_locomotion(&"run")
	if host.is_flyer:
		host.face_dir_3d(host.velocity, dt)
	var dist := host.global_position.distance_to(hunt)
	if dist <= host.engage_range * ARRIVE_TOLERANCE or _standoff_ready(dist):
		if _ready_to_attack(dist):
			_begin_attack()
		elif dist <= host.engage_range * ARRIVE_TOLERANCE:
			state = POSITION   ## in range but no token: circle instead of standing still


## True when an attack that deliberately reaches beyond the engage ring can start from `dist` — the
## juggernaut's 80–260 m charge (engage 40 m), the brute's answer to a real gap. Gating every commit
## on the engage ring alone made that attack unreachable: by the time the monster was allowed to
## swing it had always walked inside the charge's own minimum range, so it never charged and the roar
## that announces the charge never played (lead r10). A short attack (range_min inside the ring) is
## not a standoff option — a ripper still has to close to 21 m before it leaps.
func _standoff_ready(dist: float) -> bool:
	var band := host.engage_range * ARRIVE_TOLERANCE
	for a: EnemyAttack in host.attacks():
		if a.range_min > band and dist >= a.range_min and dist <= a.range_max \
				and float(_cooldowns.get(a.id, 0.0)) <= 0.0:
			return true
	return false


func _position(dt: float) -> void:
	if not _check_blind():
		return
	flank += dt * host.circle_speed
	var point := host.desired_point(flank)
	host.face_dir(host.perception.hunt_point() - host.global_position, dt)
	host.approach(point, dt)
	host.set_locomotion(&"walk")
	var dist := host.global_position.distance_to(host.perception.hunt_point())
	if _ready_to_attack(dist):
		_begin_attack()
	elif dist > host.engage_range * 2.5:
		state = APPROACH


# --- attack -------------------------------------------------------------------------------------

## True when an attack is off cooldown, in range and a fairness token is free. Needs a LIVE target:
## a ranged attack started against a remembered hunt point fires from the muzzle back at the
## monster's own body, because a shot has no target to aim at (audit #12).
##
## The rows that pass the range and cooldown tests are left in `_options` for `_begin_attack`:
## `choose_attack` is a weighted pick over the WHOLE table and cannot see either, so its answer is
## only usable when it happens to be one of these.
func _ready_to_attack(dist: float) -> bool:
	_options.clear()
	if state == ATTACK or host.status.is_staggered():
		return false
	if host.target() == null:
		return false
	var damaging := false
	for a: EnemyAttack in host.attacks():
		if dist < a.range_min or dist > a.range_max:
			continue
		if float(_cooldowns.get(a.id, 0.0)) > 0.0:
			continue
		_options.append(a)
		if not a.is_utility():
			damaging = true
	if _options.is_empty():
		return false
	if not damaging:
		return true   ## only a utility move is available, and it costs no volley slot
	# A utility row never competes with a real attack: picking the spitter's chaff puff while its
	# acid arc was ready is what used to spend a volley slot on 0 damage and shut the whole ranged
	# kind for the re-grant delay, swinging the incoming-damage reading by 80 DPS (lead r12).
	# Dropped in place — this runs every tick for every monster in range, so it allocates nothing.
	for i in range(_options.size() - 1, -1, -1):
		if (_options[i] as EnemyAttack).is_utility():
			_options.remove_at(i)
	return AttackTokenPool.request(host.token_kind(), host)


func _begin_attack() -> void:
	var pick := host.choose_attack()
	current = pick if pick != null and pick in _options else EnemyStrike.choose(_options)
	if current == null:
		return
	state = ATTACK
	phase = TELEGRAPH
	_hit_done = false
	_spawned = false
	if not current.is_utility():
		_token = host.token_kind()
		if not AttackTokenPool.request(_token, host):
			# The slot went to somebody else between the check and the pick: stand down rather
			# than swing without one.
			_token = &""
			current = null
			state = POSITION
			return
	_phase_left = current.telegraph
	host.begin_telegraph(current)
	host.play_action(current.anim)
	# No snap-turn here: the telegraph ticks `attack_windup`, which turns at turn_rate, so a flanked
	# juggernaut rotates 67° over its 0.45 s windup instead of popping the full 150° in one tick
	# (audit #7). Flanking it has to stay the answer.


func _attack(dt: float) -> void:
	if current == null:
		state = APPROACH
		return
	_phase_left -= dt
	match phase:
		TELEGRAPH: _phase_telegraph(dt)
		ACTIVE: _phase_active(dt)
		_: _phase_recover(dt)


## Anticipation: the monster winds up and tracks the player, but cannot damage anything.
func _phase_telegraph(dt: float) -> void:
	host.attack_windup(current, dt)
	if _phase_left <= 0.0:
		phase = ACTIVE
		_phase_left = current.active
		host.end_telegraph()
		host.attack_started(current)


func _phase_active(dt: float) -> void:
	host.attack_active(current, dt, _hit_done)
	if not _hit_done:
		if current.projectile_speed > 0.0 or current.blast_radius > 0.0 \
				or current.shockwave_radius > 0.0:
			if not _spawned:
				_spawned = true
				_hit_done = host.spawn_attack(current)
		elif current.damage > 0.0:
			_hit_done = host.melee_sweep(current)
		else:
			_hit_done = true   ## a pure utility move (chaff cloud): nothing to land
	if _phase_left <= 0.0:
		phase = RECOVER
		_phase_left = current.recover


func _phase_recover(dt: float) -> void:
	host.attack_recover(current, dt)
	if _phase_left <= 0.0:
		_finish_attack()


func _finish_attack() -> void:
	if current != null:
		_cooldowns[current.id] = current.cooldown
	_release_token()
	current = null
	state = REPOSITION
	_state_left = REPOSITION_TIME


func _reposition(dt: float) -> void:
	if not _check_blind():
		return
	var hunt := host.perception.hunt_point()
	flank += dt * host.circle_speed
	var away := host.global_position - hunt
	away.y = 0.0
	host.face_dir(hunt - host.global_position, dt)
	host.loco.steer_to(host.global_position + away.normalized() * 20.0, 0.6, dt)
	host.set_locomotion(&"walk")
	_state_left -= dt
	if _state_left <= 0.0:
		state = APPROACH


# --- reactions ----------------------------------------------------------------------------------

func _enter_staggered() -> void:
	if state == STAGGERED:
		return
	interrupt()
	state = STAGGERED


func _staggered(dt: float) -> void:
	host.loco.decelerate(dt)
	host.set_locomotion(&"stagger")


## Stability broke mid-swing: drop the attack, the token and the telegraph at once.
func interrupt() -> void:
	if current != null:
		_cooldowns[current.id] = maxf(float(_cooldowns.get(current.id, 0.0)), 0.4)
	host.end_telegraph()
	_release_token()
	current = null
	phase = RECOVER


func stop() -> void:
	state = DEAD
	interrupt()


func restart() -> void:
	home = host.global_position
	_patrol_point = host.global_position
	_patrol_left = 0.0
	state = IDLE
	phase = RECOVER
	current = null
	_phase_left = 0.0
	_state_left = 0.0
	_hit_done = false
	_spawned = false
	_cooldowns.clear()
	_options.clear()
	flank = randf() * TAU
	_search.reset()


func _release_token() -> void:
	if _token != &"":
		AttackTokenPool.release(_token, host)
		_token = &""


func _tick_cooldowns(dt: float) -> void:
	for id: StringName in _cooldowns.keys():
		var left := float(_cooldowns[id]) - dt
		if left <= 0.0:
			_cooldowns.erase(id)
		else:
			_cooldowns[id] = left


## Keep pack members from stacking: a cheap separation bias fed into the steering.
func _separation(dt: float) -> void:
	_sep_left -= dt
	if _sep_left > 0.0 or not host.is_inside_tree():
		return
	_sep_left = SEPARATION_INTERVAL
	var radius := EnemyTypes.get_stat(host.enemy_type, "radius", 3.0) * SEPARATION_RADIUS
	var push := Vector3.ZERO
	for n: Node in host.get_tree().get_nodes_in_group(&"enemy"):
		var other := n as Node3D
		if other == null or other == host:
			continue
		var to := host.global_position - other.global_position
		to.y = 0.0
		var d := to.length()
		if d > radius * 2.0:
			continue
		push += (to.normalized() if d > 0.01 else Vector3.RIGHT) * (1.0 - d / (radius * 2.0))
	host.loco.avoid_bias = push
