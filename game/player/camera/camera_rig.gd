extends Node3D
## CameraRig (camera-aim, CONTRACTS §3): the third-person over-the-shoulder view and the first-person
## cockpit view for a 16 m mech. Registers itself as `Game.camera_rig`, follows `Game.player` at
## 120 Hz with asymmetric smoothing (no jitter, no lag spikes), and applies every Feel camera request:
## trauma shake, kick, FOV punch, boost FOV and the landing dip.
##
## Node tree (see camera_rig.tscn):
##   Yaw → Pitch → Shoulder → Arm (collision probe) → Shake (trauma/kick/dip) → Cam
## Channels beside it: Look (input), Blend (1st/3rd cross-fade), Fov, Cinematic, Feel, Lock, Large, Cockpit.
## Gameplay aim starts at the Arm node — the camera's un-shaken position — so the ray runs through the
## screen centre (the HUD reticle) and the spring arm's retraction can never shift it (juice §3.4).
## hud_state() keys: first_person (bool), ads (bool), fov (float), arm_length (float), cinematic (bool).

const InputSetup := preload("res://core/input_setup.gd")
const CockpitFrame := preload("res://player/camera/cockpit_frame.gd")

# --- geometry (SPEC §5 + lead review r2) -----------------------------------------------------------
## Lead review r2: framing wins. At 42 m and FOV 55 the placeholder hero spans ~42 % of the screen
## height, so threats beside and behind it stay visible; the 22 m arm of r1 hid them (90 % of the frame).
## SPEC says "≈ arm 40 m"; 42 m is what puts the hero mid-band (40 %) once the body's 13.5 m of depth
## is projected, and the boost/ADS offsets below keep the review's deltas (+4/+6/+10).
## ADS 34 m (review r3, up from 28): at 28 m the hero filled ~80 % of the height and ate the left third
## of the frame; 34 m measures ~60 % — a readable zoom that still leaves the threats beside it visible.
const ARM_LENGTH := 42.0
const ARM_ADS := 34.0                ## SPEC §5: aiming down sights pulls the camera in, FOV 38°
const ARM_BOOST: Dictionary = {&"quick": 46.0, &"slide": 48.0, &"assault": 52.0}
## Camera-space right offset, solved from the same framing rule: the lateral screen shift is
## `0.5 * SHOULDER / (distance * tan(fov/2) * aspect)`, and 34 % of the width at arm 42 m needs ~12 m.
const SHOULDER := 12.0
const PITCH_MIN_DEG := -70.0
const PITCH_MAX_DEG := 75.0
const DEFAULT_PITCH_DEG := -6.0     ## SPEC §5: the view starts looking slightly down
# --- rates (SPEC §5) ------------------------------------------------------------------------------
const CINE_BLEND := 0.25            ## s cross-fade between cinematic shots
const SHAKE_FALLOFF := 600.0        ## m, extra distance falloff for non-global Feel.shake origins

@onready var _look: Node = $Look
@onready var _yaw: Node3D = $Yaw
@onready var _pitch: Node3D = $Yaw/Pitch
@onready var _shoulder: Node3D = $Yaw/Pitch/Shoulder
@onready var _arm: Node3D = $Yaw/Pitch/Shoulder/Arm
@onready var _shake: Node3D = $Yaw/Pitch/Shoulder/Arm/Shake
@onready var _cam: Camera3D = $Yaw/Pitch/Shoulder/Arm/Shake/Cam
@onready var _fov: Node = $Fov
@onready var _blend: Node = $Blend
@onready var _cine: Node = $Cinematic
@onready var _feel: Node = $Feel
@onready var _large: Node = $Large
@onready var _lock: Node = $Lock
@onready var _flight: Node = $Flight
@onready var _cull: Node = $HeroCull
@onready var _follow_geom: Node = $Follow

var _yaw_deg: float = 0.0
var _pitch_deg: float = 0.0
var _follow_vel: Vector3 = Vector3.ZERO
var _prev_target: Vector3 = Vector3.ZERO   ## last follow target, for first-person velocity feed-forward
var _arm_boost: float = 0.0         ## extra arm length held while boosting
var _eye_residual: float = 0.0      ## m, |rig - the model's raw cockpit socket|, recorded in _follow


