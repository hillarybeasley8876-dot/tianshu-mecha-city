extends Hero3Probe
## hero-v3 r7 — the lit close-up sheet (lead brief r7 gate 1): five angles round the hero at four
## times of day, IN THE CITY, so the material work is judged on the light the game actually ships
## rather than on a probe scene's ProceduralSky.
##
##   tools/godot.sh shot --scene=res://player/model/hero3/tests/hero3_look.tscn --out=look \
##       --look-tods=0,0.5,0.85,1.0 --times=1800
##
## Writes `tmp/hero-v3/look/<tag>_p<t>_<angle>.png` and `tmp/hero-v3/look/<tag>_meta.json`, which
## carries the projected screen position of the visor and the chest grille so `look.py` can cut an
## exact 3x crop round each instead of a hand-placed rectangle.
##
## `--look-debug=palette` additionally renders the shell's mask passes with the WORLD HIDDEN, which is
## what `palette.py` measures the black-and-gold gate on: the trim's mean hue and the plates' mean
## luma, on a real frame, with no guessing about which pixels are which. The world has to be hidden --
## through the full post stack the bloom spreads a bright mask across the whole frame, which made the
## first attempt read 3.9 M "trim" pixels out of a 5.7 M frame.

const FRAMES_REL := "tmp/hero-v3/look"
## The one-bone silhouette shader the r8 visor gate measures against.
const BONE_MASK := "res://player/model/hero3/tests/hero3_bonemask.gdshader"
## The mask frames are drawn mid-grey, not white: pure white is above the bloom threshold and the post
## stack would halo every mask outward. `hero3_bonemask.gdshader` and the glow shader's `flat_mask`
## hook both hardcode the same 0.5.
const MASK_GREY := 0.5
## Bearing measured FROM the direction the mech is facing, so the angles mean what they say whatever
## yaw it spawns at: 0 is dead in front of it, 90 is its left side, 180 is behind it. A `var`, not a
## `const`, because `--look-angles` narrows the list.
var ANGLES: Array = [
	{"name": "front34", "az": 35.0, "dist": 34.0, "height": 13.0, "look": 9.0},
	{"name": "side", "az": 90.0, "dist": 34.0, "height": 12.0, "look": 9.0},
	{"name": "rear34", "az": 145.0, "dist": 34.0, "height": 13.0, "look": 9.0},
	{"name": "front", "az": 0.0, "dist": 30.0, "height": 10.0, "look": 9.0},
	{"name": "top", "az": 20.0, "dist": 14.0, "height": 30.0, "look": 8.0},
]
## The Insertion Pier spawn the trailer's cold open and drop use: open sky, lit towers behind.
const SPAWN := [-560.0, 7.5, 600.0, 54.0]

var _cam: Camera3D
var _tods: PackedFloat64Array = PackedFloat64Array()
var _tod: TimeOfDay
var _debug: Array[String] = []
var _meta: Array = []
var _hero: Array[GeometryInstance3D] = []
var _body: Array[GeometryInstance3D] = []
## node -> the visibility it had before the mask passes started, so `_show_all` is exact.
var _orig: Dictionary = {}
## material_override -> what it was, so a mask pass can put the shipping material back.
var _saved: Dictionary = {}


func _ready() -> void:
	boot()
	_cam = Camera3D.new()
	_cam.name = "LookCamera"
	_cam.near = 0.05
	_cam.far = 6000.0
	_cam.fov = 40.0
	add_child(_cam)
	if not _parse():
		get_tree().quit(1)
		return
	_run.call_deferred()


func _parse() -> bool:
	probe_dir(FRAMES_REL)
	warm = int(Game.flag("look-warm", "40"))
	tag = Game.flag("look-tag", "r7")
	for t in Game.flag("look-tods", "0,0.5,0.85,1.0").split(",", false):
		_tods.append(float(t))
	if _tods.is_empty():
		push_error("hero3_look: --look-tods is empty")
		return false
	for d in Game.flag("look-debug", "").split(",", false):
		_debug.append(d)
	var want := Game.flag("look-angles", "")
	if not want.is_empty():
		var keep: Array = []
		for a in ANGLES:
			if want.split(",", false).has(String(a["name"])):
				keep.append(a)
		if keep.is_empty():
			push_error("hero3_look: --look-angles matched nothing")
			return false
		ANGLES = keep
	print("LOOK tag=%s tods=%s angles=%d debug=%s out=%s"
		% [tag, str(_tods), ANGLES.size(), str(_debug), out_dir])
	return true


func _run() -> void:
	await wait_world()
	await frames(warm)
	hide_canvas(get_tree().root)
	_tod = time_of_day()
	if _tod == null:
		push_warning("hero3_look: no TimeOfDay — every row is the default light")
	(Game.player as Node3D).call(&"debug_teleport", [SPAWN[0], SPAWN[1], SPAWN[2]], SPAWN[3])
	if not _debug.is_empty():
		_collect()
	for p in _tods:
		if _tod != null:
			_tod.set_progress_immediate(p)
		await frames(warm)
		for a in ANGLES:
			await _one(p, a as Dictionary)
	_write_meta()
	print("LOOK done")
	get_tree().quit(0)


