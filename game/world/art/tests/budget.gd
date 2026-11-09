extends Node3D
## city-art r13: the frame budget probe. Boots the REAL game (`main.tscn`) at the shipping default and
## measures frame time, draw calls and primitives at a list of cameras.
##
## `viewport_get_measured_render_time_gpu` reads 0 on this Metal build (lead r13), so the method is
## toggling one lever at a time. The machine is SHARED — other units' Godot and Blender runs, and the
## user's own Xcode builds, move the absolute frame time by 3x inside a minute — so every lever is
## measured ALTERNATELY WITH THE BASELINE inside one process:
##
##   tools/godot.sh shot --scene=res://world/art/tests/budget.tscn --out=budget --skip-menu \
##       --stub=camera --budget-seq=base,no-ssil,base,no-ssil
##
## Each entry of `--budget-seq` is a lever name (`base` = everything restored), and the sequence is
## walked once per camera. Every lever is reversible: `_saved` records the value it replaced and
## `_restore()` puts it back, so arm N never inherits arm N-1's state.
##
## `--budget-mode=spawn` measures with the game's own camera instead (the shipping A1 spawn, first
## during the 220 m insertion drop and then on the ground).

const MAIN := "res://main.tscn"
const DEFAULT_CAMS := "res://world/art/tests/cams_budget5.json"

var _cam: Camera3D
var _main: Node
var _env: Environment
var _sun: DirectionalLight3D
var _root: Viewport
var _warm: int = 24
var _samples: int = 40
var _mode: String = "cams"
var _seq: PackedStringArray = PackedStringArray(["base"])
var _wet_pushed: bool = false
## [object, property name, old value] for everything a lever replaced, and the nodes it hid.
var _saved: Array = []
var _hidden: Array[Node3D] = []
var _detail_touched: bool = false
var _occ_touched: bool = false
var _pano_touched: bool = false
var _grain_touched: bool = false
var _sky_saved: float = 0.0


func _ready() -> void:
	Engine.max_fps = 0                      # uncapped: the 60 fps cap would hide the headroom
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_warm = int(Game.flag("budget-warm", "24"))
	_samples = int(Game.flag("budget-samples", "40"))
	_mode = Game.flag("budget-mode", "cams")
	_seq = PackedStringArray(Game.flag("budget-seq", "base").split(",", false))
	_main = (load(MAIN) as PackedScene).instantiate()
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	while not Game.world_built():
		await get_tree().process_frame
	await _frames(10)
	_find_env()
	# `--budget-force=<lever>` applies one lever for the whole run and never restores it, which is what
	# the look A/B sheets are shot from (one run per arm, same build, same cameras).
	var forced := Game.flag("budget-force")
	if not forced.is_empty():
		print("BUDGET forced %s -> %s" % [forced, _apply(forced)])
	print("BUDGET mode=%s seq=%s load=%s warm=%d samples=%d"
		% [_mode, ",".join(_seq), _loadavg(), _warm, _samples])
	_describe()
	if _mode == "spawn":
		# The insertion is a 220 m drop (flow `_drop`): the lead's "A1 spawn" number is measured while
		# the mech is still in the air and sees the whole city, so it is reported as its own camera and
		# the grounded street number is measured after it as well. They are different frames.
		await _measure("A1drop")
		await _shot("A1drop")
		await _wait_grounded()
		_describe()
		# On the ground the same lever sequence as the camera sweep runs, so the spawn number is paired
		# with the r12 default inside one process like every other number in this round.
		for rep in range(int(Game.flag("budget-reps", "1"))):
			for entry in _seq:
				_restore()
				var applied := _apply(entry)
				await _measure("A1ground/%s#%d" % [entry, rep], applied)
				if rep == 0 and not Game.flag("budget-shot").is_empty():
					await _shot("A1ground_%s" % entry)
		_restore()
		get_tree().quit(0)
		return
	_cam = Camera3D.new()
	_cam.near = 0.05
	_cam.far = 6000.0
	add_child(_cam)
	for c in _cameras():
		_cam.fov = float(c.get("fov", 60.0))
		_cam.position = _vec(c["pos"])
		_cam.look_at(_vec(c["look"]), Vector3.UP)
		_cam.current = true
		# The whole sequence is walked `--budget-reps` times per camera and each lever is paired with
		# the baseline of ITS OWN repetition, so a machine that drifts over minutes (other units, the
		# user's own builds) cancels instead of deciding the answer.
		for rep in range(int(Game.flag("budget-reps", "1"))):
			for entry in _seq:
				if forced.is_empty():
					_restore()
				var applied := _apply(entry)
				await _measure("%s/%s#%d" % [String(c["name"]), entry, rep], applied)
				if rep == 0 and not Game.flag("budget-shot").is_empty():
					await _shot("%s_%s" % [String(c["name"]), entry])
		if forced.is_empty():
			_restore()
		if not Game.flag("budget-shot").is_empty():
			await _shot(String(c["name"]))
	get_tree().quit(0)


