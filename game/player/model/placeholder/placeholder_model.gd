extends Node3D
## Placeholder HeroModel (CONTRACTS §5). Same API as `player/model/hero/hero_model.tscn` so every other
## unit can be built and captured before hero-asset lands; motion is procedural (leg swing by speed,
## lean into acceleration, tuck in the air, dash/landing crouch, thruster glow, wings by `set_wings`).
## Feet at y = 0, crest at y = 16.

const ACTION_LENGTH: Dictionary = {
	&"dash_f": 0.30, &"dash_b": 0.30, &"dash_l": 0.30, &"dash_r": 0.30, &"jump": 0.40,
	&"fire_r": 0.18, &"charge_r": 0.60, &"melee_l1": 0.48, &"melee_l2": 0.47, &"melee_l3": 0.80,
	&"lunge": 0.70, &"charge_slash": 0.80, &"guard_up": 0.25, &"parry": 0.30, &"hit_light": 0.30,
	&"hit_heavy": 0.50, &"stagger": 0.60, &"overdrive_ignite": 1.00, &"plunge_dive": 0.60,
}
const DEFAULT_ACTION := 0.35
const GROUNDED_WALK: Array[StringName] = [&"idle", &"walk", &"run", &"coast"]
const AIRBORNE: Array[StringName] = [&"jump", &"fall", &"hover", &"fly", &"glide"]

var _rig: PlaceholderRig
var _state: StringName = &"idle"
var _speed: float = 0.0
var _local_in: Vector2 = Vector2.ZERO
var _thruster: float = 0.0
var _wings: float = 0.0
var _aim_point: Vector3 = Vector3.ZERO
var _aim_weight: float = 0.0
var _overdrive: bool = false
var _phase: float = 0.0
var _pause: float = 0.0
var _action: StringName = &""
var _action_t: float = 99.0
var _action_len: float = 0.0
var _base_y: float = 0.0


func _ready() -> void:
	_rig = PlaceholderRig.new()
	_rig.name = "Geometry"
	add_child(_rig)
	_rig.build()
	_base_y = _rig.rig.position.y


# --- HeroModel API -------------------------------------------------------------------------------

func set_locomotion(state: StringName, speed: float, input_local: Vector2) -> void:
	_state = state
	_speed = speed
	_local_in = input_local


func play_action(id: StringName, _blend: float = 0.08) -> float:
	_action = id
	_action_t = 0.0
	_action_len = float(ACTION_LENGTH.get(id, DEFAULT_ACTION))
	return _action_len


func set_aim(point: Vector3, weight: float) -> void:
	_aim_point = point
	_aim_weight = clampf(weight, 0.0, 1.0)


func socket(socket_name: StringName) -> Node3D:
	return _rig.socket(socket_name)


func set_thrusters(level: float) -> void:
	_thruster = clampf(level, 0.0, 1.0)


func set_wings(open: float) -> void:
	_wings = clampf(open, 0.0, 1.0)


func set_overdrive(on: bool) -> void:
	_overdrive = on


func hit_pause(seconds: float) -> void:
	_pause = maxf(_pause, seconds)


# --- procedural motion ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _pause > 0.0:
		_pause = maxf(_pause - delta, 0.0)
		return
	_action_t += delta
	_phase = fmod(_phase + delta * _gait_rate(), TAU)
	_pose(1.0 - exp(-11.0 * delta), delta)


## One full stride per 1.1 s at run speed (SPEC §4: a footstep every 0.55 s = two steps per cycle).
func _gait_rate() -> float:
	if not GROUNDED_WALK.has(_state):
		return 1.2
	return clampf(_speed, 0.0, 40.0) * 0.204


func _pose(k: float, delta: float) -> void:
	var run := clampf(_speed / 28.0, 0.0, 1.5)
	var walking := GROUNDED_WALK.has(_state)
	var air := AIRBORNE.has(_state)
	var swing := sin(_phase) * 0.5 * run if walking else 0.0
	var bend := maxf(sin(_phase + PI * 0.5), 0.0) * 0.7 * run if walking else 0.0
	var tuck := 1.0 if air else 0.0
	var flinch := _action_pulse(&"hit_light", 0.35) + _action_pulse(&"hit_heavy", 0.6)

	_rig.rig.rotation.x = lerpf(_rig.rig.rotation.x, _lean(run) + flinch, k)
	_rig.rig.rotation.z = lerpf(_rig.rig.rotation.z, -_local_in.x * 0.22, k)
	_rig.rig.rotation.y = lerpf(_rig.rig.rotation.y, _aim_yaw() * 0.5, k)
	_rig.rig.position.y = lerpf(_rig.rig.position.y, _base_y - _crouch() * 1.2, k)

	_leg(_rig.leg_l, _rig.shin_l, swing, bend, tuck, k)
	_leg(_rig.leg_r, _rig.shin_r, -swing, bend, tuck, k)
	_arms(run, swing, k, delta)
	_wing_pose(k)
	_thruster_pose(k)


