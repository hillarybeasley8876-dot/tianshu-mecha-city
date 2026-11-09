class_name BeamPool
extends Node3D
## Pooled beam visuals (projectiles unit). One shot is three coaxial cylinders — a hot white core, a
## wide coloured glow and a dim afterglow that lingers — plus a muzzle ring. All unshaded and additive
## with HDR albedo (ART.md: beams #EFFFFF core / #36E2FF glow, Glow threshold 1.2), so a 500 m beam
## still blooms instead of reading as a one-pixel white line. Slots are pre-built; firing never
## allocates.

const CAPACITY := 16
const FADE := 0.12               ## every beam fades out over this long (no hard pop)
const HOLD := 0.02               ## full brightness before the fade starts
const LIGHT_SLOTS := 3
## HDR multipliers (Glow threshold is 1.2): the core clears it and blooms, the wide glow and the
## afterglow stay under it so a stage-2 beam near the camera does not wash the frame out.
const CORE_ENERGY := 1.9
const GLOW_ENERGY := 0.55
const AFTER_ENERGY := 0.18
const RING_ENERGY := 1.6

var _beams: Array[MeshInstance3D] = []
var _core_mats: Array[StandardMaterial3D] = []
var _glow_mats: Array[StandardMaterial3D] = []
var _after_mats: Array[StandardMaterial3D] = []
var _beam_left: PackedFloat64Array = PackedFloat64Array()
var _beam_fade: PackedFloat64Array = PackedFloat64Array()
var _beam_alpha: PackedFloat64Array = PackedFloat64Array()
var _after_left: PackedFloat64Array = PackedFloat64Array()
var _after_life: PackedFloat64Array = PackedFloat64Array()
var _rings: Array[MeshInstance3D] = []
var _ring_mats: Array[StandardMaterial3D] = []
var _ring_left: PackedFloat64Array = PackedFloat64Array()
var _ring_life: PackedFloat64Array = PackedFloat64Array()
var _ring_size: PackedFloat64Array = PackedFloat64Array()
var _ring_alpha: PackedFloat64Array = PackedFloat64Array()
var _lights: Array[OmniLight3D] = []
var _light_left: PackedFloat64Array = PackedFloat64Array()
var _core_mesh := CylinderMesh.new()
var _ring_mesh := TorusMesh.new()
## Largest radii drawn since the last `reset_peaks()` and where the last beam started — the read-only
## window the first-person size tests measure through (lead r5 item 1).
var _ring_peak: float = 0.0
var _glow_peak: float = 0.0
var _beam_from: Vector3 = Vector3.ZERO
var _flash_peak: float = 0.0


func _ready() -> void:
	# World-space pool: every instance transform below is a world position, so the node must not
	# inherit the mech's transform. `weapon_system.tscn` sets top_level; a bare script instance
	# (tests, tools) may not, and then every visual is drawn at player_xf * world_pos.
	if not top_level:
		top_level = true
		global_transform = Transform3D.IDENTITY
	_core_mesh.height = 1.0
	_core_mesh.radial_segments = 10
	_core_mesh.rings = 1
	_core_mesh.cap_top = false
	_core_mesh.cap_bottom = false
	_ring_mesh.inner_radius = 0.88
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 36          ## segments around the ring (few = a visible diamond)
	_ring_mesh.ring_segments = 6
	for i in CAPACITY:
		_beams.append(_make_beam(i))
		_rings.append(_make_slot(&"Ring%d" % i, _ring_mesh, _ring_mats, Color.WHITE, RING_ENERGY))
	_beam_left.resize(CAPACITY)
	_beam_fade.resize(CAPACITY)
	_beam_alpha.resize(CAPACITY)
	_after_left.resize(CAPACITY)
	_after_life.resize(CAPACITY)
	_ring_left.resize(CAPACITY)
	_ring_life.resize(CAPACITY)
	_ring_size.resize(CAPACITY)
	_ring_alpha.resize(CAPACITY)
	for i in LIGHT_SLOTS:
		var l := OmniLight3D.new()
		l.name = "MuzzleLight%d" % i
		l.omni_range = 30.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		add_child(l)
		_lights.append(l)
	_light_left.resize(LIGHT_SLOTS)
	set_process(true)


