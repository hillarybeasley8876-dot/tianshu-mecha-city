class_name SkillFxRing
extends SkillFxPiece
## Flat expanding ring laid on a surface: the Shockcore ground shock ring, the Plunge dust wave, the
## Undertow field rim. Drawn on a unit PlaneMesh whose +Y is the surface normal, so the band always
## rides the leading edge of the expansion.

const SHADER := preload("res://combat/skills/fx/shaders/ring.gdshader")

var _mesh: MeshInstance3D = null
var _radius: float = 1.0
var _from: float = 0.0


func _ready() -> void:
	super()
	_mesh = MeshInstance3D.new()
	_mesh.name = "Ring"
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)   # unit radius: UV centre -> 1.0 at the mesh edge
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	_mesh.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.extra_cull_margin = 64.0
	add_child(_mesh)


func fire(at: Vector3, normal: Vector3, from_radius: float, radius: float, seconds: float,
		color: Color, thickness: float = 0.14, strength: float = 1.8) -> void:
	global_position = at
	var n := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	var ref := Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := n.cross(ref).normalized()
	global_basis = Basis(x, n, x.cross(n))
	_radius = radius
	_from = from_radius
	_mesh.set_instance_shader_parameter(&"color", color)
	_mesh.set_instance_shader_parameter(&"strength", strength)
	_mesh.set_instance_shader_parameter(&"thickness", thickness)
	_mesh.set_instance_shader_parameter(&"progress", 0.0)
	_begin(seconds)
	_advance(0.0)


func _advance(_delta: float) -> void:
	var u := progress()
	var eased := 1.0 - pow(1.0 - u, 2.2)
	_mesh.scale = Vector3.ONE * maxf(lerpf(_from, _radius, eased), 0.05)
	_mesh.set_instance_shader_parameter(&"progress", u)
