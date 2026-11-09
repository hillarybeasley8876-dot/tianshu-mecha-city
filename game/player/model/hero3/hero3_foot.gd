class_name Hero3Foot
extends RefCounted
## Where one foot is, how it is rolled, and where its ANKLE has to sit for the rolled sole to stay on
## the ground (hero-v3, lead r3 item A2).
##
## The first version rotated the foot about the ANKLE for the whole stance. The ankle sits 2.77 m
## above the sole, so a 16 deg heel-strike roll drove the heel 0.39 m into the floor and a 26 deg
## push-off drove the toe 0.61 m under it -- measured on the CPU-skinned mesh, not on the target.
##
## A foot does not pivot about its ankle. It pivots about whatever is touching the ground: the HEEL
## edge at strike, the TOE hinge at push-off. `ankle_offset` is that pivot written as an ankle
## displacement, which is the only thing the two-bone solver needs, and the toe bone counter-rotates
## so the toe plate stays flat while the heel lifts.

## Toe up at heel strike, heel up at push-off, in degrees. Positive roll is toe up.
const HEEL_DEG := 16.0
const TOE_OFF_DEG := 26.0
## How much of the stance is spent rolling onto the heel, and from where the push-off starts.
const HEEL_SHARE := 0.20
const TOE_SHARE := 0.70
## Measured from the exported plates; used when the mesh walk finds no foot geometry at all.
const FALLBACK: Dictionary = {
	"heel": Vector2(-2.77, 1.64),
	"toe": Vector2(-2.87, -2.04),
	"hinge": Vector2(-2.27, -0.88),
}


## The foot's position this instant, in WORLD space: planted (locked, so it cannot slide) or in
## flight along an eased arc. `lift` is the peak height of the step. This is the point on the SOLE
## that is touching the ground, not the ankle -- `ankle_offset` carries the difference.
static func position(leg: Dictionary, lift: float) -> Vector3:
	if not bool(leg["stepping"]):
		return leg["planted"]
	var t := float(leg["t"])
	var flat: Vector3 = (leg["from"] as Vector3).lerp(leg["to"] as Vector3, t * t * (3.0 - 2.0 * t))
	return flat + Vector3(0.0, lift * pow(sin(PI * t), 0.7), 0.0)


## Heel-to-toe, in radians about the model's X axis. The foot lands on its heel, lies flat through
## mid-stance, rolls over the toe hinge at push-off, then swings toe-up and drops back onto the heel.
## `u` is the foot's own phase (0 as it leaves the ground) and `swing` the swing window's length.
static func roll(u: float, swing: float, stepping: bool) -> float:
	if stepping:
		var s := u / maxf(swing, 0.01)
		return deg_to_rad(lerpf(-TOE_OFF_DEG, HEEL_DEG, smoothstep(0.0, 1.0, s)))
	if u < swing:
		return 0.0                      ## this foot sat out its window: it never left the ground
	var p := clampf((u - swing) / maxf(1.0 - swing, 0.01), 0.0, 1.0)
	var heel := HEEL_DEG * (1.0 - smoothstep(0.0, HEEL_SHARE, p))
	var toe := TOE_OFF_DEG * smoothstep(TOE_SHARE, 1.0, p)
	return deg_to_rad(heel - toe)


## How far the ANKLE moves, in metres, from its flat-foot rest position when the foot is rolled by
## `roll` about the contact pivot. `back` is the direction the leg points its heel, so the offset
## follows the lower body: on a strafe the pelvis is yawed up to 75 deg and an offset pinned to the
## model's +Z would eat 1.6 m straight out of the stance width.
##
## Rotating about a pivot `p` (given relative to the ankle) puts the ankle at `p + R(roll) * -p`,
## and that is the whole function. Heel strike uses the rear sole corner, push-off the toe hinge,
## and at roll = 0 both collapse to zero, so the stance is continuous.
static func ankle_offset(leg: Dictionary, roll: float, back: Vector3 = Vector3.BACK) -> Vector3:
	if absf(roll) < 1e-5:
		return Vector3.ZERO
	var pivot: Vector2 = (leg["heel"] as Vector2) if roll > 0.0 else (leg["hinge"] as Vector2)
	var c := cos(roll)
	var s := sin(roll)
	var ry := -pivot.x * c + pivot.y * s
	var rz := -pivot.x * s - pivot.y * c
	return Vector3.UP * (pivot.x + ry) + back * (pivot.y + rz)


