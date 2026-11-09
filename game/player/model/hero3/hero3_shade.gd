class_name Hero3Shade
extends Node
## Every material decision on the Tianshu (hero-v3 r7). The lead's finding was that the hero read as
## a black silhouette in every trailer shot, and the cause was material-level: the body carried one
## Tripo material with no emission at all, so the concept's cyan seam lines were albedo pixels that
## went black on the shaded side, and the armour albedo sat at 0.009 linear -- a hole, not a colour.
##
## This owns:
##   * `hero3_shell.gdshader` on the armour surface: the mask-driven emission, the albedo lift, the
##     gold metal and the view-dependent silhouette rim;
##   * the plain gunmetal / gold / edge materials on the joint mechanisms and the three weapons;
##   * the accent state -- the steady lines, the vents that pulse with boost / overdrive / charge,
##     and the cyan -> amber overdrive tint that used to only reach surfaces that already glowed.

const SHELL := "res://player/model/hero3/hero3_shell.gdshader"
const EMISSION_LOD0 := "res://player/model/hero3/hero3_Emission.png"
const EMISSION_LOD1 := "res://player/model/hero3/hero3_lod1_Emission.png"
## The accent language, in one place. Cyan at rest, amber in overdrive -- the same pair
## `Hero3Glow` uses for the modelled visor, vent and drone tips.
const ACCENT := Color(0.30, 0.90, 1.00)
const OVERDRIVE := Color(1.00, 0.72, 0.30)
const VENT := Color(1.00, 0.56, 0.13)
const TINT_LERP := 6.0
## The rim. It has to lift the outline off a dark city without flattening the form, so it is a
## narrow, low-gain fresnel in a cool tone -- and it is OFF in first person (the cockpit must not
## glow at the player from 30 cm away).
const RIM := Color(0.55, 0.66, 0.82)
const RIM_GAIN := 0.35
const RIM_GAIN_FP := 0.0
const RIM_POWER := 3.2
## The character fill (see the shader): a hemisphere, cool from the sky and warm from the city's
## bounce, on the same third-person switch as the rim. Without it a backlit black mech at dusk has
## no form at all.
## Neutral-warm, not blue: a blue sky fill plus a blue rim is what turned the plates blue-grey once
## city-art r15 raised the ambient (lead note on r7).
const FILL_SKY := Vector3(0.055, 0.058, 0.065)
const FILL_GROUND := Vector3(0.070, 0.052, 0.036)
const FILL_GAIN := 0.45
## The shell's tuning, pushed from here rather than left as shader defaults so it is one place to
## read, one place to A/B, and answerable from a test (`test_hero3_shade.gd`).
## Linear floor under the black armour: Tripo baked it at 0.009, which is a hole, not a colour.
## 0.052 was measured against the PRE-r15 ambient and read as lifted grey-blue once r15 raised it.
## The plates now stay near-black and get their read from the dielectric sheen below, which is what
## the lead asked for.
const LIFT_COLOR := Vector3(0.020, 0.020, 0.021)
const LIFT_BAND := Vector2(0.008, 0.130)
## The roughness the trim's baked value is clamped into, so a golden-hour sky has something to sit in.
const GOLD_ROUGH_BAND := Vector2(0.26, 0.40)
## A metal's colour is its albedo times the environment, and the environment at dusk is not gold, so
## the trim's albedo is forced to a gold hue. The Tripo bake left it tan at metallic 0.51, which read
## as dirty brass.
## 47 deg, not the 36 deg the first pass used: a metal reflects the environment, and the environment
## at --tod 0.6 is a warm orange wall that dragged the measured trim hue down by ~20 deg.
const GOLD_ALBEDO := Vector3(0.56, 0.52, 0.13)
const GOLD_TINT := 0.8
const GOLD_GLOW := 0.13
## The plates are a DIELECTRIC: a metal's specular is tinted by its albedo, so metallic black armour
## reflects nothing. A low metallic, a mid roughness and a raised F0 put the city's own light on them.
const ARMOUR_METALLIC := 0.12
const ARMOUR_ROUGH := 0.28
const ARMOUR_SPECULAR := 0.85
const LINE_GAIN := 0.9
const VENT_GAIN := 3.5
const RIM_LERP := 9.0
## `rim_tint` is a 0..1 blend, not an enum: 0 tints the rim with the albedo, 1 with emission.
const RIM_TINT := 1.0
## Vents idle at a third of their lit value: the chest is warm even standing still.
const VENT_IDLE := 0.34
const VENT_LERP := 7.0
## How long the whole mech takes to power down and back up (lead r8). ~1 s: a death is a 1.5 s beat
## and the lights going out inside it is the read, while a revive that took longer would leave the
## player flying a dark mech.
const POWER_TIME := 1.0
## Plain materials the Blender build authored. Gold has to be a metal or a golden-hour sky puts
## nothing on it; gunmetal was already close and only needs the roughness a city reflection can sit
## in.
const GOLD_METALLIC := 1.0
const GOLD_ROUGH := 0.30
const GUNMETAL_ROUGH := 0.44
const EDGE_ENERGY := 1.1
## resource_name -> what this unit does to it. Anything else is left exactly as Blender authored it.
const PLAIN: Dictionary = {
	"Hero3Gold": "gold", "Hero3Gunmetal": "gunmetal", "Hero3Joint": "gunmetal",
	"Hero3Edge": "edge",
}

