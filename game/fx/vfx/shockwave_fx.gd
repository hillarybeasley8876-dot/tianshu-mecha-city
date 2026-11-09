class_name ShockwaveFx
extends Node3D
## One expanding ring of the shockwave pool (VfxLibrary). FEEL.md uses it for missile hits
## (0 -> 20 m in 180 ms), melee_heavy (0 -> 8 m) and shockcore (0 -> 32 m): the geometry is a single
## quad with fx/vfx/shockwave_ring.gdshader, so a whole salvo costs one draw call each and no
## particles. `fire()` lays it on the impact surface and animates radius + fade on real time.

const SHADER := preload("res://fx/vfx/shockwave_ring.gdshader")
## Ease-out exponent of the expanding front: fast first, so the ring reads as a shock front rather
## than a growing circle. radius_at() is the single source of truth for the growth curve.
const EASE := 2.2

var radius_max: float = 8.0
var duration: float = 0.18
## Capture aid: the feel gallery slows real-time VFX (`--fx-slow=`) so the peak frame of a 0.18 s
## ring can be photographed. Always 1.0 in game.
var time_scale: float = 1.0
var _t: float = 0.0
var _last_real: float = 0
var _running: bool = false
var _mesh: MeshInstance3D
var _mat: ShaderMaterial


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Ring"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	_mesh.mesh = plane
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.extra_cull_margin = 64.0
	add_child(_mesh)
	visible = false


## Lay the ring on `surface` (its normal; Vector3.UP for ground) and expand to `to_radius` metres.
func fire(at: Vector3, surface: Vector3, to_radius: float, seconds: float, color: Color) -> void:
	var up := surface.normalized() if surface.length_squared() > 0.001 else Vector3.UP
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	global_transform = Transform3D(Basis(x, up, x.cross(up).normalized()), at)
	radius_max = maxf(to_radius, 0.1)
	duration = maxf(seconds, 0.02)
	_t = 0.0
	_last_real = Feel.real_now()
	_running = true
	visible = true
	_mat.set_shader_parameter(&"ring_color", color)
	_apply(0.0)


func is_running() -> bool:
	return _running


func stop() -> void:
	_running = false
	visible = false


## Front radius in metres at normalised age `p` (0 at the impact, `radius_max` at p = 1). The test
## asserts the FEEL rows' published numbers against this - shockcore 32 m and collapse 20 m.
static func radius_at(radius: float, p: float) -> float:
	return maxf(radius, 0.0) * (1.0 - pow(1.0 - clampf(p, 0.0, 1.0), EASE))


func current_radius() -> float:
	return radius_at(radius_max, _t / maxf(duration, 0.001))


func _process(_delta: float) -> void:
	if not _running:
		return
	# Real time: rings keep expanding at full speed through a hit-stop (juice-impact rule 4).
	var now := Feel.real_now()
	_t += minf(now - _last_real, 0.1) * time_scale
	_last_real = now
	_apply(_t / duration)
	if _t >= duration:
		stop()


func _apply(k: float) -> void:
	var p := clampf(k, 0.0, 1.0)
	# Ease out: fast first, so the ring reads as a shock front rather than a growing circle.
	var s := radius_at(radius_max, p) * 2.0
	_mesh.scale = Vector3(maxf(s, 0.01), 1.0, maxf(s, 0.01))
	_mat.set_shader_parameter(&"progress", p)
	_mat.set_shader_parameter(&"thickness", lerpf(0.05, 0.16, p))