## The toe bone's counter-roll: while the foot rotates up over the toe hinge the toe plate has to
## stay flat on the ground, so it is rotated back by exactly the foot's roll. Zero at every other
## moment, including the whole of the heel-strike half of the stance.
static func toe_pitch(roll: float) -> float:
	return -roll if roll < 0.0 else 0.0


## The sole's contact geometry per side, MEASURED from the exported plates rather than assumed: the
## left and right foot meshes do not end at the same z (2.49 m vs 2.32 m behind the origin), so a
## single hard-coded heel would bury one foot and float the other.
##
## Returns `{side: {"heel": Vector2, "toe": Vector2, "hinge": Vector2}}`, every point relative to
## that side's ankle bone in the model's rest frame, as (y, z).
static func measure(skeleton: Skeleton3D) -> Dictionary:
	var raw := {}
	for child in skeleton.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.skin == null or mi.mesh == null:
			continue
		var bind := PackedInt32Array()
		for b in mi.skin.get_bind_count():
			var bone := mi.skin.get_bind_bone(b)
			if bone < 0:
				bone = skeleton.find_bone(String(mi.skin.get_bind_name(b)))
			bind.append(bone)
		for surface in mi.mesh.get_surface_count():
			_accumulate(mi, surface, bind, skeleton, raw)
	var out := {}
	for side in ["L", "R"]:
		var ankle_idx := skeleton.find_bone("%s_Foot" % side)
		var hinge_idx := skeleton.find_bone("%s_Toe" % side)
		if ankle_idx < 0 or not raw.has(side):
			out[side] = FALLBACK.duplicate()
			continue
		var ankle := skeleton.get_bone_global_rest(ankle_idx).origin
		var hinge := skeleton.get_bone_global_rest(hinge_idx).origin
		var r: Dictionary = raw[side]
		out[side] = {
			"heel": Vector2(float(r["sole_y"]) - ankle.y, float(r["heel_z"]) - ankle.z),
			"toe": Vector2(float(r["toe_y"]) - ankle.y, float(r["toe_z"]) - ankle.z),
			"hinge": Vector2(hinge.y - ankle.y, hinge.z - ankle.z),
		}
	return out


## One surface's vertices, sorted into the two sole corners this module needs. Every third vertex is
## enough: the sole is thousands of vertices and only its extremes matter.
static func _accumulate(mi: MeshInstance3D, surface: int, bind: PackedInt32Array,
		skeleton: Skeleton3D, raw: Dictionary) -> void:
	var arrays := mi.mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if bones == null or verts.is_empty():
		return
	var per := int(bones.size() / verts.size())
	for i in range(0, verts.size(), 3):
		var best := -1.0
		var top := -1
		for j in per:
			if weights[i * per + j] > best:
				best = weights[i * per + j]
				top = int(bones[i * per + j])
		var bone_name := skeleton.get_bone_name(bind[top])
		if not (bone_name.ends_with("_Foot") or bone_name.ends_with("_Toe")):
			continue
		var side := bone_name.substr(0, 1)
		if not raw.has(side):
			raw[side] = {"sole_y": INF, "heel_z": -INF, "toe_y": INF, "toe_z": INF}
		var r: Dictionary = raw[side]
		var v := verts[i]
		if bone_name.ends_with("_Toe"):
			r["toe_y"] = minf(float(r["toe_y"]), v.y)
			r["toe_z"] = minf(float(r["toe_z"]), v.z)
		else:
			r["sole_y"] = minf(float(r["sole_y"]), v.y)
			# an absolute threshold, not one relative to the running minimum: the sole sits at y = 0 in
			# the rest pose and the ankle at 2.77 m, so anything below 1.2 m is unambiguously sole
			if v.y < 1.2:
				r["heel_z"] = maxf(float(r["heel_z"]), v.z)


