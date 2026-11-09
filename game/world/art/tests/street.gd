extends Node3D
## city-art look-dev street (world/art/tests/street.tscn). A canyon of towers built only from the
## mc_* material library, so every capture judges the MATERIALS, the environment and the haze — not
## city-build's geometry. Layout echoes key art v2 (deep canyon, small mech, infection creep) with a
## canal to the west for the water shader and a skybridge for the depth layers.
## Conventions copied from city-build: metre UVs on window bands and roads, ≤ 60 m plan chunks.

const KIT := preload("res://world/art/tests/street_kit.gd")
const ENV_SCENE := preload("res://world/art/environment.tscn")

const CANYON_LENGTH := 760.0
const AVENUE_W := 60.0
const SIDEWALK_W := 14.0
const GROUND_W := 420.0

## [side (-1 west / +1 east), z, width, depth, height, role]
const TOWERS: Array[Array] = [
	[-1, -300.0, 58.0, 56.0, 214.0, &"mc_panel_white"],
	[-1, -190.0, 52.0, 60.0, 150.0, &"mc_concrete"],
	[-1, -80.0, 60.0, 52.0, 236.0, &"mc_panel_white"],
	[-1, 40.0, 48.0, 58.0, 118.0, &"mc_stone"],
	[-1, 150.0, 56.0, 50.0, 176.0, &"mc_concrete"],
	[-1, 260.0, 44.0, 44.0, 92.0, &"mc_terracotta"],
	[1, -280.0, 60.0, 54.0, 188.0, &"mc_concrete"],
	[1, -160.0, 54.0, 58.0, 262.0, &"mc_panel_white"],
	[1, -40.0, 58.0, 52.0, 134.0, &"mc_stone"],
	[1, 70.0, 50.0, 56.0, 208.0, &"mc_concrete"],
	[1, 190.0, 60.0, 48.0, 156.0, &"mc_panel_white"],
	[1, 290.0, 46.0, 46.0, 104.0, &"mc_terracotta"],
]

## Distant skyline ring: [x, z, width, depth, height]. Scenery only, never walked on.
const SKYLINE: Array[Array] = [
	[-620.0, -700.0, 70.0, 70.0, 300.0], [-380.0, -820.0, 56.0, 56.0, 220.0],
	[-120.0, -900.0, 80.0, 60.0, 360.0], [180.0, -860.0, 60.0, 60.0, 250.0],
	[520.0, -740.0, 72.0, 56.0, 320.0], [780.0, -420.0, 56.0, 72.0, 200.0],
	[860.0, 60.0, 64.0, 64.0, 280.0], [700.0, 520.0, 56.0, 56.0, 180.0],
	[-760.0, -260.0, 64.0, 64.0, 240.0], [-820.0, 220.0, 56.0, 70.0, 300.0],
	[-560.0, 640.0, 60.0, 60.0, 190.0], [240.0, 780.0, 70.0, 56.0, 230.0],
]


func _ready() -> void:
	add_child(ENV_SCENE.instantiate())
	_build_ground()
	_build_towers()
	_build_canyon_details()
	_build_canal()
	_build_signage()
	_build_life()
	_build_skyline()
	var infection := get_tree().get_first_node_in_group(&"infection")
	if infection != null:
		infection.call(&"register_site", &"hive_street", Vector3(60.0, 0.0, -120.0), 170.0)
		infection.call(&"set_intensity", &"hive_street", 0.85, 0.01)
		infection.call(&"set_intensity", &"hive_a2", 0.0, 0.01)
		infection.call(&"set_intensity", &"hive_a5", 0.0, 0.01)
		infection.call(&"set_intensity", &"hive_a6", 0.0, 0.01)


func _build_ground() -> void:
	# The carriageway is its own slab; the deck either side stops at the kerb, so nothing z-fights
	# at the grazing angles a 16 m mech camera works at.
	var road := MeshInstance3D.new()
	road.mesh = KIT.slab(Vector2(AVENUE_W, CANYON_LENGTH))
	var road_mat := McMaterials.road_variant(&"avenue") as ShaderMaterial
	road_mat.set_shader_parameter(&"width_m", AVENUE_W)
	road_mat.set_shader_parameter(&"crossing_every", 190.0)
	road.material_override = road_mat
	add_child(road)

	var walk_w := (GROUND_W - AVENUE_W) * 0.5
	var walks: Array[Transform3D] = []
	for side: float in [-1.0, 1.0]:
		var x := side * (AVENUE_W * 0.5 + walk_w * 0.5)
		walks.append(Transform3D(Basis(), Vector3(x, 0.0, 0.0)))
	KIT.scatter(self, KIT.slab(Vector2(walk_w, CANYON_LENGTH)), McMaterials.get_material(&"mc_deck"),
		walks, &"deck")
	var kerbs: Array[Transform3D] = []
	for side: float in [-1.0, 1.0]:
		kerbs.append(Transform3D(Basis(), Vector3(side * (AVENUE_W * 0.5 + SIDEWALK_W * 0.5), 1.2, 0.0)))
	KIT.scatter(self, KIT.slab(Vector2(SIDEWALK_W, CANYON_LENGTH)), McMaterials.get_material(&"mc_stone"),
		kerbs, &"sidewalks")