## Every static uniform the shell reads, in one table.
const SHELL_TUNING: Dictionary = {
	&"lift_color": LIFT_COLOR, &"lift_band": LIFT_BAND,
	&"gold_metallic": GOLD_METALLIC, &"gold_roughness": GOLD_ROUGH_BAND,
	&"gold_albedo": GOLD_ALBEDO, &"gold_tint": GOLD_TINT, &"gold_glow": GOLD_GLOW,
	&"armour_metallic": ARMOUR_METALLIC, &"armour_roughness": ARMOUR_ROUGH,
	&"armour_specular": ARMOUR_SPECULAR, &"line_gain": LINE_GAIN, &"vent_gain": VENT_GAIN,
	&"rim_power": RIM_POWER, &"fill_sky": FILL_SKY, &"fill_ground": FILL_GROUND,
	&"rim_color": RIM,
}

var shell: ShaderMaterial
## Which surface of `Hero3Body` carries the Tripo atlas. `Hero3Glow` needs it: by the time it runs the
## shell is already installed, so "the textured surface" is no longer answerable from the mesh.
var armour_surface: int = -1
## The overdrive blend, read by `Hero3Glow` so the modelled visor and tips change with the body.
var tint: float = 0.0

var _tint_target: float = 0.0
var _rim: float = RIM_GAIN
var _rim_target: float = RIM_GAIN
var _vent: float = VENT_IDLE
var _vent_target: float = VENT_IDLE
## 1 powered, 0 dead. Every emissive on the mech rides this, so a wreck reads as powered down and a
## revive brings the lights back (lead r8, from the mech-move acceptance).
var power: float = 1.0
var _power_target: float = 1.0
var _edges: Array[StandardMaterial3D] = []
var _plain: Array[StandardMaterial3D] = []


func setup(model: Node3D) -> void:
	_build_shell(model)
	_tune_plain(model)
	Events.camera_mode_changed.connect(_on_camera_mode)


## The measurement hook: the shell writes a flat mask straight to emission on an otherwise black
## surface, so `palette.py` can measure the trim's hue and the plates' luma on a real frame instead of
## guessing which pixels are which. `--hero3-debug=gold|plate`. The pass is only usable with the world
## hidden (`hero3_look.gd --look-debug`), because through the full post stack the bloom spreads a
## bright mask over the whole frame.
func debug_mask(which: String) -> void:
	if shell == null:
		return
	var mode := 0
	match which:
		"gold": mode = 1
		"plate": mode = 2
		"all": mode = 3
	shell.set_shader_parameter(&"debug_mask", mode)


## Replace the armour surface's Tripo material with the shell shader, wired to the textures the glTF
## import already resolved (so nothing here hardcodes the atlas's uuid filename but the mask).
func _build_shell(model: Node3D) -> void:
	var body := _find_body(model)
	if body == null:
		push_error("Hero3Shade: no Hero3Body to shade")
		return
	var src: StandardMaterial3D = null
	for s in body.mesh.get_surface_count():
		var mat := body.get_active_material(s) as StandardMaterial3D
		if mat != null and mat.albedo_texture != null:
			armour_surface = s
			src = mat
			break
	if src == null:
		push_error("Hero3Shade: no textured surface on Hero3Body")
		return
	shell = ShaderMaterial.new()
	shell.shader = load(SHELL) as Shader
	shell.set_shader_parameter(&"albedo_tex", src.albedo_texture)
	shell.set_shader_parameter(&"normal_tex", src.normal_texture)
	shell.set_shader_parameter(&"orm_tex", src.roughness_texture)
	var lod1 := src.albedo_texture.resource_path.contains("lod1")
	shell.set_shader_parameter(&"emis_tex", load(EMISSION_LOD1 if lod1 else EMISSION_LOD0))
	for key: StringName in SHELL_TUNING:
		shell.set_shader_parameter(key, SHELL_TUNING[key])
	body.set_surface_override_material(armour_surface, shell)


