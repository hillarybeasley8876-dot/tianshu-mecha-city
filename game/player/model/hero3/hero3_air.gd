class_name Hero3Air
extends RefCounted
## The held air pose and the landing crouch for the Tianshu mech (hero-v3, lead r3 item A6).
##
## The first gait stopped planning in the air but left the IK aiming at the plants the mech had
## already left on the ground: after a second of flight the target was 26 m away and the leg hung
## straight back and down. Flying is a core verb, so that was visible all the time. Here the plants
## are RELEASED and the legs blend to a pose over `BLEND` seconds.
##
## The landing is impact, so it gets weight: both feet go back under the hips and the pelvis dips
## over the same window `mech_tuning.gd` uses for the feel shake (`land_pose_time` for the soft dip,
## `hard_recovery` for the hard one).

const STATES: Array[StringName] = [&"hover", &"fly", &"jump", &"fall", &"plunge_dive",
		&"glide", &"assault"]
const LANDINGS: Array[StringName] = [&"land_light", &"land_heavy"]
## The states that fly FAST and flat: the feet trail further back and the knees open out, instead of
## the tucked hover pose (lead r4 item 2 -- `assault` is 84 m/s and `glide` is the 42 m/s air boost).
## Free flight is NOT in here: it has its own `flight` channel below, because its legs go back AND
## together and its knee has to stay bent enough that the leg is not reaching (lead r8 item 3).
const TRAILING: Array[StringName] = [&"assault", &"glide"]
const BLEND := 0.20
const KNEE_DEG := 48.0
const BEHIND := 1.50        ## metres the feet tuck behind the hips
const TRAIL_KNEE_DEG := 22.0
const TRAIL_BEHIND := 2.80
const SPLAY := 0.35
const TOE_DEG := -22.0
## Free flight (lead r8 item 3): the legs trail back and TOGETHER, not splayed, and the knee stays at
## `FLIGHT_KNEE_DEG`. Both ends of that number are measured: a 22 deg trail knee puts the hip-to-ankle
## span at 6.05 m, which reads as a leg reaching for a plant that is not there, and a 44 deg knee folds
## the calf 0.170 m through the thigh (`test_hero3_pieces`' flight poses). 36 deg is the straightest
## leg that still clears the calf.
## Written by `Hero3Flight` through the gait.
const FLIGHT_BEHIND := 4.20
const FLIGHT_SPLAY := 0.10
const FLIGHT_KNEE_DEG := 36.0
## The landing is impact, so it gets weight (lead r5): a 16 m machine does not SINK, it ARRIVES. The
## pelvis is all the way down inside DROP_T (3 frames at 60 fps), holds HOLD_MAX (6 frames), and comes
## back over UP_MAX with a cubic ease-out. The depth scales with the impact speed `Events.landed`
## reports, so a kerb is a dip and a 20 m drop folds the mech onto its knees.
const DROP_T := 0.05          ## 3 frames: the pelvis is down before the eye can follow
const LIGHT_DIP := 0.80       ## metres at LIGHT_IMPACT
const HEAVY_DIP := 2.30       ## metres from HEAVY_IMPACT up
const LIGHT_IMPACT := 14.0    ## m/s that reads as the lightest landing worth a crouch
const HEAVY_IMPACT := 52.0    ## `mech_tuning.heavy_feel_speed`: from here up it goes all the way down
const HOLD_MIN := 0.033
const HOLD_MAX := 0.10
const UP_MIN := 0.18
const UP_MAX := 0.30
## `fall` past this downward speed stops being a float and becomes a brace: the legs reach for the
## ground and the arms come out (lead r5).
const BRACE_SPEED := 15.0
const BRACE_KNEE_DEG := 12.0
const BRACE_SPLAY := 1.30

## 0 on the ground, 1 in the held pose.
var blend: float = 0.0
## 0 in the tucked hover pose, 1 in the flat fast-flight pose.
var trail: float = 0.0
## 0 falling gently, 1 falling fast: the legs reach down and the arms spread.
var brace: float = 0.0
## 0 in every other air state, 1 in free flight: the legs trail back and together (lead r8 item 3).
var flight: float = 0.0
## The body's forward lean in radians, positive nose down. The air pose builds its leg offset in WORLD
## space, so without this the legs would hang straight down while the mech pitches forward -- the
## opposite of trailing. Rotating the offset by the lean about the pelvis' own lateral axis is what
## puts the feet behind the mech.
var pitch: float = 0.0

var _land: float = 0.0     ## seconds left in the landing crouch
var _dip: float = 0.0
var _hold: float = 0.0
var _up: float = 0.0
var _time: float = 1.0
var _impact: float = 0.0
var _fall_speed: float = 0.0
var _reach: float = 5.6    ## hip-to-ankle distance in the pose, from KNEE_DEG
var _reach_trail: float = 5.6
var _reach_brace: float = 5.6
var _reach_flight: float = 5.6
## Was the state before this one an air state? `dash_*`, `lunge` and `locked` INHERIT it (lead r4
## item 2): they happen on the ground AND in the air and the model cannot see the floor.
var _was_air: bool = false


## Note the move state the gait just entered. Called before anything asks `want`, so a dual state
## has already been resolved against the state it inherited from.
func set_state(state: StringName) -> void:
	if not Hero3Skate.is_dual(state):
		_was_air = is_airborne(state)


## Whether the legs belong in the air pose right now. This is not always `is_airborne(state)`: a
## landing is a ground state that still needs the pose released, and a dual state keeps whatever the
## state before it was doing.
func want(state: StringName) -> bool:
	if is_airborne(state):
		return true
	if is_landing(state):
		return false
	return _was_air and Hero3Skate.is_dual(state)