## Core cylinder with the glow and afterglow layers parented to it (they scale with the core).
func _make_beam(i: int) -> MeshInstance3D:
	var core := _make_slot(&"Beam%d" % i, _core_mesh, _core_mats, Color(0.937, 1.0, 1.0),
			CORE_ENERGY)
	for spec: Array in [[&"Glow", _glow_mats, Color(0.212, 0.886, 1.0), GLOW_ENERGY],
			[&"After", _after_mats, Color(0.35, 0.8, 1.0), AFTER_ENERGY]]:
		var layer := MeshInstance3D.new()
		layer.name = String(spec[0])
		layer.mesh = _core_mesh
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := additive_material(spec[2] as Color, float(spec[3]))
		layer.material_override = mat
		layer.visible = false
		core.add_child(layer)
		(spec[1] as Array).append(mat)
	return core


func _make_slot(nm: StringName, mesh: Mesh, mats: Array[StandardMaterial3D], color: Color,
		energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = String(nm)
	mi.mesh = mesh
	var mat := additive_material(color, energy)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	mats.append(mat)
	return mi


## Unshaded additive material whose albedo is `color` pushed past the glow threshold by `energy`.
static func additive_material(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, color.a)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## Stretch a beam from `from` to `to`. `afterglow` > 0 keeps a dim wide trail alive for that long
## (charged shots). Returns the slot used (-1 when the pool is saturated).
func beam(from: Vector3, to: Vector3, core_radius: float, glow_radius: float, core_color: Color,
		glow_color: Color, life: float, afterglow: float = 0.0, alpha: float = 1.0) -> int:
	var i := _free_beam()
	if i < 0:
		return -1
	var dir := to - from
	var length := dir.length()
	if length < 0.01:
		return -1
	var node := _beams[i]
	node.visible = true
	node.global_transform = Transform3D(axis_basis(dir / length), (from + to) * 0.5)
	node.scale = Vector3(core_radius * 2.0, length, core_radius * 2.0)
	var mat := _core_mats[i]
	mat.albedo_color = Color(core_color.r * CORE_ENERGY, core_color.g * CORE_ENERGY,
			core_color.b * CORE_ENERGY, alpha)
	_beam_left[i] = maxf(life, FADE + HOLD)
	_beam_fade[i] = FADE
	_beam_alpha[i] = alpha
	_beam_from = from
	_glow_peak = maxf(_glow_peak, glow_radius)
	_layer(i, &"Glow", _glow_mats, glow_radius / maxf(core_radius, 0.001), glow_color,
			GLOW_ENERGY, alpha)
	_layer(i, &"After", _after_mats, glow_radius * 1.15 / maxf(core_radius, 0.001), glow_color,
			AFTER_ENERGY, alpha)
	_after_left[i] = maxf(afterglow, 0.0)
	_after_life[i] = maxf(afterglow, 0.001)
	return i


func _layer(i: int, nm: StringName, mats: Array[StandardMaterial3D], width: float, color: Color,
		energy: float, alpha: float) -> void:
	var node := _beams[i].get_node_or_null(NodePath(nm)) as MeshInstance3D
	if node == null:
		return
	node.visible = true
	node.scale = Vector3(width, 1.0, width)
	var mat := mats[i]
	mat.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, alpha)


## Expanding ring at the muzzle (or an impact): `size` is the final radius in metres.
func ring(at: Vector3, normal: Vector3, color: Color, size: float, life: float,
		alpha: float = 1.0) -> int:
	if life <= 0.0:
		# A tuning of 0 means "no ring": without this the slot would be made visible and then never
		# hidden, because _fade_ring returns early on a countdown that starts at 0.
		return -1
	var i := _free(_ring_left)
	if i < 0:
		return -1
	var n := normal if normal.length_squared() > 0.001 else Vector3.UP
	var node := _rings[i]
	node.visible = true
	node.global_transform = Transform3D(axis_basis(n.normalized()), at)
	node.scale = Vector3.ONE * size * 0.15
	var mat := _ring_mats[i]
	mat.albedo_color = Color(color.r * RING_ENERGY, color.g * RING_ENERGY, color.b * RING_ENERGY,
			alpha)
	_ring_left[i] = life
	_ring_life[i] = life
	_ring_size[i] = size
	_ring_alpha[i] = alpha
	_ring_peak = maxf(_ring_peak, size)
	return i


