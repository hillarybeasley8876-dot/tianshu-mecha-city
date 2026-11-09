class_name FlowFakePlayer
extends CharacterBody3D
## A stand-in hero for the flow tests: a real body on `Layers.PLAYER` (so the arena and crown triggers
## fire for real) carrying the handful of PlayerMech members the flow unit touches. It is NOT a
## PlayerMech — anything flow calls that is missing here would be a flow bug worth failing on.

var hp: float = 10000.0
var hp_max: float = 10000.0
var energy: float = 1000.0
var energy_max: float = 1000.0
var invuln_left: float = 0.0
var last_impulse: Vector3 = Vector3.ZERO

var _shape: CollisionShape3D = null


func _ready() -> void:
	add_to_group(&"player")
	collision_layer = Layers.PLAYER
	collision_mask = 0
	_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 3.5
	capsule.height = 15.0
	_shape.shape = capsule
	add_child(_shape)
	Game.register_player(self)


func _physics_process(delta: float) -> void:
	invuln_left = maxf(invuln_left - delta, 0.0)


func heal(amount: float) -> void:
	hp = minf(hp + amount, hp_max)


func add_energy(amount: float) -> void:
	energy = minf(energy + amount, energy_max)


func invulnerable_for(seconds: float) -> void:
	invuln_left = maxf(invuln_left, seconds)


## Records the shove instead of applying it: the collapse beat checks that standing inside the blast
## throws the mech clear (SPEC §4 `apply_impulse`).
func apply_impulse(v: Vector3) -> void:
	last_impulse = v


func is_invulnerable() -> bool:
	return invuln_left > 0.0


## The fake never leaves the ground: the crown gate asks for this (CONTRACTS §5) before it starts the
## boss fight, so a hero flying through the gate volume on the catapult does not start it mid-air.
func is_grounded() -> bool:
	return true


func is_alive() -> bool:
	return hp > 0.0


func get_team() -> int:
	return 0


func model() -> Node3D:
	return null


func hud_state() -> Dictionary:
	return {"hp": hp, "hp_max": hp_max, "en": energy, "en_max": energy_max, "alive": is_alive()}


func debug_teleport(pos: Array, yaw_deg: float = 0.0) -> void:
	velocity = Vector3.ZERO
	global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	rotation.y = deg_to_rad(yaw_deg)


## Test helper: kill the hero the way the damage pipeline would, so flow sees the real signal.
func die() -> void:
	hp = 0.0
	Events.player_died.emit()
