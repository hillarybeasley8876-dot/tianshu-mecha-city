class_name ParryShards
extends Node3D
## The hex shards a perfect parry throws (r7). The panel flashes and bursts into chips of itself —
## the "shatters" half of the lead's note — instead of only drawing a ring.
##
## Every shard is built ONCE in `_ready()` and recycled: a parry only moves and re-fades them, so a
## parry in the middle of a fight allocates nothing (the engine rule: pre-instance VFX at load). Each
## shard carries its own ShaderMaterial because the fade is per shard, and they all share
## `mirror_shield.gdshader` with the panel so the chips read as pieces of the same surface.

const SHARD_ALPHA := 0.75   ## a chip is nearly solid: it is a fragment, not a field

var _shards: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
var _life: PackedFloat32Array = PackedFloat32Array()
var _vel: Array[Vector3] = []
var _spin: Array[Vector3] = []


func _ready() -> void:
	top_level = true
	var mesh := _chip()
	for i in MirrorShieldProfile.SHARD_COUNT:
		var m := MeshInstance3D.new()
		m.name = "Shard%d" % i
		m.mesh = mesh
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		var mat := MirrorShieldProfile.material()
		if mat != null:
			mat.set_shader_parameter(&"core_alpha", SHARD_ALPHA)
			mat.set_shader_parameter(&"rim_alpha", 1.0)
			mat.set_shader_parameter(&"hex_gain", 0.0)
			mat.set_shader_parameter(&"hex_scale", 2.0)
			mat.set_shader_parameter(&"fade", 0.0)
		m.material_override = mat
		add_child(m)
		_shards.append(m)
		_mats.append(mat)
		_life.append(0.0)
		_vel.append(Vector3.ZERO)
		_spin.append(Vector3.ZERO)


## A flat hexagonal chip — the panel's own silhouette, scaled down to a fragment.
func _chip() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = MirrorShieldProfile.SHARD_SIZE
	mesh.bottom_radius = MirrorShieldProfile.SHARD_SIZE
	mesh.height = MirrorShieldProfile.SHARD_SIZE * 0.28
	mesh.radial_segments = 6
	mesh.rings = 0
	return mesh


## Throws every shard out of `at`, fanned across the plane square-on to `normal`. The direction is
## derived from the index, not from a random number, so a parry looks the same every time and a
## capture can be compared against a previous one.
func burst(at: Vector3, normal: Vector3) -> void:
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.FORWARD
	var basis := Basis.looking_at(n, Vector3.UP)
	for i in _shards.size():
		var a := TAU * float(i) / float(_shards.size())
		var dir := (basis.x * cos(a) + basis.y * sin(a) + n * 0.45).normalized()
		_vel[i] = dir * MirrorShieldProfile.SHARD_SPEED * (0.55 + 0.45 * float(i % 3) * 0.5)
		_spin[i] = Vector3(cos(a * 3.0), sin(a * 2.0), cos(a)) * 9.0
		_life[i] = MirrorShieldProfile.SHARD_LIFE
		var shard := _shards[i]
		shard.global_position = at
		shard.global_basis = basis
		shard.visible = true


## One step of the burst: fly, tumble, fade. A shard whose life ran out is hidden and parked, which
## is what `active()` counts.
func tick(delta: float) -> void:
	for i in _shards.size():
		if _life[i] <= 0.0:
			continue
		_life[i] = maxf(_life[i] - delta, 0.0)
		var shard := _shards[i]
		if _life[i] <= 0.0:
			shard.visible = false
			continue
		shard.global_position += _vel[i] * delta
		_vel[i] *= 1.0 - 2.2 * delta
		shard.rotate_object_local(Vector3.RIGHT, _spin[i].x * delta)
		shard.rotate_object_local(Vector3.UP, _spin[i].y * delta)
		var k := _life[i] / MirrorShieldProfile.SHARD_LIFE
		_mats[i].set_shader_parameter(&"fade", k * k)


## How many shards are in the air right now.
func active() -> int:
	var n := 0
	for l in _life:
		if l > 0.0:
			n += 1
	return n


## How many exist in total — constant for the life of the node, so a test can prove the burst is a
## pool and not a per-parry allocation.
func pool_size() -> int:
	return _shards.size()


func clear() -> void:
	for i in _shards.size():
		_life[i] = 0.0
		_shards[i].visible = false
