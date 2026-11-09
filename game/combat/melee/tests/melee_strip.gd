class_name MeleeStrip
extends Node3D
## 60 fps filmstrips of the melee moves against the SHIPPED hero rig (review r4 gate): the drawn
## blade must read as held in the hand through the whole string, the lunge and the charged slash.
##
## Eight frames per move, evenly spaced across its frame data, from the front and from the side,
## composed into one sheet per view: `captures/melee_r5_strip_<move>_<view>.jpg`.
## `tools/godot.sh drive --scene=res://combat/melee/tests/melee_strip.tscn --nocam --out=melee_r5`

const MELEE := "res://combat/melee/melee_system.tscn"
const HERO_MODEL := "res://player/model/hero3/hero3_model.tscn"
# r12 §3: derived from the project directory — a literal home path breaks on any other checkout.
const OUT_DIR_REL := "captures"
## Lazy: a static initialiser runs before the autoloads exist (city-art r12 §3 `ArtRepo`).
static var OUT_DIR: String = ""
const FRAMES := 8
const CELL := Vector2i(640, 360)
## Moves to film: the ground string (one continuous run), the lunge, the charged slash.
const MOVES: Array[StringName] = [&"string", MeleeTable.LUNGE, MeleeTable.CHARGE_SLASH]
## Camera stations, relative to the mech: in front of it (it faces −Z) and off its right side.
const VIEWS: Dictionary = {
	"front": Vector3(0.0, 5.0, -36.0),
	"side": Vector3(34.0, 5.0, -2.0),
}
## Aimed at the mech's waist (the body origin is 8 m up, the head 16 m), so the blade has room.
const LOOK_AT := Vector3(0.0, 1.0, 0.0)

var player: MeleeRigPlayer = null
var melee: MeleeSystem = null
var _cam: Camera3D = null


func _ready() -> void:
	_environment()
	_ground()
	player = MeleeRigPlayer.new()
	player.name = "RigPlayer"
	if ResourceLoader.exists(HERO_MODEL):
		player.model_scene = HERO_MODEL
	add_child(player)
	player.global_position = Vector3(0.0, 8.0, 0.0)
	melee = (load(MELEE) as PackedScene).instantiate() as MeleeSystem
	player.add_child(melee)
	player.aim_ref.look_at_point(Vector3(0.0, 10.0, -40.0))
	Game.register_player(player)
	Game.mark_world_built()
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.fov = 45.0
	_cam.near = 0.5
	_cam.far = 4000.0
	add_child(_cam)
	_cam.current = true
	_run.call_deferred()


func _run() -> void:
	if OUT_DIR.is_empty():
		OUT_DIR = ArtRepo.at(OUT_DIR_REL)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	await get_tree().process_frame
	## `--strip=string:side` films one sheet, which is all a tuning pass needs.
	var only := Game.flag("strip").split(":")
	for move: StringName in MOVES:
		if only.size() == 2 and String(move) != only[0]:
			continue
		for view: String in VIEWS:
			if only.size() == 2 and view != only[1]:
				continue
			var sheet := Image.create(CELL.x * FRAMES, CELL.y, false, Image.FORMAT_RGB8)
			for i in FRAMES:
				var shot := await _frame(move, view, i)
				if shot != null:
					sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, 0))
			var path := "%s/melee_r5_strip_%s_%s.jpg" % [OUT_DIR, move, view]
			sheet.save_jpg(path, 0.86)
			print("STRIP %s" % path)
	get_tree().quit(0)


## One cell: rewind, play the move, and grab the frame `index` of 8 across its frame data.
func _frame(move: StringName, view: String, index: int) -> Image:
	_reset()
	var span := _span_ticks(move)
	var step := maxi(int(round(float(span) / float(FRAMES))), 1)
	await _wait(6)
	_start(move)
	await _wait(step * index + 10)
	## Framed on the mech at the moment of the shot: a step-in and the lunge both move it.
	_cam.global_position = player.global_position + VIEWS[view]
	_cam.look_at(player.global_position + LOOK_AT, Vector3.UP)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGB8)
	## Let the move (and the string's own chaining) finish before the next cell rewinds the rig.
	await _wait(span)
	return img


## The string is three moves back to back, so its strip spans all three.
func _span_ticks(move: StringName) -> int:
	if move != &"string":
		return MeleeTable.ticks(MeleeTable.total_frames(move))
	var total := 0
	for id: StringName in MeleeTable.GROUND_CHAIN:
		total += MeleeTable.ticks(MeleeTable.field(id, "cancel_to"))
	return total


func _start(move: StringName) -> void:
	if move == &"string":
		_string()
		return
	melee._begin(move)


## L1 → L2 → L3 through the cancel windows, the way a player chains them.
func _string() -> void:
	for id: StringName in MeleeTable.GROUND_CHAIN:
		melee._begin(id)
		var until := MeleeTable.ticks(MeleeTable.field(id, "cancel_to"))
		for _i in until:
			await get_tree().physics_frame


func _reset() -> void:
	melee.reset()
	player.reset_state()
	player.global_position = Vector3(0.0, 8.0, 0.0)
	player.global_rotation = Vector3.ZERO


func _wait(ticks: int) -> void:
	for _i in maxi(ticks, 1):
		await get_tree().physics_frame


## ART.md §3 dusk key light + a cool fill, the same read the melee range uses, so a strip is judged
## under the light the game ships.
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
	sky_mat.sun_angle_max = 6.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.2
	env.glow_intensity = 0.4
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = MeleeRange.sun_rotation(18.0, 315.0)
	sun.light_energy = 2.2
	sun.light_color = Color("ffd3a0")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = MeleeRange.sun_rotation(52.0, 135.0)
	fill.light_energy = 0.45
	fill.light_color = Color("8fa7c4")
	fill.shadow_enabled = false
	add_child(fill)


func _ground() -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600.0, 600.0)
	mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = MeleeRange.GROUND_COLOR
	mat.roughness = 0.85
	mesh.material_override = mat
	mesh.name = "Ground"
	add_child(mesh)

