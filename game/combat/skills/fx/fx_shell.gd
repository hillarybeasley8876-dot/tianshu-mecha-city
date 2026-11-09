class_name SkillFxShell
extends SkillFxPiece
## Expanding fresnel sphere: the Shockcore shell (0 → 32 m in 0.18 s), the refraction ripple at both
## ends of a Rift Step, the Plunge impact bubble. The shader fades the trailing body out as
## `progress` rises, so the read is a travelling front rather than a growing ball.

const SHADER := preload("res://combat/skills/fx/shaders/fresnel_shell.gdshader")

var _mesh: MeshInstance3D = null
var _radius: float = 1.0
var _from: float = 0.0


func _ready() -> void:
	super()
	_mesh = MeshInstance3D.new()
	_mesh.name = "Shell"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 28
	sphere.rings = 14
	_mesh.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.extra_cull_margin = 64.0
	add_child(_mesh)


## `from_radius` > 0 makes it a contracting inhale instead of an expanding shell.
func fire(at: Vector3, from_radius: float, radius: float, seconds: float, core: Color, rim: Color,
		strength: float = 1.6, power: float = 2.6) -> void:
	global_position = at
	_radius = radius
	_from = from_radius
	_mesh.set_instance_shader_parameter(&"core_color", core)
	_mesh.set_instance_shader_parameter(&"rim_color", rim)
	_mesh.set_instance_shader_parameter(&"strength", strength)
	_mesh.set_instance_shader_parameter(&"power", power)
	_mesh.set_instance_shader_parameter(&"progress", 0.0)
	_begin(seconds)
	_advance(0.0)


## Follows a moving node (the Plunge sheath rides the diving mech).
func follow(node: Node3D) -> void:
	if node != null and is_instance_valid(node):
		global_position = node.global_position


func _advance(_delta: float) -> void:
	var u := progress()
	# ease-out: the front leaves fast and settles at the rim, which is what sells the snap
	var eased := 1.0 - pow(1.0 - u, 2.4)
	_mesh.scale = Vector3.ONE * maxf(lerpf(_from, _radius, eased), 0.05)
	_mesh.set_instance_shader_parameter(&"progress", u)
