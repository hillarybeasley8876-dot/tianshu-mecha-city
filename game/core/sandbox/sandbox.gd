extends Node3D
## Core sandbox arena (core-owned): a 900 m grey-box test range at mech scale (hero ~16 m tall) so the
## movement, camera, combat, enemy and feel units can test before the city exists. Built from the
## BOXES table at load; navmesh baked at runtime, then Game.mark_world_built().
## Landmarks (x, z): spawn (0, 60) facing -Z; runway z=-330 along X; deck at +40 m with ramps west;
## twin towers + 90 m sky bridge north; trench (-30 m) east with ramps; cover field south; pillar
## forest north-west; stepped plateau (12/24/36 m) south-west for jump tests.

const GRID := preload("res://core/sandbox/grid.gdshader")
const SIZE := 900.0
const TRENCH := Rect2(150.0, -120.0, 70.0, 240.0)  ## x, z, width (x), length (z) of the -30 m trench

## [name, center x, center y, center z, size x, size y, size z, rot_x_deg, rot_z_deg, tint]
const BOXES: Array[Array] = [
	["deck_west", -220.0, 38.0, -40.0, 140.0, 4.0, 70.0, 0.0, 0.0, 0],
	["deck_ramp", -220.0, 18.5, 52.0, 30.0, 3.0, 120.0, 19.0, 0.0, 0],
	["deck_ramp_b", -320.0, 18.5, -40.0, 120.0, 3.0, 30.0, 0.0, 19.0, 0],
	["deck_pillar_a", -270.0, 18.0, -60.0, 8.0, 36.0, 8.0, 0.0, 0.0, 1],
	["deck_pillar_b", -170.0, 18.0, -20.0, 8.0, 36.0, 8.0, 0.0, 0.0, 1],
	["tower_n1", -60.0, 75.0, -260.0, 50.0, 150.0, 50.0, 0.0, 0.0, 2],
	["tower_n2", 80.0, 100.0, -260.0, 50.0, 200.0, 50.0, 0.0, 0.0, 2],
	["sky_bridge", 10.0, 88.0, -260.0, 90.0, 4.0, 22.0, 0.0, 0.0, 0],
	["tower_ne", 260.0, 60.0, -260.0, 70.0, 120.0, 40.0, 0.0, 0.0, 2],
	["block_s1", -60.0, 20.0, 220.0, 40.0, 40.0, 40.0, 0.0, 0.0, 2],
	["block_s2", 60.0, 30.0, 250.0, 50.0, 60.0, 30.0, 0.0, 0.0, 2],
	["cover_1", -20.0, 4.0, 150.0, 24.0, 8.0, 4.0, 0.0, 0.0, 1],
	["cover_2", 30.0, 4.0, 170.0, 4.0, 8.0, 24.0, 0.0, 0.0, 1],
	["cover_3", -60.0, 4.0, 120.0, 20.0, 8.0, 4.0, 0.0, 0.0, 1],
	["cover_4", 70.0, 6.0, 120.0, 12.0, 12.0, 12.0, 0.0, 0.0, 1],
	["plateau_1", -260.0, 6.0, 240.0, 80.0, 12.0, 80.0, 0.0, 0.0, 0],
	["plateau_2", -260.0, 12.0, 300.0, 60.0, 24.0, 40.0, 0.0, 0.0, 0],
	["plateau_3", -310.0, 18.0, 330.0, 40.0, 36.0, 40.0, 0.0, 0.0, 0],
	["trench_ramp_n", 185.0, -15.5, -77.0, 60.0, 3.0, 90.0, 18.0, 0.0, 0],
	["trench_ramp_s", 185.0, -15.5, 77.0, 60.0, 3.0, 90.0, -18.0, 0.0, 0],
	["runway_wall", 0.0, 3.0, -360.0, 700.0, 6.0, 3.0, 0.0, 0.0, 1],
]
const TINTS: Array[Color] = [Color(0.55, 0.57, 0.6), Color(0.45, 0.42, 0.38), Color(0.4, 0.46, 0.55)]

var _nav: NavigationRegion3D


func _ready() -> void:
	_environment()
	_ground()
	for b in BOXES:
		_box(String(b[0]), Vector3(b[1], b[2], b[3]), Vector3(b[4], b[5], b[6]), float(b[7]), float(b[8]), int(b[9]))
	for i in 9:
		var a := float(i) * TAU / 9.0
		_box("pillar_%d" % i, Vector3(-300.0 + cos(a) * 60.0, 50.0, -250.0 + sin(a) * 60.0),
				Vector3(10.0, 100.0, 10.0), 0.0, 0.0, 1)
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = Vector3(0.0, 1.0, 60.0)
	add_child(spawn)
	_bake_navigation()


func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.36, 0.6)
	sky_mat.sky_horizon_color = Color(0.68, 0.72, 0.78)
	sky_mat.ground_horizon_color = Color(0.5, 0.5, 0.52)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.fog_enabled = true
	env.fog_density = 0.0006
	env.fog_light_color = Color(0.6, 0.66, 0.74)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 700.0
	add_child(sun)


## Ground is four 40 m-thick slabs around the trench (so the trench has walls) plus the trench floor.
func _ground() -> void:
	_nav = NavigationRegion3D.new()
	_nav.name = "Navigation"
	add_child(_nav)
	var half := SIZE * 0.5
	var t := TRENCH
	_box("ground_w", Vector3((-half + t.position.x) * 0.5, -20.0, 0.0), Vector3(t.position.x + half, 40.0, SIZE), 0.0, 0.0, 0)
	_box("ground_e", Vector3((t.end.x + half) * 0.5, -20.0, 0.0), Vector3(half - t.end.x, 40.0, SIZE), 0.0, 0.0, 0)
	_box("ground_n", Vector3(t.get_center().x, -20.0, (-half + t.position.y) * 0.5), Vector3(t.size.x, 40.0, t.position.y + half), 0.0, 0.0, 0)
	_box("ground_s", Vector3(t.get_center().x, -20.0, (t.end.y + half) * 0.5), Vector3(t.size.x, 40.0, half - t.end.y), 0.0, 0.0, 0)
	_box("trench_floor", Vector3(t.get_center().x, -31.0, t.get_center().y), Vector3(t.size.x, 2.0, t.size.y), 0.0, 0.0, 1)


func _box(box_name: String, center: Vector3, size: Vector3, rot_x: float, rot_z: float, tint: int) -> void:
	var body := StaticBody3D.new()
	body.name = box_name
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = center
	body.rotation_degrees = Vector3(rot_x, 0.0, rot_z)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var mat := ShaderMaterial.new()
	mat.shader = GRID
	mat.set_shader_parameter(&"albedo", TINTS[tint])
	mesh.material_override = mat
	body.add_child(mesh)
	(_nav if _nav != null else self).add_child(body)


func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.cell_size = 1.0
	nm.cell_height = 0.5
	nm.agent_radius = 3.0
	nm.agent_height = 10.0
	nm.agent_max_climb = 2.0
	nm.agent_max_slope = 40.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Layers.WORLD
	_nav.navigation_mesh = nm
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(map, nm.cell_height)
	_nav.bake_finished.connect(_on_baked, CONNECT_ONE_SHOT)
	_nav.bake_navigation_mesh(true)


func _on_baked() -> void:
	var polys := _nav.navigation_mesh.get_polygon_count() if _nav.navigation_mesh != null else 0
	print("Sandbox: navmesh baked (%d polygons)" % polys)
	Game.mark_world_built()
