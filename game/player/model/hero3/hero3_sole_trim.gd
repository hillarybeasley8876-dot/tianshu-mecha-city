class_name Hero3SoleTrim
extends RefCounted
## How far each foot's armour reaches BELOW the model origin (hero-v3 r9 item 1).
##
## CONTRACTS §5 puts the model origin between the feet, and `Hero3Frame.ground()` takes the skeleton
## node's world y as the floor the gait plants on. That is only the same plane if the lowest vertex of
## each foot sits exactly ON the origin -- and on the shipped mesh it does not: measured, the left
## foot's lowest toe vertex is 0.145 m below it and the right foot's is 0.024 m. So the mech stood
## with one foot buried 14 cm into the floor and the other 12 cm off it, and the ground lock cannot
## fix that, because the ground lock is the plane the fault is measured FROM.
##
## The trim is MEASURED off the mesh at load, never typed: the rest position of a vertex is its bind
## pose applied to it, so this is one transform per vertex and no skinning at all. A remesh, a new
## boot plate or a different Tripo result moves the numbers by themselves.

## Bones whose armour can touch the floor.
const SOLE_BONES: Array[String] = ["Foot", "Toe"]


## `[left, right]`: metres from the model origin DOWN to the lowest vertex of that side's foot in the
## rest pose. Never negative -- a mesh whose origin is already under the sole needs no trim.
static func measure(skeleton: Skeleton3D) -> Array[float]:
	var model := skeleton.get_parent().get_parent() as Node3D
	if model == null:
		push_error("Hero3SoleTrim: the skeleton has no model above it; the sole trim cannot be measured")
		return [0.0, 0.0]
	var low: Array[float] = [INF, INF]
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin == null or mi.mesh == null:
			continue
		var bind_bone := PackedInt32Array()
		for b in mi.skin.get_bind_count():
			var bone := mi.skin.get_bind_bone(b)
			if bone < 0:
				bone = skeleton.find_bone(String(mi.skin.get_bind_name(b)))
			bind_bone.append(bone)
		for s in mi.mesh.get_surface_count():
			_lowest(mi, s, bind_bone, skeleton, low)
	var origin := skeleton.global_position.y
	return [maxf(origin - low[0], 0.0) if is_finite(low[0]) else 0.0,
			maxf(origin - low[1], 0.0) if is_finite(low[1]) else 0.0]


## The lowest rest-pose y of each side's foot armour, in WORLD space, folded into `low`.
static func _lowest(mi: MeshInstance3D, surface: int, bind_bone: PackedInt32Array,
		skel: Skeleton3D, low: Array[float]) -> void:
	var arrays := mi.mesh.surface_get_arrays(surface)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if bones == null or positions.is_empty():
		return
	var per := int(bones.size() / positions.size())
	# the skinning formula is `bone_global_pose * bind_pose * v`, so the REST position of a vertex is
	# `bone_global_rest * bind_pose * v` -- the bind pose on its own is the vertex in BONE space, and
	# using it alone is what put the first cut of this 0.35 m out.
	var binds: Array[Transform3D] = []
	binds.resize(mi.skin.get_bind_count())
	for b in binds.size():
		binds[b] = skel.get_bone_global_rest(bind_bone[b]) * mi.skin.get_bind_pose(b)
	var xf := skel.global_transform
	for i in positions.size():
		var side := -1
		var p := Vector3.ZERO
		for j in per:
			var w := weights[i * per + j]
			if w <= 0.0:
				continue
			var b := int(bones[i * per + j])
			p += (binds[b] as Transform3D) * positions[i] * w
			if side < 0:
				side = _sole_side(skel.get_bone_name(bind_bone[b]))
		if side < 0:
			continue
		low[side] = minf(low[side], (xf * p).y)


## 0 for a left foot or toe bone, 1 for a right one, -1 for anything that cannot touch the floor.
static func _sole_side(bone_name: String) -> int:
	if not (bone_name.begins_with("L_") or bone_name.begins_with("R_")):
		return -1
	for key in SOLE_BONES:
		if bone_name.contains(key):
			return 0 if bone_name.begins_with("L_") else 1
	return -1


## --- the roll profile ---------------------------------------------------------------------------
##
## `Hero3Foot.ankle_offset` keeps the sole on the ground while the foot rolls by pivoting the ankle
## about a MEASURED contact point: the rear sole corner at heel strike, the toe hinge at push-off.
## One pivot per half of the stance cannot be exact for a boot plate that is not a rectangle, so the
## sole still rides up and down by a few centimetres through the roll -- measured at up to 0.16 m,
## which is what kept the planted foot outside the r9 gate for 6 % of a walk cycle.
##
## This measures the RESIDUAL directly: for each roll sample, the ankle offset the pivot scheme asks
## for, and where the mesh's lowest vertex actually ends up under it. The correction is the
## difference, sampled every ROLL_STEP degrees over the roll the gait actually uses.

