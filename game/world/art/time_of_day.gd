class_name TimeOfDay
extends Node3D
## Time-of-day controller (city-art). The one node in group &"time_of_day" (CONTRACTS §7):
##   set_progress(p: float)          0 = mission start, 1 = boss; tweens itself over ~4 s
##   set_storm(amount, seconds)      storm cloud cover around the Spire crown
##   set_progress_immediate(p)       no tween (tools, captures, tests)
## The flow unit drives `set_progress` through the group as spires fall (ART.md §3 escalation):
## sun elevation 20 deg -> 6 deg, haze warmer/redder, windows lit 40 % -> 75 %, storm 0 -> 100 %.

const PROGRESS_SECONDS := 4.0

## --- the ramp (ART.md §3, review r2) ---------------------------------------
const ELEV_START_DEG := 18.0
const ELEV_END_DEG := 5.0
const SUN_AZIMUTH_DEG := 315.0        ## north-west: most vistas get side/back light
const SUN_ENERGY_START := 1.4   ## r14: 2.3 put every sunlit face over 248/255
const SUN_ENERGY_END := 1.05
## city-art r14 §2 (lead): "at golden hour a sunlit wall shows few lit windows". 0.45 lit 45 % of the
## cells at the mission start and the midground towers glittered in broad daylight; the key art's
## golden hour is sparse and its night is dense.
const LIT_START := 0.12
const LIT_END := 0.72
## How hard a face the sun is on suppresses its own lit windows (see `mc_sun.gdshaderinc`). Near 1
## through the golden hour, easing off under the storm when the sun is at 5 degrees and the city is
## lit by its own lights.
const SUN_FACE_KILL_START := 0.92
const SUN_FACE_KILL_END := 0.35
const AMBIENT_START := 1.0
## r6: the storm dome is a large bright violet source, so the fill RISES into the boss instead of
## falling with the sun — at 0.70 the p1.0 frame was red sunlit faces against black shade, with no
## midtones anywhere.
const AMBIENT_END := 1.05
const FOG_WARM := ArtPalette.HAZE_WARM
const FOG_DUSK := Color("e08a52")
const SKY_HORIZON_DUSK := Color("f5b070")   ## r15: #f5955a reads as hue 51-57, this as 58-67
## r15: #242a56 is L* 19 — dark enough that AgX rotates it about +60 deg on the way to the frame, and
## the zenith measured 342 deg (magenta) instead of blue at tod 0.6. L* 33 keeps it out of the rotation
## (the sky-only probe: the dome's own 25-70 deg band goes 265 deg at tod 0 and 342 deg at tod 0.6,
## and the ONLY difference between those two is this colour's value). The storm's violet comes from
## `SKY_MID_STORM` and the storm cloud tint, not from making the zenith dark.
const SKY_ZENITH_DUSK := Color("3a4a80")
const SKY_MID_STORM := Color("4b3d70")   ## r6: the storm dome is slate violet, not lit magenta
const CLOUD_DUSK := ArtPalette.CLOUD_DUSK
const STORM_AT_END := 1.0             ## storm cover reached at progress 1
## Review r2: violet belongs to the storm. It ramps in over the last third of the mission only, so
## progress 0..0.66 stays golden dusk.
const STORM_FROM := 0.66
## r16b §1: where the COLOUR ramp starts. Every colour below used to be lerped by `progress`, so half
## way to the boss the key was already half the ember (#ff9d66), the fog was half #e08a52 and the
## horizon was half #f5b070 — measured on the r15f2 probe as `lit_hue` 16-46 and `skylo_hue` 3-64 at
## `--tod=0.5`, against the key art's 45-75 and 65-85. ART.md §1's escalation is the STORM's ("as
## spires fall the light ages toward dusk and a violet storm gathers"), and the storm starts at
## STORM_FROM; the colour ramp now follows the same curve, so the golden hour is still golden at the
## trailer's combat time. `progress` still drives everything that is a QUANTITY (elevation, energy,
## lit fraction, fog depth, wetness) — only the hues wait.
const DUSK_FROM := 0.45
## Street wetness (lead 12:25): damp asphalt through the golden hour, rain-slick under the storm.
const WET_START := 0.42
const WET_STORM := 0.95
## Review r9: how far the horizon band the far city dissolves into is pulled off the sky's chroma
## toward its own grey. At 0 the distant masses took the sky's full saturation and read as a second,
## brighter sky; the key art's distance is the sky's HUE at a lower chroma.
const RING_BAND_DESAT := 0.34

