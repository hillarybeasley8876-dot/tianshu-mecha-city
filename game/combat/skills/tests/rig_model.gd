class_name SkillRigModel
extends Node3D
## HeroModel stand-in (CONTRACTS §5): real socket nodes so the fins can hide and re-show the docked
## wing blades, and counters so the tests can assert which actions the skills asked for.
##
## The sockets are EXACTLY the CONTRACTS §5 names and nothing else: `socket()` reports a name it does
## not have instead of inventing a node, so a skill that asks for a socket the contract does not
## publish fails a test rather than silently firing its cable out of the hero's chest (r4 item 5).
##
## The drone API mirrors hero-v3's shipped one (`hero3_model.gd:222-246`): bit `i` SET means
## `Drone_{i+1}` is DEPLOYED and its blade on the back is hidden; 0 shows all seven.

## CONTRACTS §5 HeroModel socket names. `missile_l` / `missile_r` are in the table; `muzzle_l` is not
## in it, and neither is any other name — asking for one is a bug in the caller.
const SOCKETS: Array[StringName] = [&"muzzle_r", &"hand_r", &"hand_l", &"shield_l", &"saber_r",
		&"back", &"wing_l", &"wing_r", &"missile_l", &"missile_r", &"cockpit", &"chest"]
const DRONES := 7              ## `Drone_1..7`, matching Hero3Rig.DRONE_BONES

var actions: Array[StringName] = []
var overdrive_on: bool = false
var thrusters: float = 0.0
var bad_sockets: PackedStringArray = PackedStringArray()

var _sockets: Dictionary = {}
var _drones: Array[MeshInstance3D] = []
var _mask: int = 0


func _ready() -> void:
	for nm: StringName in SOCKETS:
		var n := Node3D.new()
		n.name = String(nm)
		add_child(n)
		_sockets[nm] = n
	_place_sockets()
	_build_drones()


## Sockets where the 16 m hero actually carries them (CONTRACTS §5): the wings on the back at 12 m,
## not at the model's feet, so the fins launch from the mech's shoulders and the Skyhook fires from
## its left arm rather than from the ground between its boots.
const SOCKET_AT := {
	&"chest": Vector3(0.0, 11.0, 0.0), &"cockpit": Vector3(0.0, 15.0, -1.2),
	&"head": Vector3(0.0, 15.0, 0.0), &"back": Vector3(0.0, 12.0, 2.4),
	&"wing_l": Vector3(-3.0, 12.2, 2.0), &"wing_r": Vector3(3.0, 12.2, 2.0),
	&"hand_l": Vector3(-4.4, 7.6, -0.6), &"hand_r": Vector3(4.4, 7.6, -0.6),
	&"muzzle_r": Vector3(4.4, 8.4, -2.2),
	&"saber_r": Vector3(4.4, 7.0, -1.0), &"shield_l": Vector3(-4.6, 9.0, -1.0),
	&"missile_l": Vector3(-2.6, 13.4, 1.2), &"missile_r": Vector3(2.6, 13.4, 1.2),
}


func _place_sockets() -> void:
	for nm: StringName in SOCKETS:
		if SOCKET_AT.has(nm):
			(_sockets[nm] as Node3D).position = SOCKET_AT[nm]


## The seven blades, mounted where the hero carries them: `Drone_1..4` on `wing_l`, `Drone_5..7` on
## `wing_r` (Hero3Rig.DRONE_BONES / Hero3Sockets). One MeshInstance3D each, so the mask has something
## real to hide — which is exactly what the skinned Hero3 cannot offer.
func _build_drones() -> void:
	for i in DRONES:
		var blade := MeshInstance3D.new()
		blade.name = "Drone_%d" % (i + 1)
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 0.35, 6.4)
		blade.mesh = bm
		blade.material_override = SkillFx.glow(Color(0.35, 0.92, 1.0), 1.8)
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		blade.position = Vector3(float(i % 4) * 1.1 - 1.6, 0.0, 2.4)
		socket(&"wing_l" if i < 4 else &"wing_r").add_child(blade)
		_drones.append(blade)


