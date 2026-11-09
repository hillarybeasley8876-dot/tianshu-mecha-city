class_name FxBlast
extends Node3D
## One pooled explosion (feel unit): a layered fireball (FxFireball), dark smoke that outlives the
## fire by a second and a half, embers on ballistic arcs and - when the detonation is close to the
## floor - a rolling dust ring. Everything is sized from the blast radius in metres, so the same
## node serves a missile (R 8 m), a small kill (R 12 m) and a large kill (R 28 m). The scorch decal
## is the row's decal column, not this node.

const BASE_RADIUS := 8.0
## Seconds of fireball per metre of radius (a 28 m kill burns longer than an 8 m missile).
const FIRE_PER_M := 0.03
const FIRE_MIN := 0.5
const FIRE_MAX := 1.4
## The smoke plume is what still reads at 150 m once the fire has gone (r2 MUST-FIX 1).
const SMOKE_SECONDS := 2.0
const EMBER_SECONDS := 1.2
## The plume is wider than the fireball, so it keeps reading at 150 m after the fire has gone.
const SMOKE_SPREAD := 1.7
## A blast whose fireball reaches within this many metres of the floor throws a ground dust ring.
const GROUND_MARGIN := 5.0
var fireball: FxFireball
var _smoke: GPUParticles3D
var _embers: GPUParticles3D
var _dust: GPUParticles3D
var _radius: float = BASE_RADIUS
var _probe_ground: bool = false


func _ready() -> void:
	fireball = FxFireball.new()
	fireball.name = "Fire"
	add_child(fireball)
	_smoke = VfxPresets.build_smoke(20, SMOKE_SECONDS, 0.85, 0.12)
	_smoke.name = "Smoke"
	add_child(_smoke)
	# FxBlast keeps an identity basis, so the ember cone's axis is a world direction: straight up, or
	# the burst would spray sideways out of every explosion.
	_embers = VfxPresets.build_sparks(40, VfxPresets.EMBER, VfxPresets.ORANGE, 14.0, 46.0,
			EMBER_SECONDS, 0.5, 180.0, 14.0, Vector3.UP)
	_embers.name = "Embers"
	add_child(_embers)
	_dust = VfxPresets.build_dust(22, 2.0, 18.0, 1.0)
	_dust.name = "GroundDust"
	add_child(_dust)
	visible = false


## Detonate at `at` with a fireball of `radius` * `scale_mul` metres. `normal` is the surface hit; a
## ground hit also throws a dust ring at the point where the fireball meets the floor.
func fire(at: Vector3, normal: Vector3, radius: float, scale_mul: float = 1.0) -> void:
	global_position = at
	var r := maxf(radius * scale_mul, 0.3)
	var k := r / BASE_RADIUS
	_radius = r
	visible = true
	# Lift the ball so a ground hit is not sliced in half by the floor it stands on.
	fireball.position = Vector3(0.0, r * 0.42, 0.0)
	fireball.fire(r, clampf(r * FIRE_PER_M, FIRE_MIN, FIRE_MAX))
	_smoke.scale = Vector3.ONE * k * SMOKE_SPREAD
	_embers.scale = Vector3.ONE
	VfxPresets.set_size_mul(_embers, k)
	VfxPresets.restart(_smoke)
	VfxPresets.restart(_embers)
	_dust.scale = Vector3.ONE * k
	_dust.emitting = false
	# A surface normal that is already floor-facing settles it now; otherwise the ground is probed
	# on the next physics tick (a ray query is only legal there).
	if normal.length_squared() > 0.001 and normal.normalized().dot(Vector3.UP) > 0.7:
		_dust_at(global_position)
	else:
		_probe_ground = true


func stop() -> void:
	visible = false
	_probe_ground = false
	fireball.stop()
	_smoke.emitting = false
	_embers.emitting = false
	_dust.emitting = false


## Ground probe: a blast in the air has no dust ring, one skimming the street does.
func _physics_process(_delta: float) -> void:
	if not _probe_ground:
		return
	_probe_ground = false
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return
	var from := global_position
	var to := from + Vector3.DOWN * (_radius * 0.42 + GROUND_MARGIN)
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.MASK_SIGHT)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		_dust_at(hit["position"] as Vector3)


func _dust_at(at: Vector3) -> void:
	_dust.global_position = at
	_dust.emitting = false
	VfxPresets.restart(_dust)
