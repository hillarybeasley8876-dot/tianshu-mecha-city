class_name SkillFxBeam
extends SkillFxPiece
## A glowing tube between two points, redrawn every frame while it is open: the Skyhook cable
## (0.5 m emissive core + glow), the Corona Fin beams (0.6 m core / 2.5 m glow) and the three Zenith
## Lance layers all use it. `open()` keeps it alive until `close()`; `flash()` is the timed one-shot
## (a Rift Step transit streak, a fin trail).
##
## The mesh is a `CylinderMesh` built along its local +Y, so `line()` builds a basis whose Y COLUMN is
## the beam axis. It used to hang the tube under a pivot carrying a quarter turn and then overwrite
## that pivot's `global_transform` every frame — which wiped the quarter turn and laid the cylinder's
## AXIS across the beam, turning every beam into a flat translucent slab `width` tall and `length`
## deep with hard straight edges (r4 item 3). `SkillFx.tube_basis` is the one place that maths lives.

const SHADER := preload("res://combat/skills/fx/shaders/beam.gdshader")
const OPEN_LIFE := 3600.0

var _mesh: MeshInstance3D = null
var _strength: float = 1.5
var _fade: float = 0.0   ## seconds of fade at each end; 0 = hard ends


func _ready() -> void:
	super()
	_mesh = MeshInstance3D.new()
	_mesh.name = "Beam"
	# a cylinder, not a box: the shader's rim term needs a surface whose normal sweeps around the
	# axis, otherwise a beam seen from the side reads as a flat slab with hard edges
	var tube := CylinderMesh.new()
	tube.top_radius = 0.5
	tube.bottom_radius = 0.5
	tube.height = 1.0
	tube.radial_segments = 16
	tube.rings = 1
	# NO caps: a beam is an open tube. With the caps drawn, the near end of the 16 m Lance
	# layer filled a sixth of the screen with a flat pink disc that read as a ball at the
	# muzzle instead of a beam leaving it (r4 item 3).
	tube.cap_top = false
	tube.cap_bottom = false
	_mesh.mesh = tube
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.extra_cull_margin = 512.0
	add_child(_mesh)


## Long-lived beam: the owner calls `line()` every frame and `stop()` when the skill lets go.
## `solid` is how lit the tube's middle is: 1.0 is a solid bar of light, 0.1 a hollow outline. `reach`
## is the fraction of the tube the beam stays bright over (1.0 = no distance fade).
func open(color: Color, solid: float = 0.25, strength: float = 1.5, reach: float = 1.0) -> void:
	_mesh.set_instance_shader_parameter(&"color", color)
	_mesh.set_instance_shader_parameter(&"solid", solid)
	_mesh.set_instance_shader_parameter(&"reach", reach)
	_strength = strength
	_fade = 0.0
	_mesh.set_instance_shader_parameter(&"strength", strength)
	_begin(OPEN_LIFE)


## Timed beam that fades out over its own life (streaks, fin trails, lance afterglow).
func flash(from: Vector3, to: Vector3, width: float, color: Color, seconds: float,
		strength: float = 2.2, solid: float = 0.4) -> void:
	open(color, solid, strength)
	_fade = seconds
	_begin(seconds)
	line(from, to, width)


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


## The axis this beam is actually drawn along, for the test that pins the tube to `to - from`.
func axis() -> Vector3:
	return _mesh.global_basis.y.normalized()


func _advance(_delta: float) -> void:
	if _fade <= 0.0:
		return
	_mesh.set_instance_shader_parameter(&"strength", _strength * (1.0 - progress()))