func _ready() -> void:
	Game.camera_rig = self
	InputSetup.register_actions()   # idempotent: makes the rig usable in unit demo scenes too
	_cam.make_current()
	_fov.call(&"setup", _cam)
	_cine.call(&"setup", self)
	_feel.call(&"setup", self, _fov, _shake)
	_cull.call(&"setup", _cam)
	_follow_geom.call(&"setup", _blend, _large, _flight, _fov)
	_look.connect(&"flicked", _on_flick)
	_snap_to_player()


# --- public API (CONTRACTS §3) --------------------------------------------------------------------

func camera() -> Camera3D:
	return _cam


## Horizontal camera orientation: player movement is relative to it.
func yaw_basis() -> Basis:
	return Basis(Vector3.UP, _yaw.rotation.y)


## World-space view direction, free of shake, kick and dip.
func look_dir() -> Vector3:
	return -_pitch.global_basis.z.normalized()


## Origin every gameplay aim ray starts from: the camera's UN-SHAKEN position (the arm tip, where the
## Camera3D sits before the shake node rotates it). A ray from here along `look_dir()` passes exactly
## through the screen centre, so the HUD reticle and the shot agree — starting it at the chest pivot
## instead put the ray 2.3 m below the reticle line, ~9° of error at 15 m (lead, weapons integration).
## Shake, kick and dip are applied below this node, so juice still cannot steal accuracy (juice §3.4).
func aim_origin() -> Vector3:
	return _arm.global_position


func is_first_person() -> bool:
	return bool(_blend.call(&"is_on"))


func set_first_person(on: bool) -> void:
	if on == is_first_person():
		return
	# SPEC §5: the 0.35 s blend keeps the aim point, so the crosshair never jumps off the target.
	var aim := _aim()
	var point := aim.call(&"aim_point") as Vector3 if aim != null \
			else aim_origin() + look_dir() * 200.0
	_blend.call(&"set_mode", on, point)
	Events.camera_mode_changed.emit(on)


## Metres between the first-person eye the camera sits at and the model's raw `cockpit` socket
## (lead r7 item 1 gate). 0 in third person, where the camera is on the arm.
func eye_residual() -> float:
	return _eye_residual


func is_ads() -> bool:
	return bool(_fov.call(&"is_ads"))


## Absolute look angles in degrees (yaw: 0 = the player's facing, pitch: + = up). Tools, tests and
## scripted sequences drive the view through this instead of poking at input.
func set_look(yaw_deg: float, pitch_deg: float) -> void:
	_yaw_deg = wrapf(yaw_deg, -180.0, 180.0)
	_pitch_deg = clampf(pitch_deg, PITCH_MIN_DEG, PITCH_MAX_DEG)


func look_angles() -> Vector2:
	return Vector2(_yaw_deg, _pitch_deg)


## True when the last look input came from the right stick (the soft-lock cone is wider on a pad).
func using_pad() -> bool:
	return bool(_look.call(&"using_pad"))


func is_cinematic() -> bool:
	return bool(_cine.get(&"active"))


## 0 = third person, 1 = first; the cockpit frame shows itself from 0.5 (SPEC §5 blend is 0.35 s).
func first_person_blend() -> float:
	return float(_blend.call(&"value"))


## Trauma for the shake channel (Feel routes here; origin INF = global).
func add_trauma(amount: float, origin: Vector3 = Vector3.INF) -> void:
	var falloff := 1.0
	if origin != Vector3.INF:
		falloff = clampf(1.0 - _cam.global_position.distance_to(origin) / SHAKE_FALLOFF, 0.0, 1.0)
	_shake.call(&"add_trauma", amount * falloff)


## Directional camera kick in degrees (weapon recoil, melee swing): pitch/yaw/roll.
func apply_kick(pitch_deg: float, yaw_deg: float = 0.0, roll_deg: float = 0.0, duration: float = -1.0) -> void:
	_shake.call(&"add_kick", pitch_deg, yaw_deg, roll_deg, duration)


