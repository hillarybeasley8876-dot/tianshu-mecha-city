class_name HiveModel
extends Node3D
## The hive spire objective (monster-assets): a static 60 m mesh with three damage states.
##
## The GLB carries all four meshes (`Hive`, `HiveCracked`, `HiveDestroyed`, `HiveCollision`) so the
## state swap is a visibility flip, not a load. `HiveCollision` is a convex hull kept hidden — the
## flow unit instances its shape into a StaticBody3D when it makes the spire solid.
##
## API: `set_state(state)`, `state()`, `socket(name)`, `set_hit_flash(v)`, `collision_mesh()`.
## `state` is `&"intact" | &"cracked" | &"destroyed"`.

const SHADER: Shader = preload("res://enemies/models/monster_body.gdshader")
## The cracked state dims the glow — the spire is failing, not dead yet.
const CRACKED_EMISSION := 0.45
const INTACT_EMISSION := 1.0
const DESTROYED_EMISSION := 0.12

static var _material: ShaderMaterial = null

@export var body_type: StringName = &"hive"

var rig: Dictionary = {}
var meshes: Dictionary = {}
var collision: MeshInstance3D

var _sockets: Dictionary = {}
var _state: StringName = &"intact"
var _flash: float = 0.0
## Per-pod glow switch (monster_body.gdshader `pod_alive`), one channel per `pod_*` socket.
var _pods: Vector4 = Vector4.ONE


func _ready() -> void:
	rig = _load_rig()
	_build()


func _load_rig() -> Dictionary:
	var path := "res://enemies/models/%s/%s_rig.json" % [body_type, body_type]
	if not FileAccess.file_exists(path):
		push_error("HiveModel: no rig data at %s — run blender/monsters/build_all.py" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _build() -> void:
	var packed := load("res://enemies/models/%s/%s.glb" % [body_type, body_type]) as PackedScene
	if packed == null:
		push_error("HiveModel: cannot load the hive GLB")
		return
	var root := packed.instantiate() as Node3D
	if root == null:
		push_error("HiveModel: the hive GLB root is not a Node3D")
		return
	root.name = "States"
	add_child(root)
	var states := rig.get("states", {}) as Dictionary
	var material := _shared_material(root)
	for state_name: String in states:
		var node := _find_named(root, String(states[state_name])) as MeshInstance3D
		if node == null:
			push_error("HiveModel: no mesh named '%s' in the GLB" % states[state_name])
			continue
		node.visible = false
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if material != null:
			node.material_override = material
		meshes[StringName(state_name)] = node
	collision = meshes.get(&"collision") as MeshInstance3D
	_setup_sockets()
	set_state(&"intact")


func _find_named(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null


func _shared_material(root: Node) -> ShaderMaterial:
	if _material != null:
		return _material
	var source := _find_named(root, "Hive") as MeshInstance3D
	if source == null or source.mesh == null or source.mesh.get_surface_count() == 0:
		push_error("HiveModel: no Hive mesh to take the material from")
		return null
	var found := source.mesh.surface_get_material(0)
	if not (found is StandardMaterial3D):
		push_error("HiveModel: the hive surface material is %s, not StandardMaterial3D"
				% (found.get_class() if found != null else "null"))
		return null
	var base := found as StandardMaterial3D
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"albedo_tex", base.albedo_texture)
	material.set_shader_parameter(&"orm_tex", base.roughness_texture)
	material.set_shader_parameter(&"normal_tex", base.normal_texture)
	material.set_shader_parameter(&"emission_tex", base.emission_texture)
	material.set_shader_parameter(&"emission_energy", base.emission_energy_multiplier)
	material.set_shader_parameter(&"normal_depth", base.normal_scale)
	MonsterModel.apply_look(material, rig.get("look", {}) as Dictionary,
			String(rig.get("pod_mask", "")))
	_material = material
	return material


## Damage state (SPEC §8: three Hive Spires, each destroyed in stages).
func set_state(state: StringName) -> void:
	if not meshes.has(state):
		push_warning("HiveModel: no state '%s'" % state)
		return
	_state = state
	for key: StringName in meshes:
		if key == &"collision":
			continue
		(meshes[key] as MeshInstance3D).visible = key == state
	var glow := INTACT_EMISSION
	if state == &"cracked":
		glow = CRACKED_EMISSION
	elif state == &"destroyed":
		glow = DESTROYED_EMISSION
	_push(&"emission_scale", glow)


func state() -> StringName:
	return _state


func collision_mesh() -> Mesh:
	return collision.mesh if collision != null else null


func set_hit_flash(v: float) -> void:
	_flash = clampf(v, 0.0, 1.0)
	_push(&"hit_flash", _flash)


## Light or kill one pod bulb, 0..3 (SPEC §8: the spire comes apart bulb by bulb). The bulb's veins
## go dark with it, so a burst pod stops reading as a target without flow having to hide a mesh.
func set_pod_alive(index: int, alive: bool) -> void:
	if index < 0 or index >= 4:
		push_warning("HiveModel: pod index %d out of range (0..3)" % index)
		return
	_pods[index] = 1.0 if alive else 0.0
	_push(&"pod_alive", _pods)


## How many of the four bulbs are still lit (flow's stage counter).
func pods_alive() -> int:
	var out := 0
	for i in 4:
		if _pods[i] > 0.5:
			out += 1
	return out


func socket(name: StringName) -> Node3D:
	var found: Node3D = _sockets.get(name)
	if found == null:
		push_warning("HiveModel: no socket '%s'" % name)
		return self
	return found


## Every glowing target on the spire, weakest-looking first by name: the `pod_*` bulbs flow puts
## its four Hurtboxes on, then the violet `weak_*` cores. Both are returned because flow reads this
## list to find its pod sockets (`hive_visual._model_pod_sockets` only sees what is in here).
func weak_points() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var names: Array = _sockets.keys()
	names.sort()
	for key: StringName in names:
		if String(key).begins_with("pod_"):
			out.append(_sockets[key] as Node3D)
	for key: StringName in names:
		if String(key).begins_with("weak_"):
			out.append(_sockets[key] as Node3D)
	return out


func _setup_sockets() -> void:
	var table := rig.get("sockets", {}) as Dictionary
	for socket_name: String in table:
		var entry := table[socket_name] as Dictionary
		var pos: Array = entry.get("pos", [0, 0, 0])
		if pos.size() < 3:
			push_warning("HiveModel: socket '%s' has no position" % socket_name)
			continue
		var marker := Marker3D.new()
		marker.name = socket_name
		marker.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		add_child(marker)
		_sockets[StringName(socket_name)] = marker


func _push(parameter: StringName, value: Variant) -> void:
	for key: StringName in meshes:
		if key == &"collision":
			continue
		(meshes[key] as MeshInstance3D).set_instance_shader_parameter(parameter, value)


## Measured height, for the test and for the flow unit's objective marker.
func measured_size() -> float:
	var node := meshes.get(&"intact") as MeshInstance3D
	return node.mesh.get_aabb().size.y if node != null and node.mesh != null else 0.0


func target_size() -> float:
	return float((rig.get("size", {}) as Dictionary).get("target", 0.0))

