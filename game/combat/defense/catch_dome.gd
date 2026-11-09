class_name CatchDome
extends Node3D
## The catch field's surface (r7). `CatchField` is the logic — it freezes the shots and orbits them;
## this is what the player sees while it does: a translucent frontal hemisphere in the Mirror Guard's
## own language, thin enough that the rounds spinning inside it are the read.
##
## It is deliberately NOT a copy of the block panel: it is a dome rather than a cap, it is thinner
## (`MirrorShieldProfile.DOME_CORE_ALPHA`), its cells are smaller, and they TURN — so a held guard
## reads as the field opening rather than as a second shield.
##
## The mesh is built as a polar grid rather than a `SphereMesh` because the shader's rim term works
## off `length(UV * 2 - 1)`: on this grid that is the polar angle from the dome's axis, 0 straight
## ahead and 1 on the rim, so the rim glows without a second shader.

const RINGS := 8
const SEGMENTS := 32

var active: bool = false

var _mesh_instance: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _fade: float = 0.0
var _spin: float = 0.0


func _ready() -> void:
	top_level = true
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Dome"
	_mesh_instance.mesh = _dome()
	_mat = MirrorShieldProfile.dome_material()
	_mesh_instance.material_override = _mat
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.visible = false
	add_child(_mesh_instance)


## A hemisphere whose axis is local -Z (the same convention as the block panel, so both are placed
## with `Basis.looking_at`). `theta` runs 0 at the pole to PI/2 on the rim.
func _dome() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in RINGS:
		var t0 := float(ring) / float(RINGS)
		var t1 := float(ring + 1) / float(RINGS)
		for s in SEGMENTS:
			var a0 := TAU * float(s) / float(SEGMENTS)
			var a1 := TAU * float(s + 1) / float(SEGMENTS)
			if ring == 0:
				_point(st, 0.0, 0.0)
				_point(st, a0, t1)
				_point(st, a1, t1)
				continue
			_point(st, a0, t0)
			_point(st, a0, t1)
			_point(st, a1, t1)
			_point(st, a0, t0)
			_point(st, a1, t1)
			_point(st, a1, t0)
	return st.commit()


func _point(st: SurfaceTool, phi: float, t: float) -> void:
	var theta := t * PI * 0.5
	var n := Vector3(sin(theta) * cos(phi), sin(theta) * sin(phi), -cos(theta))
	st.set_normal(n)
	st.set_uv(Vector2(n.x, n.y) * 0.5 + Vector2(0.5, 0.5))
	st.set_color(Color.WHITE)
	st.add_vertex(n * DefenseTable.CATCH_RADIUS)


## Opening and closing the field runs the same fade envelope as the block shield.
func set_active(on: bool) -> void:
	active = on


## The dome is centred on the mech at the height the caught rounds orbit at, and faces the guard
## direction — the same hemisphere `CatchField._in_front` tests against.
func place(centre: Vector3, facing: Basis) -> void:
	if not active and _fade <= 0.0:
		return
	var n := -facing.z
	if n.length_squared() < 0.0001:
		return
	_mesh_instance.global_transform = Transform3D(Basis.looking_at(n, Vector3.UP), centre)


func tick(delta: float) -> void:
	_fade = MirrorShieldProfile.fade_step(_fade, active, delta)
	_spin = fmod(_spin + MirrorShieldProfile.DOME_SPIN * delta, TAU)
	if _mat != null:
		_mat.set_shader_parameter(&"fade", _fade)
		_mat.set_shader_parameter(&"hex_spin", _spin)
	if _mesh_instance != null:
		_mesh_instance.visible = _fade > 0.0


## Read by `DefenseVisualSuite`.
func fade() -> float:
	return _fade


func spin() -> float:
	return _spin


func material() -> ShaderMaterial:
	return _mat


func is_showing() -> bool:
	return _mesh_instance != null and _mesh_instance.visible


## The dome's real radius, measured off the built mesh.
func radius() -> float:
	if _mesh_instance == null or _mesh_instance.mesh == null:
		return 0.0
	return _mesh_instance.mesh.get_aabb().size.z


func clear() -> void:
	active = false
	_fade = 0.0
	if _mesh_instance != null:
		_mesh_instance.visible = false
