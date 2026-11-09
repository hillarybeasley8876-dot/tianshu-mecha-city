class_name Hero3LegIk
extends RefCounted
## Bone writing and two-bone IK for the Tianshu mech (hero-v3, brief step 3).
##
## Three things here are the result of measured failures, not taste:
##
## 1. **Every write carries the FK ORIGIN.** The first gait wrote
##    `set_bone_global_pose(idx, Transform3D(basis, rest.origin))`, which pins every bone at its rest
##    ORIGIN: the FK chain never moves, so the IK computed targets that never reached the rig and the
##    legs could not step at all (`tests/test_hero3_ik.gd` printed rest == pose for every leg bone).
##    Writing the head where the chain actually put it is what makes a rotated parent carry its
##    children -- the whole point of a skeleton. `tests/test_hero3_fk.gd` is the proof.
## 2. **The solver aims the ANKLE, not the sole.** The ankle bone sits well above the ground, so a
##    solver that aims at the contact patch measures a vertical drop longer than the leg and every
##    reach it computes comes out negative.
## 3. **The knee is clamped at both ends**: a locked knee is an IK singularity that pops, and a knee
##    folded far enough drives the calf plate through the thigh plate.

## Bend from straight, in degrees. 0 is a locked knee.
const KNEE_MIN_BEND_DEG := 8.0
## MEASURED, not guessed (lead r4 item 9). `probe_knee.gd` reads the real angle in the poses the
## interpenetration gate fails: `death` sat exactly ON the old 150 deg clamp and drove the calf
## 0.504 m through the thigh. At 135 that crossing is gone and the death pelvis still drops 5.80 m,
## so item 3's gate is untouched. `hit_knockdown` reaches 139.9 deg and the slide skate 85 deg, and
## neither improved, so their crossings are about WHERE the leg is and not how far it is folded.
const KNEE_MAX_BEND_DEG := 135.0
## Knees point forward in the model's frame (-Z). The gait overwrites this every frame with the
## pelvis' own forward: on a strafe the lower body yaws up to 60 deg toward the travel direction
## (lead r3 item A4) and a pole pinned to model -Z would fold the knees out sideways.
const POLE := Vector3(0.0, 0.0, -1.0)

var skeleton: Skeleton3D
## The knee pole in skeleton space. Defaults to model forward; `Hero3Gait` follows the pelvis yaw.
var pole: Vector3 = POLE
## How far the lower body is yawed toward the travel direction, in radians. The foot has to turn with
## it: a global-pose write sets the foot's whole orientation, so without this the plate keeps facing
## the model's -Z while the leg points 75 deg away, and rolling it about the model's X axis then
## tilted a 2.8 m wide plate sideways and buried its outboard edge 0.29 m in the floor
## (lead r3 item A4).
var foot_yaw: float = 0.0

var _rest: Dictionary = {}


func setup(skeleton_: Skeleton3D) -> void:
	skeleton = skeleton_
	for i in skeleton.get_bone_count():
		_rest[skeleton.get_bone_name(i)] = skeleton.get_bone_global_rest(i)


func rest_of(bone_name: String) -> Transform3D:
	return _rest.get(bone_name, Transform3D.IDENTITY)


## The bone's head in skeleton space, computed from its parent's CURRENT global pose and its own
## rest -- deliberately NOT `get_bone_global_pose(idx).origin`.
##
## `get_bone_global_pose` includes whatever translation this unit wrote last frame, so a caller that
## adds an offset to it compounds that offset every frame: the spine compensation lifted the chest
## 0.4 m per frame and parked the whole upper body 90 m above the mech. Deriving the head from the
## parent instead is stable, because a global-pose write always leaves `pose.origin` at zero.
func head_of(idx: int) -> Vector3:
	var parent := skeleton.get_bone_parent(idx)
	var rest := skeleton.get_bone_rest(idx)
	if parent < 0:
		return rest.origin
	var p := skeleton.get_bone_global_pose(parent)
	return p.origin + p.basis * rest.origin


## Give a bone a finished skeleton-space transform. The ORIGIN must be where the FK chain actually
## put the bone's head: writing the rest origin instead pins the bone where it was exported, which is
## how the first gait ended up with a skeleton that could not move at all.
##
## This is the ONLY write path in the unit. `set_bone_pose_rotation` is deliberately not used: its
## composition rule is not the documented `parent * rest * pose` on this skeleton (probed in
## `tests/test_hero3_fk.gd`, both candidates miss), so a rotation written through it lands somewhere
## the caller cannot predict.
func set_pose(idx: int, basis: Basis, origin: Vector3) -> void:
	skeleton.set_bone_global_pose(idx, Transform3D(basis.orthonormalized(), origin))


## Turn a bone about its own head so its rest +Y axis runs along `direction`, keeping the rest roll.
func aim(idx: int, direction: Vector3) -> void:
	if direction.length_squared() < 1e-8:
		return
	var rest: Transform3D = _rest[skeleton.get_bone_name(idx)]
	var swing := Quaternion(rest.basis.y.normalized(), direction.normalized())
	set_pose(idx, Basis(swing) * rest.basis, head_of(idx))


