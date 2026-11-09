extends Node3D
## city-art r11 — the kit-layer A/B probe (adopted from the lead's `game/tmp_lead/kitlayer_ab.gd` and
## `kitmat_ab.gd`, which this commit deletes).
##
## What it answers: on a near kit wall, WHICH layer is the look coming from? Each camera is shot five
## times down one ladder — as shipped; with the window layer off; with the emission off too; with a
## plain white albedo (base colour only); and with the whole kit material replaced by one flat
## StandardMaterial3D. The lead used the last two to prove the crumpled foil was painted into the
## Tripo ATLAS rather than being geometry, shadows or specular.
##
## The lead's version mutated the materials and never put them back, so only the FIRST camera of a run
## was valid. This one snapshots every shader parameter of every kit material, and every
## `material_override`, before it touches anything and restores them after each camera — so a whole
## camera list is valid in one run.
##
##   tools/godot.sh shot --scene=res://world/art/tests/probe_kit_layers.tscn --out=r11probe \
##     --env-only --warm=1 --times=9999 --probe-cams=res://world/art/tests/cams_r11.json
##
## `--times=9999` parks the capture harness (it would otherwise grab the game camera at t=3) while this
## node does the work and quits the tree itself.

const DEFAULT_CAMS := "res://world/art/tests/cams_r11.json"
const CITY_SCENE := "res://world/city.tscn"

var _out: String = "probe"
var _outdir: String = ArtRepo.at("captures")  ## r12 §3: derived from the project dir, not literal
var _cams: Array = []
var _warm: int = 40
var _cam: Camera3D
## `--probe-dolly=<camera name>:<seconds>` — instead of the A/B ladder, slide the camera along the
## wall it is looking at and leave the quitting to whatever is driving the run (`tools/godot.sh movie`
## ends on its timeline's `end` marker). This is the r11 shimmer gate.
var _dolly: String = ""
var _dolly_secs: float = 4.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = _arg(args, "--out=", _out)
	_outdir = _arg(args, "--outdir=", _outdir)
	_warm = int(_arg(args, "--probe-warm=", "40"))
	_cams = _load_cams(_arg(args, "--probe-cams=", DEFAULT_CAMS))
	_dolly = _arg(args, "--probe-dolly=", "")
	if _dolly != "":
		var parts := _dolly.split(":")
		_dolly = parts[0]
		_dolly_secs = float(parts[1]) if parts.size() > 1 else 4.0
	_instance_city()
	_run.call_deferred()


## The same city the vistas shoot, so the probe measures the shipped scene and not a test street.
func _instance_city() -> void:
	var packed := load(CITY_SCENE) as PackedScene
	if packed == null:
		push_error("PROBE cannot load " + CITY_SCENE)
		return
	add_child(packed.instantiate())


static func _arg(args: PackedStringArray, flag: String, def: String) -> String:
	for a in args:
		if a.begins_with(flag):
			return a.substr(flag.length())
	return def


