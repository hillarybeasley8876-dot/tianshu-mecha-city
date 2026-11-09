class_name DummyPlayer
extends CharacterBody3D
## Stationary stand-in for the hero (enemies unit tests and the AI demo movie). It is a real actor:
## group `&"player"`, a `Hurtbox` on PLAYER_HURTBOX, `take_hit` counting, `facing()`, `telemetry()`.
## The mech-move unit's PlayerMech replaces it in the real build; nothing here is imported by
## gameplay code.

signal hit_taken(hit: HitInfo)

@export var body_height: float = 16.0
@export var radius: float = 6.0

var hits: int = 0
var damage_taken: float = 0.0
## Damage split by `HitInfo.weapon`, so a balance run shows which attack is doing the work.
var damage_by_weapon: Dictionary = {}
## Hits per weapon. The incoming-damage reading is heavily quantised — one acid arc is 320 damage,
## so a 20 s window that lands 10 of them instead of 15 reads 80 DPS lower for no design reason —
## and the hit count is what makes that visible in the log instead of mysterious.
var hits_by_weapon: Dictionary = {}
var last_weapon: StringName = &""
var last_parryable: bool = false
var last_unblockable: bool = false
var invulnerable: bool = false


func _ready() -> void:
	add_to_group(&"player")
	collision_layer = Layers.PLAYER
	collision_mask = Layers.MASK_CHARACTER
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = body_height
	var shape := CollisionShape3D.new()
	shape.shape = cap
	shape.position = Vector3.UP * body_height * 0.5
	add_child(shape)
	var box := Hurtbox.new()
	box.name = "Hurtbox_body"
	box.collision_layer = Layers.PLAYER_HURTBOX
	box.collision_mask = 0
	var box_shape := CollisionShape3D.new()
	box_shape.shape = cap.duplicate()
	box_shape.position = Vector3.UP * body_height * 0.5
	box.add_child(box_shape)
	add_child(box)
	_build_visual()


## A visible 16 m mech silhouette, so captures and the demo movie show what the pack is attacking.
## Cyan accents follow the kit's colour code (skills-catalog §4.12: cyan = player).
func _build_visual() -> void:
	_part(Vector3(7.0, 8.0, 5.0), Vector3(0.0, 9.0, 0.0), Color(0.62, 0.65, 0.70))
	_part(Vector3(4.0, 3.0, 4.0), Vector3(0.0, 14.6, 0.0), Color(0.72, 0.75, 0.80))
	_part(Vector3(2.6, 1.0, 0.4), Vector3(0.0, 14.8, -2.1), Color(0.25, 0.95, 1.0))
	_part(Vector3(2.4, 5.0, 2.4), Vector3(-2.2, 2.6, 0.0), Color(0.52, 0.55, 0.60))
	_part(Vector3(2.4, 5.0, 2.4), Vector3(2.2, 2.6, 0.0), Color(0.52, 0.55, 0.60))
	_part(Vector3(1.8, 5.5, 1.8), Vector3(-4.6, 9.0, 0.0), Color(0.58, 0.60, 0.65))
	_part(Vector3(1.8, 5.5, 1.8), Vector3(4.6, 9.0, 0.0), Color(0.58, 0.60, 0.65))


func _part(size: Vector3, at: Vector3, colour: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.5
	mat.metallic = 0.4
	if colour.b > 0.9:
		mat.emission_enabled = true
		mat.emission = colour
		mat.emission_energy_multiplier = 2.5
	mi.material_override = mat
	add_child(mi)


func take_hit(hit: HitInfo) -> void:
	hit.final_amount = 0.0 if invulnerable else hit.amount
	damage_taken += hit.final_amount
	damage_by_weapon[hit.weapon] = float(damage_by_weapon.get(hit.weapon, 0.0)) + hit.final_amount
	hits_by_weapon[hit.weapon] = int(hits_by_weapon.get(hit.weapon, 0)) + 1
	hits += 1
	last_weapon = hit.weapon
	last_parryable = hit.parryable
	last_unblockable = hit.unblockable
	hit_taken.emit(hit)


func is_alive() -> bool:
	return true


func get_team() -> int:
	return 0


func facing() -> Basis:
	return global_transform.basis


## Flat numbers for tools/autoplay.gd (CONTRACTS §5 telemetry shape).
func telemetry() -> Dictionary:
	return {"hp": 10000.0 - damage_taken, "hits_taken": hits, "pos_x": global_position.x,
			"pos_y": global_position.y, "pos_z": global_position.z}
