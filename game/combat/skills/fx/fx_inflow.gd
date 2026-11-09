class_name SkillFxInflow
extends SkillFxPiece
## Spiral inflow particles: matter being dragged into a point. The Shockcore Burst inhales with them
## during its 18 f of startup, the Undertow Well runs them for the whole 3.5 s field, and the Plunge
## impact lifts a slower, wider set off the ground. Emission is a sphere shell with a negative radial
## velocity plus orbit, so the motes visibly spiral in instead of falling straight.

var _particles: GPUParticles3D = null
var _pmat: ParticleProcessMaterial = null


func _ready() -> void:
	super()
	_particles = GPUParticles3D.new()
	_particles.name = "Inflow"
	_particles.amount = 96
	_particles.lifetime = 0.9
	_particles.explosiveness = 0.0
	_particles.randomness = 0.6
	_particles.local_coords = false
	_particles.draw_order = GPUParticles3D.DRAW_ORDER_LIFETIME
	_pmat = ParticleProcessMaterial.new()
	_pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	_pmat.emission_sphere_radius = 24.0
	_pmat.gravity = Vector3.ZERO
	_pmat.radial_velocity_min = -34.0
	_pmat.radial_velocity_max = -18.0
	_pmat.orbit_velocity_min = 0.4
	_pmat.orbit_velocity_max = 1.1
	_pmat.scale_min = 0.5
	_pmat.scale_max = 1.6
	_pmat.damping_min = 2.0
	_pmat.damping_max = 6.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	ramp.add_point(0.35, Color(1.0, 1.0, 1.0, 1.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	_pmat.color_ramp = tex
	_particles.process_material = _pmat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	_particles.draw_pass_1 = quad
	_particles.material_override = SkillFx.glow(Color(1.0, 1.0, 1.0), 2.4, true)
	add_child(_particles)


## `inward` is the pull speed in m/s (positive = toward the centre).
func fire(at: Vector3, radius: float, seconds: float, color: Color, amount: int = 96,
		inward: float = 26.0, orbit: float = 0.8, mote: float = 0.9) -> void:
	global_position = at
	_pmat.emission_sphere_radius = maxf(radius, 0.5)
	_pmat.radial_velocity_min = -inward * 1.35
	_pmat.radial_velocity_max = -inward * 0.7
	_pmat.orbit_velocity_min = orbit * 0.5
	_pmat.orbit_velocity_max = orbit * 1.4
	_particles.amount = maxi(amount, 8)
	_particles.lifetime = clampf(radius / maxf(inward, 1.0) * 1.2, 0.35, 2.2)
	var mat := _particles.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = color
		mat.emission = color
	var quad := _particles.draw_pass_1 as QuadMesh
	if quad != null:
		quad.size = Vector2(mote, mote)
	_particles.emitting = true
	_particles.restart()
	_begin(seconds)


## A field that grows or shrinks while it runs (the well's arming pulse).
func move_to(at: Vector3, radius: float) -> void:
	global_position = at
	_pmat.emission_sphere_radius = maxf(radius, 0.5)


func stop() -> void:
	super()
	if _particles != null:
		_particles.emitting = false
