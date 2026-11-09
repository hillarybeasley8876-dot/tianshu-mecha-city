class_name Hero3Flight
extends RefCounted
## The flight pose language for the Tianshu (hero-v3, lead r8 item 3).
##
## mech-move r6 made flight work from every state, and the hero answered it by flying in a standing
## hover: legs under the hips, torso upright, no lean and no bank. This module is the pose, and it is
## deliberately SELF-CONTAINED -- it measures the mech's own motion off the model node it is attached
## to (the HeroModel is a child of the body, so its global transform IS the body's) rather than asking
## `PlayerMech` for a speed, a yaw rate or an `is_flying()` flag. That keeps the whole change inside
## `player/model/hero3/**` while mech-move r7 is editing `player_mech.gd`.
##
## What it produces, all of it scaled by `blend` so it fades in and out with the state:
##
##   * `lean`  -- a forward pitch that grows with the measured 3D speed: `LEAN_DEG` at the 50 m/s
##                cruise and more under the 84 m/s flight boost.
##   * `bank`  -- a roll INTO the turn, from the measured yaw rate against `turn_run_deg`, which is
##                the rate flight actually turns at.
##   * `thrust` -- the world direction the plumes should run, which is backwards along the velocity.

## The move state that means free flight. `MechAir.flight()` writes it and nothing else does, so this
## is exactly `PlayerMech.is_flying()` without reaching across the unit boundary for it.
const STATE: StringName = &"fly"
## SPEC §4 flight speeds, from `mech_tuning.gd`: 50 m/s cruise, 84 m/s with the assault jet.
const CRUISE := 50.0
const BOOST := 84.0
## Degrees of forward lean at the cruise, and the ceiling the boost is allowed to reach.
const LEAN_DEG := 25.0
const MAX_LEAN_DEG := 38.0
## `mech_tuning.turn_run_deg`: the yaw rate flight turns at, and therefore what "full bank" means.
const TURN_DEG := 120.0
const BANK_DEG := 30.0
const MAX_BANK_DEG := 38.0
## Seconds to blend the pose in and out. In is quicker than out: entering flight is a decision and
## leaving it is a glide, and a mech that snaps upright the instant the gauge empties reads as a bug.
const BLEND_IN := 0.35
const BLEND_OUT := 0.55
## A dead mech is not flying. The lead found a flight death holding its lean and its thrust direction
## for the full 0.55 s blend-out, so the death has its own cut: the plumes stop on the tick the death
## clip takes hold and the lean is gone inside `DEAD_BLEND` (lead r8, mech-move acceptance).
const DEAD_BLEND := 0.10
## Low-pass on the measured motion, in seconds. Long enough that a 400 m debug teleport is not a
## 4000 m/s lean, short enough that the pose still answers a boost inside a second.
const SMOOTH := 0.18
## 0 on the ground, 1 in the flight pose.
var blend: float = 0.0
## The measured 3D speed and yaw rate, low-passed. Reported so a gate can check the pose against them.
var speed: float = 0.0
var yaw_rate: float = 0.0
## Radians, already scaled by `blend`. Positive `lean` is nose down; positive `bank` rolls right.
var lean: float = 0.0
var bank: float = 0.0
## The world direction the thruster plumes should run: backwards along the velocity. ZERO while the
## pose is off, which tells `Hero3Rig` to leave the nozzles on their bones.
var thrust: Vector3 = Vector3.ZERO
## True while the `death` clip holds. Set by `Hero3Model`, which is the one place that sees both
## `play_action` and `stop_action`.
var dead: bool = false

var _prev_pos: Vector3 = Vector3.ZERO
var _prev_yaw: float = 0.0
var _primed: bool = false


## One physics tick of measurement. `node` is the HeroModel root, whose global transform is the
## body's; `delta` is the RAW physics delta, because this measures real motion and not the animation
## clock a hit-stop slows down.
func sample(node: Node3D, delta: float, state: StringName) -> void:
	if node == null or delta <= 0.0:
		return
	var pos := node.global_position
	var fwd := -node.global_transform.basis.z
	var yaw := atan2(-fwd.x, -fwd.z)
	if not _primed:
		_prev_pos = pos
		_prev_yaw = yaw
		_primed = true
	var raw_speed := pos.distance_to(_prev_pos) / delta
	var raw_rate := angle_difference(_prev_yaw, yaw) / delta
	var motion := pos - _prev_pos
	_prev_pos = pos
	_prev_yaw = yaw
	var k := clampf(delta / SMOOTH, 0.0, 1.0)
	speed = lerpf(speed, raw_speed, k)
	yaw_rate = lerpf(yaw_rate, raw_rate, k)
	var want := 1.0 if (state == STATE and not dead) else 0.0
	var step := DEAD_BLEND if dead else (BLEND_IN if want > 0.5 else BLEND_OUT)
	blend = move_toward(blend, want, delta / step)
	lean = deg_to_rad(minf(LEAN_DEG * speed / CRUISE, MAX_LEAN_DEG)) * blend
	bank = deg_to_rad(clampf(rad_to_deg(yaw_rate) / TURN_DEG * BANK_DEG,
			-MAX_BANK_DEG, MAX_BANK_DEG)) * blend
	thrust = Vector3.ZERO
	if blend > 0.01 and not dead:
		# the plumes run backwards along the flight path; a mech that is barely moving has no flight
		# path, so its nozzles stay on the bones they are mounted on
		thrust = -motion.normalized() if motion.length() > 1e-4 else Vector3.ZERO


## A hard cut, not a transition: a respawn or a debug teleport must not spend half a second flying.
func reset() -> void:
	dead = false
	blend = 0.0
	speed = 0.0
	yaw_rate = 0.0
	lean = 0.0
	bank = 0.0
	thrust = Vector3.ZERO
	_primed = false


func report() -> Dictionary:
	return {"blend": snappedf(blend, 0.01), "dead": dead, "speed": snappedf(speed, 0.1),
			"yaw_rate": snappedf(rad_to_deg(yaw_rate), 0.1),
			"lean": snappedf(rad_to_deg(lean), 0.1), "bank": snappedf(rad_to_deg(bank), 0.1),
			"thrust": thrust.snapped(Vector3.ONE * 0.01)}
