extends Node3D
## city-kit r8 — the wedge gate's FLOOR: what a PERFECTLY FLAT cover albedo at the lead's own r8 §1
## target measures against the lead's reference panel.
##
##   tools/godot.sh shot --scene=res://world/kit/tests/probe_cover_floor.tscn --out=r8floor --env-only \
##       --warm=1 --times=9999 --probe-cams=res://world/kit/tests/cams_r8probe.json \
##       --floor-color=0.55
##
## **Why this exists.** `tools/citykit/wedge.py` compares the shipped frame's low-frequency energy
## against the lead's probe rung 3, which replaces the albedo with plain white and a `base_color` of
## (0.25, 0.20, 0.16) — a dark panel, 0.25 LINEAR. The r8 §1 table asks for white paint at 0.72-0.80
## STORED sRGB, which is 0.48-0.60 linear: roughly 2.2x brighter than the reference. A flat surface
## that is 2.2x brighter has ~2.2x the low-frequency std under the same lighting, before any texture
## variation at all, so the 1.5x gate may simply be below the floor the mandated albedo imposes.
##
## This measures that floor instead of arguing about it: it shoots each camera twice, once as shipped
## and once with the albedo replaced by a FLAT colour passed on the command line. Run it with the
## lead's own reference colour and the wedge ratio is 1.0 by construction; run it with the r8 target
## and the number it prints is the best any texture at that brightness could score.
##
## It writes `<out>_<cam>_shipped.jpg` and `<out>_<cam>_flat.jpg`.

const CITY_SCENE := "res://world/city.tscn"
const DEFAULT_CAMS := "res://world/kit/tests/cams_r8probe.json"

var _out: String = "r8floor"
var _outdir: String = ArtRepo.at("captures")  ## derived from the project dir (city-art r12 §3), not literal
var _cams: Array = []
var _warm: int = 40
var _floor: float = 0.55
var _cam: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = _arg(args, "--out=", _out)
	_outdir = _arg(args, "--outdir=", _outdir)
	_warm = int(_arg(args, "--probe-warm=", "40"))
	_floor = float(_arg(args, "--floor-color=", "0.55"))
	_cams = _load_cams(_arg(args, "--probe-cams=", DEFAULT_CAMS))
	var packed := load(CITY_SCENE) as PackedScene
	if packed == null:
		push_error("FLOOR cannot load " + CITY_SCENE)
		get_tree().quit(1)
		return
	add_child(packed.instantiate())
	_run.call_deferred()


static func _arg(args: PackedStringArray, flag: String, def: String) -> String:
	for a in args:
		if a.begins_with(flag):
			return a.substr(flag.length())
	return def


func _load_cams(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("FLOOR no camera list at " + path)
		return []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data as Array if data is Array else []


func _run() -> void:
	var kit: Node = null
	for i in 900:
		kit = get_tree().root.find_child("KitPlacer", true, false)
		if kit != null:
			await _frames(30)
			break
		await get_tree().process_frame
	if kit == null:
		push_error("FLOOR no KitPlacer after 900 frames")
		get_tree().quit(1)
		return
	_hide_canvas(get_tree().root)
	_cam = Camera3D.new()
	_cam.near = 0.05
	_cam.far = 6000.0
	add_child(_cam)
	var mats := _shader_mats(kit)
	if mats.is_empty():
		push_error("FLOOR the KitPlacer has no ShaderMaterial")
		get_tree().quit(1)
		return
	print("FLOOR materials=%d cams=%d flat colour=%.3f linear" % [mats.size(), _cams.size(), _floor])
	var white := ImageTexture.create_from_image(_white_image())
	for spec in _cams:
		var cam_name := String(spec.get("name", "cam"))
		_cam.fov = float(spec.get("fov", 70.0))
		_cam.global_position = _vec(spec["pos"])
		_cam.look_at(_vec(spec["look"]), Vector3.UP)
		_cam.make_current()
		await _frames(_warm)
		await _save("%s_%s_shipped" % [_out, cam_name])
		var before: Array[Texture2D] = []
		var tint: Array[Color] = []
		for m in mats:
			before.append(m.get_shader_parameter(&"tex_albedo") as Texture2D)
			tint.append(m.get_shader_parameter(&"base_color") as Color)
			m.set_shader_parameter(&"tex_albedo", white)
			m.set_shader_parameter(&"base_color", Color(_floor, _floor, _floor))
		await _frames(_warm)
		await _save("%s_%s_flat" % [_out, cam_name])
		for i in mats.size():
			mats[i].set_shader_parameter(&"tex_albedo", before[i])
			mats[i].set_shader_parameter(&"base_color", tint[i])
	print("FLOOR done cameras=%d" % _cams.size())
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await get_tree().process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_outdir)
	var path := _outdir.path_join(name + ".jpg")
	var err := img.save_jpg(path, 0.85)
	print("FLOOR shot %s%s" % [path, "" if err == OK else "  SAVE FAILED %d" % err])


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


## Every distinct ShaderMaterial the kit draws with — the lead's probe's walk, kept identical so the
## two ladders really are looking at the same set.
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
		for child in n.get_children():
			stack.append(child)
	return out
