class_name DebrisPool
extends Node3D
## Pooled debris chunks (feel unit): armour shards, rubble and shell casings. Permanence sells
## violence (juice-impact rule 11), so chunks are real RigidBody3D on Layers.DEBRIS that bounce once,
## then sleep, fade and go back to the pool after LIFETIME seconds. Nothing is ever instantiated at
## shot time: the whole pool and its four procedural chunk meshes (fx/vfx/debris_chunk.gd) are built
## in _ready. Chunks are textured by fx/vfx/rock.gdshader and trail a shared dust emitter.

const ROCK := preload("res://fx/vfx/rock.gdshader")
const MAX_CHUNKS := 64
const LIFETIME := 6.0
const FADE := 0.6
const UP := Vector3(0.0, 1.0, 0.0)
## ART.md §2: warm concrete and brushed steel; a scorched variant for explosion debris.
const CONCRETE := Color(0.38, 0.36, 0.33)
const STEEL := Color(0.26, 0.28, 0.31)

var _bodies: Array[RigidBody3D] = []
var _mats: Array[ShaderMaterial] = []
## Age in game seconds, accumulated from the plain physics delta the chunks are simulated on:
## a wall-clock age would fade rubble in mid-air during a movie capture and expire it across a pause.
var _age: PackedFloat64Array = PackedFloat64Array()
var _live: PackedByteArray = PackedByteArray()
var _next: int = 0
var _trail: GPUParticles3D


func _ready() -> void:
	var meshes: Array[ArrayMesh] = []
	for v in FxDebrisChunk.VARIANTS:
		meshes.append(FxDebrisChunk.build(v, 0.5))
	for i in MAX_CHUNKS:
		_bodies.append(_make_body(i, meshes[i % meshes.size()]))
		_age.append(0.0)
		_live.append(0)
	_trail = VfxPresets.build_dust(24, 1.1, 2.0, 0.22)
	_trail.name = "Trail"
	_trail.one_shot = false
	_trail.explosiveness = 0.0
	_trail.emitting = false
	add_child(_trail)


func _make_body(index: int, mesh: ArrayMesh) -> RigidBody3D:
	var mat := ShaderMaterial.new()
	mat.shader = ROCK
	mat.set_shader_parameter(&"tint", CONCRETE)
	mat.set_shader_parameter(&"grit_color", Color(0.3, 0.28, 0.27))
	var view := MeshInstance3D.new()
	view.name = "Mesh"
	view.mesh = mesh
	view.material_override = mat
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var shape := ConvexPolygonShape3D.new()
	shape.points = _hull_points(mesh)
	var body := RigidBody3D.new()
	body.name = "Chunk%d" % index
	body.mass = 40.0
	body.collision_layer = Layers.DEBRIS
	body.collision_mask = Layers.WORLD | Layers.PROPS
	body.contact_monitor = false
	body.max_contacts_reported = 0
	body.visible = false
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.freeze = true
	body.add_child(view)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	add_child(body)
	_mats.append(mat)
	return body


## Throw `count` chunks out of `at`. `size` is the chunk edge in metres (0.5-4 m at mech scale),
## `speed` the launch speed. `metal` picks the brushed-steel tint instead of concrete.
func burst(at: Vector3, count: int, speed: float, size: float = 0.8, metal: bool = false) -> void:
	for i in maxi(count, 0):
		var slot := _take()
		var body := _bodies[slot]
		var s := clampf(size * randf_range(0.55, 1.7), 0.4, 4.5)
		body.scale = Vector3(s, s * randf_range(0.5, 1.0), s * randf_range(0.6, 1.3))
		body.freeze = false
		body.visible = true
		body.global_position = at + Vector3(randf_range(-1.0, 1.0), randf_range(0.0, 1.5),
				randf_range(-1.0, 1.0)) * size
		body.linear_velocity = (UP * randf_range(0.6, 1.4) + Vector3(randf_range(-1.0, 1.0), 0.0,
				randf_range(-1.0, 1.0)).normalized() * 0.8) * speed * randf_range(0.6, 1.3)
		body.angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0),
				randf_range(-6.0, 6.0))
		_mats[slot].set_shader_parameter(&"tint", STEEL if metal else CONCRETE)
		_mats[slot].set_shader_parameter(&"fade", 1.0)
		_age[slot] = 0.0
		_live[slot] = 1
	_trail.global_position = at
	_trail.scale = Vector3.ONE * clampf(size, 0.5, 4.0)
	_trail.emitting = true


func live_count() -> int:
	var n := 0
	for v in _live:
		n += v
	return n


## Age in game seconds of the oldest live chunk (tests read this to pin the clock).
func oldest_age() -> float:
	var out := 0.0
	for i in _bodies.size():
		if _live[i] == 1:
			out = maxf(out, _age[i])
	return out


## Drop every chunk (scene change, tests).
func clear() -> void:
	for i in _bodies.size():
		_release(i)
	_trail.emitting = false


func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	var centroid := Vector3.ZERO
	var live := 0
	for i in _bodies.size():
		if _live[i] == 0:
			continue
		_age[i] += dt
		var age := _age[i]
		centroid += _bodies[i].global_position
		live += 1
		if age < LIFETIME - FADE:
			if _bodies[i].sleeping:
				_bodies[i].freeze = true
			continue
		var k := clampf((LIFETIME - age) / FADE, 0.0, 1.0)
		_mats[i].set_shader_parameter(&"fade", k)
		if k <= 0.0:
			_release(i)
	# One shared trail emitter follows the debris instead of 64 per-chunk emitters.
	if live > 0:
		_trail.global_position = centroid / float(live)
	else:
		_trail.emitting = false


func _take() -> int:
	for i in _bodies.size():
		var slot := (_next + i) % _bodies.size()
		if _live[slot] == 0:
			_next = (slot + 1) % _bodies.size()
			return slot
	var slot := _next
	_next = (_next + 1) % _bodies.size()
	_release(slot)
	return slot


func _release(slot: int) -> void:
	_live[slot] = 0
	_bodies[slot].visible = false
	_bodies[slot].freeze = true
	_bodies[slot].linear_velocity = Vector3.ZERO
	_bodies[slot].angular_velocity = Vector3.ZERO


## Convex hull points for the collision shape, taken straight from the chunk's own vertices.
func _hull_points(mesh: ArrayMesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		if out.size() >= 32:
			break
		out.append(verts[i])
	return out
