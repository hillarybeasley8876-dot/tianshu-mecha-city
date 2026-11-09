extends Node3D
## city-art r15 — the sky-only probe. The dome is the round's biggest lever and a full city probe is
## ~3 minutes per arm, so this boots `world/art/environment.tscn` and NOTHING else: no city, no post
## stack, no geometry. One frame per time of day, and the frame is the sky the shader actually makes.
##
## It writes the same `<tag>_meta.json` shape `value_probe.gd` does, so `tmp/city-art/r15/
## skyprofile.py` reads it with the same code path as the shipping frames.
##
##   tools/godot.sh shot --scene=res://world/art/tests/sky_probe.tscn --out=sky --times=600 \
##     --sky-tods=0,0.6,1 --sky-tag=r15
## (`tools/godot.sh run` drops every flag after the scene and the seconds — use `shot`.)

const ENV_SCENE := "res://world/art/environment.tscn"
const FRAMES_REL := "tmp/city-art/r15/sky"
## The camera looks along the sun's azimuth at 12 deg up with a 96 deg vertical field, so one frame
## covers -36..+60 deg of elevation: the horizon band, the deck and the zenith in a single image.
const EYE := Vector3(0.0, 220.0, 0.0)
const LOOK_AZ_DEG := 315.0
const LOOK_EL_DEG := 12.0
const FOV := 96.0
const WARM := 20

var _cam: Camera3D
var _tod: TimeOfDay
var _out: String = ""
var _tag: String = "r15"
var _tods: PackedFloat64Array = PackedFloat64Array()
var _meta: Array = []
var _drew: bool = false


func _ready() -> void:
	_out = ArtRepo.at(FRAMES_REL)
	DirAccess.make_dir_recursive_absolute(_out)
	_tag = Game.flag("sky-tag", "r15")
	for t in Game.flag("sky-tods", "0,0.6,1").split(",", false):
		_tods.append(float(t))
	add_child((load(ENV_SCENE) as PackedScene).instantiate())
	for i in 4:
		await get_tree().physics_frame
	_tod = _find_tod()
	_cam = Camera3D.new()
	_cam.near = 0.05
	_cam.far = 4000.0
	_cam.fov = FOV
	add_child(_cam)
	var az := deg_to_rad(LOOK_AZ_DEG)
	var el := deg_to_rad(LOOK_EL_DEG)
	_cam.position = EYE
	_cam.look_at(EYE + Vector3(cos(el) * sin(az), sin(el), -cos(el) * cos(az)) * 500.0, Vector3.UP)
	_cam.current = true
	print("SKY probe tag=%s tods=%s out=%s" % [_tag, str(_tods), _out])
	_run.call_deferred()


func _run() -> void:
	for p in _tods:
		if _tod != null:
			_tod.set_progress_immediate(p)
		await _frames(WARM)
		var img := await _grab()
		var stem := "%s_p%s" % [_tag, str(p).replace(".", "")]
		if img.save_png(_out.path_join(stem + "_A.png")) != OK:
			push_error("sky_probe: cannot write %s_A.png" % stem)
		_meta.append({"stem": stem, "cam": "sky", "tod": p, "w": img.get_width(),
			"h": img.get_height(), "fov": FOV, "pos": [EYE.x, EYE.y, EYE.z],
			"look": [EYE.x + cos(deg_to_rad(LOOK_EL_DEG)) * sin(deg_to_rad(LOOK_AZ_DEG)) * 500.0,
				EYE.y + sin(deg_to_rad(LOOK_EL_DEG)) * 500.0,
				EYE.z - cos(deg_to_rad(LOOK_EL_DEG)) * cos(deg_to_rad(LOOK_AZ_DEG)) * 500.0],
			"sun_px": [-1e9, -1e9], "sun_r": 0.0, "beam_px": [], "beam_r": 0.0, "has_c": false})
		_write_meta()
		print("SKY tod=%.2f %dx%d" % [p, img.get_width(), img.get_height()])
	print("SKY done")
	get_tree().quit(0)


## A draw that cannot hang: a throttled display loop never emits `frame_post_draw`, so the server is
## told to draw after a few frames and the frame is taken whatever produced it.
func _grab() -> Image:
	_drew = false
	RenderingServer.frame_post_draw.connect(_on_drawn, CONNECT_ONE_SHOT)
	for i in 240:
		await get_tree().process_frame
		if _drew:
			break
		if i == 8:
			RenderingServer.force_draw(false)
	if not _drew:
		push_warning("sky_probe: frame_post_draw never fired — this frame is the previous one")
		if RenderingServer.frame_post_draw.is_connected(_on_drawn):
			RenderingServer.frame_post_draw.disconnect(_on_drawn)
	return get_viewport().get_texture().get_image()


func _on_drawn() -> void:
	_drew = true


func _find_tod() -> TimeOfDay:
	for n in get_tree().get_nodes_in_group(&"time_of_day"):
		if n is TimeOfDay:
			return n as TimeOfDay
	push_error("sky_probe: environment.tscn provided no TimeOfDay node")
	return null


func _write_meta() -> void:
	var f := FileAccess.open(_out.path_join(_tag + "_meta.json"), FileAccess.WRITE)
	if f == null:
		push_error("sky_probe: cannot write the meta file (error %d)" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(_meta, "  "))
	f.close()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
