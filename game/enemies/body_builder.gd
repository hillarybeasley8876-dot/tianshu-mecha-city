class_name EnemyBodyBuilder
extends RefCounted
## Builds an enemy's collision capsule, hurtboxes, lock point and model (enemies-owned). Static so
## EnemyBase stays small; the model scene is the real monster when monster-assets has shipped it and
## the placeholder with the identical API until then (CONTRACTS §6).

const LOCK_PRIORITY_PER_MASS := 0.1


static func build_body(enemy: EnemyBase) -> Array[Hurtbox]:
	var radius := EnemyTypes.get_stat(enemy.enemy_type, "radius", 3.0)
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = maxf(enemy.body_height, radius * 2.0 + 0.1)
	var shape := CollisionShape3D.new()
	shape.shape = cap
	shape.position = Vector3.UP * cap.height * 0.5
	enemy.add_child(shape)
	var boxes: Array[Hurtbox] = []
	boxes.append(_hurtbox(enemy, &"body", Vector3.UP * cap.height * 0.5, radius * 0.95,
			cap.height * 0.45, false))
	boxes.append(_hurtbox(enemy, &"head", Vector3.UP * (cap.height - radius * 0.6), radius * 0.5,
			radius * 0.5, false))
	var weak := weak_point_offset(enemy.enemy_type)
	if weak != Vector3.INF:
		boxes.append(_hurtbox(enemy, &"weak", weak, radius * 0.45, radius * 0.45, true))
	if (EnemyTypes.ARMOUR.get(enemy.enemy_type, {}) as Dictionary).has(&"plate"):
		boxes.append(_hurtbox(enemy, &"plate",
				Vector3(0.0, cap.height * 0.55, -radius * 0.85), radius * 0.8,
				cap.height * 0.3, false))
	_lock_point(enemy, cap.height * 0.55, radius)
	return boxes


static func _lock_point(enemy: EnemyBase, at: float, radius: float) -> void:
	var lock := Targetable.new()
	lock.name = "Lock"
	lock.position = Vector3.UP * at
	lock.radius = radius
	lock.priority = 1.0 + enemy.mass_kg * LOCK_PRIORITY_PER_MASS
	enemy.add_child(lock)


static func _hurtbox(enemy: EnemyBase, part: StringName, at: Vector3, radius: float,
		half_height: float, weak: bool) -> Hurtbox:
	var hb := Hurtbox.new()
	hb.name = "Hurtbox_" + String(part)
	hb.part = part
	hb.is_weak_point = weak
	hb.collision_layer = Layers.ENEMY_HURTBOX
	hb.collision_mask = 0
	hb.position = at
	var cap := CapsuleShape3D.new()
	cap.radius = maxf(radius, 0.4)
	cap.height = maxf(half_height * 2.0, cap.radius * 2.0 + 0.1)
	var cs := CollisionShape3D.new()
	cs.shape = cap
	hb.add_child(cs)
	enemy.add_child(hb)
	return hb


## Position of the archetype's glowing weak point (the MAT_WEAK row in MonsterBodyParts), or INF.
static func weak_point_offset(type: StringName) -> Vector3:
	for row: Array in MonsterBodyParts.PARTS.get(type, []):
		if int(row[3]) == MonsterPlaceholderModel.MAT_WEAK:
			return row[1]
	return Vector3.INF


static func model_path(type: StringName) -> String:
	var real := "res://enemies/models/%s/%s_model.tscn" % [type, type]
	if ResourceLoader.exists(real):
		return real
	return "res://enemies/%s/placeholder/%s_placeholder.tscn" % [type, type]


## Returns the model node, or null after pushing a readable error (never a silent missing body).
static func build_model(enemy: EnemyBase) -> Node3D:
	var path := model_path(enemy.enemy_type)
	if not ResourceLoader.exists(path):
		push_error("EnemyBase: no model scene for '%s' (looked for %s)" % [enemy.enemy_type, path])
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("EnemyBase: cannot load model " + path)
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		push_error("EnemyBase: model scene root is not a Node3D: " + path)
		return null
	node.name = "Model"
	if &"body_type" in node:
		node.set(&"body_type", enemy.enemy_type)
	enemy.add_child(node)
	return node
