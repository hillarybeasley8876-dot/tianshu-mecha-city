class_name VfxPresets
extends RefCounted
## Particle system construction for the pooled VFX library (feel unit). Every kind in
## docs/FEEL.md's "Particles / decals" column has a builder here; VfxLibrary pre-instances them so no
## shot ever instantiates a node.
##
## Preset numbers follow ref/research/juice-impact.md §6 and ART.md §2 (hero cyan, enemy acid/violet,
## blast orange #FF8A2B). Impact streaks run fx/vfx/spark_process.gdshader so their length follows
## their own speed; smoke and dust run fx/vfx/puff.gdshader (soft, lit, noise-broken rim).
## Impact emitters use fixed_fps = 0 + interpolate = false so they do not go choppy under a low
## Engine.time_scale (juice-impact §6, Godot #81429).

const CYAN := Color(0.31, 0.9, 1.0)
const ACID := Color(0.61, 1.0, 0.23)
const VIOLET := Color(0.69, 0.3, 1.0)
const ORANGE := Color(1.0, 0.54, 0.17)
const EMBER := Color(1.0, 0.78, 0.35)
const SMOKE := Color(0.15, 0.15, 0.17)
const DUST := Color(0.47, 0.43, 0.37)
const HOT := Color(1.0, 0.97, 0.9)
const BEAM_HOT := Color(0.9, 1.0, 1.0)

const SPARK_PROCESS := preload("res://fx/vfx/spark_process.gdshader")
const SPARK_DRAW := preload("res://fx/vfx/spark.gdshader")
const PUFF := preload("res://fx/vfx/puff.gdshader")

## Life of a pooled instance per kind, seconds. VfxLibrary frees the slot after this.
const LIFE: Dictionary = {
	&"spark_bullet": 0.35, &"spark_beam": 0.4, &"missile_blast": 3.4, &"kill_small": 3.0,
	&"kill_large": 4.0, &"dust_ring": 1.8, &"dust_puff": 1.2, &"steam": 2.2,
	&"thruster_burst": 0.7, &"shockwave_ring": 0.6, &"muzzle_ring": 0.25, &"spark_burst": 0.8,
	&"impact_star": 0.2,
}

## Pool size per kind (0 = built on demand, never pooled).
const POOL: Dictionary = {
	&"spark_bullet": 24, &"spark_beam": 12, &"missile_blast": 10, &"kill_small": 6,
	&"kill_large": 4, &"dust_ring": 10, &"dust_puff": 12, &"steam": 6,
	&"thruster_burst": 10, &"shockwave_ring": 12, &"muzzle_ring": 8, &"spark_burst": 8,
	&"impact_star": 6,
}

## Fireball radius in metres for the explosion kinds (r1 review: sizes at mech scale).
const RADIUS: Dictionary = {
	&"missile_blast": 8.0, &"kill_small": 12.0, &"kill_large": 28.0,
}

## Continuous emitters for the city and for wrecks: not pooled one-shots, handed out by
## VfxLibrary.emitter() and returned with VfxLibrary.release_emitter().
const PERSISTENT: Dictionary = {&"fire_loop": 8, &"smoke_column": 8}


static func life_of(kind: StringName) -> float:
	return float(LIFE.get(kind, 1.0))


static func pool_size(kind: StringName) -> int:
	return int(POOL.get(kind, 6))


static func radius_of(kind: StringName) -> float:
	return float(RADIUS.get(kind, 8.0))


