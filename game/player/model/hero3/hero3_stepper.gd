class_name Hero3Stepper
extends RefCounted
## The step planner for the Tianshu mech (hero-v3, brief step 3): the phase clock, what triggers a
## step, where the foot lands, and the footstep that follows.
##
## A plant is a WORLD point, so a planted foot physically cannot slide -- the only way it can move is
## a step. Every foot's swing window is a fixed slice of its own period, so the gait is perfectly
## periodic: double support and flight are properties of the duty factor, not of a race between two
## independently triggered steps (which is how the first pass got 92 % flight at a walk).
##
## `Hero3Gait` owns the state machine around this; the planner itself only ever advances.

## Emitted on every touchdown: which foot, where its sole landed in WORLD space, and the ground speed.
signal footstep(side: String, position: Vector3, speed: float)

## How far the ideal spot may drift before a standing mech steps.
const STEP_TRIGGER := 0.45
## How fast a foot's heel-to-toe roll fades in and out, in seconds. Only a foot that is actually
## stepping may roll: at idle the phase clock keeps running at TURN_CYCLE, and rolling a planted foot
## heel-to-toe and then snapping it flat when its swing window came and went moved the ankle 1.10 m
## in a single tick (lead r4 item 5, `probe_idle_pop.gd`).
const ROLL_FADE := 0.12
## Each foot plants this far outboard of its own hip head (lead r3 item A3): the hip heads are
## 2.46 m apart and the rest pose's feet are 5.8 m apart, and planting under the hip had the two
## leg meshes sharing 807 voxels' worth of space at a walk. 0.9 m puts them about 4 m apart.
const WIDTH := 0.90
## The static leg table. `Hero3Gait.LEGS` re-exports it so the tests and the filmstrips keep asking
## the gait rather than reaching into this helper.
const LEGS: Array = [
	{"side": "R", "thigh": "R_Thigh", "calf": "R_Calf", "foot": "R_Foot", "sign": 1.0},
	{"side": "L", "thigh": "L_Thigh", "calf": "L_Calf", "foot": "L_Foot", "sign": -1.0},
]

var skeleton: Skeleton3D
var frame: Hero3Frame
var timing: Hero3Timing
## The live leg records: the measured bone indices and lengths, plus the step state
## (`planted` / `from` / `to` / `t` / `stepping` / `used` / `roll` / `gain`).
var legs: Array = []
## 0..1 through ONE FOOT'S PERIOD, which is two steps: the whole left-right cycle.
var phase: float = 0.0
## The ground speed and the local move input the planner is serving, and the travel's sign relative to
## the lower body's facing (the mirrored gaits roll their feet the other way round).
var speed: float = 0.0
var input: Vector2 = Vector2.ZERO
var roll_sign: float = 1.0
## How much of the heel-to-toe roll the feet get, 0..1. The gait turns this down as the lower body
## yaws away from the body: on a strafe the roll's 1.1 m of ankle travel runs ACROSS the 0.9 m stance
## instead of along the travel, which drove the hip-to-ankle distance from 3.5 m to 4.9 m and made the
## reach floor drop the pelvis 2.2 m -- the duck-walk the brief names (lead r9 item 3).
var roll_scale: float = 1.0


## Leg geometry is MEASURED from the exported skeleton (blender/hero3/diag_limbs.py put the joints
## there), never assumed: Skeleton3D has no get_bone_length in Godot 4, so a bone's length is the gap
## between its own rest head and its child's.
func setup(skeleton_: Skeleton3D, frame_: Hero3Frame, timing_: Hero3Timing) -> void:
	skeleton = skeleton_
	frame = frame_
	timing = timing_
	var contact := Hero3Foot.measure(skeleton)
	for spec: Dictionary in LEGS:
		legs.append(_make_leg(spec, contact.get(String(spec["side"]), Hero3Foot.FALLBACK)))


