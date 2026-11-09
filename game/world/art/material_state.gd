class_name McMaterialState
extends RefCounted
## The city material library's STATE and its pushes (city-art r16 §6): the process-wide material
## cache, the per-uniform push lists (facade mask, haze, horizon band, wetness, sun, sky tint, detail
## distance) and the `set_*` entry points TimeOfDay drives. Split out of `material_library.gd`, which
## keeps the public `McMaterials` API and delegates here.

static var _mats: Dictionary = {}
static var _globals_ready: bool = false
## Materials that carry a `facade_mask` / `haze_far` uniform, collected as they are built so the
## load-time mask and the TimeOfDay haze ramp can be pushed to all of them in one place.
static var _facade_mats: Array[ShaderMaterial] = []
static var _haze_mats: Array[ShaderMaterial] = []
static var _band_mats: Array[ShaderMaterial] = []
static var _wet_mats: Array[ShaderMaterial] = []
static var _detail_mats: Array[ShaderMaterial] = []
static var _sun_mats: Array[ShaderMaterial] = []
static var _sun_dir := Vector3.UP
static var _sun_kill: float = 0.0
## r15 §4: the two sky colours a wet deck mirrors. The wet ground's reflection is ANALYTIC — SSR is off
## at shipping quality (r13 measured 1.75 ms of a 28 ms street frame) — so a wet surface evaluates the
## same horizon/zenith ramp the dome uses, along its reflected ray. Pushed by `set_sky_tint`.
static var _skytint_mats: Array[ShaderMaterial] = []
static var _sky_horizon: Color = ArtPalette.SKY_HORIZON
static var _sky_zenith: Color = ArtPalette.SKY_ZENITH
## shader instance id -> the uniform names it declares (`_has_uniform`).
static var _uniform_cache: Dictionary = {}
static var _facade_tex: Texture2D = null
static var _haze_near: Color = ArtPalette.HAZE_WARM
static var _haze_near_amount: float = 0.0
static var _haze_color: Color = ArtPalette.HAZE_FAR
static var _haze_amount: float = 0.0
static var _haze_band: Color = ArtPalette.SKYLINE_HAZE
static var _haze_gain: float = 0.62
static var _wet: float = 0.55
## city-art r13: past this distance every mc_* surface takes its cheap path. `NO_DETAIL` = off.
static var _detail_m: float = McMaterialRoles.NO_DETAIL
## city-art r13: past this distance a triplanar surface samples its dominant axis only.
static var _tri_m: float = McMaterialRoles.NO_DETAIL


## The shared material cache: one instance per role (or per variant key), so a model placed on twelve
## tiles is still one material.
static func cached(key: StringName) -> Material:
	return _mats.get(key)


static func cache(key: StringName, mat: Material) -> void:
	_mats[key] = mat


## Pushes this unit's load-time defaults into the declared globals. Safe to call any number of times.
static func ensure_globals() -> void:
	if _globals_ready:
		return
	_globals_ready = true
	for name in McMaterialRoles.GLOBALS:
		RenderingServer.global_shader_parameter_set(name, McMaterialRoles.GLOBALS[name])


