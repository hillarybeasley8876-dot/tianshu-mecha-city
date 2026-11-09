class_name MeleeRigPlayer
extends CharacterBody3D
## Test stand-in for the PlayerMech (CONTRACTS §5): implements exactly the API the melee and defence
## components are allowed to use, and records what they asked for (energy spent, lunges, i-frames,
## movement locks) so the suites can assert on it. Wave-1's mech-move unit replaces it in the game;
## the components never notice.

signal lunge_requested(point: Vector3, speed: float, max_time: float)

var energy: float = 1000.0
var energy_max: float = 1000.0
var hp: float = 10000.0
var hp_max: float = 10000.0
var overdrive: float = 0.0
var grounded: bool = true
var move_state_name: StringName = &"idle"
var invuln_left: float = 0.0
var lock_left: float = 0.0
var energy_spent: float = 0.0
var energy_gained: float = 0.0
var healed: float = 0.0
var lunges: int = 0
var filters: Array[Callable] = []
var model_ref: Node3D = null
var aim_ref: MeleeRigAim = null
## Headless suites take the recording stub instead of the shipped placeholder: it carries the whole
## HeroModel contract surface (`paused`, `set_saber_drawn`), which the placeholder only partly does.
var force_stub_model: bool = false

const PLACEHOLDER_MODEL := "res://player/model/placeholder/placeholder_model.tscn"
## CONTRACTS §5: the model origin sits between the feet, and PlayerMech hangs it 7.5 m below the
## body origin (the capsule centre).
const MODEL_DROP := 7.5

## Which model to hang off the rig. The suites take the recording stub; the demo range takes the
## shipped hero (`--hero`), because the blade is the `saber_r` socket now and only the real rig's
## clips sweep it (review r4).
var model_scene: String = PLACEHOLDER_MODEL


func _ready() -> void:
	collision_layer = Layers.PLAYER
	collision_mask = 0
	add_to_group(&"player")
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 3.5
	cap.height = 15.0
	shape.shape = cap
	add_child(shape)
	model_ref = _make_model()
	aim_ref = MeleeRigAim.new()
	aim_ref.name = "RigAim"
	add_child(aim_ref)


## The shipped hero (or placeholder) when it exists — captures should show the real mech, not a box —
## and the recording stub otherwise (headless suites never need the mesh).
func _make_model() -> Node3D:
	if not force_stub_model and ResourceLoader.exists(model_scene):
		var node := (load(model_scene) as PackedScene).instantiate() as Node3D
		if node != null:
			node.name = "RigModel"
			node.position = Vector3(0.0, -MODEL_DROP, 0.0)
			add_child(node)
			return node
	var stub := MeleeRigModel.new()
	stub.name = "RigModel"
	add_child(stub)
	return stub


func _physics_process(delta: float) -> void:
	invuln_left = maxf(invuln_left - delta, 0.0)
	lock_left = maxf(lock_left - delta, 0.0)
	_travel(delta)


# --- PlayerMech contract (CONTRACTS §5) ---------------------------------------------------------
func is_grounded() -> bool:
	return grounded


func is_flying() -> bool:
	return false


func is_boosting() -> bool:
	return move_state_name == &"slide" or move_state_name == &"assault"


func move_state() -> StringName:
	return move_state_name


func move_input() -> Vector2:
	return Vector2.ZERO


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
	if energy < x:
		return false
	energy -= x
	energy_spent += x
	return true


func add_energy(x: float) -> void:
	energy = minf(energy + x, energy_max)
	energy_gained += x


func add_overdrive(pct: float) -> void:
	overdrive = minf(overdrive + pct, 100.0)


func can_cancel(_tag: StringName = &"any") -> bool:
	return lock_left <= 0.0


func heal(x: float) -> void:
	hp = minf(hp + x, hp_max)
	healed += x


## MechAir.lunge in miniature: travel at `speed` toward the point, stopping `lunge_arrive` metres
## short, on arrival or when the time runs out. The melee system re-issues it every tick while
## homing, which is exactly what MechLocomotion expects.
const LUNGE_ARRIVE := 3.0

var _lunge_point: Vector3 = Vector3.ZERO
var _lunge_speed: float = 0.0
var _lunge_left: float = 0.0


