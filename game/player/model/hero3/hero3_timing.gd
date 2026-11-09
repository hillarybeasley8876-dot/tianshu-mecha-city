class_name Hero3Timing
extends RefCounted
## Stride, cadence and duty for the Tianshu gait (hero-v3).
##
## None of these are authored while the mech is moving. A step covers exactly the ground the mech
## covers in that step, so `stride = speed x cycle` and the feet keep up at any speed; the cadence
## falls out of the stride and the real ground speed. Standing still there is no ground speed to
## derive anything from, so a turn in place gets its own cadence -- the feet still have to keep up
## with the hips rotating under them.

## SPEC §4 ground speeds.
const WALK_SPEED := 9.0
const RUN_SPEED := 16.0
## Step length in metres: the ground distance between one foot's plant and the OTHER foot's next
## plant. 6.6 m at walk is 1.36 steps/s -- a 16 m machine, not a terrier.
const STRIDE_WALK := 6.6
const STRIDE_RUN := 8.8
const STRIDE_SLOW := 2.4
## Duty is the share of a foot's own period it spends on the ground. Double support is 2 x duty - 1,
## so 0.56 leaves the 12 % the lead's gate asks for; below 0.5 the gait bounds instead.
const DUTY_WALK := 0.56
const DUTY_RUN := 0.40
const BOUND_SPEED := 12.0
const MIN_CYCLE := 0.30
const MAX_CYCLE := 1.25
const TURN_CYCLE := 0.55
## How much of the foot's heel/toe roll may be spent on reach. The measured offsets are 0.83 m at
## heel strike and 1.08 m at push-off; the smaller one is used so the stride is never over-planned.
const ROLL_REACH := 0.80
const REACH_MARGIN := 0.95

var speed: float = 0.0
## How much of the full stride the gait may use, 0..1. The gait turns this down as the lower body
## yaws away from the body (lead r9 item 3): a side-step is a SHORT, QUICK step, and at the full walk
## stride the planted foot ends 5.45 m from a hip that a 6.16 m leg cannot reach, so the pelvis solve
## saturates and the mech drops 2.45 m into a duck-walk -- the exact thing the brief names.
var stride_scale: float = 1.0

var _rest_hip: float = 0.0
var _leg_len: float = 0.0
var _ankle_h: float = 0.0


func setup(rest_hip: float, leg_len: float, ankle_h: float) -> void:
	_rest_hip = rest_hip
	_leg_len = leg_len
	_ankle_h = ankle_h


func run_t() -> float:
	return clampf((speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0)


func duty() -> float:
	return lerpf(DUTY_WALK, DUTY_RUN, clampf((speed - BOUND_SPEED)
			/ (RUN_SPEED - BOUND_SPEED), 0.0, 1.0))


func swing() -> float:
	return 1.0 - duty()


## How far ahead of its own hip a foot may be planted.
##
## The reach is measured to the ANKLE, and the ankle is never as far out as the plant: the foot rolls
## about its heel at strike and about its toe hinge at push-off, which pulls the ankle 0.8-1.1 m back
## toward the hip (`Hero3Foot.ankle_offset`).
func reach_max() -> float:
	var arc := _rest_hip - Hero3Pelvis.DEEP_DROP - _ankle_h
	return sqrt(maxf(_leg_len * _leg_len - arc * arc, 0.0)) * REACH_MARGIN + ROLL_REACH


func stride() -> float:
	var wish := lerpf(STRIDE_SLOW, STRIDE_WALK, clampf(speed / WALK_SPEED, 0.0, 1.0))
	wish = lerpf(wish, STRIDE_RUN, run_t())
	return minf(wish, reach_max() / maxf(duty(), 0.05)) * clampf(stride_scale, 0.2, 1.0)


## How far from its own hip a foot travels while it is planted: the number the pelvis curve and the
## landing spot are both built on.
func excursion() -> float:
	return duty() * stride()


## One step's worth of travel in seconds.
func cycle() -> float:
	if speed <= 0.6:
		return TURN_CYCLE
	return clampf(stride() / maxf(speed, 0.8), MIN_CYCLE, MAX_CYCLE)


## The fastest ground speed the step planner can actually serve, in m/s. Above it one step has to
## cover more ground than the leg can reach and the feet skate, so the gait hands over to
## `Hero3Skate` (lead r4 item 2). This is MEASURED from the rig, not authored: it is where `cycle()`
## bottoms out at MIN_CYCLE with the longest stride the timing allows.
func step_limit() -> float:
	return STRIDE_RUN / MIN_CYCLE


## Where foot `i` is inside its own period: 0 at the instant it leaves the ground, `swing()` at the
## instant it lands again.
static func leg_phase(phase: float, i: int) -> float:
	return fposmod(phase - 0.5 * float(i), 1.0)
