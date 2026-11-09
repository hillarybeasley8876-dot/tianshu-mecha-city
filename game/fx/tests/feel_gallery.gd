extends Node3D
## Feel gallery (feel unit): plays every docs/FEEL.md row in the core sandbox in front of a static
## camera, one every INTERVAL seconds, labelled on screen. The 16 m placeholder mech stands beside
## the effect so sizes read at mech scale, and the world's glow + AgX are switched on so bloom is
## judged exactly as it will be in game (ART.md §3).
##
## Movie (one row every 1.5 s of MOVIE time):
##     tools/godot.sh movie --movie=<abs>/feel_gallery.avi \
##         --scene=res://fx/tests/feel_gallery.tscn --timeline=res://fx/tests/gallery_timeline.json
##
## Stills (the gallery photographs itself: every row at rendered frame 1 and frame 4, immune to
## clock drift and to the rows' own slow-mos):
##     tools/godot.sh drive --scene=res://fx/tests/feel_gallery.tscn \
##         --timeline=res://fx/tests/gallery_timeline.json --fx-stills=1
## --fx-out=<dir> picks the directory (default: the repo's captures/), --fx-cam=<metres> the camera
## distance (a 28 m kill_large does not fit the default framing), --fx-slow=<factor> stretches the
## real-time VFX so the peak frame of a 0.18 s shockwave can be photographed at all.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const DIRECTOR := "res://fx/feel_director.tscn"
const MECH := "res://player/model/placeholder/placeholder_model.tscn"
const INTERVAL := 1.5
const START := 2.0
## Effects land on open ground; the mech stands beside them as the scale reference.
const ORIGIN := Vector3(0.0, 1.0, 0.0)
const MECH_POS := Vector3(-24.0, 0.0, 4.0)
const CAM_DIST := 62.0
const CAM_FOV := 55.0
const LABEL_LAYER := 60
## Stills mode: the row is fired once and photographed this many rendered frames later. Frame 1
## catches the 1-2 frame flashes and the B/W impact frames, frame 4 the particles and the ring.
const STILL_EARLY := 1
const STILL_LATE := 4
## Real seconds between two rows in stills mode: long enough for the previous row's slow-mo and
## fireball to be gone, short enough that 49 rows finish inside one drive.
const STILL_GAP := 1.8
## Default still directory. Relative to res:// so no home path ever lands under game/ (the house
## rule `test_no_abs_paths` walks the disk).
const STILL_DIR := "res://../captures"

var _ids: Array[StringName] = []
var _next: int = 0
var _start: float = 0.0
var _t: float = 0.0
var _label: Label
var _clock_label: Label
var _drawn: bool = false
## Stills mode (`--fx-stills`): the stills loop owns the schedule, `_process` stands down.
var _stills_mode: bool = false
## The stand-in player the afterimage rows ghost (the placeholder mech), and whether it is drifting
## this frame: three ghosts of a standing mech stack into one blob.
var _player: Node3D
var _drift: bool = false


## The gallery clock (CONTRACTS §3): unscaled game seconds since `start`. The schedule runs on this
## and never on Time.get_ticks_usec() — a wall clock drifts against the capture tool's scaled frame
## clock, and the rows' own slow-mos stretch that one further (r5 item 3).
static func elapsed(start: float) -> float:
	return Feel.real_now() - start


func _ready() -> void:
	var sandbox := (load(SANDBOX) as PackedScene).instantiate()
	sandbox.name = "World"
	add_child(sandbox)
	_polish_environment(sandbox)
	_add_mech()
	var cam := Camera3D.new()
	cam.name = "GalleryCamera"
	cam.fov = float(Game.flag("fx-fov", str(CAM_FOV)))
	cam.near = 0.05
	cam.far = 4000.0
	add_child(cam)
	cam.global_position = _cam_pos()
	cam.look_at(_cam_look(), Vector3.UP)
	cam.make_current()
	add_child((load(DIRECTOR) as PackedScene).instantiate())
	_hud()
	_ids = FeelTable.ids()
	_start = Feel.real_now()
	if Game.has_flag("fx-stills"):
		# Stills mode fires the rows itself, one at a time, and photographs each: the 1.5 s schedule
		# below must not also run, or every row fires twice and the two labels fight.
		_stills_mode = true
		_stills.call_deferred()
		return
	print("GALLERY %d events, interval %.1f s" % [_ids.size(), INTERVAL])


