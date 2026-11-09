class_name SkillFxArcs
extends SkillFxPiece
## Radial lightning arcs: the Shockcore Burst's discharge crawling out along the ground plane and up
## into the air. One ImmediateMesh per instance holds every arc as a flat ribbon, rebuilt a few times
## per second so the bolts crawl instead of sitting still.

const SEGMENTS := 7
const RESHUFFLE := 0.045

var _mesh: MeshInstance3D = null
var _geo: ImmediateMesh = null
var _radius: float = 32.0
var _count: int = 8
var _width: float = 0.7
var _color: Color = Color(0.75, 0.98, 1.0)
var _arcs: Array[PackedVector3Array] = []
var _next_shuffle: float = 0.0


func _ready() -> void:
	super()
	_mesh = MeshInstance3D.new()
	_mesh.name = "Arcs"
	_geo = ImmediateMesh.new()
	_mesh.mesh = _geo
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.extra_cull_margin = 128.0
	add_child(_mesh)


func fire(at: Vector3, radius: float, count: int, seconds: float, color: Color,
		width: float = 0.7) -> void:
	global_position = at
	global_basis = Basis.IDENTITY
	_radius = radius
	_count = clampi(count, 1, 16)
	_width = width
	_color = color
	_next_shuffle = 0.0
	_reshuffle()
	_begin(seconds)


func _advance(delta: float) -> void:
	_next_shuffle -= delta
	if _next_shuffle <= 0.0:
		_next_shuffle = RESHUFFLE
		_reshuffle()
	_rebuild()


## New jagged paths out of the centre: a random azimuth, a random elevation and a per-vertex jitter.
func _reshuffle() -> void:
	_arcs.clear()
	for i in _count:
		var az := TAU * float(i) / float(_count) + randf_range(-0.25, 0.25)
		var elev := randf_range(-0.12, 0.55)
		var dir := Vector3(cos(az), elev, sin(az)).normalized()
		var side := dir.cross(Vector3.UP).normalized()
		if side.length_squared() < 0.01:
			side = Vector3.RIGHT
		var pts := PackedVector3Array()
		var reach := _radius * randf_range(0.55, 1.0)
		for s in SEGMENTS + 1:
			var u := float(s) / float(SEGMENTS)
			var jitter := side * randf_range(-1.0, 1.0) * _radius * 0.09 * u
			jitter += Vector3.UP * randf_range(-1.0, 1.0) * _radius * 0.05 * u
			pts.append(dir * reach * u + jitter)
		_arcs.append(pts)


func _rebuild() -> void:
	var fade := 1.0 - progress()
	_geo.clear_surfaces()
	if fade <= 0.02:
		return
	_geo.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for pts: PackedVector3Array in _arcs:
		for s in pts.size() - 1:
			var a := pts[s]
			var b := pts[s + 1]
			var side := (b - a).cross(Vector3.UP)
			if side.length_squared() < 0.001:
				side = Vector3.RIGHT
			side = side.normalized() * _width * (1.0 - float(s) / float(pts.size()))
			var alpha := fade * (1.0 - 0.55 * float(s) / float(pts.size()))
			_tri(a - side, a + side, b + side, alpha)
			_tri(a - side, b + side, b - side, alpha)
	_geo.surface_end()


func _tri(a: Vector3, b: Vector3, c: Vector3, alpha: float) -> void:
	for p: Vector3 in [a, b, c]:
		_geo.surface_set_color(Color(_color.r, _color.g, _color.b, alpha))
		_geo.surface_add_vertex(p)
