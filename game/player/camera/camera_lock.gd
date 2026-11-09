extends Node
## Hard-lock camera tracking (camera-aim). SPEC §5: in third person the view's yaw and pitch converge
## on the locked target at 9 rad/s, so the player's own look input still adds on top and fights it; in
## the cockpit the view stays free and the rig never calls this. Owns the two guards on that tracking:
##   - audit #5: a target nearly overhead/underfoot gives an ill-conditioned yaw bearing (the
##     horizontal offset is ~0, so atan2 flips by up to 180° tick to tick and the view whips). The yaw
##     term fades out near the vertical; the pitch term is well conditioned there.
##   - CONTRACTS §5 large-target framing: pitch +12° above the locked core so a titan's head stays in
##     shot, CLAMPED so a high core cannot tip the 64 m arm far enough to bury the camera in the street.

const OMEGA := 9.0             ## critically damped lock tracking, rad/s
const MIN_CAM_Y := 3.0         ## m: floor the large-target pitch offset keeps the camera above
const YAW_FADE := Vector2(0.15, 0.35)   ## flat/length ratio over which the yaw term fades out


## `angles` is (yaw, pitch) in degrees; returns the tracked pair. `pivot` is the rig's pitch node (the
## point the view rotates about), `feet_y` the ground the hero stands on.
func track(delta: float, pivot: Node3D, target: Node3D, angles: Vector2, large: Node,
		feet_y: float, limits: Vector2) -> Vector2:
	var to := target.global_position - pivot.global_position
	if to.length_squared() < 1.0:
		return angles
	var k := 1.0 - exp(-OMEGA * delta)
	var flat := Vector2(to.x, to.z).length()
	var out := angles
	var yaw_w := smoothstep(YAW_FADE.x, YAW_FADE.y, flat / to.length())
	if yaw_w > 0.0:
		var want := rad_to_deg(atan2(-to.x, -to.z))
		out.x = wrapf(angles.x + wrapf(want - angles.x, -180.0, 180.0) * k * yaw_w, -180.0, 180.0)
	var bearing := rad_to_deg(atan2(to.y, flat))
	out.y = clampf(lerpf(angles.y, bearing + large_pitch_offset(pivot, large, feet_y, bearing), k),
			limits.x, limits.y)
	return out


## CONTRACTS §5 asks for a flat +12°, but the camera also has to stay above the street: an arm of `L`
## at pitch p drops it L·sin(p) below the pivot, so a core high on a titan would bury the shot in the
## road. No feedback loop — `bearing` is measured from the lifted pivot, which the offset cannot move.
func large_pitch_offset(pivot: Node3D, large: Node, feet_y: float, bearing_deg: float) -> float:
	var want := float(large.call(&"pitch_offset"))
	if is_zero_approx(want):
		return 0.0
	var head := pivot.global_position.y - feet_y - MIN_CAM_Y
	var limit := rad_to_deg(asin(clampf(head / float(large.call(&"arm")), 0.0, 1.0)))
	return minf(want, limit - bearing_deg)
