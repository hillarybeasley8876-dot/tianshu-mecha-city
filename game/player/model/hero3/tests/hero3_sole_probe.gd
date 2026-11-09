class_name Hero3SoleProbe
extends RefCounted
## CPU skinning of the mech's FEET, for the gates that ask where the sole actually IS (hero-v3 r9).
##
## `test_hero3_skin.gd` grew its own copy of this; both now ask here so a change to the mesh (a new
## toe plate, a different vertex stride) is one edit. Only Foot and Toe pieces are collected: the
## arms, the back frame and the drones cannot touch the floor, and skinning the whole 160k-tri body
## every tick would make the gate unusable.

## Every Nth vertex. The sole has thousands; only the extremes matter and a stride of 2 already
## finds them (measured: stride 1 and stride 2 agree to 1 mm on the deepest vertex).
const VSTRIDE := 2

## One row per sampled vertex: `[Vector3 pos, PackedInt32Array [bone, bind]*, PackedFloat32Array, side, MeshInstance3D]`.
var verts: Array = []
var skeleton: Skeleton3D


func setup(skel: Skeleton3D) -> void:
	skeleton = skel
	verts.clear()
	var model := skel.get_parent().get_parent() as Node3D
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin == null or mi.mesh == null:
			continue
		var bind_bone := PackedInt32Array()
		for b in mi.skin.get_bind_count():
			var bone := mi.skin.get_bind_bone(b)
			if bone < 0:
				bone = skel.find_bone(String(mi.skin.get_bind_name(b)))
			bind_bone.append(bone)
		for s in mi.mesh.get_surface_count():
			_collect_surface(mi, s, bind_bone)


## Each side's lowest skinned FOOT/TOE vertex this instant, in WORLD space, as `[{y, at}, {y, at}]`
## (`y` is `INF` and `at` the origin when that side has no vertex, which the shipping mesh never is).
## The position matters as much as the height: the floor ray has to be cast under the FOOT, not under
## the hip, or a mech straddling a kerb is measured against the wrong slab.
func sample() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"y": INF, "at": Vector3.ZERO}, {"y": INF, "at": Vector3.ZERO}]
	var xf := skeleton.global_transform
	var cache := {}
	for row in verts:
		var mi: MeshInstance3D = row[4]
		var binds: PackedInt32Array = row[1]
		var wts: PackedFloat32Array = row[2]
		var p := Vector3.ZERO
		for j in wts.size():
			var key := Vector2i(mi.get_instance_id() % 100000, binds[j * 2 + 1])
			if not cache.has(key):
				cache[key] = skeleton.get_bone_global_pose(binds[j * 2]) \
						* mi.skin.get_bind_pose(binds[j * 2 + 1])
			p += (cache[key] as Transform3D) * (row[0] as Vector3) * wts[j]
		var w := xf * p
		var i := 0 if String(row[3]) == "L" else 1
		if w.y < float(out[i]["y"]):
			out[i] = {"y": w.y, "at": w}
	return out


func _collect_surface(mi: MeshInstance3D, surface: int, bind_bone: PackedInt32Array) -> void:
	var arrays := mi.mesh.surface_get_arrays(surface)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if bones == null or positions.is_empty():
		return
	var per := int(bones.size() / positions.size())
	for i in range(0, positions.size(), VSTRIDE):
		var best := -1.0
		var side := ""
		var binds := PackedInt32Array()
		var wts := PackedFloat32Array()
		for j in per:
			var w := weights[i * per + j]
			if w <= 0.0:
				continue
			var b := int(bones[i * per + j])
			binds.append(bind_bone[b])
			binds.append(b)
			wts.append(w)
			if w > best:
				best = w
				side = skeleton.get_bone_name(bind_bone[b])
		if not (side.contains("Foot") or side.contains("Toe")):
			continue
		if not (side.begins_with("L_") or side.begins_with("R_")):
			continue
		verts.append([positions[i], binds, wts, side.substr(0, 1), mi])
