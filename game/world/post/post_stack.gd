class_name PostStack
extends Node
## The cinematic post stack (post-render unit, brief `briefs/post-render.md`).
##
## One node, self-installing: it finds the active `Camera3D` and owns `Camera3D.compositor` (in 4.7.2 the
## `Compositor` lives on the camera, not on `Environment`), finds city-art's WorldEnvironment through the
## `&"time_of_day"` group and owns the grade, exposure and glow rows of it. Everything is load-time
## (godot-tech §4.6: never add a CompositorEffect or change a mip chain mid-game).
##
##   `--no-post`            disables the whole stack — this is the "before" half of every A/B sheet.
##   `--post=<a,b,c>`       enables only the named effects (lens, bloom, shafts, dof) for isolation.
##   `--post-tune=k:v,...`  measurement hook: sets Environment properties for one run (see _apply_tune).
##
## Settings keys honoured (CONTRACTS §2): `fx_lens` (vignette + fringe), `fx_film_grain`, and
## `photosensitive`, which removes grain, the colour fringe and the anamorphic streaks entirely.

## Every effect this stack can own, in render order. Shafts add light first so they bloom; depth of
## field blurs before bloom; the lens is last so grain and vignette sit on top of everything.
const ORDER: Array[StringName] = [&"shafts", &"dof", &"bloom", &"lens"]

var enabled: bool = true
var preset: Dictionary = {}
var effects: Dictionary = {}          ## StringName -> CompositorEffect (only the enabled ones)
var sun_uv := Vector2(0.5, 0.5)       ## sun position in screen uv; shafts read this
var sun_visible: float = 0.0          ## 1 when the sun is in front of the camera
var bound_environment: Environment = null
var cinematic: bool = false           ## DOF is on only while a cinematic shot holds the camera

var _compositor: Compositor
var _grade: PostGrade
var _camera: Camera3D
var _time_of_day: Node
var _sun: DirectionalLight3D
var _world_env: WorldEnvironment
var _only: Array[StringName] = []
var _tune: Dictionary = {}
var _env_baseline: Dictionary = {}
var _env_props: Dictionary = {}   ## Environment property names, cached (GDScript `in` does not work on Object)
var _last_progress: float = -1.0
var _warned_no_env: bool = false


func _ready() -> void:
	add_to_group(&"post_stack")
	process_mode = Node.PROCESS_MODE_ALWAYS
	preset = PostPresets.get_preset()
	enabled = not Game.has_flag("no-post")
	_only = _parse_only(Game.flag("post"))
	_grade = PostGrade.new()
	_tune = _parse_tune(Game.flag("post-tune"))
	_build_effects()
	if enabled:
		print("POST stack on: effects=%s" % [effects.keys()])
	else:
		print("POST stack off (--no-post)")


## The effects for this preset, in render order. Disabled ones are simply not in the Compositor, so an
## off effect costs nothing at all (unlike `enabled = false`, which still allocates its textures).
func _build_effects() -> void:
	effects.clear()
	_compositor = Compositor.new()
	if not enabled:
		return
	var row := preset
	var list: Array[CompositorEffect] = []
	if _want(&"shafts") and bool(row[&"shafts"]):
		var shafts := PostSunShafts.new()
		shafts.strength = float(row[&"shaft_strength"])
		shafts.steps = int(row[&"shaft_steps"])
		effects[&"shafts"] = shafts
		list.append(shafts)
	if _want(&"dof") and bool(row[&"dof"]):
		var dof := PostDof.new()
		dof.max_blur = float(row[&"dof_blur"])
		effects[&"dof"] = dof
		list.append(dof)
	if _want(&"bloom") and bool(row[&"bloom"]):
		var bloom := PostBloom.new()
		bloom.configure(row)
		effects[&"bloom"] = bloom
		list.append(bloom)
	if _want(&"lens"):
		var lens := PostLens.new()
		lens.vignette = float(row[&"vignette"])
		lens.fringe = float(row[&"fringe"])
		lens.grain = float(row[&"grain"])
		lens.sharpen = float(row[&"sharpen"])
		effects[&"lens"] = lens
		list.append(lens)
	_compositor.compositor_effects = list
	_apply_settings()


func _process(_delta: float) -> void:
	if not enabled:
		return
	_bind_environment()
	_attach_camera()
	_update_grade()
	_update_sun()
	_update_cinematic()


## city-art's environment arrives with the city, which may be a frame or two after this node. Bind once
## and then only touch the grade, so nothing here fights TimeOfDay's own per-frame writes.
func _bind_environment() -> void:
	if bound_environment != null:
		return
	if _time_of_day == null:
		_time_of_day = get_tree().get_first_node_in_group(&"time_of_day")
		if _time_of_day == null:
			return
	_world_env = _time_of_day.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	_sun = _time_of_day.get_node_or_null(^"Sun") as DirectionalLight3D
	if _world_env == null or _world_env.environment == null:
		if not _warned_no_env:
			_warned_no_env = true
			push_warning("PostStack: the time_of_day node has no WorldEnvironment yet; retrying")
		return
	bound_environment = _world_env.environment
	_snapshot_environment()
	retune(_tune)
	_update_grade()
	Settings.changed.connect(_on_setting)


