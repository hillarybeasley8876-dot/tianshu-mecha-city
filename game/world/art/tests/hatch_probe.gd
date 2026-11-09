extends Node3D
## city-art r16b §2 — the HATCH probe. The diagonal ripple that covers the sky is intermittent: on the
## r15 frames it measures 0.004 to 1.24 /255 at a FIXED screen-space frequency (17.34 px, 118.3 deg),
## and on frames rendered since it is under 0.06. Everything that could make it come and go is a
## function of how long the process has been running — the lens grain's hash argument carries
## `Time.get_ticks_msec()`, so a hash that is clean white noise in the first seconds is a quantised,
## structured field minutes later — so this probe holds ONE camera and ONE time of day and takes the
## same crop every `--hatch-gap` seconds, which turns "is it there" into a curve against elapsed time.
##
##   MC_WINDOW_OK=1 tools/godot.sh shot --scene=res://world/art/tests/hatch_probe.tscn --out=hatch \
##     --times=1800 --hatch-seconds=600 --hatch-gap=5 --hatch-tag=base
##
## Each sample is a 512x512 crop at the patch's own coordinates, so 120 samples cost 90 MB and the
## analysis (`tmp/city-art/r16b/hatch_amp.py`) reads them without loading 5.7 Mpx frames.

const CITY_SCENE := "res://world/city.tscn"
const POST_SCENE := "res://world/post/post_stack.tscn"
const OUT_REL := "tmp/city-art/r16b/hatch"
const CROP := 512
const DRAW_TIMEOUT_FRAMES := 240

var _city: Node3D
var _tod: TimeOfDay
var _cam: Camera3D
var _out: String = ""
var _tag: String = "base"
var _drew: bool = false


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
	_tag = Game.flag("hatch-tag", "base")
	_out = ArtRepo.at(OUT_REL).path_join(_tag)
	DirAccess.make_dir_recursive_absolute(_out)
	var spec := Game.flag("hatch-cam", "res://world/art/tests/cams_r16b.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(spec))
	if not (parsed is Array) or (parsed as Array).is_empty():
		push_error("hatch_probe: %s is not a non-empty JSON array" % spec)
		return false
	var want := Game.flag("hatch-name", "S02city")
	var cam: Dictionary = (parsed as Array)[0]
	for c: Dictionary in parsed as Array:
		if String(c["name"]) == want:
			cam = c
	var pos: Array = cam["pos"]
	var look: Array = cam["look"]
	_cam.fov = float(cam.get("fov", 52.0))
	_cam.position = Vector3(pos[0], pos[1], pos[2])
	_cam.look_at(Vector3(look[0], look[1], look[2]), Vector3.UP)
	_cam.current = true
	if _tod != null:
		_tod.set_progress_immediate(float(Game.flag("tod", "0.6")))
	return true


## One crop every `gap` seconds for `seconds`, each named by the elapsed whole seconds so the analysis
## can plot the amplitude against the process's age.
func _run() -> void:
	var seconds := float(Game.flag("hatch-seconds", "600"))
	var gap := float(Game.flag("hatch-gap", "5"))
	var t0 := Time.get_ticks_msec()
	var next_at := 0.0
	while true:
		var elapsed := float(Time.get_ticks_msec() - t0) * 0.001
		if elapsed > seconds:
			break
		if elapsed >= next_at:
			await _frames(2)
			var img := await _grab()
			# The crop is a FRACTION of the frame, not a pixel: the tool window's backing store is not
			# the same size from run to run, and a fixed pixel box lands on a building edge on one
			# machine and on flat sky on another (which is how the first run of this probe measured a
			# high-pass std of 20/255 instead of 0.6).
			var at := Vector2i(int(float(img.get_width()) * 0.34), int(float(img.get_height()) * 0.20))
			var crop := img.get_region(Rect2i(at - Vector2i(CROP, CROP) / 2, Vector2i(CROP, CROP)))
			var name := "%s_t%04d.png" % [_tag, int(elapsed)]
			if crop.save_png(_out.path_join(name)) != OK:
				push_error("hatch_probe: cannot write %s" % name)
			print("HATCH %6.1f s -> %s (%dx%d frame, crop at %s)"
				% [elapsed, name, img.get_width(), img.get_height(), at])
			next_at += gap
		await _frames(4)
	print("HATCH done")
	get_tree().quit(0)


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
		push_warning("hatch_probe: frame_post_draw never fired — this frame is the previous one")
		if RenderingServer.frame_post_draw.is_connected(_on_drawn):
			RenderingServer.frame_post_draw.disconnect(_on_drawn)
	return get_viewport().get_texture().get_image()


func _on_drawn() -> void:
	_drew = true


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find_tod() -> TimeOfDay:
	for n in get_tree().get_nodes_in_group(&"time_of_day"):
		if n is TimeOfDay:
			return n as TimeOfDay
	push_warning("hatch_probe: no node in group time_of_day")
	return null


func _add_post() -> void:
	if Game.has_flag("no-post") or not ResourceLoader.exists(POST_SCENE):
		return
	add_child((load(POST_SCENE) as PackedScene).instantiate())


func _instance_city() -> Node3D:
	if not ResourceLoader.exists(CITY_SCENE):
		push_error("hatch_probe: %s does not exist" % CITY_SCENE)
		return null
	var node := (load(CITY_SCENE) as PackedScene).instantiate() as Node3D
	add_child(node)
	for placeholder in [^"BlockoutEnvironment", ^"Sun"]:
		var n := node.get_node_or_null(NodePath(placeholder))
		if n != null:
			node.remove_child(n)
			n.queue_free()
	return node
