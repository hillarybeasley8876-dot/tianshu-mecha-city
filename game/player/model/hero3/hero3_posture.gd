class_name Hero3Posture
extends RefCounted
## Everything above the hips on the Tianshu mech (hero-v3, brief step 3): the root translation that
## carries the crouch and the sway, the pelvis counter-rotation and settle, the aimed spine chain and
## the held arms. `hero3_gait.gd` owns the step planner and decides WHAT the posture is; this module
## only writes bones, so the planner stays readable as data.
##
## Every write goes through `Hero3LegIk`, which carries the FK origin. Writing a rest ORIGIN instead
## pins each bone where it was exported, and the whole upper body stops following the hips -- that is
## the bug `tests/test_hero3_fk.gd` pins down.

## The arms are held, not swung: a small constant offset from the exported rest pose puts them in a
## combat-ready guard. Radians, applied in each bone's own rest space, parent chain first.
const READY_POSE: Array = [
	{"bone": "R_Clavicle", "euler": Vector3(0.0, -0.10, 0.0)},
	{"bone": "R_Upperarm", "euler": Vector3(-0.28, 0.0, -0.16)},
	{"bone": "R_Forearm", "euler": Vector3(-0.42, 0.0, 0.0)},
	{"bone": "L_Clavicle", "euler": Vector3(0.0, 0.10, 0.0)},
	{"bone": "L_Upperarm", "euler": Vector3(-0.24, 0.0, 0.16)},
	{"bone": "L_Forearm", "euler": Vector3(-0.52, 0.0, 0.0)},
	## The wrist aims the BLADE, and it is authored on its own: a clip writes absolute world bases, so
	## the hand's euler alone decides where the 12 m of steel points -- the arm's euler only moves
	## where the hilt IS. 0.875 rad puts the blade 15 deg above horizontal pointing forward, measured
	## against `Hero3Rig.blade_rest` (the saber's real axis off the mesh, not the socket's).
	{"bone": "R_Hand", "euler": Vector3(0.875, 0.0, 0.0)},
]
## Per-bone aim limits, in degrees, so the mech turns its whole upper body toward a target instead of
## snapping the head round like an owl.
const AIM_CHAIN: Array = [
	{"bone": "Spine01", "yaw": 20.0, "pitch": 12.0},
	{"bone": "Spine02", "yaw": 26.0, "pitch": 18.0},
	{"bone": "Neck", "yaw": 24.0, "pitch": 20.0},
	{"bone": "Head", "yaw": 26.0, "pitch": 22.0},
]
## How much of the lower body's yaw each link has GIVEN BACK by the time it is written, in AIM_CHAIN
## order. 1.0 means "this link sits on the aim", 0.0 means "this link still points where the hips do".
##
## Every write here is an ABSOLUTE skeleton-space basis (`Hero3LegIk.set_basis`), so the chain does
## NOT accumulate: a link's value IS its world yaw. That is why this is a "given back" fraction and
## not a per-link increment, and why the first version was wrong -- it SUBTRACTED the pelvis yaw from
## the chest, which turned the chest a further -80 deg instead of putting it back on the aim. A left
## strafe left the shoulder line at -37 deg (lead r4 interim item d).
const COUNTER_SHARE: Array[float] = [0.5, 1.0, 1.0, 1.0]
## How much of the AIM each link has taken by the time it is written, in AIM_CHAIN order. Absolute
## writes again: the chest is not "20 deg more than the waist", it IS 20 deg off the model forward. So
## the waist takes a third of the turn, the chest most of it, and the neck and head finish it -- which
## also keeps every link inside its own per-bone limit at a 25 deg aim.
const AIM_SHARE: Array[float] = [0.35, 0.70, 1.0, 1.0]
## How much of the locomotion LEAN each link of the chain takes, in AIM_CHAIN order. The spine writes
## are ABSOLUTE, so without this the pelvis leans and the chest does not: the mech bent at the waist
## and the eye read a bolt-upright torso at 16 m/s (lead r9 item 3, measured -1.8 deg at every speed).
## The neck and head take half, which keeps the helm looking where the mech is going.
const LEAN_SHARE: Array[float] = [1.0, 1.0, 0.5, 0.5]
## How much of the lean the PELVIS itself takes. The hips carry the legs, and a pelvis pitched into a
## 42 m/s skate folds the knee far enough to drive the calf plate 0.141 m through the thigh (measured,
## `test_hero3_pieces`). The chest still takes the whole lean -- the spine writes are absolute -- so
## the machine reads as leaning from the ankles while the hips stay nearly level.
const PELVIS_LEAN_SHARE := 0.22
## The most the mech may lean, in radians. Past this the knee fold and the plate collisions win.
const LEAN_MAX := 0.38
## The bones an upper clip layers ON TOP of the posture instead of replacing (lead r4 item 6). A
## clip's spine keys are small offsets -- a flinch, a twist -- and the aim and the counter-rotation
## have to survive them. Arm keys are absolute for a melee swing and offsets for a weapon clip, which
## says so with `"offset": true`.
const LAYERED: Array[String] = ["Spine01", "Spine02", "Neck", "Head"]
const TORSO_COUNTER_DEG := 6.0
const SETTLE_OVERSHOOT_DEG := 2.0
const SETTLE_TIME := 0.25
## How far the upper arms counter-swing against the legs, in radians of peak amplitude. This is a
## MACHINE balancing itself, not a person walking: 5 deg is enough to read as weight transfer at 34 m
## of leg, small enough that the arms never flail (lead r9 item 3 -- measured 0.0 deg before this, the
## arms hung like a mannequin's at every speed) and small enough to keep the upperarm plate out of the
## clavicle (`test_hero3_pieces`: 0.053 m of interpenetration at 0.12 rad, 0.000 m here).
const ARM_SWING := 0.085

