class_name Hero3Stance
extends RefCounted
## The non-stepping foot stances and the hand-over to and from them (hero-v3, lead r4 items 2 and 3).
##
## A stance and the step planner are ALTERNATIVES: either the feet are on world-locked plants the
## planner laid down, or they are pinned in the PELVIS frame by a stance that slides with the body.
## The two stances that exist are `Hero3Skate` (slide, dash, lunge, locked, and anything above the
## step limit) and a FULL clip's own foot targets (death, ram_kick), which is the more specific
## instruction and wins.
##
## The hand-over is INSTANT -- above the step limit a single planned step is already unreachable, so
## the feet change owner on the tick the state does -- but the stance itself blends in, measured in
## the pelvis frame so a foot is never dragged through the world behind the mech.

## How long the soles take to travel from the stance into the plants the cycle lays down when the
## mech slows back under the step limit. Long enough to read as a plant, short enough that the hip
## has not run away from the foot by the time it lands.
const REPLANT_TIME := 0.14

var skeleton: Skeleton3D
var frame: Hero3Frame
var timing: Hero3Timing
var skate: Hero3Skate
var clips: Hero3ClipPlayer = null
## The sole solver, held WEAKLY. The sole asks the stance whether it is the one holding the feet, and
## the stance asks the sole where they are as it takes them over; a strong reference each way is a
## cycle that neither RefCounted object is ever freed from.
var _sole: WeakRef = null
## The travel-direction geometry: which foot leads the stance, and which way the feet roll.
var yaw_dir: Hero3Yaw
## What the gait is doing this tick, so the stance can answer without being told twice.
var state: StringName = &"idle"
var speed: float = 0.0
var input: Vector2 = Vector2.ZERO
var yaw: float = 0.0
## Is a stance the one holding the feet right now?
var skating: bool = false
## Is a FULL clip the stance source right now, and how much authority does it have?
var clip_feet: bool = false
var clip_w: float = 0.0
## How far the stance has blended in, MONOTONIC while it holds: a blend that ran backwards on the
## way out would walk the foot back to where it started.
var stance_t: float = 0.0
## Seconds left in the stance -> planner handover.
var replant_t: float = 0.0
## Each sole's offset from its own hip when the stance took over, so it can blend in without dragging
## the foot through the world behind the mech, and the same again on the way out.
var entry_offset: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var exit_offset: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]


## 1 while this state should be skating on the ground: a skate state, or any ground state going
## faster than the step planner can serve.
func want(want_air: bool) -> float:
	if want_air:
		return 0.0
	if Hero3Skate.is_skate_state(state):
		return 1.0
	return 1.0 if speed > timing.step_limit() else 0.0


## Where this foot is while the stance holds it: pinned to its own hip on the ground.
func contact(i: int, leg: Dictionary) -> Vector3:
	# the stance is pinned in the PELVIS frame, so the foot travels with the body instead of being
	# left behind in the world. The blend in is pelvis-relative for the same reason: at 150 m/s a
	# world-locked start point is 18 m behind by the time the blend is over.
	return frame.hip_ground(leg) + entry_offset[i].lerp(offset(i, leg), stance_t)


## Just out of a stance: the sole travels from where the stance left it into the plant the cycle just
## laid down, over REPLANT_TIME, instead of snapping there.
func replant_blend(i: int, leg: Dictionary, target: Vector3) -> Vector3:
	if replant_t <= 0.0:
		return target
	var k := smoothstep(0.0, 1.0, 1.0 - replant_t / REPLANT_TIME)
	return (frame.hip_ground(leg) + exit_offset[i]).lerp(target, k)


## This foot's place in the current stance, as an offset from its own hip on the ground. A FULL clip
## (lead r4 item 3) wins over the skate: it is the more specific instruction.
func offset(i: int, leg: Dictionary) -> Vector3:
	if clip_feet:
		var target := clips.foot_target(String(leg["spec"]["side"]))
		if target != Vector3.INF:
			return skeleton.global_transform * target - frame.hip_ground(leg)
		# the clip names the OTHER foot only (ram_kick's support leg): hold this one where it is
		return entry_offset[i]
	return skate_offset(i, leg)


## This foot's place in the skate stance, as an offset from its own hip on the ground: the normal
## stance width, staggered fore and aft along the travel (lead r4 item 2).
func skate_offset(i: int, leg: Dictionary) -> Vector3:
	var lead := 1.0 if i == yaw_dir.lead_foot(input, yaw) else -1.0
	return frame.pelvis_right() * (Hero3Stepper.WIDTH * float(leg["sign"])) \
			- frame.foot_back(yaw) * (stagger() * lead)


## How far the feet are staggered fore and aft.
##
## A named skate state (slide, dash, lunge, locked) has an authored stance. A plain ground state that
## is merely going faster than the planner can step gets the GAIT'S OWN excursion instead, so that
## when the speed falls back under the limit the feet are already standing where the cycle is about to
## plant them: without this the coast handover slid each sole 3.5 m along the floor to reach its plant
## (lead r4 interim item c).
func stagger() -> float:
	if Hero3Skate.is_skate_state(state):
		return skate.stagger(state)
	return maxf(timing.excursion(), skate.stagger(state))


## How far the current stance has blended in: the clip's own weight while a FULL clip owns the feet,
## the skate's blend otherwise.
func weight() -> float:
	return clip_w if clip_feet else skate.blend


## Take the feet into the stance. `contacts` is where each sole is in WORLD space right now, so the
## stance can blend in from there without the foot being dragged through the world behind the mech.
func enter(legs: Array, contacts: Array[Vector3]) -> void:
	for i in legs.size():
		entry_offset[i] = contacts[i] - frame.hip_ground(legs[i])
		var leg: Dictionary = legs[i]
		leg["stepping"] = false
		leg["used"] = false
		leg["roll"] = 0.0
		leg["gain"] = 0.0
	stance_t = 0.0


## Hand the feet back to the step planner. The plants themselves are NOT overridden -- a plant left
## at the stance position is under the hip, and the hip runs away from it at 29 m/s, which is exactly
## the 3 m ankle miss this replaced. The caller lays the cycle out again.
func leave(legs: Array) -> void:
	for i in legs.size():
		exit_offset[i] = offset(i, legs[i])
	replant_t = REPLANT_TIME
	stance_t = 0.0


## Decide who owns the feet this tick and hand over if that changed. Returns true when the feet have
## just gone back to the planner, so the caller knows to lay the cycle out again.
func resolve(legs: Array, want_skate: float) -> bool:
	var holding := clip_feet or want_skate > 0.5
	if holding == skating:
		if holding:
			hold()
		return false
	var sole := _sole.get_ref() as Hero3Sole
	if sole == null:
		push_error("Hero3Stance: no sole solver, so the feet cannot change owner")
		return false
	# `skating` is set BEFORE the soles are read: the sole solver dispatches on it, so it has to
	# already be the stance that is asking
	skating = holding
	if holding:
		enter(legs, sole.contacts())
		return false
	leave(legs)
	return true


## Bind the sole solver the stance reads the feet's world positions from as it takes them over.
func set_sole(sole: Hero3Sole) -> void:
	_sole = weakref(sole)


## Keep the blend MONOTONIC for as long as the stance holds.
func hold() -> void:
	stance_t = maxf(stance_t, weight())


func tick(delta: float) -> void:
	replant_t = maxf(replant_t - delta, 0.0)
