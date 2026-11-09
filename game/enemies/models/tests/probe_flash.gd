extends Node3D
## Hit flash and attack tell probe (monster-assets, lead r5 item 2). Windowed — it needs a real
## renderer, so it runs through `tools/godot.sh run`, not `test`.
##
##   tools/godot.sh run res://enemies/models/tests/probe_flash.tscn 90
##
## The acceptance pass found two ways a monster turned into a flat cut-out with no form:
##   * the hit flash added `hit_flash * 4.0` of pure white to every texel — 2.4 against the monster's
##     own emission of 2.0 — so one missile impact, or a salvo re-arming it, made a mantis a "pale
##     ghost" (trailer r2, `captures/trailer/sheets/ghost_mantis_hitflash.jpg`);
##   * the tell was `mix(glow, tell_color * (0.8 + 2.4 * length(glow)), tell)`, and that constant
##     0.8 landed on every texel, so a windup took the median luma from 0.04-0.26 to 0.82-0.85 with
##     84-98 % of the pixels above 0.5.
##
## For every type this renders three frames against a black background — neutral, `set_hit_flash(1)`,
## `set_telegraph(parryable, 1)` — and prints the median luma of the monster's own pixels plus the
## fraction above 0.5. The gate: the carapace median stays within 1.5x of neutral for both.
## The frames are written to `captures/monsters_flash_<type>_<mode>.jpg` for the review sheets.

const TYPES: Array[StringName] = [&"ripper", &"mantis", &"spitter", &"harrier", &"juggernaut",
		&"titan", &"hive"]
## the lead's bar: the flash and the tell may brighten the creature, not replace it
const LUMA_GATE := 1.5
## a pixel darker than this is the black background, not the monster
const BACKGROUND := 0.004

var _camera: Camera3D
var _root: Node3D
## Where the frames go. `tools/godot.sh run` cannot pass extra arguments through, so this defaults
## to the project's own captures/ directory.
var _out: String = ProjectSettings.globalize_path("res://").path_join("..").path_join("captures")
## 97th-percentile luma of the last shot: the veins and cores, which the flash and the tell are
## supposed to brighten even while the carapace median stays put.
var _last_bright: float = 0.0
var _neutral_bright: float = 0.0
var _flash_bright: float = 0.0
var _tell_bright: float = 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--flash-out="):
			_out = arg.trim_prefix("--flash-out=")
	DirAccess.make_dir_recursive_absolute(_out)
	var types: Array[StringName] = TYPES
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--flash-types="):
			types = []
			for t in arg.trim_prefix("--flash-types=").split(",", false):
				types.append(StringName(t))
	_build_stage()
	for type in types:
		await _probe(type)
	print("FLASH done")
	get_tree().quit(0)


func _build_stage() -> void:
	_root = Node3D.new()
	add_child(_root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.62)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 138, 0)
	key.light_energy = 1.4
	add_child(key)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	add_child(_camera)


func _probe(type: StringName) -> void:
	var path := "res://enemies/models/%s/%s_model.tscn" % [type, type]
	var packed := load(path) as PackedScene
	if packed == null:
		print("FLASH %s FAIL cannot load %s" % [type, path])
		return
	var model := packed.instantiate() as Node3D
	_root.add_child(model)
	await get_tree().process_frame
	var size: float = maxf(model.call("measured_size"), 1.0)
	_camera.position = Vector3(size * 1.15, size * 0.62, size * 1.9)
	_camera.look_at(Vector3(0.0, size * 0.45, 0.0), Vector3.UP)
	var neutral := await _shot(model, type, "neutral", Callable())
	_neutral_bright = _last_bright
	var flash := await _shot(model, type, "flash",
			func() -> void: _apply(model, &"set_hit_flash", 1.0))
	_flash_bright = _last_bright
	var tell := await _shot(model, type, "tell",
			func() -> void: _apply(model, &"set_telegraph", [&"parryable", 1.0]))
	_tell_bright = _last_bright
	print("FLASH %-11s neutral median %.3f bright %.3f (%.0f%% > 0.5)"
			% [type, neutral.x, _neutral_bright, neutral.y * 100.0])
	print("FLASH %-11s flash   median %.3f (%.2fx) bright %.3f (%.2fx) %.0f%% > 0.5  %s"
			% [type, flash.x, flash.x / maxf(neutral.x, 1e-4), _flash_bright,
				_flash_bright / maxf(_neutral_bright, 1e-4), flash.y * 100.0,
				_verdict(flash.x, neutral.x)])
	print("FLASH %-11s tell    median %.3f (%.2fx) bright %.3f (%.2fx) %.0f%% > 0.5  %s"
			% [type, tell.x, tell.x / maxf(neutral.x, 1e-4), _tell_bright,
				_tell_bright / maxf(_neutral_bright, 1e-4), tell.y * 100.0,
				_verdict(tell.x, neutral.x)])
	model.queue_free()
	await get_tree().process_frame


## `HiveModel` has no telegraph (it is not a monster), so every call is guarded.
func _apply(model: Node3D, method: StringName, value: Variant) -> void:
	if model.has_method(method):
		if value is Array:
			model.callv(method, value as Array)
		else:
			model.call(method, value)


func _verdict(value: float, neutral: float) -> String:
	return "OK" if value <= neutral * LUMA_GATE else "OVER GATE"


## Render one frame and return (median luma, fraction above 0.5) over the monster's pixels.
func _shot(model: Node3D, type: StringName, mode: String, setup: Callable) -> Vector2:
	_apply(model, &"set_hit_flash", 0.0)
	_apply(model, &"set_telegraph", [&"parryable", 0.0])
	if setup.is_valid():
		setup.call()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if not _out.is_empty():
		image.save_jpg("%s/monsters_flash_%s_%s.jpg" % [_out, type, mode], 0.88)
	var luma := PackedFloat32Array()
	var over := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var c := image.get_pixel(x, y)
			if maxf(c.r, maxf(c.g, c.b)) < BACKGROUND:
				continue
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			luma.append(l)
			if l > 0.5:
				over += 1
	if luma.is_empty():
		push_error("probe_flash(%s/%s): the frame is empty — is the model on screen?" % [type, mode])
		return Vector2.ZERO
	var sorted := luma.duplicate()
	sorted.sort()
	_last_bright = sorted[int(sorted.size() * 0.97)]
	return Vector2(sorted[sorted.size() / 2], float(over) / float(sorted.size()))