## --fx-slow=<factor> stretches the real-time VFX (rings, fireballs, contact flashes) so the peak
## frame of a 0.18 s shockwave can actually be photographed. Capture aid only.
func _slow_factor() -> float:
	return maxf(float(Game.flag("fx-slow", "1")), 0.01)


func _process(_delta: float) -> void:
	if _drift and _player != null:
		_player.global_position += Vector3(2.5, 0.0, 0.0)
	_t = elapsed(_start)
	if _stills_mode or _next >= _ids.size() or _t < START + float(_next) * INTERVAL:
		return
	var id := _ids[_next]
	_next += 1
	_fire(id, "%d/%d  %s" % [_next, _ids.size(), id])
	if _next >= _ids.size():
		_finish.call_deferred()


## The last row has been fired: hold for a beat so its tail is on film, then end the run (the
## timeline in fx/tests/gallery_timeline.json is only the safety net).
func _finish() -> void:
	await _real(INTERVAL)
	print("GALLERY movie done, %d rows" % _ids.size())
	get_tree().quit(0)


# --- stills ---------------------------------------------------------------------------------------

## Every row fired once, photographed STILL_EARLY and STILL_LATE rendered frames later and written
## as `<nn>_<id>_f1.jpg` / `<nn>_<id>_f4.jpg`. The label on screen is the file name, so a contact
## sheet can be read without a legend.
func _stills() -> void:
	var dir := ProjectSettings.globalize_path(Game.flag("fx-out", STILL_DIR))
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		push_error("feel_gallery: cannot create the still directory " + dir)
		get_tree().quit(1)
		return
	await _frames(120)   ## let the sandbox navmesh bake and the first shaders compile
	var i := 0
	for id in _ids:
		i += 1
		var shot := "%02d_%s" % [i, id]
		_reset_rate_limits()
		_drift = _ghosts_of(id) > 0
		_fire(id, shot)
		await _frames(STILL_EARLY)
		await _save(dir, shot + "_f1")
		await _frames(STILL_LATE - STILL_EARLY)
		await _save(dir, shot + "_f4")
		_drift = false
		if _player != null:
			_player.position = MECH_POS
		await _real(STILL_GAP)
	print("GALLERY stills done, %d rows in %s" % [_ids.size(), dir])
	get_tree().quit(0)


func _reset_rate_limits() -> void:
	var director := get_tree().get_first_node_in_group(&"feel_director")
	if director != null:
		director.call(&"reset_rate_limits")


## How many afterimages this row asks for; > 0 means the stand-in mech has to move while it is
## photographed, or the three ghosts land on one pose.
func _ghosts_of(id: StringName) -> int:
	var director := get_tree().get_first_node_in_group(&"feel_director") as FeelDirector
	if director == null:
		return 0
	var ev := director.event(id)
	return ev.ghosts if ev != null else 0


func _on_drawn() -> void:
	_drawn = true


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _real(seconds: float) -> void:
	var t0 := Feel.real_now()
	while Feel.real_now() - t0 < seconds:
		await get_tree().process_frame