## Give a bone a finished skeleton-space BASIS, leaving its head where FK put it (plus `offset` in
## skeleton space). The caller must have run `force_update_all_bone_transforms` first, so the head it
## reads is current -- which is what makes a rotated parent carry its children.
func set_basis(idx: int, target: Basis, offset: Vector3 = Vector3.ZERO) -> void:
	set_pose(idx, target, head_of(idx) + offset)


## Solve thigh + calf so the ankle lands on `target` (skeleton space), then lay the foot down with
## `roll` radians of pitch about the model's X axis (positive = toe up, the heel-strike end) and
## counter-roll the toe bone so the toe plate stays flat while the heel lifts (lead r3 item A2).
func solve(leg: Dictionary, target: Vector3, roll: float) -> void:
	var thigh := int(leg["thigh"])
	var calf := int(leg["calf"])
	var foot := int(leg["foot"])
	var l1 := float(leg["l1"])
	var l2 := float(leg["l2"])
	var hip := head_of(thigh)
	var to_target := target - hip
	# the knee angle is the law of cosines, clamped at both ends so it can neither lock nor invert
	var bend := bend_for(l1, l2, to_target.length())
	var dist := sqrt(maxf(l1 * l1 + l2 * l2 + 2.0 * l1 * l2 * cos(bend), 0.01))
	var dir := to_target.normalized() if to_target.length() > 1e-5 else Vector3.DOWN
	var side := dir.cross(pole)
	if side.length_squared() < 1e-6:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var perp := side.cross(dir).normalized()
	var cos_hip := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var hip_angle := acos(cos_hip)
	var knee := hip + (dir * cos(hip_angle) + perp * sin(hip_angle)) * l1
	aim(thigh, knee - hip)
	skeleton.force_update_all_bone_transforms()
	aim(calf, hip + dir * dist - head_of(calf))
	skeleton.force_update_all_bone_transforms()
	# the foot lies flat while it is planted and rolls heel-to-toe through the step, turned with the
	# lower body first so the roll axis is the foot's OWN lateral axis
	var rest: Transform3D = _rest[skeleton.get_bone_name(foot)]
	set_basis(foot, _foot_basis(roll) * rest.basis)
	skeleton.force_update_all_bone_transforms()
	var toe_pitch := Hero3Foot.toe_pitch(roll)
	if absf(toe_pitch) > 1e-5:
		var toe := skeleton.find_bone("%s_Toe" % String(leg["spec"]["side"]))
		if toe >= 0:
			# A global-pose write REPLACES the parent's contribution, so the toe has to be given the
			# foot's roll as well as its own counter-roll: the foot's world rotation is R(roll) and
			# this bone's rest basis already sits inside it. Writing R(toe_pitch) alone left the plate
			# 25 deg off flat and pushed its sole 0.06 m into the floor (probe_sink.gd).
			var toe_rest: Transform3D = _rest[skeleton.get_bone_name(toe)]
			set_basis(toe, _foot_basis(roll + toe_pitch) * toe_rest.basis)
			skeleton.force_update_all_bone_transforms()


## Solve a two-bone chain so its end lands on `target` (skeleton space) and give the end bone a
## finished basis. The arm version of `solve()`: the legs aim the ankle and then roll the foot, the
## arms aim the hand and then point the RIFLE (lead r4 item 6).
##
## `reach_dir` is the pole: the direction the middle joint is pushed toward, so an elbow does not fold
## out sideways. The target is clamped into the chain's reach -- an unreachable hand still points at
## the target, it just stops short.
func solve_chain(root: int, mid: int, end: int, l1: float, l2: float, target: Vector3,
		reach_dir: Vector3, end_basis: Basis) -> void:
	var hip := head_of(root)
	var to_target := target - hip
	var dist := clampf(to_target.length(), absf(l1 - l2) + 0.05, (l1 + l2) * 0.97)
	var dir := to_target.normalized() if to_target.length() > 1e-5 else Vector3.DOWN
	var side := dir.cross(reach_dir)
	if side.length_squared() < 1e-6:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var perp := side.cross(dir).normalized()
	var cos_root := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var root_angle := acos(cos_root)
	var joint := hip + (dir * cos(root_angle) + perp * sin(root_angle)) * l1
	aim(root, joint - hip)
	skeleton.force_update_all_bone_transforms()
	aim(mid, hip + dir * dist - head_of(mid))
	skeleton.force_update_all_bone_transforms()
	set_basis(end, end_basis)
	skeleton.force_update_all_bone_transforms()


## The lower-body yaw followed by the foot's own roll, in skeleton space.
func _foot_basis(roll: float) -> Basis:
	return Basis(Quaternion(Vector3.UP, foot_yaw) * Quaternion(Vector3.RIGHT, roll))



## The knee's bend from straight, in radians, for a hip-to-ankle distance of `dist`.
func bend_for(l1: float, l2: float, dist: float) -> float:
	var cos_interior := clampf((l1 * l1 + l2 * l2 - dist * dist) / (2.0 * l1 * l2), -1.0, 1.0)
	return clampf(PI - acos(cos_interior), deg_to_rad(KNEE_MIN_BEND_DEG),
			deg_to_rad(KNEE_MAX_BEND_DEG))