## One camera and one lever: warm, then time `_samples` frames and read the render counters back.
func _measure(label: String, applied: String = "") -> void:
	await _frames(_warm)
	var ms: PackedFloat64Array = []
	var draws := 0
	var prims := 0
	var objs := 0
	for i in _samples:
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		draws = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		prims = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		objs = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var sorted := ms.duplicate()
	sorted.sort()
	var mean := 0.0
	for v in ms:
		mean += v
	mean /= maxf(float(ms.size()), 1.0)
	print("BUDGET %-18s draws=%5d objs=%6d prims=%9d mean=%6.2fms p50=%6.2f p95=%6.2f fps=%5.1f cpu=%5.2f phys=%5.2f load=%s %s"
		% [label, draws, objs, prims, mean, sorted[int(sorted.size() * 0.5)],
		   sorted[int(sorted.size() * 0.95)], 1000.0 / maxf(mean, 0.001),
		   Performance.get_monitor(Performance.TIME_PROCESS),
		   Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS), _loadavg(), applied])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Waits for the insertion drop to end. `is_grounded()` is the mech's own answer; the height test is a
## second opinion so a mech that is grounded on a skyrail 300 m up is not called "the street".
func _wait_grounded() -> void:
	var waited := 0
	while waited < 3600:
		await get_tree().process_frame
		waited += 1
		var p := Game.player as PlayerMech
		if p != null and p.is_grounded() and p.global_position.y < 120.0:
			return
	push_warning("budget: the mech never landed in %d frames — measuring anyway" % waited)


## What the frame actually contains: without this a "spawn" number that is really a camera pointing at
## the sky (or a world that has not finished building) reads exactly like a fast one.
func _describe() -> void:
	var cam := get_viewport().get_camera_3d()
	var player := Game.player as Node3D
	print("BUDGET scene cam=%s at=%s player=%s main_children=%d"
		% [cam.name if cam != null else "none",
		   ("(%.0f,%.0f,%.0f)" % [cam.global_position.x, cam.global_position.y, cam.global_position.z])
				if cam != null else "-",
		   ("(%.0f,%.0f,%.0f)" % [player.global_position.x, player.global_position.y,
			   player.global_position.z]) if player != null else "none",
		   _main.get_child_count() if _main != null else 0])


## `--budget-shot=<prefix>` writes `captures/<prefix>_<camera>.jpg` beside every measurement, so the
## look gate and the cost gate are judged from the same run.
func _shot(name: String) -> void:
	var prefix := Game.flag("budget-shot")
	if prefix.is_empty():
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ArtRepo.at("captures").path_join("%s_%s.jpg" % [prefix, name])
	if img.save_jpg(path, 0.85) != OK:
		push_error("budget: could not write %s" % path)
	else:
		print("BUDGET shot %s" % path)


func _cameras() -> Array:
	var path := Game.flag("budget-cams", DEFAULT_CAMS)
	if not FileAccess.file_exists(path):
		push_error("budget: no camera list at %s" % path)
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Array else []