var progress: float = 0.0
var storm: float = 0.0
var lit_fraction: float = LIT_START   ## what the mc_window global is currently set to

var _target_progress: float = 0.0
var _target_storm: float = 0.0
var _progress_rate: float = 0.0
var _storm_rate: float = 0.0
var _env: Environment
var _sun: DirectionalLight3D
var _storm_node: Node
var _world_env: WorldEnvironment
var _sky_mat: ShaderMaterial
var _preset: Dictionary = {}
var _flash: float = 0.0


func _ready() -> void:
	add_to_group(&"time_of_day")
	McMaterials.ensure_globals()
	_preset = ArtQuality.get_preset()
	_resolve_nodes()
	if _world_env != null and _env == null:
		_env = CityEnvironment.build(_preset)
		_world_env.environment = _env
	# Lead 12:25: the WorldEnvironment carries the shared post stack, so anything post-render appended
	# to `CityEnvironment.compositor()` runs on the city, the vistas and the look-dev scenes alike.
	if _world_env != null:
		_world_env.compositor = CityEnvironment.compositor()
	ArtQuality.apply(_env, _sun, _preset)
	_sky_mat = CityEnvironment.sky_uniforms(_env)
	var gi := get_node_or_null(^"GiController") as GiController
	if gi != null:
		gi.bind(_env)
	var forced := Game.flag("tod")
	set_progress_immediate(float(forced) if forced.is_valid_float() else 0.0)


func _resolve_nodes() -> void:
	_world_env = get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if _world_env != null:
		_env = _world_env.environment
	_sun = get_node_or_null(^"Sun") as DirectionalLight3D
	_storm_node = get_node_or_null(^"Storm")
	if _world_env == null or _sun == null:
		push_error("TimeOfDay: environment.tscn must provide WorldEnvironment and Sun children")


func _process(delta: float) -> void:
	var real := Feel.real_delta(delta)
	if not is_equal_approx(_target_progress, progress):
		progress = move_toward(progress, _target_progress, _progress_rate * real)
		_apply()
	if not is_equal_approx(_target_storm, storm):
		storm = move_toward(storm, _target_storm, _storm_rate * real)
		_apply_storm()
	if _flash > 0.0:
		_flash = maxf(_flash - real * 4.0, 0.0)
		_apply_flash()
	RenderingServer.global_shader_parameter_set(&"mc_time", float(Time.get_ticks_msec()) * 0.001)


## CONTRACTS §7 hook. p in 0..1; the controller tweens itself over PROGRESS_SECONDS.
func set_progress(p: float) -> void:
	_target_progress = clampf(p, 0.0, 1.0)
	_progress_rate = absf(_target_progress - progress) / PROGRESS_SECONDS
	if is_equal_approx(_progress_rate, 0.0):
		return
	if _target_progress >= 1.0:
		set_storm(STORM_AT_END, PROGRESS_SECONDS)


