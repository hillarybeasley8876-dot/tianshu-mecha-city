class_name SkillFxSheath
extends SkillFxPiece
## Plasma sheath + speed streaks around a moving body: the Plunge Breaker's 190 m/s dive. The sheath is
## a stretched fresnel shell that trails behind the velocity, and six ribbons stream off the silhouette
## so the dive reads as speed even in a single frame.

const SHELL_SHADER := preload("res://combat/skills/fx/shaders/fresnel_shell.gdshader")
const OPEN_LIFE := 60.0
const RIBBONS := 6

var _shell: MeshInstance3D = null
var _ribbons: MeshInstance3D = null
var _geo: ImmediateMesh = null
var _target: Node3D = null
var _radius: float = 9.0
var _color: Color = Color(0.7, 0.96, 1.0)


func _ready() -> void:
	super()
	_shell = MeshInstance3D.new()
	_shell.name = "Sheath"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 20
	sphere.rings = 10
	_shell.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = SHELL_SHADER
	_shell.material_override = mat
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shell.extra_cull_margin = 32.0
	add_child(_shell)
	_ribbons = MeshInstance3D.new()
	_ribbons.name = "Streaks"
	_geo = ImmediateMesh.new()
	_ribbons.mesh = _geo
	_ribbons.material_override = SkillFx.glow(Color(1.0, 1.0, 1.0), 2.6, true)
	_ribbons.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ribbons.extra_cull_margin = 128.0
	add_child(_ribbons)


func open(target: Node3D, radius: float, color: Color) -> void:
	_target = target
	_radius = radius
	_color = color
	_shell.set_instance_shader_parameter(&"core_color", Color(color.r, color.g, color.b, 1.0))
	_shell.set_instance_shader_parameter(&"rim_color", Color(1.0, 1.0, 1.0, 1.0))
	_shell.set_instance_shader_parameter(&"strength", 1.5)
	_shell.set_instance_shader_parameter(&"power", 1.8)
	_shell.set_instance_shader_parameter(&"progress", 0.0)
	var mat := _ribbons.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = color
		mat.emission = color
	_begin(OPEN_LIFE)


## Called every frame by the skill with the body's current velocity.
func follow(velocity: Vector3) -> void:
	if _target != null and is_instance_valid(_target):
		global_position = _target.global_position
	var speed := velocity.length()
	var dir := velocity.normalized() if speed > 0.5 else Vector3.DOWN
	var stretch := clampf(speed / 60.0, 0.6, 3.2)
	_shell.global_transform = Transform3D(_trail_basis(dir, stretch), global_position)
	_draw_ribbons(dir, speed)


func _trail_basis(dir: Vector3, stretch: float) -> Basis:
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	return SkillFx.stretched(dir, up, _radius, _radius * stretch)


func _draw_ribbons(dir: Vector3, speed: float) -> void:
	_geo.clear_surfaces()
	if speed < 8.0:
		return
	var length := clampf(speed * 0.45, 12.0, 90.0)
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var other := side.cross(dir).normalized()
	_geo.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RIBBONS:
		var ang := TAU * float(i) / float(RIBBONS)
		# LOCAL space: `Streaks` is a plain child of this piece and already inherits its translation,
		# so world-space vertices landed every ribbon at twice the mech's position (audit #5)
		var offset := (side * cos(ang) + other * sin(ang)) * _radius * 0.7
		var a := offset
		var b := a - dir * length
		var w := 0.55
		var quad_side := other * w if absf(offset.dot(other)) > 0.01 else side * w
		_geo.surface_set_color(_color)
		for p: Vector3 in [a - quad_side, a + quad_side, b + quad_side,
				a - quad_side, b + quad_side, b - quad_side]:
			_geo.surface_add_vertex(p)
	_geo.surface_end()


func stop() -> void:
	super()
	_target = null
	if _geo != null:
		_geo.clear_surfaces()