var skeleton: Skeleton3D
var ik: Hero3LegIk

## Written by the gait every frame before `apply()`.
var drop: float = 0.0
var sway: float = 0.0
## The lower body yaws toward the travel direction on a strafe (lead r3 item A4) and the spine
## chain takes exactly that much back, so the chest and the rifle keep facing the aim.
var yaw: float = 0.0
var phase: float = 0.0
var speed: float = 0.0
var walk_speed: float = 9.0
var settle: float = 0.0
var air: float = 0.0
var aim_point: Vector3 = Vector3.ZERO
var aim_weight: float = 0.0
## How far the lower body leans into the travel, in radians, already signed: positive tips the mech
## forward about its own lateral axis (lead r4 item 2 -- a skate leans 8-12 deg, a dash burst 20).
var lean: float = 0.0
## The root a FULL clip asks for (lead r4 item 3): how far it slides along the model's -Z, and how far
## the pelvis pitches and rolls. A topple is a roll, a knockdown is a pitch, and neither is reachable
## with leg keys alone.
var root_z: float = 0.0
var clip_pitch: float = 0.0
var clip_roll: float = 0.0
## The arms' counter-swing this frame, in radians, already signed per side by `apply_ready`. Written
## by the gait from the phase clock, so the arm is always opposite the leg on its own side.
var arm_swing: float = 0.0
## How far the arms are pulled in for a skate or a dash burst, 0..1. `READY_POSE` itself is left
## alone: it is `Hero3ClipPlayer`'s blend base, and a clip that owns an arm overrides this anyway.
var pull: float = 0.0
## The rifle solver (lead r4 item 6). Set by `Hero3Model` from the rig's measured barrel.
var aim_solver: Hero3Aim = null

var _root: int = 0
var _pelvis: int = 0
## bone -> the basis this module wrote for it this frame, so `Hero3ClipPlayer` can layer a clip's
## offset on top instead of replacing it. Read through `written`.
var _written: Dictionary = {}
var written: Dictionary:
	get: return _written


func setup(skeleton_: Skeleton3D, ik_: Hero3LegIk) -> void:
	skeleton = skeleton_
	ik = ik_
	_root = skeleton.find_bone("Root")
	_pelvis = skeleton.find_bone("Pelvis")


