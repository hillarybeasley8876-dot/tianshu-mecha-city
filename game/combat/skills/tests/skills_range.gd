class_name SkillsRange
extends Node3D
## Demo range for the skills captures and the movie (tests/demo only): a grey-box runway at mech scale
## with a tower and a sky bridge carrying `&"anchor_node"` markers (the level hook from CONTRACTS §7),
## dummy targets at 100 / 180 / 300 m, the real `skill_system.tscn` on a rig player and the real
## FeelDirector, so the captures show the shipped FEEL rows rather than a stripped-down stand-in.
##
## Camera: `--cam=px,py,pz,lx,ly,lz[,fov]`. Drive it with
## `tools/godot.sh drive --timeline=res://combat/skills/tests/timeline_skills.json`.

const SKILLS := "res://combat/skills/skill_system.tscn"
const FEEL := "res://fx/feel_director.tscn"

var player: SkillRigPlayer = null
var system: SkillSystem = null

var _cam: Camera3D = null
var _label: Label = null


func _ready() -> void:
	_environment()
	_ground()
	_landmarks()
	_targets()
	player = SkillRigPlayer.new()
	player.name = "RigPlayer"
	add_child(player)
	player.global_position = Vector3(0.0, 8.0, 0.0)
	system = (load(SKILLS) as PackedScene).instantiate() as SkillSystem
	player.add_child(system)
	var aim_spec := Game.flag("aim").split(",")
	player.rig_aim.point = Vector3(0.0, 10.0, -200.0)
	if aim_spec.size() >= 3:
		player.rig_aim.point = Vector3(float(aim_spec[0]), float(aim_spec[1]), float(aim_spec[2]))
	Game.register_player(player)
	_feel()
	_camera()
	_readout()
	set_process(true)


## The shipped fx unit: the FEEL rows in docs/FEEL.md drive the shake, flash, post and particles the
## captures are judged on.
func _feel() -> void:
	if not ResourceLoader.exists(FEEL):
		push_warning("SkillsRange: no FeelDirector at %s, captures will have no screen feel" % FEEL)
		return
	add_child((load(FEEL) as PackedScene).instantiate())


## ART.md §Look: AgX at exposure 1.0 with Glow above an HDR threshold of 1.2, so the additive skill
## geometry blooms instead of clipping to flat white.
func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.05, 0.09, 0.20)
	sky_mat.sky_horizon_color = Color(0.40, 0.44, 0.56)
	sky_mat.ground_bottom_color = Color(0.09, 0.10, 0.12)
	sky_mat.ground_horizon_color = Color(0.28, 0.30, 0.34)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.42, 0.48, 0.60)
	env.fog_density = 0.0006
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.2
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for level: Array in [[2, 0.3], [3, 0.45], [4, 0.4], [5, 0.25]]:
		env.set_glow_level(int(level[0]), float(level[1]))
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	sun.light_energy = 1.4
	sun.light_color = Color(1.0, 0.93, 0.84)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-16.0, 205.0, 0.0)
	fill.light_energy = 0.5
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.shadow_enabled = false
	add_child(fill)


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
	mesh.material_override = _solid(Color(0.20, 0.21, 0.24), 0.9)
	mesh.position = Vector3(0.0, 0.02, 0.0)
	add_child(mesh)
	for i in 5:  ## range markers every 100 m so distances read in the captures
		var stripe := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(60.0, 2.0)
		stripe.mesh = pm
		stripe.material_override = _solid(Color(0.30, 0.32, 0.36), 0.85)
		stripe.position = Vector3(0.0, 0.05, -100.0 * float(i + 1))
		add_child(stripe)


## A tower, a sky bridge and the glowing `&"anchor_node"` markers the Skyhook snaps to (CONTRACTS §7
## — the city places these; here the range spawns its own so the grapple has real hooks to bite).
func _landmarks() -> void:
	_block("Tower", Vector3(-90.0, 60.0, -230.0), Vector3(46.0, 120.0, 46.0))
	_block("TowerB", Vector3(90.0, 80.0, -230.0), Vector3(46.0, 160.0, 46.0))
	_block("SkyBridge", Vector3(0.0, 96.0, -230.0), Vector3(140.0, 5.0, 20.0))
	_block("Pylon", Vector3(150.0, 30.0, -120.0), Vector3(16.0, 60.0, 16.0))
	for at: Vector3 in [Vector3(-90.0, 122.0, -230.0), Vector3(90.0, 162.0, -230.0),
			Vector3(-40.0, 92.0, -230.0), Vector3(40.0, 92.0, -230.0),
			Vector3(150.0, 62.0, -120.0)]:
		_anchor_node(at)