## A name the contract does not publish is a caller bug: record it and return null rather than
## conjuring a node, so `SkillInputSuite._contract_sockets` fails on it. A WARNING, not an error: the
## stricter test host fails a suite on any logged error, and the assertion that matters is the
## `bad_sockets` one — a `push_error` here would make every run depend on tooling's allow-list.
func socket(nm: StringName) -> Node3D:
	if not _sockets.has(nm):
		bad_sockets.append(String(nm))
		push_warning("SkillRigModel: no CONTRACTS §5 socket named %s" % nm)
		return null
	return _sockets[nm] as Node3D


# --- drone API (hero-v3's shipped semantics) ------------------------------------------------------

## Bit `i` set = `Drone_{i+1}` deployed, its blade on the back hidden. Absolute: 0 shows all seven.
func set_drones_docked(mask: int) -> void:
	_mask = mask
	for i in _drones.size():
		_drones[i].visible = (mask & (1 << i)) == 0


func drones_docked() -> int:
	return _mask


func set_drone_deployed(index: int, deployed: bool) -> void:
	if index < 0 or index >= _drones.size():
		push_error("SkillRigModel: no drone at index %d" % index)
		return
	set_drones_docked((_mask | (1 << index)) if deployed else (_mask & ~(1 << index)))


func drone_deployed(index: int) -> bool:
	return index >= 0 and index < _drones.size() and (_mask & (1 << index)) != 0


func drone_tip(index: int) -> Vector3:
	if index < 0 or index >= _drones.size():
		return global_position
	return _drones[index].global_position


# --- the rest of the HeroModel contract -----------------------------------------------------------

func play_action(id: StringName, _blend: float = 0.08) -> float:
	actions.append(id)
	return 0.3


func last_action() -> StringName:
	return actions[-1] if not actions.is_empty() else &""


func played(id: StringName) -> bool:
	return actions.has(id)


func set_locomotion(_state: StringName, _speed: float, _input_local: Vector2) -> void:
	pass


func set_aim(_point: Vector3, _weight: float) -> void:
	pass


func set_thrusters(level: float) -> void:
	thrusters = level


func set_wings(_open: float) -> void:
	pass


func set_overdrive(on: bool) -> void:
	overdrive_on = on


func hit_pause(_s: float) -> void:
	pass


## Is any docked wing blade still visible? (False while every fin that owns one is airborne.)
func wings_docked_visible() -> bool:
	for blade in _drones:
		if blade.visible:
			return true
	return false


## How many of the seven blades are hidden right now.
func drones_hidden() -> int:
	var n := 0
	for blade in _drones:
		if not blade.visible:
			n += 1
	return n


# --- capture body ------------------------------------------------------------------------------

## A grey-box 16 m mech so the captures have a hero to read against (the real HeroModel is the
## hero-asset unit's). Built once, under the model node, which PlayerMech places 7.5 m below the body
## origin so the feet land on the ground (CONTRACTS §5). The wing blades come from `_build_drones`.
func build_body() -> void:
	var hull := _mat(Color(0.34, 0.36, 0.40), 0.55, 0.5)
	var trim := _mat(Color(0.16, 0.17, 0.20), 0.4, 0.7)
	_part("Torso", Vector3(5.2, 6.4, 4.4), Vector3(0.0, 11.0, 0.0), hull)
	_part("Hips", Vector3(4.4, 2.6, 3.6), Vector3(0.0, 7.4, 0.0), trim)
	_part("Head", Vector3(2.2, 1.8, 2.2), Vector3(0.0, 15.0, -0.4), trim)
	_part("Cockpit", Vector3(1.5, 0.7, 0.4), Vector3(0.0, 15.0, -1.6), SkillFx.glow(
			Color(0.45, 0.95, 1.0), 2.6))
	for side in [-1.0, 1.0]:
		_part("Arm%s" % side, Vector3(1.8, 5.6, 1.8), Vector3(side * 3.6, 10.4, 0.0), hull)
		_part("Thigh%s" % side, Vector3(2.2, 4.0, 2.4), Vector3(side * 1.6, 4.4, 0.0), hull)
		_part("Shin%s" % side, Vector3(1.8, 3.6, 2.0), Vector3(side * 1.6, 1.6, 0.2), trim)
		_part("Foot%s" % side, Vector3(2.4, 1.0, 4.2), Vector3(side * 1.6, 0.5, -0.6), trim)


func _part(part_name: String, size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = at
	add_child(mi)


func _mat(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m