func _one(p: float, a: Dictionary) -> void:
	_aim(a)
	await frames(10)
	var stem := "%s_p%s_%s" % [tag, str(p).replace(".", ""), String(a["name"])]
	var img := await grab()
	save_png(img, stem)
	_meta.append({"stem": stem, "tod": p, "angle": String(a["name"]),
			"w": img.get_width(), "h": img.get_height(),
			"visor_uv": _project(_glow_at("visor")), "vent_uv": _project(_glow_at("vent"))})
	if _debug.has("palette"):
		await _mask_frames(stem)
	if _debug.has("glow"):
		await _glow_frames(stem)
	print("LOOK %-16s tod=%.2f" % [stem, p])


## Three extra frames per camera for the r8 close-up gates (lead brief r8 items 1 and 2):
##   `_noglow` the beauty frame with the modelled panels hidden -- what the ATLAS is doing on its own,
##             which is how the cream blotches inside the grille get attributed rather than guessed at;
##   `_panel`  the panels alone, flat white, world hidden -- an exact screen mask of both openings;
##   `_head`   the helmet alone -- an exact screen mask to test the visor against.
func _glow_frames(stem: String) -> void:
	_panels_visible(false)
	await frames(HIDE_SETTLE)
	save_png(await grab(), stem + "_noglow")
	_vent_gain(0.0)
	await frames(HIDE_SETTLE)
	save_png(await grab(), stem + "_noglow_novent")
	_panels_visible(true)
	await frames(HIDE_SETTLE)
	save_png(await grab(), stem + "_novent")
	_vent_gain(-1.0)
	_hide_world()
	_hide(_hero, [] as Array[GeometryInstance3D])
	await frames(HIDE_SETTLE)
	save_png(await grab(), stem + "_glowbg")
	var panels := _panel_nodes()
	_hide(_hero, panels)
	_flatten(panels)
	await frames(HIDE_SETTLE)
	save_png(await grab(), stem + "_panel")
	_restore(panels)
	_hide(_hero, _body)
	_bone_mask("Head")
	await frames(HIDE_SETTLE)
	save_png(await grab(), stem + "_head")
	_bone_mask("")
	_show_all()
	await frames(4)


## Force the shell's vent emission gain, to attribute a bright patch to the atlas's own emission
## rather than to the modelled panel. Negative restores whatever `Hero3Shade` had set.
func _vent_gain(v: float) -> void:
	var model := (Game.player as Node3D).call(&"model") as Node3D
	var shade: Hero3Shade = model.rig.shade
	if shade == null or shade.shell == null:
		return
	if v < 0.0:
		shade.shell.set_shader_parameter(&"vent_gain", Hero3Shade.VENT_GAIN)
	else:
		shade.shell.set_shader_parameter(&"vent_gain", v)


## The two opening panels ONLY: the modelled light sources include seven drone tips on the back, and
## with the world hidden nothing occludes them, so they would land in the panel mask and be measured
## as if they were the visor.
func _panel_nodes() -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for node in _hero:
		if String(node.name).begins_with("GlowPanel"):
			out.append(node)
	return out


func _panels_visible(on: bool) -> void:
	for node in _panel_nodes():
		node.visible = on


## The panels' own `flat_mask` hook: flat grey, but the sheet's ALPHA is untouched, so the mask is the
## part of the panel that is actually visible rather than the whole quad including its feather.
func _flatten(nodes: Array[GeometryInstance3D]) -> void:
	for node in nodes:
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.material_override as ShaderMaterial
		if mat == null:
			continue
		_saved[node] = mat.get_shader_parameter(&"flat_mask")
		mat.set_shader_parameter(&"flat_mask", 1)


func _restore(nodes: Array[GeometryInstance3D]) -> void:
	for node in nodes:
		var mi := node as MeshInstance3D
		if mi == null or not _saved.has(node):
			continue
		var mat := mi.material_override as ShaderMaterial
		if mat == null:
			continue
		# `get_shader_parameter` answers null for a uniform that was never written, and `int(null)`
		# is a runtime error in GDScript -- which left `flat_mask` stuck ON for every camera after
		# the first, so their beauty frames were the flat grey mask and not the shipping panel.
		var prev: Variant = _saved[node]
		mat.set_shader_parameter(&"flat_mask", int(prev) if prev != null else 0)
	_saved.clear()


## Draw only the armour fragments whose dominant skin bind is `bone` ("" clears it).
func _bone_mask(bone: String) -> void:
	for node in _body:
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		if bone.is_empty():
			if _saved.has(mi):
				mi.material_override = _saved[mi]
			continue
		_saved[mi] = mi.material_override
		var mat := ShaderMaterial.new()
		mat.shader = load(BONE_MASK) as Shader
		mat.set_shader_parameter(&"bind_index", _bind_of(mi, bone))
		mi.material_override = mat
	if bone.is_empty():
		_saved.clear()


