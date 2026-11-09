class_name StormCrown
extends MeshInstance3D
## The storm shell around the Spire crown (city-art). One inverted sphere at the crown altitude
## carrying `mc_storm`, plus one shadow-less OmniLight3D that plays the strike flash — godot-tech
## §4.3 forbids shadowed omni lights on moving rigs, and short-lived lights ghost in volumetric fog,
## so the strike light has volumetric energy 0 and a hard life cap.
## TimeOfDay calls `set_cover(amount)`; `lightning_at` arrives through TimeOfDay -> `strike(pos)`.

const SHADER := preload("res://world/art/shaders/mc_storm.gdshader")
const RADIUS := 760.0
const SEGMENTS := 40
const RINGS := 20
const STRIKE_LIGHT_ENERGY := 26.0
const STRIKE_DECAY := 6.0            ## 1/s exponential decay of a flash
const AUTO_STRIKE_MIN := 2.6         ## seconds between unprompted strikes at cover 1
const AUTO_STRIKE_MAX := 9.0

## city-art r16b §4: the strike has to be DETERMINISTIC when it is measured. A random flash every
## 2.6-9 s means the clip number at `--tod=1.0` is a lottery, and six of r15's seven clip-gate failures
## are at the boss time. `--storm-strike=none` holds the crown dark (the floor), `=peak` holds one
## strike at its peak for ever (the ceiling), and the default keeps the storm alive.
enum StrikeMode { AUTO, NONE, PEAK }

## Crown centre in Godot coordinates: the Spire stands at Blender (0, 120) with its deck at +224 m.
const CROWN_CENTER := Vector3(0.0, 300.0, -120.0)
## Where the deterministic strike sits: on the crown deck, in front of the Spire.
const PEAK_STRIKE := Vector3(0.0, 340.0, -120.0)

var cover: float = 0.0

var _mat: ShaderMaterial
var _light: OmniLight3D
var _flash: float = 0.0
var _next_strike: float = 0.0
var _mode: StrikeMode = StrikeMode.AUTO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20261101
	match Game.flag("storm-strike", "auto"):
		"none": _mode = StrikeMode.NONE
		"peak": _mode = StrikeMode.PEAK
		_: _mode = StrikeMode.AUTO
	mesh = _dome_mesh()
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"cloud_dark", Color("241a3a"))
	_mat.set_shader_parameter(&"cloud_light", ArtPalette.STORM)
	material_override = _mat
	position = CROWN_CENTER
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = RADIUS
	visibility_range_end = 3000.0

	_light = OmniLight3D.new()
	_light.omni_range = 420.0
	_light.light_color = ArtPalette.linear(ArtPalette.STORM)
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.light_volumetric_fog_energy = 0.0
	_light.light_bake_mode = Light3D.BAKE_DISABLED
	add_child(_light)

	set_cover(0.0)
	_next_strike = _rng.randf_range(AUTO_STRIKE_MIN, AUTO_STRIKE_MAX)


func _dome_mesh() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = RADIUS
	m.height = RADIUS * 2.0
	m.radial_segments = SEGMENTS
	m.rings = RINGS
	m.is_hemisphere = false
	return m


## Storm cloud cover 0..1 (ART.md §3: 0 % at the start, 100 % at the boss).
func set_cover(amount: float) -> void:
	cover = clampf(amount, 0.0, 1.0)
	if _mat != null:
		_mat.set_shader_parameter(&"cover", cover)
	visible = cover > 0.002


func strike(pos: Vector3) -> void:
	_flash = 1.0
	if _mat != null:
		_mat.set_shader_parameter(&"flash_pos", pos)
	if _light != null:
		_light.global_position = pos
	_next_strike = _rng.randf_range(AUTO_STRIKE_MIN, AUTO_STRIKE_MAX)


func _process(delta: float) -> void:
	if cover <= 0.002:
		return
	var real := Feel.real_delta(delta)
	if _mode == StrikeMode.NONE:
		_flash = 0.0
		_push_flash()
		return
	if _mode == StrikeMode.PEAK:
		_flash = 1.0
		if _mat != null:
			_mat.set_shader_parameter(&"flash_pos", PEAK_STRIKE)
		if _light != null:
			_light.global_position = PEAK_STRIKE
		_push_flash()
		return
	if _flash > 0.0:
		_flash = maxf(_flash - real * STRIKE_DECAY, 0.0)
		_push_flash()
	_next_strike -= real
	if _next_strike <= 0.0:
		strike(_random_strike_point())


## The flash's two consumers, so the three strike modes cannot drift apart.
func _push_flash() -> void:
	if _mat != null:
		_mat.set_shader_parameter(&"flash", _flash * 2.2)
	if _light != null:
		_light.light_energy = STRIKE_LIGHT_ENERGY * _flash * _flash * cover


## Unprompted strikes ring the crown deck, so the storm is alive without the flow unit scripting it.
func _random_strike_point() -> Vector3:
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(180.0, 620.0)
	return CROWN_CENTER + Vector3(cos(a) * r, _rng.randf_range(-70.0, 90.0), sin(a) * r)