func _anchor_node(at: Vector3) -> void:
	var node := Marker3D.new()
	node.name = "AnchorNode"
	node.add_to_group(&"anchor_node")
	add_child(node)
	node.global_position = at
	var glow := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 3.2
	sphere.height = 6.4
	glow.mesh = sphere
	glow.material_override = SkillFx.glow(Color(1.0, 0.72, 0.25), 3.0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(glow)


func _block(block_name: String, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = block_name
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	add_child(body)
	body.global_position = at
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = _solid(Color(0.30, 0.31, 0.34), 0.8)
	body.add_child(mesh)


func _solid(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = 0.1
	return m


## Targets at the three engagement bands (SPEC §5: close ≤ 80, mid 80-180, long 180-300) so the
## captures show each effect at a readable size: a burst silhouette at 30 m, fins and the well at
## 100-180 m, the lance corridor down the whole runway.
func _targets() -> void:
	for i in 5:
		_dummy(Vector3(float(i - 2) * 24.0, 0.0, -300.0), false)
	for i in 3:
		_dummy(Vector3(float(i - 1) * 26.0, 0.0, -180.0), i == 1)
	for i in 4:
		_dummy(Vector3(float(i - 2) * 16.0, 0.0, -100.0), false)
	for i in 3:
		_dummy(Vector3(float(i - 1) * 18.0, 0.0, -34.0), false)


func _dummy(at: Vector3, heavy: bool) -> void:
	var e := SkillDummyEnemy.new()
	if heavy:
		e.make_heavy()
	e.invincible = true
	add_child(e)
	e.global_position = at


## Timeline hook: cut the camera (tools/godot.sh drive --timeline=...).
## `args` = [px, py, pz, lx, ly, lz, fov]. One camera cannot frame a 20 m barrier and an 800 m beam,
## so the movie cuts between a hero framing and two wide ones.
func debug_cam(a: Array) -> void:
	if _cam == null or a.size() < 6:
		return
	_cam.global_position = Vector3(float(a[0]), float(a[1]), float(a[2]))
	_cam.look_at(Vector3(float(a[3]), float(a[4]), float(a[5])), Vector3.UP)
	if a.size() >= 7:
		_cam.fov = float(a[6])


func _camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.fov = 55.0          ## Godot fov is VERTICAL (SPEC §5)
	_cam.near = 0.5
	_cam.far = 4000.0
	add_child(_cam)
	var spec := Game.flag("cam").split(",")
	var pos := Vector3(38.0, 30.0, 62.0)
	var look := Vector3(0.0, 16.0, -140.0)
	if spec.size() >= 6:
		pos = Vector3(float(spec[0]), float(spec[1]), float(spec[2]))
		look = Vector3(float(spec[3]), float(spec[4]), float(spec[5]))
	if spec.size() >= 7:
		_cam.fov = float(spec[6])
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	_cam.current = true


## Live `hud_state()` so a capture shows the cooldown / charge / OD numbers the HUD unit will draw.
func _readout() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Readout"
	add_child(layer)
	_label = Label.new()
	_label.name = "State"
	_label.position = Vector2(24.0, 20.0)
	_label.add_theme_font_size_override(&"font_size", 18)
	_label.add_theme_color_override(&"font_color", Color(0.85, 0.95, 1.0))
	layer.add_child(_label)


func _process(_delta: float) -> void:
	if _label == null or system == null:
		return
	var s := system.hud_state()
	var lines: PackedStringArray = PackedStringArray()
	for id: String in ["rift_step", "anchor", "fins", "ward", "burst", "well", "plunge"]:
		var cd := float(s["%s_cd" % id])
		var ch := int(s["%s_charges" % id])
		lines.append("%-10s cd %5.1f  charges %d  %s" % [id, cd, ch,
				"READY" if bool(s["%s_ready" % id]) else "-"])
	lines.append("od %5.1f  active %s  left %4.1f  lance %s" % [float(s["od"]),
			str(s["overdrive_active"]), float(s["overdrive_left"]),
			"READY" if bool(s["lance_ready"]) else "-"])
	lines.append("ambush %s  fins_out %d  ward %.1f/%.0f  well %.1f" % [
			str(s["ambushing"]), int(s["fins_out"]), float(s["ward_left"]),
			float(s["ward_absorb"]), float(s["well_left"])])
	_label.text = "\n".join(lines)
