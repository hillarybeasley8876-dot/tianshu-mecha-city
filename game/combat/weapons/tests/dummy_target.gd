class_name DummyTarget
extends StaticBody3D
## Test dummy (weapons unit): a static body carrying a Hurtbox on ENEMY_HURTBOX plus a Targetable
## lock point. Records everything a shot tells it so the weapon tests can assert damage, pierce
## counts, marks and primes. Never dies, so a test can keep shooting the same dummy.

signal hit_taken(hit: HitInfo)

@export var size: float = 10.0

var damage_taken: float = 0.0
var stagger_taken: float = 0.0
var hits: int = 0
var primes: int = 0
var hit_pauses: int = 0
var hurtbox: Hurtbox = null
var lock_point: Targetable = null
var status := DummyStatus.new()


func _ready() -> void:
	collision_layer = Layers.ENEMY   # scenery/hurtbox queries never touch the body itself
	collision_mask = 0
	var body_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, size, size)
	body_shape.shape = box
	add_child(body_shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size, size, size)
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.38, 0.42)
	mesh.material_override = mat
	add_child(mesh)
	hurtbox = Hurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = Layers.ENEMY_HURTBOX
	hurtbox.collision_mask = 0
	var hshape := CollisionShape3D.new()
	var hbox := BoxShape3D.new()
	hbox.size = Vector3(size, size, size)
	hshape.shape = hbox
	hurtbox.add_child(hshape)
	add_child(hurtbox)
	lock_point = Targetable.new()
	lock_point.name = "Lock"
	lock_point.radius = size * 0.5
	add_child(lock_point)
	var detonator := DummyDetonator.new()
	detonator.name = "Detonator"
	detonator.target = self
	add_child(detonator)


func reset() -> void:
	damage_taken = 0.0
	stagger_taken = 0.0
	hits = 0
	primes = 0
	status.marks = 0
	status.primed = false
	status.staggered = false


# --- damageable actor contract (CONTRACTS §4) -------------------------------------------------
func take_hit(hit: HitInfo) -> void:
	hits += 1
	damage_taken += hit.amount
	stagger_taken += hit.stagger
	hit.final_amount = hit.amount
	hit_taken.emit(hit)


func is_alive() -> bool:
	return true


func get_team() -> int:
	return 1


func hit_pause(_seconds: float) -> void:
	hit_pauses += 1


# --- StatusComponent stand-in (CONTRACTS §4: marks arrive as `actor.status.add_mark_hit(n)`) ----
class DummyStatus:
	extends RefCounted
	var marks: int = 0
	var primed: bool = false
	var staggered: bool = false

	func add_mark_hit(count: int = 1) -> void:
		marks += count

	func consume_marks() -> int:
		var n := marks
		marks = 0
		return n

	func prime(_seconds: float = 4.0) -> void:
		primed = true

	func is_primed() -> bool:
		return primed

	func is_staggered() -> bool:
		return staggered


## COLLAPSE stand-in: the real one is the skills unit's SkillSystem in group `prime_detonators`.
class DummyDetonator:
	extends Node
	var target: DummyTarget = null

	func _ready() -> void:
		add_to_group(&"prime_detonators")

	func detonate_primes(center: Vector3, radius: float, _source: Node) -> void:
		if target == null or not is_instance_valid(target) or not target.status.is_primed():
			return
		if target.global_position.distance_to(center) > radius + target.size:
			return
		target.primes += 1
		target.status.primed = false
