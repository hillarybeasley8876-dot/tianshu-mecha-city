class_name StreetWeb
extends Node3D
## Cables, banner lines and laundry strung across the streets (city-art, brief 5 / lead r4 §1).
##
## The detail-energy gap the lead measured is not a texture problem: the key art is full of thin dark
## lines crossing the bright sky and the canyon walls — cable bundles, sky-bridges, washing lines —
## and a flat city has none. This hangs them off the real facades, so every span starts on a building
## the player can see rather than in mid-air.
##
## Two batches: one ArrayMesh of catenaries (CableNet) and one MultiMesh of cloth quads (ClothLines),
## so a district's whole web is two draw calls.

const SPACING_MIN := 24.0
const SPACING_MAX := 40.0
const REACH_M := 78.0            ## how far from the kerb line an anchor may be
const ATTACH_MIN := 11.0         ## metres above the street
const ATTACH_MAX := 52.0
const BUNDLE := 3                ## cables per crossing
## MAP.md §4: laundry and banners belong to the Old Town and the low quarters, not the civic core.
const CLOTH_DISTRICTS: Array[String] = ["D2", "D3", "D6"]
const CLOTH_EVERY := 3           ## one crossing in three carries washing
## Only the Old Town and the low quarters string lanterns.
const LANTERN_DISTRICTS: Array[String] = ["D3", "D2"]
const LANTERN_M := 0.62          ## lantern size

var spans: int = 0
var cloths: int = 0
var lanterns: int = 0
var _lantern_rows: Array[Transform3D] = []


## `design` is the design-time layout (streets + buildings). Returns the number of cable spans.
func build(design: Dictionary, seed: int = 20261102) -> int:
	var streets: Array = design.get("streets", [])
	var buildings: Array = design.get("buildings", [])
	if streets.is_empty() or buildings.is_empty():
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cable_rows: Array = []
	var cloth_rows: Array = []
	var crossings := 0
	for s in streets:
		crossings += _street(s as Dictionary, buildings, rng, cable_rows, cloth_rows)
	spans = cable_rows.size() / BUNDLE
	cloths = cloth_rows.size()
	lanterns = _lantern_rows.size()
	if not cable_rows.is_empty():
		var net := CableNet.new()
		net.name = "Cables"
		add_child(net)
		net.build(cable_rows)
	if not cloth_rows.is_empty():
		var lines := ClothLines.new()
		lines.name = "Banners"
		add_child(lines)
		lines.build(cloth_rows)
	_emit_lanterns()
	return spans


## One MultiMesh of crossed emissive quads, so a whole district's lanterns are a single draw call.
func _emit_lanterns() -> void:
	if _lantern_rows.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	McMeshKit.lamp(st, Vector3.ZERO, LANTERN_M)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = _lantern_rows.size()
	for i in range(_lantern_rows.size()):
		mm.set_instance_transform(i, _lantern_rows[i])
	var node := MultiMeshInstance3D.new()
	node.name = "Lanterns"
	node.multimesh = mm
	node.material_override = McMaterials.glow_band(ArtPalette.NEON_AMBER, 2.6)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = 500.0
	node.visibility_range_end_margin = 40.0
	add_child(node)


## Lanterns hung at intervals under the lowest cable of the crossing.
func _lanterns(a: Vector3, b: Vector3, rng: RandomNumberGenerator) -> void:
	var span := a.distance_to(b)
	var count := clampi(int(span / rng.randf_range(3.5, 6.0)), 3, 22)
	var sag := span * 0.07
	for i in range(count):
		var t := (float(i) + 0.5) / float(count)
		var at := a.lerp(b, t) - Vector3.UP * (sag * 4.0 * t * (1.0 - t) + 0.9)
		_lantern_rows.append(Transform3D(Basis(), at))


