extends Node3D
## city-art r14 — the value-structure probe (lead brief r14 §1: "measure first").
##
## For every camera and every time of day it renders THREE lossless frames at the shipping default and
## writes the geometry the masks need next to it, so `tmp/city-art/r15/values.py` can measure them:
##   <tag>_p<t>_<cam>_A.png  the shipping frame (post, glow, temporal upscaler — what ships)
##   <tag>_p<t>_<cam>_B.png  the same camera with every visual hidden: the bare sky, and therefore an
##                           EXACT sky mask (A minus B) for the far-field contrast
##   <tag>_p<t>_<cam>_C.png  the same camera with the SUN off and nothing else changed, so A - C is an
##                           exact sun-visibility mask: sunlit surfaces, shaded surfaces and the sky
##                           separate without any heuristic (r15 §1, colour)
##   <tag>_meta.json         per frame: size, fov, the projected sun disc and Spire tether
##
## The B frame is why the horizon is not guessed. Three automatic sky finders were tried on the key
## art first — per-pixel gradient, row busyness, vertical-edge persistence — and all three put the
## horizon inside the cloud bank on v1_pier, because a golden-hour sky is the busiest thing in these
## frames after the city. On the renders the mask is free and exact, so the renders get it.
##
## Everything is measured in numpy rather than here because the metric definition has to be re-runnable
## without re-rendering a 15-camera city, and because GDScript needs seconds per 5.7 Mpx frame.
##
##   tools/godot.sh shot --scene=res://world/art/tests/value_probe.tscn --out=vp \
##     --value-cams=res://world/art/tests/cams_value.json --value-tods=0,0.5,1 --value-tag=r13
## (`tools/godot.sh run` drops every flag after the scene and the seconds — use `shot`.)

const CITY_SCENE := "res://world/city.tscn"
## The shipping frame is the one `main.gd` builds, and post is one of its PARTS — a probe that only
## instances the city measures a frame the game never shows (r14: the whole post stack was missing and
## a --post-tune sweep moved the numbers by 0.01).
const POST_SCENE := "res://world/post/post_stack.tscn"
## r16b: the frame directory is a flag, so a round keeps its own frames instead of
## overwriting the last one's (`--value-frames=tmp/city-art/r16b/frames`).
const FRAMES_REL := "tmp/city-art/r15/frames"
const LAYOUT := "res://world/city/layout.json"
## The sun's disc is 0.53 deg across. What clips around it is the disc plus the glare it throws — the
## sky shader's halo and the bloom the disc is above the threshold for — which measures ~5 deg of
## radius at the shipping default. Wider than that and a genuinely bleached sky band would be excused,
## so 5 deg is the line and the frames where it matters are listed in the status file.
const SUN_MASK_DEG := 5.0
## Half-width, in pixels at the backing-store resolution, of the Spire tether exclusion.
const BEAM_MASK_PX := 26.0
## How many frames to wait for `frame_post_draw` before forcing a draw. A windowed Godot on macOS
## throttles its display loop while another window covers it — the trailer's recorder does exactly
## that — and an un-guarded `await frame_post_draw` then blocks for ever (r14, first probe run).
const DRAW_TIMEOUT_FRAMES := 240
## Frames the temporal upscaler needs to forget the geometry it was fed, so the B frame is the bare sky
## and not the sky with last frame's city still dissolved into it.
const HIDE_SETTLE := 24

var _city: Node3D
var _tod: TimeOfDay
var _cam: Camera3D
var _out: String = ""
var _warm: int = 70
var _tag: String = "r14"
var _cams: Array = []
var _tods: PackedFloat64Array = PackedFloat64Array()
var _meta: Array = []
var _size := Vector2i.ZERO
var _drew: bool = false
var _hidden: Array[Node] = []


func _ready() -> void:
	_city = _instance_city()
	_add_post()
	for i in 4:
		await get_tree().physics_frame
	await _frames(30)
	_tod = _find_tod()
	_cam = Camera3D.new()
	_cam.near = 0.05
	_cam.far = 6000.0
	add_child(_cam)
	if not _parse_flags():
		get_tree().quit(1)
		return
	_run.call_deferred()


