class_name WeaponsRange
extends Node3D
## Demo range for the weapons captures (tests/demo only): the same rig the test suite uses, plus a
## lit environment, target walls at 100/300/500 m, a 12-dummy missile field, an over-the-shoulder
## camera and a debug readout of `hud_state()` (heat, vent needle, locks, charge).
##
## Camera: `--cam=px,py,pz,lx,ly,lz[,fov]` (default looks down the range from the mech's right).
## Drive it with `tools/godot.sh drive --timeline=res://combat/weapons/tests/timeline_*.json`.

const WEAPONS := "res://combat/weapons/weapon_system.tscn"

var player: RigPlayer = null
var system: WeaponSystem = null
var _label: Label = null
var _cam: Camera3D = null


func _ready() -> void:
	FxBridge.reset()
	_environment()
	_feel()
	_ground()
	_targets()
	player = RigPlayer.new()
	player.name = "RigPlayer"
	add_child(player)
	player.global_position = Vector3.ZERO
	system = (load(WEAPONS) as PackedScene).instantiate() as WeaponSystem
	player.add_child(system)
	var aim_spec := Game.flag("aim").split(",")
	if aim_spec.size() >= 3:
		player.aim_system.point = Vector3(float(aim_spec[0]), float(aim_spec[1]),
				float(aim_spec[2]))
	else:
		player.aim_system.point = Vector3(0.0, 12.0, -300.0)
	Game.register_player(player)
	_camera()
	_readout()
	_debug_geometry()
	set_process(true)


## Capture geometry that only exists with `--debug`: the crosshair ray and the missile paint box, so
## a normal capture never shows a stray line.
func _debug_geometry() -> void:
	if not Game.has_flag("debug"):
		return
	var origin := player.aim_system.global_position
	var dir := player.aim_system.aim_dir_from(origin)
	_line(origin, origin + dir * 500.0, Color(1.0, 1.0, 1.0, 0.5))
	_line(origin, player.aim_system.aim_point(), Color(1.0, 0.4, 0.2, 0.8))


func _line(from: Vector3, to: Vector3, color: Color) -> void:
	var im := ImmediateMesh.new()
	var mat := BeamPool.additive_material(color, 1.0)
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	im.surface_set_color(color)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.name = "DebugLine"
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## ART.md §Look: AgX tonemap at exposure 1.0 and Glow with the HDR threshold at 1.2, so the HDR beam
## albedo actually blooms in captures instead of clipping to a flat white line.
func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.06, 0.10, 0.22)
	sky_mat.sky_horizon_color = Color(0.42, 0.46, 0.58)
	sky_mat.ground_bottom_color = Color(0.10, 0.11, 0.13)
	sky_mat.ground_horizon_color = Color(0.30, 0.32, 0.36)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.45, 0.50, 0.60)
	env.fog_density = 0.0007
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.2
	env.glow_intensity = 0.4
	env.glow_bloom = 0.03
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for level: Array in [[2, 0.25], [3, 0.4], [4, 0.35], [5, 0.2]]:
		env.set_glow_level(int(level[0]), float(level[1]))
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)   ## lights the side the camera sees
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.94, 0.86)
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()   ## keeps the mech readable from the capture camera
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-18.0, 205.0, 0.0)
	fill.light_energy = 0.55
	fill.light_color = Color(0.72, 0.82, 1.0)
	fill.shadow_enabled = false
	add_child(fill)


## The real fx unit's VfxLibrary so captures show the shipped impact effects; the weapons fall back
## to their own only when it is absent (headless tests). The FeelDirector itself is not instanced
## here: its ScreenFx post shader does not compile (see status/weapons.md "Requests").
func _feel() -> void:
	var lib := VfxLibrary.new()
	lib.name = "Vfx"
	add_child(lib)


func _ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000.0, 4.0, 2000.0)
	cs.shape = box
	body.add_child(cs)
	body.position = Vector3(0.0, -2.0, 0.0)
	add_child(body)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000.0, 2000.0)
	mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.23, 0.25)
	mat.roughness = 0.9
	mesh.material_override = mat
	mesh.position = Vector3(0.0, 0.02, 0.0)
	add_child(mesh)
	for i in 6:  ## range markers every 100 m so distances read in captures
		var stripe := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(46.0, 1.6)
		stripe.mesh = pm
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.32, 0.34, 0.37)
		stripe.material_override = sm
		stripe.position = Vector3(0.0, 0.05, -100.0 * float(i + 1))
		add_child(stripe)


func _targets() -> void:
	for i in 5:  ## 300 m wall: the rifle volley target
		_dummy(Vector3(float(i - 2) * 26.0, 12.0, -300.0), 16.0)
	for i in 3:
		_dummy(Vector3(float(i - 1) * 22.0, 10.0, -100.0), 12.0)
	for i in 3:
		_dummy(Vector3(float(i - 1) * 30.0, 14.0, -480.0), 18.0)
	for row in 3:    ## 12 painted targets for the missile circus
		for col in 4:
			_dummy(Vector3(float(col - 2) * 8.0 + 4.0, 8.0 + float(row) * 8.0, -90.0), 6.0)


func _dummy(at: Vector3, size: float) -> void:
	var t := DummyTarget.new()
	t.size = size
	add_child(t)
	t.global_position = at


func _camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.fov = 55.0          ## Godot fov is vertical (SPEC §5)
	_cam.near = 0.5
	_cam.far = 4000.0
	add_child(_cam)
	var spec := Game.flag("cam").split(",")
	var pos := Vector3(26.0, 24.0, 46.0)
	var look := Vector3(0.0, 13.0, -120.0)
	if spec.size() >= 6:
		pos = Vector3(float(spec[0]), float(spec[1]), float(spec[2]))
		look = Vector3(float(spec[3]), float(spec[4]), float(spec[5]))
	if spec.size() >= 7:
		_cam.fov = float(spec[6])
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	_cam.current = true


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


func _process(_delta: float) -> void:
	if _label == null or system == null:
		return
	var s := system.hud_state()
	var needle := "%s" % ("off" if not bool(s.get("overheated", false))
			else "needle %.2f / mark %.2f" % [float(s.get("vent_needle", 0.0)),
			float(s.get("vent_mark", 0.0))])
	_label.text = "weapon %s   ammo %d/%d   %s\nheat %.0f%%   %s   superheated %s\nmissiles %d/%d   cd %.1fs   charge %.2f (stage %d)" % [
		s.get("weapon", "?"), int(s.get("ammo", 0)), int(s.get("ammo_max", 0)),
		"RELOADING" if bool(s.get("reloading", false)) else "",
		float(s.get("heat", 0.0)) * 100.0, needle, "yes" if bool(s.get("superheated", false)) else "no",
		int(s.get("missile_locks", 0)), int(s.get("missile_locks_max", 12)),
		float(s.get("missile_cd", 0.0)), float(s.get("charge", 0.0)),
		int(s.get("charge_stage", 0))]