## Builds one instance of `kind`. Unknown kinds return a bare Node3D and warn (the director warns once).
static func build(kind: StringName) -> Node3D:
	match kind:
		&"spark_bullet":
			return build_impact(build_sparks(20, HOT, ORANGE, 18.0, 42.0, 0.3, 0.26, 60.0, 24.0))
		&"spark_beam":
			return build_impact(build_sparks(18, BEAM_HOT, CYAN, 22.0, 48.0, 0.34, 0.22, 62.0, 14.0))
		&"spark_burst":
			return build_impact(build_sparks(48, Color(1.0, 0.95, 0.8), EMBER, 12.0, 40.0, 0.55, 0.3,
					180.0, 16.0))
		&"impact_star":
			return _pop(6.0, 0.13, Color(1.0, 0.97, 0.9), 6.0, 1.0)
		&"muzzle_ring":
			return build_sparks(6, CYAN, CYAN, 6.0, 16.0, 0.12, 0.6, 180.0, 0.0)
		&"thruster_burst":
			return build_sparks(20, BEAM_HOT, CYAN, 14.0, 32.0, 0.3, 0.7, 22.0, 0.0)
		&"missile_blast", &"kill_small", &"kill_large":
			var blast := FxBlast.new()
			blast.name = "Blast"
			return blast
		&"dust_ring":
			return build_dust(24, 1.8, 14.0, 0.7)
		&"dust_puff":
			return build_dust(10, 1.2, 4.0, 0.45)
		&"steam":
			return build_steam(14)
		&"fire_loop":
			return build_fire_loop()
		&"smoke_column":
			return build_smoke_column()
		&"shockwave_ring":
			var ring := ShockwaveFx.new()
			ring.name = "ShockwaveRing"
			return ring
	push_warning("VfxPresets: unknown kind %s" % kind)
	var empty := Node3D.new()
	empty.name = "Unknown"
	return empty


static func _quad() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	return q


## Wraps a spark emitter in the impact composite (streaks + contact flash). The pop is what still
## reads at 150 m, where a 0.26 m streak is a fraction of a pixel (r2 MUST-FIX 3).
static func build_impact(emitter: GPUParticles3D) -> Node3D:
	var root := FxImpact.new()
	root.name = "Impact"
	root.setup(emitter, FxFlashPop.new())
	return root


## A bare contact flash / cross flare, pooled as `impact_star` for heavy melee hits. The node is
## configured here and fired by VfxLibrary once it is in the tree (its material only exists then).
static func _pop(size_m: float, seconds: float, color: Color, heat: float, star: float) -> Node3D:
	var node := FxFlashPop.new()
	node.name = "FlashPop"
	node.configure(size_m, seconds, color, heat, star)
	return node


## Streaks fire away from the surface; ground effects stay upright (a dust ring must not tilt).
static func facing(normal: Vector3) -> Basis:
	var n := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	if n.dot(Vector3.UP) > 0.7:
		return Basis(Vector3.UP, randf() * TAU)
	# ParticleProcessMaterial aims along local -Z, so the node's +Z axis points into the surface.
	var z := -n
	var ref := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(z).normalized()
	return Basis(x, z.cross(x).normalized(), z)


static func _draw(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


static func _pm() -> ParticleProcessMaterial:
	return ParticleProcessMaterial.new()


## Velocity-aligned streaks (the core of every bullet/beam/melee impact). `width` is the streak
## thickness in metres; the length is set per particle from its own speed in spark_process.gdshader.
## `dir` is the cone axis in the emitter's own frame (the spark shader rotates it by the emitter's
## basis, so a node with an identity basis fires along world `dir`).
static func build_sparks(amount: int, hot: Color, cool: Color, vmin: float, vmax: float, life: float,
		width: float, spread: float, gravity: float, dir: Vector3 = Vector3(0.0, 0.3, -1.0)) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Sparks"
	p.amount = amount
	var proc := ShaderMaterial.new()
	proc.shader = SPARK_PROCESS
	proc.set_shader_parameter(&"spread_deg", spread)
	proc.set_shader_parameter(&"speed_min", vmin)
	proc.set_shader_parameter(&"speed_max", vmax)
	proc.set_shader_parameter(&"gravity", -gravity)
	proc.set_shader_parameter(&"width_min", width * 0.7)
	proc.set_shader_parameter(&"width_max", width)
	proc.set_shader_parameter(&"color_hot", hot)
	proc.set_shader_parameter(&"color_cool", cool)
	# Sparks ricochet off the surface rather than running along it: tilt the cone up from local -Z.
	proc.set_shader_parameter(&"emit_direction", dir.normalized())
	proc.set_shader_parameter(&"stretch", 0.05)
	p.process_material = proc
	var q := _quad()
	var draw := _draw(SPARK_DRAW)
	draw.set_shader_parameter(&"color_hot", hot)
	draw.set_shader_parameter(&"color_cool", cool)
	draw.set_shader_parameter(&"hold", 0.5)
	q.material = draw
	p.draw_pass_1 = q
	# A custom particles shader gives Godot nothing to derive a culling box from, so it must be set
	# by hand or the whole system disappears as soon as the streaks leave the emitter's own AABB.
	var reach := vmax * life + 4.0
	p.visibility_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * reach * 2.0)
	return _finish(p, life)


