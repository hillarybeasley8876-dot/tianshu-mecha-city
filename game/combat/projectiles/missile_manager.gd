class_name MissileManager
extends Node3D
## Hailstorm missiles (projectiles unit): every missile lives in flat arrays and is simulated in one
## loop; the Itano-circus rendering (hulls, engine flares, tapered core ribbons, lingering smoke)
## lives in MissileVisuals, four MultiMeshes for the whole swarm.
##
## Clock: plain `delta`, the world clock (CONTRACTS §3) — the launcher paints and ripples on the
## player's clock, but a missile in the air belongs to the world and crawls with it in witch time.

const CAPACITY := MissileVisuals.CAPACITY
const CHAFF_REFRESH := 0.5

var tuning: MissileTuning = null
var query: ShotQuery = null
var sparks: SparkPool = null
var visuals: MissileVisuals = null

var guided: bool = false          ## aim held after release: the swarm follows the crosshair
var guided_point: Vector3 = Vector3.ZERO
var launched: int = 0
var impacts: int = 0
var absorbed: int = 0

var _active: PackedByteArray = PackedByteArray()
var _pos: PackedVector3Array = PackedVector3Array()
var _dir: PackedVector3Array = PackedVector3Array()
var _bloom: PackedVector3Array = PackedVector3Array()
var _age: PackedFloat64Array = PackedFloat64Array()
var _targets: Array[Node3D] = []
var _fallback: PackedVector3Array = PackedVector3Array()
var _chaff: Array[Node3D] = []
var _chaff_used: Dictionary = {}
var _chaff_timer: float = 0.0
var _salvo_hit_done: bool = false


func _ready() -> void:
	# World-space pool: every instance transform below is a world position, so the node must not
	# inherit the mech's transform. `weapon_system.tscn` sets top_level; a bare script instance
	# (tests, tools) may not, and then every visual is drawn at player_xf * world_pos.
	if not top_level:
		top_level = true
		global_transform = Transform3D.IDENTITY
	if tuning == null:
		tuning = MissileTuning.new()
	_active.resize(CAPACITY)
	_pos.resize(CAPACITY)
	_dir.resize(CAPACITY)
	_bloom.resize(CAPACITY)
	_age.resize(CAPACITY)
	_fallback.resize(CAPACITY)
	for i in CAPACITY:
		_targets.append(null)
	visuals = MissileVisuals.new()
	visuals.name = "Visuals"
	add_child(visuals)
	set_physics_process(true)


func active_count() -> int:
	var n := 0
	for i in CAPACITY:
		n += _active[i]
	return n


## Put one missile in the air. `target` may be null, in which case it flies to `point`.
func launch(from: Vector3, dir: Vector3, target: Node3D, point: Vector3) -> bool:
	var i := _free_slot()
	if i < 0:
		push_warning("MissileManager: pool full (%d), missile dropped" % CAPACITY)
		return false
	_active[i] = 1
	_pos[i] = from
	_dir[i] = dir.normalized()
	_bloom[i] = _bloom_dir(dir)
	_age[i] = 0.0
	_targets[i] = target
	_fallback[i] = point
	visuals.launch(i, from)
	launched += 1
	return true


## Called when a new salvo leaves the rails: resets the per-salvo feel budget and chaff tally.
func begin_salvo() -> void:
	_salvo_hit_done = false
	_chaff_used.clear()


func _bloom_dir(dir: Vector3) -> Vector3:
	var d := dir.normalized()
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var spread := deg_to_rad(tuning.bloom_cone_deg)
	var yaw := randf_range(-spread, spread)
	var pitch := randf_range(-spread, spread) * 0.6
	return (d.rotated(up, yaw).rotated(up.cross(d).normalized(), pitch)).normalized()


func _free_slot() -> int:
	for i in CAPACITY:
		if _active[i] == 0:
			return i
	return -1


## Drop every missile in flight (respawn, tests). Pooled visuals are parked, nothing is freed.
func clear() -> void:
	for i in CAPACITY:
		_active[i] = 0
		_targets[i] = null
	visuals.clear()


func _physics_process(delta: float) -> void:
	if query == null or visuals == null:
		return
	visuals.begin(delta)
	_chaff_timer -= delta
	if _chaff_timer <= 0.0:
		_refresh_chaff()
	var live := 0
	for i in CAPACITY:
		if _active[i] == 0:
			continue
		if not _advance(i, delta):
			_retire(i)
			continue
		live += 1
		visuals.sample(i, _pos[i])
		visuals.body(i, _pos[i], _dir[i])
	visuals.flush(live)


