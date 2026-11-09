class_name FacadeSigns
extends Node3D
## The Chinese neo-futurist signage layer (city-art, review r3 §2). ART.md §4: restrained neon,
## concentrated where the player is. Four pieces, all built from the DESIGN layout so they land on real
## facades, and all batched into a handful of MultiMeshes so the whole layer costs a few draw calls:
##
##   blade      vertical neon blade signs on podiums and towers, procedural CJK-like glyph strips
##   shopfront  a warm glow band at L1 on the street-facing side of every podium
##   parapet    a light line along the roof edge of tier C/D towers
##   billboard  8 large holo billboards, placed near the arenas, canyon and Spire plaza
##
## Nothing here names a real brand: every graphic comes from `HoloGraphics`, which draws blocky stroke
## glyphs from a seeded RNG (ART.md §4 "fictional Chinese/English brands").

const DETAIL_END := 450.0          ## props are detail; matches city-build's detail chunks
const BILLBOARD_RANGE := 1600.0    ## a billboard is a landmark, so it outlives the detail chunks

## Blade signs: which tiers get one, how many per building and how tall the strip runs.
const BLADE_TIERS: Array[String] = ["B", "C", "D"]
const BLADE_PER_TOWER := 2
const BLADE_W := 1.9
const BLADE_H_MIN := 7.0
const BLADE_H_MAX := 17.0
const BLADE_OUT := 1.2             ## metres the blade stands off the wall
const BLADE_TINTS: Array[Color] = [ArtPalette.NEON_CYAN, ArtPalette.NEON_MAGENTA,
	ArtPalette.NEON_AMBER, ArtPalette.NEON_JADE]

## Shopfront glow: a warm band at the base of a podium, on the side that faces its street.
const SHOP_Y := 4.4
const SHOP_H := 1.6

## Parapet light lines on tier C/D roofs.
const PARAPET_TIERS: Array[String] = ["C", "D"]
const PARAPET_MIN_HEIGHT := 80.0
const PARAPET_W := 0.6

## Holo billboards: 8 of them, 26 x 13 m, on the tallest facade near each anchor point.
const BILLBOARD_W := 26.0
const BILLBOARD_H := 13.0
const BILLBOARD_ANCHORS: Array[Vector2] = [
	Vector2(0.0, 120.0),      # the Spire plaza (A3)
	Vector2(-60.0, -450.0),   # Sky Garden (A6)
	Vector2(-470.0, -40.0),   # Interchange Knot (A2)
	Vector2(460.0, 420.0),    # Megablock Canyon (A4)
	Vector2(470.0, -210.0),   # Foundry Decks (A5)
	Vector2(-449.0, -410.0),  # Container Yard (A1)
	Vector2(-520.0, 430.0),   # the pagoda, Old Town
	Vector2(-250.0, 60.0),    # the canal crossing
]

var blades: int = 0
var shopfronts: int = 0
var parapets: int = 0
var billboards: int = 0

## The four wall normals of an axis-aligned footprint, in building-local space.
const AXES: Array[Vector2] = [Vector2(0.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, -1.0), Vector2(-1.0, 0.0)]

var _rng := RandomNumberGenerator.new()


## Builds every piece from the design layout's buildings. Returns the total instances placed.
func build(design: Dictionary, seed: int = 20261101) -> int:
	_rng.seed = seed
	var buildings: Array = design.get("buildings", [])
	if buildings.is_empty():
		push_warning("FacadeSigns: no buildings in the design layout — no signage placed")
		return 0
	blades = _blade_signs(buildings)
	shopfronts = _shopfronts(buildings)
	parapets = _parapets(buildings)
	billboards = _billboards(buildings)
	return blades + shopfronts + parapets + billboards


## Vertical neon blade signs. A blade projects PERPENDICULAR from the wall, so you read it edge-on from
## the front and full-face walking past — its quad's normal is the wall's tangent, not the wall's
## normal. One MultiMesh per tint keeps the whole layer at four draw calls.
func _blade_signs(buildings: Array) -> int:
	var by_tint: Array = []
	for i in BLADE_TINTS.size():
		by_tint.append([] as Array[Transform3D])
	for b in buildings:
		var tier := String(b.get("tier", "B"))
		var height := float(b.get("height", 0.0))
		if not BLADE_TIERS.has(tier) or height < 20.0:
			continue
		var count := BLADE_PER_TOWER if tier != "B" else 1
		for i in range(count):
			var tint := _rng.randi_range(0, BLADE_TINTS.size() - 1)
			(by_tint[tint] as Array).append(_blade_xform(b, height))
	var total := 0
	for i in BLADE_TINTS.size():
		var rows: Array = by_tint[i]
		if rows.is_empty():
			continue
		_multimesh("blade_%d" % i, _quad_mesh(BLADE_W, 1.0),
			McMaterials.sign_material(HoloGraphics.shop_sign(400 + i * 37, BLADE_TINTS[i]),
				BLADE_TINTS[i]), rows, DETAIL_END)
		total += rows.size()
	return total


