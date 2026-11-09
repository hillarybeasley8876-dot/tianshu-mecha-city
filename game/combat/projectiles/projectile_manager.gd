class_name ProjectileManager
extends Node3D
## Pooled ballistic rounds for the gatling (projectiles unit). Bullets live in flat arrays, are
## ray-stepped every physics tick (900 m/s never tunnels through a 6 m Ripper) and are drawn by one
## MultiMesh: slot i is instance i, so only the tracer rounds write transforms.
##
## Clock: plain `delta`, the world clock (CONTRACTS §3) — rounds in flight slow down in witch time
## with everything else they are flying past. Only the gun's own timers are player-side.

const CAPACITY := 600            ## CONTRACTS §2 projectile budget
const TRACER_LENGTH := 42.0   ## ~2 frames of travel at 900 m/s, so the stream reads as a stream
const TRACER_WIDTH := 0.35
const TRACER_COLOR := Color(1.0, 0.78, 0.34)

var tuning: GatlingTuning = null
var query: ShotQuery = null
var sparks: SparkPool = null

var shots_fired: int = 0
var tracers: int = 0
var hits_landed: int = 0

var _active: PackedByteArray = PackedByteArray()
var _tracer: PackedByteArray = PackedByteArray()
var _pos: PackedVector3Array = PackedVector3Array()
var _vel: PackedVector3Array = PackedVector3Array()
var _dmg: PackedFloat64Array = PackedFloat64Array()
var _imp: PackedFloat64Array = PackedFloat64Array()
var _travelled: PackedFloat64Array = PackedFloat64Array()
var _age: PackedFloat64Array = PackedFloat64Array()
var _mmi: MultiMeshInstance3D
var _parked := Transform3D(Basis.IDENTITY, Vector3(0.0, -100000.0, 0.0))
## Near-lens recording (lead r6): the headless dummy renderer keeps no MultiMesh instance transforms,
## so the first-person scan reads what this pool writes instead of reading the buffer back. Off in the
## game and in the perf suite.
var recording: bool = false
var _recorded: Array[Dictionary] = []


func _ready() -> void:
	# World-space pool: every instance transform below is a world position, so the node must not
	# inherit the mech's transform. `weapon_system.tscn` sets top_level; a bare script instance
	# (tests, tools) may not, and then every visual is drawn at player_xf * world_pos.
	if not top_level:
		top_level = true
		global_transform = Transform3D.IDENTITY
	if tuning == null:
		tuning = GatlingTuning.new()
	_active.resize(CAPACITY)
	_tracer.resize(CAPACITY)
	_pos.resize(CAPACITY)
	_vel.resize(CAPACITY)
	_dmg.resize(CAPACITY)
	_imp.resize(CAPACITY)
	_travelled.resize(CAPACITY)
	_age.resize(CAPACITY)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 1.0, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = CAPACITY
	mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Tracers"
	_mmi.multimesh = mm
	_mmi.material_override = BeamPool.additive_material(TRACER_COLOR, 5.0)
	(_mmi.material_override as StandardMaterial3D).vertex_color_use_as_albedo = true
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	for i in CAPACITY:
		mm.set_instance_transform(i, _parked)  # unused slots must not draw at the origin
	set_physics_process(true)


func active_count() -> int:
	var n := 0
	for i in CAPACITY:
		n += _active[i]
	return n


## Launch one round. Returns false when the pool is full (never allocates past the budget).
func fire(from: Vector3, dir: Vector3, damage: float, impact: float, speed: float, life: float,
		tracer: bool) -> bool:
	var i := _free_slot()
	if i < 0:
		push_warning("ProjectileManager: pool full (%d), round dropped" % CAPACITY)
		return false
	_active[i] = 1
	_tracer[i] = 1 if tracer else 0
	_pos[i] = from
	_vel[i] = dir.normalized() * speed
	_dmg[i] = damage
	_imp[i] = impact
	_travelled[i] = 0.0
	_age[i] = life
	shots_fired += 1
	tracers += 1 if tracer else 0
	return true


func _free_slot() -> int:
	for i in CAPACITY:
		if _active[i] == 0:
			return i
	return -1


## Drop every round in flight (respawn, tests). Pooled visuals are parked, nothing is freed.
func clear() -> void:
	var mm := _mmi.multimesh
	for i in CAPACITY:
		if _active[i] != 0:
			_active[i] = 0
			mm.set_instance_transform(i, _parked)
	mm.visible_instance_count = 0


func _physics_process(delta: float) -> void:
	if query == null:
		return
	var mm := _mmi.multimesh
	var visible := 0
	for i in CAPACITY:
		if _active[i] == 0:
			continue
		var alive := _step(i, delta)
		if not alive:
			_active[i] = 0
			if _tracer[i] == 1:
				mm.set_instance_transform(i, _parked)
			continue
		if _tracer[i] == 1:
			visible += 1
			var dir := _vel[i].normalized()
			var xf := Transform3D(ShotQuery.aligned_basis(dir),
					_pos[i] + dir * TRACER_LENGTH * 0.5).scaled_local(
					Vector3(TRACER_WIDTH, TRACER_WIDTH, TRACER_LENGTH))
			mm.set_instance_transform(i, xf)
			mm.set_instance_color(i, Color(1.0, 0.92, 0.6, 1.0))
			_note(xf, Vector3.ONE, Color(1.0, 0.92, 0.6, 1.0), _mmi.material_override)
	mm.visible_instance_count = CAPACITY if visible > 0 else 0


## Start a recording window (the near-lens scan calls this before it awaits a physics frame).
func begin_record() -> void:
	_recorded.clear()


## Every instance drawn since the last `begin_record()`, exactly as it went into the MultiMesh.
func drawn() -> Array[Dictionary]:
	return _recorded


func _note(xf: Transform3D, size: Vector3, tint: Color, mat: Material) -> void:
	if recording:
		_recorded.append({"xf": xf, "size": size, "tint": tint, "mat": mat, "kind": "box", "label": "Tracers"})



## Advance one bullet. Returns false when it is done (hit, out of range or expired).
func _step(i: int, delta: float) -> bool:
	_age[i] -= delta
	if _age[i] <= 0.0:
		return false
	var step := _vel[i] * delta
	var length := step.length()
	var dir := step / maxf(length, 0.0001)
	var hits := query.ray_hits(_pos[i], dir, length, Layers.MASK_PLAYER_ATTACK, 1)
	if not hits.is_empty():
		_impact(i, hits[0])
		return false
	_pos[i] += step
	_travelled[i] += length
	return _travelled[i] < tuning.max_range


func _impact(i: int, hit_info: Dictionary) -> void:
	var point: Vector3 = hit_info["position"]
	var normal: Vector3 = hit_info["normal"]
	var distance: float = _pos[i].distance_to(point) + _travelled[i]
	var falloff := tuning.damage_at(distance)
	var hit := HitInfo.make(_dmg[i] * falloff, HitInfo.BALLISTIC, query.source, &"gatling")
	hit.stagger = _imp[i] * falloff
	var receiver := query.deliver(hit, hit_info["collider"], point, normal)
	hits_landed += 1 if receiver != null else 0
	if sparks != null:
		sparks.spark_bullet(point, normal, 1.2)
	if receiver != null:
		Feel.play(&"gatling_hit", point)