func lunge_to(point: Vector3, speed: float, max_time: float) -> void:
	lunges += 1
	lunge_requested.emit(point, speed, max_time)
	_lunge_point = point
	_lunge_speed = maxf(speed, 1.0)
	_lunge_left = maxf(max_time, 0.0)


func _travel(delta: float) -> void:
	if _lunge_left <= 0.0:
		return
	_lunge_left = maxf(_lunge_left - delta, 0.0)
	var to := _lunge_point - global_position
	to.y = 0.0
	var dist := to.length()
	if dist <= LUNGE_ARRIVE or dist < 0.01:
		_lunge_left = 0.0
		return
	global_position += to / dist * minf(_lunge_speed * delta, dist - LUNGE_ARRIVE)


func apply_impulse(v: Vector3) -> void:
	velocity += v


func lock_movement(seconds: float, _allow_turn: bool = false) -> void:
	lock_left = maxf(lock_left, seconds)


func set_strafe_aim(_on: bool) -> void:
	pass


func invulnerable_for(seconds: float) -> void:
	invuln_left = maxf(invuln_left, seconds)


func is_invulnerable() -> bool:
	return invuln_left > 0.0


func add_damage_filter(f: Callable) -> void:
	if f.is_valid() and not filters.has(f):
		filters.append(f)


func model() -> Node3D:
	return model_ref


func aim() -> Node:
	return aim_ref


func telemetry() -> Dictionary:
	return {"energy": energy, "hp": hp, "lunges": lunges}


func debug_teleport(pos: Array, yaw_deg: float = 0.0) -> void:
	global_position = Vector3(pos[0], pos[1], pos[2])
	global_rotation.y = deg_to_rad(yaw_deg)


## Demo-range hooks (the capture scene fills `demo_targets`): `drive --timeline` can only call
## methods on the registered player, so the lock and the stagger are routed through here.
var demo_targets: Array[Node3D] = []
var demo_spit: Callable = Callable()


func debug_spit() -> void:
	if demo_spit.is_valid():
		demo_spit.call()


func debug_lock(index: int) -> void:
	if aim_ref == null:
		return
	if index < 0 or index >= demo_targets.size():
		aim_ref.lock(null)
		return
	aim_ref.lock(demo_targets[index])


func debug_stagger(index: int) -> void:
	if index < 0 or index >= demo_targets.size():
		return
	var t := demo_targets[index]
	if t.has_method(&"stagger"):
		t.call(&"stagger")


## Airborne toggle for the aerial-string capture: the rig has no gravity, so the pose is set.
func debug_air(on: bool) -> void:
	grounded = not on
	move_state_name = &"hover" if on else &"idle"
	if on:
		global_position.y = 44.0
		velocity = Vector3.ZERO


## Points the crosshair without taking a hard lock (the aerial string must not become a lunge).
func debug_aim(p: Array) -> void:
	if aim_ref != null and p.size() >= 3:
		aim_ref.look_at_point(Vector3(float(p[0]), float(p[1]), float(p[2])))


## Walks a target to `metres` in front of the mech and turns it to face it, so a Core Rend can be
## staged without moving the mech.
func debug_close(index: int, metres: float) -> void:
	if index < 0 or index >= demo_targets.size():
		return
	var t := demo_targets[index]
	var at := global_position + (-global_basis.z) * metres
	at.y = 6.0
	t.global_position = at
	t.look_at(global_position, Vector3.UP)


func debug_reset_pose() -> void:
	velocity = Vector3.ZERO
	grounded = true
	move_state_name = &"idle"


# --- damageable actor contract (CONTRACTS §4) ---------------------------------------------------
func take_hit(hit: HitInfo) -> void:
	for f in filters:
		if f.is_valid() and bool(f.call(hit)):
			hit.final_amount = 0.0
			return
	hp = maxf(hp - hit.amount, 0.0)
	hit.final_amount = hit.amount


func is_alive() -> bool:
	return hp > 0.0


func get_team() -> int:
	return 0


func hit_pause(_seconds: float) -> void:
	pass


func reset_state() -> void:
	energy = energy_max
	hp = hp_max
	overdrive = 0.0
	energy_spent = 0.0
	energy_gained = 0.0
	healed = 0.0
	lunges = 0
	_lunge_left = 0.0
	invuln_left = 0.0
	lock_left = 0.0
	velocity = Vector3.ZERO