func _vec(v: Variant) -> Vector3:
	var a: Array = v
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## The WorldEnvironment and Sun the city instanced (`environment.tscn`), found through the group so a
## look-dev scene that names them differently still resolves.
func _find_env() -> void:
	for n in get_tree().get_nodes_in_group(&"time_of_day"):
		var tod := n as Node
		var we := tod.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
		if we != null:
			_env = we.environment
		_sun = tod.get_node_or_null(^"Sun") as DirectionalLight3D
	_root = get_viewport()
	if _env == null:
		push_error("budget: no WorldEnvironment — the levers that need one will do nothing")


## --- levers ---------------------------------------------------------------------------------------

## Puts back everything the previous lever replaced. Called before every arm, so arm N never inherits
## arm N-1's state and the baseline is the real shipping default rather than the last thing measured.
func _restore() -> void:
	for row: Array in _saved:
		(row[0] as Object).set(row[1], row[2])
	_saved.clear()
	for n: Node3D in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden.clear()
	if _detail_touched:
		McMaterials.set_detail_distance(McMaterials.NO_DETAIL, McMaterials.NO_DETAIL)
		_detail_touched = false
	if _occ_touched:
		RenderingServer.viewport_set_use_occlusion_culling(_root.get_viewport_rid(), true)
		_occ_touched = false
	if _pano_touched:
		var sky_mat := _sky_material()
		if sky_mat != null:
			sky_mat.set_shader_parameter(&"pano_blend", _sky_saved)
		_pano_touched = false
	if _grain_touched:
		var stack := get_tree().get_first_node_in_group(&"post_stack") as PostStack
		if stack != null:
			var lens := stack.effects.get(&"lens") as PostLens
			if lens != null:
				lens.legacy_grain = 0.0
		_grain_touched = false


## The sky material behind the Environment's `sky`, or null. `CityEnvironment.sky_uniforms` is the one
## place that knows how to reach it.
func _sky_material() -> ShaderMaterial:
	return CityEnvironment.sky_uniforms(_env) if _env != null else null


func _save_set(obj: Object, prop: String, value: Variant) -> void:
	_saved.append([obj, prop, obj.get(prop)])
	obj.set(prop, value)


