class_name CityEnvironment
extends RefCounted
## Builds the Godot `Environment` + `Sky` for 云阙城 at golden dusk (city-art, ART.md §3).
## TimeOfDay owns the animation; this class owns the construction and the colour grade, so the
## resource can also be built head-less in tests.
## It also owns the one `Compositor` the frame is finished through (lead 12:25): the post-render unit
## appends its `CompositorEffect`s to `CityEnvironment.compositor()` and they run under everything
## feel puts on top.

const GRADE_SIZE := 16
const SKY_SHADER := preload("res://world/art/shaders/mc_sky.gdshader")

## The shared stack. One `Compositor` for the whole project, so an effect another unit appends is
## picked up by every scene carrying the environment (city, vistas, look-dev) without that unit having
## to touch a scene file. Empty by default: city-art's look is the Environment plus the mc_* shaders,
## and this is the hook, not a second grade.
static var _compositor: Compositor = null


## The post-processing stack post-render attaches to (`world/post/**`).
static func compositor() -> Compositor:
	if _compositor == null:
		_compositor = Compositor.new()
		_compositor.resource_name = "mc_post"
	return _compositor


## Adds an effect to the shared stack. Effects run in append order, so a grade has to be added before
## the lens pass that reads it; `enabled` and the presets stay the caller's business.
static func add_compositor_effect(effect: CompositorEffect) -> void:
	if effect == null:
		push_error("CityEnvironment: refusing to add a null CompositorEffect")
		return
	var list: Array[CompositorEffect] = compositor().compositor_effects
	if list.has(effect):
		return
	list.append(effect)
	compositor().compositor_effects = list


## The dusk dome. 4.7's PhysicalSkyMaterial is a physical Rayleigh/Mie model with no colour ramp and
## no cloud cover, so ART.md §2's fixed gradient is built as a `sky` shader instead (see mc_sky).
static func build_sky() -> Sky:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter(&"zenith", ArtPalette.SKY_ZENITH)
	sky_mat.set_shader_parameter(&"mid_sky", ArtPalette.SKY_MID)
	sky_mat.set_shader_parameter(&"horizon", ArtPalette.SKY_HORIZON)
	sky_mat.set_shader_parameter(&"horizon_away", ArtPalette.SKY_HORIZON_AWAY)
	sky_mat.set_shader_parameter(&"ground", ArtPalette.HAZE_UNDER_DECK)
	sky_mat.set_shader_parameter(&"sun_color", ArtPalette.SUN_DISC)
	sky_mat.set_shader_parameter(&"cloud_warm", ArtPalette.CLOUD_WARM)
	sky_mat.set_shader_parameter(&"cloud_dusk", ArtPalette.CLOUD_DUSK)
	# r14: 0.9 put the horizon band over 248/255 across the top of V7 and V8 before any bloom.
	# r15: 0.58 was cut for that clipping and it cost far more than it bought — the sky is ALSO the
	# ambient source, so a dark sky is a dark shade. Measured at tod 0.6 (`r15b_exp` against
	# `r15a_sky`): the sky's own luma 0.16 -> 0.29, the shaded surfaces' median 0.008 -> 0.092 on V3 and
	# 0.004 -> 0.094 on S02city, the zenith's hue 10 deg -> 339 deg (a dark blue through AgX rotates to
	# magenta; a bright one does not), and the clip gate did not move (0.33-0.78 % against a 1.5 % gate).
	sky_mat.set_shader_parameter(&"exposure", 1.05)
	# r15: the CC0 cloud field (sky/README.md). Blend 0 in the manifest = the hand-built dome alone;
	# `--pano-blend=` is how the two are A/B'd on side-by-side sheets rather than on preference.
	SkyPano.apply(sky_mat)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	return sky


## The sun-material pair TimeOfDay needs, so it can push the ramp into the sky shader.
static func sky_uniforms(env: Environment) -> ShaderMaterial:
	if env == null or env.sky == null:
		return null
	return env.sky.sky_material as ShaderMaterial



