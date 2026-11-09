extends Node3D
## city-kit props QA studio: every Tripo prop as SHIPPED (through `PropScatter.load_mesh`, the same
## path the game draws) on a 1 m / 10 m grid floor under a neutral three-point rig that turns with the
## camera, once in the shipped material and once in a clay pass whose BACK faces are flat magenta.
## A hole shows the magenta inside it, a flipped face shows magenta on the outside.
##   tools/godot.sh run res://world/kit/tests/props_studio.tscn 600 -- \
##       --qa-out=/abs/dir --qa-tag=before [--qa-props=a,b] [--qa-views=front,top,q34]
## The report lists each prop's AABB, longest side against `PropPlacer.PROP_SIZE_M` and its triangle
## count, so a bad import shows without opening an image.

const CLAY_SHADER := preload("res://world/kit/tests/props_clay.gdshader")
const GRID_SHADER := preload("res://world/kit/tests/props_grid.gdshader")
const FOV := 30.0
const MARGIN := 0.86
const SHOT_W := 800
const SHOT_H := 450
## [name, direction from the subject toward the eye, up hint]
const VIEWS := {
	"front": [Vector3(0.0, 0.12, -1.0), Vector3.UP],
	"right": [Vector3(1.0, 0.12, 0.0), Vector3.UP],
	"back": [Vector3(0.0, 0.12, 1.0), Vector3.UP],
	"left": [Vector3(-1.0, 0.12, 0.0), Vector3.UP],
	"top": [Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0)],
	"q34": [Vector3(-0.75, 0.45, -0.8), Vector3.UP],
}

var _out: String = ""
var _tag: String = "props"
var _views: PackedStringArray = []
var _passes: PackedStringArray = []
var _cam: Camera3D
var _label: Label
var _clay: ShaderMaterial
var _rig: Node3D
var _lines: PackedStringArray = []
var _shots: int = 0
var _vp: SubViewport


func _ready() -> void:
	_out = Game.flag("qa-out", "")
	if _out.is_empty():
		push_error("props_studio: --qa-out=/abs/dir is required")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_tag = Game.flag("qa-tag", "props")
	_views = _flag_list("qa-views", "front,right,back,left,top,q34")
	_passes = _flag_list("qa-pass", "tex,clay")
	_vp = _offscreen(Vector2i(1600, 900))
	_studio()
	_hud()
	_cam = Camera3D.new()
	_cam.near = 0.05
	_cam.far = 6000.0
	_vp.add_child(_cam)
	_cam.current = true
	_clay = ShaderMaterial.new()
	_clay.shader = CLAY_SHADER
	_run.call_deferred()


func _flag_list(flag: String, fallback: String) -> PackedStringArray:
	var spec := Game.flag(flag, "")
	return (spec if not spec.is_empty() else fallback).split(",", false)


## Renders offscreen. A fully occluded macOS window stops drawing (frame_post_draw never fires and
## every capture hangs), and the machine is shared with other units' heavy slots, so this shrinks the
## real window to a small always-on-top tile and renders into a SubViewport of the capture size.
func _offscreen(size: Vector2i) -> SubViewport:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_size(Vector2i(320, 180))
	var screen := DisplayServer.screen_get_usable_rect()
	# `--qa-tile=N` picks the screen corner (0 bottom-right, 1 bottom-left, 2 top-right, 3 top-left)
	# so two of these runs can never cover each other.
	var slot := int(Game.flag("qa-tile", "0")) % 4
	var at := screen.position
	at.x += 20 if slot % 2 == 1 else screen.size.x - 340
	at.y += 40 if slot >= 2 else screen.size.y - 200
	DisplayServer.window_set_position(at)
	var vp := SubViewport.new()
	vp.name = "PropsOffscreen"
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	add_child(vp)
	return vp


func _studio() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.30, 0.31, 0.33)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.64, 0.66, 0.70)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_rig = Node3D.new()
	_rig.name = "LightRig"
	add_child(_rig)
	_light(Vector3(-1.0, 1.3, -1.2), 1.8, true)
	_light(Vector3(1.2, 0.4, -0.8), 0.45, false)
	_light(Vector3(0.3, 1.0, 1.3), 0.9, false)
	var plane := PlaneMesh.new()
	plane.size = Vector2(3000.0, 3000.0)
	var mat := ShaderMaterial.new()
	mat.shader = GRID_SHADER
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	ground.material_override = mat
	add_child(ground)


func _light(from: Vector3, energy: float, shadow: bool) -> void:
	var l := DirectionalLight3D.new()
	l.light_energy = energy
	l.shadow_enabled = shadow
	l.directional_shadow_max_distance = 700.0
	_rig.add_child(l)
	l.look_at_from_position(from * 10.0, Vector3.ZERO, Vector3.UP)