## Applies one lever and returns a short description of what actually took effect, so a run's line says
## what it measured rather than what it was asked to measure.
func _apply(lever: String) -> String:
	match lever:
		"base", "":
			return ""
		"no-sun-shadow":
			if _sun != null:
				_save_set(_sun, "shadow_enabled", false)
				return lever
		"shadow":
			if _sun != null:
				_save_set(_sun, "directional_shadow_max_distance", float(Game.flag("shadow", "350")))
				return "%s=%s" % [lever, Game.flag("shadow", "350")]
		"splits":
			if _sun != null:
				_save_set(_sun, "directional_shadow_mode",
					DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if Game.flag("splits", "2") == "2"
					else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
				return "%s=%s" % [lever, Game.flag("splits", "2")]
		"shadow-blur":
			if _sun != null:
				_save_set(_sun, "shadow_blur", float(Game.flag("shadow-blur", "0")))
				var nb := float(Game.flag("normal-bias", "-1"))
				if nb >= 0.0:
					_save_set(_sun, "shadow_normal_bias", nb)
				var sb := float(Game.flag("bias", "-1"))
				if sb >= 0.0:
					_save_set(_sun, "shadow_bias", sb)
				return "%s=%s nb=%s b=%s" % [lever, Game.flag("shadow-blur", "0"),
					Game.flag("normal-bias", "-"), Game.flag("bias", "-")]
		"no-ssao":
			if _env != null:
				_save_set(_env, "ssao_enabled", false)
				return lever
		"no-ssil":
			if _env != null:
				_save_set(_env, "ssil_enabled", false)
				return lever
		# r15 §4: the analytic wet-ground reflection (mc_wet.gdshaderinc). `wet_reflection` early-outs
		# on a dry fragment, so zeroing the city-wide wetness is a true A/B of its cost and not just of
		# its look.
		"no-wet":
			McMaterials.set_wetness(0.0)
			_wet_pushed = true
			return lever
		"no-ssr":
			if _env != null:
				_save_set(_env, "ssr_enabled", false)
				return lever
		# r15 §4: SSR is OFF at shipping quality (r13 measured 1.75 ms of a 28 ms street frame), so the
		# wet ground's reflection is analytic instead (mc_wet.gdshaderinc). This lever is how that
		# trade is priced on THIS build rather than quoted from r13: `base,ssr,base,ssr` pairs them.
		"ssr":
			if _env != null:
				_save_set(_env, "ssr_enabled", true)
				_save_set(_env, "ssr_max_steps", int(Game.flag("ssr-steps", "48")))
				return "%s steps=%s" % [lever, Game.flag("ssr-steps", "48")]
		"no-vol":
			if _env != null:
				_save_set(_env, "volumetric_fog_enabled", false)
				return lever
		"vol-length":
			if _env != null:
				_save_set(_env, "volumetric_fog_length", float(Game.flag("vol-length", "120")))
				return "%s=%s" % [lever, Game.flag("vol-length", "120")]
		"no-glow":
			if _env != null:
				_save_set(_env, "glow_enabled", false)
				return lever
		"no-grade":
			if _env != null:
				_save_set(_env, "adjustment_enabled", false)
				return lever
		"no-sky":
			if _env != null:
				_save_set(_env, "background_mode", Environment.BG_COLOR)
				_save_set(_env, "ambient_light_source", Environment.AMBIENT_SOURCE_COLOR)
				return lever
		"scale":
			if _root != null:
				_save_set(_root, "scaling_3d_scale", float(Game.flag("scale", "0.6")))
				return "%s=%s" % [lever, Game.flag("scale", "0.6")]
		"no-mc":
			return "%s(%d)" % [lever, _plain_materials()]
		"detail":
			var m := float(Game.flag("detail", "150"))
			var tri := float(Game.flag("tri", "-1"))
			McMaterials.set_detail_distance(m, tri)
			_detail_touched = true
			return "%s=%s tri=%s" % [lever, Game.flag("detail", "150"), Game.flag("tri", "off")]
		"legacy":
			# The shipping default as it stood before r13: no detail distance, 0.67 MetalFX and SSR on.
			# One lever, so the whole round's saving is a single paired measurement.
			McMaterials.set_detail_distance(McMaterials.NO_DETAIL, McMaterials.NO_DETAIL)
			_detail_touched = true
			if _env != null:
				_save_set(_env, "ssr_enabled", true)
			if _root != null:
				_save_set(_root, "scaling_3d_scale", 0.67)
			return lever
		"legacy-no-ssr":
			# `legacy` without the SSR toggle. Toggling an Environment effect at runtime recompiles every
			# material's pipeline variant (godot-tech §4.6), and a run that does it once per camera per
			# repetition gets slower and slower as it goes: the same five cameras measure 24-34 ms with no
			# lever at all and 75-118 ms at the last two after 20 toggles. The frame-time numbers in this
			# round therefore come from arms that only push uniforms.
			McMaterials.set_detail_distance(McMaterials.NO_DETAIL, McMaterials.NO_DETAIL)
			_detail_touched = true
			if _root != null:
				_save_set(_root, "scaling_3d_scale", 0.67)
			return lever
		# r16b: the two things this round changed that touch the GPU at all. Everything else it moved is
		# a uniform value or a colour, which costs nothing to set differently.
		"no-pano":
			# The CC0 cloud plate (item 3) is one texture fetch and a branch in the sky shader.
			var sky_mat := _sky_material()
			if sky_mat != null:
				_sky_saved = float(sky_mat.get_shader_parameter(&"pano_blend"))
				sky_mat.set_shader_parameter(&"pano_blend", 0.0)
				_pano_touched = true
				return "%s (was %.2f)" % [lever, _sky_saved]
		"legacy-grain":
			# The pre-r16b sine hash (item 2): `fract(sin(...))` against the integer hash that ships.
			var stack := get_tree().get_first_node_in_group(&"post_stack") as PostStack
			if stack != null:
				var lens := stack.effects.get(&"lens") as PostLens
				if lens != null:
					lens.legacy_grain = 1.0
					_grain_touched = true
					return lever
		"no-probes":
			return _hide_named([&"ArenaProbes"], lever)
		"no-art":
			return _hide_named([&"Dressing", &"Greebles", &"Signs", &"StreetWeb", &"Scaffolds",
				&"Cargo", &"SpireLights"], lever)
		"no-kit":
			return _hide_named([&"KitPlacer"], lever)
		"no-tiles":
			return _hide_named([&"Tiles"], lever)
		"no-skyline":
			return _hide_named([&"Skyline"], lever)
		"no-occ":
			# The engine's own switch, so the arm is the shipping renderer without the feature rather
			# than a scene with the occluders deleted.
			RenderingServer.viewport_set_use_occlusion_culling(_root.get_viewport_rid(), false)
			_occ_touched = true
			return lever
		"no-dress-shadow":
			return _cast_off_named([&"Dressing", &"Greebles", &"Signs", &"StreetWeb", &"Scaffolds",
				&"Cargo", &"SpireLights"], lever)
		"no-far-shadow":
			return _cast_off_far(lever)
	push_warning("budget: unknown lever '%s' — ignored" % lever)
	return "(unknown)"


## Hides the named subtrees. `visible = false` removes them from every render pass (shadow, depth,
## colour) which is exactly what a lever has to do to be worth a millisecond.
func _hide_named(names: Array[StringName], lever: String) -> String:
	var found := 0
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and names.has(n.name) and (n as Node3D).visible:
			(n as Node3D).visible = false
			_hidden.append(n as Node3D)
			found += 1
		stack.append_array(n.get_children())
	if found == 0:
		push_warning("budget: lever '%s' matched nothing" % lever)
	return "%s(%d)" % [lever, found]


## Turns shadow casting off for every mesh under the named roots.
func _cast_off_named(names: Array[StringName], lever: String) -> String:
	var roots: Array[Node] = []
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and names.has(n.name):
			roots.append(n)
		stack.append_array(n.get_children())
	var changed := 0
	for r: Node in roots:
		changed += _cast_off(r)
	return "%s(%d)" % [lever, changed]


## The far tier: city-kit's far LODs and city-build's skyline ring. Measured here, applied for real in
## `CityArt` (a runtime pass over the placed kit), never by editing `kit_placer.gd`.
func _cast_off_far(lever: String) -> String:
	var changed := 0
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (String(n.name).contains("_far") or String(n.name) == "Skyline"):
			changed += _cast_off(n)
		stack.append_array(n.get_children())
	return "%s(%d)" % [lever, changed]


func _cast_off(node: Node) -> int:
	var changed := 0
	var gi := node as GeometryInstance3D
	if gi != null and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_save_set(gi, "cast_shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		changed += 1
	for child in node.get_children():
		changed += _cast_off(child)
	return changed


## What do the `mc_*` shaders cost? Every surface is swapped for one plain StandardMaterial3D that
## carries only its albedo texture, so the frame that comes back is the same geometry, the same lights
## and the same pixels with none of this unit's shader work in them.
func _plain_materials() -> int:
	var cache: Dictionary = {}
	var changed := 0
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var plain := _plain(mi.mesh.surface_get_material(i), cache)
				if plain != null:
					_save_set(mi, "surface_material_override/%d" % i, plain)
					changed += 1
		var mmi := n as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null and mmi.multimesh.mesh != null:
			var plain2 := _plain(mmi.multimesh.mesh.surface_get_material(0), cache)
			if plain2 != null:
				_save_set(mmi, "material_override", plain2)
				changed += 1
		stack.append_array(n.get_children())
	return changed


func _plain(src: Material, cache: Dictionary) -> Material:
	if src == null:
		return null
	var key := src.get_rid()
	if cache.has(key):
		return cache[key]
	var out := StandardMaterial3D.new()
	var sm := src as StandardMaterial3D
	if sm != null:
		out.albedo_color = sm.albedo_color
		out.albedo_texture = sm.albedo_texture
		out.roughness = sm.roughness
		out.metallic = sm.metallic
		out.cull_mode = sm.cull_mode
	cache[key] = out
	return out


## The machine load next to every number (lead r13: measure on a quiet machine and print the load).
func _loadavg() -> String:
	var out: Array = []
	OS.execute("sysctl", PackedStringArray(["-n", "vm.loadavg"]), out)
	return String(out[0]).strip_edges() if not out.is_empty() else "?"