func _street(s: Dictionary, buildings: Array, rng: RandomNumberGenerator,
		cable_rows: Array, cloth_rows: Array) -> int:
	var z := float(s.get("z", 0.0))
	var made := 0
	var index := 0
	for step in PropPlacer.walk(s.get("points", []), rng.randf_range(SPACING_MIN, SPACING_MAX), rng):
		var p: Vector2 = step[0]
		var dir: Vector2 = step[1]
		var side := dir.orthogonal()
		var left := _anchor(p, side, buildings, z)
		var right := _anchor(p, -side, buildings, z)
		index += 1
		if left.is_empty() or right.is_empty():
			continue
		var a: Vector3 = left["pos"]
		var b: Vector3 = right["pos"]
		var span := a.distance_to(b)
		if span < 14.0 or span > 190.0:
			continue
		_bundle(cable_rows, a, b, side, rng)
		if index % CLOTH_EVERY == 0 and CLOTH_DISTRICTS.has(String(left["district"])):
			_washing(cloth_rows, a, b, rng)
		# MAP.md §4 / key art v3: the Old Town's crossings are strung with lanterns, and nothing else in
		# the city is — so they are what makes a D3 street read as D3 from 200 m away.
		if LANTERN_DISTRICTS.has(String(left["district"])):
			_lanterns(a, b, rng)
		made += 1
	return made


## A bundle of cables between the same two anchors: they sag by different amounts and are offset along
## the street, which is what makes a real span read as several wires instead of one clean line.
func _bundle(rows: Array, a: Vector3, b: Vector3, side: Vector2, rng: RandomNumberGenerator) -> void:
	var along := Vector3(side.x, 0.0, -side.y) * 1.6
	for i in range(BUNDLE):
		var drop := float(i) * rng.randf_range(1.1, 2.4)
		var off := along * rng.randf_range(-1.0, 1.0)
		var p0 := a + Vector3.UP * -drop + off
		var p1 := b + Vector3.UP * -drop * rng.randf_range(0.6, 1.3) - off
		rows.append([p0, p1, p0.distance_to(p1) * rng.randf_range(0.05, 0.11)])


## Washing hung under a line: quads whose top edge rides the catenary at a random point along it.
func _washing(rows: Array, a: Vector3, b: Vector3, rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(3, 6)
	# The cloth quad's local +X has to run ALONG the line: Basis(UP, t) maps (1,0,0) to (cos t, 0, -sin t).
	var yaw := rad_to_deg(atan2(-(b.z - a.z), b.x - a.x))
	for i in range(count):
		var t := (float(i) + rng.randf_range(0.2, 0.8)) / float(count)
		var sag := a.distance_to(b) * 0.09 * 4.0 * t * (1.0 - t)
		var at := a.lerp(b, t) - Vector3.UP * (sag + 0.4)
		rows.append([at, yaw, rng.randf_range(1.1, 2.2), rng.randf_range(1.4, 3.0)])


## The nearest facade on one side of the street, as {pos, district}. `p` is in Blender XY.
func _anchor(p: Vector2, side: Vector2, buildings: Array, z: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := REACH_M
	for b in buildings:
		var row := b as Dictionary
		var q := _rect_closest(row, p)
		var to := q - p
		var d := to.length()
		if d > best_d or d < 1e-3:
			continue
		if to.normalized().dot(side) < 0.45:
			continue
		best_d = d
		var height := float(row.get("height", 20.0))
		var attach := clampf(height * rng_free(row) * 0.62, ATTACH_MIN, ATTACH_MAX)
		best = {"pos": Vector3(q.x, z + float(row.get("base_z", 0.0)) + attach, -q.y),
			"district": String(row.get("district", "D4"))}
	return best


## A stable 0.35-1.0 per building, so two anchors on the same block do not tie.
static func rng_free(row: Dictionary) -> float:
	return 0.55 + 0.45 * float(abs(String(row.get("id", "")).hash()) % 97) / 97.0


## Closest point on a rotated footprint rectangle to `p`, in Blender XY.
static func _rect_closest(row: Dictionary, p: Vector2) -> Vector2:
	var centre: Array = row.get("center", [0.0, 0.0])
	var size: Array = row.get("size", [10.0, 10.0])
	var rot := deg_to_rad(float(row.get("rot", 0.0)))
	var half := Vector2(float(size[0]) * 0.5, float(size[1]) * 0.5)
	var d := p - Vector2(float(centre[0]), float(centre[1]))
	var c := cos(-rot)
	var s := sin(-rot)
	var local := Vector2(d.x * c - d.y * s, d.x * s + d.y * c)
	local.x = clampf(local.x, -half.x, half.x)
	local.y = clampf(local.y, -half.y, half.y)
	var back := Vector2(local.x * c + local.y * s, -local.x * s + local.y * c)
	return Vector2(float(centre[0]), float(centre[1])) + back