## Largest muzzle / shock ring radius drawn since the last `reset_peaks()` (metres).
func ring_peak_m() -> float:
	return _ring_peak


## Largest flash-light energy requested since the last `reset_peaks()`.
func flash_peak_energy() -> float:
	return _flash_peak


## Largest beam glow radius drawn since the last `reset_peaks()` (metres).
func glow_peak_m() -> float:
	return _glow_peak


## Where the most recent beam started (the first-person path starts it down range).
func last_beam_from() -> Vector3:
	return _beam_from


func reset_peaks() -> void:
	_ring_peak = 0.0
	_glow_peak = 0.0
	_flash_peak = 0.0


## Muzzle flash: the fx unit's pooled lights when it exists, else our own three omni lights.
func flash(at: Vector3, color: Color, energy: float, range_m: float = 30.0,
		frames: float = 3.0) -> void:
	_flash_peak = maxf(_flash_peak, energy)
	if FxBridge.flash(self, at, color, energy, range_m, frames):
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
	l.omni_range = range_m
	l.light_energy = energy
	_light_left[best] = frames / 60.0


func _free(times: PackedFloat64Array) -> int:
	for i in CAPACITY:
		if times[i] <= 0.0:
			return i
	return -1


## A beam slot is only free once its afterglow has aged out too, or reusing it would teleport a
## charged shot's fading trail to the new shot's line.
func _free_beam() -> int:
	for i in CAPACITY:
		if _beam_left[i] <= 0.0 and _after_left[i] <= 0.0:
			return i
	return -1


## Basis whose local +Y points along `y` (cylinders and tori are Y-up meshes).
static func axis_basis(y: Vector3) -> Basis:
	var x := Vector3.UP.cross(y)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT.cross(y)
	x = x.normalized()
	return Basis(x, y, x.cross(y))


func _process(delta: float) -> void:
	for i in CAPACITY:
		_fade_beam(i, delta)
		_fade_ring(i, delta)
	for i in LIGHT_SLOTS:
		if _light_left[i] <= 0.0:
			continue
		_light_left[i] -= delta
		if _light_left[i] <= 0.0:
			_lights[i].light_energy = 0.0


## Hold at full brightness, then fade the last FADE seconds so nothing pops out of existence.
func _fade_beam(i: int, delta: float) -> void:
	if _after_left[i] > 0.0:
		_after_left[i] -= delta
		var a := clampf(_after_left[i] / _after_life[i], 0.0, 1.0)
		_after_mats[i].albedo_color.a = a * 0.8 * _beam_alpha[i]
		if _after_left[i] <= 0.0:
			_after_mats[i].albedo_color.a = 0.0
			(_beams[i].get_node_or_null(^"After") as MeshInstance3D).visible = false
			if _beam_left[i] <= 0.0:
				_beams[i].visible = false
	if _beam_left[i] <= 0.0:
		return
	_beam_left[i] -= delta
	var k := clampf(_beam_left[i] / maxf(_beam_fade[i], 0.001), 0.0, 1.0) * _beam_alpha[i]
	_core_mats[i].albedo_color.a = k
	_glow_mats[i].albedo_color.a = k
	if _beam_left[i] <= 0.0:
		(_beams[i].get_node_or_null(^"Glow") as MeshInstance3D).visible = false
		# The After layer is a child of the core, so the core stays alive (its alpha is already 0)
		# until the afterglow has faded — a charged shot's 0.4 s trail must not pop off with the
		# 0.14 s beam.
		if _after_left[i] <= 0.0:
			_beams[i].visible = false


func _fade_ring(i: int, delta: float) -> void:
	if _ring_left[i] <= 0.0:
		return
	_ring_left[i] -= delta
	var t := 1.0 - clampf(_ring_left[i] / maxf(_ring_life[i], 0.001), 0.0, 1.0)
	_rings[i].scale = Vector3.ONE * lerpf(0.15, 1.0, ease(t, 0.35)) * _ring_size[i]
	_ring_mats[i].albedo_color.a = (1.0 - t) * _ring_alpha[i]
	if _ring_left[i] <= 0.0:
		_rings[i].visible = false
