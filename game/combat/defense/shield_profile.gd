class_name MirrorShieldProfile
extends RefCounted
## The Mirror Guard's visual language in ONE place (r7): the numbers that decide how the block panel
## and the catch dome read, the material builder that pushes them into `mirror_shield.gdshader`, and
## the CPU mirror of the shader's alpha maths so a headless test can pin what the pixels will do.
##
## The lead's finding was that the guard rendered as "a flat, opaque, mint-green hexagon about 12 m
## across with a hard edge". Three numbers caused that and all three live here:
##   * `DefenseTable.PANEL_RADIUS` 6.5 (13 m across, wider than the hero's chest);
##   * a material with ONE alpha everywhere, so the interior was as bright as the edge;
##   * `4fe6ff` pushed through an additive material at energy 1.15, which saturates green and blue
##     together and lands on mint once the environment and bloom are on top of it.
## The fix is a nearly empty interior (`CORE_ALPHA`) under a bright rim (`RIM_ALPHA`) in the hero's
## own accent, on a smaller curved cap. `center_alpha()` / `rim_alpha()` are what the test measures.

const SHADER := "res://combat/defense/shaders/mirror_shield.gdshader"

## The interior. `center_alpha()` = CORE_ALPHA * (1 + HEX_GAIN) is the WORST pixel in the interior,
## so the whole middle of the shield is guaranteed under the lead's 0.25 ceiling.
const CORE_ALPHA := 0.12
const HEX_GAIN := 0.30
const RIM_ALPHA := 0.95          ## the lead's floor is 0.8
const RIM_POWER := 2.4
const EDGE_SOFT := 0.22          ## width of the radial band that replaces the hard silhouette
const HEX_SCALE := 7.0
const CORE_COLOR := Color(0.30, 0.90, 1.00)   ## Hero3Shade.ACCENT — the hero's own seam cyan
const RIM_COLOR := Color(0.72, 0.98, 1.00)

## Coming and going (lead: 0.08 s in, 0.15 s out). The fade is a shader uniform, not a visibility
## flip, so the shield arrives and leaves instead of popping.
const FADE_IN := 0.08
const FADE_OUT := 0.15

## A block ripples out of the point that was hit. `RIPPLE_TIME` is the lead's 0.5 s ceiling.
const RIPPLE_TIME := 0.45
const RIPPLE_WIDTH := 0.18
const RIPPLE_GAIN := 1.6

## A perfect parry: the panel flashes white-gold and throws hex shards.
const FLASH_TIME := 0.12
const SHARD_COUNT := 18
const SHARD_LIFE := 0.55
const SHARD_SPEED := 26.0
const SHARD_SIZE := 0.55

## The catch dome: the same language, thinner and cooler, and its hex cells turn so it never reads as
## a second copy of the block panel.
const DOME_CORE_ALPHA := 0.06
const DOME_RIM_ALPHA := 0.85
const DOME_HEX_GAIN := 0.45
const DOME_HEX_SCALE := 11.0
const DOME_SPIN := 0.55          ## rad/s the cells turn at
const DOME_COLOR := Color(0.42, 0.86, 1.00)

## Every uniform `material()` writes. The test walks this list, so a typo in either direction fails.
const UNIFORMS: Array[StringName] = [
	&"core_color", &"rim_color", &"core_alpha", &"rim_alpha", &"rim_power", &"edge_soft",
	&"hex_gain", &"hex_scale", &"hex_spin", &"fade", &"flash", &"ripple", &"ripple_width",
	&"ripple_gain",
]


## The worst alpha anywhere in the interior — the number the lead capped at 0.25.
static func center_alpha() -> float:
	return CORE_ALPHA * (1.0 + HEX_GAIN)


## The alpha on the rim, where the fresnel and the radial band both saturate.
static func rim_alpha() -> float:
	return RIM_ALPHA


## The dome's interior ceiling, the same bound for the catch field.
static func dome_center_alpha() -> float:
	return DOME_CORE_ALPHA * (1.0 + DOME_HEX_GAIN)


## One step of the fade envelope: 0 → 1 over FADE_IN, 1 → 0 over FADE_OUT. `move_toward` rather than
## a curve, so dropping the guard halfway through raising it turns around instead of jumping.
static func fade_step(current: float, up: bool, delta: float) -> float:
	var span := FADE_IN if up else FADE_OUT
	return move_toward(current, 1.0 if up else 0.0, delta / span)


## How far the ripple ring has travelled and how strong it still is, from the time since impact.
## Returns (progress 0..1, strength 0..1); strength is 0 at and after RIPPLE_TIME.
static func ripple_at(since: float) -> Vector2:
	if since < 0.0 or since >= RIPPLE_TIME:
		return Vector2.ZERO
	var k := since / RIPPLE_TIME
	return Vector2(k, 1.0 - k)


## The block panel's material. A fresh ShaderMaterial per surface — there are two in the whole game
## (the panel and the dome) plus one per pooled shard, all built once at load.
static func material() -> ShaderMaterial:
	return _build(CORE_COLOR, RIM_COLOR, CORE_ALPHA, RIM_ALPHA, HEX_GAIN, HEX_SCALE)


## The catch dome's material: thinner, cooler, and its cells turn.
static func dome_material() -> ShaderMaterial:
	return _build(DOME_COLOR, RIM_COLOR, DOME_CORE_ALPHA, DOME_RIM_ALPHA, DOME_HEX_GAIN,
			DOME_HEX_SCALE)


static func _build(core: Color, rim: Color, core_a: float, rim_a: float, hex_gain: float,
		hex_scale: float) -> ShaderMaterial:
	var shader := load(SHADER) as Shader
	if shader == null:
		push_error("MirrorShieldProfile: cannot load %s — the Mirror Guard has no surface" % SHADER)
		return null
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter(&"core_color", core)
	m.set_shader_parameter(&"rim_color", rim)
	m.set_shader_parameter(&"core_alpha", core_a)
	m.set_shader_parameter(&"rim_alpha", rim_a)
	m.set_shader_parameter(&"rim_power", RIM_POWER)
	m.set_shader_parameter(&"edge_soft", EDGE_SOFT)
	m.set_shader_parameter(&"hex_gain", hex_gain)
	m.set_shader_parameter(&"hex_scale", hex_scale)
	m.set_shader_parameter(&"hex_spin", 0.0)
	m.set_shader_parameter(&"fade", 1.0)
	m.set_shader_parameter(&"flash", 0.0)
	m.set_shader_parameter(&"ripple", Vector3.ZERO)
	m.set_shader_parameter(&"ripple_width", RIPPLE_WIDTH)
	m.set_shader_parameter(&"ripple_gain", RIPPLE_GAIN)
	return m
