class_name MeleeRange
extends Node3D
## Demo range for the melee and defence captures (tests/demo only): the same rig the suites use —
## a MeleeRigPlayer carrying the real `melee_system.tscn` and `defense_system.tscn` — plus a lit
## arena, three dummy monsters (12 / 18 / 70 m), an acid-spitting battery that feeds the catch field,
## a camera and a live readout of both `hud_state()`s.
##
## Camera: `--cam=px,py,pz,lx,ly,lz[,fov]`. Drive it with
## `tools/godot.sh drive --scene=res://combat/melee/tests/melee_range.tscn --timeline=...`.

const MELEE := "res://combat/melee/melee_system.tscn"
const DEFENSE := "res://combat/defense/defense_system.tscn"
const SPIT_INTERVAL := 1.1     ## seconds between acid arcs from the battery
const SPIT_SPEED := 42.0
const CAMERA_RIG := "res://player/camera/camera_rig.tscn"
const MAX_CAPTURES := 24      ## --autoshot stops here, so a long run cannot fill the disk
## Review r4: the drawn blade is the `saber_r` socket, so the range runs the shipped hero rig —
## its clips are what sweep the blade. `--hero` is the default here; `--placeholder` falls back.
const HERO_MODEL := "res://player/model/hero3/hero3_model.tscn"

var player: MeleeRigPlayer = null
var melee: MeleeSystem = null
var defense: DefenseSystem = null
var monsters: Array[Node3D] = []

var _label: Label = null
var _cam: Camera3D = null
var _host: Node3D = null
var _spit_t: float = 0.0
var _spitter: MeleeDummy = null
var _follow: bool = false
var _cam_offset := Vector3(34.0, 15.0, 26.0)
var _captures: int = 0


func _ready() -> void:
	_environment()
	_ground()
	_arena()
	_feel()
	_monsters()
	player = MeleeRigPlayer.new()
	player.name = "RigPlayer"
	if ResourceLoader.exists(HERO_MODEL) and not Game.has_flag("placeholder"):
		player.model_scene = HERO_MODEL
	add_child(player)
	player.global_position = Vector3(0.0, 8.0, 0.0)
	melee = (load(MELEE) as PackedScene).instantiate() as MeleeSystem
	player.add_child(melee)
	defense = (load(DEFENSE) as PackedScene).instantiate() as DefenseSystem
	player.add_child(defense)
	player.demo_targets = monsters
	player.demo_spit = _fire_now
	player.aim_ref.look_at_point(Vector3(0.0, 10.0, -20.0))
	Game.register_player(player)
	Game.mark_world_built()
	_camera_rig()
	_camera()
	_readout()
	_capture_hooks()
	set_process(true)


## Capture on the EVENT, not on a timer (review r1 MUST-FIX 3): a still taken from the hit callback
## lands on the frame where the hit-stop freezes both actors, which is the frame that has to be
## judged. `--autoshot` turns it on; the name carries the weapon so the stills sort themselves.
func _capture_hooks() -> void:
	if not Game.has_flag("autoshot"):
		return
	Events.hit_landed.connect(_on_hit_landed)
	Events.parry_success.connect(func(_hit: HitInfo, _src: Node) -> void:
			_capture("melee_ev_parry_%d" % _shots_taken()))
	Events.melee_swing.connect(func(id: StringName, _step: int) -> void:
			if id == &"execution":
				_capture("melee_ev_exec_%d" % _shots_taken()))


func _on_hit_landed(hit: HitInfo, _actor: Node) -> void:
	_capture("melee_ev_%s_%d" % [hit.weapon, _shots_taken()])


func _shots_taken() -> int:
	return _captures


func _capture(name: String) -> void:
	_captures += 1
	if _captures > MAX_CAPTURES:
		return
	_save(name)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	# r12 §3: derived from the project directory, never a literal home path.
	var dir := ArtRepo.at("captures")
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	img.save_jpg("%s/%s.jpg" % [dir, name], 0.85)
	print("RANGE shot -> %s/%s.jpg" % [dir, name])


