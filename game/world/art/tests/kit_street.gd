extends Node3D
## city-art kit look-dev (world/art/tests/kit_street.tscn). Judges the `mc_kit` skin — the material
## `McMaterials.kit()` hands city-kit for its Tripo buildings — before any Tripo building exists:
##   * six synthetic towers carrying a baked texture set (tests/kit_bake.gd) in the two UV regimes a
##     real export uses, one with baked neon and one double-sided;
##   * four REAL processed Tripo props from world/props/meshes, so the path that matters — a material
##     Godot imported from a glb, packed ORM, baked emissive — is exercised, not simulated;
##   * two `mc_concrete` blockout towers of the same massing as the control, which is the "building
##     blocks" look the kit has to beat;
##   * a hive site, because the creep has to reach kit geometry too.
## Cameras are passed on the command line:
##   tools/godot.sh shot --scene=res://world/art/tests/kit_street.tscn --out=kit --env-only --warm=90 \
##     --cams=street:0,26,-150:0,60,120:55;near:0,90,-430:0,80,150:50;mid:0,150,-900:0,110,200:50

const ENV_SCENE := preload("res://world/art/environment.tscn")
const BAKE := preload("res://world/art/tests/kit_bake.gd")
const PROPS: Array[String] = ["ac_cluster", "antenna_array", "barrier", "streetlamp"]

## [x, z, w, d, h, seed, uv_scale, neon, two_sided] — a canyon running north, so the near camera sees
## the sun on one wall and the shadow on the other, which is where the window layer has to hold up.
const TOWERS: Array[Array] = [
	[-92.0, -150.0, 54.0, 52.0, 186.0, 11, 1.0, true, false],
	[-88.0, -20.0, 46.0, 58.0, 128.0, 23, 4.0, false, false],
	[-96.0, 130.0, 58.0, 50.0, 224.0, 37, 1.0, false, true],
	[90.0, -180.0, 50.0, 54.0, 152.0, 51, 3.0, false, false],
	[94.0, -40.0, 56.0, 48.0, 206.0, 67, 1.0, true, false],
	[86.0, 120.0, 44.0, 52.0, 116.0, 83, 5.0, false, false],
	# The control: same massing, city-build's procedural role, no Tripo detail at all.
	[-92.0, 280.0, 54.0, 52.0, 170.0, 0, 0.0, false, false],
	[90.0, 280.0, 54.0, 52.0, 170.0, 0, 0.0, false, false],
]

var kit_surfaces: int = 0
var prop_surfaces: int = 0


func _ready() -> void:
	add_child(ENV_SCENE.instantiate())
	_build_ground()
	_build_towers()
	_build_props()
	var infection := get_tree().get_first_node_in_group(&"infection")
	if infection != null:
		infection.call(&"register_site", &"hive_kit", Vector3(0.0, 0.0, 60.0), 150.0)
		infection.call(&"set_intensity", &"hive_kit", 0.8, 0.01)
	print("KITSTREET towers=%d kit_surfaces=%d prop_surfaces=%d materials=%d"
		% [TOWERS.size(), kit_surfaces, prop_surfaces, McKitSkin.count()])


func _build_ground() -> void:
	var deck := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1800.0, 4.0, 1800.0)
	deck.mesh = mesh
	deck.position = Vector3(0.0, -2.0, 0.0)
	deck.material_override = McMaterials.get_material(&"mc_deck")
	add_child(deck)


## Each tower is a box carrying a baked texture set, skinned through the same one-line call city-kit
## makes. `uv_scale` 0 means the control: no kit material at all, just city-build's procedural role.
func _build_towers() -> void:
	for t in TOWERS:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(t[2], t[4], t[3])
		mi.mesh = box
		mi.position = Vector3(t[0], float(t[4]) * 0.5, t[1])
		if float(t[6]) <= 0.0:
			mi.material_override = McMaterials.get_material(&"mc_concrete")
			add_child(mi)
			continue
		var src := BAKE.material("kit_tower_%d" % int(t[5]), int(t[5]), Color(0.74, 0.72, 0.68),
			float(t[6]), Color(0.35, 0.95, 1.0) if bool(t[7]) else Color(0, 0, 0),
			bool(t[8]))
		box.material = src        # as the glb importer would hand it over
		var kit_root := Node3D.new()
		kit_root.name = "Kit_%d" % int(t[5])
		kit_root.add_child(mi)
		add_child(kit_root)
		# The whole hand-off: one call, on the imported material, from the unit that owns the kit.
		kit_surfaces += McMaterials.apply_kit(kit_root)


## Four real Tripo props at the foot of the towers. Their glbs carry packed ORM maps and a baked
## emissive mask, so this is the material shape `mc_kit` will actually meet.
func _build_props() -> void:
	var spots := [Vector3(-58.0, 0.0, -150.0), Vector3(-58.0, 0.0, -40.0),
		Vector3(62.0, 0.0, -180.0), Vector3(62.0, 0.0, -20.0)]
	for i in PROPS.size():
		var mesh := PropScatter.load_mesh(StringName(PROPS[i]))
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = spots[i]
		var root := Node3D.new()
		root.name = "Prop_" + PROPS[i]
		root.add_child(mi)
		add_child(root)
		prop_surfaces += McMaterials.apply_kit(root)