## The full environment: sky ambient, AgX tonemap, warm haze depth fog, height fog is faked with the
## depth-fog curve (Godot has no height fog in stock Forward+), and the split-toned grade.
static func build(preset: Dictionary) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = build_sky()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Review r2: the city came out uniformly salmon — a fully warm sky dome lit the shadows with the
	# same hue as the sun. Mixing in a cool sky-neutral ambient restores the golden-hour separation:
	# warm key, cool shade. Lead r4 §2: the shaded faces have to sit 2-3 stops under the sunlit ones and
	# read COOL, so the fill is blue-violet and deliberately weak — the bounce that keeps a shadow
	# readable comes from SSIL and the arena probes, not from a bright flat ambient.
	# r16b §1, measured both ways and left alone: the dome is GOLD through 0-9 deg now (item 1), so the
	# sky half of the ambient warmed with it and the shade is no longer as cool as the light is warm —
	# `db` (b* of the shade minus b* of the sunlit faces, target <= -15) lost A4st (-17.3 -> -10.1) and
	# V6 (-15.0 -> -14.5). Both ways of cooling it cost more than they buy: dropping the sky's share to
	# 0.28 made `db` SHALLOWER on five of six cameras (the fixed #93a0bd is less blue than the dome's own
	# average), and raising it to 0.62 bought 1-2 units of `db` while pushing `shd_chroma` over its
	# ceiling (V7 11.5 -> 13.9) and `shd_p50` under its floor (S02city 0.099 -> 0.083) — both of which
	# are gated too. 0.45 stays, and the two `db` frames are reported as known misses.
	env.ambient_light_sky_contribution = 0.45
	env.ambient_light_color = ArtPalette.linear(Color("93a0bd"))
	env.ambient_light_energy = float(preset.get("sky_ambient", 0.35))
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	# Review r2: the city read dark. AgX at white 16.29 is very flat in the mids; 9.0 with a small
	# exposure lift keeps the golden key bright without clipping the sun disc. Lead r4: with the ambient
	# down at 0.27 the whole frame gained a stop, and V5/V7/V8 were clipping to white — pulled back.
	env.tonemap_exposure = 1.28
	env.tonemap_agx_white = 10.5
	env.tonemap_agx_contrast = 1.15

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = ArtPalette.linear(ArtPalette.HAZE_WARM)
	env.fog_light_energy = 0.85
	# Sun scattering through the haze is the aerial perspective the key art sells: towers past ~600 m
	# wash out to pale gold instead of staying dark silhouettes. Kept below 1 so near facades (<100 m)
	# do not lose their own colour.
	# city-art r14: 0.5 made the fog glow toward the sun hard enough to clip. Measured at the shipping
	# default it was 6.2 % of V7 on its own — a white-gold field around the sun exactly as the lead
	# described it — and it is a screen-wide wash, not a shaft. 0.12 keeps the warm forward-scatter the
	# aerial perspective needs without the field.
	env.fog_sun_scatter = 0.12
	env.fog_density = 0.0
	env.fog_depth_begin = 90.0
	env.fog_depth_end = 1600.0
	env.fog_depth_curve = 0.75
	# r15: 0.22 (rising to 0.45 with progress) put the warm fog colour over the sky itself. Measured at
	# tod 0.6 with the band just above the horizon: `skylo_hue` 357 deg (red) at 0.358 of fog over the
	# sky, 311 deg at 0.08 — the fog was the red, not the dome. The sky's own ramp supplies the warm
	# horizon; the fog only has to soften the far city into it.
	env.fog_sky_affect = 0.08
	env.fog_aerial_perspective = 0.28
	env.fog_height = 40.0
	env.fog_height_density = 0.0

	_apply_grade(env)
	return env


## Colour grade (ART.md §3): warm highlights, teal-violet shadows, mild contrast lift.
static func _apply_grade(env: Environment) -> void:
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.06
	var lut := grade_lut()
	if lut != null:
		env.adjustment_color_correction = lut


## Procedural 16^3 split-tone LUT. Returns null (and leaves the plain adjustment params) if the
## 3D texture cannot be created, which keeps the environment usable instead of failing hard.
static func grade_lut() -> Texture3D:
	var n := GRADE_SIZE
	var slices: Array[Image] = []
	slices.resize(n)
	for z in range(n):
		var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
		for y in range(n):
			for x in range(n):
				var c := Vector3(float(x), float(y), float(z)) / float(n - 1)
				img.set_pixel(x, y, _grade(c))
		slices[z] = img
	var tex := ImageTexture3D.new()
	if tex.create(Image.FORMAT_RGB8, n, n, n, false, slices) != OK:
		push_warning("CityEnvironment: could not build the colour-grade LUT; using plain adjustments")
		return null
	return tex


## Warm highlights (#FFCF8A-ish), teal-violet shadows (#3A3440 -> #4C4468), saturation-preserving.
static func _grade(c: Vector3) -> Color:
	var lum := clampf(c.dot(Vector3(0.2126, 0.7152, 0.0722)), 0.0, 1.0)
	var shadow := Color(0.97, 0.96, 1.03)      ## cool the darks slightly toward violet-teal
	var high := Color(1.03, 1.00, 0.94)        ## warm the brights (golden key)
	var t := smoothstep(0.15, 0.75, lum)
	var out := Color(
		c.x * lerpf(shadow.r, high.r, t),
		c.y * lerpf(shadow.g, high.g, t),
		c.z * lerpf(shadow.b, high.b, t))
	# Gentle S-curve so haze layers separate without crushing the hero silhouette.
	var s := out.r * out.r * (3.0 - 2.0 * out.r)
	out.r = lerpf(out.r, s, 0.18)
	s = out.g * out.g * (3.0 - 2.0 * out.g)
	out.g = lerpf(out.g, s, 0.18)
	s = out.b * out.b * (3.0 - 2.0 * out.b)
	out.b = lerpf(out.b, s, 0.18)
	return Color(clampf(out.r, 0.0, 1.0), clampf(out.g, 0.0, 1.0), clampf(out.b, 0.0, 1.0), 1.0)
