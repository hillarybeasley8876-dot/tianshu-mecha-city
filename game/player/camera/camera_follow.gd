extends Node
## Follow geometry (camera-aim). Every question of the form "where does the rig want to be, how fast
## does it get there, and how long is its arm" lives here, so `camera_rig.gd` stays about applying the
## answers. It owns the chest pivot (SPEC §5, 12.5 m above the feet), the cockpit eye point, the
## follow spring rate (10 rad/s walking, 7 boosting, 14 dashing, 40 in the cockpit, 9 flying) and the
## arm length, including the two states that override it: a CONTRACTS §5 large-target lock and a
## flying mech (lead r7 item 3).

const PIVOT_HEIGHT := 12.5      ## chest pivot, third person (SPEC §5)
const OMEGA_WALK := 10.0        ## follow spring, rad/s walking
const OMEGA_BOOST := 7.0        ## heavier, more lag while boosting
const OMEGA_DASH := 14.0        ## tighter during a sideways dash
const OMEGA_FIRST := 40.0       ## the cockpit view is rigid: the canopy must not lag the body

var _blend: Node = null
var _large: Node = null
var _flight: Node = null
var _fov: Node = null


func setup(blend: Node, large: Node, flight: Node, fov: Node) -> void:
	_blend = blend
	_large = large
	_flight = flight
	_fov = fov


## The point the follow spring is steering at: the chest pivot, led forward by the flying mech's own
## velocity, then lerped onto the cockpit eye as the first-person blend comes in.
func target(p: Node3D, fp_t: float, fly: float) -> Vector3:
	var out := chest(p)
	if fly > 0.0:
		# CameraFlight's lead cancels the spring's ramp lag, so the pivot rides ON the mech at 84 m/s
		# instead of 24 m behind it — which is also what keeps the arm probe spanning camera → hero.
		out += (_flight.call(&"velocity") as Vector3) * float(_flight.call(&"lead")) * fly
	if fp_t > 0.0:
		out = out.lerp(_blend.call(&"cockpit_point", p) as Vector3, fp_t)
	return out


## Spring rate for this tick: the ground rate for the mech's own state, blended to the flight rate and
## then to the rigid cockpit rate.
func omega(p: Node3D, fp_t: float, fly: float) -> float:
	return lerpf(lerpf(_ground_omega(p), float(_flight.call(&"omega")), fly), OMEGA_FIRST, fp_t)


func _ground_omega(p: Node3D) -> float:
	if p.has_method(&"move_state") and p.call(&"move_state") == &"dash":
		return OMEGA_DASH
	if p.has_method(&"is_boosting") and bool(p.call(&"is_boosting")):
		return OMEGA_BOOST
	return OMEGA_WALK


## SPEC §2 heights are measured from the feet, but PlayerMech's origin is the capsule centre, so the
## chest pivot hangs off the model root (which sits on the ground) rather than the body node.
## A large-target lock lifts the pivot (CONTRACTS §5): looking 12° up along a 64 m arm would otherwise
## drop the camera below the street. The lift fades out with the first-person blend, because in the
## cockpit the follow target is the eye socket and the arm is zero.
func chest(p: Node3D) -> Vector3:
	var lift := float(_large.call(&"pivot_lift")) * (1.0 - float(_blend.call(&"value")))
	return feet(p) + Vector3.UP * (PIVOT_HEIGHT + lift)


func feet(p: Node3D) -> Vector3:
	if p.has_method(&"model"):
		var model := p.call(&"model") as Node3D
		if model != null:
			return model.global_position
	return p.global_position


## Desired arm length: the third-person arm (shortened to ARM_ADS while aiming down sights, on the FOV
## channel's own 0.25 s in / 0.40 s out ramp) blended to zero in the cockpit. A large hard-lock target
## (CONTRACTS §5) and a flying mech (lead r7 item 3) both override it: each is a state in which the
## frame must hold an actor that is moving on its own terms, and flight wins because the hero leaving
## the frame is the worse failure.
func arm(base: float, ads: float) -> float:
	var third := lerpf(base, ads, float(_fov.call(&"ads_blend")))
	third = lerpf(third, float(_large.call(&"arm")), float(_large.call(&"value")))
	third = lerpf(third, float(_flight.call(&"arm")), float(_flight.call(&"value")))
	return lerpf(third, 0.0, float(_blend.call(&"value")))