func _hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	_vp.add_child(layer)
	_label = Label.new()
	_label.position = Vector2(20.0, 14.0)
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.85))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_label)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.resize(SHOT_W, SHOT_H, Image.INTERPOLATE_LANCZOS)
	var path := _out.path_join("%s_%s.jpg" % [_tag, name])
	var err := img.save_jpg(path, 0.88)
	if err != OK:
		_note("FAIL save %s (%d)" % [path, err])
	_shots += 1


func _note(line: String) -> void:
	_lines.append(line)
	print("QA ", line)


## Pinhole fit: the smallest distance along `dir` at which every point is inside MARGIN of the frame.
func _frame(points: PackedVector3Array, dir: Vector3, up_hint: Vector3) -> void:
	var box := _bounds(points)
	var centre := box.get_center()
	var z := dir.normalized()
	var x := up_hint.cross(z).normalized()
	var y := z.cross(x).normalized()
	var aspect := float(_vp.size.x) / maxf(float(_vp.size.y), 1.0)
	var tv := tan(deg_to_rad(FOV) * 0.5) * MARGIN
	var th := tv * aspect
	var d := 0.5
	for p in points:
		var r := p - centre
		var pz := r.dot(z)
		d = maxf(d, pz + absf(r.dot(x)) / th)
		d = maxf(d, pz + absf(r.dot(y)) / tv)
	_cam.fov = FOV
	_cam.global_transform = Transform3D(Basis(x, y, z), centre + z * d)
	_turn_lights(z)


## The rig is authored for a camera in front (-Z); it turns with the camera so every side gets the
## same key / fill / rim.
func _turn_lights(dir: Vector3) -> void:
	var h := Vector2(dir.x, dir.z)
	if h.length() < 0.2:
		_rig.rotation.y = 0.0
		return
	_rig.rotation.y = atan2(-dir.x, -dir.z)


func _bounds(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box


## A subsample of the mesh surface in world space; enough to frame and to measure the AABB.
func _points(mi: MeshInstance3D, max_points: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	if mi.mesh == null:
		return out
	var total := 0
	for s in mi.mesh.get_surface_count():
		total += mi.mesh.surface_get_array_len(s)
	var step := maxi(1, total / maxi(max_points, 1))
	for s in mi.mesh.get_surface_count():
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for i in range(0, verts.size(), step):
			out.append(mi.global_transform * verts[i])
	return out


func _tri_count(mesh: Mesh) -> int:
	var tris := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			tris += (idx as PackedInt32Array).size() / 3
		else:
			tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return tris


func _set_clay(mi: MeshInstance3D, on: bool) -> void:
	mi.material_override = _clay if on else null


func _props() -> Array[StringName]:
	var spec := Game.flag("qa-props", "")
	var names: Array = PropPlacer.PROP_SIZE_M.keys()
	names.sort()
	var out: Array[StringName] = []
	for n: Variant in names:
		var key := StringName(n)
		if spec.is_empty() or spec.split(",", false).has(String(key)):
			out.append(key)
	return out


func _run() -> void:
	await _frames(10)
	for prop in _props():
		var mesh := PropScatter.load_mesh(prop)
		if mesh == null:
			_note("FAIL %s has no mesh" % prop)
			continue
		var mi := MeshInstance3D.new()
		mi.name = String(prop)
		mi.mesh = mesh
		add_child(mi)
		await _frames(1)
		var pts := _points(mi, 20000)
		var box := _bounds(pts)
		var target := float(PropPlacer.PROP_SIZE_M.get(prop, 0.0))
		var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
		_note("PROP %-16s tris %-6d longest %6.2f target %5.1f base_y %6.2f size %s"
				% [prop, _tri_count(mesh), longest, target, box.position.y, str(box.size)])
		for pass_name in _passes:
			_set_clay(mi, pass_name == "clay")
			for view in _views:
				if not VIEWS.has(view):
					continue
				var v: Array = VIEWS[view]
				_frame(pts, v[0], v[1])
				_label.text = "%s  %s  %s  [%s]" % [prop, view, pass_name, _tag]
				await _frames(3)
				await _snap("%s_%s" % [prop, pass_name + "_" + view])
		_set_clay(mi, false)
		mi.queue_free()
		await _frames(2)
	var path := _out.path_join(_tag + "_report.txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	print("QA done tag=%s props=%d shots=%d report=%s" % [_tag, _props().size(), _shots, path])
	get_tree().quit(0)
