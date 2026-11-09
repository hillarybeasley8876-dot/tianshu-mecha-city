class_name PlaceholderRig
extends Node3D
## Builds the 16 m blocky hero mech out of primitives and exposes the nodes the animation layer drives.
## Feet at y = 0, crest at y = 16 (CONTRACTS §2). Hero colours: white armour, cobalt panels, amber
## trim, cyan optics and thrusters.

const WHITE := Color("e9edf2")
const COBALT := Color("1f4fc8")
const AMBER := Color("f2a33a")
const CYAN := Color("4fe6ff")
const DARK := Color("2a3040")

var rig: Node3D
var hips: Node3D
var chest: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var fore_l: Node3D
var fore_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var shin_l: Node3D
var shin_r: Node3D
var wing_l: Node3D
var wing_r: Node3D
var backpack: Node3D
var thrusters: Array[MeshInstance3D] = []
var glow_material: StandardMaterial3D

var _sockets: Dictionary = {}


func build() -> void:
	glow_material = _mat(CYAN, 2.5)
	# 12.37 puts the soles on y = 0 (CONTRACTS: model origin between the feet) and the crest at 15.2 m.
	rig = _pivot(self, "Rig", Vector3(0.0, 12.37, 0.0))
	hips = _pivot(rig, "Hips", Vector3(0.0, -4.6, 0.0))
	_box(hips, "Waist", Vector3(3.4, 1.4, 2.4), Vector3(0.0, 0.7, 0.0), COBALT)
	_legs()
	chest = _pivot(hips, "Chest", Vector3(0.0, 1.4, 0.0))
	_box(chest, "Torso", Vector3(4.6, 4.0, 2.8), Vector3(0.0, 2.0, 0.0), WHITE)
	_box(chest, "Collar", Vector3(5.4, 0.9, 3.0), Vector3(0.0, 3.6, 0.0), COBALT)
	_box(chest, "Vent", Vector3(2.2, 1.2, 0.4), Vector3(0.0, 1.6, 1.5), AMBER)
	_socket(chest, &"chest", Vector3(0.0, 2.2, 1.4))
	head = _pivot(chest, "Head", Vector3(0.0, 4.2, 0.0))
	_box(head, "Skull", Vector3(2.0, 1.6, 2.2), Vector3.ZERO, WHITE)
	_box(head, "Visor", Vector3(1.7, 0.55, 0.3), Vector3(0.0, 0.1, -1.1), CYAN, 2.2)
	_box(head, "Crest", Vector3(0.35, 1.3, 2.6), Vector3(0.0, 1.2, 0.1), AMBER)
	# Pilot eye 12 m above the feet (CONTRACTS §5 / SPEC §2), just under the skull: camera-aim's
	# first-person view starts here and must not need its 11.5 m clamp.
	_socket(head, &"cockpit", Vector3(0.0, -1.37, -1.0))
	_arms()
	_backpack()


func _legs() -> void:
	leg_l = _pivot(hips, "LegL", Vector3(-1.3, 0.0, 0.0))
	leg_r = _pivot(hips, "LegR", Vector3(1.3, 0.0, 0.0))
	shin_l = _leg(leg_l)
	shin_r = _leg(leg_r)


func _leg(hip: Node3D) -> Node3D:
	_box(hip, "Thigh", Vector3(1.7, 3.4, 1.9), Vector3(0.0, -1.7, 0.0), COBALT)
	var knee := _pivot(hip, "Knee", Vector3(0.0, -3.5, 0.0))
	_box(knee, "Shin", Vector3(1.5, 3.4, 1.7), Vector3(0.0, -1.7, 0.0), WHITE)
	_box(knee, "Foot", Vector3(1.9, 0.9, 3.2), Vector3(0.0, -3.8, -0.5), AMBER)
	_thruster(_pivot(knee, "Calf", Vector3(0.0, -1.0, 1.0)))
	return knee


