class_name CableNet
extends MeshInstance3D
## Overhead cables strung between buildings (city-art, brief 5). One ArrayMesh holds every span as a
## thin extruded catenary, so a whole district's cabling is a single draw call. Cables are what make
## a canyon read as inhabited in the key art, and they cost almost nothing.

const SEGMENTS := 8
const RADIUS := 0.16
const SIDES := 3
const DEFAULT_SAG := 0.09        ## fraction of the span's length

var span_count: int = 0


## Builds the whole net from [from: Vector3, to: Vector3, sag: float] triples (sag optional).
func build(spans: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	span_count = 0
	for s in spans:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var sag := float(s[2]) if s.size() > 2 else a.distance_to(b) * DEFAULT_SAG
		_catenary(st, a, b, sag)
		span_count += 1
	if span_count == 0:
		mesh = null
		return
	mesh = st.commit()
	if material_override == null:
		material_override = _cable_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_range_end = 700.0
	visibility_range_end_margin = 40.0


func _catenary(st: SurfaceTool, a: Vector3, b: Vector3, sag: float) -> void:
	var along := (b - a).normalized()
	var side := along.cross(Vector3.UP)
	if side.length_squared() < 1e-5:
		side = Vector3.RIGHT
	side = side.normalized() * RADIUS
	var up := side.cross(along).normalized() * RADIUS
	var prev := PackedVector3Array()
	for i in range(SEGMENTS + 1):
		var t := float(i) / float(SEGMENTS)
		var p := a.lerp(b, t) - Vector3.UP * (sag * 4.0 * t * (1.0 - t))
		var ring := PackedVector3Array()
		for k in range(SIDES):
			var ang := TAU * float(k) / float(SIDES)
			ring.append(p + side * cos(ang) + up * sin(ang))
		if prev.size() == SIDES:
			for k in range(SIDES):
				var k2 := (k + 1) % SIDES
				_tri(st, prev[k], prev[k2], ring[k2])
				_tri(st, prev[k], ring[k2], ring[k])
		prev = ring


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_uv(Vector2(v.x * 0.2, v.y * 0.2))
		st.add_vertex(v)


func _cable_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = ArtPalette.linear(Color(0.09, 0.09, 0.10))
	m.roughness = 0.55
	m.metallic = 0.1
	return m