func _load_cams(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("PROBE no camera list at " + path)
		return []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Array:
		push_error("PROBE " + path + " is not a JSON array of cameras")
		return []
	return data as Array


## The city builds for several seconds; the KitPlacer only exists once its batches are up.
func _wait_kit() -> Node:
	for i in 900:
		var kit: Node = get_tree().root.find_child("KitPlacer", true, false)
		if kit != null:
			await _frames(30)
			return kit
		await get_tree().process_frame
	return null


func _run() -> void:
	var kit := await _wait_kit()
	if kit == null:
		push_error("PROBE no KitPlacer after 900 frames")
		get_tree().quit(1)
		return
	_hide_canvas(get_tree().root)
	_cam = Camera3D.new()
	_cam.near = 0.05
	_cam.far = 6000.0
	add_child(_cam)
	var mats := _shader_mats(kit)
	var inst := _instances(kit)
	print("PROBE kit materials=%d instances=%d cams=%d warm=%d"
		% [mats.size(), inst.size(), _cams.size(), _warm])
	if mats.is_empty():
		push_error("PROBE the KitPlacer has no ShaderMaterial — nothing to A/B")
		get_tree().quit(1)
		return
	if _dolly != "":
		await _run_dolly()
		return
	for spec in _cams:
		await _shoot(spec, mats, inst)
	print("PROBE done cameras=%d" % _cams.size())
	get_tree().quit(0)


## The shimmer gate: slide the camera along the wall it is looking at, so every facade line crosses the
## pixel grid at a different rate. Nothing is saved — the run is recorded by `tools/godot.sh movie`.
func _run_dolly() -> void:
	var spec: Dictionary = {}
	for c in _cams:
		if String(c.get("name", "")) == _dolly:
			spec = c
	if spec.is_empty():
		push_error("PROBE dolly: no camera named " + _dolly)
		get_tree().quit(1)
		return
	var base := _vec(spec["pos"])
	var look := _vec(spec["look"])
	_cam.fov = float(spec.get("fov", 70.0))
	_cam.make_current()
	var dir := (look - base)
	dir.y = 0.0
	var span := dir.length() * 0.45          # a slide proportional to how far the wall is
	var perp := Vector3(-dir.z, 0.0, dir.x).normalized()
	print("PROBE dolly %s span=%.1f m over %.1f s" % [_dolly, span, _dolly_secs])
	var t := 0.0
	while true:
		_cam.global_position = base + perp * ((t / _dolly_secs - 0.5) * span)
		_cam.look_at(look, Vector3.UP)
		await get_tree().process_frame
		t += get_process_delta_time()


## One camera, five rungs of the ladder, then everything put back exactly as it was.
func _shoot(spec: Dictionary, mats: Array[ShaderMaterial], inst: Array[GeometryInstance3D]) -> void:
	var cam_name := String(spec.get("name", "cam"))
	_cam.fov = float(spec.get("fov", 70.0))
	_cam.global_position = _vec(spec["pos"])
	_cam.look_at(_vec(spec["look"]), Vector3.UP)
	_cam.make_current()
	await _frames(_warm)
	await _save("%s_%s_shipped" % [_out, cam_name])

	var snap := _snapshot(mats, inst)
	# 0. the facade's COLOUR with none of its STRUCTURE: no slab, no mullion, no reveal, no pane. This
	#    is the flat-wall reference that has the same lighting, the same geometry and the same tint as
	#    the shipped wall, so the difference between the two is the grid and nothing else.
	for m in mats:
		m.set_shader_parameter(&"facade_lines", 0.0)
	await _frames(_warm)
	await _save("%s_%s_tintonly" % [_out, cam_name])

	# 1. the window layer off, both routes: the atlas panes and the r11 facade grid
	for m in mats:
		m.set_shader_parameter(&"win_mask_from", 0.0)
		m.set_shader_parameter(&"win_dark_lo", -1.0)
		m.set_shader_parameter(&"win_dark_hi", -0.5)
		m.set_shader_parameter(&"facade_mix", 0.0)
	await _frames(_warm)
	await _save("%s_%s_nowindows" % [_out, cam_name])

	# 2. ... and the model's own baked emission off
	for m in mats:
		m.set_shader_parameter(&"use_emission", 0.0)
	await _frames(_warm)
	await _save("%s_%s_nowindows_noemit" % [_out, cam_name])

	# 3. ... and the albedo texture replaced by plain white: base colour only. This is the FLATNESS
	#    FLOOR — the panel the shipped wall's low-frequency energy is measured against.
	var white := ImageTexture.create_from_image(_white_image())
	for m in mats:
		m.set_shader_parameter(&"tex_albedo", white)
		m.set_shader_parameter(&"base_color", Color(0.25, 0.2, 0.16))
	await _frames(_warm)
	await _save("%s_%s_plainalbedo" % [_out, cam_name])

	# 4. the whole kit material replaced by one flat untextured StandardMaterial3D
	var flat := StandardMaterial3D.new()
	flat.albedo_color = Color(0.25, 0.2, 0.16)
	flat.roughness = 0.65
	for gi in inst:
		gi.material_override = flat
	await _frames(_warm)
	await _save("%s_%s_flatmat" % [_out, cam_name])

	_restore(snap, mats, inst)


## Every shader parameter of every kit material, plus every `material_override`, before the ladder.
func _snapshot(mats: Array[ShaderMaterial], inst: Array[GeometryInstance3D]) -> Array:
	var params: Array[Dictionary] = []
	for m in mats:
		var d: Dictionary = {}
		for u in m.shader.get_shader_uniform_list(true):
			var n := StringName(u["name"])
			d[n] = m.get_shader_parameter(n)
		params.append(d)
	var over: Array[Material] = []
	for gi in inst:
		over.append(gi.material_override)
	return [params, over]


func _restore(snap: Array, mats: Array[ShaderMaterial], inst: Array[GeometryInstance3D]) -> void:
	var params: Array = snap[0]
	for i in mats.size():
		var d: Dictionary = params[i]
		for n in d:
			mats[i].set_shader_parameter(n, d[n])
	var over: Array = snap[1]
	for i in inst.size():
		inst[i].material_override = over[i] as Material


## --- the small helpers -----------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await get_tree().process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_outdir)
	var path := _outdir.path_join(name + ".jpg")
	var err := img.save_jpg(path, 0.85)
	print("PROBE shot %s%s" % [path, "" if err == OK else "  SAVE FAILED %d" % err])


static func _vec(v: Variant) -> Vector3:
	var a := v as Array
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _white_image() -> Image:
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return img


func _hide_canvas(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	for child in node.get_children():
		_hide_canvas(child)


## Every distinct ShaderMaterial the kit draws with, in either the override or the mesh's own slot.
func _shader_mats(node: Node) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var gi := n as GeometryInstance3D
		if gi != null:
			var mesh: Mesh = null
			var mm := gi as MultiMeshInstance3D
			if mm != null and mm.multimesh != null:
				mesh = mm.multimesh.mesh
			elif gi is MeshInstance3D:
				mesh = (gi as MeshInstance3D).mesh
			if mesh != null:
				var mats: Array[Material] = [gi.material_override]
				for s in mesh.get_surface_count():
					mats.append(mesh.surface_get_material(s))
				for m in mats:
					if m is ShaderMaterial and not out.has(m as ShaderMaterial):
						out.append(m as ShaderMaterial)
		stack.append_array(n.get_children())
	return out


func _instances(node: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MultiMeshInstance3D or n is MeshInstance3D:
			out.append(n as GeometryInstance3D)
		stack.append_array(n.get_children())
	return out
