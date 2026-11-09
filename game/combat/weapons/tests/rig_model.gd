class_name RigModel
extends Node3D
## Placeholder hero model for the weapons range (tests/demo only): a 16 m grey-box mech with the
## sockets the weapon component asks for, implementing the HeroModel API surface it uses. The real
## model comes from the hero-asset unit; this exists so captures show shots leaving a muzzle instead
## of a bare chest, and so the socket code path is exercised.

const SOCKETS: Array[StringName] = [&"muzzle_r", &"hand_r", &"hand_l", &"missile_l", &"missile_r",
		&"cockpit", &"chest", &"back", &"shield_l", &"saber_r", &"wing_l", &"wing_r"]

var last_action: StringName = &""

var _sockets: Dictionary = {}


func _ready() -> void:
	var hull := _material(Color(0.46, 0.49, 0.54), 0.25, 0.45)
	var dark := _material(Color(0.30, 0.32, 0.36), 0.3, 0.55)
	var trim := _material(Color(0.15, 0.75, 0.95), 0.2, 0.2, Color(0.21, 0.89, 1.0), 2.2)
	_box("leg_l", Vector3(-2.6, 4.0, 0.0), Vector3(3.4, 8.0, 4.0), dark)
	_box("leg_r", Vector3(2.6, 4.0, 0.0), Vector3(3.4, 8.0, 4.0), dark)
	_box("hips", Vector3(0.0, 8.6, 0.0), Vector3(9.0, 2.4, 5.4), dark)
	_box("torso", Vector3(0.0, 12.4, 0.0), Vector3(8.4, 6.4, 6.0), hull)
	_box("chest_vent", Vector3(0.0, 12.6, -3.1), Vector3(4.0, 2.4, 0.5), trim)
	_box("head", Vector3(0.0, 16.4, -0.6), Vector3(3.6, 2.8, 4.0), hull)
	_box("eye", Vector3(0.0, 16.6, -2.7), Vector3(2.8, 0.9, 0.4), trim)
	_box("arm_l", Vector3(-5.6, 12.0, 0.0), Vector3(2.6, 6.4, 2.8), hull)
	_box("arm_r", Vector3(4.8, 12.8, 0.0), Vector3(2.6, 6.4, 2.8), hull)
	_box("pod_l", Vector3(-6.2, 15.4, -1.0), Vector3(3.6, 2.6, 5.0), dark)
	_box("pod_r", Vector3(6.2, 15.4, -1.0), Vector3(3.6, 2.6, 5.0), dark)
	_box("backpack", Vector3(0.0, 13.6, 4.2), Vector3(7.0, 5.4, 2.8), dark)
	# The gun is held at chest height close to the body: `muzzle_r` has to sit ~6 m from the cockpit
	# lens (camera-aim r7 measured 6.0 m on the real hero, `rig_probe --probe-dump-at`), or the
	# first-person near-lens gate in `suite_fp_near.gd` would measure a muzzle 12 m away and pass
	# vacuously. `fp_near.lens_is_about_6m_from_the_muzzle` pins the relationship.
	_box("rifle", Vector3(3.6, 13.2, -2.4), Vector3(1.8, 1.8, 8.0), hull)
	_box("rifle_coil", Vector3(3.6, 13.2, -5.4), Vector3(2.4, 2.4, 1.6), trim)
	_socket(&"muzzle_r", Vector3(3.6, 13.2, -6.4))
	_socket(&"hand_r", Vector3(3.6, 13.2, 0.4))
	_socket(&"hand_l", Vector3(-5.6, 11.0, -1.6))
	_socket(&"missile_l", Vector3(-6.2, 16.8, -1.0))
	_socket(&"missile_r", Vector3(6.2, 16.8, -1.0))
	_socket(&"cockpit", Vector3(0.0, 16.4, -1.8))
	_socket(&"chest", Vector3(0.0, 12.4, 0.0))
	_socket(&"back", Vector3(0.0, 13.6, 5.8))


func _material(albedo: Color, metallic: float, roughness: float, emission: Color = Color.BLACK,
		energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


func _box(nm: String, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _socket(nm: StringName, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = String(nm)
	m.position = pos
	add_child(m)
	_sockets[nm] = m


# --- HeroModel API (CONTRACTS §5) --------------------------------------------------------------
func socket(nm: StringName) -> Node3D:
	return _sockets.get(nm, null) as Node3D


func play_action(id: StringName, _blend: float = 0.08) -> float:
	last_action = id
	return 0.0


func set_locomotion(_state: StringName, _speed: float, _input_local: Vector2) -> void:
	pass


func set_aim(_point: Vector3, _weight: float) -> void:
	pass


func set_thrusters(_level: float) -> void:
	pass


func set_wings(_open: float) -> void:
	pass


func set_overdrive(_on: bool) -> void:
	pass


func hit_pause(_seconds: float) -> void:
	pass