## Waits for the next drawn frame (at most 240 process frames: an occluded window draws nothing),
## then writes the viewport. The label is already the file name.
func _save(dir: String, shot: String) -> void:
	# A member flag, not a captured local: a GDScript lambda captures by value, so the outer `while`
	# would never see it flip.
	_drawn = false
	RenderingServer.frame_post_draw.connect(_on_drawn, CONNECT_ONE_SHOT)
	var guard := 0
	while not _drawn and guard < 240:
		await get_tree().process_frame
		guard += 1
	if not _drawn:
		RenderingServer.frame_post_draw.disconnect(_on_drawn)
		push_warning("feel_gallery: no frame drawn for " + shot)
		return
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(shot + ".jpg")
	if img.save_jpg(path, 0.85) != OK:
		push_error("feel_gallery: cannot write " + path)


# --- scene ----------------------------------------------------------------------------------------

## The sandbox is core's; the gallery turns its glow on in place (ART.md §3: HDR threshold ~1.2,
## AgX, exposure 1.0) so fire and beams bloom the way they will in the city.
func _polish_environment(sandbox: Node) -> void:
	for child in sandbox.get_children():
		var we := child as WorldEnvironment
		if we == null or we.environment == null:
			continue
		var env := we.environment
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
		env.tonemap_exposure = 1.0
		env.glow_enabled = bool(Game.flag("fx-glow", "1") != "0")
		env.glow_intensity = 0.85
		env.glow_strength = 0.85
		env.glow_hdr_threshold = 1.2
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		# ART.md §3: "no full-screen bloom wash". The bloom term and the two widest mips are what
		# smear a bright blast across the whole horizon, so the gallery judges fx without them.
		env.glow_bloom = 0.0
		env.set("glow_levels/5", false)
		env.set("glow_levels/6", false)
		env.set("glow_levels/7", false)
		return
	push_warning("feel_gallery: no WorldEnvironment in the sandbox - bloom will not be judged")


## The 16 m placeholder mech is the scale reference AND the stand-in player, so the dash and the
## perfect dodge rows leave their afterimages here too (FEEL.md:31-32).
func _add_mech() -> void:
	var mech := (load(MECH) as PackedScene).instantiate()
	mech.name = "ScaleMech"
	mech.position = MECH_POS
	_player = Node3D.new()
	_player.name = "GalleryPlayer"
	_player.set_script(load("res://fx/tests/stand_in_player.gd"))
	_player.add_child(mech)
	add_child(_player)
	Game.player = _player


## --fx-cam=<metres> pulls the camera to that distance from the effect. The aim point rises with the
## distance so a close shot frames the impact itself and a wide one frames the blast above the mech.
func _cam_pos() -> Vector3:
	return _cam_look() + Vector3(0.0, 0.24, 0.97).normalized() * _cam_dist()


func _cam_look() -> Vector3:
	var d := _cam_dist()
	return ORIGIN + Vector3(-minf(d * 0.12, 7.0), clampf(d * 0.13, 1.5, 9.0), 0.0)


func _cam_dist() -> float:
	var dist := float(Game.flag("fx-cam", str(CAM_DIST)))
	return dist if dist > 0.0 else CAM_DIST


func _fire(id: StringName, text: String) -> void:
	_label.text = text
	_clock_label.text = "t %.2f  %s" % [_t, text]
	var lib := get_tree().get_first_node_in_group(&"vfx_library") as VfxLibrary
	if lib != null:
		lib.set_time_scale(1.0 / _slow_factor())
	Feel.play(id, ORIGIN, 1.0)


func _hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GalleryHud"
	layer.layer = LABEL_LAYER
	add_child(layer)
	_label = Label.new()
	_label.name = "Id"
	_label.position = Vector2(40.0, 32.0)
	_label.add_theme_font_size_override(&"font_size", 34)
	_label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_label.add_theme_constant_override(&"outline_size", 8)
	_label.text = "feel gallery"
	layer.add_child(_label)
	_clock_label = Label.new()
	_clock_label.name = "Clock"
	_clock_label.position = Vector2(40.0, 78.0)
	_clock_label.add_theme_font_size_override(&"font_size", 26)
	_clock_label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_clock_label.add_theme_constant_override(&"outline_size", 8)
	layer.add_child(_clock_label)
