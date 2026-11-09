extends RefCounted
## Cockpit interior geometry (camera-aim). Builds the canopy the pilot sees in first person: thin
## gunmetal struts with cyan trim lines, a slim dashboard along the bottom of the frame and a glass
## layer. Local space: eye at the origin, -Z forward, metres at mech scale.
## The layout is tuned against the first-person FOV (62° vertical, ~97° horizontal at 16:9): at the
## 1.45 m canopy distance the frame half-extents are ±0.87 m tall and ±1.55 m wide, so the struts sit
## just inside the frame edge. Lead review r1 wants the frame under 18 % of the screen — test_camera
## rasterises these boxes and checks it.
## Materials are built in code (no external art); hero-asset can swap in a modelled canopy later.

const GLASS_SHADER := preload("res://player/camera/cockpit_glass.gdshader")

const GUNMETAL := Color(0.165, 0.184, 0.22)     ## #2A2F38, lead review r1
const GUNMETAL_DARK := Color(0.105, 0.12, 0.145)
const CYAN := Color(0.31, 0.902, 1.0)           ## #4FE6FF
const AMBER := Color(1.0, 0.72, 0.31)
const STRUT_ROUGH := 0.4
const TRIM_ENERGY := 1.5            ## enough to glow, not enough to blow out to white under ACES
const GLASS_MAX_ALPHA := 0.08       ## lead review r1: the canopy must never hide the world

## [name, position, size, rotation_deg, material key, lift, slide]. Members are flat plates AIMED AT THE
## EYE: a plate square-on to the pilot shows only its face, so a 7 cm strut stays 7 cm on screen instead
## of showing its 9 cm side as well. `lift` and `slide` move a part along its own +Y (face normal) and
## +Z (up the slope), so a readout can sit ON the console without repeating the trigonometry.
## Positions are given in the rest-pose VIEW frame (the canopy group carries the rig's default pitch),
## so the numbers read as fractions of the frame at FOV 62: the pillars sit at 75 % of the half-width,
## the top rail at 85 % of the half-height, the console spans the bottom 9 % of the screen.
const PARTS: Array[Array] = [
	# canopy: two raked A-pillars, a top rail with a shadow bevel under it, and the glass
	["pillar_l", Vector3(-1.16, 0.02, -1.45), Vector3(0.06, 1.74, 0.045), Vector3(0.0, 38.7, 6.0), &"metal", 0.0, 0.0],
	["pillar_r", Vector3(1.16, 0.02, -1.45), Vector3(0.06, 1.74, 0.045), Vector3(0.0, -38.7, -6.0), &"metal", 0.0, 0.0],
	["pillar_l_trim", Vector3(-1.13, 0.02, -1.42), Vector3(0.012, 1.62, 0.018), Vector3(0.0, 38.7, 6.0), &"cyan", 0.0, 0.0],
	["pillar_r_trim", Vector3(1.13, 0.02, -1.42), Vector3(0.012, 1.62, 0.018), Vector3(0.0, -38.7, -6.0), &"cyan", 0.0, 0.0],
	["rail_top", Vector3(0.0, 0.74, -1.45), Vector3(2.42, 0.06, 0.045), Vector3(28.8, 0.0, 0.0), &"metal", 0.0, 0.0],
	["rail_top_bevel", Vector3(0.0, 0.785, -1.42), Vector3(2.3, 0.025, 0.03), Vector3(28.8, 0.0, 0.0), &"dark", 0.0, 0.0],
	["rail_top_trim", Vector3(0.0, 0.715, -1.42), Vector3(2.3, 0.012, 0.02), Vector3(28.8, 0.0, 0.0), &"cyan", 0.0, 0.0],
	["canopy_glass", Vector3(0.0, 0.0, -1.52), Vector3(2.62, 2.0, 0.0), Vector3.ZERO, &"glass", 0.0, 0.0],
	# console: a raked panel filling the bottom 9 % of the frame, dark inset glass and three readouts
	["dash", Vector3(0.0, -0.66, -1.235), Vector3(2.3, 0.04, 0.13), Vector3(-57.0, 0.0, 0.0), &"console", 0.0, 0.0],
	["dash_inset", Vector3(0.0, -0.66, -1.235), Vector3(2.06, 0.012, 0.1), Vector3(-57.0, 0.0, 0.0), &"dark", 0.027, 0.0],
	["dash_trim", Vector3(0.0, -0.66, -1.235), Vector3(2.2, 0.008, 0.012), Vector3(-57.0, 0.0, 0.0), &"cyan", 0.034, -0.055],
	["screen_l", Vector3(-0.72, -0.66, -1.235), Vector3(0.5, 0.01, 0.055), Vector3(-57.0, 0.0, 0.0), &"cyan", 0.034, 0.008],
	["screen_c", Vector3(0.0, -0.66, -1.235), Vector3(0.56, 0.01, 0.065), Vector3(-57.0, 0.0, 0.0), &"screen", 0.034, 0.008],
	["screen_r", Vector3(0.72, -0.66, -1.235), Vector3(0.5, 0.01, 0.055), Vector3(-57.0, 0.0, 0.0), &"amber", 0.034, 0.008],
	# side rails tying the console into the pillars
	["rail_side_l", Vector3(-1.15, -0.63, -1.34), Vector3(0.05, 0.05, 0.18), Vector3(0.0, 41.0, 0.0), &"metal", 0.0, 0.0],
	["rail_side_r", Vector3(1.15, -0.63, -1.34), Vector3(0.05, 0.05, 0.18), Vector3(0.0, -41.0, 0.0), &"metal", 0.0, 0.0],
]


