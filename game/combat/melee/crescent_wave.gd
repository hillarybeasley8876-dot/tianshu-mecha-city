class_name CrescentWave
extends Node3D
## The charged slash's crescent (skills-catalog §4.3 "MOONLIGHT-style wave", ×2 for our 16 m hero):
## a 90 m crescent 24 m wide flying at 140 m/s, 600 damage + 300 impact to everything it crosses.
## It is a COLLAPSE detonator (CONTRACTS §4): everything it touches goes off.
##
## The body is a curved sheet (`CrescentMesh`), not a slab: it bows forward, tapers to points, leans
## its crest back and scours the ground with sparks and dust where it passes (review r1 MUST-FIX 2).
## Only one is alive at a time per melee system; the owner calls `launch()` and the wave frees itself.

const HIT_INTERVAL := 0.04    ## s between sweep queries, so a fast wave cannot tunnel
const COLLAPSE_RADIUS := 20.0 ## skills-catalog §4.4 COLLAPSE 10 m, ×2 for our 16 m hero
const FADE_IN := 0.06         ## s the sheet takes to reach full brightness after the swing
const FADE_OUT := 24.0        ## metres over which it thins out at the end of its run

var source: Node = null

var _dir: Vector3 = Vector3.FORWARD
var _travelled: float = 0.0
var _since_query: float = 0.0
var _since_scour: float = 0.0
var _age: float = 0.0
var _hit_ids: Dictionary = {}
var _mesh: MeshInstance3D = null
var _mat: StandardMaterial3D = null

signal hit_actor(actor: Node, hit: HitInfo)


func _ready() -> void:
	top_level = true
	_build()


func _build() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Crescent"
	_mesh.mesh = CrescentMesh.build(MeleeTable.WAVE_WIDTH, MeleeTable.WAVE_THICKNESS,
			MeleeTable.WAVE_HEIGHT, randf() * TAU)
	_mat = CombatMesh.hdr(Color.WHITE, 1.0, 0.0)
	_mat.vertex_color_use_as_albedo = true
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


## Sends the wave from `at` along `dir` (world, normalised).
func launch(at: Vector3, dir: Vector3, src: Node) -> void:
	global_position = at
	source = src
	_dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	_travelled = 0.0
	_since_query = HIT_INTERVAL
	_since_scour = MeleeTable.WAVE_SCOUR_STEP
	_age = 0.0
	_hit_ids.clear()
	look_at_safe()
	CombatVfx.spawn(source, &"spark_burst", at, _dir, 1.6)
	CombatVfx.flash(source, at, Color(0.75, 0.97, 1.0), 4.0, 30.0)


func look_at_safe() -> void:
	var up := Vector3.UP if absf(_dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	global_basis = Basis.looking_at(_dir, up)


func _physics_process(delta: float) -> void:
	_age += delta
	var step := MeleeTable.WAVE_SPEED * delta
	global_position += _dir * step
	_travelled += step
	_since_query += delta
	_since_scour += step
	_fade()
	if _since_scour >= MeleeTable.WAVE_SCOUR_STEP:
		_since_scour = 0.0
		_scour()
	if _since_query >= HIT_INTERVAL:
		_since_query = 0.0
		_sweep()
	if _travelled >= MeleeTable.WAVE_LENGTH:
		queue_free()


## The sheet snaps on over FADE_IN and thins out over the last FADE_OUT metres of its run.
func _fade() -> void:
	var in_k := clampf(_age / FADE_IN, 0.0, 1.0)
	var left := MeleeTable.WAVE_LENGTH - _travelled
	var out_k := clampf(left / FADE_OUT, 0.0, 1.0)
	_mat.albedo_color = Color(1.0, 1.0, 1.0, in_k * out_k)


## Ground scouring: sparks, dust and a few chunks thrown up along the leading edge, so the wave
## reads as cutting the street rather than floating over it. The dust is deliberately small — at
## mech scale a `dust_puff` at scale 3 is a 16 m quad, and a dozen of those white out the frame.
func _scour() -> void:
	var at := global_position + Vector3.DOWN * (global_position.y - _ground_y())
	CombatVfx.spawn(source, &"spark_bullet", at, Vector3.UP, 1.2)
	CombatVfx.spawn(source, &"dust_puff", at, Vector3.UP, 1.1)
	CombatVfx.debris(source, at, 4, 14.0, 0.9)


## Height of the ground under the wave, from a short ray down; the launch height when there is no
## world to hit (a test with no colliders).
func _ground_y() -> float:
	var space := _space()
	if space == null:
		return 0.0
	var params := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP,
			global_position + Vector3.DOWN * 200.0)
	params.collision_mask = Layers.WORLD
	params.collide_with_areas = false
	var hit := space.intersect_ray(params)
	return float((hit["position"] as Vector3).y) if hit.has("position") else 0.0


## The whole crescent edge at once: a box the width and height of the wave, swept a short way forward.
func _sweep() -> void:
	var space := _space()
	if space == null:
		return
	var params := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(MeleeTable.WAVE_WIDTH, MeleeTable.WAVE_HEIGHT,
			MeleeTable.WAVE_SPEED * HIT_INTERVAL * 2.0)
	params.shape = box
	params.transform = Transform3D(global_basis, global_position + Vector3.UP * MeleeTable.WAVE_HEIGHT * 0.3)
	params.collision_mask = Layers.MASK_PLAYER_ATTACK
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.exclude = _exclusions()
	for r: Dictionary in space.intersect_shape(params, 24):
		_damage(r["collider"] as Object)


func _space() -> PhysicsDirectSpaceState3D:
	var w := get_world_3d()
	return w.direct_space_state if is_inside_tree() and w != null else null


func _exclusions() -> Array[RID]:
	var out: Array[RID] = []
	if source is CollisionObject3D:
		out.append((source as CollisionObject3D).get_rid())
		for n in source.find_children("*", "CollisionObject3D", true, false):
			out.append((n as CollisionObject3D).get_rid())
	return out


func _damage(col: Object) -> void:
	if col == null:
		return
	var actor: Node = null
	if col is Hurtbox:
		actor = (col as Hurtbox).actor()
	elif col is Node and (col as Node).has_method(&"take_hit"):
		actor = col as Node
	if actor == null or actor == source or _hit_ids.has(actor.get_instance_id()):
		return
	if actor.has_method(&"is_alive") and not bool(actor.call(&"is_alive")):
		return
	_hit_ids[actor.get_instance_id()] = true
	var at := _actor_point(actor)
	var hit := HitInfo.make(MeleeTable.WAVE_DAMAGE, HitInfo.MELEE, source, &"crescent_wave")
	hit.stagger = MeleeTable.WAVE_IMPACT
	hit.position = at
	hit.normal = _dir
	hit.knockback = _dir * 8.0
	if col is Hurtbox:
		if (col as Hurtbox).apply(hit) == null:
			return
	else:
		actor.call(&"take_hit", hit)
	Events.hit_landed.emit(hit, actor)
	hit_actor.emit(actor, hit)
	CombatVfx.spawn(source, &"spark_beam", at, _dir, 1.4)
	CombatVfx.flash(source, at, Color(0.75, 0.97, 1.0), 3.0, 24.0)
	## COLLAPSE: the charged wave is one of the five detonators (CONTRACTS §4).
	get_tree().call_group(&"prime_detonators", &"detonate_primes", at, COLLAPSE_RADIUS, source)


func _actor_point(actor: Node) -> Vector3:
	return (actor as Node3D).global_position if actor is Node3D else global_position