func _build_towers() -> void:
	var shells: Dictionary = {}     ## role -> Array[Transform3D]
	var core := KIT.box(Vector3.ONE)
	var win_meshes: Array[Dictionary] = []
	for t in TOWERS:
		var side: float = t[0]
		var z: float = t[1]
		var size := Vector3(t[2], t[4], t[3])
		var x := side * (AVENUE_W * 0.5 + SIDEWALK_W + size.x * 0.5)
		var role: StringName = t[5]
		var xf := Transform3D(Basis().scaled(size), Vector3(x, size.y * 0.5, z))
		if not shells.has(role):
			shells[role] = [] as Array[Transform3D]
		(shells[role] as Array).append(xf)
		win_meshes.append({"size": size, "pos": Vector3(x, 0.0, z)})

	for role in shells:
		KIT.scatter(self, core, McMaterials.get_material(role), shells[role], role)
	var win_mat := McMaterials.get_material(&"mc_window")
	for w in win_meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = KIT.windows(w["size"])
		mi.position = w["pos"]
		mi.material_override = win_mat
		add_child(mi)


func _build_canyon_details() -> void:
	var metal := McMaterials.get_material(&"mc_metal")
	var panel := McMaterials.get_material(&"mc_panel_white")
	var accent := McMaterials.get_material(&"mc_up_accent")
	var roof: Array[Transform3D] = []
	var rails: Array[Transform3D] = []
	for t in TOWERS:
		var side: float = t[0]
		var z: float = t[1]
		var size := Vector3(t[2], t[4], t[3])
		var x := side * (AVENUE_W * 0.5 + SIDEWALK_W + size.x * 0.5)
		var top := size.y
		for i in range(3):
			var w := 6.0 + float(i) * 3.0
			roof.append(Transform3D(Basis().scaled(Vector3(w, 4.0 + float(i), w * 0.8)),
				Vector3(x + (float(i) - 1.0) * size.x * 0.28, top + 2.0 + float(i) * 0.5, z + float(i) * 6.0)))
		# Lift / vent rail up the street facade: the reserved cyan "up" language.
		rails.append(Transform3D(Basis().scaled(Vector3(1.6, top * 0.92, 1.6)),
			Vector3(x - side * (size.x * 0.5 + 0.6), top * 0.46, z + size.z * 0.3)))
	KIT.scatter(self, KIT.box(Vector3.ONE), metal, roof, &"rooftop_machinery")
	KIT.scatter(self, KIT.box(Vector3.ONE), accent, rails, &"up_rails")

	# Skybridge across the canyon at +80: the mid depth layer of the key art.
	var bridge := MeshInstance3D.new()
	bridge.mesh = KIT.box(Vector3(AVENUE_W + SIDEWALK_W * 2.0 + 40.0, 4.0, 20.0))
	bridge.position = Vector3(0.0, 80.0, -110.0)
	bridge.material_override = panel
	add_child(bridge)
	var fascia := MeshInstance3D.new()
	fascia.mesh = KIT.box(Vector3(AVENUE_W + SIDEWALK_W * 2.0 + 40.0, 1.2, 21.0))
	fascia.position = Vector3(0.0, 76.0, -110.0)
	fascia.material_override = accent
	add_child(fascia)


func _build_canal() -> void:
	var bank := MeshInstance3D.new()
	bank.mesh = KIT.slab(Vector2(90.0, CANYON_LENGTH), Vector3(-235.0, -6.0, 0.0))
	bank.material_override = McMaterials.get_material(&"mc_stone")
	add_child(bank)
	var water := MeshInstance3D.new()
	water.mesh = KIT.slab(Vector2(80.0, CANYON_LENGTH), Vector3(-235.0, -3.0, 0.0))
	water.material_override = McMaterials.get_material(&"mc_water")
	add_child(water)