func _parse_flags() -> bool:
	_out = ArtRepo.at(Game.flag("value-frames", FRAMES_REL))
	DirAccess.make_dir_recursive_absolute(_out)
	_warm = int(Game.flag("value-warm", "70"))
	_tag = Game.flag("value-tag", "r15")
	var spec := Game.flag("value-cams", "res://world/art/tests/cams_value.json")
	if not FileAccess.file_exists(spec):
		push_error("value_probe: camera list %s does not exist" % spec)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(spec))
	if not (parsed is Array) or (parsed as Array).is_empty():
		push_error("value_probe: %s is not a non-empty JSON array" % spec)
		return false
	_cams = parsed as Array
	for t in Game.flag("value-tods", "0,0.5,1").split(",", false):
		_tods.append(float(t))
	_load_meta()
	_hide_named(Game.flag("value-hide", ""))
	print("VALUE probe tag=%s cams=%d tods=%s warm=%d out=%s"
		% [_tag, _cams.size(), str(_tods), _warm, _out])
	return true


func _run() -> void:
	for p in _tods:
		if _tod != null:
			_tod.set_progress_immediate(p)
		else:
			push_warning("value_probe: no TimeOfDay node — every frame is at the default progress")
		await _frames(_warm)
		_apply_tune()
		await _frames(4)
		for c in _cams:
			await _one(float(p), c as Dictionary)
	print("VALUE done")
	get_tree().quit(0)


func _one(p: float, c: Dictionary) -> void:
	_aim(c)
	await _frames(_warm)
	var img := await _grab()
	_size = Vector2i(img.get_width(), img.get_height())
	var stem := "%s_p%s_%s" % [_tag, str(p).replace(".", ""), String(c["name"])]
	if img.save_png(_out.path_join(stem + "_A.png")) != OK:
		push_error("value_probe: cannot write %s_A.png" % stem)
	# C: the sun off, everything else untouched. A - C is the sun-visibility mask the colour metrics
	# need, and it costs one frame instead of a shadow/AO heuristic.
	var sun := _sun()
	var have_c := sun != null
	if have_c:
		sun.visible = false
		await _frames(HIDE_SETTLE)
		var nosun := await _grab()
		if nosun.save_png(_out.path_join(stem + "_C.png")) != OK:
			push_error("value_probe: cannot write %s_C.png" % stem)
		sun.visible = true
		await _frames(HIDE_SETTLE)
	_hide_all()
	await _frames(HIDE_SETTLE)
	var bare := await _grab()
	if bare.save_png(_out.path_join(stem + "_B.png")) != OK:
		push_error("value_probe: cannot write %s_B.png" % stem)
	_show_all()
	_meta.append(_frame_meta(p, c, stem, have_c))
	_write_meta()   # after every frame: a run cut short by the slot timeout still has its numbers
	print("VALUE %-10s tod=%.2f %dx%d" % [String(c["name"]), p, _size.x, _size.y])


func _sun() -> DirectionalLight3D:
	return _tod.get_node_or_null(^"Sun") as DirectionalLight3D if _tod != null else null


## `--value-tune=tonemap_exposure:0.5,ambient_light_energy:0.16,lit:0.1,sky_exposure:0.7` — the A/B
## hook for this round. Any Environment property by name, plus the four numbers TimeOfDay overwrites on
## every `set_progress` (`ambient_light_energy`, `sun_energy`, `lit`, and the sky material's own
## uniforms as `sky_<name>`), which is why it is applied AFTER the progress is set and not at load.
## r16b: a value that is not a number is read as a COLOUR — an sRGB hex (`ffd08a`) or `r,g,b` — so a
## palette A/B is one flag instead of an edit, a commit and a re-import.
func _apply_tune() -> void:
	var spec := Game.flag("value-tune", "")
	if spec.is_empty():
		return
	var env := _env()
	for part in spec.split(",", false):
		var kv := part.split(":")
		if kv.size() != 2:
			push_warning("value_probe: --value-tune wants key:value, got '%s'" % part)
			continue
		var key := kv[0].strip_edges()
		var value: Variant = _tune_value(kv[1].strip_edges())
		if key == "lit":
			RenderingServer.global_shader_parameter_set(&"mc_lit_fraction", float(value))
		elif key == "wet":
			# r16b §4: the wet ground is a global push, not an Environment row — the clip gate at
			# `--tod=1.0` needed it as an arm of its own.
			McMaterials.set_wetness(float(value))
		elif key.begins_with("sun_"):
			var sun := _tod.get_node_or_null(^"Sun") as DirectionalLight3D if _tod != null else null
			if sun != null:
				# `sun_energy` is the light's `light_energy`; every other `sun_<prop>` is the property
				# itself, so the flag reads the way the light's own inspector does.
				var prop := "light_energy" if key == "sun_energy" else key.substr(4)
				sun.set(prop, value)
		elif key.begins_with("sky_"):
			var mat := CityEnvironment.sky_uniforms(env)
			if mat != null:
				mat.set_shader_parameter(StringName(key.substr(4)), value)
		elif env != null:
			env.set(key, value)
	print("VALUE tune %s" % spec)


