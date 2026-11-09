extends Node3D
## city-art r13, the occluder gate: a 6 s camera dolly through A1 -> A3 at street height, recorded with
## occlusion culling on and off. The two runs are the same scene on the same build, so any pixel that
## differs between them is something the occluders hid — which is the one failure mode that matters.
##
##   tools/godot.sh shot --scene=res://world/art/tests/occ_dolly.tscn --out=occ --occ=1 \
##       --dolly-out=tmp/city-art/r13/dolly_on
##   uv run --with numpy python tmp/city-art/r13/dolly_diff.py on off
##
## `--occ=0` turns the viewport's occlusion culling off with `viewport_set_occlusion_culling`, which is
## the switch the engine itself reads, so the "off" arm is the shipping renderer without the feature
## rather than a scene with the occluders deleted.

const CITY := "res://world/city.tscn"
## A1 Container Yard -> A3 Spire Plaza, at the height of a mech's chest on the street.
const START := Vector3(-566.0, 22.0, 524.0)
const END := Vector3(-40.0, 20.0, 170.0)
const LOOK_AHEAD := 0.06
const SECONDS := 6.0
const SAVE_EVERY := 3
const SAVE_SIZE := Vector2i(1280, 720)

var _cam: Camera3D
var _frames: int = 360
var _dir: String = ""


func _ready() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var seconds := float(Game.flag("dolly-seconds", str(SECONDS)))
	_frames = int(seconds * 60.0)
	_dir = Game.flag("dolly-out", "tmp/city-art/r13/dolly")
	add_child((load(CITY) as PackedScene).instantiate())
	_run.call_deferred()


func _run() -> void:
	while not Game.world_built():
		await get_tree().process_frame
	await _frames_wait(30)
	var occ := _occluders()
	print("DOLLY occluders=%s instances=%d culling=%s" % [occ != null,
		occ.get_child_count() if occ != null else 0, Game.flag("occ", "1")])
	RenderingServer.viewport_set_use_occlusion_culling(
		get_viewport().get_viewport_rid(), Game.flag("occ", "1") != "0")
	_cam = Camera3D.new()
	_cam.near = 0.05
	_cam.far = 6000.0
	_cam.fov = 62.0
	add_child(_cam)
	_cam.current = true
	DirAccess.make_dir_recursive_absolute(ArtRepo.at(_dir))
	for f in range(_frames + 1):
		var t := float(f) / float(_frames)
		_cam.position = START.lerp(END, t)
		_cam.look_at(START.lerp(END, minf(t + LOOK_AHEAD, 1.0)) + Vector3.DOWN * 6.0, Vector3.UP)
		await get_tree().process_frame
		if f % SAVE_EVERY == 0:
			await _save(f)
	print("DOLLY wrote %d frames to %s" % [_frames / SAVE_EVERY + 1, _dir])
	get_tree().quit(0)


func _frames_wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _occluders() -> Node3D:
	return get_tree().root.find_child("Occluders", true, false) as Node3D


func _save(f: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(SAVE_SIZE.x, SAVE_SIZE.y, Image.INTERPOLATE_BILINEAR)
	var path := ArtRepo.at(_dir).path_join("f%04d.jpg" % f)
	if img.save_jpg(path, 0.95) != OK:
		push_error("dolly: could not write %s" % path)