## Collects a material into the facade-mask / far-haze / wetness push lists, if its SHADER declares
## those uniforms, and applies the state pushed so far. Materials are built lazily during the swap,
## which happens AFTER TimeOfDay has already run its first `_apply`, so a material that only received
## the push would sit at the shader defaults — the stored state is replayed onto every new material.
static func register(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	if _has_uniform(mat, &"facade_on") and not _facade_mats.has(mat):
		_facade_mats.append(mat)
		if _facade_tex != null:
			mat.set_shader_parameter(&"facade_mask", _facade_tex)
	if _has_uniform(mat, &"haze_near_amount") and not _haze_mats.has(mat):
		_haze_mats.append(mat)
		_push_haze(mat)
	# Review r9: `mc_skyline` carries `sky_band` but NOT `haze_near_amount`, so it never landed on the
	# haze list and `_push_haze` never reached it — the ring and the HLOD proxies kept the lavender
	# `ArtPalette.SKYLINE_HAZE` they were built with, in every vista, while TimeOfDay computed the sky's
	# own horizon colour and pushed it into a list that had no skyline material on it. Its own list.
	if _has_uniform(mat, &"sky_band") and not _band_mats.has(mat):
		_band_mats.append(mat)
		mat.set_shader_parameter(&"sky_band", _haze_band)
	if _has_uniform(mat, &"wet") and not _wet_mats.has(mat):
		_wet_mats.append(mat)
		mat.set_shader_parameter(&"wet", _wet)
	if _has_uniform(mat, &"sun_dir") and not _sun_mats.has(mat):
		_sun_mats.append(mat)
		mat.set_shader_parameter(&"sun_dir", _sun_dir)
		mat.set_shader_parameter(&"sun_face_kill", _sun_kill)
	if _has_uniform(mat, &"sky_horizon") and not _skytint_mats.has(mat):
		_skytint_mats.append(mat)
		mat.set_shader_parameter(&"sky_horizon", _sky_horizon)
		mat.set_shader_parameter(&"sky_zenith", _sky_zenith)
	if _has_uniform(mat, &"detail_m") and not _detail_mats.has(mat):
		_detail_mats.append(mat)
		mat.set_shader_parameter(&"detail_m", _detail_m)
		mat.set_shader_parameter(&"tri_m", _tri_m)


## Does this material's shader DECLARE `name`? `get_shader_parameter` cannot answer that: it only
## reports a value once one has been set on the material, so testing it for null silently classified
## every material as "no such uniform" and left the haze / wetness push lists permanently empty (the
## layered aerial perspective sat at its shader defaults for r3-r5 without a single error). The
## uniform list is read once per shader and cached by RID.
static func _has_uniform(mat: ShaderMaterial, name: StringName) -> bool:
	var shader := mat.shader
	if shader == null:
		return false
	var key := shader.get_instance_id()
	var names: Variant = _uniform_cache.get(key)
	if names == null:
		var list: PackedStringArray = []
		for u in shader.get_shader_uniform_list(true):
			list.append(String((u as Dictionary).get("name", "")))
		_uniform_cache[key] = list
		names = list
	return (names as PackedStringArray).has(String(name))


## Review r3 §1: the top-down building mask every facade material samples. Built once from the design
## layout by CityArt; without it a viaduct parapet would grow the same window grid as a tower.
static func set_facade_mask(tex: Texture2D) -> void:
	_facade_tex = tex
	for m in _facade_mats:
		m.set_shader_parameter(&"facade_mask", tex)


## Review r3 §3: the layered aerial perspective every city material applies itself (the built-in depth
## fog saturates at 1.3 km and flattened the far band). TimeOfDay drives both bands so they swing with
## the sun and the storm. `band` is the horizon colour the distant ring dissolves into.
static func set_haze(near: Color, near_amount: float, far: Color, far_amount: float,
		band: Color, gain: float) -> void:
	_haze_near = near
	_haze_near_amount = near_amount
	_haze_color = far
	_haze_amount = far_amount
	_haze_band = band
	_haze_gain = gain
	for m in _haze_mats:
		_push_haze(m)
	for m in _band_mats:
		m.set_shader_parameter(&"sky_band", band)


static func _push_haze(m: ShaderMaterial) -> void:
	m.set_shader_parameter(&"haze_near", _haze_near)
	m.set_shader_parameter(&"haze_near_amount", _haze_near_amount)
	m.set_shader_parameter(&"haze_far", _haze_color)
	m.set_shader_parameter(&"haze_far_amount", _haze_amount)
	m.set_shader_parameter(&"haze_gain", _haze_gain)


## City-wide wetness (lead 12:25): how much of the road and deck surfaces hold water, so the neon,
## windows and dusk sky land in them for post-render's SSR. 0 = dry, 1 = every basin full. Materials
## carrying a `wet` uniform are collected as they are built, exactly like the haze list, so TimeOfDay
## can swing the whole city on one number.
static func set_wetness(amount: float) -> void:
	_wet = clampf(amount, 0.0, 1.0)
	for m in _wet_mats:
		m.set_shader_parameter(&"wet", _wet)


## city-art r14 §2: where the sun is, and how hard a sunlit face's lit windows are suppressed. Pushed
## to every material that declares `sun_dir` (see `mc_sun.gdshaderinc`), collected the same way the
## haze and wetness lists are, so a material built after TimeOfDay's first `_apply` still gets it.
static func set_sun(dir: Vector3, face_kill: float) -> void:
	_sun_dir = dir.normalized()
	_sun_kill = clampf(face_kill, 0.0, 1.0)
	for m in _sun_mats:
		m.set_shader_parameter(&"sun_dir", _sun_dir)
		m.set_shader_parameter(&"sun_face_kill", _sun_kill)


## The sun direction and the sunlit-face suppression currently pushed (tests and tools read them).
static func sun() -> Dictionary:
	return {"dir": _sun_dir, "kill": _sun_kill}


## city-art r15 §4: the sky colours a wet deck mirrors. Pushed to every material that declares
## `sky_horizon` (the wet-ground analytic reflection in `mc_surface` / `mc_road`), collected the same
## way the haze, wetness and sun lists are, so a material built after TimeOfDay's first `_apply`
## still gets it. Colours are sRGB — the uniforms are `: source_color` and the engine converts.
static func set_sky_tint(horizon: Color, zenith: Color) -> void:
	_sky_horizon = horizon
	_sky_zenith = zenith
	for m in _skytint_mats:
		m.set_shader_parameter(&"sky_horizon", _sky_horizon)
		m.set_shader_parameter(&"sky_zenith", _sky_zenith)


## The sky tint currently pushed (tests and tools read it).
static func sky_tint() -> Dictionary:
	return {"horizon": _sky_horizon, "zenith": _sky_zenith}


## The wetness currently pushed (tests and tools read it; the shader side is the `wet` uniform).
static func wetness() -> float:
	return _wet


## city-art r13: the detail distance. Every `mc_*` surface that declares `detail_m` switches to its
## cheap path past this many metres from the camera — one texture fetch, no procedural detail, the
## dissolved window grid. `NO_DETAIL` (the default) is far enough that nothing takes it, so the A/B is
## one call and a scene that never pushes it renders exactly as it did before.
static func set_detail_distance(metres: float, triplanar_m: float = -1.0) -> void:
	_detail_m = maxf(metres, 0.0)
	if triplanar_m >= 0.0:
		_tri_m = triplanar_m
	for m in _detail_mats:
		m.set_shader_parameter(&"detail_m", _detail_m)
		m.set_shader_parameter(&"tri_m", _tri_m)


## The triplanar cut-off currently pushed (tests and tools read it).
static func triplanar_distance() -> float:
	return _tri_m


## The detail distance currently pushed (tests and tools read it).
static func detail_distance() -> float:
	return _detail_m


## How many materials are listening to the mask / haze / horizon-band / wetness pushes (evidence for
## the status file, and the assertion that keeps the r9 `sky_band` bug from coming back silently).
static func registered() -> Dictionary:
	return {"facade": _facade_mats.size(), "haze": _haze_mats.size(),
		"band": _band_mats.size(), "wet": _wet_mats.size(), "detail": _detail_mats.size(),
		"sun": _sun_mats.size(), "skytint": _skytint_mats.size()}


## The horizon-band colour currently pushed; `skyline_variant` seeds a new material from it.
static func haze_band() -> Color:
	return _haze_band
