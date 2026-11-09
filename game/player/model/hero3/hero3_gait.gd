class_name Hero3Gait
extends Node
## Procedural locomotion for the Tianshu mech (hero-v3, brief step 3).
##
## This is NOT mocap. Human mocap on a 16 m machine gave the old hero flailing arms, bouncing
## shoulders, two locomotion cycles beating against each other and a crouched duck-walk when
## strafing. The legs here are two-bone IK on a phase-clock step planner:
##
##   * A plant is a WORLD point, so a planted foot physically cannot slide -- the only way it can
##     move is a step.
##   * The pelvis height is a CURVE OF THE PHASE, not a follower of the furthest foot. Following the
##     furthest foot is what made the first accepted walk W-shaped: during double support the two
##     feet are symmetric about the hip, so their maximum distance dips in the middle of the window
##     and the hips rose and fell again inside every step (lead r3 item A1).
##   * The lower body yaws toward the travel direction and the torso takes the yaw back, so a strafe
##     is a real side-step instead of the legs scissoring through each other (item A4).
##   * Cadence is not a constant: one step covers exactly the ground the mech covers in that step,
##     so stride = speed x cycle and the feet keep up at any speed.
##
## The work is split by responsibility (lead r6): `Hero3Stepper` owns the phase clock, the step
## triggers and the plants, `Hero3Stance` the non-stepping stances and the hand-over to and from
## them, `Hero3Sole` where each foot is this instant, and `Hero3Yaw` the lower body's heading. This
## file is the state machine that drives them and the API the rest of the game asks.

## Emitted on every touchdown: which foot, where its sole landed in WORLD space, and the ground speed.
## `mech_contact.gd` fires `Events.footstep` on a timer today, so the thud does not land when a foot
## does; the lead rewires it to this at the switch (lead r4 item 11).
signal footstep(side: String, position: Vector3, speed: float)

## How deep the pelvis may ever go. MEASURED (tests/probe_leg.gd): the hip sits 8.60 m up with a
## 5.90 m hip-to-ankle span, and the knee clamp at 135 deg leaves 3.07 m, so 2.45 m of fold is
## reachable with both feet still planted -- which is what a heavy landing needs (lead r5).
const MAX_DROP := 2.45
const WALK_SPEED := Hero3Timing.WALK_SPEED
## The static leg table, re-exported from the planner so the tests and the filmstrips keep asking the
## gait rather than reaching into its helper.
const LEGS: Array = Hero3Stepper.LEGS
const SETTLE_TIME := 0.25
const YAW_BLEND := 0.25
## How far the mech leans into its own travel at the run speed, in degrees. Scaled linearly with the
## ground speed, so a walk leans a third of it and a stand leans not at all.
const LOCO_LEAN_DEG := 9.0
## How much of the foot roll is given up at a 90 deg lower-body yaw (a pure strafe). The roll's ankle
## travel runs across the stance there instead of along the travel, and the reach floor answers by
## dropping the hips -- measured 2.23 m of pelvis drop on a strafe against 0.90 m on a walk.
const ROLL_YAW_CUT := 0.35
## How much of the walk stride is given up at a 90 deg lower-body yaw. See `Hero3Timing.stride_scale`.
const STRIDE_YAW_CUT := 0.32

var skeleton: Skeleton3D
var ik: Hero3LegIk
var posture: Hero3Posture
## The held air pose and the landing crouch (lead r3 item A6).
var air: Hero3Air
## The non-stepping ground stances: slide, dash, lunge, locked, and anything above the step limit
## (lead r4 item 2).
var skate: Hero3Skate
## The clip player, so a FULL clip can drive the root and the feet (lead r4 item 3). `Hero3Model`
## advances the clip clock BEFORE the gait for exactly this reason: the gait reads the clip's targets
## for the frame it is about to solve. The model assigns this AFTER `setup`, so `update` is what
## hands it on to the stance.
var clips: Hero3ClipPlayer = null
## The world-space reference frames every plan is built in.
var frame: Hero3Frame
## Stride, cadence and duty, derived from the ground speed rather than authored.
var timing: Hero3Timing
## The phase clock, the step triggers and the world-locked plants.
var step: Hero3Stepper
## The stances that hold the feet instead of stepping them, and the hand-over either way.
var stance: Hero3Stance
## Where each sole and ankle is this instant.
var sole: Hero3Sole
## The lower body's heading relative to the travel direction.
var yaw_dir: Hero3Yaw