## The hip-to-ankle distance that puts the knee at KNEE_DEG, from the measured bone lengths.
func setup(l1: float, l2: float) -> void:
	_reach = _reach_for(l1, l2, KNEE_DEG)
	_reach_trail = _reach_for(l1, l2, TRAIL_KNEE_DEG)
	_reach_brace = _reach_for(l1, l2, BRACE_KNEE_DEG)
	_reach_flight = _reach_for(l1, l2, FLIGHT_KNEE_DEG)


static func _reach_for(l1: float, l2: float, knee_deg: float) -> float:
	return sqrt(maxf(l1 * l1 + l2 * l2 - 2.0 * l1 * l2 * cos(PI - deg_to_rad(knee_deg)), 0.5))


static func is_airborne(state: StringName) -> bool:
	return STATES.has(state)


static func is_trailing(state: StringName) -> bool:
	return TRAILING.has(state)


static func is_landing(state: StringName) -> bool:
	return LANDINGS.has(state)


## Advance the blend and the crouch. `want` is the caller's decision that the legs should be in the
## air pose right now -- which is not always `is_airborne(state)`, because a `dash_*` or a `lunge`
## happens on the ground AND in the air and the model cannot see the floor (lead r4 item 2).
## Returns true on the tick the legs come back to the ground, so the caller knows to put both feet
## under the hips.
func update(delta: float, want: bool, state: StringName) -> bool:
	var was := blend
	blend = move_toward(blend, 1.0 if want else 0.0, delta / BLEND)
	trail = move_toward(trail, 1.0 if (want and is_trailing(state)) else 0.0, delta / BLEND)
	var bracing := want and state == &"fall" and _fall_speed > BRACE_SPEED
	brace = move_toward(brace, 1.0 if bracing else 0.0, delta / BLEND)
	_land = maxf(_land - delta, 0.0)
	return was > 0.0 and blend <= 0.0


## The touchdown speed `Events.landed` reported, and the current downward speed. The first sets how
## deep the crouch goes, the second how hard the mech braces in the air (lead r5).
func set_impact(speed: float) -> void:
	_impact = maxf(speed, 0.0)


func set_fall_speed(speed: float) -> void:
	_fall_speed = maxf(speed, 0.0)


func begin_landing(state: StringName) -> void:
	if _land > 0.0:
		return  # `set_locomotion` runs every tick: re-arming would pin the pelvis at full depth
	var k := clampf((_impact - LIGHT_IMPACT) / (HEAVY_IMPACT - LIGHT_IMPACT), 0.0, 1.0)
	if state != &"land_heavy":
		k = minf(k, 0.75)  # the body already called this one light; do not fold it onto its knees
	_dip = lerpf(LIGHT_DIP, HEAVY_DIP, k)
	_hold = lerpf(HOLD_MIN, HOLD_MAX, k)
	_up = lerpf(UP_MIN, UP_MAX, k)
	_time = DROP_T + _hold + _up
	_land = _time
	# The feet are ON the floor the instant the body reports a landing, so the air pose is released at
	# once: while it was still blending out the pelvis sank 2.4 m with the legs tucked and the knees
	# never folded at all (measured: 46 deg at the deepest, against 120 deg for a planted crouch).
	blend = 0.0
	trail = 0.0
	brace = 0.0


## True while a landing crouch is still running.
func landing() -> bool:
	return _land > 0.0


## How much deeper the pelvis sits because of the landing crouch, in metres: DOWN inside three frames,
## held, then back up on a cubic ease-out, so it reads as an arrival rather than a sink.
func dip() -> float:
	if _land <= 0.0:
		return 0.0
	var t := _time - _land
	if t < DROP_T:
		return _dip * (t / DROP_T)
	if t < DROP_T + _hold:
		return _dip
	var u := clampf((t - DROP_T - _hold) / maxf(_up, 0.01), 0.0, 1.0)
	return _dip * pow(1.0 - u, 3.0)


## How deep this landing crouch is going, 0..1, for anything that wants to scale with it.
func dip_ratio() -> float:
	return clampf((_dip - LIGHT_DIP) / (HEAVY_DIP - LIGHT_DIP), 0.0, 1.0)


## Where this leg's ANKLE belongs in the held pose: `behind` behind the hip along the pelvis' back
## axis, `SPLAY` outboard along its stance axis, and far enough below that the knee sits at the pose's
## own bend. `trail` opens the pose out for fast flat flight and `flight` brings the legs together
## behind the mech; `pitch` then swings the whole offset back with the body's lean.
func ankle(hip: Vector3, right: Vector3, back: Vector3, side: float) -> Vector3:
	var behind := lerpf(BEHIND, TRAIL_BEHIND, trail)
	var reach := lerpf(_reach, _reach_trail, trail)
	var lateral := SPLAY * side
	behind = lerpf(behind, FLIGHT_BEHIND, flight)
	reach = lerpf(reach, _reach_flight, flight)
	lateral = lerpf(lateral, FLIGHT_SPLAY * side, flight)
	# falling fast: the legs come out from under the body and reach for the ground they can see
	behind = lerpf(behind, 0.0, brace)
	reach = lerpf(reach, _reach_brace, brace)
	lateral = lerpf(lateral, BRACE_SPLAY * side, brace)
	var vertical := sqrt(maxf(reach * reach - behind * behind - lateral * lateral, 0.5))
	var offset := right * lateral + back * behind - Vector3(0.0, vertical, 0.0)
	if absf(pitch) > 1e-4:
		offset = offset.rotated(right, -pitch)
	return hip + offset


## The foot roll in the air: toes down, blended in with the pose itself.
func roll(ground_roll: float) -> float:
	if blend <= 0.001:
		return ground_roll
	return lerpf(ground_roll, deg_to_rad(TOE_DEG), blend)
