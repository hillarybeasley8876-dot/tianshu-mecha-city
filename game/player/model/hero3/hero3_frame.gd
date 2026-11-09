class_name Hero3Frame
extends RefCounted
## The world-space reference frames the Tianshu gait plans in (hero-v3).
##
## Every one of these is a direction or a point that the step planner, the pelvis curve and the air
## pose all need, and every one of them is derived from the PELVIS rather than from the model node:
## on a strafe the lower body yaws up to 80 deg (lead r3 item A4), so the stance axis, the foot's heel
## axis and the hips all turn with it while the chest keeps facing the aim.

var skeleton: Skeleton3D
var ik: Hero3LegIk


func setup(skeleton_: Skeleton3D, ik_: Hero3LegIk) -> void:
	skeleton = skeleton_
	ik = ik_


## The y of the plane the mech stands on. The model node's own origin sits between the feet
## (CONTRACTS §5), so its world y IS the ground.
func ground() -> float:
	return skeleton.global_position.y


## The hip joint's world position, height included.
func hip(leg: Dictionary) -> Vector3:
	return skeleton.global_transform * ik.head_of(int(leg["thigh"]))


## The same hip dropped to the ground plane, which is where a plant is planned.
func hip_ground(leg: Dictionary) -> Vector3:
	var point := hip(leg)
	return Vector3(point.x, ground(), point.z)


## The pelvis' stance axis in world space, flattened: the direction a foot is planted outboard along.
func pelvis_right() -> Vector3:
	return _pelvis_axis(Vector3.RIGHT, "Pelvis", Vector3.RIGHT)


## The pelvis' BACKWARD axis in world space, flattened: the direction the air pose tucks along.
func pelvis_back() -> Vector3:
	return _pelvis_axis(Vector3.BACK, "Pelvis", Vector3.BACK)


## The world direction the foot's heel points, from the lower-body yaw ALONE. This has to match the
## rotation `Hero3LegIk` writes exactly, so it is derived from the yaw rather than read back off the
## pelvis bone (which also carries the 6 deg gait counter-rotation).
func foot_back(yaw: float) -> Vector3:
	return _flatten(skeleton.global_transform.basis * Vector3(sin(yaw), 0.0, cos(yaw)), Vector3.BACK)


## The world direction the mech is travelling, from the stick rotated into the model's frame. Zero
## while standing, which is what makes a turn in place a pure foot reposition rather than a step.
func travel(input: Vector2) -> Vector3:
	if input.length() < 0.01:
		return Vector3.ZERO
	return _flatten(skeleton.global_transform.basis * Vector3(input.x, 0.0, input.y).normalized(),
			Vector3.ZERO)


func _pelvis_axis(local: Vector3, bone_name: String, fallback: Vector3) -> Vector3:
	var idx := skeleton.find_bone(bone_name)
	if idx < 0:
		return fallback
	return _flatten(skeleton.global_transform.basis * skeleton.get_bone_global_pose(idx).basis * local,
			fallback)


func _flatten(v: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	return flat.normalized() if flat.length() > 1e-4 else fallback
