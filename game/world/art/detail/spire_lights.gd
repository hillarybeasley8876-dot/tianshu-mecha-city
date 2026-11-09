class_name SpireLights
extends Node3D
## The Spire's light language (ART.md §1, review r2): accent strips running up the shaft, glowing ring
## edges at the collar / roof ring / crown deck, so the tower reads as the city's beacon from V1.
## The strips are attached to the REAL surface: one ray per azimuth per height, cast inward from
## outside, gives the radius city-build actually built — a guessed profile would bury half of them.
## Cost: one MultiMesh for the strips plus one MeshInstance3D per ring, all unshaded and shadow-free.

const AZIMUTHS := 8                ## strips around the shaft
const HEIGHTS: Array[float] = [18.0, 62.0, 108.0, 152.0, 196.0, 240.0, 284.0, 326.0]
const RING_HEIGHTS: Array[float] = [80.0, 160.0, 224.0]
const STRIP_W := 1.1               ## metres across the strip
const STRIP_D := 0.5               ## metres proud of the surface
const RAY_START := 260.0           ## metres out from the axis where the probe ray begins
const STRIP_GAIN := 1.0   ## r14: 2.2 clipped the shaft to white at every distance; r16b: 1.4 still peaked at 5.1 linear (see mc_up_accent)
const RING_GAIN := 1.1    ## r14: with the strips

var strips: int = 0
var rings: int = 0


## Builds the whole set. `centre` is the Spire axis in Godot space, `height` its full height.
func build(centre: Vector3, height: float) -> int:
	await get_tree().physics_frame
	var state := get_world_3d().direct_space_state
	var scale_h := height / 360.0
	var pts := _probe(state, centre, scale_h)
	_rings(centre, pts, scale_h)
	_strip_mesh(centre, pts)
	return strips + rings


## pts[azimuth][height_index] = the surface point the inward ray hit (Vector3.ZERO when it hit nothing).
func _probe(state: PhysicsDirectSpaceState3D, centre: Vector3, scale_h: float) -> Array:
	var pts: Array = []
	for a in range(AZIMUTHS):
		var ang := TAU * float(a) / float(AZIMUTHS)
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var column: Array[Vector3] = []
		for h in HEIGHTS:
			var y := h * scale_h
			var from := centre + out * RAY_START + Vector3.UP * y
			var to := centre + out * 4.0 + Vector3.UP * y
			var q := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD)
			q.collide_with_areas = false
			var hit := state.intersect_ray(q)
			column.append(hit.get("position", Vector3.ZERO) as Vector3)
		pts.append(column)
	return pts


## Ring edges: a thin glowing band at each deck line, at the mean radius the probe found there.
func _rings(centre: Vector3, pts: Array, scale_h: float) -> void:
	var mat := McMaterials.accent_variant(&"spire_ring", RING_GAIN, 0.85, 0.25, 1)
	for h in RING_HEIGHTS:
		var idx := _nearest_height(h)
		var r := _mean_radius(pts, idx, centre)
		if r < 4.0:
			continue
		var torus := TorusMesh.new()
		torus.inner_radius = maxf(r - 0.8, 0.5)
		torus.outer_radius = r + 0.8
		torus.rings = 48
		torus.ring_segments = 6
		var node := MeshInstance3D.new()
		node.name = "SpireRing_%d" % int(h)
		node.mesh = torus
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = centre + Vector3.UP * (h * scale_h)
		add_child(node)
		rings += 1


## Vertical strips: one box per height segment per azimuth, following the probed surface points.
func _strip_mesh(centre: Vector3, pts: Array) -> void:
	var xforms: Array[Transform3D] = []
	for a in range(pts.size()):
		var column: Array = pts[a]
		for i in range(column.size() - 1):
			var p0: Vector3 = column[i]
			var p1: Vector3 = column[i + 1]
			if p0 == Vector3.ZERO or p1 == Vector3.ZERO:
				continue
			var seg := p1 - p0
			if seg.length() < 2.0:
				continue
			var out := (p0 - centre)
			out.y = 0.0
			if out.length() < 0.5:
				continue
			var basis := _basis(seg.normalized(), out.normalized())
			var mid := (p0 + p1) * 0.5 + out.normalized() * (STRIP_D * 0.5)
			xforms.append(Transform3D(basis.scaled_local(Vector3(STRIP_W, seg.length(), STRIP_D)), mid))
	if xforms.is_empty():
		push_warning("SpireLights: no Spire surface found — the shaft has no collider at %s" % centre)
		return
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = xforms.size()
	var bounds := AABB(xforms[0].origin, Vector3.ZERO)
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
		bounds = bounds.expand(xforms[i].origin)
	var node := MultiMeshInstance3D.new()
	node.name = "SpireStrips"
	node.multimesh = mm
	node.material_override = McMaterials.accent_variant(&"spire_strip", STRIP_GAIN, 0.45, 1.8, 1)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A MultiMesh's own AABB is empty until the renderer has seen it, and an empty AABB is culled: the
	# strips were built and then never drawn. Give the node the bounds of the instances it holds.
	bounds = bounds.grow(8.0)
	node.custom_aabb = bounds
	add_child(node)
	strips = xforms.size()


## Y along the segment, Z outward from the shaft — a strip is a flat ribbon standing on the surface.
func _basis(up: Vector3, out: Vector3) -> Basis:
	var z := (out - up * out.dot(up)).normalized()
	if not z.is_finite() or z.length_squared() < 1e-6:
		z = Vector3.FORWARD
	var x := up.cross(z).normalized()
	return Basis(x, up, z)


func _nearest_height(h: float) -> int:
	var best := 0
	for i in range(HEIGHTS.size()):
		if absf(HEIGHTS[i] - h) < absf(HEIGHTS[best] - h):
			best = i
	return best


func _mean_radius(pts: Array, idx: int, centre: Vector3) -> float:
	var total := 0.0
	var n := 0
	for column in pts:
		var p: Vector3 = (column as Array)[idx]
		if p == Vector3.ZERO:
			continue
		total += Vector2(p.x - centre.x, p.z - centre.z).length()
		n += 1
	return total / float(n) if n > 0 else 0.0