## `0.42` -> a float, `ffd08a` / `#ffd08a` -> that sRGB colour, `0.1,0.2,0.3` -> a linear triple.
func _tune_value(raw: String) -> Variant:
	if raw.is_valid_float():
		return float(raw)
	var hex := raw.lstrip("#")
	if hex.length() == 6 and hex.is_valid_hex_number(false):
		return Color(hex)
	var parts := raw.split(",", false)
	if parts.size() == 3:
		return Color(float(parts[0]), float(parts[1]), float(parts[2]))
	push_warning("value_probe: --value-tune value '%s' is not a number or a colour" % raw)
	return 0.0


func _env() -> Environment:
	var we := _tod.get_node_or_null(^"WorldEnvironment") as WorldEnvironment if _tod != null else null
	return we.environment if we != null else null


func _aim(c: Dictionary) -> void:
	var pos: Array = c["pos"]
	var look: Array = c["look"]
	_cam.fov = float(c.get("fov", 60.0))
	_cam.position = Vector3(pos[0], pos[1], pos[2])
	_cam.look_at(Vector3(look[0], look[1], look[2]), Vector3.UP)
	_cam.current = true


## A draw that cannot hang. The signal normally arrives on the next frame, but a throttled display
## loop never emits it, so after a few frames the server is told to draw and the frame is taken
## whatever produced it. `_drew` is a member because a GDScript lambda captures its locals BY VALUE:
## a `got` flag set inside the callback would never be seen out here.
func _grab() -> Image:
	_drew = false
	RenderingServer.frame_post_draw.connect(_on_drawn, CONNECT_ONE_SHOT)
	for i in DRAW_TIMEOUT_FRAMES:
		await get_tree().process_frame
		if _drew:
			break
		if i == 8:
			RenderingServer.force_draw(false)
	if not _drew:
		push_warning("value_probe: frame_post_draw never fired — this frame is the previous one")
		if RenderingServer.frame_post_draw.is_connected(_on_drawn):
			RenderingServer.frame_post_draw.disconnect(_on_drawn)
	return get_viewport().get_texture().get_image()


func _on_drawn() -> void:
	_drew = true


## Everything the Python side needs to build the two exclusion masks, in the frame's own pixel space.
## The sun comes from the light's own basis (TimeOfDay aims it), so the mask follows the time of day
## without the probe knowing anything about the ramp.
func _frame_meta(p: float, c: Dictionary, stem: String, has_c: bool) -> Dictionary:
	var px_per_deg := float(_size.y) / maxf(_cam.fov, 1.0)
	var sun_px := Vector2(-1e9, -1e9)
	var sun := _sun()
	if sun != null:
		# A DirectionalLight3D shines along its -Z, and TimeOfDay builds the basis with z_axis = to_sun,
		# so the direction TO the sun is the basis +Z. Reading -Z here pointed the mask at the anti-sun and
		# it never fired (r14: the T1fac frame's 14 deg sun blob was charged to the clipping gate).
		var to_sun := sun.global_transform.basis.z.normalized()
		var at := _cam.global_position + to_sun * 20000.0
		if not _cam.is_position_behind(at):
			sun_px = _cam.unproject_position(at)
	var beam := _beam_segment()
	var beam_px: Array = []
	if not _cam.is_position_behind(beam[0]) and not _cam.is_position_behind(beam[1]):
		# Plain floats: JSON.stringify turns a Vector2 into the STRING "(x, y)", which no reader wants.
		var b0 := _cam.unproject_position(beam[0])
		var b1 := _cam.unproject_position(beam[1])
		beam_px = [[b0.x, b0.y], [b1.x, b1.y]]
	return {"stem": stem, "cam": String(c["name"]), "tod": p, "w": _size.x, "h": _size.y,
		"fov": _cam.fov, "pos": c["pos"], "look": c["look"], "has_c": has_c,
		"sun_px": [sun_px.x, sun_px.y], "sun_r": SUN_MASK_DEG * px_per_deg,
		"beam_px": beam_px, "beam_r": BEAM_MASK_PX}