## The crouch and the sway are ONE root translation, so every plate below the root drops together.
## The pelvis then counter-rotates against the legs and overshoots by at most 2 deg on a stop.
func apply_pelvis() -> void:
	if _root >= 0:
		var root_rest := ik.rest_of("Root")
		ik.set_pose(_root, root_rest.basis,
				root_rest.origin + Vector3(sway, -drop, -root_z))
	skeleton.force_update_all_bone_transforms()
	if _pelvis < 0:
		return
	var pitch := 0.0
	if settle > 0.0:
		var k := settle / SETTLE_TIME
		pitch = deg_to_rad(SETTLE_OVERSHOOT_DEG) * sin(k * TAU) * k
	var counter := deg_to_rad(TORSO_COUNTER_DEG) * sin(TAU * phase) * _moving() * (1.0 - air)
	# a positive pitch about +X tips the up axis BACKWARD, so a forward lean is a negative pitch
	var q := Quaternion(Vector3.UP, yaw + counter) \
			* Quaternion(Vector3.RIGHT, pitch + clip_pitch - lean * PELVIS_LEAN_SHARE) \
			* Quaternion(Vector3.BACK, clip_roll)
	ik.set_basis(_pelvis, Basis(q) * ik.rest_of("Pelvis").basis)
	skeleton.force_update_all_bone_transforms()


## The spine chain turns toward the aim point inside its per-bone limits and counter-rotates against
## the pelvis -- both its gait sway and the strafe yaw.
##
## It deliberately does NOT translate: the first version lifted Spine01 by 45 % of the pelvis drop to
## keep the head level, and at the deepest drop that opened a 0.46 m gap between the Pelvis-weighted
## plates and the Spine01-weighted ones (lead r3 item A5, `probe_waist.gd`). A child bone is never
## moved away from its parent; the smaller bob makes the compensation unnecessary.
func apply_torso() -> void:
	_written.clear()
	var aim := _aim_angles()
	for i in AIM_CHAIN.size():
		var link: Dictionary = AIM_CHAIN[i]
		var bone_name := String(link["bone"])
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			continue
		var share := float(AIM_SHARE[i])
		var link_yaw := clampf(aim.x * share, -deg_to_rad(float(link["yaw"])),
				deg_to_rad(float(link["yaw"])))
		var link_pitch := clampf(aim.y * share, -deg_to_rad(float(link["pitch"])),
				deg_to_rad(float(link["pitch"])))
		# a positive yaw about +Y carries the model's -Z to the LEFT and a positive pitch about +X
		# tips it DOWN, so both are already signed the way `_aim_angles` returns them
		var q := Quaternion(Vector3.UP, _carry(i) + link_yaw) \
				* Quaternion(Vector3.RIGHT, link_pitch - lean * float(LEAN_SHARE[i]))
		_written[bone_name] = Basis(q)
		ik.set_basis(idx, Basis(q) * ik.rest_of(bone_name).basis)
		skeleton.force_update_all_bone_transforms()


## How much of the lower body's yaw this link is still CARRYING, in radians.
##
## The chest, the neck and the head carry none of it -- they sit on the aim, which is what puts the
## shoulder line back to 0 on a strafe -- and the waist carries half, so the untwist is spread over
## two joints instead of appearing all at once. The torso's counter-rotation against the gait sway
## needs no term of its own: the chest is written absolutely, so the hips swinging +-6 deg under a
## chest that stays put IS the 6 deg of counter-rotation the brief asks for.
func _carry(i: int) -> float:
	return yaw * (1.0 - float(COUNTER_SHARE[i]))




## Arms held, not swung: one constant offset from the exported rest pose, parent chain first so each
## bone is written against an up-to-date parent.
func apply_ready() -> void:
	for row: Dictionary in READY_POSE:
		var bone_name := String(row["bone"])
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			continue
		var basis := Basis.from_euler(ready_euler(bone_name) + _swing(bone_name))
		_written[bone_name] = basis
		ik.set_basis(idx, basis * ik.rest_of(bone_name).basis)
		skeleton.force_update_all_bone_transforms()