## One blade: pinned to one of the four walls, standing off it and turned to face along the wall.
func _blade_xform(b: Dictionary, height: float) -> Transform3D:
	var size: Array = b.get("size", [20.0, 20.0])
	var half := Vector2(float(size[0]) * 0.5, float(size[1]) * 0.5)
	var rot := deg_to_rad(-float(b.get("rot", 0.0)))
	var centre := _centre(b)
	var base := float(b.get("base_z", 0.0))
	var h := _rng.randf_range(BLADE_H_MIN, minf(BLADE_H_MAX, height * 0.55))
	var y := base + _rng.randf_range(8.0, maxf(9.0, height - h - 4.0))

	var outward := AXES[_rng.randi_range(0, AXES.size() - 1)]
	var along := Vector2(-outward.y, outward.x)
	var reach := half.y if absf(outward.y) > 0.5 else half.x
	var span := half.x if absf(outward.y) > 0.5 else half.y
	var local := outward * (reach + BLADE_OUT) + along * _rng.randf_range(-0.3, 0.3) * span
	var world := local.rotated(rot) + centre
	var face := along.rotated(rot)
	var basis := Basis(Vector3.UP, atan2(face.x, face.y)).scaled(Vector3(1.0, h, 1.0))
	return Transform3D(basis, Vector3(world.x, y + h * 0.5, world.y))


## Shopfront glow: a warm band at L1 on the two street-facing walls of every podium. It is the layer
## that makes a canyon floor read as a street rather than a corridor — the key art's Old Town and
## canyon both have a continuous warm line at the base of the buildings.
func _shopfronts(buildings: Array) -> int:
	var rows: Array = [] as Array[Transform3D]
	for b in buildings:
		var size: Array = b.get("size", [20.0, 20.0])
		if float(b.get("height", 0.0)) < 8.0:
			continue
		var half := Vector2(float(size[0]) * 0.5, float(size[1]) * 0.5)
		var rot := deg_to_rad(-float(b.get("rot", 0.0)))
		var centre := _centre(b)
		var base := float(b.get("base_z", 0.0))
		# The two longer walls of the footprint are the ones that front a street.
		var long_is_x := half.x >= half.y
		var axes: Array[Vector2] = []
		if long_is_x:
			axes.append(AXES[0])
			axes.append(AXES[2])
		else:
			axes.append(AXES[1])
			axes.append(AXES[3])
		var span := half.x if long_is_x else half.y
		for axis in axes:
			var outward: Vector2 = axis
			var reach := half.y if absf(outward.y) > 0.5 else half.x
			var world := (outward * (reach + 0.25)).rotated(rot) + centre
			var face := Vector2(-outward.y, outward.x).rotated(rot)
			var basis := Basis(Vector3.UP, atan2(face.x, face.y)) \
				.scaled_local(Vector3(span * 1.7, SHOP_H, 1.0))
			rows.append(Transform3D(basis, Vector3(world.x, base + SHOP_Y, world.y)))
	if rows.is_empty():
		return 0
	_multimesh("shopfront", _quad_mesh(1.0, 1.0),
		McMaterials.glow_band(ArtPalette.STREET_SODIUM, 1.25), rows, DETAIL_END)
	return rows.size()