## A full snapshot of the Environment as city-art left it, so the look-dev bracket harness
## (`--post-bracket`) can restore between candidates instead of drifting.
func _snapshot_environment() -> void:
	_env_baseline.clear()
	for p in bound_environment.get_property_list():
		var key: String = p["name"]
		var usage: int = p["usage"]
		if usage & PROPERTY_USAGE_CATEGORY or usage & PROPERTY_USAGE_GROUP:
			continue
		_env_props[StringName(key)] = true
		_env_baseline[key] = bound_environment.get(key)


## Restores city-art's Environment and re-applies this unit's rows. Look-dev only: production never
## re-applies renderer state after load (godot-tech §4.6).
func restore_environment() -> void:
	if bound_environment == null:
		return
	for key: String in _env_baseline:
		bound_environment.set(key, _env_baseline[key])
	_apply_renderer_settings(bound_environment)


## Applies a set of `key:value` strings to the bound Environment and forces the grade to rebuild.
## Used by the bracket harness; see `_parse_tune` for the command-line form.
func retune(tune: Dictionary) -> void:
	restore_environment()
	_last_progress = -1.0
	for key: StringName in tune:
		var raw: String = tune[key]
		if String(key).begins_with("grade_"):
			if not _grade.override(key, raw):
				push_warning("PostStack: unknown grade key '%s'" % key)
			continue
		if key in [&"contrast", &"saturation", &"grade_strength"]:
			preset[key] = float(raw)
			continue
		# `lens_<prop>` writes straight into the lens pass (grain, sharpen, vignette, fringe,
		# time_offset, legacy_grain), which is not an Environment row. city-art r16b §2 A/Bs the film
		# grain against the diagonal hatch with it: `--post-tune=lens_grain:0` is one arm and
		# `lens_time_offset:600,lens_legacy_grain:1` the other.
		if String(key).begins_with("lens_"):
			var lens := effects.get(&"lens") as PostLens
			if lens == null:
				push_warning("PostStack: no lens pass to tune '%s'" % key)
				continue
			lens.set(String(key).substr(5), float(raw))
			continue
		if not _env_props.has(key):
			push_warning("PostStack: Environment has no property '%s'" % key)
			continue
		bound_environment.set(key, float(raw) if raw.is_valid_float() else Color(raw))
	print("POST retune %s" % [tune])


## The renderer rows this unit owns at runtime. Every value is in `PostPresets` and repeated verbatim in
## `status/post-render.md` under "Requests" so the owning files (city-art's environment.gd / quality.gd)
## can hold the same numbers and this override becomes a no-op.
func _apply_renderer_settings(env: Environment) -> void:
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = float(preset[&"exposure"])
	env.tonemap_agx_white = float(preset[&"agx_white"])
	env.tonemap_agx_contrast = float(preset[&"agx_contrast"])
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.0
	# This stack's own bloom supersedes the engine glow, which at hdr_threshold 1.45 bloomed almost
	# nothing and, at a low threshold, washes the whole frame instead of haloing the sources. With the
	# compute bloom off (low preset, or `--post=` isolation) the engine glow is the fallback, retuned to
	# this unit's threshold so the low preset still haloes the neon and the tether.
	if effects.has(&"bloom"):
		env.glow_enabled = false
	else:
		# Screen blend at a low threshold is a full-frame wash, not a bloom — that is what made the first
		# fallback look worse than no bloom at all. Additive, dimmer and above 1.0 keeps it a halo.
		env.glow_enabled = true
		env.glow_hdr_threshold = 1.15
		env.glow_intensity = 0.35
		env.glow_strength = 1.0
		env.glow_bloom = 0.05
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE


## The grade cube follows `TimeOfDay.progress` (0 = dusk, 1 = storm). Rebuilt only when the ramp moves,
## which is a 2.2 ms cost paid during the 4 s progress tween and never in a fight.
func _update_grade() -> void:
	if bound_environment == null or _grade == null:
		return
	var progress := _progress()
	if is_equal_approx(progress, _last_progress):
		return
	_last_progress = progress
	var cube := _grade.texture_for(progress, preset)
	if cube != null:
		bound_environment.adjustment_color_correction = cube


## TimeOfDay.progress, read defensively: the group contract says a `&"time_of_day"` node exists, not that
## it is city-art's class, so a look-dev stand-in without the property must not take the frame down.
func _progress() -> float:
	if _time_of_day == null:
		return 0.0
	var raw: Variant = _time_of_day.get(&"progress")
	if raw is float or raw is int:
		return clampf(float(raw), 0.0, 1.0)
	return 0.0