## A look flick while hard-locked switches target (AimSystem owns the selection).
func _on_flick(direction: float) -> void:
	var aim := _aim()
	if aim != null and aim.has_method(&"switch_target"):
		aim.call(&"switch_target", direction)


## The view basis the Feel module rotates a kick direction into.
func view_basis() -> Basis:
	return _pitch.global_basis


## Boost holds a longer arm while it lasts (SPEC §5 "the world opens up"); called by CameraFeel.
func set_boost_arm(kind: StringName, active: bool) -> void:
	_arm_boost = (float(ARM_BOOST.get(kind, ARM_LENGTH)) - ARM_LENGTH) if active else 0.0


## Temporary absolute FOV (cinematics, overdrive). `s` = seconds to blend in.
func set_override_fov(degrees: float, s: float = 0.2) -> void:
	_fov.call(&"override", degrees, s)


func clear_override_fov(s: float = 0.25) -> void:
	_fov.call(&"release", s)


## SPEC §5 "occluding buildings dither to 30 %". Every tick the arm fades whatever sits between the hero
## and the camera down to 30 %; this is the manual hook for scripted beats (a boss reveal, a cinematic)
## — 0 hides the occluders, 1 leaves them solid. City-art owns the shader; join the node to the
## `camera_dither` group and give it `set_fade(amount)` or a `fade` instance shader parameter.
func occluder_fade(amount: float) -> void:
	_arm.call(&"set_fade", amount)


func hud_state() -> Dictionary:
	return {
		&"first_person": is_first_person(),
		&"ads": is_ads(),
		&"fov": float(_fov.call(&"current")),
		&"arm_length": float(_arm.call(&"current_length")),
		&"cinematic": is_cinematic(),
	}


# --- per-tick -------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# CONTRACTS §3 clocks: the camera is presentation, so every spring, lerp and decay here runs on REAL
	# time. During witch time the player keeps full speed and the world crawls — a camera on scaled time
	# would fall behind the hero; on real time it tracks exactly as it does at 1.0 time scale.
	var dt := Feel.real_delta(delta)
	if is_cinematic():
		# CONTRACTS §5: an execution times its shots on player time (a hit-stop holds the cut with the
		# finisher); presentation beats (drop-in, victory) run on real time.
		var cine_dt := Feel.player_delta(delta) if bool(_cine.get(&"player_clock")) else dt
		_cine.call(&"advance", cine_dt)
		# The shot owns the orientation: the rig's own look nodes must not add their yaw/pitch on top,
		# or a shot aimed level ends up looking 6° down.
		_yaw.rotation = Vector3.ZERO
		_pitch.rotation = Vector3.ZERO
		_shake.call(&"advance", is_first_person(), dt)
		return
	if Input.is_action_just_pressed(&"camera_toggle"):
		set_first_person(not is_first_person())
	var fp := first_person_blend()
	# CONTRACTS §5 large-target framing: one factor per tick, read by the follow pivot, the arm target
	# and the lock pitch below. It eases back to zero on its own when the lock drops.
	_large.call(&"update", dt, _hard_target())
	var p := Game.player as Node3D
	_flight.call(&"update", dt, p)
	_cull.call(&"update", first_person_blend(), p)
	_blend.call(&"advance", dt, _pitch.global_position, Vector2(_yaw_deg, _pitch_deg),
			PITCH_MIN_DEG, PITCH_MAX_DEG)
	_follow(dt, fp)
	_update_look(dt)
	_track_lock(dt)
	_track_flight(dt)
	_yaw.rotation.y = deg_to_rad(_yaw_deg + float(_blend.call(&"yaw_off")))
	_pitch.rotation.x = deg_to_rad(clampf(_pitch_deg + float(_blend.call(&"pitch_off")),
			PITCH_MIN_DEG, PITCH_MAX_DEG))
	_shoulder.position.x = lerpf(SHOULDER, 0.0, fp)
	_arm.set(&"length", _arm_target())
	_arm.call(&"set_push_bonus", maxf(float(_large.call(&"push_bonus")),
			float(_flight.call(&"push_bonus"))))
	_arm.call(&"update", dt)
	_shake.call(&"advance", is_first_person(), dt)
	_fov.call(&"update", dt, is_first_person(), Input.is_action_pressed(&"aim"))


