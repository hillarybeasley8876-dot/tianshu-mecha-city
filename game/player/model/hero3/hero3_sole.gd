class_name Hero3Sole
extends RefCounted
## Where each foot IS this instant, in WORLD space (hero-v3, brief step 3).
##
## Three sources answer that question and they are alternatives, in this order: the held air pose
## (`Hero3Air`), the stance holding the feet in the pelvis frame (`Hero3Stance`), and the step
## planner's world-locked plants and swing arcs (`Hero3Stepper`). On top of the plant sits the
## heel-to-toe roll, which moves the ANKLE without moving the sole -- so the sole and the ankle are
## two different questions and both are asked here.

## How far a swinging foot bows outboard of its own plant line. A swing that ran straight down the
## centreline passed within 1.77 m of the planted ankle for two ticks of every cycle on the back
## diagonals (lead r3 item A4's 1.8 m gate).
const SWING_BOW := 0.45
## A step lifts 0.8-1.2 m, scaled between a walk and a run.
const LIFT_WALK := 1.00
const LIFT_RUN := 1.20

var frame: Hero3Frame
var timing: Hero3Timing
var air: Hero3Air
var stance: Hero3Stance
var step: Hero3Stepper
## The lower body's yaw this tick, which the foot roll pivots around.
var yaw: float = 0.0
## How far each foot's own armour reaches below the model origin, measured off the mesh at load
## (`Hero3SoleTrim`). `Hero3Frame.ground()` is the plane the gait plants on, so without this the left
## boot stands 0.145 m inside the floor and the right one 0.024 m -- the mesh is not symmetric about
## its own origin and the origin is not at the sole (hero-v3 r9 item 1).
var trim: Array[float] = [0.0, 0.0]
## The same correction as `trim`, but per roll angle: the ankle pivot scheme in `Hero3Foot` keeps the
## sole on the ground to within a few centimetres, and this measures the rest (hero-v3 r9 item 1).
var roll_trim: Array[PackedFloat32Array] = []
## The floor under each FOOT, so a foot on a kerb and a foot on the road are not both planted on the
## body's own plane (`Hero3Ground`). Null in a scene with no world, which is every filmstrip.
var ground: Hero3Ground = null
## Seconds since the last tick, which the ground follow needs.
var delta: float = 0.0


## Where foot `i` touches the ground this instant: a world-locked plant, a point on the eased swing
## arc, or wherever the stance is holding it. This is the SOLE, not the ankle.
func contact(i: int) -> Vector3:
	var at := _contact(i)
	if ground != null and air.blend <= 0.001:
		at.y = ground.under(i, at, frame.ground(), delta)
	return at + Vector3.UP * (trim[i] + roll_lift(i))


## The extra rise this foot's sole target needs at the roll it is holding right now.
func roll_lift(i: int) -> float:
	if i >= roll_trim.size():
		return 0.0
	return Hero3SoleTrim.roll_lift(roll_trim[i], roll(i))


func _contact(i: int) -> Vector3:
	var leg: Dictionary = step.legs[i]
	if air.blend > 0.001:
		return air_ankle(i) - Vector3(0.0, float(leg["ankle_h"]), 0.0) \
				- Hero3Foot.ankle_offset(leg, roll(i), frame.foot_back(yaw))
	if stance.skating:
		return stance.contact(i, leg)
	var target := Hero3Foot.position(leg, lerpf(LIFT_WALK, LIFT_RUN, timing.run_t()))
	if bool(leg["stepping"]):
		target += frame.pelvis_right() * (SWING_BOW * float(leg["sign"]) * sin(PI * float(leg["t"])))
	return stance.replant_blend(i, leg, target)


## Where this foot's ANKLE has to be for the rolled sole to sit on the ground: the rest ankle height
## plus whatever the heel or toe pivot moved it by (lead r3 item A2), blended into the air pose.
func ankle(i: int) -> Vector3:
	if air.blend > 0.001:
		return air_ankle(i) + Vector3.UP * trim[i]
	var leg: Dictionary = step.legs[i]
	return contact(i) + Vector3(0.0, float(leg["ankle_h"]), 0.0) \
			+ Hero3Foot.ankle_offset(leg, roll(i), frame.foot_back(yaw))


## Where this leg's ankle belongs in the held air pose, from `Hero3Air`.
func air_ankle(i: int) -> Vector3:
	var leg: Dictionary = step.legs[i]
	return air.ankle(frame.hip(leg), frame.pelvis_right(), frame.pelvis_back(), float(leg["sign"]))


## Each foot's roll this instant, in radians: positive is toe up.
##
## The curve itself, the mirror for a backpedal and the idle gain are all folded into `leg["roll"]`
## by the planner, so all that is left here is the air pose's blend over it.
func roll(i: int) -> float:
	return air.roll(float(step.legs[i]["roll"]))


## Where each SOLE is being aimed, in WORLD space.
func contacts() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in step.legs.size():
		out.append(contact(i))
	return out


## Where each ANKLE is being aimed, in WORLD space. A target the leg cannot reach is a foot that
## skates, and no amount of world-locked planting hides it.
func ankles() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in step.legs.size():
		out.append(ankle(i))
	return out


## Each foot's roll this instant, in radians: positive is toe up.
func rolls() -> Array[float]:
	var out: Array[float] = []
	for i in step.legs.size():
		out.append(roll(i))
	return out