var _rest_hip: float = 0.0     ## measured: the thigh head's rest height, 8.60 m
var _leg_len: float = 0.0      ## measured: thigh + calf, 6.16 m
var _state: StringName = &"idle"
var _speed: float = 0.0
var _input: Vector2 = Vector2.ZERO
var _drop: float = 0.0
var _sway: float = 0.0
var _settle: float = 0.0
var _yaw: float = 0.0          ## lower-body yaw toward the travel direction, radians
var _aim_point: Vector3 = Vector3.ZERO
var _aim_weight: float = 0.0


func setup(skeleton_: Skeleton3D) -> void:
	skeleton = skeleton_
	ik = Hero3LegIk.new()
	ik.setup(skeleton)
	posture = Hero3Posture.new()
	posture.setup(skeleton, ik)
	air = Hero3Air.new()
	skate = Hero3Skate.new()
	frame = Hero3Frame.new()
	frame.setup(skeleton, ik)
	timing = Hero3Timing.new()
	step = Hero3Stepper.new()
	step.setup(skeleton, frame, timing)
	_rest_hip = skeleton.get_bone_global_rest(int(step.legs[0]["thigh"])).origin.y
	_leg_len = float(step.legs[0]["l1"]) + float(step.legs[0]["l2"])
	air.setup(float(step.legs[0]["l1"]), float(step.legs[0]["l2"]))
	timing.setup(_rest_hip, _leg_len, float(step.legs[0]["ankle_h"]))
	yaw_dir = Hero3Yaw.new()
	yaw_dir.setup(frame)
	stance = Hero3Stance.new()
	stance.skeleton = skeleton
	stance.frame = frame
	stance.timing = timing
	stance.skate = skate
	stance.yaw_dir = yaw_dir
	sole = Hero3Sole.new()
	sole.frame = frame
	sole.timing = timing
	sole.air = air
	sole.stance = stance
	sole.step = step
	# the sole trim is measured off the mesh, in the rest pose, before anything has posed a bone.
	# `Hero3Sole.trim` is indexed by LEG, and `Hero3Stepper.LEGS` is ordered R then L.
	# `--hero3-notrim` is the r9 BEFORE baseline: no measured sole trim, no roll profile and no
	# per-foot ground ray, in the same binary as the fix (the same discipline as `--hero3-plain`).
	var bare := not String(Game.flag("hero3-notrim", "")).is_empty()
	Hero3Pelvis.drop_bias = 0.07 if bare else 0.0
	if bare:
		sole.trim = [0.0, 0.0]
		sole.roll_trim = []
	else:
		var trim := Hero3SoleTrim.measure(skeleton)
		sole.trim = [trim[1], trim[0]]
		sole.roll_trim = Hero3SoleTrim.measure_roll(skeleton, step.legs)
		sole.ground = Hero3Ground.new()
		sole.ground.setup(skeleton)
	# the stance asks the sole where the feet are as it takes them over, and the sole asks the stance
	# whether it is the one holding them: the stance's side of that is a weak reference, so the pair
	# is still freed with the gait
	stance.set_sole(sole)
	step.footstep.connect(_on_footstep)
	reset()


## The planner reports its own touchdowns; the gait re-emits them so the HeroModel API is unchanged.
func _on_footstep(side: String, position: Vector3, speed: float) -> void:
	footstep.emit(side, position, speed)


## Put both feet back under their hips, planted, with no step in flight.
func reset() -> void:
	skeleton.force_update_all_bone_transforms()
	if sole.ground != null:
		sole.ground.reset()
	# a reset is a hard cut, not a transition: the roll is already at its steady-state gain, so a
	# filmstrip that resets into a walk does not spend its first step fading the heel strike in
	step.reset(1.0 if _speed > 0.6 else 0.0)
	_drop = 0.0
	_sway = 0.0
	air.blend = 0.0
	air.trail = 0.0
	skate.blend = 0.0
	skate.burst = 0.0
	stance.skating = false
	# `stance.stance_t` is a LATCH: it only ever rises while a stance holds, and the only two places
	# it falls are `enter` and `leave`. Clearing `skating` here without clearing the latch left it
	# pinned at 1.0 for good, so the sole kept blending all the way onto the STANCE offset at a
	# standstill -- the mech stood in a skate stance with `skate.blend` at 0, and an upper-body clip
	# read as moving the right knee 1.5 m.
	stance.stance_t = 0.0
	stance.replant_t = 0.0
	_settle = 0.0
	if _speed > 0.6:
		_replant()


