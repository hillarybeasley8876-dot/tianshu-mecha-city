class_name McKitBake
extends RefCounted
## city-art test kit — a synthetic stand-in for what city-kit's Blender pass exports, so the `mc_kit`
## skin can be judged before a single Tripo building has landed.
##
## The point is to be DIFFICULT in the same ways a real glTF texture set is: the windows are baked into
## the colour map as dark panes (no separate mask), occlusion/roughness/metal arrive packed in one
## image, the emissive is a neon strip rather than a window mask, and the UVs are per-model 0..1 on
## one variant and metre-scaled on another. `world/art/tests/kit_street.gd` skins these with
## `McMaterials.kit()` and photographs the result.

const SIZE := 512


## A facade bake: pale stone, a floor band every `rows`, dark glass panes inside every bay, pilasters
## every fourth bay, and per-pane value jitter so the panes are not one repeated stamp.
static func albedo(seed_value: int, base: Color, rows: int, cols: int, pane: float) -> ImageTexture:
	var px := PackedByteArray()
	px.resize(SIZE * SIZE * 3)
	var floor_h := float(SIZE) / float(rows)
	var bay_w := float(SIZE) / float(cols)
	for y in SIZE:
		var fy := float(y)
		var row := int(fy / floor_h)
		var in_floor := fy - float(row) * floor_h
		var band := 0.80 if in_floor < floor_h * 0.10 else 1.0
		for x in SIZE:
			var fx := float(x)
			var col := int(fx / bay_w)
			var in_bay := fx - float(col) * bay_w
			var pilaster := 1.06 if (col % 4 == 0 and in_bay < bay_w * 0.16) else 1.0
			var c := Color(base.r * band * pilaster, base.g * band * pilaster, base.b * band * pilaster)
			# The pane: dark glass with a mullion down its middle and a reveal around it.
			var pane_x := in_bay > bay_w * 0.18 and in_bay < bay_w * (0.18 + pane)
			var pane_y := in_floor > floor_h * 0.22 and in_floor < floor_h * 0.86
			if pane_x and pane_y:
				var j := 0.82 + 0.36 * _cell_hash(col, row, seed_value)
				var mullion := absf(in_bay - bay_w * (0.18 + pane * 0.5)) < bay_w * 0.03
				var v := 0.0 if mullion else 0.10 * j
				c = Color(v * 0.82, v * 0.92, v * 1.15)
			elif pane_x and in_floor >= floor_h * 0.86 and in_floor < floor_h * 0.92:
				c = c.darkened(0.35)   # the sill shadow under every pane
			var i := (y * SIZE + x) * 3
			px[i] = int(clampf(c.r, 0.0, 1.0) * 255.0)
			px[i + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
			px[i + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, px)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Occlusion / roughness / metal packed the way the glTF importer hands it over (r, g, b).
static func orm(rough: float, metal: float, seed_value: int) -> ImageTexture:
	var px := PackedByteArray()
	px.resize(SIZE * SIZE * 3)
	for y in SIZE:
		for x in SIZE:
			var i := (y * SIZE + x) * 3
			var ao := 0.72 + 0.28 * _cell_hash(int(x / 16), int(y / 16), seed_value)
			px[i] = int(clampf(ao, 0.0, 1.0) * 255.0)
			px[i + 1] = int(clampf(rough, 0.0, 1.0) * 255.0)
			px[i + 2] = int(clampf(metal, 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, px)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A neon strip: black except a vertical sign band and two shopfront blocks. This is what a Tripo
## building's baked emissive actually looks like, and the skin has to keep it without letting it
## swamp the window layer.
static func neon(tint: Color) -> ImageTexture:
	var px := PackedByteArray()
	px.resize(SIZE * SIZE * 3)
	for y in SIZE:
		for x in SIZE:
			var on := (x > SIZE * 0.06 and x < SIZE * 0.10 and y > SIZE * 0.06 and y < SIZE * 0.26) \
				or (y > SIZE * 0.88 and y < SIZE * 0.92 and (x / 26) % 3 == 0)
			var i := (y * SIZE + x) * 3
			px[i] = int(tint.r * 255.0) if on else 0
			px[i + 1] = int(tint.g * 255.0) if on else 0
			px[i + 2] = int(tint.b * 255.0) if on else 0
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, px)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _cell_hash(a: int, b: int, seed_value: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ (seed_value * 83492791)
	return float(absi(h) % 1000) / 1000.0


## An imported-looking material: colour + packed ORM + optional baked emissive, in the shape Godot's
## glTF importer produces (one image shared by the roughness and metallic slots). `uv_scale` is the
## tile size in UV units — 1.0 is a model-wide bake (what Tripo gives), anything larger is a
## metre-scaled set.
static func material(mat_name: String, seed_value: int, base: Color, uv_scale: float,
		neon_tint: Color = Color(0, 0, 0), two_sided: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	m.albedo_texture = albedo(seed_value, base, 26, 18, 0.64)
	var packed := orm(0.62, 0.08, seed_value)
	m.roughness_texture = packed
	m.metallic_texture = packed
	m.roughness = 1.0
	m.metallic = 1.0
	m.uv1_scale = Vector3(uv_scale, uv_scale, 1.0)
	if neon_tint.r + neon_tint.g + neon_tint.b > 0.0:
		m.emission_enabled = true
		m.emission = neon_tint
		m.emission_energy_multiplier = 2.2
		m.emission_texture = neon(neon_tint)
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
