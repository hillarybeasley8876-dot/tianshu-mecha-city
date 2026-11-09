extends Node3D
## Monster gallery (monster-assets): every HUSK model on the core sandbox ground under the ART.md
## dusk light, with glow and AgX switched on so the acid-green veins and violet cores are judged the
## way they will be in game (ART.md §3, brief "Done when": "glow visible under sandbox light").
##
##   tools/godot.sh shot  --scene=res://enemies/models/tests/model_gallery.tscn --out=monsters_gallery \
##       --cams=lineup:0,26,-120:0,26,0:60 --warm=90
##   tools/godot.sh movie --movie=<abs>/monsters_cycles.avi --scene=res://enemies/models/tests/model_gallery.tscn \
##       --timeline=res://enemies/models/tests/gallery_timeline.json
##
## Options (Game flags): `--gallery-clip=<id>` plays that action on every model that has it;
## `--gallery-state=<intact|cracked|destroyed>` sets the hive; `--gallery-flash=1` holds the hit
## flash on so the white additive term can be photographed; `--gallery-gait=<type>:<m/s>` runs that
## one monster across the ground at a real gameplay speed with the camera tracking it from the side,
## which is how foot sliding is judged (lead r3).

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const MECH := "res://player/model/placeholder/placeholder_model.tscn"
## How far the gait demo runs before it wraps back to the start (the sandbox ground is 400 m).
const GAIT_RUN_M := 150.0
## How often `--gallery-attack` restarts its one-shot, so a strip catches the whole action.
const ATTACK_EVERY := 2.5
## Left-to-right order, small to large, with the 16 m hero placeholder beside them for scale.
const LINEUP: Array[Array] = [
	[&"ripper", Vector3(-52.0, 0.0, 0.0)],
	[&"mantis", Vector3(-30.0, 0.0, 0.0)],
	[&"spitter", Vector3(-8.0, 0.0, 0.0)],
	[&"harrier", Vector3(14.0, 22.0, 0.0)],
	[&"juggernaut", Vector3(40.0, 0.0, 0.0)],
	[&"hive", Vector3(96.0, 0.0, 0.0)],
	[&"titan", Vector3(160.0, 0.0, 0.0)],
]
const CYCLE: Array[StringName] = [&"idle", &"walk", &"run", &"attack"]
## How long each locomotion state holds before the gallery moves on (movie pacing).
const CYCLE_HOLD := 4.0
## The line-up camera, matching the documented `shot --cams=lineup:40,45,-150:40,30,0:60`.
const CAM_POS := Vector3(40.0, 45.0, -150.0)
const CAM_LOOK := Vector3(40.0, 30.0, 0.0)
const CAM_FOV := 60.0

var _models: Dictionary = {}
var _clip: StringName = &""
var _t: float = 0.0
var _step: int = -1
var _label: Label
## `--gallery-gait=<type>:<m/s>`: the one monster under test, and the speed it runs the ground at.
var _gait: StringName = &""
var _gait_speed: float = 0.0
var _gait_model: MonsterModel = null
var _gait_cam: Camera3D = null
## `--gallery-attack=<type>:<action>`: the one-shot to keep restarting while idle is re-asserted.
var _attack: String = ""
var _attack_at: float = 0.0
## The renderer reports the previous frame's totals and reads ~0 while the scene is still
## warming up, so the counters are sampled on a timer rather than once at startup.
## Clay pass (lead r5 item 1): `--gallery-clay=1` swaps every monster material for a shader whose
## back faces are flat magenta, so a torn skin and a hole are unmistakable in a turnaround.
const CLAY: Shader = preload("res://enemies/models/tests/gallery_clay.gdshader")
const STATS_EVERY := 120
var _stats_at: int = STATS_EVERY


func _ready() -> void:
	var sandbox := (load(SANDBOX) as PackedScene).instantiate()
	sandbox.name = "World"
	add_child(sandbox)
	_polish_environment(sandbox)
	_hud()
	_parse_gait()
	if _gait != &"":
		_spawn_gait()
		_gait_camera()
	else:
		_add_mech()
		_spawn()
		_camera()
		_spawn_swarm()
	_clip = StringName(Game.flag("gallery-clip", ""))
	if not _clip.is_empty():
		_play_all(_clip)
	var state := Game.flag("gallery-state", "")
	if not state.is_empty() and _models.has(&"hive"):
		(_models[&"hive"] as HiveModel).set_state(StringName(state))
	if Game.flag("gallery-clay", "0") != "0":
		_apply_clay()
	if Game.flag("gallery-flash", "0") != "0":
		for key: StringName in _models:
			var model := _models[key] as MonsterModel
			if model != null:
				model.set_hit_flash(1.0)
	print("GALLERY %d models, clip '%s'" % [_models.size(), _clip])


