class_name RigPlayer
extends CharacterBody3D
## Test stand-in for the PlayerMech (CONTRACTS §5): implements exactly the API the weapon component
## is allowed to use. Wave-1's mech-move unit will replace it; the component never notices.

var energy: float = 1000.0
var energy_max: float = 1000.0
var hp: float = 4200.0
var hp_max: float = 4200.0
var strafe_aim: bool = false
var energy_spent: float = 0.0

var aim_system: RigAim = null
var rig_model: RigModel = null


func _ready() -> void:
	collision_layer = Layers.PLAYER
	collision_mask = 0
	add_to_group(&"player")
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 4.0
	cap.height = 16.0
	shape.shape = cap
	shape.position = Vector3(0.0, 8.0, 0.0)
	add_child(shape)
	aim_system = RigAim.new()
	aim_system.name = "RigAim"
	aim_system.position = Vector3(0.0, 11.5, 0.0)
	add_child(aim_system)
	rig_model = RigModel.new()
	rig_model.name = "RigModel"
	add_child(rig_model)


func consume_energy(x: float) -> bool:
	if x <= 0.0:
		return true
	if energy < x:
		return false
	energy -= x
	energy_spent += x
	return true


func add_energy(x: float) -> void:
	energy = minf(energy + x, energy_max)


func heal(x: float) -> void:
	hp = minf(hp + x, hp_max)


func set_strafe_aim(on: bool) -> void:
	strafe_aim = on


func lock_movement(_seconds: float, _allow_turn: bool = false) -> void:
	pass


func apply_impulse(v: Vector3) -> void:
	velocity += v


func invulnerable_for(_seconds: float) -> void:
	pass


func is_invulnerable() -> bool:
	return false


func model() -> Node3D:
	return rig_model


## The first-person lens, from camera-aim's own rule (`player/camera/cockpit_frame.gd:54`): the
## model's `cockpit` socket, lifted to the SPEC §5 11.5 m eye band floor, then 1.2 m forward at the
## canopy glass. Mirrored rather than loaded so the rig has no hard dependency on another unit's
## file; `RigAim` parks its Camera3D here every tick, and that camera is what `WeaponContext.lens()`
## reads — the same public API the real AimSystem answers.
func lens() -> Vector3:
	var eye := global_position + Vector3.UP * 13.5
	var s := rig_model.socket(&"cockpit") if rig_model != null else null
	if s != null:
		eye = s.global_position
	eye.y = maxf(eye.y, global_position.y + 11.5)
	return eye - global_basis.z.normalized() * 1.2


func aim() -> Node:
	return aim_system


func telemetry() -> Dictionary:
	var out: Dictionary = {"energy": energy, "hp": hp, "strafe_aim": strafe_aim}
	var ws := get_node_or_null(^"WeaponSystem")
	if ws != null and ws.has_method(&"hud_state"):
		out.merge(ws.call(&"hud_state"), true)
	return out


## Timeline hook: point the crosshair somewhere (tools/godot.sh drive --timeline=...).
func debug_aim(p: Array) -> void:
	if aim_system != null and p.size() >= 3:
		aim_system.point = Vector3(float(p[0]), float(p[1]), float(p[2]))


func debug_teleport(pos: Array, yaw_deg: float) -> void:
	global_position = Vector3(pos[0], pos[1], pos[2])
	global_rotation.y = deg_to_rad(yaw_deg)


# --- damageable actor contract -----------------------------------------------------------------
func take_hit(hit: HitInfo) -> void:
	hp -= hit.amount
	hit.final_amount = hit.amount


func is_alive() -> bool:
	return hp > 0.0


func get_team() -> int:
	return 0


func hit_pause(_seconds: float) -> void:
	pass
