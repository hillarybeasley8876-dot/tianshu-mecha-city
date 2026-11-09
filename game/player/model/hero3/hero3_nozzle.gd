class_name Hero3Nozzle
extends RefCounted
## The Tianshu's exhaust mouths, MEASURED off the mesh (hero-v3 r9 item 2).
##
## r8 guessed them: a bone name, a fraction along the bone and a hand-typed `Vector3(±1.5, 0, 0.6)`
## offset, added to a point that was already in a different space. That is why the plumes floated over
## the hero's head and shoulders. Nothing here is typed -- `measure` finds the rearmost face of the
## backpack on each side, takes its centroid as the mouth and its mean surface normal as the exhaust
## axis, and hands both back in the BONE's own frame.
##
## What the mesh actually has, measured (`tests/probe_nozzle.gd`): there is no modelled port anywhere
## on this model. The rearmost surface of the backpack is a broad armour plate (mean radius 1.1-2.1 m,
## normal within 5 deg of straight back), and the rearmost surface of each calf is the calf itself
## (radius 1.0-1.1 m at knee height) -- a leg, not a nozzle. So there are TWO nozzles, both on the
## back frame, and the calf flames are gone rather than floating beside the knees.
##
## The two sides of the shipped mesh are not symmetric (the mouths sit 0.6 m apart in height), so the
## pair is the mean of the two measurements, mirrored. That is the same rule `hero3_bones.py` uses for
## the joints: the mech is a machine, and a symmetric rig keeps the animation honest.

## Metres behind the rearmost vertex of a side that a mouth may still reach.
const BAND := 0.35
## A mouth vertex's normal has to be at least this aligned with the exhaust axis, which cuts the
## pack's side plates and the drone blades out of the measurement.
const NORMAL_MIN := 0.55
## The backpack's own height band, in metres in the 16 m model frame. The drone blades live above it.
const Y_LO := 11.6
const Y_HI := 15.4
## Fewer vertices than this in the band means there is no port on that side.
const MIN_VERTS := 40
## How much of the measured plate radius the flame's own mouth is. The plate is broad armour; the
## exhaust is the middle of it.
const MOUTH_SHARE := 0.42
const FALLBACK_RADIUS := 0.85


## One row per nozzle: `{bone, at, axis, radius}`, `at` and `axis` in the BONE's own rest frame, so a
## `BoneAttachment3D` places them with no further arithmetic.
static func measure(skeleton: Skeleton3D) -> Array[Dictionary]:
	var sides: Array[Dictionary] = []
	for sign: float in [-1.0, 1.0]:
		var found := _side(skeleton, sign)
		if not found.is_empty():
			sides.append(found)
	if sides.size() < 2:
		push_warning("Hero3Nozzle: only %d backpack mouth(s) measured; the plumes will be one-sided"
				% sides.size())
		return sides
	# the mean of the two, mirrored: a symmetric pair on an asymmetric mesh
	var l: Dictionary = sides[0]
	var r: Dictionary = sides[1]
	var at := ((l["at"] as Vector3) + Vector3(-(r["at"] as Vector3).x, (r["at"] as Vector3).y,
			(r["at"] as Vector3).z)) * 0.5
	var axis := ((l["axis"] as Vector3) + Vector3(-(r["axis"] as Vector3).x,
			(r["axis"] as Vector3).y, (r["axis"] as Vector3).z)).normalized()
	var radius := (float(l["radius"]) + float(r["radius"])) * 0.5
	var out: Array[Dictionary] = []
	for sign: float in [-1.0, 1.0]:
		out.append({"bone": String(l["bone"]), "at": Vector3(at.x * sign, at.y, at.z),
				"axis": Vector3(axis.x * sign, axis.y, axis.z).normalized(),
				"radius": radius * MOUTH_SHARE})
	return out


## One side's rearmost face: its centroid, its mean normal and its radius, all in the bone's frame.
static func _side(skeleton: Skeleton3D, sign: float) -> Dictionary:
	var bone_name := "BackFrame"
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		push_error("Hero3Nozzle: the skeleton has no %s, so the backpack has no nozzle" % bone_name)
		return {}
	var rest := skeleton.get_bone_global_rest(bone)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	_gather(skeleton, bone_name, verts, normals)
	if verts.is_empty():
		return {}
	var rear := -INF
	for i in verts.size():
		if _on_side(verts[i], sign):
			rear = maxf(rear, verts[i].z)
	if not is_finite(rear):
		return {}
	var centre := Vector3.ZERO
	var axis := Vector3.ZERO
	var n := 0
	for i in verts.size():
		if not _on_side(verts[i], sign) or verts[i].z < rear - BAND or normals[i].z < NORMAL_MIN:
			continue
		centre += verts[i]
		axis += normals[i]
		n += 1
	if n < MIN_VERTS:
		return {}
	centre /= float(n)
	axis = axis.normalized()
	var radius := 0.0
	for i in verts.size():
		if not _on_side(verts[i], sign) or verts[i].z < rear - BAND or normals[i].z < NORMAL_MIN:
			continue
		radius = maxf(radius, (verts[i] - centre).length())
	return {"bone": bone_name, "at": rest.affine_inverse() * centre,
			"axis": (rest.basis.inverse() * axis).normalized(),
			"radius": maxf(radius, FALLBACK_RADIUS)}


static func _on_side(v: Vector3, sign: float) -> bool:
	return signf(v.x) == sign and v.y >= Y_LO and v.y <= Y_HI


## Every vertex whose dominant bone is `bone_name`, with its rest-pose normal, in SKELETON space.
static func _gather(skeleton: Skeleton3D, bone_name: String, verts: PackedVector3Array,
		normals: PackedVector3Array) -> void:
	var model := skeleton.get_parent().get_parent() as Node3D
	if model == null:
		return
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if bones == null or positions.is_empty() or norms.is_empty():
				continue
			var per := int(bones.size() / positions.size())
			for i in positions.size():
				var best := -1.0
				var top := 0
				for j in per:
					if weights[i * per + j] > best:
						best = weights[i * per + j]
						top = int(bones[i * per + j])
				var idx := mi.skin.get_bind_bone(top)
				if idx < 0:
					idx = skeleton.find_bone(String(mi.skin.get_bind_name(top)))
				if skeleton.get_bone_name(idx) != bone_name:
					continue
				var rest := skeleton.get_bone_global_rest(idx) * mi.skin.get_bind_pose(top)
				verts.append(rest * positions[i])
				normals.append((rest.basis * norms[i]).normalized())
