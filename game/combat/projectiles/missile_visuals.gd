class_name MissileVisuals
extends Node3D
## Itano circus rendering for the Hailstorm swarm (projectiles unit): four MultiMeshes for the whole
## swarm, so 24 missiles plus their history cost four draw calls.
##
##   bodies  small missile hulls, oriented along flight
##   flares  billboard engine flare at each head (bright, additive, flickering)
##   core    tapered additive ribbon: wide and hot at the missile, thin at the tail
##   smoke   soft grey-white lit puffs that linger SMOKE_LIFE seconds and widen x3
##
## The position history is kept here (it is a rendering concern): the manager pushes samples while a
## missile flies, and `retire()` leaves the smoke behind to age out on its own.

const CAPACITY := 24
const SAMPLES := 20              ## smoke history per missile (SAMPLES * SAMPLE_DT = 1.5 s)
const SAMPLE_DT := 0.075
const CORE_SEG := 8              ## ribbon uses the newest samples
const CORE_LIFE := CORE_SEG * SAMPLE_DT   ## a dead missile's ribbon fades with its samples
const SMOKE_LIFE := 1.5
const CORE_WIDTH := 0.9
const SMOKE_SIZE := 4.2
const FLARE_SIZE := 3.6
const BODY_LENGTH := 5.0
const BODY_RADIUS := 0.55
const CORE_COLOR := Color(0.45, 0.85, 1.0)
const FLARE_COLOR := Color(1.0, 0.78, 0.42)
## Cockpit scale (lead r6). A missile leaves a shoulder rail ~5 m from the first-person lens, where a
## 3.6 m engine flare is an orange slab across the canopy. Mirrors WeaponContext.FP_SCALE — restated
## rather than imported across a cyclic class reference; `fp_near.fp_scale_agrees_with_the_context`
## fails if the two drift apart.
const FP_SCALE := 0.27
const FP_HIDE := 5.0           ## m from the lens: nothing of the circus is drawn at all
const FP_NEAR := 14.0          ## m: drawn at FP_SCALE from here in
const FP_FAR := 40.0           ## m: full third-person size again by here

## Camera mode, pushed by the WeaponSystem every tick (it owns the AimSystem read).
var first_person: bool = false
var lens: Vector3 = Vector3.ZERO
## Largest scale any part of the circus was drawn at since the last `reset_peaks()` — the window the
## first-person suite measures the near-lens rule through.
var _scale_peak: float = 0.0
## Near-lens recording (lead r6): the headless dummy renderer keeps no MultiMesh instance transforms,
## so the first-person scan reads what this pool writes instead of reading the buffer back. Off in the
## game and in the perf suite, where the write sites cost one branch.
var recording: bool = false
var _recorded: Array[Dictionary] = []

var _now: float = 0.0
var _pts: Array[PackedVector3Array] = []
var _times: Array[PackedFloat64Array] = []
var _head: PackedInt32Array = PackedInt32Array()
var _filled: PackedInt32Array = PackedInt32Array()
var _last: PackedFloat64Array = PackedFloat64Array()
var _bodies: MultiMeshInstance3D
var _flares: MultiMeshInstance3D
var _core: MultiMeshInstance3D
var _smoke: MultiMeshInstance3D
var _parked := Transform3D(Basis.IDENTITY, Vector3(0.0, -100000.0, 0.0))


func _ready() -> void:
	# World-space pool (see MissileManager): instance transforms below are world positions.
	if not top_level:
		top_level = true
		global_transform = Transform3D.IDENTITY
	_head.resize(CAPACITY)
	_filled.resize(CAPACITY)
	_last.resize(CAPACITY)
	for i in CAPACITY:
		var p := PackedVector3Array()
		p.resize(SAMPLES)
		_pts.append(p)
		var t := PackedFloat64Array()
		t.resize(SAMPLES)
		# Unwritten history slots are "infinitely old", not "written at t=0": while _now < SMOKE_LIFE
		# a zeroed sample would age in and draw its puff at the pool origin.
		t.fill(-1.0e9)
		_times.append(t)
	var hull := CylinderMesh.new()
	hull.height = 1.0
	hull.top_radius = 0.0
	hull.bottom_radius = 1.0
	hull.radial_segments = 6
	hull.rings = 1
	_bodies = _mesh(&"Bodies", hull, false, Color(0.9, 0.9, 0.95), CAPACITY, 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_flares = _mesh(&"Flares", quad, true, FLARE_COLOR, CAPACITY, 3.0, false, true)
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	_core = _mesh(&"CoreTrails", box, true, CORE_COLOR, CAPACITY * CORE_SEG, 0.95)
	_smoke = _mesh(&"SmokeTrails", quad, false, Color(0.84, 0.86, 0.9),
			CAPACITY * SAMPLES, 1.0, true)


func _mesh(nm: StringName, mesh: Mesh, additive: bool, color: Color, count: int, energy: float,
		soft: bool = false, billboard: bool = false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mat: StandardMaterial3D
	if additive:
		mat = BeamPool.additive_material(color, energy)
	else:
		mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.9
		if soft:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_texture = FxBridge.soft_disc_texture()
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mat.billboard_keep_scale = true   ## without it every instance collapses to 1x1 m
	mat.vertex_color_use_as_albedo = true
	if billboard:   ## flares only: the core ribbon must keep its own orientation
		mat.albedo_texture = FxBridge.soft_disc_texture()   ## a bare additive quad reads as a square
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
	var node := MultiMeshInstance3D.new()
	node.name = String(nm)
	node.multimesh = mm
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	for i in count:
		mm.set_instance_transform(i, _parked)
		mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))
	return node