## Dark, soft, rising smoke. Lit by puff.gdshader's cheap sun term so it reads as volume.
## `burst` is the Godot explosiveness: 1.0 = the whole plume leaves at once (a detonation), 0.0 = a
## steady column (a burning wreck or a reactor stack). `soot` is how much sun the plume catches:
## 0.5 is a normal plume, 0.12 is the near-black column a detonation leaves behind (r2 MUST-FIX 1).
static func build_smoke(amount: int, life: float, burst: float = 0.55,
		soot: float = 0.5) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Smoke"
	p.amount = maxi(amount, 3)
	var pm := _pm()
	pm.direction = Vector3.UP
	pm.spread = 42.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0.0, 1.6, 0.0)
	pm.damping_min = 1.2
	pm.damping_max = 3.0
	pm.scale_min = 2.2
	pm.scale_max = 5.5
	pm.scale_curve = _curve(0.0, 0.35, 1.0, 1.0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.8
	pm.color = Color(SMOKE, 0.95)
	pm.color_ramp = _fade(Color(SMOKE, 0.98), 0.85)
	p.process_material = pm
	var q := _quad()
	q.material = _puff_material(Color(SMOKE, 0.95), 0.85, 0.55, soot)
	p.draw_pass_1 = q
	var out := _finish(p, maxf(life, 1.0))
	out.explosiveness = clampf(burst, 0.0, 1.0)
	return out


## Ground dust: launches outward with a wide spread and settles fast, so it reads as a low ring
## rolling away from the impact instead of a column of blobs.
static func build_dust(amount: int, life: float, speed: float, size_m: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Dust"
	p.amount = amount
	var pm := _pm()
	pm.direction = Vector3.UP
	pm.spread = 89.0
	pm.flatness = 0.85
	pm.initial_velocity_min = speed * 0.45
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0.0, -3.5, 0.0)
	pm.damping_min = 4.0
	pm.damping_max = 9.0
	pm.scale_min = 1.0 * size_m * 4.0
	pm.scale_max = 2.6 * size_m * 4.0
	pm.scale_curve = _curve(0.0, 0.45, 1.0, 1.0)
	pm.color = Color(DUST, 0.8)
	pm.color_ramp = _fade(Color(DUST, 0.85), 0.6)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	p.process_material = pm
	var q := _quad()
	q.material = _puff_material(Color(DUST, 0.8), 0.6, 0.4)
	p.draw_pass_1 = q
	var out := _finish(p, life)
	out.explosiveness = 0.9
	return out


static func build_steam(amount: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Steam"
	p.amount = amount
	var pm := _pm()
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0.0, 2.5, 0.0)
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	pm.scale_min = 1.2
	pm.scale_max = 3.2
	pm.scale_curve = _curve(0.0, 0.3, 1.0, 1.0)
	pm.color = Color(0.9, 0.94, 1.0, 0.5)
	pm.color_ramp = _fade(Color(0.9, 0.94, 1.0, 0.5), 0.5)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5
	p.process_material = pm
	var q := _quad()
	q.material = _puff_material(Color(0.9, 0.94, 1.0, 0.5), 0.7, 0.35)
	p.draw_pass_1 = q
	var out := _finish(p, 1.6)
	out.explosiveness = 0.7
	return out


## A burning wreck (r1 SHOULD): low continuous flames + a smoke plume. Handed out by
## VfxLibrary.emitter(&"fire_loop"), returned with release_emitter().
static func build_fire_loop() -> Node3D:
	var root := Node3D.new()
	root.name = "FireLoop"
	var fire := FxFireball.new()
	fire.name = "Fire"
	fire.auto_loop = true
	root.add_child(fire)
	fire.set_loop_radius(3.0)
	var smoke := build_smoke(16, 4.0)
	smoke.name = "Smoke"
	smoke.one_shot = false
	smoke.explosiveness = 0.0
	smoke.emitting = true
	root.add_child(smoke)
	return root


## A city smoke stack (r1 SHOULD): one tall, slow, wind-bent column for reactor stacks and burning
## buildings. Scale it up for a 60 m plume.
static func build_smoke_column() -> GPUParticles3D:
	var p := build_smoke(24, 9.0)
	p.name = "SmokeColumn"
	p.one_shot = false
	p.explosiveness = 0.0
	p.emitting = true
	p.lifetime = 9.0
	var pm := p.process_material as ParticleProcessMaterial
	pm.spread = 8.0
	pm.initial_velocity_min = 7.0
	pm.initial_velocity_max = 12.0
	pm.gravity = Vector3(1.6, 2.2, 0.4)
	pm.scale_min = 6.0
	pm.scale_max = 16.0
	return p


## Soft lit puff material (fx/vfx/puff.gdshader). `softness` is the alpha falloff, `breakup` the
## noise that chews the rim so puffs do not read as circles.
static func _puff_material(color: Color, softness: float, breakup: float,
		sun_gain: float = 0.5) -> ShaderMaterial:
	var m := _draw(PUFF)
	m.set_shader_parameter(&"puff_color", color)
	m.set_shader_parameter(&"softness", softness)
	m.set_shader_parameter(&"breakup", breakup)
	m.set_shader_parameter(&"sun_gain", sun_gain)
	return m


## Hold-then-fade gradient: an impact puff must stay visible for most of its life and then die
## quickly, otherwise it reads as a smudge on a bright floor. `peak` scales the held alpha.
static func _fade(color: Color, peak: float = 0.95) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(color, color.a))
	g.set_offset(0, 0.0)
	g.add_point(0.5, Color(color, color.a * peak))
	g.set_color(1, Color(color, 0.0))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _finish(p: GPUParticles3D, life: float) -> GPUParticles3D:
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = life
	p.fixed_fps = 0
	p.interpolate = false
	p.local_coords = false
	p.emitting = false
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	return p


static func _curve(x0: float, y0: float, x1: float, y1: float) -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(x0, y0))
	c.add_point(Vector2(x1, y1))
	var t := CurveTexture.new()
	t.curve = c
	return t


## Restarts every emitter inside a pooled instance (composites hold several).
## Size multiplier for a spark emitter, through the `size_mul` uniform. NOT node.scale: local_coords
## is false, so the particles ignore the node transform and scaling the node only shrank the culling
## box while the streaks stayed their full size. Returns false for emitters built from a
## ParticleProcessMaterial (no size_mul uniform), which the caller sizes the ordinary way.
static func set_size_mul(p: GPUParticles3D, k: float) -> bool:
	var mat := p.process_material as ShaderMaterial
	if mat == null:
		return false
	mat.set_shader_parameter(&"size_mul", clampf(k, 0.05, 40.0))
	return true


static func restart(node: Node) -> void:
	if node is GPUParticles3D:
		(node as GPUParticles3D).restart()
		(node as GPUParticles3D).emitting = true
	for child in node.get_children():
		restart(child)
