class_name Hero3Aim
extends RefCounted
## Puts the rifle on the aim line (hero-v3, lead r4 item 6).
##
## The old behaviour had two faults and they compounded. The signs in `_aim_angles` were inverted, so
## a target on the right turned the chest left; and the arms were written as ABSOLUTE bases from
## `READY_POSE`, so they never inherited the aimed spine at all -- the rifle's barrel direction was
## identical to six decimals at aim 0 deg, 20 deg right and 25 deg up. Shots leave `muzzle_r` toward
## the aim point, so the beam came out of a gun pointing at the floor.
##
## Here the arms are SOLVED: the right hand is placed on the aim line and two-bone IK carries the
## upper arm and forearm to it, then the hand is turned so the barrel -- measured off the rifle mesh,
## not assumed -- lies along the aim. The left hand grips the barrel ahead of it. The result is that
## `muzzle_r` sits at the barrel tip with its -Z along the barrel, which is what
## `WeaponContext.aim_dir_from` needs.

## How far ahead of the right hand the left hand grips the barrel, in metres. The rifle is 4.6 m long
## and the left arm's reach is 5.46 m, so a foregrip further out than this is simply unreachable.
const FOREGRIP := 2.0
## How far along the aim line the right hand sits from the shoulder, as a fraction of the arm's reach.
const GRIP_REACH := 0.62
## How far out to the side the right hand is carried, in metres, so the rifle is not inside the chest.
const GRIP_SIDE := 0.55
## The elbow pole: down and outboard, so the elbows fold the way a mech's do.
const ELBOW_POLE := Vector3(0.35, -1.0, 0.25)
## The bones the aim solves, so `Hero3Posture` knows what to record for the clip layering.
const ARM_BONES: Array[String] = ["R_Upperarm", "R_Forearm", "R_Hand",
		"L_Upperarm", "L_Forearm", "L_Hand"]

var skeleton: Skeleton3D
var ik: Hero3LegIk
## The barrel direction and the muzzle's distance along it, both MEASURED off the rifle mesh in the
## R_Hand's rest frame (`Hero3Rig.measure_rifle`).
var barrel_rest: Vector3 = Vector3(0.0, 0.0, -1.0)
var barrel_len: float = 4.6

var _r: Array[int] = []
var _l: Array[int] = []
var _l1: float = 0.0
var _l2: float = 0.0


func setup(skeleton_: Skeleton3D, ik_: Hero3LegIk) -> void:
	skeleton = skeleton_
	ik = ik_
	_r = [skeleton.find_bone("R_Upperarm"), skeleton.find_bone("R_Forearm"),
			skeleton.find_bone("R_Hand")]
	_l = [skeleton.find_bone("L_Upperarm"), skeleton.find_bone("L_Forearm"),
			skeleton.find_bone("L_Hand")]
	_l1 = skeleton.get_bone_global_rest(_r[0]).origin.distance_to(
			skeleton.get_bone_global_rest(_r[1]).origin)
	_l2 = skeleton.get_bone_global_rest(_r[1]).origin.distance_to(
			skeleton.get_bone_global_rest(_r[2]).origin)


## Where the muzzle ends up, in skeleton space, for a hand pose. The gate measures this.
func muzzle(hand: Transform3D) -> Vector3:
	return hand.origin + (hand.basis * barrel_rest).normalized() * barrel_len


## Solve both arms onto `aim_dir` (skeleton space), blended from the pose the arms are already in by
## `weight`. `aim_point` is used for the second pass: pointing the barrel along the shoulder-to-target
## direction leaves the muzzle off that line by however far the arm carries it, which at 5 m offset
## and 200 m range is over a degree -- inside the gate, but there is no reason to leave it there.
func solve(aim_dir: Vector3, aim_point: Vector3, weight: float) -> void:
	if weight <= 0.001:
		return
	var dir := aim_dir
	for pass_i in 2:
		var grip := _grip(dir)
		var hand_basis := _barrel_basis(dir)
		_solve_arm(_r, grip, hand_basis, weight)
		if pass_i == 0:
			var hand := skeleton.get_bone_global_pose(_r[2])
			var to_aim := aim_point - muzzle(hand)
			if to_aim.length() > 1.0:
				dir = to_aim.normalized()
	_solve_arm(_l, _grip(dir) + dir * FOREGRIP, _barrel_basis(dir), weight)


## Where the right hand goes: on the aim line, carried `GRIP_SIDE` outboard so the rifle clears the
## chest, and no further than the arm can reach.
func _grip(dir: Vector3) -> Vector3:
	var shoulder := ik.head_of(_r[0])
	var side := dir.cross(Vector3.UP)
	side = side.normalized() if side.length() > 1e-4 else Vector3.RIGHT
	var target := shoulder + dir * ((_l1 + _l2) * GRIP_REACH) + side * GRIP_SIDE
	var reach := target - shoulder
	var limit := (_l1 + _l2) * 0.97
	if reach.length() > limit:
		target = shoulder + reach.normalized() * limit
	return target


## The R_Hand basis that puts the barrel along `dir`, keeping the rest roll.
func _barrel_basis(dir: Vector3) -> Basis:
	var rest: Transform3D = ik.rest_of("R_Hand")
	var axis := (rest.basis * barrel_rest).normalized()
	return Basis(Quaternion(axis, dir.normalized())) * rest.basis


func _solve_arm(chain: Array[int], target: Vector3, hand_basis: Basis, weight: float) -> void:
	var blended := target
	if weight < 0.999:
		blended = skeleton.get_bone_global_pose(chain[2]).origin.lerp(target, weight)
	ik.solve_chain(chain[0], chain[1], chain[2], _l1, _l2, blended,
			ELBOW_POLE if chain[0] == _r[0] else Vector3(-ELBOW_POLE.x, ELBOW_POLE.y, ELBOW_POLE.z),
			hand_basis)