func set_state(state: StringName, speed: float, input_local: Vector2) -> void:
	var was_moving := _speed > 0.6
	var was_air := air.blend > 0.5
	_state = state
	_speed = speed
	timing.speed = speed
	timing.stride_scale = 1.0
	_input = input_local
	step.speed = speed
	step.input = input_local
	stance.state = state
	stance.speed = speed
	stance.input = input_local
	air.set_state(state)
	if was_moving and speed <= 0.6:
		_settle = SETTLE_TIME
	# no replant into the air: `Hero3Air` owns the legs there, and laying a cycle out first leaves a
	# foot flagged as stepping for the whole flight
	if not was_moving and speed > 0.6 and not Hero3Air.is_airborne(state) \
			and not Hero3Air.is_landing(state):
		_replant()
	if was_air and Hero3Air.is_landing(state) and not air.landing():
		air.begin_landing(state)
		step.replant_under_hips()


## The touchdown the game just reported (`Events.landed`), and the mech's current downward speed:
## the first scales the landing crouch, the second braces the air pose (lead r5).
func set_impact(speed: float) -> void:
	air.set_impact(speed)


func set_fall_speed(speed: float) -> void:
	air.set_fall_speed(speed)


## Free flight's pose inputs (lead r8 item 3), pushed in by `Hero3Model` from `Hero3Flight`: how much
## of the flight pose is blended in, and how far the body is pitched forward. The legs need both --
## they are built in world space, so without the pitch they would hang straight down under a mech
## that is leaning into its own flight path.
func set_flight(blend: float, pitch: float) -> void:
	air.flight = clampf(blend, 0.0, 1.0)
	air.pitch = pitch


## Enter the gait cycle at a well-defined instant, with both feet where that instant says they are.
## The lower body is already turned when the gait starts: blending the yaw in from zero would swing
## the hips 2 m sideways while the plants are still placed for the old heading, and the legs start
## the strafe stretched across each other.
func _replant() -> void:
	_yaw = yaw_dir.target(_input, _speed)
	sole.yaw = _yaw
	stance.yaw = _yaw
	step.replant()


## Take the feet into a stance, or hand them back to the step planner. The hand-over is INSTANT --
## above the step limit a single planned step is already unreachable -- while the stance itself
## (pelvis depth, lean, arm pull) blends over `Hero3Skate.BLEND` or the clip's own weight.
func _resolve_stance(want_skate: float) -> bool:
	if stance.resolve(step.legs, want_skate):
		_replant()
	return stance.skating


# --- the pelvis --------------------------------------------------------------------------------

## The pelvis depth this instant: the phase curve, floored by what the legs can actually reach, and
## lifted back to rest height in the air. `Hero3Pelvis` owns the curve itself.
func _pelvis_drop() -> float:
	var ground := maxf(Hero3Pelvis.curve(step.phase, timing.duty(),
			clampf(_speed / WALK_SPEED, 0.0, 1.0)), _need_now())
	if skate.blend > 0.001:
		ground = maxf(lerpf(ground, skate.drop(_state), skate.blend), _need_now())
	return clampf(lerpf(ground, 0.0, air.blend) + air.dip(), -0.60, MAX_DROP)


## What the reach floor needs to know about each leg this instant: how far the ankle is from the hip
## horizontally, how high it is, and how much this foot constrains the hips at all.
func _need_now() -> float:
	var entries: Array = []
	for i in step.legs.size():
		var leg: Dictionary = step.legs[i]
		var weight := 1.0
		if bool(leg["stepping"]):
			# a swinging foot only constrains the hips once it is close to landing
			weight = smoothstep(0.55, 1.0, float(leg["t"]))
		var hip := frame.hip_ground(leg)
		var ankle := sole.ankle(i)
		entries.append({"flat": Vector2(ankle.x - hip.x, ankle.z - hip.z).length(),
				"ankle_y": ankle.y, "weight": weight})
	return Hero3Pelvis.need(_rest_hip, _leg_len, entries)


