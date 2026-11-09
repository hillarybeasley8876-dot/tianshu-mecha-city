class_name Scaffolds
extends Node3D
## Two construction sites (city-art, lead r4 §1). A tower half-clad in scaffold is the single most
## legible "this city is alive and being built" read there is, and it breaks a box silhouette with a
## fine lattice from the roofline all the way down — exactly the high-frequency structure the key art
## has on every mid-ground block and the blockout does not.
##
## One ArrayMesh per site, steel material, no shadows: the lattice is 40-60 mm tube at 60-120 m.

const SITES := 2
const LIFT_M := 2.6              ## scaffold storey height (a real frame is ~2 m; 2.6 reads at range)
const BAY_M := 2.4               ## horizontal bay
const TUBE := 0.16
const CLAD_FROM := 0.55          ## the finished cladding starts this far up the tower
const VISIBILITY_M := 900.0

var sites: int = 0


## Picks the tallest wide towers that are not already landmarks and wraps one facade of each.
func build(design: Dictionary, seed: int = 20261102) -> int:
	var pool: Array = []
	for b in design.get("buildings", []):
		var row := b as Dictionary
		var size: Array = row.get("size", [0.0, 0.0])
		if float(row.get("height", 0.0)) < 40.0 or float(size[0]) < 16.0 or float(size[1]) < 16.0:
			continue
		if String(row.get("tier", "B")) == "A":
			continue
		pool.append(row)
	if pool.is_empty():
		return 0
	# Deterministic: tallest first, ties broken by id, so two runs pick the same two towers.
	pool.sort_custom(func(a: Dictionary, c: Dictionary) -> bool:
		var ha := float(a.get("height", 0.0))
		var hc := float(c.get("height", 0.0))
		return ha > hc if not is_equal_approx(ha, hc) else String(a.get("id", "")) < String(c.get("id", "")))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in range(mini(SITES, pool.size())):
		var row: Dictionary = pool[i * 3]
		if _site(row, i, rng):
			sites += 1
	return sites


## One facade: vertical standards on a bay grid, ledgers every lift, and a boarded deck every fourth.
func _site(row: Dictionary, index: int, rng: RandomNumberGenerator) -> bool:
	var size: Array = row.get("size", [20.0, 20.0])
	var centre: Array = row.get("center", [0.0, 0.0])
	var half := Vector2(float(size[0]) * 0.5, float(size[1]) * 0.5)
	var base_z := float(row.get("base_z", 0.0))
	var height := float(row.get("height", 40.0))
	var rot := -deg_to_rad(float(row.get("rot", 0.0)))
	var org := Vector3(float(centre[0]), 0.0, -float(centre[1]))
	# The face on the -Z side of the footprint, in building-local space, before the block rotation.
	var width := half.x * 2.0
	var bays := maxi(int(width / BAY_M), 2)
	var lifts := maxi(int(height * (1.0 - CLAD_FROM) / LIFT_M), 3)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in range(bays + 1):
		var x := -half.x + width * float(b) / float(bays)
		McMeshKit.box(st, Vector3(x, height * 0.5, -half.y - 0.9),
			Vector3(TUBE, height, TUBE))
	for l in range(lifts + 1):
		var y := height * CLAD_FROM + float(l) * LIFT_M
		McMeshKit.box(st, Vector3(0.0, y, -half.y - 0.9), Vector3(width, TUBE, TUBE))
		McMeshKit.box(st, Vector3(0.0, y, -half.y - 1.9), Vector3(width, TUBE, TUBE))
		if l % 4 == 0:
			McMeshKit.box(st, Vector3(0.0, y - 0.2, -half.y - 1.4), Vector3(width, 0.14, 1.1))
	for b in range(bays):
		if rng.randf() > 0.5:
			continue
		var x := -half.x + width * (float(b) + 0.5) / float(bays)
		McMeshKit.box(st, Vector3(x, height * CLAD_FROM + 1.4, -half.y - 1.4),
			Vector3(width / float(bays) * 0.8, 1.2, TUBE))
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	var node := MeshInstance3D.new()
	node.name = "Scaffold%d" % index
	node.mesh = mesh
	node.transform = Transform3D(Basis(Vector3.UP, rot), Vector3(org.x, base_z, org.z))
	node.material_override = McMaterials.get_material(&"mc_metal")
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = VISIBILITY_M
	node.visibility_range_end_margin = 60.0
	add_child(node)
	return true