func _arms() -> void:
	arm_l = _pivot(chest, "ShoulderL", Vector3(-3.0, 3.3, 0.0))
	arm_r = _pivot(chest, "ShoulderR", Vector3(3.0, 3.3, 0.0))
	for pair: Array in [[arm_l, -1.0], [arm_r, 1.0]]:
		var sh: Node3D = pair[0]
		var s: float = pair[1]
		_box(sh, "Pauldron", Vector3(2.0, 2.0, 2.4), Vector3(s * 0.6, 0.2, 0.0), COBALT)
		_box(sh, "UpperArm", Vector3(1.3, 2.6, 1.4), Vector3(s * 0.8, -1.6, 0.0), DARK)
		var elbow := _pivot(sh, "Elbow", Vector3(s * 0.8, -3.0, 0.0))
		_box(elbow, "Forearm", Vector3(1.4, 2.6, 1.5), Vector3(0.0, -1.2, 0.0), WHITE)
		if s < 0.0:
			fore_l = elbow
		else:
			fore_r = elbow
	_box(fore_l, "Shield", Vector3(0.6, 4.4, 3.4), Vector3(-1.1, -1.4, 0.0), COBALT)
	_box(fore_l, "ShieldTrim", Vector3(0.7, 0.5, 3.5), Vector3(-1.2, 0.4, 0.0), AMBER)
	_socket(fore_l, &"shield_l", Vector3(-1.6, -1.4, 0.0))
	_socket(fore_l, &"hand_l", Vector3(0.0, -2.7, 0.0))
	_rifle()
	_socket(fore_r, &"hand_r", Vector3(0.0, -2.7, 0.0))
	_socket(fore_r, &"saber_r", Vector3(0.0, -2.9, 0.6))


func _rifle() -> void:
	var gun := _pivot(fore_r, "Rifle", Vector3(0.0, -2.6, -0.4))
	_box(gun, "Body", Vector3(1.0, 1.2, 5.6), Vector3.ZERO, DARK)
	_box(gun, "Barrel", Vector3(0.6, 0.6, 2.6), Vector3(0.0, 0.2, -4.0), WHITE)
	_box(gun, "Sight", Vector3(0.5, 0.7, 1.2), Vector3(0.0, 0.9, 0.6), CYAN, 2.0)
	_socket(gun, &"muzzle_r", Vector3(0.0, 0.2, -5.6))


func _backpack() -> void:
	backpack = _pivot(chest, "Backpack", Vector3(0.0, 2.4, 1.9))
	_box(backpack, "Pack", Vector3(4.0, 3.4, 1.6), Vector3.ZERO, DARK)
	_socket(backpack, &"back", Vector3(0.0, 0.0, 0.9))
	_socket(backpack, &"missile_l", Vector3(-1.6, 1.9, 0.2))
	_socket(backpack, &"missile_r", Vector3(1.6, 1.9, 0.2))
	for s: float in [-1.0, 1.0]:
		var nozzle := _pivot(backpack, "Nozzle", Vector3(s * 1.2, -2.0, 0.2))
		_box(nozzle, "Cone", Vector3(1.1, 1.4, 1.1), Vector3.ZERO, DARK)
		_thruster(nozzle)
	wing_l = _pivot(backpack, "wing_l", Vector3(-1.9, 0.6, 0.4))
	wing_r = _pivot(backpack, "wing_r", Vector3(1.9, 0.6, 0.4))
	for pair: Array in [[wing_l, -1.0], [wing_r, 1.0]]:
		var w: Node3D = pair[0]
		var s: float = pair[1]
		_box(w, "Plate", Vector3(0.4, 1.0, 5.2), Vector3(s * 0.4, 0.0, 2.6), WHITE)
		_box(w, "Edge", Vector3(0.5, 0.35, 5.3), Vector3(s * 0.45, 0.55, 2.6), CYAN, 1.6)
	_sockets[&"wing_l"] = wing_l
	_sockets[&"wing_r"] = wing_r


func socket(name: StringName) -> Node3D:
	return _sockets.get(name) as Node3D


# --- primitive helpers ---------------------------------------------------------------------------

func _pivot(parent: Node3D, node_name: String, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = at
	parent.add_child(n)
	return n


func _box(parent: Node3D, node_name: String, size: Vector3, at: Vector3, color: Color,
		emission: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = at
	mi.material_override = _mat(color, emission)
	parent.add_child(mi)
	return mi


func _thruster(parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Flame"
	var mesh := SphereMesh.new()
	mesh.radius = 0.45
	mesh.height = 1.2
	mi.mesh = mesh
	mi.position = Vector3(0.0, -0.9, 0.0)
	mi.material_override = glow_material
	parent.add_child(mi)
	thrusters.append(mi)


func _socket(parent: Node3D, socket_name: StringName, at: Vector3) -> void:
	var m := Marker3D.new()
	m.name = String(socket_name)
	m.position = at
	parent.add_child(m)
	_sockets[socket_name] = m


func _mat(color: Color, emission: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.55
	m.metallic = 0.25
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m