## Start a fresh history for slot `i`.
func launch(i: int, at: Vector3) -> void:
	_head[i] = 0
	_filled[i] = 1
	_last[i] = _now
	_pts[i][0] = at
	_times[i][0] = _now


## Advance the clock and start a frame of writes.
func begin(delta: float) -> void:
	_now += delta


## Record a position sample (throttled to SAMPLE_DT).
func sample(i: int, at: Vector3) -> void:
	if _now - _last[i] < SAMPLE_DT:
		return
	_last[i] = _now
	var h := (_head[i] + 1) % SAMPLES
	_head[i] = h
	_pts[i][h] = at
	_times[i][h] = _now
	_filled[i] = mini(_filled[i] + 1, SAMPLES)


## Hull + engine flare for a flying missile.
func body(i: int, at: Vector3, dir: Vector3) -> void:
	var back := at - dir * BODY_LENGTH * 0.5
	var hull := _near_scale(at)
	var flare := _near_scale(back)
	if hull <= 0.0:
		_bodies.multimesh.set_instance_transform(i, _parked)
	else:
		var b := BeamPool.axis_basis(dir)
		var xf := Transform3D(b, at).scaled_local(
				Vector3(BODY_RADIUS, BODY_LENGTH, BODY_RADIUS) * hull)
		_bodies.multimesh.set_instance_transform(i, xf)
		_bodies.multimesh.set_instance_color(i, Color(1.0, 0.96, 0.9, 1.0))
		_note(xf, Vector3.ONE, Color(1.0, 0.96, 0.9, 1.0), _bodies.material_override,
				"cylinder", "Bodies")
	if flare <= 0.0:
		_flares.multimesh.set_instance_transform(i, _parked)
		return
	var flicker := 0.85 + 0.15 * sin(_now * 47.0 + float(i) * 2.1)
	var fxf := Transform3D(Basis.IDENTITY, back).scaled_local(
			Vector3.ONE * FLARE_SIZE * flicker * flare)
	_flares.multimesh.set_instance_transform(i, fxf)
	_flares.multimesh.set_instance_color(i, Color(FLARE_COLOR * flicker, 1.0))
	_note(fxf, Vector3.ONE, Color(FLARE_COLOR * flicker, 1.0), _flares.material_override,
			"quad", "Flares")


## How big a circus visual at `at` may be drawn: 1.0 in third person, FP_SCALE while it is close to the
## cockpit lens and 0 (not drawn) inside FP_HIDE, ramping back to full size by FP_FAR so the swarm
## still reads as a swarm once it is out over the street.
func _near_scale(at: Vector3) -> float:
	if not first_person:
		return 1.0
	var d := at.distance_to(lens)
	if d < FP_HIDE:
		return 0.0
	var s := lerpf(FP_SCALE, 1.0, clampf((d - FP_NEAR) / (FP_FAR - FP_NEAR), 0.0, 1.0))
	_scale_peak = maxf(_scale_peak, s)
	return s


## Largest near-lens scale applied since the last `reset_peaks()` (1.0 = untouched third-person size).
func scale_peak() -> float:
	return _scale_peak


func reset_peaks() -> void:
	_scale_peak = 0.0


## The missile is gone: park hull and flare, keep the smoke.
func retire(i: int) -> void:
	_bodies.multimesh.set_instance_transform(i, _parked)
	_flares.multimesh.set_instance_transform(i, _parked)


