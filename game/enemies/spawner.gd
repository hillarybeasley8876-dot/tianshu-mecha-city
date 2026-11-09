class_name EnemySpawner
extends Node3D
## Spawns and recycles monsters (enemies-owned; CONTRACTS §6).
## API: `spawn(type, at) -> EnemyBase`, `alive_count() -> int`.
## Launch flags: `--no-enemies` suppresses the `--enemies=type:n,...` ring; `--enemies=ripper:8,...`
## places that mix around the player at 150–250 m on the navmesh once the world is built.
## Rippers are pooled (they die constantly); everything else is instanced per spawn.

const SCENE := "res://enemies/%s/%s.tscn"
const SPAWN_MIN := 150.0     ## metres from the player
const SPAWN_MAX := 250.0
const SPAWN_TRIES := 12
const LEASH_INTERVAL := 2.0  ## how often lost monsters are checked
const LEASH_AFTER := 8.0     ## unreachable for this long → put it back in the fight
## A monster that has lost the player and is farther than this (or twice its engage ring, whichever
## is nearer) is not going to find them by accident. It is a fixed distance rather than a multiple of
## `engage_range` because that is a stand-off band for the artillery — see `_leash`.
const LEASH_BLIND_MAX := 120.0
const GROUND_SNAP_MAX := 60.0  ## a mesh point this far from the query point is not "under" it
const CENTRE_SNAP_MAX := 150.0 ## the player may stand off this class's mesh (a deck, a plaza)
const LEVEL_TOLERANCE := 12.0  ## a spawn point this far above/below the player is another island

@export var auto_spawn: bool = true   ## honour --enemies / --no-enemies at world-ready
@export var leash: bool = true        ## relocate monsters stranded on unreachable geometry

var _pool: Dictionary = {}     ## StringName -> Array[EnemyBase]
var _live: Array[EnemyBase] = []
var _lost_for: Dictionary = {} ## EnemyBase -> seconds it has been unable to path to the player
var _leash_left: float = LEASH_INTERVAL
var _ready_done: bool = false


func _ready() -> void:
	if not auto_spawn:
		return
	if Game.world_built():
		_spawn_from_flags.call_deferred()
	else:
		Events.world_ready.connect(_spawn_from_flags, CONNECT_ONE_SHOT)


func _physics_process(delta: float) -> void:
	AttackTokenPool.tick(delta)
	if not leash:
		return
	_leash_left -= delta
	if _leash_left > 0.0:
		return
	_leash_left = LEASH_INTERVAL
	_leash(LEASH_INTERVAL)


## A monster that is out of the fight is put back into it. There are two ways to be out of it, and
## the second one is the lead's r12 finding: it cannot path to the player at all (a disconnected
## navmesh island, a pit it fell into), OR it has fought the player, lost sight of them and is now
## hunting a remembered point on the far side of the map — which is how a monster used to spend the
## rest of the run silent behind a wall while an objective waited for an arena to be cleared. After
## LEASH_AFTER seconds it is moved to reachable ground at SPAWN_MIN..SPAWN_MAX metres, preferring a
## ring point it can actually see the player from and turned to face them, because a monster
## teleported in facing the wrong way just goes blind again.
func _leash(step: float) -> void:
	var player := _player_position()
	var ground_cache: Dictionary = {}
	for e: EnemyBase in live_enemies():
		if not e.alive:
			continue
		var agent := e.loco.agent
		# Everything is measured against the GROUND under the player: the mech's origin is 7.5 m up
		# and it can hover, and a 3D near test against that stranded every ground monster whenever
		# the player left the deck (audit #5).
		if not ground_cache.has(e.enemy_type):
			ground_cache[e.enemy_type] = _grounded(player, e.enemy_type)
		var ground: Vector3 = ground_cache[e.enemy_type]
		var flat := Vector3(e.global_position.x - ground.x, 0.0, e.global_position.z - ground.z)
		# is_target_reachable() only means something once the agent has a goal; without one it
		# answers about the default (0, 0, 0) target and calls a stranded monster reachable.
		var stranded := agent != null and flat.length() > e.engage_range * 2.0 \
				and not (e.loco.has_goal() and agent.is_target_reachable())
		# Blind is its own distance test. `engage_range` is a stand-off BAND for the artillery — the
		# spitter's is 300 m — so "twice the engage ring" would mean a spitter is never far from
		# anything, which is exactly how one sat silent in the sandbox trench for a whole run
		# (lead r12, Request 21). Only a monster that has ALREADY fought the player counts: one that
		# has never seen them is patrolling, and teleporting the whole map into the player's face
		# would be worse than the bug.
		var blind := e.perception.is_alerted() and e.target() == null \
				and flat.length() > minf(e.engage_range * 2.0, LEASH_BLIND_MAX)
		if not (stranded or blind):
			_lost_for.erase(e)
			continue
		var lost := float(_lost_for.get(e, 0.0)) + step
		_lost_for[e] = lost
		if lost < LEASH_AFTER:
			continue
		_lost_for.erase(e)
		e.global_position = _grounded(
				_reachable_ring_point(ground, float(hash(e)) / 4294967296.0, e.enemy_type,
						player if blind else Vector3.INF),
				e.enemy_type)
		e.velocity = Vector3.ZERO
		e.loco.reset_path()
		if blind:
			_face(e, player)