## Holographic signage: one wide billboard and a run of vertical shop signs on the street facades.
func _build_signage() -> void:
	var tints: Array[Color] = [ArtPalette.NEON_CYAN, ArtPalette.NEON_MAGENTA,
		ArtPalette.NEON_AMBER, ArtPalette.NEON_JADE]
	var projector := McMaterials.get_material(&"mc_metal")
	for i in range(5):
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var z := -220.0 + float(i) * 110.0
		var w := 14.0 if i % 2 == 0 else 26.0
		var h := 34.0 if i % 2 == 0 else 15.0
		var y := 40.0 + float(i) * 12.0
		var x := side * (AVENUE_W * 0.5 + SIDEWALK_W + 1.5)
		var tint: Color = tints[i % tints.size()]
		var graphic := HoloGraphics.shop_sign(1000 + i, tint) if i % 2 == 0 \
			else HoloGraphics.billboard(2000 + i, tint)
		var sign := MeshInstance3D.new()
		# The sign faces the street, i.e. back toward x = 0 from the facade it hangs on.
		sign.mesh = KIT.wall(Vector2(w, h), Vector3.ZERO, Vector3(-side, 0.0, 0.0))
		sign.position = Vector3(x, y, z)
		var mat := McMaterials.hologram(tint, graphic)
		mat.set_shader_parameter(&"project_range", 400.0)
		mat.set_shader_parameter(&"gain", 1.8)
		sign.material_override = mat
		sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sign)
		var box := MeshInstance3D.new()
		box.mesh = KIT.box(Vector3(3.0, 1.6, 3.0))
		box.position = Vector3(x + side * 1.6, y - h * 0.5 - 2.0, z)
		box.material_override = projector
		add_child(box)



## Detail layers (brief 5): cables across the canyon, Old Town banners, reactor smoke, steam vents
## and a drone flock — everything that separates "a city" from "a row of boxes".
func _build_life() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var spans: Array = []
	var banners: Array = []
	for i in range(TOWERS.size() - 1):
		var a: Array = TOWERS[i]
		var b: Array = TOWERS[i + 1]
		if signf(a[0]) != signf(b[0]):
			continue
		var ax := float(a[0]) * (AVENUE_W * 0.5 + SIDEWALK_W + float(a[2]) * 0.5)
		var bx := float(b[0]) * (AVENUE_W * 0.5 + SIDEWALK_W + float(b[2]) * 0.5)
		var y := minf(float(a[4]), float(b[4])) * rng.randf_range(0.35, 0.8)
		spans.append([Vector3(ax, y, a[1] + 12.0), Vector3(bx, y, b[1] - 12.0)])
	# Two long spans straight across the canyon, the way the key art strings them.
	for z: float in [-240.0, -30.0, 170.0]:
		spans.append([Vector3(-52.0, 62.0, z), Vector3(52.0, 68.0, z), 14.0])
		spans.append([Vector3(-52.0, 74.0, z + 6.0), Vector3(52.0, 71.0, z + 6.0), 12.0])
	var cables := CableNet.new()
	cables.name = "cables"
	add_child(cables)
	cables.build(spans)

	for t in TOWERS:
		if t[5] != &"mc_terracotta":
			continue
		var side: float = t[0]
		var x := side * (AVENUE_W * 0.5 + SIDEWALK_W + 1.0)
		for k in range(5):
			banners.append([Vector3(x, 14.0 + float(k) * 9.0, float(t[1]) - 16.0 + float(k) * 7.0),
				-90.0 * side, rng.randf_range(2.4, 4.0), rng.randf_range(5.0, 9.0)])
	var cloth := ClothLines.new()
	cloth.name = "banners"
	add_child(cloth)
	cloth.build(banners)

	var life := CityLife.new()
	life.name = "life"
	add_child(life)
	for z: float in [-300.0, -60.0, 200.0]:
		life.smoke_column(Vector3(AVENUE_W * 0.5 + 96.0, 96.0, z), 130.0, 10.0)
		life.steam_vent(Vector3(AVENUE_W * 0.5 + 6.0, 1.5, z + 40.0))
	life.drone_flock(Vector3(0.0, 120.0, -80.0), 130.0, 48)
	for e in life.emitters:
		e.emitting = true


func _build_skyline() -> void:
	var xs: Array[Transform3D] = []
	for s in SKYLINE:
		var size := Vector3(s[2], s[4], s[3])
		xs.append(Transform3D(Basis().scaled(size), Vector3(s[0], size.y * 0.5, s[1])))
	var node := KIT.scatter(self, KIT.box(Vector3.ONE), McMaterials.get_material(&"mc_concrete"),
		xs, &"skyline")
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
