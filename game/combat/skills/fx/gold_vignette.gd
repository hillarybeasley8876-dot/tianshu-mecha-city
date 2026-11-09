class_name SkillGoldVignette
extends CanvasLayer
## Screen-space gold rim for the Zenith Overdrive and the Lance charge. The skills unit owns it
## (CONTRACTS §1: `fx/**` is the feel unit's), so it is a thin CanvasLayer over the viewport that no
## other post effect touches: Feel keeps the red damage vignette, this is the gold power edge.

const SHADER := preload("res://combat/skills/fx/shaders/rim_vignette.gdshader")

var _rect: ColorRect = null
var _mat: ShaderMaterial = null
var _left: float = 0.0
var _hold: float = 0.0
var _target: float = 0.0


func _ready() -> void:
	layer = 5
	_rect = ColorRect.new()
	_rect.name = "GoldRim"
	_rect.anchor_right = 1.0
	_rect.anchor_bottom = 1.0
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"strength", 0.0)
	_rect.material = _mat
	add_child(_rect)
	set_process(true)


## Hold the rim at `strength` for `hold` seconds, then fade out over `fade`.
func open(color: Color, strength: float, hold: float, fade: float = 0.35,
		width: float = 0.55) -> void:
	_mat.set_shader_parameter(&"color", color)
	_mat.set_shader_parameter(&"width", width)
	_target = strength
	_hold = maxf(hold, 0.0)
	_left = _hold + maxf(fade, 0.05)
	_mat.set_shader_parameter(&"strength", strength)
	visible = true


func close() -> void:
	_hold = 0.0
	_left = 0.08
	_target = 0.0


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left > 0.0 and _hold > 0.0:
		_hold -= delta
		return
	var k: float = clampf(_left / 0.35, 0.0, 1.0)
	_mat.set_shader_parameter(&"strength", _target * k * k)
	if _left <= 0.0:
		visible = false