## The skin's bind index for a bone name: ARRAY_BONES carries bind indices, not skeleton indices.
func _bind_of(mi: MeshInstance3D, bone: String) -> int:
	var skel := mi.get_node_or_null(^"../Skeleton3D") as Skeleton3D
	if skel == null:
		skel = mi.get_parent() as Skeleton3D
	var want := skel.find_bone(bone) if skel != null else -1
	for b in mi.skin.get_bind_count():
		var idx := mi.skin.get_bind_bone(b)
		if idx < 0 and skel != null:
			idx = skel.find_bone(String(mi.skin.get_bind_name(b)))
		if idx == want:
			return b
	push_error("hero3_look: no skin bind for bone %s" % bone)
	return -1


## Three frames with the world hidden and only the armour surface visible: the bare background, the
## gold mask and the plate mask. `mask - bg` is then an exact silhouette and the bright pixels inside
## it are the trim (or the plates) -- the same trick `hero3_read.gd` uses.
func _mask_frames(stem: String) -> void:
	_hide_world()
	_hide(_hero, _body)
	await frames(HIDE_SETTLE)
	save_png(await grab(), stem + "_bg")
	for which in ["gold", "plate"]:
		_set_debug(which)
		await frames(HIDE_SETTLE)
		save_png(await grab(), "%s_%s" % [stem, which])
	_set_debug("")
	_show_all()
	await frames(4)


## The hero's own geometry, and the armour surface on its own.
func _collect() -> void:
	var model := (Game.player as Node3D).call(&"model") as Node3D
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is GeometryInstance3D:
			_hero.append(node as GeometryInstance3D)
			if String(node.name).begins_with("Hero3Body"):
				_body.append(node as GeometryInstance3D)
		stack.append_array(node.get_children())
	print("LOOK hero meshes %d, armour surfaces %d" % [_hero.size(), _body.size()])


func _hide_world() -> void:
	_walk(get_tree().root, func(node: GeometryInstance3D) -> void:
		if not _hero.has(node) and node.visible:
			if not _orig.has(node):
				_orig[node] = true
			node.visible = false)


## Hide everything in `nodes` except what is in `keep`. This SETS visibility rather than only taking
## it away: the mask passes call it several times in a row and a hide-only version cannot bring a node
## back for the next pass.
func _hide(nodes: Array[GeometryInstance3D], keep: Array[GeometryInstance3D]) -> void:
	for node in nodes:
		if not _orig.has(node):
			_orig[node] = node.visible
		node.visible = keep.has(node)


func _show_all() -> void:
	for node: GeometryInstance3D in _orig:
		if is_instance_valid(node):
			node.visible = bool(_orig[node])
	_orig.clear()



func _walk(node: Node, fn: Callable) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			fn.call(child as GeometryInstance3D)
		_walk(child, fn)


func _set_debug(which: String) -> void:
	var model := (Game.player as Node3D).call(&"model") as Node3D
	var shade: Hero3Shade = model.rig.shade
	if shade != null:
		shade.debug_mask(which)


## The grille's world position, so the sheet can crop exactly where the visor and the vent are.
func _glow_at(which: String) -> Vector3:
	var model := (Game.player as Node3D).call(&"model") as Node3D
	var glow: Hero3Glow = model.rig.glow
	if glow == null:
		return Vector3.ZERO
	var local: Vector3 = glow.visor_at if which == "visor" else glow.vent_at
	return model.rig.skeleton.to_global(local)


## NORMALISED screen position, not pixels: `unproject_position` answers in the viewport's own space
## and the captured image is the backing store, which on this display is 1.89x larger. Dividing by the
## viewport's own rect makes the number resolution-independent.
func _project(world: Vector3) -> Array:
	if world == Vector3.ZERO or _cam.is_position_behind(world):
		return []
	var px := _cam.unproject_position(world)
	var vp := get_viewport().get_visible_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		return []
	return [px.x / vp.x, px.y / vp.y]


func _write_meta() -> void:
	var path := out_dir.path_join("%s_meta.json" % tag)
	var fh := FileAccess.open(path, FileAccess.WRITE)
	if fh == null:
		push_error("hero3_look: cannot write %s" % path)
		return
	fh.store_string(JSON.stringify(_meta, "  "))
	fh.close()
	print("LOOK wrote %s (%d frames)" % [path, _meta.size()])


func _aim(a: Dictionary) -> void:
	var player := Game.player as Node3D
	var at := player.global_position + Vector3.UP * float(a["look"])
	# the direction the mech is looking, so `az` is a bearing off its own face
	var facing := -player.global_transform.basis.z
	var dir := Basis(Vector3.UP, deg_to_rad(float(a["az"]))) * facing
	_cam.global_position = player.global_position + dir * float(a["dist"]) \
			+ Vector3.UP * float(a["height"])
	_cam.look_at(at, Vector3.UP)
	_cam.current = true