func _apply_pelvis(delta: float) -> void:
	_yaw = lerpf(_yaw, yaw_dir.target(_input, _speed), clampf(delta / YAW_BLEND, 0.0, 1.0))
	sole.yaw = _yaw
	stance.yaw = _yaw
	ik.pole = Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	_drop = _pelvis_drop()
	_sway = Hero3Pelvis.sway(step.phase, timing.duty(), clampf(_speed / WALK_SPEED, 0.0, 1.0),
			timing.run_t(), air.blend)
	posture.drop = _drop
	posture.sway = _sway
	posture.root_z = 0.0
	posture.clip_pitch = 0.0
	posture.clip_roll = 0.0
	# A FULL clip keys the ROOT rather than the leg bones (lead r4 item 3): its translation replaces
	# the pelvis curve outright, which is how death gets 4 m down to one knee and then onto the floor.
	var root_w := clips.root_weight() if clips != null else 0.0
	if root_w > 0.0:
		var root := clips.root_pose()
		if not root.is_empty():
			var offset: Vector3 = root[0]
			posture.drop = lerpf(_drop, -offset.y, root_w)
			posture.sway = lerpf(_sway, offset.x, root_w)
			posture.root_z = offset.z * root_w
			posture.clip_pitch = float(root[1]) * root_w
			posture.clip_roll = float(root[2]) * root_w
	posture.yaw = _yaw
	posture.phase = step.phase
	posture.speed = _speed
	posture.walk_speed = WALK_SPEED
	posture.settle = _settle
	posture.air = air.blend
	posture.aim_point = _aim_point
	posture.aim_weight = _aim_weight
	# The lean is the whole story of "this machine is going somewhere": a locomotion term that grows
	# with the ground speed (lead r9 item 3 -- measured a constant -1.8 deg at every speed before it,
	# so the mech stood bolt upright at 16 m/s), plus the skate's own harder brace on top.
	var into := yaw_dir.lean_dir(_input, _yaw)
	# A skate has its own authored brace, so the locomotion term fades out as the skate blends in --
	# adding the two folded the knee far enough to drive the calf plate through the thigh.
	posture.lean = clampf((deg_to_rad(LOCO_LEAN_DEG)
			* clampf(_speed / Hero3Timing.RUN_SPEED, 0.0, 1.0) * (1.0 - skate.blend)
			+ skate.lean(_state) * skate.blend) * into, -Hero3Posture.LEAN_MAX,
			Hero3Posture.LEAN_MAX)
	# The arms counter-swing against the legs: leg 0 (right) is forward around phase `swing/2`, so the
	# right arm is BACK there. `arm_swing` is signed once and mirrored per side in `Hero3Posture`.
	posture.arm_swing = Hero3Posture.ARM_SWING * cos(TAU * (step.phase - timing.swing() * 0.5)) \
			* clampf(_speed / Hero3Timing.WALK_SPEED, 0.0, 1.0) * (1.0 - air.blend) \
			* (1.0 - skate.blend)
	posture.pull = clampf(skate.blend * 0.6 + skate.burst * 0.4, 0.0, 1.0)
	posture.apply_pelvis()


# --- per-frame ---------------------------------------------------------------------------------

## Step length and cadence, read through from `Hero3Timing` so the tests and the filmstrips keep
## asking the gait rather than reaching into its helper.
func stride() -> float:
	return timing.stride()


func cycle() -> float:
	return timing.cycle()


func set_aim(point: Vector3, weight: float) -> void:
	_aim_point = point
	_aim_weight = clampf(weight, 0.0, 1.0)