func set_progress_immediate(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	_target_progress = progress
	_progress_rate = 0.0
	storm = storm_for(progress)
	_target_storm = storm
	_storm_rate = 0.0
	_apply()
	_apply_storm()


## Storm cover as a function of mission progress: nothing until STORM_FROM, then a smooth ramp to full.
static func storm_for(p: float) -> float:
	return smoothstep(STORM_FROM, 1.0, clampf(p, 0.0, 1.0)) * STORM_AT_END


## r16b §1: how far the COLOURS have aged toward the ember, 0..1. Nothing until DUSK_FROM, so the
## golden hour holds through the mission's middle, then the ember arrives with the storm.
static func dusk_for(p: float) -> float:
	return smoothstep(DUSK_FROM, 1.0, clampf(p, 0.0, 1.0))



## CONTRACTS §7 hook. Storm cloud cover around the Spire crown, 0..1.
func set_storm(amount: float, seconds: float = PROGRESS_SECONDS) -> void:
	_target_storm = clampf(amount, 0.0, 1.0)
	_storm_rate = absf(_target_storm - storm) / maxf(seconds, 0.01)


## CONTRACTS §7 hook. A lightning strike at a world position (storm crown, boss telegraphs).
func lightning_at(pos: Vector3) -> void:
	_flash = 1.0
	if _storm_node != null and _storm_node.has_method(&"strike"):
		_storm_node.call(&"strike", pos)
	_apply_flash()


func _apply_flash() -> void:
	if _env == null:
		return
	# r15: 2.6 was tuned when `sky_ambient` was 0.33. It is 1.90 now, so a full flash was driving the
	# ambient to ~4.9 and the boss-time frames clipped (V7 8.3 %, V8 12.1 % at `--tod=1.0`, against
	# 6.7 % and 6.2 % at r14). The flash has to stay a FLASH — a brief lift over a base that is already
	# readable — not a second exposure.
	_env.ambient_light_energy = lerpf(_ambient(), _ambient() * 1.6, _flash)
	if _sun != null:
		_sun.light_energy = lerpf(_sun_energy(), _sun_energy() * 1.5, _flash * 0.4)


func _sun_energy() -> float:
	return lerpf(SUN_ENERGY_START, SUN_ENERGY_END, progress)


func _ambient() -> float:
	return lerpf(AMBIENT_START, AMBIENT_END, progress) * float(_preset.get("sky_ambient", 0.35))


## Sun elevation 20 deg -> 6 deg on a fixed north-west azimuth, plus haze, sky and window-lit ramp.
## r16b: the QUANTITIES follow `progress`, the COLOURS follow `dusk` (see DUSK_FROM).
func _apply() -> void:
	var elev := deg_to_rad(lerpf(ELEV_START_DEG, ELEV_END_DEG, progress))
	var dusk := dusk_for(progress)
	var az := deg_to_rad(SUN_AZIMUTH_DEG)
	var to_sun := Vector3(cos(elev) * sin(az), sin(elev), -cos(elev) * cos(az)).normalized()
	if _sun != null:
		var z_axis := to_sun
		var x_axis := Vector3.UP.cross(z_axis).normalized()
		if x_axis.length_squared() < 1e-6:
			x_axis = Vector3.RIGHT
		_sun.transform = Transform3D(Basis(x_axis, z_axis.cross(x_axis).normalized(), z_axis),
			Vector3.ZERO)
		_sun.light_color = ArtPalette.mix_linear(ArtPalette.SUN_COLOR, ArtPalette.SUN_COLOR_DUSK, dusk)
		_sun.light_energy = _sun_energy()
		_sun.light_angular_distance = 0.4   ## r14: 0.7 spread the specular into a blob
	lit_fraction = lerpf(LIT_START, LIT_END, progress)
	RenderingServer.global_shader_parameter_set(&"mc_lit_fraction", lit_fraction)
	McMaterials.set_sun(to_sun, lerpf(SUN_FACE_KILL_START, SUN_FACE_KILL_END, progress))
	if _env != null:
		_env.ambient_light_energy = _ambient()
		_env.fog_light_color = FOG_WARM.lerp(FOG_DUSK, dusk).srgb_to_linear()
		_env.fog_light_energy = lerpf(0.85, 1.15, progress)
		_env.fog_depth_begin = lerpf(90.0, 30.0, progress)
		_env.fog_sky_affect = lerpf(0.08, 0.18, dusk)   ## r15: was 0.22 -> 0.45; see environment.gd
	if _sky_mat != null:
		_sky_mat.set_shader_parameter(&"sun_dir", to_sun)
		_sky_mat.set_shader_parameter(&"horizon",
			ArtPalette.srgb_mix(ArtPalette.SKY_HORIZON, SKY_HORIZON_DUSK, dusk))
		_sky_mat.set_shader_parameter(&"horizon_away",
			ArtPalette.srgb_mix(ArtPalette.SKY_HORIZON_AWAY, SKY_HORIZON_DUSK, dusk * 0.7))
		_sky_mat.set_shader_parameter(&"zenith",
			ArtPalette.srgb_mix(ArtPalette.SKY_ZENITH, SKY_ZENITH_DUSK, dusk))
		# The mid dome only turns violet with the storm; before that it is golden dusk.
		_sky_mat.set_shader_parameter(&"mid_sky",
			ArtPalette.srgb_mix(ArtPalette.SKY_MID, SKY_MID_STORM, storm * 0.9))
		_sky_mat.set_shader_parameter(&"haze_gain", lerpf(0.8, 0.5, dusk))
		_sky_mat.set_shader_parameter(&"sun_intensity", lerpf(3.0, 2.2, progress))
		_push_sky_cover()
	# r15 §4: the wet ground mirrors the sky, so it needs the sky's own two colours — the same numbers
	# the dome was just given, pushed onto every material that declares `sky_horizon`.
	McMaterials.set_sky_tint(
		ArtPalette.srgb_mix(ArtPalette.SKY_HORIZON, SKY_HORIZON_DUSK, dusk),
		ArtPalette.srgb_mix(ArtPalette.SKY_ZENITH, SKY_ZENITH_DUSK, dusk))
	# Review r3 §3: the layered aerial perspective lives in the shaders (Godot's depth fog is one
	# colour over one curve and flattened everything past 1.3 km), so it is pushed with the rest of the
	# ramp: warm gold through the near/mid band, cool violet-blue beyond it, and violet with the storm.
	McMaterials.set_haze(
		ArtPalette.srgb_mix(ArtPalette.HAZE_WARM, FOG_DUSK, dusk * 0.8), lerpf(0.40, 0.50, progress),
		ArtPalette.srgb_mix(ArtPalette.HAZE_FAR, ArtPalette.HAZE_FAR_STORM, storm),
		lerpf(0.58, 0.70, progress),
		_ring_band(progress, storm), lerpf(0.55, 0.46, progress))
	# Lead 12:25: the streets stay damp through the golden hour and the rain proper arrives with the
	# storm, so the reflections post-render's SSR picks up build as the mission does.
	McMaterials.set_wetness(lerpf(WET_START, WET_STORM, maxf(progress * 0.35, storm)))


## The colour the distant ring dissolves into (review r3 §3, retuned in r9). It has to be the sky's OWN
## horizon value or the ring detaches from it: a fixed warm grey sat on a violet storm sky as a pale band
## across the whole horizon, and the lavender `SKYLINE_HAZE` it fell back to (see `McMaterials.
## _register` — the push never reached `mc_skyline`) read as periwinkle boxes pasted over an amber sky
## in all eight vistas. The ring is seen near the horizon in every direction, so the two horizon colours
## are averaged, pulled toward the storm as it gathers, then DESATURATED: distance takes a mass toward
## the sky's hue but not all the way to its chroma, which is what keeps the far city a silhouette
## instead of a second, brighter sky.
static func _ring_band(progress: float, storm: float) -> Color:
	var dusk := dusk_for(progress)
	var band := ArtPalette.srgb_mix(
		ArtPalette.srgb_mix(ArtPalette.SKY_HORIZON, SKY_HORIZON_DUSK, dusk),
		ArtPalette.srgb_mix(ArtPalette.SKY_HORIZON_AWAY, SKY_HORIZON_DUSK, dusk * 0.7), 0.5)
	band = ArtPalette.srgb_mix(band, CLOUD_DUSK, storm * 0.55)
	var grey := (band.r + band.g + band.b) / 3.0
	return ArtPalette.srgb_mix(band, Color(grey, grey, grey), RING_BAND_DESAT)


func _apply_storm() -> void:
	if _storm_node != null and _storm_node.has_method(&"set_cover"):
		_storm_node.call(&"set_cover", storm)
	_push_sky_cover()
	if _env != null and bool(_preset.get("volumetric", false)):
		_env.volumetric_fog_density = lerpf(
			float(_preset.get("vol_density", 0.002)), float(_preset.get("vol_density", 0.002)) * 2.0, storm)


## Cloud cover, storm tint and how far up the dome the deck reaches. Driven by BOTH progress and
## storm, so it is pushed from `_apply` (every progress step) and from `_apply_storm` (every storm
## step) rather than from one of them.
func _push_sky_cover() -> void:
	if _sky_mat == null:
		return
	# r15: the cover ramp came down from 0.58 -> 0.90. At 0.77 (tod 0.6) the deck's hard threshold
	# saturated and the whole dome took the cloud colour; the new soft `mass` keeps its contrast at any
	# cover, but a golden-hour sky is not eight-tenths covered either — the key art's is sparse enough
	# that the blue above the banks is sky.
	# r16b §1: the cover is part of the COLOUR ramp, not a quantity. Driven by `progress` it was 0.60 at
	# tod 0.5 against 0.40 at tod 0, and the extra deck is what put the 0-9 deg band at hue 47-56
	# instead of 65-70 (the key art's own sky measures hue 57-64 at chroma 26-32 across its whole
	# visible band): the cloud BODY is violet-grey, so more cloud is a less golden sky. It now follows
	# `dusk`, like every other colour, and only the storm thickens it.
	var cover_t := maxf(dusk_for(progress), storm)
	_sky_mat.set_shader_parameter(&"cloud_cover", lerpf(0.40, 0.80, cover_t))
	_sky_mat.set_shader_parameter(&"cloud_storm", storm)
	# The storm deck reaches higher and is thicker; the golden-hour one sits on the towers.
	_sky_mat.set_shader_parameter(&"deck_top", lerpf(0.26, 0.52, storm))
	_sky_mat.set_shader_parameter(&"deck_span", lerpf(0.44, 0.62, storm))

