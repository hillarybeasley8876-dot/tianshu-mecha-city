class_name BossBody
extends RefCounted
## The Brood Titan's collision body (boss unit): one capsule, three hurtboxes (body / head / armoured
## legs), the body lock point and the three weak cores. Statics, for the same reason the enemies unit
## has `EnemyBodyBuilder` — so `brood_titan.gd` stays the actor instead of growing a shape factory.
##
## The shapes are the titan's own because `EnemyTypes` (enemies-owned) has no titan row: an 18 m
## radius and a 60 m height have nothing to do with a 6 m ripper's numbers.

const LOCK_HEIGHT := 32.0
const BODY := {"at": Vector3.UP * 34.0, "r": 15.0, "half": 13.0}
const HEAD := {"at": Vector3.UP * 53.0, "r": 8.0, "half": 5.0}
const LEGS := {"at": Vector3.UP * 10.0, "r": 13.0, "half": 10.0}
## The body lock point sits below the cores' priority 50, so locking the titan and locking a core are
## both available and the cores win when the reticle is on one.
const LOCK_PRIORITY := 10.0


## Builds everything under `titan` and returns its three cores.
static func build(titan: BroodTitan) -> Array[BossCore]:
	_capsule(titan)
	_hurtbox(titan, &"body", BODY)
	_hurtbox(titan, &"head", HEAD)
	_hurtbox(titan, &"legs", LEGS)
	_lock_point(titan)
	return _cores(titan)


static func _capsule(titan: BroodTitan) -> void:
	var cap := CapsuleShape3D.new()
	cap.radius = BossTuning.RADIUS
	cap.height = BossTuning.HEIGHT
	var shape := CollisionShape3D.new()
	shape.shape = cap
	shape.position = Vector3.UP * cap.height * 0.5
	titan.add_child(shape)


static func _hurtbox(titan: BroodTitan, part: StringName, row: Dictionary) -> void:
	var hb := Hurtbox.new()
	hb.name = "Hurtbox_" + String(part)
	hb.part = part
	hb.collision_layer = Layers.ENEMY_HURTBOX
	hb.collision_mask = 0
	hb.position = row["at"]
	var radius := float(row["r"])
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = maxf(float(row["half"]) * 2.0, radius * 2.0 + 0.1)
	var cs := CollisionShape3D.new()
	cs.shape = cap
	hb.add_child(cs)
	titan.add_child(hb)


static func _lock_point(titan: BroodTitan) -> void:
	var lock := Targetable.new()
	lock.name = "Lock"
	lock.position = Vector3.UP * LOCK_HEIGHT
	lock.radius = BossTuning.RADIUS
	lock.priority = LOCK_PRIORITY
	titan.add_child(lock)


static func _cores(titan: BroodTitan) -> Array[BossCore]:
	var out: Array[BossCore] = []
	for row: Dictionary in BossTuning.CORES:
		var core := BossCore.make(titan, row)
		titan.add_child(core)
		out.append(core)
	return out
