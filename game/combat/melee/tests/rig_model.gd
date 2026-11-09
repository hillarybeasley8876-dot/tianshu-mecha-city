class_name MeleeRigModel
extends Node3D
## Test stand-in for the HeroModel (CONTRACTS §5): records the action ids the component plays so the
## suites can assert that every move drives the model, and offers the `saber_r` socket the blade
## visual attaches to. `play_action` also SWINGS that socket, the way a real clip moves the hand, so
## the blade-in-hand suite is a real check instead of a comparison against a fixed point.

## Length of the synthetic swing `play_action` runs, seconds.
const SWING_TIME := 0.45
const SWING_DEG := 130.0
const SOCKET_REST := Vector3(0.0, 11.0, -1.0)

var actions: Array[StringName] = []
var locomotion: StringName = &"idle"
var saber_drawn: bool = false
var pause_left: float = 0.0
## hero-v3 compatibility (review r5 item 2): flip this on to make the stand-in answer like a model
## that carries its own steel blade, and the saber visual must stop drawing a second one.
var own_blade: bool = false

var _sockets: Dictionary = {}
var _swing_left: float = 0.0


func _ready() -> void:
	for n: StringName in [&"saber_r", &"shield_l", &"hand_r", &"muzzle_r"]:
		var m := Marker3D.new()
		m.name = String(n)
		m.position = SOCKET_REST
		add_child(m)
		_sockets[n] = m


func _physics_process(delta: float) -> void:
	pause_left = maxf(pause_left - delta, 0.0)
	_swing(delta)


## The hand sweeps from high-right to low-left across the clip, and travels with it. This is what
## the drawn blade must follow: a blade placed on a computed arc does not.
func _swing(delta: float) -> void:
	if _swing_left <= 0.0:
		return
	_swing_left = maxf(_swing_left - delta, 0.0)
	var k := 1.0 - _swing_left / SWING_TIME
	var hand := _sockets.get(&"saber_r") as Node3D
	if hand == null:
		return
	hand.rotation = Vector3(deg_to_rad(lerpf(-SWING_DEG * 0.5, SWING_DEG * 0.5, k)), 0.0,
			deg_to_rad(lerpf(40.0, -40.0, k)))
	hand.position = SOCKET_REST + Vector3(lerpf(3.0, -3.0, k), sin(k * PI) * 2.0, lerpf(-5.0, 5.0, k))


func set_locomotion(state: StringName, _speed: float, _input_local: Vector2) -> void:
	locomotion = state


func play_action(id: StringName, _blend: float = 0.08) -> float:
	actions.append(id)
	_swing_left = SWING_TIME
	return SWING_TIME


func set_aim(_point: Vector3, _weight: float) -> void:
	pass


func socket(socket_name: StringName) -> Node3D:
	return _sockets.get(socket_name) as Node3D


func set_thrusters(_level: float) -> void:
	pass


func set_wings(_open: float) -> void:
	pass


func set_overdrive(_on: bool) -> void:
	pass


## HeroModel API (CONTRACTS §5): the hilt moves between the hip and the hand.
func set_saber_drawn(on: bool) -> void:
	saber_drawn = on


## hero-v3 duck type: the model carries a modelled blade on `R_Hand`, so nothing else may draw one.
func has_own_blade() -> bool:
	return own_blade


## How much steel the model carries — the saber's energy extension makes up the rest.
func blade_length() -> float:
	return MeleeTable.MODEL_BLADE_LENGTH


## HeroModel.paused(): true while this actor's own local hit-stop is running.
func paused() -> bool:
	return pause_left > 0.0


func hit_pause(seconds: float) -> void:
	pause_left = maxf(pause_left, seconds)


func played(id: StringName) -> bool:
	return actions.has(id)


func clear() -> void:
	actions.clear()
