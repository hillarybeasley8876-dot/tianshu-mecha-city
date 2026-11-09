class_name SkillRigPlayer
extends CharacterBody3D
## Test stand-in for the PlayerMech (CONTRACTS §5): implements exactly the API the skill component is
## allowed to use, and nothing more. Deliberately independent of the weapons unit's RigPlayer so the
## skills tests keep working if that rig changes.
##
## `tuning` is a real MechTuning instance, so the numbers the SkillSystem reads back for the dash
## refund and the EN regen multiplier are the shipped ones.

var tuning: MechTuning = MechTuning.new()
var energy: float = 1000.0
var energy_max: float = 1000.0
var hp: float = 10000.0
var hp_max: float = 10000.0
var overdrive: float = 0.0
var overdrive_active: bool = false

var grounded: bool = true
var stick: Vector2 = Vector2.ZERO
var cancellable: bool = true
var locked_for: float = 0.0
var invuln: float = 0.0
var energy_spent: float = 0.0

var rig_aim: SkillRigAim = null
var rig_model: SkillRigModel = null
var _filters: Array[Callable] = []
var _fall: float = 0.0   ## the fall speed the rig itself has built up this flight
## Sum of the physics deltas the rig has actually seen. Feel's slow-mo scales `delta`, so a test that
## needs a rate (cooldowns per second) has to divide by this rather than by wall-clock frames.
var game_time: float = 0.0


func _ready() -> void:
	energy_max = tuning.energy_max
	energy = energy_max
	hp = hp_max
	collision_layer = Layers.PLAYER
	collision_mask = Layers.MASK_CHARACTER
	add_to_group(&"player")
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = tuning.capsule_radius
	cap.height = tuning.capsule_height
	shape.shape = cap
	add_child(shape)
	rig_aim = SkillRigAim.new()
	rig_aim.name = "RigAim"
	add_child(rig_aim)
	rig_model = SkillRigModel.new()
	rig_model.name = "RigModel"
	add_child(rig_model)
	# CONTRACTS §5: the model node sits 7.5 m below the body origin so the feet reach the ground
	rig_model.position = Vector3(0.0, -tuning.capsule_height * 0.5, 0.0)
	rig_model.build_body()


func _physics_process(delta: float) -> void:
	game_time += delta
	locked_for = maxf(locked_for - delta, 0.0)
	invuln = maxf(invuln - delta, 0.0)
	if is_on_floor():
		_fall = 0.0
		velocity.y = minf(velocity.y, 0.0)
	else:
		_fall = maxf(_fall - tuning.fall_gravity * delta, -tuning.terminal_speed)
		# the terminal speed clamps the fall the rig produced, never a velocity an ability set
		# directly (the Plunge dive drives 190 m/s straight down)
		velocity.y = minf(velocity.y, _fall)
	move_and_slide()
	grounded = is_on_floor()


# --- contract API (CONTRACTS §5) ------------------------------------------------------------------

func is_grounded() -> bool:
	return grounded


func is_flying() -> bool:
	return false


func is_boosting() -> bool:
	return false


func move_state() -> StringName:
	return &"idle"


func move_input() -> Vector2:
	return stick


func facing() -> Basis:
	return global_basis


func consume_energy(x: float) -> bool:
	if x <= 0.0:
		return true
	if energy < x:
		return false
	energy -= x
	energy_spent += x
	return true


func drain_energy(x: float, _big: bool = false) -> bool:
	energy = maxf(energy - x, 0.0)
	return energy > 0.0


func add_energy(x: float) -> void:
	energy = minf(energy + maxf(x, 0.0), energy_max)


func add_overdrive(pct: float) -> void:
	if not overdrive_active:
		overdrive = clampf(overdrive + pct, 0.0, tuning.od_max)


## Mirrors `MechEnergy.set_overdrive_active` exactly: a repeat call is a no-op, closing the window
## zeroes the OD meter and announces it ONCE. The death suite counts those events, so the stand-in
## may not be laxer than the shipped component it stands in for.
func set_overdrive_active(on: bool) -> void:
	if on == overdrive_active:
		return
	overdrive_active = on
	if not on:
		overdrive = 0.0
	Events.overdrive_changed.emit(on)


func heal(x: float) -> void:
	hp = minf(hp + x, hp_max)


func lunge_to(_point: Vector3, _speed: float, _max_time: float) -> void:
	pass


func apply_impulse(v: Vector3) -> void:
	velocity += v


func lock_movement(seconds: float, _allow_turn: bool = false) -> void:
	locked_for = maxf(locked_for, seconds)
	velocity = Vector3.ZERO


func set_strafe_aim(_on: bool) -> void:
	pass


func invulnerable_for(seconds: float) -> void:
	invuln = maxf(invuln, seconds)


func is_invulnerable() -> bool:
	return invuln > 0.0


func add_damage_filter(f: Callable) -> void:
	if f.is_valid() and not _filters.has(f):
		_filters.append(f)


func remove_damage_filter(f: Callable) -> void:
	_filters.erase(f)


func can_cancel(_tag: StringName = &"any") -> bool:
	return cancellable and locked_for <= 0.0


func model() -> Node3D:
	return rig_model


func aim() -> Node:
	return rig_aim


func take_hit(hit: HitInfo) -> void:
	for f in _filters:
		if f.is_valid() and bool(f.call(hit)):
			hit.final_amount = 0.0
			return
	hp -= hit.amount
	hit.final_amount = hit.amount


func is_alive() -> bool:
	return hp > 0.0


func get_team() -> int:
	return 0


func hit_pause(_seconds: float) -> void:
	pass


func telemetry() -> Dictionary:
	var out: Dictionary = {"energy": energy, "hp": hp, "od": overdrive}
	var s := get_node_or_null(^"SkillSystem")
	if s != null and s.has_method(&"hud_state"):
		out.merge(s.call(&"hud_state"), true)
	return out


## Timeline hooks for `tools/godot.sh drive --timeline=...` (autoplay calls these on Game.player).

## Put the crosshair somewhere, so the anchor / well / lance have an aim point.
func debug_aim(p: Array) -> void:
	if rig_aim != null and p.size() >= 3:
		rig_aim.point = Vector3(float(p[0]), float(p[1]), float(p[2]))


## Hard-lock the nearest enemy, so the fins / rift / plunge have a target.
func debug_lock() -> void:
	if rig_aim == null or not is_inside_tree():
		return
	var best: Node3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(&"enemy"):
		var e := n as Node3D
		if e == null:
			continue
		var d := e.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = e
	rig_aim.locked = best


## Cut the capture camera; the range owns it, so the rig forwards (autoplay only reaches Game.player).
func debug_cam(a: Array) -> void:
	var range := get_parent() as SkillsRange
	if range != null:
		range.debug_cam(a)


## Fill (or empty) the OD meter so the Overdrive can be demonstrated on demand.
func debug_od(pct: float) -> void:
	overdrive = clampf(pct, 0.0, tuning.od_max)


func debug_teleport(pos: Array, yaw_deg: float = 0.0) -> void:
	velocity = Vector3.ZERO
	global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	rotation.y = deg_to_rad(yaw_deg)