## Instances (or recycles) a monster of `type` at `at`. Returns null on an unknown type.
func spawn(type: StringName, at: Transform3D) -> EnemyBase:
	if not EnemyTypes.is_type(type):
		push_error("EnemySpawner: unknown enemy type '%s'" % type)
		return null
	var enemy := _take(type)
	if enemy == null:
		return null
	var xf := Transform3D(at.basis.orthonormalized(), _grounded(at.origin, type))
	if enemy.get_parent() == null:
		# Placed BEFORE it enters the tree. `EnemyBase._ready` turns the body's collision on and
		# builds the model, and it runs inside `add_child` — adding first and moving second meant a
		# new monster was a solid body standing on the spawner's own origin for one tick, so
		# anything resting there (the hero at world (0,0,0), the titan on its AddSpawner) took that
		# body as its floor and then inherited the jump to the spawn point as platform velocity: the
		# hero was thrown at ~16 km/s and the titan 68-134 m in a tick (lead r11 item 1). Setting
		# the LOCAL transform first is right whatever the spawner's own transform is — translated,
		# rotated, or moving with a parent — because `add_child` then resolves the global one.
		enemy.transform = global_transform.affine_inverse() * xf
		add_child(enemy)
	else:
		enemy.global_transform = xf   ## a pooled ripper: place it before `recycle` re-arms it
	enemy.recycle()
	enemy.visible = true
	if enemy not in _live:
		_live.append(enemy)
	return enemy


func alive_count() -> int:
	_prune()
	return _live.size()


func live_enemies() -> Array[EnemyBase]:
	_prune()
	return _live.duplicate()


func clear() -> void:
	for e: EnemyBase in _live:
		if is_instance_valid(e):
			e.queue_free()
	_live.clear()


func _take(type: StringName) -> EnemyBase:
	if type == EnemyTypes.RIPPER:
		var free_list: Array = _pool.get(type, [])
		while not free_list.is_empty():
			var reused: EnemyBase = free_list.pop_back()
			# A live entry means the pool was handed a monster that is still fighting; popping it
			# would teleport a fighting ripper into the new ring (audit #2/#3).
			if is_instance_valid(reused) and not reused.alive:
				return reused
		_pool[type] = free_list
	var packed := load(SCENE % [type, type]) as PackedScene
	if packed == null:
		push_error("EnemySpawner: cannot load scene for '%s'" % type)
		return null
	var enemy := packed.instantiate() as EnemyBase
	if enemy == null:
		push_error("EnemySpawner: scene root of '%s' is not an EnemyBase" % type)
		return null
	enemy.dissolved.connect(_on_dissolved.bind(type))
	return enemy


## Rippers are returned to the pool after their wreck has finished dissolving: `reclaim()` stops
## EnemyBase from freeing the node, so the next spawn reuses it instead of churning the scene.
func _on_dissolved(enemy: EnemyBase, type: StringName) -> void:
	_live.erase(enemy)
	if type != EnemyTypes.RIPPER:
		return
	enemy.reclaim()
	enemy.visible = false
	var free_list: Array = _pool.get(type, [])
	if enemy not in free_list:
		free_list.append(enemy)
	_pool[type] = free_list


func _prune() -> void:
	for i in range(_live.size() - 1, -1, -1):
		var e := _live[i]
		if not is_instance_valid(e) or not e.alive:
			_live.remove_at(i)


## Public placement helper: a navmesh point around `centre`, on the same level as `centre`. `t`
## (0..1) picks the bearing, so callers can spread a group evenly around the player. `type` selects
## the agent-class navmesh (CONTRACTS §7); leave it empty for the world's default map.
func place_around(centre: Vector3, t: float, type: StringName = &"") -> Vector3:
	return _reachable_ring_point(centre, fposmod(t, 1.0), type)


## The map this archetype spawns on: its agent-class map when the world has one, the default map
## otherwise (sandboxes, stubbed worlds).
func _map_for(type: StringName) -> RID:
	if type == &"":
		return get_world_3d().navigation_map
	return EnemyTypes.nav_map_for(self, type)


