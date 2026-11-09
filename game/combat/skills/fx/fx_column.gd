class_name SkillFxColumn
extends SkillFxPiece
## Vertical light column: the Plunge Breaker's impact pillar. A cylinder that punches up from the
## crater, holds for a beat and collapses back into the ground, with a heat-haze sleeve around it so
## the air over the impact shimmers.

const HAZE_SHADER := preload("res://combat/skills/fx/shaders/heat_haze.gdshader")
const BEAM_SHADER := preload("res://combat/skills/fx/shaders/beam.gdshader")
## Hard ceiling on the column's additive emission. Seen from the third-person camera 25-40 m away a
## taller, brighter pillar stacks enough additive layers to clip the whole crater to flat white
## (r2 review), so the peak is capped here rather than at each call site.
const PEAK_STRENGTH := 1.0

var _core: MeshInstance3D = null
var _haze: MeshInstance3D = null
var _height: float = 60.0
var _radius: float = 6.0
var _hold: float = 0.25
var _strength: float = PEAK_STRENGTH


func _ready() -> void:
	super()
	_core = _box(BEAM_SHADER, 3.0)
	_core.name = "ColumnCore"
	_haze = _box(HAZE_SHADER, 0.0)
	_haze.name = "ColumnHaze"
	(_haze.material_override as ShaderMaterial).set_shader_parameter(&"strength", 0.22)


func _box(shader: Shader, priority: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = int(priority)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 128.0
	add_child(mi)
	return mi


## `at` is the ground contact point; the column rises along +Y. `strength` is clamped to
## `PEAK_STRENGTH` so a close camera gets a bloom instead of a white-out.
func fire(at: Vector3, height: float, radius: float, seconds: float, color: Color,
		hold: float = 0.25, strength: float = PEAK_STRENGTH) -> void:
	global_position = at
	global_basis = Basis.IDENTITY
	_height = height
	_radius = radius
	_strength = clampf(strength, 0.0, PEAK_STRENGTH)
	_hold = clampf(hold / maxf(seconds, 0.01), 0.0, 0.9)
	_core.set_instance_shader_parameter(&"color", color)
	_core.set_instance_shader_parameter(&"core", 0.35)
	_core.set_instance_shader_parameter(&"strength", _strength)
	_begin(seconds)
	_advance(0.0)


func _advance(_delta: float) -> void:
	var u := progress()
	# snap up in the first 20 % of life, hold, then sink back into the crater
	var rise := clampf(u / 0.2, 0.0, 1.0)
	var fall_from := _hold + 0.2
	var sink := 1.0
	if u > fall_from:
		sink = clampf(1.0 - (u - fall_from) / maxf(1.0 - fall_from, 0.01), 0.0, 1.0)
	var h: float = _height * rise * sink
	var w: float = _radius * (0.7 + 0.3 * rise) * (0.5 + 0.5 * sink)
	for mi: MeshInstance3D in [_core, _haze]:
		# a zero-height column must go INVISIBLE, not get a zero-scale transform: a degenerate basis
		# is what `--nan-watch` reports at the start and end of every plunge impact
		mi.visible = h > 0.5
		if not mi.visible:
			continue
		mi.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(w, h, w)),
				global_position + Vector3(0.0, h * 0.5, 0.0))
	_core.set_instance_shader_parameter(&"strength", _strength * sink)