## Screen-space sun position for the shafts. A directional light's +Z axis points at the sun.
func _update_sun() -> void:
	var shafts := effects.get(&"shafts") as PostSunShafts
	if shafts == null or _camera == null or _sun == null:
		return
	var to_sun := _sun.global_basis.z.normalized()
	var facing := -_camera.global_basis.z
	var align := facing.dot(to_sun)
	sun_visible = clampf((align - 0.1) / 0.4, 0.0, 1.0)
	var far_point := _camera.global_position + to_sun * 8000.0
	if _camera.is_position_behind(far_point):
		sun_visible = 0.0
	sun_uv = _camera.unproject_position(far_point) / Vector2(_camera.get_viewport().get_visible_rect().size)
	shafts.sun_uv = sun_uv
	shafts.sun_visible = sun_visible


## Turns the whole stack on or off at runtime by detaching the Compositor. Used by the isolation
## harness to A/B the GPU cost inside one run; `enabled` still gates `_process` entirely.
func set_active(on: bool) -> void:
	enabled = on
	if on and _camera == null:
		_camera = get_viewport().get_camera_3d()
	if _camera != null:
		_camera.compositor = _compositor if on else null
	set_process(on)


## Re-points the Compositor when the active camera changes (the vista harness swaps cameras).
func _attach_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam == _camera:
		return
	_camera = cam
	if _compositor != null:
		cam.compositor = _compositor
	var dof := effects.get(&"dof") as PostDof
	if dof != null:
		dof.near_plane = _camera.near
		dof.far_plane = _camera.far


## Accessibility (CONTRACTS §2). `photosensitive` removes the three effects that shimmer or split
## colour: film grain, the chromatic fringe and the anamorphic streaks. It is not optional, so it wins
## over the individual `fx_*` keys.
func _apply_settings() -> void:
	var photo := _setting(&"photosensitive", false)
	var lens := effects.get(&"lens") as PostLens
	if lens != null:
		var lens_on := _setting(&"fx_lens", true)
		lens.vignette = float(preset[&"vignette"]) if lens_on else 0.0
		lens.fringe = 0.0 if (photo or not lens_on) else float(preset[&"fringe"])
		lens.grain = 0.0 if photo else float(preset[&"grain"])
		lens.sharpen = float(preset[&"sharpen"])
		if not _setting(&"fx_film_grain", true):
			lens.grain = 0.0
	var bloom := effects.get(&"bloom") as PostBloom
	if bloom != null:
		bloom.streak = 0.0 if photo else float(preset[&"streak"])
	var shafts := effects.get(&"shafts") as PostSunShafts
	if shafts != null:
		shafts.strength = float(preset[&"shaft_strength"])


func _on_setting(key: StringName) -> void:
	if key in [&"photosensitive", &"fx_lens", &"fx_film_grain"]:
		_apply_settings()


## `fx_lens` and `fx_film_grain` are requested from the lead (see `## Requests`): until they are in
## core/settings.gd DEFAULTS, `Settings.get_value` returns null and must not be cast straight to bool.
func _setting(key: StringName, fallback: bool) -> bool:
	var v: Variant = Settings.get_value(key)
	return fallback if v == null else bool(v)


## Cinematic depth of field (brief §1: drop-in, collapse, boss intro/death — never in play). Flow and
## camera-aim call this around a beat; `_update_cinematic` also follows `CameraRig.is_cinematic()` so a
## shot list that is already running does not need a second caller.
func set_cinematic(on: bool, focus_distance: float = 0.0) -> void:
	cinematic = on
	var dof := effects.get(&"dof") as PostDof
	if dof != null:
		dof.active = on
		if focus_distance > 0.0:
			dof.focus = focus_distance


func _update_cinematic() -> void:
	var rig := Game.camera_rig
	if rig == null or not rig.has_method(&"is_cinematic"):
		return
	var on := bool(rig.call(&"is_cinematic"))
	if on == cinematic:
		return
	var dof := effects.get(&"dof") as PostDof
	if dof == null:
		return
	cinematic = on
	dof.active = on


## `--post=lens,bloom` keeps only the named effects (empty flag = all of them).
func _want(effect: StringName) -> bool:
	return _only.is_empty() or _only.has(effect)


func _parse_only(flag: String) -> Array[StringName]:
	var out: Array[StringName] = []
	if flag == "":
		return out
	for part in flag.split(",", false):
		out.append(StringName(part.strip_edges()))
	return out


## `--post-tune=fog_depth_begin:200,tonemap_exposure:1.1,grade_pivot:0.55,lens_grain:0` — measurement
## hook only. It
## writes any Environment property for one run so an A/B can be shot without editing another unit's
## file, and any `grade_*` key into the LUT builder; nothing in the shipped presets depends on it.
func _parse_tune(flag: String) -> Dictionary:
	var out: Dictionary = {}
	for part in flag.split(",", false):
		var kv := part.split(":")
		if kv.size() != 2:
			push_warning("PostStack: --post-tune wants key:value, got '%s'" % part)
			continue
		out[StringName(kv[0].strip_edges())] = kv[1].strip_edges()
	return out

