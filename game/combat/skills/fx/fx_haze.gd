class_name SkillFxHaze
extends SkillFxPiece
## Heat distortion sleeve around a beam or a column: a transparent volume that re-reads the screen
## behind it with a scrolling warp. The Zenith Lance runs one over its whole 800 m so the air over the
## beam boils, and the Plunge column reuses the same shader.

const SHADER := preload("res://combat/skills/fx/shaders/heat_haze.gdshader")
const OPEN_LIFE := 3600.0

var _mesh: MeshInstance3D = null


func _ready() -> void:
	super()
	_mesh = MeshInstance3D.new()
	_mesh.name = "Haze"
	var tube := CylinderMesh.new()
	tube.top_radius = 0.5
	tube.bottom_radius = 0.5
	tube.height = 1.0
	tube.radial_segments = 12
	tube.rings = 1
	# NO caps: a beam is an open tube. With the caps drawn, the near end of the 16 m Lance
	# layer filled a sixth of the screen with a flat pink disc that read as a ball at the
	# muzzle instead of a beam leaving it (r4 item 3).
	tube.cap_top = false
	tube.cap_bottom = false
	_mesh.mesh = tube
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.render_priority = 4
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.extra_cull_margin = 512.0
	add_child(_mesh)


func open(strength: float = 0.4, scale: float = 8.0, speed: float = 1.6) -> void:
	var mat := _mesh.material_override as ShaderMaterial
	mat.set_shader_parameter(&"strength", strength)
	mat.set_shader_parameter(&"scale", scale)
	mat.set_shader_parameter(&"speed", speed)
	_begin(OPEN_LIFE)


## The tube's local +Y is its axis, so `SkillFx.tube_basis` puts that column along the beam. It used to
## hang under a quarter-turned pivot whose `global_transform` this call overwrote every frame, which
## laid the sleeve across the lance as a flat sheet (r4 item 3).
func line(from: Vector3, to: Vector3, width: float) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.01:
		_mesh.visible = false
		return
	_mesh.visible = true
	var dir := delta / length
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	_mesh.global_transform = Transform3D(SkillFx.tube_basis(dir, up, width, length),
			(from + to) * 0.5)