## Fills `parent` with a `Canopy` group holding the meshes. `rest_pitch_deg` is the rig's default pitch:
## the canopy is raked with it so the frame is centred in the view at rest and sweeps naturally when the
## player looks up or down. Returns the created instances by name for the tests.
static func build(parent: Node3D, rest_pitch_deg: float) -> Dictionary:
	var group := Node3D.new()
	group.name = "Canopy"
	group.rotation_degrees.x = rest_pitch_deg
	parent.add_child(group)
	var mats := materials()
	var built := {}
	for part in PARTS:
		var inst := MeshInstance3D.new()
		inst.name = String(part[0])
		var size := part[2] as Vector3
		if size.z > 0.0:
			var box := BoxMesh.new()
			box.size = size
			inst.mesh = box
		else:
			# A flat pane: one quad, one face — no back face to double the glass alpha.
			var quad := QuadMesh.new()
			quad.size = Vector2(size.x, size.y)
			inst.mesh = quad
		inst.material_override = mats[part[4]] as Material
		var rot := part[3] as Vector3
		inst.rotation_degrees = rot
		inst.position = (part[1] as Vector3) + Basis.from_euler(rot * (PI / 180.0)) \
				* Vector3(0.0, part[5] as float, part[6] as float)
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(inst)
		built[part[0]] = inst
	return built


static func materials() -> Dictionary:
	return {
		&"metal": _metal(GUNMETAL),
		&"console": _console(),
		&"dark": _metal(GUNMETAL_DARK),
		&"cyan": _lit(CYAN),
		&"amber": _lit(AMBER),
		&"screen": _screen(),
		&"glass": _glass(),
	}


static func _metal(albedo: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.metallic = 0.4
	mat.roughness = STRUT_ROUGH
	return mat


static func _lit(colour: Color) -> StandardMaterial3D:
	var mat := _metal(colour)
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = TRIM_ENERGY
	return mat


## The console body: lighter than the struts and faintly self-lit, so the panel reads as a surface the
## pilot can see instead of a black bar across the bottom of the frame.
static func _console() -> StandardMaterial3D:
	var mat := _metal(GUNMETAL.lightened(0.28))
	mat.metallic = 0.2
	mat.roughness = 0.55
	return mat


## A dashboard screen: dark glass with a soft glow behind it, so the readouts have depth.
static func _screen() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.09, 0.12)
	mat.metallic = 0.2
	mat.roughness = 0.15
	mat.emission_enabled = true
	mat.emission = CYAN
	mat.emission_energy_multiplier = 0.5
	return mat


static func _glass() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GLASS_SHADER
	mat.set_shader_parameter(&"max_alpha", GLASS_MAX_ALPHA)
	return mat