## Bring the rifle onto the aim (lead r4 item 6). Called after `apply_ready`, so it overrides the held
## arm pose, and before the clip player, so a weapon clip layers its recoil on top of the result.
func apply_aim() -> void:
	if aim_solver == null or aim_weight <= 0.001 or aim_point == Vector3.ZERO:
		return
	var local := skeleton.to_local(aim_point) if skeleton.is_inside_tree() else aim_point
	var chest := ik.head_of(skeleton.find_bone("Spine02"))
	var to_aim := local - chest
	if to_aim.length() < 1.0:
		return
	aim_solver.solve(to_aim.normalized(), local, aim_weight)
	for bone_name in Hero3Aim.ARM_BONES:
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			continue
		_written[bone_name] = skeleton.get_bone_global_pose(idx).basis \
				* ik.rest_of(bone_name).basis.inverse()


## The held euler for one bone, with the skate's pull-in already applied. `Hero3ClipPlayer` needs
## this: it re-writes the READY_POSE bones that sit UNDER a bone the clip owns, in the same
## parent-first pass as its own writes (see `apply()`).
func ready_euler(bone_name: String) -> Vector3:
	for row: Dictionary in READY_POSE:
		if String(row["bone"]) != bone_name:
			continue
		var euler: Vector3 = row["euler"]
		return _pulled(bone_name, euler) if pull > 0.001 else euler
	return Vector3.ZERO


## The arm counter-swing, as an offset on the held pose. The right arm mirrors the left, so each arm
## is opposite the leg on its OWN side; the forearm gets a third of it, which reads as the elbow
## absorbing the swing instead of the whole arm pivoting at the shoulder.
func _swing(bone_name: String) -> Vector3:
	if absf(arm_swing) < 1e-5:
		return Vector3.ZERO
	var side := -1.0 if bone_name.begins_with("R_") else 1.0
	if bone_name.ends_with("Upperarm"):
		return Vector3(arm_swing * side, 0.0, 0.0)
	if bone_name.ends_with("Forearm"):
		return Vector3(arm_swing * side * 0.33, 0.0, 0.0)
	return Vector3.ZERO


## The skate's arm pull-in, as an offset on the ready pose: the upper arms come in toward the ribs
## and the elbows fold. A mech bracing into a 42 m/s skid does not hold its arms out.
func _pulled(bone_name: String, euler: Vector3) -> Vector3:
	if bone_name.ends_with("Upperarm"):
		return euler + Vector3(-0.40 * pull, 0.0, -euler.z * 0.7 * pull)
	if bone_name.ends_with("Forearm"):
		return euler + Vector3(-0.60 * pull, 0.0, 0.0)
	return euler


func _moving() -> float:
	return clampf(speed / maxf(walk_speed, 0.01), 0.0, 1.0)


## Yaw and pitch toward the aim point, in radians, already scaled by the aim weight.
func _aim_angles() -> Vector2:
	if aim_weight <= 0.001 or aim_point == Vector3.ZERO:
		return Vector2.ZERO
	var local := skeleton.to_local(aim_point) if skeleton.is_inside_tree() else aim_point
	var flat := Vector2(local.x, local.z)
	if flat.length() <= 0.05:
		return Vector2.ZERO
	# `atan2(-x, -z)` is the yaw that carries the model's forward (-Z) ONTO the target: rotating about
	# +Y sends (0,0,-1) to (-sin, 0, -cos), so a POSITIVE yaw turns LEFT and a target on the right
	# needs a negative angle. The pitch is the other way: rotating about +X sends (0,0,-1) to
	# (0, sin, -cos), so a POSITIVE pitch tips UP and an upward target needs a positive angle. Both
	# signs were wrong (lead r4 item 6).
	return Vector2(clampf(atan2(-local.x, -local.z), -PI, PI),
			clampf(atan2(local.y - 12.0, flat.length()), -0.9, 0.9)) * aim_weight