## How many of slot `i`'s history samples are young enough to draw a smoke puff. Read by the
## regression suite: a slot that was never written must count 0, not 19 puffs at the pool origin.
func live_samples(i: int) -> int:
	var n := 0
	for s in SAMPLES:
		var idx := (_head[i] - s + SAMPLES * 2) % SAMPLES
		if _now - _times[i][idx] <= SMOKE_LIFE:
			n += 1
	return n


## Park everything (pool reset, tests).
func clear() -> void:
	for i in CAPACITY:
		_filled[i] = 0
		_times[i].fill(-1.0e9)
		retire(i)
		for s in SAMPLES:
			_smoke.multimesh.set_instance_transform(i * SAMPLES + s, _parked)
			if s < CORE_SEG:
				_core.multimesh.set_instance_transform(i * CORE_SEG + s, _parked)
	flush(0)


## Write the ribbons and publish the visible counts. `live` = missiles still in the air.
func flush(live: int) -> void:
	var core_mm := _core.multimesh
	var smoke_mm := _smoke.multimesh
	var any := live > 0
	for i in CAPACITY:
		if _filled[i] == 0:
			continue
		if _trail(i, core_mm, smoke_mm):
			any = true
	_bodies.multimesh.visible_instance_count = CAPACITY if live > 0 else 0
	_flares.multimesh.visible_instance_count = CAPACITY if live > 0 else 0
	core_mm.visible_instance_count = CAPACITY * CORE_SEG if any else 0
	smoke_mm.visible_instance_count = CAPACITY * SAMPLES if any else 0


## One missile's core ribbon and smoke. Returns true when anything is still visible.
func _trail(i: int, core_mm: MultiMesh, smoke_mm: MultiMesh) -> bool:
	var head := _head[i]
	var from := _pts[i][head]
	var visible := false
	for s in SAMPLES:
		var idx := (head - s + SAMPLES * 2) % SAMPLES
		var age := _now - _times[i][idx]
		var to := _pts[i][idx]
		_smoke_at(i * SAMPLES + s, smoke_mm, to, age)
		visible = visible or age <= SMOKE_LIFE
		if s < CORE_SEG:
			var seg := from - to
			var length := seg.length()
			var cidx := i * CORE_SEG + s
			var wide := _near_scale(to)
			if length < 0.05 or s >= _filled[i] or age > CORE_LIFE or wide <= 0.0:
				core_mm.set_instance_transform(cidx, _parked)
			else:
				var k := 1.0 - float(s) / float(CORE_SEG)
				var w := (CORE_WIDTH * k + 0.12) * wide
				var xf := Transform3D(
						ShotQuery.aligned_basis(seg / length), (from + to) * 0.5).scaled_local(
						Vector3(w, w, length))
				core_mm.set_instance_transform(cidx, xf)
				core_mm.set_instance_color(cidx, Color(CORE_COLOR, k * k))
				_note(xf, Vector3.ONE, Color(CORE_COLOR, k * k), _core.material_override, "box", "CoreTrails")
			from = to
	return visible


## One smoke puff: grows to 3x over SMOKE_LIFE and fades out.
func _smoke_at(idx: int, mm: MultiMesh, at: Vector3, age: float) -> void:
	var near := _near_scale(at)
	if age > SMOKE_LIFE or age < 0.0 or near <= 0.0:
		mm.set_instance_transform(idx, _parked)
		return
	var t := age / SMOKE_LIFE
	var size := SMOKE_SIZE * lerpf(1.0, 3.0, t) * near
	var xf := Transform3D(Basis.IDENTITY, at + Vector3.UP * age * 1.2).scaled_local(
			Vector3.ONE * size)
	mm.set_instance_transform(idx, xf)
	mm.set_instance_color(idx, Color(0.86, 0.88, 0.92, (1.0 - t) * 0.7))
	_note(xf, Vector3.ONE, Color(0.86, 0.88, 0.92, (1.0 - t) * 0.7),
			_smoke.material_override, "quad", "SmokeTrails")


## Start a recording window (the near-lens scan calls this before it awaits a physics frame).
func begin_record() -> void:
	_recorded.clear()


## Every instance drawn since the last `begin_record()`, exactly as it went into the MultiMeshes.
func drawn() -> Array[Dictionary]:
	return _recorded


func _note(xf: Transform3D, size: Vector3, tint: Color, mat: Material, kind: String,
		label: String) -> void:
	if recording:
		_recorded.append({"xf": xf, "size": size, "tint": tint, "mat": mat, "kind": kind,
				"label": label})
