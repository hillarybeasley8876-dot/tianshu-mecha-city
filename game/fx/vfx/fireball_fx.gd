class_name FxFireball
extends Node3D
## Layered fireball (feel unit): 3 camera-facing quads running fx/vfx/fireball.gdshader, each with its
## own radius ratio, delay, noise seed and heat. The outer layer is the deep-red rolling edge, the
## inner ones are the white-yellow core, and they all erode away over `duration` — the "real fire"
## the r1 review asked for instead of a translucent blob. One blast = 3 draw calls, no particles.

const SHADER := preload("res://fx/vfx/fireball.gdshader")
## Per layer: ratio of the requested radius, start delay (s), HDR heat, spin (rad/s), erosion rate.
## Three overlapping shells at different sizes, delays and seeds are what give the ball depth - the
## r2 review's "2-3 overlapping layers", and the inner one carries the bloom.
const LAYERS: Array[Array] = [
	[1.00, 0.000, 1.5, 0.55, 0.62],
	[0.86, 0.035, 3.4, -0.95, 0.46],
	[0.62, 0.070, 6.0, 1.45, 0.30],
]
## Metres per second of front speed: an 8 m missile ball is full size in ~0.12 s (r2 MUST-FIX 1),
## a 28 m kill in ~0.3 s. Absolute seconds, not a fraction of the life, so the punch is the same
## whether the fire burns for 0.5 s or 1.4 s.
const EXPAND_BASE := 0.055
const EXPAND_PER_M := 0.009
const EXPAND_MAX := 0.30
## Quad size relative to the burning radius; the shader's `shell` disc sits inside it (2 / 0.86).
const QUAD_OVERSCAN := 2.33
## Noise cells per quad unit, from the radius, so flame cells stay about a metre at any blast size.
const NOISE_PER_M := 0.95
## Heat is per-pixel: a blast much wider than the reference radius is pulled back so it does not clip
## a third of the screen to white under AgX.
const HEAT_REF_RADIUS := 8.0
## Extra core heat in the first instants, so the detonation punches before it settles.
const POP_TIME := 0.05
const POP_GAIN := 0.35
## A looping ball (burning wreck) restarts its age here instead of stopping.
const LOOP_SECONDS := 1.1

## Continuous mode for fire_loop: the layers cycle instead of burning out once.
var auto_loop: bool = false
## Capture aid: the feel gallery slows real-time VFX (`--fx-slow=`) so a 0.15 s peak can be
## photographed. Always 1.0 in game.
var time_scale: float = 1.0
var _meshes: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
var _t: float = 0.0
var _last_real: float = 0
var _running: bool = false
var _radius: float = 8.0
var _duration: float = 0.55


func _ready() -> void:
	for i in LAYERS.size():
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		var mi := MeshInstance3D.new()
		mi.name = "Layer%d" % i
		mi.mesh = quad
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 128.0
		add_child(mi)
		_meshes.append(mi)
		_mats.append(mat)
	if auto_loop:
		fire(_radius, LOOP_SECONDS)
	else:
		visible = false


## Continuous mode: set the steady-state radius before the node enters the tree.
func set_loop_radius(radius: float) -> void:
	_radius = maxf(radius, 0.2)
	_duration = LOOP_SECONDS


## Burn a fireball of `radius` metres at this node's position for `duration` seconds.
func fire(radius: float, duration: float = 0.55) -> void:
	_radius = maxf(radius, 0.2)
	_duration = maxf(duration, 0.08)
	_t = 0.0
	_last_real = Feel.real_now()
	_running = true
	visible = true
	_apply()


func is_running() -> bool:
	return _running


func stop() -> void:
	_running = false
	visible = false


func _process(_delta: float) -> void:
	if not _running:
		return
	# Real time: fire keeps burning at full speed through a hit-stop (juice-impact rule 4).
	var now := Feel.real_now()
	_t += minf(now - _last_real, 0.1) * time_scale
	_last_real = now
	if _t >= _duration:
		if not auto_loop:
			stop()
			return
		_t = fmod(_t, _duration)
	_apply()


## Burning radius of the outer shell in metres right now (tests and the gallery read it).
func current_radius() -> float:
	return _radius * lerpf(0.12, 1.0,
			1.0 - pow(1.0 - clampf(_t / clampf(EXPAND_BASE + _radius * EXPAND_PER_M, 0.08, EXPAND_MAX),
			0.0, 1.0), 2.6))


func _apply() -> void:
	var heat_k := clampf(HEAT_REF_RADIUS / maxf(_radius, 1.0), 0.5, 1.15)
	var expand := clampf(EXPAND_BASE + _radius * EXPAND_PER_M, 0.08, EXPAND_MAX)
	var pop := 1.0 + POP_GAIN * exp(-_t / POP_TIME)
	for i in _meshes.size():
		var cfg: Array = LAYERS[i]
		var delay := float(cfg[1])
		var mi := _meshes[i]
		if _t < delay:
			mi.visible = false
			continue
		mi.visible = true
		# Ease-out expansion: the front races out to the full radius, then the ball only burns down.
		var age := clampf((_t - delay) / _duration, 0.0, 1.0)
		var grow := 1.0 - pow(1.0 - clampf((_t - delay) / expand, 0.0, 1.0), 2.6)
		var r := _radius * float(cfg[0]) * lerpf(0.12, 1.0, grow)
		mi.scale = Vector3.ONE * maxf(r * QUAD_OVERSCAN, 0.05)
		var mat := _mats[i]
		mat.set_shader_parameter(&"age", age)
		mat.set_shader_parameter(&"heat", float(cfg[2]) * heat_k * pop)
		mat.set_shader_parameter(&"seed", float(i) * 3.77 + 0.6)
		mat.set_shader_parameter(&"spin", _t * float(cfg[3]))
		mat.set_shader_parameter(&"erosion", float(cfg[4]))
		mat.set_shader_parameter(&"noise_scale", clampf(r * NOISE_PER_M, 3.0, 34.0))