## Override every monster mesh with the clay shader. Applied after the models are built, so it wins
## over `MonsterLook`'s per-type material without touching it.
func _apply_clay() -> void:
	var material := ShaderMaterial.new()
	material.shader = CLAY
	var count := 0
	for key: StringName in _models:
		for mesh in _meshes_of(_models[key]):
			mesh.material_override = material
			# Godot draws both LOD meshes through the visibility-range cross-fade, and the clay
			# shader is `cull_disabled`, so a distant monster reads as solid magenta back faces — a
			# probe artefact, not a model defect (the shipped shader renders the same models
			# correctly at 40/120/220 m). Turn the fade off so a turnaround shows one mesh.
			mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			count += 1
	print("GALLERY clay on %d meshes" % count)


func _meshes_of(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D:
			out.append(current as MeshInstance3D)
		stack.append_array(current.get_children())
	return out


func _polish_environment(sandbox: Node) -> void:
	for child in sandbox.get_children():
		var we := child as WorldEnvironment
		if we == null or we.environment == null:
			continue
		var env := we.environment
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
		env.tonemap_exposure = 1.0
		# ART.md §3: glow on at an HDR threshold of ~1.2 so the veins and cores bloom and the
		# carapace does not; no bloom term and no widest mips, or a 60 m hive washes the frame.
		env.glow_enabled = true
		env.glow_intensity = 0.9
		env.glow_strength = 0.9
		env.glow_hdr_threshold = 1.2
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		env.glow_bloom = 0.0
		for level in [5, 6, 7]:
			env.set("glow_levels/%d" % level, false)
		return
	push_warning("model_gallery: no WorldEnvironment in the sandbox — glow cannot be judged")


func _add_mech() -> void:
	var packed := load(MECH) as PackedScene
	if packed == null:
		push_warning("model_gallery: no hero placeholder at " + MECH)
		return
	var mech := packed.instantiate() as Node3D
	mech.name = "HeroPlaceholder"
	mech.position = Vector3(-78.0, 0.0, 0.0)
	add_child(mech)


func _spawn() -> void:
	for row: Array in LINEUP:
		var type_name: StringName = row[0]
		var path := "res://enemies/models/%s/%s_model.tscn" % [type_name, type_name]
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("model_gallery: cannot load " + path)
			continue
		var model := packed.instantiate() as Node3D
		if model == null:
			push_error("model_gallery: " + path + " root is not a Node3D")
			continue
		model.name = String(type_name)
		model.position = row[1]
		add_child(model)
		_models[type_name] = model
		var monster := model as MonsterModel
		if monster != null:
			monster.set_locomotion(&"idle", 0.0)


func _play_all(clip: StringName) -> void:
	for key: StringName in _models:
		var monster := _models[key] as MonsterModel
		if monster != null and monster.clip_ids().has(String(clip)):
			monster.play_action(clip)


## The movie cycles locomotion states so foot sliding and popping are visible; a fixed --gallery-clip
## overrides it, and a gait demo replaces both.
func _process(delta: float) -> void:
	_stats_at -= 1
	if _stats_at <= 0:
		_stats_at = STATS_EVERY
		_report_render_stats()
	if _gait != &"":
		_run_gait(delta)
		return
	if _label != null:
		_label.text = "clip %s   t %.1f" % [_current_clip(), _t]
	if not _clip.is_empty():
		return
	_t += delta
	var step := int(_t / CYCLE_HOLD)
	if step == _step:
		return
	_step = step
	var state: StringName = CYCLE[step % CYCLE.size()]
	for key: StringName in _models:
		var monster := _models[key] as MonsterModel
		if monster != null:
			monster.set_locomotion(state, 0.0 if state == &"idle" else 12.0)


func _parse_gait() -> void:
	var spec := Game.flag("gallery-gait", "")
	if spec.is_empty():
		return
	var parts := spec.split(":")
	_gait = StringName(parts[0])
	_gait_speed = float(parts[1]) if parts.size() > 1 else 12.0
	_attack = Game.flag("gallery-attack", "")
	if not _attack.is_empty():
		_gait_speed = 0.0


## One monster running the ground at a real gameplay speed. The body is moved by the same number of
## metres per second the model is told about, so any slide between the planted foot and the floor is
## the model's own and not a mismatch in the harness.
func _spawn_gait() -> void:
	var path := "res://enemies/models/%s/%s_model.tscn" % [_gait, _gait]
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("model_gallery: cannot load " + path)
		return
	_gait_model = packed.instantiate() as MonsterModel
	if _gait_model == null:
		push_error("model_gallery: " + path + " root is not a MonsterModel")
		return
	_gait_model.name = String(_gait)
	_gait_model.position = Vector3(-GAIT_RUN_M * 0.5, 0.0, 0.0)
	# models face −Z (CONTRACTS §6); turn it to face +X so the tracking camera sees its side, which
	# is the only view where a foot slipping against the floor is visible
	_gait_model.rotation.y = -PI * 0.5
	add_child(_gait_model)
	_models[_gait] = _gait_model
	print("GAIT %s at %.1f m/s" % [_gait, _gait_speed])


func _run_gait(delta: float) -> void:
	if _gait_model == null:
		return
	if not _attack.is_empty():
		# Reproduce what EnemyBase does: start a one-shot, then re-assert a locomotion state on every
		# frame (lead audit 1). Before the hold the attack was cross-faded away one frame later, so
		# a monster wound up and struck in its idle loop.
		_gait_model.set_locomotion(&"idle", 0.0)
		_attack_at -= delta
		if _attack_at <= 0.0:
			_gait_model.play_action(StringName(_attack))
			_attack_at = ATTACK_EVERY
		if _label != null:
			_label.text = "%s  re-asserting idle every frame  clip %s" % [
					_gait, _gait_model.animation.current_animation]
		_track()
		return
	var travelled := _gait_model.position.x + GAIT_RUN_M * 0.5 + _gait_speed * delta
	if travelled > GAIT_RUN_M:
		travelled = 0.0
	_gait_model.position.x = travelled - GAIT_RUN_M * 0.5
	if _gait_speed > 0.0:
		_gait_model.set_locomotion(&"run", _gait_speed)
	if _label != null:
		_label.text = "%s  %.0f m/s  x %.1f m  clip %s  x%.2f" % [_gait, _gait_speed,
				_gait_model.position.x, _gait_model.animation.current_animation,
				_gait_model.animation.speed_scale]
	_track()


## Keep the side-on camera framed on the model, whatever the demo is doing.
func _track() -> void:
	if _gait_cam == null or _gait_model == null:
		return
	var size := _gait_model.world_size()
	var focus := _gait_model.position + Vector3(0.0, size.y * 0.45, 0.0)
	_gait_cam.position = focus + Vector3(0.0, 0.0, -maxf(size.y, size.x) * 2.0)
	_gait_cam.look_at(focus)


## Side-on and tracking: the only view where a foot that slips against the floor is visible.
func _gait_camera() -> void:
	_gait_cam = Camera3D.new()
	_gait_cam.fov = 40.0
	add_child(_gait_cam)
	_gait_cam.current = true
	_run_gait(0.0)


func _current_clip() -> StringName:
	if not _clip.is_empty():
		return _clip
	return CYCLE[ maxi(_step, 0) % CYCLE.size()]


func _hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(24.0, 18.0)
	_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(_label)


## The scene ships a camera so `drive` and `movie` (which use the scene's own camera, unlike `shot`,
## which builds one from --cams) actually record the line-up instead of a black frame. `shot --cams`
## still overrides it by making its own camera current.
func _camera() -> void:
	var cam := Camera3D.new()
	cam.position = CAM_POS
	cam.fov = CAM_FOV
	add_child(cam)
	cam.look_at(CAM_LOOK)
	cam.current = true


## `--gallery-swarm=N` fills the ground with N rippers at the briefed "40 on screen" load, so the
## draw calls and frame cost of a full swarm are measured in the real renderer (lead note).
func _spawn_swarm() -> void:
	var count := int(Game.flag("gallery-swarm", "0"))
	if count <= 0:
		return
	var packed := load("res://enemies/models/ripper/ripper_model.tscn") as PackedScene
	if packed == null:
		push_error("model_gallery: cannot load the ripper for the swarm")
		return
	var per_row := 10
	for i in count:
		var model := packed.instantiate() as MonsterModel
		if model == null:
			continue
		model.name = "Swarm%d" % i
		model.position = Vector3(-120.0 + float(i % per_row) * 14.0, 0.0,
				-40.0 - float(i / per_row) * 16.0)
		add_child(model)
		model.set_locomotion(&"run", 30.0)
	print("GALLERY swarm %d rippers" % count)


## Draw calls, primitives and video memory for the frame just drawn (Godot reports these only with
## a real renderer, so this is why the gallery runs windowed rather than headless).
func _report_render_stats() -> void:
	print("RENDER draw_calls %d  objects %d  primitives %d  video_mem %.1f MB" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
	])