## One run covers one time of day (the slot timeout is 600 s), so the meta file is a MERGE across
## runs: a frame already on disk is replaced by its new row, never duplicated.
func _load_meta() -> void:
	var path := _out.path_join(_tag + "_meta.json")
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Array:
		_meta.assign(parsed as Array)


func _write_meta() -> void:
	var path := _out.path_join(_tag + "_meta.json")
	var by_stem := {}
	for m in _meta:
		by_stem[String((m as Dictionary)["stem"])] = m
	var merged: Array = []
	for stem in by_stem:
		merged.append(by_stem[stem])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("value_probe: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(merged, "  "))
	f.close()


## The Spire tether, read from the shipped layout: the crown up to `tether_top_z`, in Godot space.
func _beam_segment() -> Array[Vector3]:
	var out: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	if not FileAccess.file_exists(LAYOUT):
		push_warning("value_probe: %s missing — the Spire tether is not masked out" % LAYOUT)
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if not (parsed is Dictionary):
		return out
	for lm: Dictionary in (parsed as Dictionary).get("landmarks", []):
		if String(lm.get("kind", "")) != "spire":
			continue
		var p: Array = lm.get("pos", [0, 0, 0])
		var params: Dictionary = lm.get("params", {})
		var base := Vector3(float(p[0]), 0.0, -float(p[1]))
		out[0] = base + Vector3.UP * float(params.get("height", 360.0))
		out[1] = base + Vector3.UP * float(params.get("tether_top_z", 960.0))
	return out


func _find_tod() -> TimeOfDay:
	for n in get_tree().get_nodes_in_group(&"time_of_day"):
		if n is TimeOfDay:
			return n as TimeOfDay
	push_warning("value_probe: no node in group time_of_day")
	return null


## Every visual in the city, off — which leaves the Environment's sky and nothing else. Only nodes
## that were visible are recorded, so restoring puts the scene back exactly as it was.
## `--value-hide=<name fragment[,fragment...]>` — the attribution tool for a shape the art host
## does not own (r16b: a comma-separated list, so one arm can take a whole layer apart). CityArt's
## own `--art-debug=hide=` only walks the art subtree, so the crown rim (built at runtime by city.gd)
## and anything else under the City node is out of its reach and cannot be blamed by hiding it.
func _hide_named(fragment: String) -> void:
	if fragment.is_empty():
		return
	var hidden := 0
	var stack: Array[Node] = [_city]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D:
			for part in fragment.split(",", false):
				if String(n.name).contains(part.strip_edges()):
					(n as Node3D).visible = false
					hidden += 1
					break
		stack.append_array(n.get_children())
	print("VALUE hid %d nodes matching '%s'" % [hidden, fragment])


func _hide_all() -> void:
	_hidden.clear()
	_collect_visuals(_city)
	for n in _hidden:
		(n as Node).set(&"visible", false)


func _show_all() -> void:
	for n in _hidden:
		(n as Node).set(&"visible", true)
	_hidden.clear()


func _collect_visuals(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		if child is VisualInstance3D and bool(child.get(&"visible")):
			_hidden.append(child)
		_collect_visuals(child)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## The same city the vistas harness instances, so the frames are the shipping city and not a look-dev
## stand-in (CONTRACTS §7 "Art integration": city.tscn instances environment.tscn itself).
## post_stack.tscn, exactly as `main.gd` adds it, unless `--no-post` says otherwise.
func _add_post() -> void:
	if Game.has_flag("no-post") or not ResourceLoader.exists(POST_SCENE):
		return
	var node := (load(POST_SCENE) as PackedScene).instantiate()
	add_child(node)


func _instance_city() -> Node3D:
	if not ResourceLoader.exists(CITY_SCENE):
		push_error("value_probe: %s does not exist — city-build has not exported the city" % CITY_SCENE)
		return null
	var node := (load(CITY_SCENE) as PackedScene).instantiate() as Node3D
	add_child(node)
	for placeholder in [^"BlockoutEnvironment", ^"Sun"]:
		var n := node.get_node_or_null(NodePath(placeholder))
		if n != null:
			node.remove_child(n)
			n.queue_free()
	return node