func _advance(i: int, delta: float) -> bool:
	_age[i] += delta
	if _age[i] > tuning.life:
		return false
	var speed: float
	if _age[i] < tuning.bloom_time:
		_dir[i] = _bloom[i]
		speed = tuning.bloom_speed
	else:
		speed = lerpf(tuning.speed_start, tuning.speed_max,
				clampf((_age[i] - tuning.bloom_time) / maxf(tuning.ignite_time, 0.001), 0.0, 1.0))
		_steer(i, delta)
	var step := _dir[i] * speed * delta
	var length := step.length()
	var hits := query.ray_hits(_pos[i], _dir[i], length, Layers.MASK_PLAYER_ATTACK, 1)
	if not hits.is_empty():
		_detonate(i, hits[0]["position"], hits[0]["normal"], hits[0]["collider"])
		return false
	_pos[i] += step
	if _chaff_block(i):
		return false
	var goal := _goal(i)
	if _pos[i].distance_to(goal) <= tuning.fuse_radius and _age[i] >= tuning.bloom_time:
		_detonate(i, goal, -_dir[i], null)
		return false
	return true


func _steer(i: int, delta: float) -> void:
	var to_goal := _goal(i) - _pos[i]
	if to_goal.length_squared() < 0.01:
		return
	var desired := to_goal.normalized()
	var t := _age[i] - tuning.bloom_time
	var turn := deg_to_rad(tuning.turn_start_deg if t < tuning.turn_ramp_time else tuning.turn_max_deg)
	var angle := _dir[i].angle_to(desired)
	if angle < 0.0001:
		return
	_dir[i] = desired if angle <= turn * delta else _dir[i].slerp(desired, turn * delta / angle)


func _goal(i: int) -> Vector3:
	if guided:
		return guided_point
	var tgt := _targets[i]
	if tgt != null and is_instance_valid(tgt) and tgt.is_inside_tree():
		return tgt.global_position
	return _fallback[i]


func _detonate(i: int, at: Vector3, normal: Vector3, collider: Object) -> void:
	var hit := HitInfo.make(tuning.damage, HitInfo.EXPLOSIVE, query.source, &"hailstorm")
	hit.stagger = tuning.impact
	hit.knockback = _dir[i] * 6.0
	var actor: Node = null
	if collider != null:
		actor = query.deliver(hit, collider, at, normal, tuning.blast_radius)
	var others: Array[Node] = []
	if actor != null:
		others.append(actor)
	query.blast(at, tuning.blast_radius, tuning.damage, tuning.impact, HitInfo.EXPLOSIVE,
			&"hailstorm", others)
	impacts += 1
	if sparks != null:
		sparks.blast(at, normal, tuning.blast_radius)
	Feel.play(&"missile_hit", at)
	if not _salvo_hit_done:
		_salvo_hit_done = true
		if query.source != null and query.source.has_method(&"hit_pause"):
			Feel.local_hit_stop([query.source], 0.05)


## Spore chaff: a cloud eats up to `chaff_absorb` missiles. Returns true when this missile was eaten.
func _chaff_block(i: int) -> bool:
	for cloud in _chaff:
		if not is_instance_valid(cloud):
			continue
		var radius := tuning.chaff_radius
		var declared: Variant = cloud.get(&"radius")
		if declared != null:
			radius = float(declared)
		if _pos[i].distance_to((cloud as Node3D).global_position) > radius:
			continue
		var id := cloud.get_instance_id()
		var used := int(_chaff_used.get(id, 0))
		if used >= tuning.chaff_absorb:
			continue
		_chaff_used[id] = used + 1
		absorbed += 1
		if sparks != null:
			sparks.impact(_pos[i], Vector3.UP, Color(0.65, 0.45, 0.9), 3.0, 0.25, 1.0)
		return true
	return false


func _refresh_chaff() -> void:
	_chaff_timer = CHAFF_REFRESH
	_chaff.clear()
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group(tuning.chaff_group):
		if n is Node3D:
			_chaff.append(n as Node3D)


## The missile is done: the visuals keep its smoke trail alive while it ages out.
func _retire(i: int) -> void:
	_active[i] = 0
	_targets[i] = null
	visuals.retire(i)