## Parapet light lines: a thin emissive strip along the roof edge of the tier C/D towers, which is what
## separates a tower's silhouette from the sky in the key art's dusk shots.
func _parapets(buildings: Array) -> int:
	var rows: Array = [] as Array[Transform3D]
	for b in buildings:
		if not PARAPET_TIERS.has(String(b.get("tier", "B"))):
			continue
		var height := float(b.get("height", 0.0))
		if height < PARAPET_MIN_HEIGHT:
			continue
		var size: Array = b.get("size", [20.0, 20.0])
		var half := Vector2(float(size[0]) * 0.5, float(size[1]) * 0.5)
		var rot := deg_to_rad(-float(b.get("rot", 0.0)))
		var centre := _centre(b)
		var y := float(b.get("base_z", 0.0)) + height + 0.9
		for axis in AXES:
			var reach := half.y if absf(axis.y) > 0.5 else half.x
			var span := half.x if absf(axis.y) > 0.5 else half.y
			var world := (axis * reach).rotated(rot) + centre
			var along := Vector2(-axis.y, axis.x).rotated(rot)
			var basis := Basis(Vector3.UP, atan2(along.x, along.y)) \
				.scaled_local(Vector3(span * 2.0, PARAPET_W, 1.0))
			rows.append(Transform3D(basis, Vector3(world.x, y, world.y)))
	if rows.is_empty():
		return 0
	_multimesh("parapet", _quad_mesh(1.0, 1.0),
		McMaterials.glow_band(ArtPalette.NEON_CYAN, 0.85), rows, 1800.0)
	return rows.size()


## Large holo billboards (ART.md §4: 6-10, fictional brands). One per anchor point, mounted on the
## tallest facade within 260 m of it and turned to face the anchor — so the player meets them walking in.
func _billboards(buildings: Array) -> int:
	var placed := 0
	for anchor in BILLBOARD_ANCHORS:
		var best: Dictionary = {}
		var best_score := -INF
		for b in buildings:
			var height := float(b.get("height", 0.0))
			var d := _centre(b).distance_to(anchor)
			if height < 40.0 or d > 260.0:
				continue
			var score := height - d * 0.35
			if score > best_score:
				best_score = score
				best = b
		if best.is_empty():
			continue
		_billboard_at(best, anchor)
		placed += 1
	if placed < BILLBOARD_ANCHORS.size():
		push_warning("FacadeSigns: only %d of %d billboards found a facade"
			% [placed, BILLBOARD_ANCHORS.size()])
	return placed


func _billboard_at(b: Dictionary, anchor: Vector2) -> void:
	var size: Array = b.get("size", [20.0, 20.0])
	var half := Vector2(float(size[0]) * 0.5, float(size[1]) * 0.5)
	var rot := deg_to_rad(-float(b.get("rot", 0.0)))
	var centre := _centre(b)
	# Face the wall whose outward normal points most toward the anchor.
	var to_anchor := (anchor - centre).normalized()
	var outward := Vector2.UP
	var best_dot := -INF
	for axis in AXES:
		var d := axis.rotated(rot).dot(to_anchor)
		if d > best_dot:
			best_dot = d
			outward = axis
	var reach := half.y if absf(outward.y) > 0.5 else half.x
	var world := (outward * (reach + 1.0)).rotated(rot) + centre
	var y := float(b.get("base_z", 0.0)) + float(b.get("height", 0.0)) * 0.62
	var node := MeshInstance3D.new()
	node.name = "holo_billboard"
	node.mesh = _quad_mesh(BILLBOARD_W, BILLBOARD_H)
	node.material_override = McMaterials.hologram(ArtPalette.NEON_MAGENTA,
		HoloGraphics.billboard(9100 + int(anchor.x) % 977, ArtPalette.NEON_CYAN))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = BILLBOARD_RANGE
	node.position = Vector3(world.x, y, world.y)
	node.rotation.y = atan2(outward.rotated(rot).x, outward.rotated(rot).y)
	add_child(node)


## Blender XY -> Godot XZ (Y mirrors), as PropPlacer.to_godot does.
static func _centre(b: Dictionary) -> Vector2:
	var c: Array = b.get("center", [0.0, 0.0])
	return Vector2(float(c[0]), -float(c[1]))


func _quad_mesh(w: float, h: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	return q


## One MultiMeshInstance3D for a whole batch (godot-tech §4.4: a MultiMesh spread over the whole map is
## never culled, so batches this large are split by the caller's visibility range instead).
func _multimesh(label: String, mesh: Mesh, mat: Material, rows: Array, range_m: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = rows.size()
	for i in range(rows.size()):
		mm.set_instance_transform(i, rows[i])
	var node := MultiMeshInstance3D.new()
	node.name = "sign_" + label
	node.multimesh = mm
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = range_m
	node.visibility_range_end_margin = 60.0
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	add_child(node)
