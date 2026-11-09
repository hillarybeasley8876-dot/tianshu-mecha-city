class_name ShotQuery
extends RefCounted
## Shared shot plumbing for the weapons unit: pierce rays, HitInfo delivery, spherical blasts and the
## downstream calls every hit makes (Events, marks, primes, Feel). One instance per weapon/manager,
## carrying the attacking actor so hits report the right `source`.
##
## Space-state note: `direct_space_state` is only valid inside physics, and every caller runs in
## `_physics_process`, so it is fetched per query rather than cached across frames.

var source: Node = null                ## attacking actor (the PlayerMech root)
var exclude: Array[RID] = []           ## bodies/areas the shots ignore (the shooter itself)

## Hit marker for the HUD (CONTRACTS §4): when the last hit landed and what kind it was.
var last_hit_usec: int = 0
var last_hit_kind: StringName = &""


func _init(source_: Node = null) -> void:
	source = source_


## Basis whose -Z faces `dir`, safe when the shot runs straight up or down.
static func aligned_basis(dir: Vector3) -> Basis:
	var d := dir
	if d.length_squared() < 0.0001:
		return Basis.IDENTITY
	d = d.normalized()
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	return Basis.looking_at(d, up)


## Every hit point along `from` + `dir` up to `length`, piercing up to `max_hits` colliders.
## Returns intersect_ray dictionaries in travel order (empty when nothing is hit).
func ray_hits(from: Vector3, dir: Vector3, length: float, mask: int, max_hits: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var space := space()
	if space == null or length <= 0.0 or dir.length_squared() < 0.0001:
		return out
	var skip: Array[RID] = exclude.duplicate()
	var params := PhysicsRayQueryParameters3D.create(from, from, mask, skip)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var start := from
	var left := length
	for _i in maxi(max_hits, 1):
		params.from = start
		params.to = start + dir * left
		params.exclude = skip
		var r := space.intersect_ray(params)
		if r.is_empty():
			break
		out.append(r)
		var obj: Object = r["collider"]
		if obj is CollisionObject3D:
			skip.append((obj as CollisionObject3D).get_rid())
		var travelled: float = start.distance_to(r["position"])
		left -= travelled + 0.05
		start = (r["position"] as Vector3) + dir * 0.05
		if left <= 0.0:
			break
	return out


func space() -> PhysicsDirectSpaceState3D:
	if source == null or not is_instance_valid(source) or not (source is Node3D):
		return null
	var w := (source as Node3D).get_world_3d()
	return w.direct_space_state if w != null else null


## Point a HitInfo at an impact and hand it to the receiver. Returns the damaged actor (null when the
## shot only met scenery). Emits Events.hit_landed, feeds marks, updates the hit marker and with
## `detonate_radius` > 0 also asks the COLLAPSE detonators to set off primed targets around the impact.
func deliver(hit: HitInfo, collider: Object, point: Vector3, normal: Vector3,
		detonate_radius: float = 0.0) -> Node:
	hit.position = point
	hit.normal = normal
	var receiver: Node = null
	if collider is Hurtbox:
		receiver = (collider as Hurtbox).apply(hit)
	elif collider is Node and (collider as Node).has_method(&"take_hit"):
		(collider as Node).call(&"take_hit", hit)
		receiver = collider as Node
	if receiver == null:
		return null
	Events.hit_landed.emit(hit, receiver)
	notify_mark(receiver, 1)
	mark_hit(hit, receiver)
	if detonate_radius > 0.0:
		detonate_primes(point, detonate_radius)
	return receiver


## Radial damage inside `radius` with linear falloff, one hit per actor. `exclude_actors` keeps the
## directly hit body from being charged twice. Returns the number of actors damaged.
func blast(center: Vector3, radius: float, damage: float, impact: float, kind: StringName,
		weapon: StringName, exclude_actors: Array[Node] = []) -> int:
	var space := space()
	if space == null or radius <= 0.0 or damage <= 0.0:
		return 0
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = Layers.MASK_PLAYER_ATTACK
	params.exclude = exclude
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var seen: Dictionary = {}
	for a in exclude_actors:
		if is_instance_valid(a):
			seen[a.get_instance_id()] = true
	var count := 0
	for r: Dictionary in space.intersect_shape(params, 24):
		var col: Object = r["collider"]
		if not (col is Hurtbox):
			continue
		var hb := col as Hurtbox
		var actor := hb.actor()
		if actor == null or seen.has(actor.get_instance_id()):
			continue
		seen[actor.get_instance_id()] = true
		var falloff := clampf(1.0 - center.distance_to(hb.global_position) / radius, 0.0, 1.0)
		if falloff <= 0.0:
			continue
		var hit := HitInfo.make(damage * falloff, kind, source, weapon)
		hit.stagger = impact * falloff
		hit.position = hb.global_position
		hit.normal = (hb.global_position - center).normalized()
		if hb.apply(hit) != null:
			count += 1
			Events.hit_landed.emit(hit, actor)
			notify_mark(actor, 1)
			mark_hit(hit, actor)
	return count


## Hit marker (CONTRACTS §4): kill > weak point > stagger > normal. The HUD reads `last_hit_usec`
## and `last_hit_kind` from the weapon component's `hud_state()`.
func mark_hit(hit: HitInfo, receiver: Node) -> void:
	last_hit_usec = Time.get_ticks_usec()
	var kind := &"normal"
	if hit.weak_point:
		kind = &"weak"
	var status: Variant = receiver.get(&"status") if is_instance_valid(receiver) else null
	if status != null and status is Object and (status as Object).has_method(&"is_staggered") \
			and bool((status as Object).call(&"is_staggered")):
		kind = &"stagger"
	if is_instance_valid(receiver) and receiver.has_method(&"is_alive") \
			and not bool(receiver.call(&"is_alive")):
		kind = &"kill"
	last_hit_kind = kind


## Marks (CONTRACTS §4): the enemies unit's StatusComponent, reached as `enemy.status`. Dummies and
## older stand-ins that carry the method themselves are still supported.
func notify_mark(receiver: Node, count: int) -> void:
	if not is_instance_valid(receiver):
		return
	var status: Variant = receiver.get(&"status")
	if status != null and status is Object and (status as Object).has_method(&"add_mark_hit"):
		(status as Object).call(&"add_mark_hit", count)
		return
	if receiver.has_method(&"add_mark_hit"):
		receiver.call(&"add_mark_hit", count)


## COLLAPSE (CONTRACTS §4): the skills unit listens in group `prime_detonators` and resolves the
## primed enemies inside `radius`. A stand-in `detonate_primed()` on the receiver still works.
func detonate_primes(center: Vector3, radius: float) -> void:
	var tree := _tree()
	if tree != null:
		tree.call_group(&"prime_detonators", &"detonate_primes", center, radius, source)


func _tree() -> SceneTree:
	return source.get_tree() if is_instance_valid(source) and source is Node else null


## Whether `from` can see `to` with only scenery in between (missile lock line of sight).
func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var space := space()
	if space == null:
		return false
	var dir := to - from
	var length := dir.length()
	if length < 0.01:
		return true
	var params := PhysicsRayQueryParameters3D.create(from, to, Layers.MASK_SIGHT, exclude)
	params.collide_with_areas = false
	return space.intersect_ray(params).is_empty()