## The joint mechanisms, the caps and the three weapons are flat-colour StandardMaterial3Ds. They are
## duplicated once here (the glTF materials are shared resources) and then written directly.
func _tune_plain(model: Node3D) -> void:
	var seen: Dictionary = {}
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			_own(node as MeshInstance3D, seen)
		stack.append_array(node.get_children())


func _own(mi: MeshInstance3D, seen: Dictionary) -> void:
	for s in mi.mesh.get_surface_count():
		var shared := mi.get_active_material(s) as StandardMaterial3D
		if shared == null or not PLAIN.has(shared.resource_name):
			continue
		var mat: StandardMaterial3D = seen.get(shared.resource_name)
		if mat == null:
			mat = _retune(shared.duplicate() as StandardMaterial3D,
					String(PLAIN[shared.resource_name]))
			seen[shared.resource_name] = mat
		mi.set_surface_override_material(s, mat)


func _retune(mat: StandardMaterial3D, kind: String) -> StandardMaterial3D:
	match kind:
		"gold":
			mat.metallic = GOLD_METALLIC
			mat.roughness = GOLD_ROUGH
			mat.rim_tint = RIM_TINT
			_plain.append(mat)
		"gunmetal":
			mat.roughness = GUNMETAL_ROUGH
			mat.rim_tint = RIM_TINT
			_plain.append(mat)
		"edge":
			mat.emission_energy_multiplier = EDGE_ENERGY
			mat.rim_tint = RIM_TINT
			_edges.append(mat)
	return mat


func _find_body(model: Node3D) -> MeshInstance3D:
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and String(node.name).begins_with("Hero3Body"):
			return node as MeshInstance3D
		stack.append_array(node.get_children())
	return null


# --- state -----------------------------------------------------------------------------------------

func set_overdrive(on: bool) -> void:
	_tint_target = 1.0 if on else 0.0


## A dead mech is a wreck, not an idling machine: every emissive on it -- the seam lines, the vents,
## the gold trim's anchor, the weapon edges and the modelled visor and drone tips -- fades out over
## `POWER_TIME` and comes back on the revive (lead r8, from the mech-move acceptance).
func set_powered(on: bool) -> void:
	_power_target = 1.0 if on else 0.0


## `boost` is the thruster level and `charging` is a held weapon or melee charge: both light the
## vents, and the overdrive tint rides on top.
func set_pulse(boost: float, charging: bool) -> void:
	var lit: float = maxf(clampf(boost, 0.0, 1.0), _tint_target)
	if charging:
		lit = 1.0
	_vent_target = lerpf(VENT_IDLE, 1.0, lit)


func _on_camera_mode(first_person: bool) -> void:
	_rim_target = RIM_GAIN_FP if first_person else RIM_GAIN


func update(delta: float) -> void:
	tint = lerpf(tint, _tint_target, clampf(delta * TINT_LERP, 0.0, 1.0))
	_rim = lerpf(_rim, _rim_target, clampf(delta * RIM_LERP, 0.0, 1.0))
	_vent = lerpf(_vent, _vent_target, clampf(delta * VENT_LERP, 0.0, 1.0))
	power = move_toward(power, _power_target, delta / POWER_TIME)
	var accent := ACCENT.lerp(OVERDRIVE, tint)
	if shell != null:
		shell.set_shader_parameter(&"accent_color", accent)
		shell.set_shader_parameter(&"vent_color", VENT.lerp(OVERDRIVE, tint))
		shell.set_shader_parameter(&"vent_pulse", _vent * power)
		shell.set_shader_parameter(&"rim_gain", _rim)
		shell.set_shader_parameter(&"fill_gain", FILL_GAIN * _rim / RIM_GAIN)
		# the two gains the shell multiplies its emission by, rather than a colour it can only tint
		shell.set_shader_parameter(&"line_gain", LINE_GAIN * power)
		shell.set_shader_parameter(&"gold_glow", GOLD_GLOW * power)
	for mat in _edges:
		mat.emission = accent
		mat.emission_energy_multiplier = EDGE_ENERGY * power
	for mat in _plain + _edges:
		mat.rim_enabled = _rim > 0.001
		mat.rim = _rim


func report() -> Dictionary:
	return {"shell": shell != null, "rim": snappedf(_rim, 0.01),
			"fill": snappedf(FILL_GAIN * _rim / RIM_GAIN, 0.01),
			"vent": snappedf(_vent, 0.01), "tint": snappedf(tint, 0.01),
			"power": snappedf(power, 0.01),
			"edges": _edges.size(), "plain": _plain.size()}
