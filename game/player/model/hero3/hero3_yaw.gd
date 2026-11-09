class_name Hero3Yaw
extends RefCounted
## The lower body's heading relative to the travel direction (hero-v3, lead r3 item A4).
##
## The mech keeps facing its aim, so the LEGS turn instead: the pelvis yaws toward the travel and the
## torso takes the yaw back, which is what makes a strafe a real side-step instead of the legs
## scissoring through each other. `Hero3Gait` owns the smoothed value; this owns the geometry.

## The lower body FOLLOWS the travel angle exactly up to 80 deg. The lead's r3 suggested 60 deg, but
## the geometry does not allow it. The two feet's plants are always exactly one STRIDE apart along the
## travel, so the separation across the stance axis is `stance_width - stride x sin(angle between
## the travel and the pelvis forward)`. At 60 deg a pure lateral strafe leaves 30 deg across the
## stance, and at a run that is 4.26 - 8.8 x 0.5 = -0.14 m: the legs scissor straight through each
## other. 80 deg leaves 10 deg and 2.7 m. Back diagonals are mirrored to 45 deg, which points the
## pelvis exactly AWAY from the travel, so the mech backpedals and the sine term is zero.
const SIDE_DEG := 80.0
const BACK_DEG := 45.0

var frame: Hero3Frame


func setup(frame_: Hero3Frame) -> void:
	frame = frame_


## How far the lower body should turn toward the travel direction, in radians.
##
## The sign matters and is easy to get backwards: the yaw is the angle that carries the pelvis'
## forward axis (-Z) ONTO the travel direction, which is `atan2(-input.x, -input.y)` -- a right
## strafe is a NEGATIVE yaw. With the sign flipped the legs turned away from the travel and the
## forward diagonals scissored to -2.5 m.
func target(input: Vector2, speed: float) -> float:
	if input.length() < 0.01 or speed <= 0.6:
		return 0.0
	var angle := atan2(-input.x, -input.y)
	var limit := deg_to_rad(SIDE_DEG)
	if absf(angle) > PI * 0.5:
		limit = deg_to_rad(BACK_DEG)
		angle = wrapf(angle + PI, -PI, PI)
	return clampf(angle, -limit, limit) * clampf(speed / Hero3Timing.WALK_SPEED, 0.35, 1.0)


## Which foot leads a skate stance: the one on the side the mech is travelling towards, and the
## right foot when the travel runs straight fore or aft.
##
## The stance axis is derived from the lower-body YAW, not read off the pelvis bone. The pelvis also
## carries the +-6 deg gait counter-sway, so on a straight walk the dot product swung either side of
## zero and the lead foot flipped every half cycle -- which put the rear foot 3.25 m behind the hips
## at the moment the coast handed back to the planner and cost a 7 m slide into the plant.
func lead_foot(input: Vector2, yaw: float) -> int:
	var right := (-frame.foot_back(yaw)).cross(Vector3.UP).normalized()
	return 1 if frame.travel(input).dot(right) < -0.05 else 0


## +1 when the mech is travelling the way its lower body faces, -1 when it is backpedalling. The yaw
## already turns the lower body toward the travel, so this is only ever -1 for the mirrored gaits.
func roll_sign(input: Vector2, yaw: float) -> float:
	var dir := frame.travel(input)
	if dir == Vector3.ZERO:
		return 1.0
	return 1.0 if dir.dot(-frame.foot_back(yaw)) >= 0.0 else -1.0


## +1 when the travel runs the way the lower body faces, -1 when the mech is going backwards, and 0
## when it is standing: the lean is "into the travel", and the lower body only turns 80 deg toward it.
func lean_dir(input: Vector2, yaw: float) -> float:
	return 0.0 if input.length() < 0.01 else roll_sign(input, yaw)