## Drops a monster onto the ground (navmesh first, physics ray as the fallback).
func _grounded(at: Vector3, type: StringName = &"") -> Vector3:
	var map := _map_for(type)
	if EnemyTypes.nav_query_ready(self, type) and EnemyTypes.map_ready(map):
		var snapped := NavigationServer3D.map_get_closest_point(map, at)
		if snapped.distance_to(at) < GROUND_SNAP_MAX:
			return snapped
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 200.0, at + Vector3.DOWN * 400.0,
			Layers.MASK_SIGHT)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return hit["position"] as Vector3
	return at


## A navmesh point 150–250 m from `centre` on the player's own deck. Tries a ring of bearings so a
## monster never starts the fight stranded in a pit (the sandbox trench) or on a floor the player
## is not on. `look` is the point the caller wants the monster to be able to SEE from where it
## lands (Vector3.INF = do not care): a blind monster put back on a bearing with a wall in the way
## is blind again a second later, so the ring search prefers a clear line and only falls back to the
## first reachable bearing when every one of them is blocked.
##
## Reachability is deliberately NOT proved with a path query: Godot 4.7.2 prints an engine error for
## every query between disconnected navmesh islands ("It's not expect to not find the most reachable
## polygons") and returns a degenerate start→end pair instead of an empty path, and a vertical city
## is nothing but islands — 46 of them in one scripted fight (lead note 02:40). On-mesh plus
## same-level is the cheap test that catches the case that actually mattered.
func _reachable_ring_point(centre: Vector3, seed_t: float, type: StringName = &"",
		look: Vector3 = Vector3.INF) -> Vector3:
	var angle := TAU * seed_t
	var fallback := centre + Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_MIN
	var map := _map_for(type)
	if not EnemyTypes.nav_query_ready(self, type) or not EnemyTypes.map_ready(map):
		return fallback
	var goal := NavigationServer3D.map_get_closest_point(map, centre)
	if goal.distance_to(centre) > CENTRE_SNAP_MAX:
		return fallback
	var first := Vector3.INF
	for i in SPAWN_TRIES:
		angle = TAU * (seed_t + float(i) / float(SPAWN_TRIES))
		var dist := lerpf(SPAWN_MIN, SPAWN_MAX, fposmod(seed_t + float(i) * 0.37, 1.0))
		var probe := centre + Vector3(cos(angle), 0.0, sin(angle)) * dist
		var snapped := NavigationServer3D.map_get_closest_point(map, probe)
		if snapped.distance_to(probe) > GROUND_SNAP_MAX:
			continue
		if absf(snapped.y - goal.y) > LEVEL_TOLERANCE:
			continue
		if first == Vector3.INF:
			first = snapped
		if look == Vector3.INF or _sees(snapped, look):
			return snapped
	return first if first != Vector3.INF else fallback


## Clear line of sight between two world points at chest height — the same ray Perception uses.
func _sees(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 2.0, to + Vector3.UP * 2.0,
			Layers.MASK_SIGHT)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Turns a monster to face `at` (the convention EnemyBase.face_dir uses). A monster moved into the
## fight facing away from it never re-acquires: perception's sight cone is 70–90° half-angle.
static func _face(e: Node3D, at: Vector3) -> void:
	var dir := at - e.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	e.rotation.y = atan2(-dir.x, -dir.z)


## A transform at `at` facing `look`, safe when the two coincide (Basis.looking_at rejects a zero
## target vector, which happens when a spawn lands exactly on the player).
static func face_towards(at: Vector3, look: Vector3) -> Transform3D:
	var dir := look - at
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Transform3D(Basis.IDENTITY, at)
	return Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), at)


# --- launch flags -------------------------------------------------------------------------------

## `--no-enemies` wins over `--enemies=type:n,...`; a bare `--enemies` spawns one of each type.
func _spawn_from_flags() -> void:
	if _ready_done or Game.has_flag("no-enemies") or Game.stubbed("enemies"):
		return
	_ready_done = true
	var spec := Game.flag("enemies")
	var centre := _player_position()
	if spec == "":
		return
	if spec == "true":
		for t: StringName in EnemyTypes.ALL:
			spawn(t, face_towards(place_around(centre, randf(), t), centre))
		return
	for entry: String in spec.split(",", false):
		var parts := entry.split(":")
		var type := StringName(parts[0].strip_edges())
		var count := int(parts[1]) if parts.size() > 1 else 1
		for i in count:
			var at := place_around(centre, float(i) / maxf(float(count), 1.0), type)
			spawn(type, face_towards(at, centre))


func _player_position() -> Vector3:
	if Game.player != null and is_instance_valid(Game.player):
		return Game.player.global_position
	if Game.world != null:
		var marker := Game.world.get_node_or_null(^"PlayerSpawn") as Node3D
		if marker != null:
			return marker.global_position
	return global_position
