class_name EnemyBlast
extends RefCounted
## Area damage from enemy attacks (enemies-owned): acid bursts, shockwave impacts. Queries
## Layers.MASK_ENEMY_ATTACK so barriers and cover protect the player, and applies distance falloff.

const FALLOFF_MIN := 0.35   ## a hit at the very edge still does 35 %


## Damages every hurtbox victim inside `radius` of `at`. `exclude` keeps the shooter out.
static func apply(world: World3D, at: Vector3, radius: float, hit: HitInfo, exclude: Node) -> int:
	if world == null:
		return 0
	var space := world.direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(radius, 0.5)
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, at)
	params.collision_mask = Layers.MASK_ENEMY_ATTACK
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var excluded: Array[RID] = []
	if exclude is CollisionObject3D:
		excluded.append((exclude as CollisionObject3D).get_rid())
	params.exclude = excluded
	var hit_count := 0
	var seen: Array[Node] = []
	for r: Dictionary in space.intersect_shape(params, 12):
		var col: Object = r.get("collider")
		if not (col is Hurtbox):
			continue
		var box := col as Hurtbox
		var victim := box.actor()
		if victim == null or victim in seen or victim == exclude:
			continue
		seen.append(victim)
		var copy := hit.duplicate_hit()
		var d := at.distance_to(box.global_position)
		copy.amount *= lerpf(1.0, FALLOFF_MIN, clampf(d / sphere.radius, 0.0, 1.0))
		copy.position = box.global_position
		copy.knockback = (box.global_position - at).normalized() * hit.knockback.length()
		if box.apply(copy) != null:
			hit_count += 1
	return hit_count
