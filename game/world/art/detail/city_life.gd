class_name CityLife
extends Node3D
## Atmosphere and life layers (city-art, brief 5): reactor smoke columns, foundry steam vents and
## cheap bird/drone flocks. Every emitter is pre-instanced once here at load, which is also what
## warms the particle pipelines (godot-tech §4.5: a pipeline compiled mid-game is a stutter).
## Visibility ranges cull them; none of them casts shadows.

const SMOKE_RISE := 26.0
const SMOKE_LIFETIME := 26.0
const STEAM_LIFETIME := 5.0
const FLOCK_LIFETIME := 14.0
## Review r3 (lead): a reactor plume 600 m behind the Spire read as a black blob stuck under the Crown.
## The emitter is `unshaded`, so its colour does not change with distance the way the city's own
## surfaces do — a mid-grey at 55 % alpha stayed dark against a bright hazy sky. Backlit smoke at dusk
## is LUMINOUS, so the tint is warm and pale and the peak alpha is low; it reads as vapour at any range.
const SMOKE_TINT := Color(0.88, 0.82, 0.76)
const SMOKE_ALPHA := 0.30
const SMOKE_FADE_BEGIN := 700.0     ## metres; past this the plume dissolves rather than silhouettes
const SMOKE_FADE_LENGTH := 900.0

var emitters: Array[GPUParticles3D] = []


func _ready() -> void:
	# A hidden instance of every emitter type so its pipeline compiles before the first shot.
	smoke_column(Vector3(0.0, -400.0, 0.0), 60.0)
	steam_vent(Vector3(40.0, -400.0, 0.0))
	drone_flock(Vector3(-40.0, -400.0, 0.0), 40.0)
	for e in emitters:
		e.emitting = false


## A reactor stack plume: slow, tall, wind-sheared to the north-west with the prevailing sun side.
## The particle scale MULTIPLIES the draw-pass quad, so the quad is the puff size and `scale_*` only
## varies it — the other way round gave 300 m puffs that read as one black blob over the skyline.
func smoke_column(at: Vector3, height: float = 120.0, radius: float = 12.0,
		tint: Color = SMOKE_TINT) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "smoke_column"
	p.amount = 42
	p.lifetime = SMOKE_LIFETIME
	p.fixed_fps = 30
	p.visibility_aabb = AABB(Vector3(-radius * 6.0, 0.0, -radius * 6.0),
		Vector3(radius * 12.0, height * 1.6, radius * 12.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius * 0.5
	pm.direction = Vector3(-0.35, 1.0, -0.2).normalized()
	pm.spread = 12.0
	pm.initial_velocity_min = SMOKE_RISE * 0.6
	pm.initial_velocity_max = SMOKE_RISE
	pm.gravity = Vector3(-1.2, 0.6, -0.5)
	pm.damping_min = 0.4
	pm.damping_max = 1.2
	pm.scale_min = 0.55
	pm.scale_max = 1.5
	pm.scale_curve = _grow_curve()
	pm.color = tint
	pm.color_ramp = _fade_ramp(tint, SMOKE_ALPHA)
	p.process_material = pm
	p.draw_pass_1 = _quad(radius * 2.2)
	p.material_override = _billboard(SoftTextures.puff(3), tint, SMOKE_FADE_BEGIN,
		SMOKE_FADE_LENGTH)
	p.position = at
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_range_end = 2600.0
	add_child(p)
	emitters.append(p)
	return p


## A pavement steam vent: fast, short-lived, bright at the mouth.
func steam_vent(at: Vector3, normal: Vector3 = Vector3.UP) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "steam_vent"
	p.amount = 18
	p.lifetime = STEAM_LIFETIME
	p.fixed_fps = 30
	p.visibility_aabb = AABB(Vector3(-12.0, 0.0, -12.0), Vector3(24.0, 26.0, 24.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.6
	pm.direction = normal
	pm.spread = 14.0
	pm.initial_velocity_min = 7.0
	pm.initial_velocity_max = 13.0
	pm.gravity = Vector3(-1.6, 1.4, -0.6)
	pm.scale_min = 1.5
	pm.scale_max = 4.5
	pm.scale_curve = _grow_curve()
	pm.color_ramp = _fade_ramp(Color(0.86, 0.86, 0.88))
	p.process_material = pm
	p.draw_pass_1 = _quad(2.4)
	p.material_override = _billboard(SoftTextures.puff(7), Color(0.86, 0.86, 0.88))
	p.position = at
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_range_end = 320.0
	add_child(p)
	emitters.append(p)
	return p


## A flock of drones/birds wheeling over a district: no simulation, just a big emission box.
func drone_flock(at: Vector3, radius: float = 90.0, count: int = 40) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "drone_flock"
	p.amount = count
	p.lifetime = FLOCK_LIFETIME
	p.fixed_fps = 30
	p.visibility_aabb = AABB(Vector3(-radius, -radius * 0.4, -radius),
		Vector3(radius * 2.0, radius * 0.8, radius * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(radius, radius * 0.25, radius)
	pm.direction = Vector3(1.0, 0.0, 0.35).normalized()
	pm.spread = 45.0
	pm.initial_velocity_min = 12.0
	pm.initial_velocity_max = 26.0
	pm.gravity = Vector3(0.0, 0.4, 0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 3.2
	pm.turbulence_noise_scale = 1.4
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.color_ramp = _fade_ramp(Color(0.10, 0.11, 0.14))
	p.process_material = pm
	p.draw_pass_1 = _quad(1.1)
	p.material_override = _billboard(SoftTextures.radial(1.4), Color(0.10, 0.11, 0.14))
	p.position = at
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_range_end = 1400.0
	add_child(p)
	emitters.append(p)
	return p


func _quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	return q


func _billboard(tex: Texture2D, tint: Color, fade_begin: float = 0.0,
		fade_length: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_color = tint
	m.albedo_texture = tex
	m.disable_receive_shadows = true
	m.no_depth_test = false
	if fade_begin > 0.0:
		# Godot 4 names the pair min/max distance; the 3.x begin/length names are silently remapped away.
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		m.distance_fade_min_distance = fade_begin
		m.distance_fade_max_distance = fade_begin + fade_length
	return m


## Particles grow as they age: `scale_curve` is a CurveTexture, not a Curve.
func _grow_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.15))
	c.add_point(Vector2(0.35, 0.75))
	c.add_point(Vector2(1.0, 1.0))
	var t := CurveTexture.new()
	t.curve = c
	return t


func _fade_ramp(tint: Color, peak: float = 0.55) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(tint.r, tint.g, tint.b, 0.0))
	g.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	g.add_point(0.18, Color(tint.r, tint.g, tint.b, peak))
	g.add_point(0.62, Color(tint.r, tint.g, tint.b, peak * 0.58))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t
