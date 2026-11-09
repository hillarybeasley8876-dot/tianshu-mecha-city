class_name MonsterAssembly
extends RefCounted
## The GLB half of `MonsterModel` (monster-assets): instantiate the exported body under a `Visual`
## node, find its skeleton and animation player, collect the skinned meshes and give them the shared
## material, the per-type shadow setting and the LOD visibility ranges.
##
## Split out of `monster_model.gd` (lead split r1). Nothing here knows about clips or sockets.

var visual: Node3D
var skeleton: Skeleton3D
var animation: AnimationPlayer
var meshes: Array[MeshInstance3D] = []

var _body_type: StringName = &""
var _rig: Dictionary = {}


## Build the body under `host`. A failed load leaves `skeleton`/`animation` null and `meshes` empty;
## the caller warns once and carries on, exactly as the single-file version did.
func build(host: Node3D, body_type: StringName, rig: Dictionary) -> void:
	_body_type = body_type
	_rig = rig
	visual = Node3D.new()
	visual.name = "Visual"
	host.add_child(visual)
	var path := "res://enemies/models/%s/%s.glb" % [body_type, body_type]
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("MonsterModel(%s): cannot load %s" % [body_type, path])
		return
	var instanced := packed.instantiate() as Node3D
	if instanced == null:
		push_error("MonsterModel(%s): %s root is not a Node3D" % [body_type, path])
		return
	instanced.name = "Body"
	if rig.get("scale", 1.0) is float and not is_equal_approx(float(rig.get("scale", 1.0)), 1.0):
		# the skyline titan is the fight model at x1.5 (90 m, lead note)
		instanced.scale = Vector3.ONE * float(rig["scale"])
	visual.add_child(instanced)
	skeleton = _find(instanced, "Skeleton3D") as Skeleton3D
	animation = _find(instanced, "AnimationPlayer") as AnimationPlayer
	_setup_meshes(instanced)


func _find(node: Node, klass: String) -> Node:
	if node.is_class(klass):
		return node
	for child in node.get_children():
		var found := _find(child, klass)
		if found != null:
			return found
	return null


func _setup_meshes(root: Node) -> void:
	_collect_meshes(root)
	var shadow := bool(_rig.get("shadow", false))
	var material := MonsterLook.shared(_body_type, _rig, meshes)
	var lod_distance := float(_rig.get("lod_dist_m", 0.0))
	for mesh in meshes:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if material != null:
			mesh.material_override = material
		mesh.set_instance_shader_parameter(&"hit_flash", 0.0)
		mesh.set_instance_shader_parameter(&"emission_scale", 1.0)
		mesh.set_instance_shader_parameter(&"tell", 0.0)
		mesh.set_instance_shader_parameter(&"armor_damage", 0.0)
	if lod_distance > 0.0 and meshes.size() >= 2:
		# HLOD: LOD0 inside the distance, the decimated copy beyond it, both skinned by the same rig.
		meshes[0].visibility_range_end = lod_distance
		meshes[0].visibility_range_end_margin = lod_distance * 0.15
		meshes[0].visibility_range_fade_mode = \
				GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		for extra in meshes.slice(1):
			extra.visibility_range_begin = lod_distance
			extra.visibility_range_begin_margin = lod_distance * 0.15
			extra.visibility_range_fade_mode = \
					GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child)
