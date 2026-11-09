extends Node3D
## city-art prop QA row (world/props/tests/prop_row.tscn). Lays every processed prop out on a strip
## at its real size, in the project's own lighting, so decimation damage, wrong scale, bad emissive
## masks and over-bright props are all visible in one capture. 16 m reference mech box at the origin.
##   tools/godot.sh shot --scene=res://world/props/tests/prop_row.tscn --out=art_props --env-only \
##     --cams="row:0,40,180:0,8,0:60"

const ENV_SCENE := preload("res://world/art/environment.tscn")
const KIT := preload("res://world/art/tests/street_kit.gd")
const SPACING := 26.0
const ROW_LENGTH := 210.0
const MECH_HEIGHT := 16.0

## Same order as blender/props/prop_table.py, grouped so a capture reads as a catalogue.
const ORDER: Array[StringName] = [
	&"hovercar_a", &"hovercar_b", &"truck", &"bus", &"maglev_car", &"wreck_car", &"wreck_mech",
	&"streetlamp", &"vending", &"bus_shelter", &"barrier", &"food_stall", &"anchor_node",
	&"holo_projector", &"lift_platform", &"planter_tree", &"blossom_tree",
	&"ac_cluster", &"antenna_array", &"pipe_cluster", &"solar_array", &"storage_tank",
	&"water_tank", &"billboard_frame", &"container_stack", &"crane",
	&"mech_statue", &"guardian_lion", &"pagoda_top", &"koi_dragon",
]


func _ready() -> void:
	add_child(ENV_SCENE.instantiate())
	_ground()
	var per_row := int(ROW_LENGTH / SPACING)
	var missing: Array[String] = []
	for i in range(ORDER.size()):
		var prop: StringName = ORDER[i]
		var mesh := PropScatter.load_mesh(prop)
		if mesh == null:
			missing.append(String(prop))
			continue
		var node := MeshInstance3D.new()
		node.name = String(prop)
		node.mesh = mesh
		var row := float(i / per_row)
		var col := float(i % per_row)
		node.position = Vector3((col - float(per_row) * 0.5) * SPACING, 0.0, row * 80.0 - 80.0)
		if prop == &"koi_dragon":
			node.material_override = McMaterials.hologram()
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	_mech_reference()
	if not missing.is_empty():
		push_error("prop_row: missing processed meshes: %s" % ", ".join(missing))


func _ground() -> void:
	var ground := MeshInstance3D.new()
	ground.mesh = KIT.slab(Vector2(ROW_LENGTH + 120.0, 340.0))
	ground.material_override = McMaterials.get_material(&"mc_deck")
	add_child(ground)


## A plain 16 m box standing in for the hero mech: every prop in the row is judged against it.
func _mech_reference() -> void:
	var box := MeshInstance3D.new()
	box.name = "MechReference16m"
	box.mesh = KIT.box(Vector3(6.0, MECH_HEIGHT, 6.0))
	box.position = Vector3(-ROW_LENGTH * 0.5 - 20.0, MECH_HEIGHT * 0.5, 0.0)
	box.material_override = McMaterials.get_material(&"mc_panel_white")
	add_child(box)
