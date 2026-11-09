class_name MeleeDummy
extends CharacterBody3D
## Test enemy (melee unit): a static hurtbox that records everything a swing tells it, plus the
## Core Rend surface (`is_executable` / `execute_hit`, CONTRACTS §6) and a StatusComponent
## stand-in, so the execution rules can be asserted without the enemies unit's AI running.

signal hit_taken(hit: HitInfo)

const EXECUTE_RANGE := 14.0     ## mirrors enemies/enemy_base.gd (skills-catalog §4.6 ×2)
const EXECUTE_ARC_DEG := 60.0

@export var size: float = 12.0
@export var enemy_type: StringName = &"mantis"

var hp: float = 1800.0
var hp_max: float = 1800.0
var alive: bool = true
var status: DummyStatus = null
var damage_taken: float = 0.0
var stagger_taken: float = 0.0
var hits: int = 0
var hit_pauses: int = 0
var executions: int = 0
var ai_enabled: bool = true
var hurtbox: Hurtbox = null
var lock_point: Targetable = null


class DummyStatus:
	extends RefCounted
	var stability: float = 700.0
	var staggered: bool = false
	var marks: int = 0
	var primed: bool = false

	func add_impact(amount: float) -> bool:
		stability = maxf(stability - amount, 0.0)
		if stability <= 0.0:
			staggered = true
		return staggered

	func is_staggered() -> bool:
		return staggered

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

	func detonate_primed() -> void:
		primed = false


func _ready() -> void:
	add_to_group(&"enemy")
	collision_layer = Layers.ENEMY
	collision_mask = 0
	status = DummyStatus.new()
	var body := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, size, size)
	body.shape = box
	add_child(body)
	_body_mesh()
	hurtbox = Hurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = Layers.ENEMY_HURTBOX
	hurtbox.collision_mask = 0
	var hs := CollisionShape3D.new()
	var hb := BoxShape3D.new()
	hb.size = Vector3(size, size, size)
	hs.shape = hb
	hurtbox.add_child(hs)
	add_child(hurtbox)
	lock_point = Targetable.new()
	lock_point.name = "Lock"
	lock_point.radius = size * 0.5
	add_child(lock_point)


## A husk silhouette so captures read as a monster rather than a cube: a hunched carapace, two legs
## and a glowing core (ART.md: the 蚀骸 HUSK are biomechanical, dark plating with acid-green light).
func _body_mesh() -> void:
	var plate := StandardMaterial3D.new()
	plate.albedo_color = Color(0.24, 0.22, 0.25)
	plate.roughness = 0.65
	plate.metallic = 0.25
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(0.61, 1.0, 0.23)
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.61, 1.0, 0.23)
	core_mat.emission_energy_multiplier = 1.6
	_part(Vector3(0.0, size * 0.1, 0.0), Vector3(size * 0.8, size * 0.62, size * 1.05), plate)
	_part(Vector3(0.0, size * 0.42, -size * 0.34), Vector3(size * 0.5, size * 0.34, size * 0.5),
			plate)
	for side in [-1.0, 1.0]:
		_part(Vector3(side * size * 0.26, -size * 0.34, 0.0),
				Vector3(size * 0.2, size * 0.62, size * 0.24), plate)
	_part(Vector3(0.0, size * 0.06, size * 0.5), Vector3(size * 0.2, size * 0.2, size * 0.08),
			core_mat)


func _part(at: Vector3, box_size: Vector3, mat: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.position = at
	add_child(mesh)


func reset() -> void:
	hp = hp_max
	alive = true
	damage_taken = 0.0
	stagger_taken = 0.0
	hits = 0
	hit_pauses = 0
	executions = 0
	status = DummyStatus.new()


## Core Rend gate (skills-catalog §4.6): staggered, alive, inside 14 m and ±60° in front.
func is_executable(by: Node3D) -> bool:
	if not alive or not status.is_staggered() or by == null or not is_instance_valid(by):
		return false
	var to := by.global_position - global_position
	if to.length() > EXECUTE_RANGE:
		return false
	return (-global_basis.z).dot(to.normalized()) >= cos(deg_to_rad(EXECUTE_ARC_DEG))


func execute_hit(by: Node3D, damage: float = 9999.0) -> void:
	if not is_executable(by):
		return
	executions += 1
	var hit := HitInfo.make(damage, HitInfo.MELEE, by, &"core_rend")
	hit.finisher = true
	take_hit(hit)


## EnemyBase.set_ai_enabled (CONTRACTS §6): a perfect parry pauses the attacker's AI for 0.6 s.
func set_ai_enabled(on: bool) -> void:
	ai_enabled = on


## EnemyBase.handles_own_knockback (CONTRACTS §6, enemies r3): the real monsters return true because
## their own stagger reaction carries the shove. Off here so the suite can prove both branches.
var own_knockback: bool = false


func handles_own_knockback() -> bool:
	return own_knockback


func stagger() -> void:
	status.stability = 0.0
	status.staggered = true


# --- damageable actor contract (CONTRACTS §4) ---------------------------------------------------
func take_hit(hit: HitInfo) -> void:
	if not alive:
		return
	hits += 1
	damage_taken += hit.amount
	stagger_taken += hit.stagger
	hit.final_amount = hit.amount
	if hit.stagger > 0.0:
		status.add_impact(hit.stagger)
	if hit.knockback != Vector3.ZERO:
		velocity += hit.knockback
	hit_taken.emit(hit)
	hp = maxf(hp - hit.amount, 0.0)  # the dummy never dies, so a suite can keep swinging it


func is_alive() -> bool:
	return alive


func get_team() -> int:
	return 1


func hit_pause(_seconds: float) -> void:
	hit_pauses += 1
