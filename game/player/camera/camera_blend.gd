extends Node
## First/third-person blend (camera-aim). Owns the 0.35 s mode cross-fade (SPEC §5), the aim point the
## cross-fade keeps on the reticle, and the cockpit eye point it fades towards. The rig asks it for the
## blend value (`value()`), the look-angle corrections (`yaw_off()` / `pitch_off()`) and the target
## position; everything else about placing the camera stays in the rig.

const CockpitFrame := preload("res://player/camera/cockpit_frame.gd")

const MODE_BLEND := 0.35            ## s, third <-> first person, keeping the aim point
const OFFSET_DECAY := 180.0        ## deg/s the leftover correction unwinds at after a blend
## hero-v3 r5 item 8: the gait dips the pelvis 0.3-0.5 m on every plant and the `cockpit` socket rides
## on the chest, so a raw read rattles the first-person view once per step. The bob is measured
## against a slow baseline and only EYE_BOB_KEEP of it reaches the camera, which leaves a swell
## instead of a shake. Lead r7 item 1 added the cap below: the correction may never carry the eye
## further than EYE_OFFSET_MAX from the socket, so travel (a fall, a jump, a heavy landing) is passed
## through almost whole and is still felt in the cockpit.
const EYE_LAG := 0.30              ## s, time constant of the baseline the bob is measured against
const EYE_BOB_KEEP := 0.35         ## fraction of the bob that reaches the view
## m, the most the eye may sit off the model's raw `cockpit` socket (lead r7 item 1 gate: <= 0.2 m).
## Above the cap the motion is effectively passed through whole, which is what a jump, a fall or a
## heavy landing should feel like in the cockpit; below it the gait's step bob is damped to a swell.
const EYE_OFFSET_MAX := 0.18

var _on: bool = false              ## the mode the player asked for
var _t: float = 0.0                ## 0 = third person, 1 = first
var _aim_point: Vector3 = Vector3.ZERO
var _yaw_off: float = 0.0
var _pitch_off: float = 0.0
var _active: bool = false
var _dt: float = 0.0
var _eye: Vector3 = Vector3.ZERO   ## the filtered eye point the rig reads
var _eye_slow: Vector3 = Vector3.ZERO
var _eye_on: bool = false
var _eye_frame: int = -1


## SPEC §5: the blend keeps the aim point, so the crosshair never jumps off the target at the toggle.
func set_mode(on: bool, aim_point: Vector3) -> void:
	if on == _on:
		return
	_aim_point = aim_point
	_active = true
	_on = on


func is_on() -> bool:
	return _on


## 0 = third person, 1 = first; the cockpit frame shows itself from 0.5.
func value() -> float:
	return _t


func yaw_off() -> float:
	return _yaw_off


func pitch_off() -> float:
	return _pitch_off


## Advance the cross-fade and the look-angle corrections that hold the reticle on `_aim_point`.
## `pivot` is the pitch node's world position; `look` the rig's own yaw/pitch in degrees.
func advance(delta: float, pivot: Vector3, look: Vector2, pitch_min: float, pitch_max: float) -> void:
	_dt = delta
	_t = move_toward(_t, 1.0 if _on else 0.0, delta / MODE_BLEND)
	if not _active:
		_yaw_off = move_toward(_yaw_off, 0.0, OFFSET_DECAY * delta)
		_pitch_off = move_toward(_pitch_off, 0.0, OFFSET_DECAY * delta)
		return
	if _t <= 0.0 or _t >= 1.0:
		_active = false
		_yaw_off = 0.0
		_pitch_off = 0.0
		return
	var to := _aim_point - pivot
	if to.length_squared() < 1.0:
		return
	# The correction peaks mid-blend and is gone at both ends.
	var weight := 4.0 * _t * (1.0 - _t)
	_yaw_off = wrapf(rad_to_deg(atan2(-to.x, -to.z)) - look.x, -180.0, 180.0) * weight
	_pitch_off = clampf(rad_to_deg(atan2(to.y, Vector2(to.x, to.z).length())) - look.y,
			pitch_min, pitch_max) * weight


## Where the cockpit view sits: the model's `cockpit` socket (SPEC §2/§5 eye band), with the gait's
## step bob damped out of it. The rig asks for this twice a tick (`_follow` and the canopy), so the
## filter only runs once per physics frame and both reads see the same point.
func cockpit_point(player: Node3D) -> Vector3:
	var frame := Engine.get_physics_frames()
	if frame == _eye_frame:
		return _eye
	_eye_frame = frame
	_eye = _filter_eye(CockpitFrame.eye_point(player))
	return _eye


func _filter_eye(want: Vector3) -> Vector3:
	if Game.has_flag("eye-raw"):
		return want  # capture affordance: film the view WITHOUT the low-pass, to show what it buys
	if not _eye_on:
		_eye_on = true
		_eye_slow = want
		return want
	_eye_slow = _eye_slow.lerp(want, clampf(_dt / EYE_LAG, 0.0, 1.0))
	var bob := want - _eye_slow
	var off := bob * (1.0 - EYE_BOB_KEEP)
	if off.length() > EYE_OFFSET_MAX:
		off = off.normalized() * EYE_OFFSET_MAX
		# Restart the baseline from the capped offset, or the filter winds up over a long fall.
		_eye_slow = want - off / (1.0 - EYE_BOB_KEEP)
	return want - off
