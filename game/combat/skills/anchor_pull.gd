class_name AnchorPull
extends RefCounted
## What the Skyhook does once it has bitten (skills-catalog §4.4 S2): the surface reel / swing /
## release, the light-enemy yank and the heavy pull-in with its Hook Kick. Split out of
## skyhook_anchor.gd so that file stays about the shot and the state machine; `SkyhookAnchor` owns
## the state, the cable and the anchor point, and delegates the three attached modes here.

const ARRIVE := 8.0            ## metres from the anchor at which the reel stops
const STALL_TICKS := 12        ## ticks of no progress before a reel counts as blocked (audit #9)

var ctx: SkillContext = null
var hook: SkyhookAnchor = null

var _reel_t: float = 0.0
var _swing: bool = false
var _yank_from: Vector3 = Vector3.ZERO
var _melee_held: bool = false
var _t: float = 0.0
var _stall: int = 0            ## ticks the reel has made no progress along the cable
var _last_dist: float = -1.0


func _init(ctx_: SkillContext, hook_: SkyhookAnchor) -> void:
	ctx = ctx_
	hook = hook_


func reset() -> void:
	_reel_t = 0.0
	_swing = false
	_melee_held = false
	_t = 0.0
	_stall = 0
	_last_dist = -1.0


## Called when the hook bites: the yank needs where the body started, the reel needs a clean ramp.
func on_latch() -> void:
	_reel_t = 0.0
	_t = 0.0
	_stall = 0
	_last_dist = -1.0
	var e := hook.attached_enemy()
	_yank_from = e.global_position if e != null else Vector3.ZERO


# --- surface: reel / swing / release ---------------------------------------------------------------

## Reel speed ramps 60 -> 92 m/s over 0.6 s. Aiming more than `swing_angle_deg` off the cable stops
## the reel and swings instead; at 90 deg the hook lets go and the mech keeps every bit of momentum.
func reel_speed() -> float:
	var u := clampf(_reel_t / maxf(ctx.tuning.reel_ramp, 0.0001), 0.0, 1.0)
	return lerpf(ctx.tuning.reel_start, ctx.tuning.reel_top, u)


func off_cable_angle() -> float:
	var to_anchor := hook.anchor_point() - ctx.chest()
	if to_anchor.length_squared() < 0.01:
		return 0.0
	return rad_to_deg(ctx.aim_dir_from(ctx.chest()).angle_to(to_anchor.normalized()))


## True once the aim has pulled more than 25 deg off the cable and the reel has become a swing.
func is_swinging() -> bool:
	return _swing


func tick_surface(delta: float) -> void:
	var body := ctx.player as CharacterBody3D
	if body == null:
		hook.detach_silently()
		return
	_reel_t += delta
	var to_anchor := hook.anchor_point() - ctx.chest()
	var dist := to_anchor.length()
	var dir := to_anchor.normalized() if dist > 0.01 else Vector3.UP
	var angle := off_cable_angle()
	if not _swing and angle > ctx.tuning.swing_angle_deg:
		_swing = true
	if _swing and angle >= ctx.tuning.swing_detach_deg:
		hook.detach(true)
		return
	if dist <= ARRIVE:
		hook.detach(true)
		return
	if _swing:
		_swing_step(body, dir, dist, delta)
	else:
		_reel_step(body, dir, delta)
	if Input.is_action_just_pressed(&"jump"):
		release_jump()
	elif cancel_pressed():
		hook.detach(true)


func _reel_step(body: CharacterBody3D, dir: Vector3, delta: float) -> void:
	# An anchor on the street or on anything below chest height can never satisfy `ARRIVE`: the body
	# stops on the floor first. Ending the reel when it is blocked is what stops the mech being
	# pinned to the spot at full reel speed until the player cancels (audit #9).
	if _blocked(body, dir, hook.anchor_point().distance_to(ctx.chest())):
		hook.detach(true)
		return
	body.velocity = dir * reel_speed()
	Feel.post(&"speedlines", clampf(reel_speed() / 140.0, 0.0, 1.0), 0.12)
	hook.reel_streak(delta, body.velocity)