## ART.md §3 lighting: a low warm sun from the north-west at golden dusk, AgX at exposure 1.0 and
## glow with an HDR threshold, so bloom and colour are judged exactly as they will be in the city.
## The r1 range was a grey/blue box that swallowed the cyan blade; the warm mid-tones here are what
## make a white-hot saber read.
const SUN_ELEVATION := 18.0     ## degrees above the horizon (ART.md 16–20°)
const SUN_AZIMUTH := 315.0      ## compass degrees the light comes FROM (north-west)
const SUN_COLOR := Color("ffd3a0")
## ART.md's facade albedos assume textured, ambient-occluded city geometry. A bare untextured plane
## at 0.66 albedo under a 2.2 sun clips to white, which is what hid the saber in r1: the range uses
## the same warm hues a stop and a half down so the mid-tones land where the city's will.
const GROUND_COLOR := Color(0.30, 0.27, 0.23)    ## warm concrete, darkened
const BLOCK_COLOR := Color(0.44, 0.41, 0.36)     ## pale limestone, darkened


## Godot's −Z is north: a sun at elevation E, azimuth A sits at yaw `180 − A`, pitched down by E.
static func sun_rotation(elevation_deg: float, azimuth_deg: float) -> Vector3:
	return Vector3(-elevation_deg, 180.0 - azimuth_deg, 0.0)


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("2b4c7e")
	sky_mat.sky_horizon_color = Color("f2b880")
	sky_mat.sky_curve = 0.45
	sky_mat.sky_energy_multiplier = 0.7
	sky_mat.ground_horizon_color = Color("c99a6e")
	sky_mat.ground_bottom_color = Color("3a3440")
	sky_mat.ground_curve = 0.1
	sky_mat.sun_angle_max = 6.0
	sky_mat.sun_curve = 0.1
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color("e8b98a")
	env.fog_density = 0.0009
	env.fog_sky_affect = 0.12
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.2
	env.glow_intensity = 0.4
	env.glow_bloom = 0.02
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for level: Array in [[2, 0.2], [3, 0.3], [4, 0.2], [5, 0.1]]:
		env.set_glow_level(int(level[0]), float(level[1]))
	env.ssao_enabled = true
	env.ssao_intensity = 1.4
	env.ssao_radius = 6.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = sun_rotation(SUN_ELEVATION, SUN_AZIMUTH)
	sun.light_energy = 2.2
	sun.light_color = SUN_COLOR
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 500.0
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.15
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_blend_splits = false
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = sun_rotation(52.0, 135.0)
	fill.light_energy = 0.45
	fill.light_color = Color("8fa7c4")     ## cool sky bounce from the opposite side
	fill.shadow_enabled = false
	add_child(fill)


func _ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1200.0, 4.0, 1200.0)
	cs.shape = box
	body.add_child(cs)
	body.position = Vector3(0.0, -2.0, 0.0)
	add_child(body)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1200.0, 1200.0)
	mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GROUND_COLOR
	mat.roughness = 0.85
	mat.metallic = 0.0
	mesh.material_override = mat
	mesh.position = Vector3(0.0, 0.02, 0.0)
	add_child(mesh)


## A few blocks so the range reads as a place and the blade has something to cut across.
func _arena() -> void:
	for spec: Array in [[-46.0, -40.0, 26.0], [44.0, -70.0, 34.0], [-30.0, -120.0, 18.0]]:
		var block := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(float(spec[2]), float(spec[2]) * 1.6, float(spec[2]))
		block.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = BLOCK_COLOR
		mat.roughness = 0.8
		block.material_override = mat
		block.position = Vector3(float(spec[0]), bm.size.y * 0.5, float(spec[1]))
		add_child(block)


## The shipped VFX library, registered so MeleeStrike can find sparks without a FeelDirector (the
## director's screen post shader does not compile headless — see status/weapons.md).
func _feel() -> void:
	var lib := VfxLibrary.new()
	lib.name = "Vfx"
	lib.add_to_group(&"vfx_library")
	add_child(lib)


## Index 0 is the string / execution target, 1 a flanker, 2 the 70 m lunge target.
func _monsters() -> void:
	monsters.append(_monster(Vector3(0.0, 6.0, -24.0), 11.0, &"mantis"))
	monsters.append(_monster(Vector3(21.0, 5.0, -30.0), 8.0, &"ripper"))
	monsters.append(_monster(Vector3(-5.0, 9.0, -70.0), 16.0, &"mantis"))
	_spitter = _monster(Vector3(17.0, 9.0, -52.0), 12.0, &"spitter")


func _monster(at: Vector3, size: float, kind: StringName) -> MeleeDummy:
	var d := MeleeDummy.new()
	d.size = size
	d.enemy_type = kind
	add_child(d)
	d.global_position = at
	d.look_at(Vector3(at.x, at.y, 0.0), Vector3.UP)
	return d