## Critically damped follow spring (SPEC §5: 10 rad/s walking, 7 boosting, 14 in a sideways dash).
## A spring rather than an averaging filter: no jitter when the mech skates at 42 m/s, no snap on landing.
## In the cockpit the canopy is pinned to the eye point every tick, so the camera must be too: a spring
## alone trails a moving target by 2v/omega (2.1 m at boost, 4.2 m at assault — audit #4), which slides
## the camera out through the pillars. Above the canopy's 0.5 visibility the rig is therefore blended
## onto the eye point and its velocity fed forward, so the cockpit view is rigid without a jump at 1.0.
func _follow(delta: float, fp_t: float) -> void:
	var p := Game.player as Node3D
	if p == null:
		return
	_eye_residual = 0.0
	var fly := float(_flight.call(&"value")) * (1.0 - fp_t)
	var target := _follow_geom.call(&"target", p, fp_t, fly) as Vector3
	var omega := float(_follow_geom.call(&"omega", p, fp_t, fly))
	_follow_vel += ((target - global_position) * omega * omega - _follow_vel * 2.0 * omega) * delta
	global_position += _follow_vel * delta
	var rigid := smoothstep(0.5, 1.0, fp_t)
	if rigid <= 0.0:
		_prev_target = target
		return
	var want_vel := (target - _prev_target) / maxf(delta, 0.0001)
	_prev_target = target
	global_position = global_position.lerp(target, rigid)
	_follow_vel = _follow_vel.lerp(want_vel, rigid)
	if fp_t > 0.99:
		# Telemetry for the cockpit gate (lead r7 item 1): how far the eye the camera is actually
		# sitting at is from the model's `cockpit` socket. Measured HERE, in the tick that placed the
		# camera — the socket is animated, so any outside sampler reads it a tick later and reports the
		# hero's own motion as camera error.
		_eye_residual = global_position.distance_to(CockpitFrame.eye_point(p))


func _update_look(delta: float) -> void:
	var aim := _aim()
	var speed_scale := 1.0
	var assist := Vector2.ZERO
	if aim != null:
		if aim.has_method(&"look_speed_scale"):
			speed_scale = float(aim.call(&"look_speed_scale"))
		if aim.has_method(&"assist_delta"):
			assist = aim.call(&"assist_delta", delta) as Vector2
	var d: Vector2 = _look.call(&"take_delta", delta, Input.is_action_pressed(&"aim"), speed_scale)
	var invert := -1.0 if bool(Settings.get_value(&"invert_y")) else 1.0
	# invert_y flips the player's own pitch only. `assist` is already a signed "turn toward the soft
	# target" correction in the same down-positive convention (audit #6); inverting it too pushed the
	# reticle away from the target at ~25 %/s with the default aim_assist.
	_yaw_deg = wrapf(_yaw_deg - (d.x + assist.x), -180.0, 180.0)
	_pitch_deg = clampf(_pitch_deg - d.y * invert - assist.y, PITCH_MIN_DEG, PITCH_MAX_DEG)


## Lock-on tracking (third person, SPEC §5): CameraLock converges the view on the target and owns the
## near-vertical yaw guard (audit #5) and the CONTRACTS §5 large-target pitch offset. In the cockpit the
## view stays free. The offset is part of the tracked pitch, so it never jerks the view when the lock
## drops — tracking simply stops and the player owns the angle again.
func _track_lock(delta: float) -> void:
	if is_first_person():
		return
	var t := _hard_target()
	var p := Game.player as Node3D
	if t == null or p == null:
		return
	var next: Vector2 = _lock.call(&"track", delta, _pitch, t, Vector2(_yaw_deg, _pitch_deg),
			_large, _feet(p).y, Vector2(PITCH_MIN_DEG, PITCH_MAX_DEG))
	_yaw_deg = next.x
	_pitch_deg = next.y


