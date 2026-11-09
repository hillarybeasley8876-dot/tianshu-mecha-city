class_name ClothLines
extends MultiMeshInstance3D
## Hanging banners, laundry and awnings (city-art, brief 5). One MultiMesh of quads driven by the
## mc_cloth vertex wave; per-instance seed comes from the instance index so no two cloths match.

const SHADER := preload("res://world/art/shaders/mc_cloth.gdshader")
var _mat: ShaderMaterial


## `items` are [position, yaw_deg, width, height] rows: the top edge of the cloth sits at `position`.
func build(items: Array) -> void:
	if items.is_empty():
		multimesh = null
		return
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _cloth_quad(float(items[0][2]), float(items[0][3]))
	mm.instance_count = items.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	for i in range(items.size()):
		var row: Array = items[i]
		var w := float(row[2])
		var h := float(row[3])
		var basis := Basis(Vector3.UP, deg_to_rad(float(row[1])))
		# The shared quad is sized from the first item; scale the rest to match their own size.
		var sx := w / maxf(float(items[0][2]), 0.01)
		var sy := h / maxf(float(items[0][3]), 0.01)
		basis = basis * Basis.from_scale(Vector3(sx, sy, 1.0))
		mm.set_instance_transform(i, Transform3D(basis, row[0]))
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), 1.0))
	multimesh = mm
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_range_end = 420.0
	visibility_range_end_margin = 30.0


## A quad whose origin is at the TOP edge centre, with UV.y = 1 at the top (the hung edge).
func _cloth_quad(w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [
		[Vector3(-w * 0.5, 0.0, 0.0), Vector2(0.0, 0.0)],
		[Vector3(w * 0.5, 0.0, 0.0), Vector2(1.0, 0.0)],
		[Vector3(w * 0.5, -h, 0.0), Vector2(1.0, 1.0)],
		[Vector3(-w * 0.5, -h, 0.0), Vector2(0.0, 1.0)],
	]
	for tri in [[0, 1, 2], [0, 2, 3]]:
		for i in tri:
			st.set_normal(Vector3.BACK)
			st.set_uv(corners[i][1])
			st.add_vertex(corners[i][0])
	return st.commit()