## The shipped camera rig, so the Core Rend mini-cinematic cuts to real shots (CONTRACTS §5). The
## range's own capture camera only takes over when the rig is missing (`--nocam`).
func _camera_rig() -> void:
	if Game.has_flag("nocam") or not ResourceLoader.exists(CAMERA_RIG):
		return
	var rig := (load(CAMERA_RIG) as PackedScene).instantiate() as Node3D
	if rig == null:
		push_warning("MeleeRange: %s is not a Node3D" % CAMERA_RIG)
		return
	rig.name = "CameraRig"
	add_child(rig)
	Game.camera_rig = rig


func _camera() -> void:
	if Game.camera_rig != null:
		return
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.fov = 55.0     ## Godot fov is vertical (SPEC §5)
	_cam.near = 0.5
	_cam.far = 4000.0
	add_child(_cam)
	var spec := Game.flag("cam").split(",")
	var pos := Vector3(38.0, 22.0, 30.0)
	var look := Vector3(2.0, 9.0, -26.0)
	if spec.size() >= 6:
		pos = Vector3(float(spec[0]), float(spec[1]), float(spec[2]))
		look = Vector3(float(spec[3]), float(spec[4]), float(spec[5]))
	if spec.size() >= 7:
		_cam.fov = float(spec[6])
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	_cam.current = true
	## Follow mode keeps the mech framed through a 70 m lunge: the offset is relative to the mech.
	_follow = not Game.has_flag("cam")


## The acid battery: pooled enemy shots from the spitter, so the catch field and the projectile
## parry have something real to work on (the enemies unit's EnemyProjectile, `reflectable` set).
func _spit(delta: float) -> void:
	if _spitter == null or not is_instance_valid(_spitter):
		return
	_spit_t -= delta
	if _spit_t > 0.0:
		return
	_spit_t = SPIT_INTERVAL
	_fire_now()


## Fires one acid arc immediately (the timeline's `debug_spit`, so a parry can be timed).
func _fire_now() -> void:
	if _host == null:
		_host = Node3D.new()
		_host.name = "Shots"
		add_child(_host)
	var from := _spitter.global_position + Vector3(0.0, 6.0, 0.0)
	var to := player.global_position + Vector3(0.0, 2.0, 0.0)
	var hit := HitInfo.make(220.0, HitInfo.BALLISTIC, _spitter, &"spitter_acid")
	hit.knockback = (to - from).normalized() * 6.0
	var shot := EnemyProjectile.new()
	_host.add_child(shot)
	shot.launch(from, (to - from).normalized() * SPIT_SPEED, hit, _spitter, true, false, 0.0)


func _readout() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Readout"
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(24.0, 20.0)
	_label.add_theme_font_size_override(&"font_size", 22)
	_label.add_theme_color_override(&"font_color", Color(0.75, 0.95, 1.0))
	_label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0))
	_label.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(_label)


func _process(delta: float) -> void:
	_spit(delta)
	if _follow and _cam != null and player != null:
		var want := player.global_position + _cam_offset
		_cam.global_position = _cam.global_position.lerp(want, clampf(delta * 14.0, 0.0, 1.0))
		var focus := player.global_position + Vector3(0.0, 1.0, -16.0)
		if not _cam.global_position.is_equal_approx(focus):
			_cam.look_at(focus, Vector3.UP)
	if _label == null or melee == null or defense == null:
		return
	var m := melee.hud_state()
	var d := defense.hud_state()
	_label.text = ("melee  %s (%s)   combo %d   charge %.2f\n"
			+ "lunge %s   execution %s   jackpot %s\n"
			+ "guard  %s   perfect %s   caught %d   break %s\n"
			+ "parries %d   blocked %.0f   EN %.0f") % [
		m.get("move", ""), m.get("phase", ""), int(m.get("combo_step", 0)),
		float(m.get("charging", 0.0)),
		"READY" if bool(m.get("lunge_ready", false)) else "-",
		"EXECUTING" if bool(m.get("executing", false))
				else ("READY" if bool(m.get("execution_available", false)) else "-"),
		"YES" if bool(m.get("jackpot", false)) else "-",
		d.get("state", ""), "OPEN" if bool(d.get("perfect_window", false)) else "-",
		int(d.get("catch_count", 0)), "STUNNED" if bool(d.get("guard_break", false)) else "-",
		int(d.get("parries", 0)), float(d.get("blocked_damage", 0.0)), player.energy]
