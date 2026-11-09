class_name StreetKit
extends RefCounted
## Mesh helpers for the city-art look-dev street (world/art/tests). The real city geometry comes from
## city-build; this only needs to reproduce the conventions the art shaders depend on:
## metre UVs on window bands and road slabs, and ≤ 60 m chunks so shadows land in one PSSM split.

const FLOOR := 4.0            ## ART.md §4 facade module
const WIN_W := 3.2
const WIN_H := 2.6
const WIN_OUT := 0.15         ## window bands stand proud of the wall, like city-build's kit


## A box with world-triplanar materials; kept ≤ 60 m in plan for the shadow splits.
static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## Horizontal slab (road, deck, canal) at y = 0 with UVs in METRES, origin at the slab centre.
static func slab(size: Vector2, origin: Vector3 = Vector3.ZERO) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var corners := [
		[Vector3(-hx, 0.0, hz), Vector2(0.0, size.y)],
		[Vector3(hx, 0.0, hz), Vector2(size.x, size.y)],
		[Vector3(hx, 0.0, -hz), Vector2(size.x, 0.0)],
		[Vector3(-hx, 0.0, -hz), Vector2(0.0, 0.0)],
	]
	for tri in [[0, 2, 1], [0, 3, 2]]:
		for i in tri:
			st.set_normal(Vector3.UP)
			st.set_uv(corners[i][1])
			st.add_vertex(corners[i][0] + origin)
	return st.commit()


## Vertical wall quad whose visible side faces `facing`, UVs in metres from its lower-left corner.
## Godot's front face is clockwise seen from the front, so the winding here is the mirror of `slab`'s.
static func wall(size: Vector2, origin: Vector3, facing: Vector3 = Vector3.BACK) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var basis := Basis.looking_at(facing, Vector3.UP)
	var corners := [
		[Vector3(0.0, 0.0, 0.0), Vector2(0.0, 0.0)],
		[Vector3(size.x, 0.0, 0.0), Vector2(size.x, 0.0)],
		[Vector3(size.x, size.y, 0.0), Vector2(size.x, size.y)],
		[Vector3(0.0, size.y, 0.0), Vector2(0.0, size.y)],
	]
	for tri in [[0, 1, 2], [0, 2, 3]]:
		for i in tri:
			st.set_normal(basis * Vector3.FORWARD)
			st.set_uv(corners[i][1])
			st.add_vertex(origin + basis * corners[i][0])
	return st.commit()


## Every window band on one tower: a quad per floor per facade, standing WIN_OUT proud of the wall.
## `size` is the tower footprint (x, z) and height (y); returns one mesh in tower-local space with
## the base at y = 0, which is exactly the metre-UV layout the mc_window shader expects.
static func windows(size: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var floors := int(floor(size.y / FLOOR))
	var faces := [
		[Vector3(size.x * 0.5, 0.0, -size.z * 0.5 - WIN_OUT), Vector3.RIGHT, size.x],   # -Z
		[Vector3(size.x * 0.5 + WIN_OUT, 0.0, size.z * 0.5), Vector3.BACK, size.z],     # +X
		[Vector3(-size.x * 0.5, 0.0, size.z * 0.5 + WIN_OUT), Vector3.LEFT, size.z],    # +Z
		[Vector3(-size.x * 0.5 - WIN_OUT, 0.0, -size.z * 0.5), Vector3.FORWARD, size.x], # -X
	]
	for f in faces:
		var origin: Vector3 = f[0]
		var right: Vector3 = f[1]
		var span: float = f[2]
		var cols := int(floor(span / FLOOR))
		var pad := (span - float(cols) * FLOOR) * 0.5
		for row in range(1, floors):
			var y := float(row) * FLOOR
			for col in range(cols):
				var u0 := pad + float(col) * FLOOR + (FLOOR - WIN_W) * 0.5
				_quad(st, origin + right * u0 + Vector3.UP * y, right, WIN_W, WIN_H, u0, y)
	return st.commit()


static func _quad(st: SurfaceTool, origin: Vector3, right: Vector3, w: float, h: float,
		u0: float, v0: float) -> void:
	var n := right.cross(Vector3.UP).normalized() * -1.0
	var p := [
		[origin, Vector2(u0, v0)],
		[origin + right * w, Vector2(u0 + w, v0)],
		[origin + right * w + Vector3.UP * h, Vector2(u0 + w, v0 + h)],
		[origin + Vector3.UP * h, Vector2(u0, v0 + h)],
	]
	for tri in [[0, 1, 2], [0, 2, 3]]:
		for i in tri:
			st.set_normal(n)
			st.set_uv(p[i][1])
			st.add_vertex(p[i][0])


## One MultiMeshInstance3D holding every instance of a mesh/material pair (godot-tech §4.4: split
## MultiMeshes per region, never one for the whole map — the street is one region).
static func scatter(parent: Node3D, mesh: Mesh, mat: Material, xforms: Array[Transform3D],
		name: StringName = &"scatter") -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var node := MultiMeshInstance3D.new()
	node.name = String(name)
	node.multimesh = mm
	node.material_override = mat
	parent.add_child(node)
	return node
