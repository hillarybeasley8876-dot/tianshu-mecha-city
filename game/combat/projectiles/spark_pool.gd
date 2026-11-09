class_name SparkPool
extends Node3D
## Impact visuals (projectiles unit) and the weapons' route into the fx unit: every impact asks for a
## pooled kind through FxBridge first (`spark_beam`, `spark_bullet`, `missile_blast`, `scorch`) and
## only draws its own fallback when the fx unit is not in the tree (bare range scene, headless tests).
##
## The fallback is deliberately not a small orb: an expanding emissive fireball, a flash light and a
## soft grey-white smoke puff that rises and fades (ART.md explosions #FF8A2B -> #FFD27A).

const CAPACITY := 24
const SMOKE_SLOTS := 12
const LIGHT_SLOTS := 4
const LIGHT_LIFE := 0.14

var _items: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var _left: PackedFloat64Array = PackedFloat64Array()
var _life: PackedFloat64Array = PackedFloat64Array()
var _size: PackedFloat64Array = PackedFloat64Array()
var _alpha: PackedFloat64Array = PackedFloat64Array()
var _smoke: Array[MeshInstance3D] = []
var _smoke_mats: Array[StandardMaterial3D] = []
var _smoke_left: PackedFloat64Array = PackedFloat64Array()
var _smoke_life: PackedFloat64Array = PackedFloat64Array()
var _smoke_size: PackedFloat64Array = PackedFloat64Array()
var _smoke_rise: PackedFloat64Array = PackedFloat64Array()
var _lights: Array[OmniLight3D] = []
var _light_left: PackedFloat64Array = PackedFloat64Array()
var _light_peak: PackedFloat64Array = PackedFloat64Array()
## Largest size drawn by `muzzle_flash()` and by everything else, kept apart so a test can measure
## the gun's flash without the impact sparks the same pool draws at the target (lead r5 item 1).
var _flash_peak: float = 0.0
var _spark_peak: float = 0.0
var _puff_peak: float = 0.0


func _ready() -> void:
	# World-space pool: every instance transform below is a world position, so the node must not
	# inherit the mech's transform. `weapon_system.tscn` sets top_level; a bare script instance
	# (tests, tools) may not, and then every visual is drawn at player_xf * world_pos.
	if not top_level:
		top_level = true
		global_transform = Transform3D.IDENTITY
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 10
	sphere.rings = 6
	for i in CAPACITY:
		_items.append(_make(&"Spark%d" % i, sphere, _mats, BeamPool.additive_material(
				Color(1.0, 0.9, 0.6), 1.8)))
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	for i in SMOKE_SLOTS:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
		mat.albedo_texture = FxBridge.soft_disc_texture()
		mat.albedo_color = Color(0.82, 0.84, 0.88)
		mat.disable_receive_shadows = true
		_smoke.append(_make(&"Smoke%d" % i, quad, _smoke_mats, mat))
	_left.resize(CAPACITY)
	_life.resize(CAPACITY)
	_size.resize(CAPACITY)
	_alpha.resize(CAPACITY)
	_smoke_left.resize(SMOKE_SLOTS)
	_smoke_life.resize(SMOKE_SLOTS)
	_smoke_size.resize(SMOKE_SLOTS)
	_smoke_rise.resize(SMOKE_SLOTS)
	for i in LIGHT_SLOTS:
		var l := OmniLight3D.new()
		l.name = "SparkLight%d" % i
		l.omni_range = 26.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		add_child(l)
		_lights.append(l)
	_light_left.resize(LIGHT_SLOTS)
	_light_peak.resize(LIGHT_SLOTS)
	set_process(true)