## True when the body cannot close on the anchor any further: driven into the floor along the cable, or
## simply not getting any closer for a tenth of a second.
func _blocked(body: CharacterBody3D, dir: Vector3, dist: float) -> bool:
	if body.is_on_floor() and dir.y < -0.7:
		return true
	for i in body.get_slide_collision_count():
		var n := body.get_slide_collision(i).get_normal()
		if n.dot(dir) < -0.7:
			return true
	if _last_dist >= 0.0 and dist > _last_dist - 0.05:
		_stall += 1
	else:
		_stall = 0
	_last_dist = dist
	return _stall >= STALL_TICKS


## A swing keeps the tangential component of the current velocity and adds pull along the cable, so
## the mech arcs instead of snapping to the anchor (Pathfinder-style [APX-PF]).
func _swing_step(body: CharacterBody3D, dir: Vector3, dist: float, delta: float) -> void:
	var v := body.velocity
	var radial := dir * v.dot(dir)
	var tangent := v - radial
	var pull := dir * ctx.tuning.reel_top * clampf(dist / ctx.tuning.anchor_range, 0.25, 1.0)
	body.velocity = tangent * 0.995 + pull * delta * 8.0


## Jump while attached: let go and add +12 m/s up (SPEC / skills-catalog §4.4 S2).
func release_jump() -> void:
	var body := ctx.player as CharacterBody3D
	if body != null:
		body.velocity.y = maxf(body.velocity.y, 0.0) + ctx.tuning.release_up
	hook.detach(true)
	Events.jumped.emit()


## Dash, guard or an attack cancels the grapple (skills-catalog §4.4 S2).
func cancel_pressed() -> bool:
	return Input.is_action_just_pressed(&"boost") or Input.is_action_just_pressed(&"guard") \
			or Input.is_action_just_pressed(&"fire")


# --- attached to an enemy ---------------------------------------------------------------------------

## Light: the enemy is dragged to 18 m in front of the mech over 0.35 s, then stunned 0.6 s.
func tick_light(delta: float) -> void:
	var e := hook.attached_enemy()
	if e == null or not is_instance_valid(e) or not ctx.is_alive(e):
		hook.detach(false)
		return
	_t += delta
	hook.set_anchor_point(ctx.centre_of(e))
	var stop := ctx.origin() + ctx.facing() * ctx.tuning.yank_distance
	var u := clampf(_t / maxf(ctx.tuning.yank_time, 0.0001), 0.0, 1.0)
	e.global_position = _yank_from.lerp(stop, u * u * (3.0 - 2.0 * u))
	if u < 1.0:
		return
	var s := ctx.status_of(e)
	if s != null and s.has_method(&"apply_slow"):
		s.call(&"apply_slow", 0.0, ctx.tuning.yank_stun)
	ctx.damage(e, 0.0, HitInfo.CRUSH, &"skyhook_yank", 0.0, ctx.facing() * 2.0, ctx.centre_of(e))
	SkillFx.spawn(hook, &"spark_burst", hook.anchor_point(), Vector3.UP, 1.0)
	hook.detach(true)


## Heavy: the mech is reeled in. Melee during the reel is the Hook Kick (900 / 700).
func tick_heavy(delta: float) -> void:
	var body := ctx.player as CharacterBody3D
	var e := hook.attached_enemy()
	if body == null or e == null or not is_instance_valid(e) or not ctx.is_alive(e):
		hook.detach(false)
		return
	hook.set_anchor_point(ctx.centre_of(e))
	_reel_t += delta
	var dir := (hook.anchor_point() - ctx.chest()).normalized()
	body.velocity = dir * ctx.tuning.pull_in_speed
	if Input.is_action_just_pressed(&"melee") and not _melee_held:
		_melee_held = true
		hook_kick()
	if not Input.is_action_pressed(&"melee"):
		_melee_held = false
	if ctx.origin().distance_to(hook.anchor_point()) <= ctx.tuning.yank_distance \
			or cancel_pressed() or Input.is_action_just_pressed(&"jump"):
		hook.detach(true)


func hook_kick() -> float:
	var e := hook.attached_enemy()
	if e == null or not is_instance_valid(e):
		return 0.0
	var dealt := ctx.damage(e, ctx.tuning.hook_kick_damage, HitInfo.MELEE, &"hook_kick",
			ctx.tuning.hook_kick_impact, ctx.facing() * 14.0, ctx.centre_of(e))
	Feel.play(&"melee_heavy", ctx.centre_of(e))
	SkillFx.spawn(hook, &"spark_burst", ctx.centre_of(e), ctx.facing(), 1.4)
	return dealt
