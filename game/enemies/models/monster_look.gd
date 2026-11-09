class_name MonsterLook
extends RefCounted
## The shared body material for every HUSK monster (monster-assets): one ShaderMaterial per type,
## built from the Tripo PBR textures the GLB carries, with the per-type look numbers from
## `<type>_rig.json` on top (`blender/monsters/mon_types.LOOK`).
##
## Split out of `monster_model.gd` (lead split r1). `HiveModel` shares this too — same shader, same
## table, one extra pod-mask texture.

const SHADER: Shader = preload("res://enemies/models/monster_body.gdshader")

## Static per-type material cache: instance uniforms make one material enough for every copy, so
## all 40 rippers on screen share this one.
static var _materials: Dictionary = {}

## The look keys the rig data carries, in the order the shader declares them.
const LOOK_KEYS: Array[String] = ["albedo_gain", "metallic_cap", "roughness_floor", "rim_gain",
		"emission_energy", "pod_boost", "flash_energy", "tell_energy"]


## One ShaderMaterial per type. `meshes` is only read to find the GLB's own surface material to
## build from, so an already-cached type costs nothing.
static func shared(body_type: StringName, rig: Dictionary,
		meshes: Array[MeshInstance3D]) -> ShaderMaterial:
	if _materials.has(body_type):
		return _materials[body_type]
	var source := _source(body_type, meshes)
	if source == null:
		push_error("MonsterModel(%s): the GLB has no surface material to build from" % body_type)
		return null
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"albedo_tex", source.albedo_texture)
	material.set_shader_parameter(&"orm_tex", source.roughness_texture)
	material.set_shader_parameter(&"normal_tex", source.normal_texture)
	material.set_shader_parameter(&"emission_tex", source.emission_texture)
	material.set_shader_parameter(&"emission_energy", source.emission_energy_multiplier)
	material.set_shader_parameter(&"normal_depth", source.normal_scale)
	apply(material, rig.get("look", {}) as Dictionary)
	for slot: StringName in [&"albedo_tex", &"orm_tex", &"normal_tex", &"emission_tex"]:
		if material.get_shader_parameter(slot) == null:
			push_warning("MonsterModel(%s): %s is missing from the GLB material" % [body_type, slot])
	_materials[body_type] = material
	return material


## The per-type look numbers from `<type>_rig.json` (written by blender/monsters/mon_types.LOOK):
## the albedo grade measured against ART.md's #1B2430 chitin, the metallic/roughness clamp that
## stops the carapace reflecting the warm dusk sky, the vein energy and the rim. `pod_mask_path` is
## the hive's per-bulb glow mask; every other type passes nothing.
static func apply(material: ShaderMaterial, look: Dictionary, pod_mask_path: String = "") -> void:
	if material == null:
		return
	if look.is_empty():
		push_warning("MonsterModel: no 'look' block in the rig data — run blender/monsters/build_all.py")
		return
	for key: String in LOOK_KEYS:
		if look.has(key):
			material.set_shader_parameter(StringName(key), float(look[key]))
	var rim: Array = look.get("rim_color", []) as Array
	if rim.size() >= 3:
		material.set_shader_parameter(&"rim_color",
				Color(float(rim[0]), float(rim[1]), float(rim[2])))
	if pod_mask_path.is_empty():
		return
	var path := pod_mask_path
	if not ResourceLoader.exists(path):
		push_warning("MonsterModel: pod mask %s is missing — pods keep their built-in glow" % path)
		return
	material.set_shader_parameter(&"pod_mask_tex", load(path))


static func _source(body_type: StringName, meshes: Array[MeshInstance3D]) -> StandardMaterial3D:
	for mesh in meshes:
		if mesh.mesh == null or mesh.mesh.get_surface_count() == 0:
			continue
		var found := mesh.mesh.surface_get_material(0)
		if found is StandardMaterial3D:
			return found as StandardMaterial3D
		push_warning("MonsterModel(%s): surface material is %s, not StandardMaterial3D"
				% [body_type, found.get_class()])
	return null