func _make(nm: StringName, mesh: Mesh, mats: Array[StandardMaterial3D],
		mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = String(nm)
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	mats.append(mat)
	return mi


## Beam hit: the fx unit's cyan sparks, else a bright short flash sphere.
func spark_beam(at: Vector3, normal: Vector3, scale_m: float) -> void:
	if FxBridge.spawn(self, &"spark_beam", at, normal, maxf(scale_m / 4.0, 0.4)):
		return
	impact(at, normal, Color(0.55, 0.92, 1.0), scale_m, 0.18, 1.6)


## Gatling hit: small, fast, per round.
func spark_bullet(at: Vector3, normal: Vector3, scale_m: float) -> void:
	if FxBridge.spawn(self, &"spark_bullet", at, normal, maxf(scale_m / 2.5, 0.3)):
		return
	impact(at, normal, Color(1.0, 0.78, 0.35), scale_m, 0.12, 0.0)


## Missile detonation: `missile_blast` + `scorch` + a flash through the fx unit, else the fallback
## fireball (0 -> 2x radius in 0.15 s), flash light and smoke puff.
func blast(at: Vector3, normal: Vector3, radius: float) -> void:
	var n := normal if normal.length_squared() > 0.001 else Vector3.UP
	if FxBridge.spawn(self, &"missile_blast", at, n, maxf(radius / 6.0, 0.5)):
		FxBridge.spawn(self, &"scorch", at, n, radius / 6.0)
		FxBridge.ring(self, at, n, radius * 1.6, 0.25, Color(1.0, 0.62, 0.25))
		return
	impact(at, n, Color(1.0, 0.55, 0.18), radius * 1.7, 0.28, 5.0)
	_smoke_puff(at + n * radius * 0.3, radius * 2.4, 1.1, radius * 0.9)


## Missile launch puff (dust at the rail). The fallback is our own soft smoke quad.
func puff(at: Vector3, normal: Vector3, scale_m: float) -> void:
	var n := normal if normal.length_squared() > 0.001 else Vector3.UP
	# Recorded here, not in _smoke_puff: a detonation's smoke is not a launch puff.
	_puff_peak = maxf(_puff_peak, scale_m * 2.0)
	if FxBridge.spawn(self, &"dust_puff", at, n, maxf(scale_m / 3.0, 0.4)):
		return
	_smoke_puff(at, scale_m * 2.0, 0.55, scale_m * 0.5)
	impact(at, n, Color(1.0, 0.82, 0.5), scale_m * 0.5, 0.14, 1.2)


## The gun's own flash at the muzzle. Drawn by this pool (there is no fx route for a muzzle flash), so
## it is the one visual the first-person size rule has to reach: the caller passes the already-scaled
## size and opacity from `WeaponContext`. Kept apart from `impact()` so the peak it records is the
## flash alone.
func muzzle_flash(at: Vector3, dir: Vector3, color: Color, size: float, life: float,
		alpha: float = 1.0) -> void:
	_flash_peak = maxf(_flash_peak, size)
	_draw(at, color, size, life, 0.0, alpha)


## Largest muzzle flash drawn since the last `reset_peaks()` (metres).
func flash_peak_m() -> float:
	return _flash_peak


## Largest impact / blast / puff sphere drawn since the last `reset_peaks()` (metres).
func spark_peak_m() -> float:
	return _spark_peak


## Largest smoke puff (missile launch dust) drawn since the last `reset_peaks()` (metres).
func puff_peak_m() -> float:
	return _puff_peak


func reset_peaks() -> void:
	_flash_peak = 0.0
	_spark_peak = 0.0
	_puff_peak = 0.0


## Generic fallback impact: an expanding emissive sphere, plus an omni flash when `light` > 0.
func impact(at: Vector3, normal: Vector3, color: Color, scale_m: float, life: float = 0.16,
		light: float = 0.0, alpha: float = 1.0) -> void:
	_spark_peak = maxf(_spark_peak, scale_m)
	_draw(at, color, scale_m, life, light, alpha)


func _draw(at: Vector3, color: Color, scale_m: float, life: float, light: float,
		alpha: float) -> void:
	var i := _free(_left, CAPACITY)
	if i < 0:
		return
	var mi := _items[i]
	mi.visible = true
	mi.global_position = at
	mi.scale = Vector3.ONE * scale_m * 0.3
	var mat := _mats[i]
	mat.albedo_color = Color(color.r * 1.8, color.g * 1.8, color.b * 1.8, alpha)
	mat.emission = color
	_left[i] = life
	_life[i] = life
	_size[i] = scale_m
	_alpha[i] = alpha
	if light > 0.0:
		_flash(at, color, light)


func _smoke_puff(at: Vector3, size: float, life: float, rise: float) -> void:
	var i := _free(_smoke_left, SMOKE_SLOTS)
	if i < 0:
		return
	var mi := _smoke[i]
	mi.visible = true
	mi.global_position = at
	mi.scale = Vector3.ONE * size * 0.4
	_smoke_mats[i].albedo_color = Color(0.82, 0.84, 0.88, 0.75)
	_smoke_left[i] = life
	_smoke_life[i] = life
	_smoke_size[i] = size
	_smoke_rise[i] = rise


func _flash(at: Vector3, color: Color, energy: float) -> void:
	if FxBridge.flash(self, at, color, energy, 26.0, 3.0):
		return
	var best := 0
	for i in LIGHT_SLOTS:
		if _light_left[i] <= 0.0:
			best = i
			break
		if _light_left[i] < _light_left[best]:
			best = i
	var l := _lights[best]
	l.global_position = at
	l.light_color = color
	l.light_energy = energy
	_light_left[best] = LIGHT_LIFE
	_light_peak[best] = energy


func _free(times: PackedFloat64Array, count: int) -> int:
	for i in count:
		if times[i] <= 0.0:
			return i
	return -1


func _process(delta: float) -> void:
	for i in CAPACITY:
		if _left[i] > 0.0:
			_left[i] -= delta
			var t := 1.0 - clampf(_left[i] / maxf(_life[i], 0.001), 0.0, 1.0)
			_items[i].scale = Vector3.ONE * lerpf(0.3, 1.0, ease(t, 0.4)) * _size[i]
			_mats[i].albedo_color.a = (1.0 - t * t) * _alpha[i]
			if _left[i] <= 0.0:
				_items[i].visible = false
	for i in SMOKE_SLOTS:
		if _smoke_left[i] > 0.0:
			_smoke_left[i] -= delta
			var t := 1.0 - clampf(_smoke_left[i] / maxf(_smoke_life[i], 0.001), 0.0, 1.0)
			_smoke[i].scale = Vector3.ONE * lerpf(0.4, 1.0, t) * _smoke_size[i]
			_smoke[i].global_position += Vector3.UP * _smoke_rise[i] * delta
			_smoke_mats[i].albedo_color.a = (1.0 - t) * 0.75
			if _smoke_left[i] <= 0.0:
				_smoke[i].visible = false
	for i in LIGHT_SLOTS:
		if _light_left[i] <= 0.0:
			continue
		_light_left[i] -= delta
		_lights[i].light_energy = _light_peak[i] * clampf(_light_left[i] / LIGHT_LIFE, 0.0, 1.0)
		if _light_left[i] <= 0.0:
			_lights[i].light_energy = 0.0
