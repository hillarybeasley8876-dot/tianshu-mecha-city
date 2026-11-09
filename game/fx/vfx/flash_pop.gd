class_name FxFlashPop
extends Node3D
## Contact flash (feel unit): one camera-facing additive billboard that snaps on for a few frames at
## an impact point. Two flavours from the same shader - a small round pop on every spark burst
## (r2 MUST-FIX 3: "a tiny flash billboard at the contact point") and the 3-frame white cross flare
## on heavy hits (r2 SHOULD, anime-mech flavour). Pooled by VfxLibrary; nothing is allocated here.

const SHADER := preload("res://fx/vfx/flash_pop.gdshader")

## Resting configuration of a pooled pop; VfxLibrary calls configure() at build time and fire() on
## every shot, so a bare `impact_star` slot needs no per-shot allocation.
var pop_size: float = 1.2
var pop_seconds: float = 0.08
var pop_color: Color = Color(1.0, 0.96, 0.85)
var pop_heat: float = 4.0
var star: float = 0.0
## Capture aid: the feel gallery slows real-time VFX (`--fx-slow=`) so a 3-frame pop can be
## photographed. Always 1.0 in game.
var time_scale: float = 1.0

var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _t: float = 0.0
var _last_real: float = 0
var _running: bool = false
var _size: float = 1.2
var _seconds: float = 0.08


## Resting configuration (safe before _ready: nothing here touches the material).
func configure(size_m: float, seconds: float, color: Color, heat: float, star_amount: float) -> void:
	pop_size = maxf(size_m, 0.05)
	pop_seconds = maxf(seconds, 0.016)
	pop_color = color
	pop_heat = heat
	star = clampf(star_amount, 0.0, 1.0)


## Fire the configured pop at `scale_mul` times its resting size.
func fire(scale_mul: float = 1.0) -> void:
	pop(pop_size * scale_mul, pop_seconds, pop_color, pop_heat, star)


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mesh = MeshInstance3D.new()
	_mesh.name = "Pop"
	_mesh.mesh = quad
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.extra_cull_margin = 64.0
	add_child(_mesh)
	visible = false


## Flash at this node's position: `size_m` across, `seconds` long, `star` 0..1 for the cross flare.
func pop(size_m: float, seconds: float, color: Color, heat: float, star_amount: float = 0.0) -> void:
	_size = maxf(size_m, 0.05)
	_seconds = maxf(seconds, 0.016)
	_t = 0.0
	_last_real = Feel.real_now()
	_running = true
	visible = true
	_mat.set_shader_parameter(&"pop_color", color)
	_mat.set_shader_parameter(&"heat", heat)
	_mat.set_shader_parameter(&"star", clampf(star_amount, 0.0, 1.0))
	_apply(0.0)


func is_running() -> bool:
	return _running


func stop() -> void:
	_running = false
	visible = false


func _process(_delta: float) -> void:
	if not _running:
		return
	# Real time: the pop must not stretch out during a hit-stop (juice-impact rule 4).
	var now := Feel.real_now()
	_t += minf(now - _last_real, 0.1) * time_scale
	_last_real = now
	if _t >= _seconds:
		stop()
		return
	_apply(_t / _seconds)


func _apply(p: float) -> void:
	# Grows a little as it dies, so the flash reads as a burst of light rather than a fading dot.
	_mesh.scale = Vector3.ONE * _size * lerpf(0.55, 1.25, p)
	_mat.set_shader_parameter(&"progress", clampf(p, 0.0, 1.0))
