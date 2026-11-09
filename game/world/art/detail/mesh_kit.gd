class_name McMeshKit
extends RefCounted
## The procedural primitives the dressing layers share (city-art). RoofGreebles and Scaffolds both
## build boxes and cylinders into a SurfaceTool, and two copies of a box builder is one too many.
## Every helper writes metre-scale UVs, so the city's PBR materials tile on a greeble exactly as they
## do on a wall.

## A unit cube's six faces as [normal, corner0..3], wound CCW seen from outside.
const CUBE_FACES: Array = [
	[Vector3(0, 0, 1), Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
	[Vector3(0, 0, -1), Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)],
	[Vector3(1, 0, 0), Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)],
	[Vector3(-1, 0, 0), Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)],
	[Vector3(0, 1, 0), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)],
	[Vector3(0, -1, 0), Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)],
]


## Axis-aligned box centred on `c` with full extents `s`.
static func box(st: SurfaceTool, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var uvs := [Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(0, s.y)]
	for f in CUBE_FACES:
		var n: Vector3 = f[0]
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for k in tri:
				st.set_normal(n)
				st.set_uv(uvs[k])
				st.add_vertex(c + (f[k + 1] as Vector3) * h)


## Vertical cylinder standing on `base`, capped at the top.
static func cyl(st: SurfaceTool, base: Vector3, r: float, h: float, sides: int) -> void:
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var p00 := base + d0 * r
		var p10 := base + d1 * r
		var p01 := p00 + Vector3.UP * h
		var p11 := p10 + Vector3.UP * h
		quad(st, p00, p10, p11, p01, (d0 + d1) * 0.5, h * float(i) / float(sides), h)
		tri(st, base + Vector3.UP * h, p01, p11, Vector3.UP)
		tri(st, base, p10, p00, Vector3.DOWN)


## A crossed pair of quads with 0..1 UVs, for a small emissive lamp: the band material's edge falloff
## then lands on the silhouette instead of on an arbitrary corner of a box.
static func lamp(st: SurfaceTool, at: Vector3, s: float) -> void:
	var h := s * 0.5
	quad(st, at + Vector3(-h, -h, 0), at + Vector3(h, -h, 0),
		at + Vector3(h, h, 0), at + Vector3(-h, h, 0), Vector3.BACK, 0.0, 1.0)
	quad(st, at + Vector3(0, -h, -h), at + Vector3(0, -h, h),
		at + Vector3(0, h, h), at + Vector3(0, h, -h), Vector3.RIGHT, 0.0, 1.0)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		n: Vector3, v0: float, v1: float) -> void:
	vertex(st, a, Vector2(0.0, v0), n)
	vertex(st, b, Vector2(1.0, v0), n)
	vertex(st, c, Vector2(1.0, v1), n)
	vertex(st, a, Vector2(0.0, v0), n)
	vertex(st, c, Vector2(1.0, v1), n)
	vertex(st, d, Vector2(0.0, v1), n)


static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	for v in [a, b, c]:
		vertex(st, v, Vector2(v.x + v.z, v.z - v.x), n)


static func vertex(st: SurfaceTool, v: Vector3, uv: Vector2, n: Vector3) -> void:
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(v)


## One MultiMeshInstance3D over `rows` of [Transform3D, Color] on a shared `mesh`. Every dressing
## layer batches this way: a MultiMeshInstance3D has only `material_override`, so two materials over
## the same transforms are two batches, not two surfaces. `use_colors` is on so a per-instance seed or
## district weight can ride in COLOR instead of costing another material.
static func multi(parent: Node3D, node_name: StringName, mesh: Mesh, rows: Array,
		mat: Material, vis_m: float = 0.0, shadows: bool = false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = rows.size()
	for i in range(rows.size()):
		var row: Array = rows[i] as Array
		mm.set_instance_transform(i, row[0] as Transform3D)
		mm.set_instance_color(i, row[1] as Color)
	var node := MultiMeshInstance3D.new()
	node.name = String(node_name)
	node.multimesh = mm
	node.material_override = mat
	if not shadows:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_m > 0.0:
		node.visibility_range_end = vis_m
		node.visibility_range_end_margin = 80.0
	parent.add_child(node)
	return node
