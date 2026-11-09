class_name EnemyStrike
extends RefCounted
## Attack resolution (enemies-owned): arc sweeps, target picking and projectile/shockwave spawning.
## Static helpers so EnemyBase and every archetype share one implementation of "what does this
## swing actually hit".

## Weighted random pick from the archetype's attack table.
static func choose(list: Array[EnemyAttack]) -> EnemyAttack:
	if list.is_empty():
		return null
	var total := 0.0
	for a: EnemyAttack in list:
		total += maxf(a.weight, 0.0)
	if total <= 0.0:
		return list[0]
	var roll := randf() * total
	for a: EnemyAttack in list:
		roll -= maxf(a.weight, 0.0)
		if roll <= 0.0:
			return a
	return list[list.size() - 1]


## Sweeps the attack's arc once per active frame; stops after the first victim.
## Returns true when something was damaged, so the brain can stop retrying.
static func melee_sweep(host: EnemyBase, attack: EnemyAttack) -> bool:
	var space := host.get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(attack.range_max, 1.0)
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, host.centre())
	params.collision_mask = Layers.MASK_ENEMY_ATTACK
	params.exclude = [host.get_rid()]
	params.collide_with_areas = true
	params.collide_with_bodies = true
	for r: Dictionary in space.intersect_shape(params, 8):
		var col: Object = r.get("collider")
		if col is Hurtbox and _apply(host, attack, col as Hurtbox):
			return true
	return _fallback(host, attack)


## Damage a target that has no hurtbox volume (test dummies, early player stubs).
static func _fallback(host: EnemyBase, attack: EnemyAttack) -> bool:
	var t := host.target()
	if t == null or not is_instance_valid(t) or not t.has_method(&"take_hit"):
		return false
	if not in_arc(host, attack, t.global_position):
		return false
	var hit := attack.build_hit(host)
	hit.position = host.target_centre()
	hit.knockback = (t.global_position - host.global_position).normalized() * attack.knockback
	t.call(&"take_hit", hit)
	host.attack_landed.emit(host, attack.id)
	return true


static func _apply(host: EnemyBase, attack: EnemyAttack, box: Hurtbox) -> bool:
	var victim := box.actor() as Node3D
	if victim == null or victim == host or not in_arc(host, attack, victim.global_position):
		return false
	var hit := attack.build_hit(host)
	hit.position = box.global_position
	hit.knockback = (victim.global_position - host.global_position).normalized() * attack.knockback
	if box.apply(hit) == null:
		return false
	host.attack_landed.emit(host, attack.id)
	return true


static func in_arc(host: EnemyBase, attack: EnemyAttack, at: Vector3) -> bool:
	var to := at - host.global_position
	if to.length() > attack.range_max + 4.0:
		return false
	if attack.arc_deg >= 360.0:
		return true
	return (-host.global_transform.basis.z).dot(to.normalized()) >= cos(deg_to_rad(attack.arc_deg * 0.5))


## Projectiles and shockwaves are spawned once, at the start of the active window.
static func spawn(host: EnemyBase, attack: EnemyAttack) -> bool:
	var parent := host.get_parent()
	if parent == null:
		push_error("EnemyStrike: enemy '%s' has no parent to spawn into" % host.enemy_type)
		return false
	if attack.shockwave_radius > 0.0:
		EnemyShockwave.spawn(parent, host.global_position, attack)
		return true
	if attack.projectile_speed > 0.0:
		EnemyProjectilePool.spawn(parent, host.model_socket(&"muzzle").global_position,
				host.target_centre(), attack, host)
		return true
	return false
