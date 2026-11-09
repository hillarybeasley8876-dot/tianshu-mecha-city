class_name CasingPool
extends Node3D
## Spent casings for the gatling (projectiles unit): one MultiMesh, ballistic arcs, no physics bodies.
## Casings are pure decoration, so they are capped and recycled — a long burst can never grow the pool.
##
## Camera mode (lead r6): a casing is a 1.25 m orange box and the cockpit lens sits ~6 m from the
## ejection port, so at third-person scale it is a car door sliding across the canopy. In first person
## it is drawn at FP_SCALE, thrown away from the lens at FP_SPEED and not drawn at all inside FP_HIDE
## of the eye. Third person takes none of those branches and is identical to r5.

const CAPACITY := 96
const GRAVITY := 25.5         ## the hero's fall gravity (SPEC §4), so casings drop at mech scale
const LIFE := 1.6
const BOUNCE := 0.35
const SIZE := Vector3(0.42, 0.42, 1.25)   ## m, sized for the 42 m third-person arm
## Mirrors WeaponContext.FP_SCALE (a casing is not a WeaponContext, so the constant is restated here
## rather than imported across a cyclic class reference; `fp_near.fp_scale_agrees_with_the_context`
## fails if the two ever drift apart).
const FP_SCALE := 0.27
const FP_SPEED := 1.8         ## 14 -> 25 m/s: a casing leaves the 8 m canopy zone in ~0.1 s
const FP_HIDE := 4.0          ## m from the lens: closer than this it is not drawn at all
const FP_THROW := Vector3(0.0, -0.6, 0.0)   ## in the cockpit the throw is down and outboard

var _mmi: MultiMeshInstance3D
var _pos: PackedVector3Array = PackedVector3Array()
var _vel: PackedVector3Array = PackedVector3Array()
var _spin: PackedVector3Array = PackedVector3Array()
var _rot: PackedVector3Array = PackedVector3Array()
var _left: PackedFloat64Array = PackedFloat64Array()
var _scale: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0
var _count: int = 0
var ejected: int = 0
## Camera mode, pushed by the WeaponSystem every tick (it owns the AimSystem read).
var first_person: bool = false
var lens: Vector3 = Vector3.ZERO
## Casings currently suppressed by the near-lens rule — read by the first-person suite.
var hidden_near: int = 0
## Near-lens recording (lead r6). The headless dummy renderer `tools/godot.sh test` runs under does
## NOT keep MultiMesh instance transforms — `set_instance_transform` followed by
## `get_instance_transform` returns identity, measured — so the first-person scan cannot read the
## buffer back. Each pool instead notes what it writes, and only while `recording` is on, so the game
## and the perf suite pay nothing for it.
var recording: bool = false
var _recorded: Array[Dictionary] = []


func _ready() -> void:
	# World-space pool: every instance transform below is a world position, so the node must not
	# inherit the mech's transform. `weapon_system.tscn` sets top_level; a bare script instance
	# (tests, tools) may not, and then every visual is drawn at player_xf * world_pos.
	if not top_level:
		top_level = true
		global_transform = Transform3D.IDENTITY
	var mesh := BoxMesh.new()
	mesh.size = SIZE

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.68, 0.32)
	mat.metallic = 0.9
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.5, 0.15)
	mat.emission_energy_multiplier = 0.3
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = CAPACITY
	mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Casings"
	_mmi.multimesh = mm
	_mmi.material_override = mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	_pos.resize(CAPACITY)
	_vel.resize(CAPACITY)
	_spin.resize(CAPACITY)
	_rot.resize(CAPACITY)
	_left.resize(CAPACITY)
	_scale.resize(CAPACITY)
	_scale.fill(1.0)
	set_physics_process(true)


## Eject one casing from `at`, thrown along `dir` (already randomised by the caller).
func eject(at: Vector3, dir: Vector3, speed: float) -> void:
	var i := _next
	_next = (_next + 1) % CAPACITY
	_count = mini(_count + 1, CAPACITY)
	_pos[i] = at
	_scale[i] = FP_SCALE if first_person else 1.0
	var jitter := Vector3(randf_range(-0.14, 0.14), randf_range(-0.08, 0.26), randf_range(-0.14, 0.14))
	var d := dir
	var v := speed
	if first_person:
		d = _fp_dir(at, dir)
		v = speed * FP_SPEED
	_vel[i] = (d.normalized() + jitter).normalized() * v * randf_range(0.8, 1.2)
	_spin[i] = Vector3(randf_range(-14.0, 14.0), randf_range(-14.0, 14.0), randf_range(-14.0, 14.0))
	_rot[i] = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	_left[i] = LIFE
	ejected += 1


## Cockpit throw: the side-and-up kick the third-person camera reads as an arc sends the casing
## straight across the canopy from inside, so it is bent outboard along the lens -> port ray and
## pushed down, away from the eye.
func _fp_dir(at: Vector3, dir: Vector3) -> Vector3:
	var away := at - lens
	var out := away.normalized() if away.length_squared() > 0.01 else Vector3.DOWN
	return (dir.normalized() * 0.5 + out + FP_THROW).normalized()


## Longest edge of a casing as it is drawn right now (metres): 1.25 m in third person, 0.34 m in the
## cockpit. The first-person gate reads this instead of guessing at the mesh.
func drawn_length() -> float:
	return SIZE.z * (FP_SCALE if first_person else 1.0)


func _physics_process(delta: float) -> void:
	if _count == 0:
		return
	var mm := _mmi.multimesh
	var live := 0
	hidden_near = 0
	for i in _count:
		if _left[i] <= 0.0:
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, -10000.0, 0.0)))
			continue
		live += 1
		_left[i] -= delta
		var v := _vel[i]
		v.y -= GRAVITY * delta
		var p := _pos[i] + v * delta
		if p.y < 0.2 and v.y < 0.0:   # cheap floor bounce, no body needed
			p.y = 0.2
			v.y = -v.y * BOUNCE
			v.x *= 0.7
			v.z *= 0.7
		_pos[i] = p
		_vel[i] = v
		_rot[i] += _spin[i] * delta
		if first_person and p.distance_to(lens) < FP_HIDE:
			hidden_near += 1
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, -10000.0, 0.0)))
			continue
		var b := Basis.from_euler(_rot[i]).scaled(Vector3.ONE * _scale[i])
		var xf := Transform3D(b, p)
		mm.set_instance_transform(i, xf)
		var fade := clampf(_left[i] / 0.4, 0.0, 1.0)
		mm.set_instance_color(i, Color(1.0, 0.85, 0.55, fade))
		_note(xf, SIZE, Color(1.0, 0.85, 0.55, fade), _mmi.material_override)
	mm.visible_instance_count = _count if live > 0 else 0


## Start a recording window (the near-lens scan calls this before it awaits a physics frame).
func begin_record() -> void:
	_recorded.clear()


## Every instance drawn since the last `begin_record()`, exactly as it went into the MultiMesh.
func drawn() -> Array[Dictionary]:
	return _recorded


func _note(xf: Transform3D, size: Vector3, tint: Color, mat: Material) -> void:
	if recording:
		_recorded.append({"xf": xf, "size": size, "tint": tint, "mat": mat, "kind": "box",
				"label": "Casings"})