func _lean(run: float) -> float:
	match _state:
		&"slide", &"glide": return 0.30
		&"assault": return 0.38
		&"dash_f", &"dash_b", &"dash_l", &"dash_r": return 0.26
		&"hover", &"fly": return 0.20
		&"land_heavy": return 0.10
		_: return 0.05 + run * 0.10


func _crouch() -> float:
	match _state:
		&"land_heavy": return 1.0
		&"land_light": return 0.45
		&"dash_f", &"dash_b", &"dash_l", &"dash_r": return 0.5
		&"slide", &"glide", &"assault": return 0.3
		&"hover", &"fly": return 0.25
		_: return 0.0


func _leg(hip: Node3D, knee: Node3D, swing: float, bend: float, tuck: float, k: float) -> void:
	var thigh := lerpf(swing, -0.55, tuck)
	hip.rotation.x = lerpf(hip.rotation.x, thigh, k)
	hip.rotation.z = lerpf(hip.rotation.z, 0.06 * signf(hip.position.x), k)
	knee.rotation.x = lerpf(knee.rotation.x, lerpf(bend, 0.95, tuck), k)


func _arms(run: float, swing: float, k: float, _delta: float) -> void:
	var aim := _aim_weight
	var recoil := _action_pulse(&"fire_r", 1.0) * 0.5 + _action_pulse(&"charge_r", 1.0) * 0.2
	var slash := _action_pulse(&"melee_l1", 1.0) + _action_pulse(&"melee_l2", 1.0)
	var guard := _action_pulse(&"guard_up", 1.0) + _action_pulse(&"parry", 1.0)
	_rig.arm_r.rotation.x = lerpf(_rig.arm_r.rotation.x, -1.15 * aim - recoil - slash * 1.4 + swing * 0.3, k)
	_rig.arm_r.rotation.z = lerpf(_rig.arm_r.rotation.z, -0.18, k)
	_rig.arm_l.rotation.x = lerpf(_rig.arm_l.rotation.x, -0.55 * guard - 0.25 * aim - swing * 0.3, k)
	_rig.arm_l.rotation.z = lerpf(_rig.arm_l.rotation.z, 0.30 + 0.25 * guard, k)
	if run > 0.1:
		_rig.arm_l.rotation.x = lerpf(_rig.arm_l.rotation.x, -swing * 0.4, k * 0.5)


func _wing_pose(k: float) -> void:
	var spread := 0.12 + _wings * 0.85
	_rig.wing_l.rotation.y = lerpf(_rig.wing_l.rotation.y, -spread, k)
	_rig.wing_r.rotation.y = lerpf(_rig.wing_r.rotation.y, spread, k)
	_rig.wing_l.rotation.x = lerpf(_rig.wing_l.rotation.x, -_wings * 0.25, k)
	_rig.wing_r.rotation.x = lerpf(_rig.wing_r.rotation.x, -_wings * 0.25, k)


func _thruster_pose(k: float) -> void:
	var level := _thruster
	_rig.glow_material.emission = PlaceholderRig.AMBER if _overdrive else PlaceholderRig.CYAN
	_rig.glow_material.emission_energy_multiplier = lerpf(
			_rig.glow_material.emission_energy_multiplier, 0.4 + level * 5.0, k)
	for t in _rig.thrusters:
		t.scale = Vector3.ONE * (0.35 + level * 1.4)
		t.scale.y = 0.35 + level * 3.2
		t.visible = level > 0.02


## 0..1 envelope of the running action clip, used to add a one-shot pose offset.
func _action_pulse(id: StringName, scale: float) -> float:
	if _action != id or _action_t >= _action_len:
		return 0.0
	var u := _action_t / maxf(_action_len, 0.001)
	return sin(u * PI) * scale


func _aim_yaw() -> float:
	if _aim_weight <= 0.01:
		return 0.0
	var local := global_transform.affine_inverse() * _aim_point
	return clampf(atan2(local.x, -local.z), -1.2, 1.2) * _aim_weight