func _make_leg(spec: Dictionary, contact: Dictionary) -> Dictionary:
	var thigh := skeleton.find_bone(String(spec["thigh"]))
	var calf := skeleton.find_bone(String(spec["calf"]))
	var foot := skeleton.find_bone(String(spec["foot"]))
	var l1 := skeleton.get_bone_global_rest(thigh).origin.distance_to(
			skeleton.get_bone_global_rest(calf).origin)
	var l2 := skeleton.get_bone_global_rest(calf).origin.distance_to(
			skeleton.get_bone_global_rest(foot).origin)
	return {"spec": spec, "thigh": thigh, "calf": calf, "foot": foot, "l1": l1, "l2": l2,
			"ankle_h": skeleton.get_bone_global_rest(foot).origin.y,
			"sign": float(spec["sign"]), "heel": contact["heel"], "toe": contact["toe"],
			"hinge": contact["hinge"], "planted": Vector3.ZERO, "from": Vector3.ZERO,
			"to": Vector3.ZERO, "t": 1.0, "stepping": false, "used": false, "roll": 0.0,
			"gain": 0.0}


## Put both feet back under their hips, planted, with no step in flight. `gain` is the roll's
## steady-state value: a reset is a hard cut, not a transition, so a filmstrip that resets into a
## walk does not spend its first step fading the heel strike in.
func reset(gain: float) -> void:
	for leg: Dictionary in legs:
		var home := plant_home(leg)
		leg["planted"] = home
		leg["from"] = home
		leg["to"] = home
		leg["t"] = 1.0
		leg["stepping"] = false
		leg["gain"] = gain
	phase = 0.0


## Enter the gait cycle at a well-defined instant, with both feet where that instant says they are.
##
## A standing start is not a detail. With both feet under the hips and the clock at 0, the second foot
## waits half a period for its window -- 0.73 s, which is 6.6 m of travel at walk -- and gets dragged
## past the end of its leg before it ever lifts. So the clock is set to the moment foot 1 touches
## down (the one instant both feet have a defined place in EITHER gait: at a run the swing window is
## longer than half a period, so the windows always overlap and there is no "both planted" phase to
## enter at), and each foot is placed on the arc that instant implies.
func replant() -> void:
	var dir := frame.travel(input)
	var x := timing.excursion()
	var swing := timing.swing()
	var period := timing.cycle() * 2.0
	phase = fposmod(swing, 1.0)
	for i in legs.size():
		var leg: Dictionary = legs[i]
		var u := Hero3Timing.leg_phase(phase, i)
		var home := plant_home(leg)
		leg["used"] = false
		leg["stepping"] = false
		leg["t"] = 1.0
		if u < swing:
			leg["from"] = home - dir * (speed * u * period) - dir * x
			leg["to"] = home + dir * (speed * (swing - u) * period) + dir * x
			leg["t"] = u / swing
			leg["stepping"] = true
			leg["used"] = true
		else:
			var p := (u - swing) / maxf(1.0 - swing, 0.01)
			leg["planted"] = home + dir * (x * (1.0 - 2.0 * p))
			leg["from"] = leg["planted"]
			leg["to"] = leg["planted"]


## Both feet back under their own hips, flat, with nothing in flight: the pose a landing starts from.
func replant_under_hips() -> void:
	phase = timing.swing()
	for leg: Dictionary in legs:
		var home := plant_home(leg)
		leg["planted"] = home
		leg["from"] = home
		leg["to"] = home
		leg["t"] = 1.0
		leg["stepping"] = false
		leg["used"] = false
		leg["roll"] = 0.0
		leg["gain"] = 0.0