const ROLL_MIN := -30.0
const ROLL_MAX := 20.0
const ROLL_STEP := 2.0


## Per leg, the metres the sole target has to rise at each roll sample, in `Hero3Sole.contact`. The
## array runs from ROLL_MIN to ROLL_MAX in ROLL_STEP steps; `roll_lift` reads it back.
static func measure_roll(skeleton: Skeleton3D, legs: Array) -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	for leg: Dictionary in legs:
		out.append(_profile(skeleton, leg))
	return out


## The correction at a given roll, in radians, from a profile `measure_roll` produced.
static func roll_lift(profile: PackedFloat32Array, roll: float) -> float:
	if profile.is_empty():
		return 0.0
	var deg := clampf(rad_to_deg(roll), ROLL_MIN, ROLL_MAX)
	var f := (deg - ROLL_MIN) / ROLL_STEP
	var i := clampi(int(f), 0, profile.size() - 1)
	var j := clampi(i + 1, 0, profile.size() - 1)
	return lerpf(profile[i], profile[j], f - float(i))


static func _profile(skeleton: Skeleton3D, leg: Dictionary) -> PackedFloat32Array:
	var verts := _foot_verts(skeleton, String(leg["spec"]["side"]))
	var ankle := skeleton.get_bone_global_rest(int(leg["foot"])).origin
	var toe_idx := skeleton.find_bone("%s_Toe" % String(leg["spec"]["side"]))
	var hinge := skeleton.get_bone_global_rest(toe_idx).origin if toe_idx >= 0 else ankle
	var flat := _lowest_at(verts, ankle, hinge, 0.0)
	var out := PackedFloat32Array()
	for deg in range(int(ROLL_MIN), int(ROLL_MAX) + 1, int(ROLL_STEP)):
		var r := deg_to_rad(float(deg))
		var offset := Hero3Foot.ankle_offset(leg, r)
		var low := _lowest_at(verts, ankle, hinge, r)
		# the sole's height above the contact point, relative to the flat foot it was trimmed for
		out.append(-(offset.y + low - flat))
	return out


## Every foot and toe vertex of one side, in SKELETON space, tagged with the bone that carries it.
static func _foot_verts(skeleton: Skeleton3D, side: String) -> Array:
	var out: Array = []
	var model := skeleton.get_parent().get_parent() as Node3D
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin == null or mi.mesh == null:
			continue
		var bind_bone := PackedInt32Array()
		for b in mi.skin.get_bind_count():
			var bone := mi.skin.get_bind_bone(b)
			if bone < 0:
				bone = skeleton.find_bone(String(mi.skin.get_bind_name(b)))
			bind_bone.append(bone)
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if bones == null or positions.is_empty():
				continue
			var per := int(bones.size() / positions.size())
			for i in positions.size():
				var best := -1.0
				var top := 0
				for j in per:
					if weights[i * per + j] > best:
						best = weights[i * per + j]
						top = int(bones[i * per + j])
				var bone_name := skeleton.get_bone_name(bind_bone[top])
				if not bone_name.begins_with(side + "_"):
					continue
				if not (bone_name.ends_with("_Foot") or bone_name.ends_with("_Toe")):
					continue
				var rest := skeleton.get_bone_global_rest(bind_bone[top]) \
						* mi.skin.get_bind_pose(top)
				out.append([rest * positions[i], bone_name.ends_with("_Toe")])
	return out


## The lowest vertex of the foot, relative to the ANKLE, when the foot is rolled by `roll` about the
## model's X axis and the toe plate counter-rotates to stay flat (`Hero3Foot.toe_pitch`).
static func _lowest_at(verts: Array, ankle: Vector3, hinge: Vector3, roll: float) -> float:
	var foot_r := Basis(Vector3.RIGHT, roll)
	var toe_r := Basis(Vector3.RIGHT, roll + Hero3Foot.toe_pitch(roll))
	var low := INF
	for row in verts:
		var v: Vector3 = row[0]
		var p := foot_r * (v - ankle) + ankle if not bool(row[1]) \
				else foot_r * (hinge - ankle) + ankle + toe_r * (v - hinge)
		low = minf(low, p.y - ankle.y)
	return low
