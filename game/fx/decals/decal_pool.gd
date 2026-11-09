class_name DecalPool
extends Node3D
## Ring buffer of 96 world decals (feel unit). Permanence sells violence (juice-impact rule 11), but
## decals, lights and probes share a 512-element cluster budget per view, so the pool is fixed and the
## oldest decal is recycled. Kinds and sizes come from FEEL.md: scorch (bullet/beam hits),
## scorch_ring (shockcore), land_crater (heavy landings, plunge), bullet_hole (small arms).

const MAX_DECALS := 96
## Short-lived heat glows (a shot landing on a wall) live in their own small ring so they never eat
## a permanent scorch slot: GLOW_DECALS slots, each fading out over GLOW_SECONDS of real time.
const MAX_GLOWS := 32
const GLOW_SECONDS := 0.25
## Footprint in metres per kind (x = width, z = depth, y = projection depth).
const SIZES: Dictionary = {
	&"scorch": Vector3(3.5, 4.0, 3.5),
	&"scorch_ring": Vector3(8.0, 4.0, 8.0),
	&"land_crater": Vector3(8.0, 5.0, 8.0),
	&"bullet_hole": Vector3(0.5, 0.6, 0.5),
	&"impact_glow": Vector3(1.6, 1.2, 1.6),
}

var _decals: Array[Decal] = []
var _next: int = 0
var _glows: Array[Decal] = []
## Seconds left per heat glow, stepped on unscaled game time in _process. -1 = slot not live.
var _glow_left: PackedFloat64Array = PackedFloat64Array()
var _glow_next: int = 0


func _ready() -> void:
	# PAUSABLE (not inherited ALWAYS): decals and heat glows must not expire behind the pause menu.
	for i in MAX_DECALS:
		var d := _make_decal("Decal%d" % i, 1.0)
		add_child(d)
		_decals.append(d)
	for i in MAX_GLOWS:
		var g := _make_decal("Glow%d" % i, 0.0)
		add_child(g)
		_glows.append(g)
		_glow_left.append(-1.0)


func _make_decal(decal_name: String, albedo_mix: float) -> Decal:
	var d := Decal.new()
	d.name = decal_name
	d.size = Vector3(2.0, 3.0, 2.0)
	d.upper_fade = 0.4
	d.lower_fade = 0.3
	d.normal_fade = 0.35
	d.distance_fade_enabled = true
	d.distance_fade_begin = 180.0
	d.distance_fade_length = 60.0
	d.cull_mask = 1
	d.albedo_mix = albedo_mix
	if albedo_mix <= 0.0:
		# A heat glow adds light to the surface instead of painting over it.
		d.modulate = Color(1.0, 0.8, 0.55, 1.0)
		d.emission_energy = 1.0
	d.visible = false
	return d


## Stamp `kind` on the surface at `at` whose normal is `normal`. Returns false for unknown kinds.
func add(kind: StringName, at: Vector3, normal: Vector3 = Vector3.UP, scale: float = 1.0,
		modulate: Color = Color.WHITE) -> bool:
	var base: Variant = SIZES.get(kind)
	if base == null:
		push_warning("DecalPool: unknown decal kind %s" % kind)
		return false
	var transient := kind == &"impact_glow"
	var d: Decal = _glows[_glow_next] if transient else _decals[_next]
	if transient:
		_glow_next = (_glow_next + 1) % _glows.size()
	else:
		_next = (_next + 1) % _decals.size()
	var n := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	var ref := Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(n).normalized()
	# A Decal projects along its local -Y, so the node's +Y points away from the surface.
	var basis := Basis(x, n, x.cross(n).normalized())
	basis = basis.rotated(n, randf() * TAU)
	d.global_transform = Transform3D(basis, at + n * 0.05)
	d.size = (base as Vector3) * maxf(scale, 0.05)
	d.texture_albedo = DecalTextures.albedo(kind)
	d.modulate = modulate if not transient else Color(1.0, 0.82, 0.55, 1.0)
	d.visible = true
	if transient:
		var slot := (_glow_next + _glows.size() - 1) % _glows.size()
		_glow_left[slot] = GLOW_SECONDS
	return true


## The heat glows fade on unscaled game time, so they still die during a hit-stop (juice-impact rule 4)
## but not four times too fast under movie capture, and not across a pause.
func _process(delta: float) -> void:
	var dt := minf(Feel.real_delta(delta), 0.1)
	for i in _glows.size():
		var g := _glows[i]
		if not g.visible or _glow_left[i] < 0.0:
			continue
		_glow_left[i] = maxf(_glow_left[i] - dt, 0.0)
		var k := clampf(_glow_left[i] / GLOW_SECONDS, 0.0, 1.0)
		if k <= 0.0:
			g.visible = false
			_glow_left[i] = -1.0
		else:
			g.modulate.a = k * k


func active_count() -> int:
	var n := 0
	for d in _decals:
		if d.visible:
			n += 1
	return n


func glow_count() -> int:
	var n := 0
	for d in _glows:
		if d.visible:
			n += 1
	return n


func clear() -> void:
	for d in _decals:
		d.visible = false
	for i in _glows.size():
		_glows[i].visible = false
		_glow_left[i] = -1.0
	_next = 0
	_glow_next = 0