## Flight framing (lead r7 item 3): a dead-zone pitch follow. The hero may sit DEAD of the frame's
## half-height off the view axis before the view eases back, so the player's own aim is untouched
## until the mech is genuinely leaving the frame. Never in the cockpit — the canopy is rigid.
func _track_flight(delta: float) -> void:
	if is_first_person():
		return
	var p := Game.player as Node3D
	if p == null:
		return
	var rate := float(_flight.call(&"pitch_rate", _cam, _chest(p), _pitch_deg))
	if is_zero_approx(rate):
		return
	_pitch_deg = clampf(_pitch_deg + rate * delta, PITCH_MIN_DEG, PITCH_MAX_DEG)


## Desired arm length, with the boost offset the Feel channel holds (SPEC §5 "the world opens up").
func _arm_target() -> float:
	return float(_follow_geom.call(&"arm", ARM_LENGTH + _arm_boost, ARM_ADS))


func _cockpit_point(p: Node3D) -> Vector3:
	return _blend.call(&"cockpit_point", p) as Vector3


func _chest(p: Node3D) -> Vector3:
	return _follow_geom.call(&"chest", p) as Vector3


func _feet(p: Node3D) -> Vector3:
	return _follow_geom.call(&"feet", p) as Vector3


func _aim() -> Node:
	var p := Game.player
	if p != null and p.has_method(&"aim"):
		return p.call(&"aim") as Node
	return null


func _hard_target() -> Node3D:
	var aim := _aim()
	if aim != null and aim.has_method(&"hard_target"):
		return aim.call(&"hard_target") as Node3D
	return null


# --- cinematics (execution mini-cinematics) -------------------------------------------------------

## `shots`: array of {offset: Vector3 (in anchor space), look_at: Node3D|Vector3, fov: float, t: float
## seconds from the start}. Control returns to the player after `duration`. CameraCinematic owns the
## sequencing; these are the hooks it drives on the rig.
func request_cinematic(shots: Array, duration: float, clock: StringName = &"real") -> void:
	_cine.call(&"request", shots, duration, clock)


func set_look_enabled(on: bool) -> void:
	_look.set(&"enabled", on)
	# Both ways: motion buffered while look was off (a cinematic, a HUD screen) must not land as one jump
	# when it comes back.
	_look.call(&"flush")


## Collapse the spring arm onto the pivot (cinematic shots place the camera exactly).
func set_arm_length(length: float) -> void:
	_arm.set(&"length", length)
	_arm.call(&"snap")
	_shoulder.position.x = 0.0


## Hand the view back after a cinematic. CONTRACTS §5: this ENDS the cinematic — the shot list is
## cancelled, the held FOV released, and the arm (which shots collapse to zero) restored at full length
## instead of creeping out at 10 m/s. `CameraCinematic.cancel()` never calls back into here, so calling
## this from inside a shot's own `_finish()` cannot recurse.
func end_cinematic() -> void:
	_cine.call(&"cancel")
	release_fov(0.2)
	_shoulder.position.x = lerpf(SHOULDER, 0.0, first_person_blend())
	_arm.set(&"length", _arm_target())
	_snap_to_player()
	set_look_enabled(true)


func hold_fov(degrees: float) -> void:
	_fov.call(&"override", degrees, 0.0, true)


func release_fov(s: float = 0.25) -> void:
	_fov.call(&"release", s)


## Re-seat the rig behind (or inside) the mech without easing: spawn, teleport, end of a cinematic.
func snap_to_player() -> void:
	_snap_to_player()


func hard_target() -> Node3D:
	return _hard_target()


func _snap_to_player() -> void:
	var p := Game.player as Node3D
	if p == null:
		return
	_yaw_deg = rad_to_deg(p.global_rotation.y)
	_pitch_deg = DEFAULT_PITCH_DEG
	_follow_vel = Vector3.ZERO
	# The whole transform, not just the position: a cinematic rotates the rig node itself to aim a shot,
	# and that basis has to be cleared or the view stays yawed long after control comes back.
	global_transform = Transform3D(Basis.IDENTITY,
			_cockpit_point(p) if is_first_person() else _chest(p))
	_prev_target = global_position
	_yaw.rotation.y = deg_to_rad(_yaw_deg)
	_pitch.rotation.x = deg_to_rad(_pitch_deg)
	_arm.set(&"length", _arm_target())
	_arm.call(&"snap")
