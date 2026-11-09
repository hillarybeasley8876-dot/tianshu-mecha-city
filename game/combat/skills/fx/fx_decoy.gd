class_name SkillFxDecoy
extends SkillFxPiece
## The Rift Step decoy: a hologram of the mech left standing where the blink started, which the Ripper
## AI keeps biting at (docs/SPEC.md §3). Pooled MeshInstance3Ds are re-pointed at the live mesh
## resources (the same trick as the fx unit's afterimage pool) and drawn with the hologram shader:
## scanlines, a rising sweep and a hard fresnel edge, so it reads as projected light, not a clone.

const SHADER := preload("res://combat/skills/fx/shaders/hologram.gdshader")
const MAX_MESHES := 24

var _ghosts: Array[MeshInstance3D] = []
var _used: int = 0


func _ready() -> void:
	super()
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	for i in MAX_MESHES:
		var mi := MeshInstance3D.new()
		mi.name = "Decoy%d" % i
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_ghosts.append(mi)


## Freeze the source's silhouette at its current world pose for `seconds`.
func fire(source: Node3D, seconds: float, tint: Color = Color(0.42, 0.86, 1.0),
		strength: float = 1.5) -> void:
	global_position = Vector3.ZERO
	global_basis = Basis.IDENTITY
	_used = 0
	if source != null and is_instance_valid(source):
		for mi: MeshInstance3D in _meshes(source):
			if _used >= MAX_MESHES:
				break
			_bind(mi, tint, strength)
	_begin(seconds)


func _bind(source: MeshInstance3D, tint: Color, strength: float) -> void:
	if source.mesh == null or not source.is_visible_in_tree():
		return
	var g := _ghosts[_used]
	_used += 1
	g.mesh = source.mesh
	g.skeleton = _rebase(g, source)
	g.global_transform = source.global_transform
	g.visible = true
	g.set_instance_shader_parameter(&"tint", tint)
	g.set_instance_shader_parameter(&"strength", strength)
	g.set_instance_shader_parameter(&"fade", 1.0)


func _advance(_delta: float) -> void:
	var fade := 1.0 - progress()
	for i in _used:
		_ghosts[i].set_instance_shader_parameter(&"fade", fade)


func stop() -> void:
	super()
	for g in _ghosts:
		g.visible = false
		g.mesh = null
	_used = 0


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


## A skinned part must point at the source's Skeleton3D or it renders in bind pose; the path is
## re-based because the ghost lives under the skill system, not under the mech.
func _rebase(ghost: MeshInstance3D, source: MeshInstance3D) -> NodePath:
	if source.skeleton.is_empty():
		return NodePath()
	var skel := source.get_node_or_null(source.skeleton)
	return ghost.get_path_to(skel) if skel != null else NodePath()