## The phase clock. Every foot's swing window is a fixed slice of its own period, so the gait is
## perfectly periodic: double support and flight are properties of `duty`, not of a race between two
## independently triggered steps (which is how the first pass got 92 % flight at a walk).
func plan(delta: float) -> void:
	var period := timing.cycle() * 2.0
	phase = fposmod(phase + delta / period, 1.0)
	var swing := timing.swing()
	for i in legs.size():
		var leg: Dictionary = legs[i]
		var u := Hero3Timing.leg_phase(phase, i)
		if u < swing:
			if not bool(leg["used"]):
				leg["used"] = true
				leg["from"] = leg["planted"]
				leg["stepping"] = needs_step(leg)
			if bool(leg["stepping"]):
				leg["t"] = u / swing
				leg["to"] = landing_spot(leg, (swing - u) * period)
		else:
			if bool(leg["stepping"]):
				leg["planted"] = leg["to"]
				leg["stepping"] = false
				footstep.emit(String(leg["spec"]["side"]), leg["planted"], speed)
			leg["used"] = false
		# A foot only rolls while it is part of an ACTIVE gait (lead r4 item 5): at idle the phase
		# clock keeps running at TURN_CYCLE, and rolling a planted foot heel-to-toe and then snapping
		# it flat when its swing window came and went moved the ankle 1.10 m in a single tick. The
		# gain fades over ROLL_FADE so the transition is not itself a pop, and it is applied HERE so
		# `leg["roll"]` is the roll the foot actually gets.
		leg["gain"] = move_toward(float(leg["gain"]), 1.0 if roll_active(leg) else 0.0,
				delta / ROLL_FADE)
		# the roll is read AFTER `stepping` is updated. Reading it before used last frame's flag, so
		# the tick a foot left the ground got a flat foot instead of the toe-off roll -- and without
		# that roll's 1.08 m the ankle target sat 6.29 m from a 6.16 m leg and the foot skated.
		leg["roll"] = Hero3Foot.roll(u, swing, bool(leg["stepping"])) * float(leg["gain"]) \
				* roll_sign * roll_scale


## Is this foot part of a gait that is actually stepping? A moving mech always is; a standing one is
## while its hips rotate away from the plant, which is what a turn in place is.
func roll_active(leg: Dictionary) -> bool:
	return speed > 0.6 or needs_step(leg)


## A moving mech always steps. A standing one only steps when its hips have walked away from the
## plant -- which is exactly what turning in place does, so a turn is real foot repositioning.
func needs_step(leg: Dictionary) -> bool:
	if speed > 0.6:
		return true
	return ideal(leg).distance_to(leg["planted"]) > STEP_TRIGGER


## Where this foot will land: ahead of where its hip WILL be, by the distance the hip travels while
## the foot is planted. That distance is `duty x stride` in each direction, so the foot lands
## `duty x stride` ahead and leaves the same distance behind.
func landing_spot(leg: Dictionary, time_to_land: float) -> Vector3:
	var dir := frame.travel(input)
	var hip := plant_home(leg) + dir * (speed * time_to_land)
	var spot := hip + dir * timing.excursion()
	var offset := Vector3(spot.x - hip.x, 0.0, spot.z - hip.z)
	if offset.length() > timing.reach_max():
		spot = Vector3(hip.x, spot.y, hip.z) + offset.normalized() * timing.reach_max()
	return spot


## Where this foot belongs when it is standing still: under its own hip head, pushed `stance_width`
## outboard along the PELVIS' stance axis, so the yaw that turns the lower body into a strafe carries
## the stance width with it (lead r3 item A3).
func plant_home(leg: Dictionary) -> Vector3:
	return frame.hip_ground(leg) + frame.pelvis_right() * (WIDTH * float(leg["sign"]))


## Where this foot wants to be if it is not moving: under its own hip, stance width outboard.
func ideal(leg: Dictionary) -> Vector3:
	return plant_home(leg) + frame.travel(input) * (timing.stride() * 0.5)


## How many feet are carrying the mech right now: 2 is double support, 0 is a bound's flight phase.
func support_count() -> int:
	var n := 0
	for leg: Dictionary in legs:
		if not bool(leg["stepping"]):
			n += 1
	return n


## True while this foot is on the ground. The slide measurement only counts the planted frames.
func is_planted(index: int) -> bool:
	return not bool(legs[index]["stepping"])


## The planted-foot positions in WORLD space, so a test can measure slide directly instead of
## trusting the solver: a plant is a constant here, so any movement is slide by definition.
func planted() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for leg: Dictionary in legs:
		out.append(leg["planted"])
	return out


## The ankle bone's height above the sole, measured from the exported skeleton.
func ankle_height() -> float:
	return float(legs[0]["ankle_h"])


## How far the planted foot `index` is from its own hip, horizontally: 0 is mid-stance.
func stance_offset(index: int) -> float:
	var leg: Dictionary = legs[index]
	if bool(leg["stepping"]):
		return -1.0
	var hip := frame.hip_ground(leg)
	var planted: Vector3 = leg["planted"]
	return Vector2(planted.x - hip.x, planted.z - hip.z).length()