func update(delta: float) -> void:
	if skeleton == null or step.legs.is_empty():
		return
	# the air pose is `Hero3Air`'s own decision: a landing is a ground state that still has to
	# release the pose, and a dual state inherits the one before it
	var want_air := air.want(_state)
	var want_skate := stance.want(want_air)
	skate.update(delta, want_skate, _state)
	stance.clips = clips
	stance.clip_w = clips.stance_weight() if clips != null else 0.0
	stance.clip_feet = stance.clip_w > 0.0
	if air.update(delta, want_air, _state):
		step.replant_under_hips()
	var holding := _resolve_stance(want_skate)
	if not holding and not want_air:
		step.roll_sign = yaw_dir.roll_sign(_input, _yaw)
		step.roll_scale = 1.0 - ROLL_YAW_CUT * absf(sin(_yaw))
		timing.stride_scale = 1.0 - STRIDE_YAW_CUT * absf(sin(_yaw))
		step.plan(delta)
	stance.tick(delta)
	if _settle > 0.0:
		_settle = maxf(_settle - delta, 0.0)
	sole.delta = delta
	_apply_pelvis(delta)
	ik.foot_yaw = _yaw
	for i in step.legs.size():
		ik.solve(step.legs[i], skeleton.to_local(sole.ankle(i)), sole.roll(i))
	posture.apply_torso()
	posture.apply_ready()
	posture.apply_aim()
	skeleton.force_update_all_bone_transforms()


# --- what the tests and the filmstrips measure ---------------------------------------------------
#
# The numbers live where the data does: the planner owns the plants, the sole owns the targets. The
# gait re-exports them so the tests and the filmstrips keep asking the gait rather than reaching
# into its helpers.

## The planted-foot positions in WORLD space, so a test can measure slide directly instead of
## trusting the solver: a plant is a constant here, so any movement is slide by definition.
func planted_feet() -> Array[Vector3]:
	return step.planted()


## Where each SOLE is being aimed, in WORLD space.
func foot_targets() -> Array[Vector3]:
	return sole.contacts()


## Where each ANKLE is being aimed, in WORLD space.
func ankle_targets() -> Array[Vector3]:
	return sole.ankles()


## The ankle bone's height above the sole, measured from the exported skeleton.
func ankle_height() -> float:
	return step.ankle_height()


## True while this foot is on the ground. The slide measurement only counts the planted frames.
func is_planted(index: int) -> bool:
	return step.is_planted(index)


## How many feet are carrying the mech right now: 2 is double support, 0 is a bound's flight phase.
func support_count() -> int:
	return step.support_count()


## How far the planted foot `index` is from its own hip, horizontally: 0 is mid-stance.
func stance_offset(index: int) -> float:
	return step.stance_offset(index)


## How far the stance has blended in. MONOTONIC while the stance holds, so a value that stays high
## after the state has gone is the stance never having been let go of (`probe_knee.gd`).
func debug_stance_t() -> float:
	return stance.stance_t


## The hip's height above the ground: the number the lead reads as "pelvis height" on a filmstrip.
func pelvis_height() -> float:
	return _rest_hip - _drop


## How far the lower body has turned toward the travel direction, in radians (lead r3 item A4).
func body_yaw() -> float:
	return _yaw


## 0 on the ground, 1 in the held air pose.
func air_blend() -> float:
	return air.blend


## The measured sole correction on foot `index` this tick: the static trim off the mesh plus the roll
## profile. A gate that asks where the gait is AIMING the sole subtracts this, because the aim is the
## planner's plant and the trim is the mesh correction under it.
func sole_trim(index: int) -> float:
	return sole.trim[index] + sole.roll_lift(index)


## Each foot's roll this instant, in radians: positive is toe up.
func foot_rolls() -> Array[float]:
	return sole.rolls()


func report() -> Dictionary:
	return {"state": String(_state), "speed": snappedf(_speed, 0.01),
			"trim": "L %.3f R %.3f" % [sole.trim[0], sole.trim[1]],
			"drop": snappedf(_drop, 0.01), "phase": snappedf(step.phase, 0.01),
			"stepping": "%s%s" % ["R" if bool(step.legs[0]["stepping"]) else "-",
					"L" if bool(step.legs[1]["stepping"]) else "-"],
			"cycle": snappedf(cycle(), 0.01), "stride": snappedf(stride(), 0.01),
			"cadence": snappedf(1.0 / cycle(), 0.01), "duty": snappedf(timing.duty(), 0.01),
			"yaw": snappedf(rad_to_deg(_yaw), 0.1), "air": snappedf(air.blend, 0.01),
			"skate": snappedf(skate.blend, 0.01), "burst": snappedf(skate.burst, 0.01),
			"lean": snappedf(rad_to_deg(posture.lean), 0.1),
			"step_limit": snappedf(timing.step_limit(), 0.1),
			"pelvis": snappedf(pelvis_height(), 0.01)}


