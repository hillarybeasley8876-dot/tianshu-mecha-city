extends Node
## AimSystem (camera-aim, CONTRACTS §5): the player's aim component. Turns the camera into a shooting
## direction (crosshair ray + parallax-corrected muzzle direction), finds the soft-lock target under the
## crosshair, owns the hard lock (toggle, switch, LOS loss) and answers the missile lock box query.
## It is instanced as a child of PlayerMech and only uses the camera rig + the &"targetable" group, so
## it also runs standalone in tests.
##
## hud_state() keys: aim_point (Vector3), hard_target (Node), soft_target (Node), first_person (bool),
## ads (bool), lock_range (float), assist (float), in_view (int), soft_distance (float, −1 = none),
## hard_distance (float, −1 = none). The HUD colours the reticle from the distances and the weapon's
## effective range (SPEC §5).

const TargetQuery := preload("res://player/aim/target_query.gd")

const RAY_LENGTH := 1500.0         ## CONTRACTS §5: aim_point is the hit or a point at 1,500 m
const LOS_GRACE := 0.5             ## SPEC §5: hidden this long and the hard lock drops
const STICK_SLOWDOWN := 0.55       ## SPEC §5: pad aim slowdown inside the cone
const ASSIST_PULL := 0.25          ## fraction of the aim error corrected per second (mouse)
const LEAD_TIME := 0.12            ## s the soft-lock assist leads a moving target by (SPEC §5)
## Seconds the keep-cone test is suspended after a deliberate `switch_target`, so the lock framing can
## swing the view onto the newly picked target before it is judged. Long enough for the worst realistic
## step (the 9 rad/s tracking closes ~63 % of the gap in 0.11 s, ~95 % in 0.33 s); short enough that
## turning away from a switched lock still drops it almost immediately.
const SWITCH_GRACE := 0.35

var lock_range: float = TargetQuery.HARD_RANGE

var _query := TargetQuery.new()
var _rig: Node3D = null
var _hard: Targetable = null
var _soft: Targetable = null
var _aim_point: Vector3 = Vector3.ZERO
var _los_lost: float = 0.0
var _switch_grace: float = 0.0     ## s left before the keep cone applies again after a switch
var _in_view: int = 0


func _ready() -> void:
	_rig = Game.camera_rig


func _physics_process(delta: float) -> void:
	if _rig == null or not is_instance_valid(_rig):
		_rig = Game.camera_rig
	_update_aim_point()
	_update_soft()
	_update_hard(delta)
	if Input.is_action_just_pressed(&"lock_on"):
		toggle_lock()
	_read_switch_input()


# --- public API (CONTRACTS §5) --------------------------------------------------------------------

## Crosshair hit point, or a point 1,500 m out when the ray hits nothing.
func aim_point() -> Vector3:
	return _aim_point


## Direction from a muzzle to the aim point, corrected for the parallax between camera and gun: if
## something blocks the muzzle's own line first, that is what the shot would hit.
func aim_dir_from(from: Vector3) -> Vector3:
	var to := _aim_point - from
	var dist := to.length()
	if dist < 0.01:
		return _view_dir()
	var dir := to / dist
	var hit := _ray(from, from + dir * dist)
	if not hit.is_empty():
		return (hit["position"] as Vector3 - from).normalized()
	return dir


func hard_target() -> Targetable:
	return _hard if _is_valid(_hard) else null


func soft_target() -> Targetable:
	return _soft if _is_valid(_soft) else null


## Missile painting box: SPEC §5 24°×16° around the crosshair, line-of-sight checked, best first
## (priority, then closest to the crosshair).
func targets_in_view(max_count: int, max_range: float) -> Array[Targetable]:
	var out: Array[Targetable] = []
	var origin := _origin()
	var view := _view_basis()
	var space := _space()
	if space == null:
		return out
	for t in _query.candidates(space, origin, minf(max_range, lock_range)):
		var angles := _query.angles_to(t.global_position, origin, view)
		if absf(angles.x) > TargetQuery.BOX_YAW_DEG * 0.5 or absf(angles.y) > TargetQuery.BOX_PITCH_DEG * 0.5:
			continue
		out.append(t)
	out.sort_custom(func(a: Targetable, b: Targetable) -> bool:
			return _view_rank(a, origin, view) < _view_rank(b, origin, view))
	_in_view = out.size()
	if out.size() > max_count:
		out.resize(max_count)
	return out


func camera() -> Camera3D:
	if _rig != null and is_instance_valid(_rig) and _rig.has_method(&"camera"):
		return _rig.call(&"camera") as Camera3D
	return get_viewport().get_camera_3d() if is_inside_tree() else null


func is_first_person() -> bool:
	return _rig != null and is_instance_valid(_rig) and bool(_rig.call(&"is_first_person"))


func hud_state() -> Dictionary:
	return {
		&"aim_point": _aim_point,
		&"hard_target": hard_target(),
		&"soft_target": soft_target(),
		&"first_person": is_first_person(),
		&"ads": _is_ads(),
		&"lock_range": lock_range,
		&"assist": assist_strength(),
		&"in_view": _in_view,
		&"soft_distance": _distance_to(soft_target()),
		&"hard_distance": _distance_to(hard_target()),
	}


func _distance_to(t: Targetable) -> float:
	return -1.0 if t == null else _origin().distance_to(t.global_position)


# --- hard lock ------------------------------------------------------------------------------------

func toggle_lock() -> void:
	if hard_target() != null:
		_set_hard(null)
	else:
		_set_hard(_best_hard())


## Lock a specific target (scripted sequences: boss intros, tutorials, executions). Null releases.
func lock_to(t: Targetable) -> void:
	_set_hard(t if _is_valid(t) else null)


## Flick while locked takes the next target on that side, wrapping around. Two callers, one selection:
## the camera rig routes the mouse and right-stick flicks here (CONTRACTS §5), and `_read_switch_input`
## below routes the pad's D-pad ← / →. Keyboard and mouse switching stays the flick (SPEC §3); there is
## no wheel binding, because the wheel is weapon swap.
func switch_target(direction: float) -> void:
	if _hard == null or is_zero_approx(direction):
		return
	var space := _space()
	if space == null:
		return
	var origin := _origin()
	var view := _view_basis()
	var pool := _query.candidates(space, origin, lock_range)
	if pool.size() < 2:
		return
	var here := _query.angles_to(_hard.global_position, origin, view).x
	var best: Targetable = null
	var best_delta := INF
	var wrap_best: Targetable = null
	var wrap_delta := INF
	for t in pool:
		if t == _hard:
			continue
		var dx := _query.angles_to(t.global_position, origin, view).x - here
		var ahead := dx * direction
		if ahead > 1.0 and ahead < best_delta:
			best_delta = ahead
			best = t
		var wrapped := absf(dx - direction * 360.0)
		if wrapped < wrap_delta:
			wrap_delta = wrapped
			wrap_best = t
	var was := _hard
	_set_hard(best if best != null else wrap_best)
	if _hard != was:
		_switch_grace = SWITCH_GRACE


## SPEC §3 row "Lock-on toggle / switch | … | R3 / RS flick, D-pad ← →": the pad's D-pad is the discrete
## twin of the flick and uses the SAME selection. PadInput (core) holds the action for as long as the
## button is down, so the just-pressed edge is the press — one switch per press however long it is held.
## Only where a flick could fire: no hard lock means nothing to step off (and it must not acquire one),
## and a cinematic has both flick paths dead (the rig returns before `_update_look`, and the cinematic
## disables the look channel).
func _read_switch_input() -> void:
	if hard_target() == null or _cinematic():
		return
	if Input.is_action_just_pressed(&"lock_next"):
		switch_target(1.0)
	elif Input.is_action_just_pressed(&"lock_prev"):
		switch_target(-1.0)


func _cinematic() -> bool:
	return _rig != null and is_instance_valid(_rig) and _rig.has_method(&"is_cinematic") \
			and bool(_rig.call(&"is_cinematic"))


## SPEC §5: the lock NEVER switches by itself. It is kept while the target stays inside 1.5× the acquire
## cone, and is dropped when it has been hidden for LOS_GRACE or has died.
func _update_hard(delta: float) -> void:
	_switch_grace = maxf(_switch_grace - delta, 0.0)
	if _hard == null:
		return
	if not _is_valid(_hard) or _origin().distance_to(_hard.global_position) > lock_range:
		_set_hard(null)
		return
	# The keep cone measures where the view is POINTING, and a deliberate switch selects a target the
	# lock framing has not turned onto yet (9 rad/s, so a 40° swing needs ~0.1 s). Judging it on the
	# tick it was picked undoes the player's own input — see SWITCH_GRACE.
	if _switch_grace <= 0.0 and not _query.inside_cone(_hard, _origin(), _view_basis(),
			TargetQuery.HARD_CONE_YAW_DEG, TargetQuery.HARD_CONE_PITCH_DEG,
			TargetQuery.HARD_KEEP_SCALE):
		_set_hard(null)
		return
	var space := _space()
	var blocked := space != null and not _query.has_line_of_sight(space, _origin(), _hard.global_position)
	_los_lost = _los_lost + delta if blocked else 0.0
	if _los_lost >= LOS_GRACE:
		_set_hard(null)


func _best_hard() -> Targetable:
	var space := _space()
	if space == null:
		return null
	return _query.best_in_cone(space, _origin(), _view_basis(), lock_range,
			TargetQuery.HARD_CONE_YAW_DEG, TargetQuery.HARD_CONE_PITCH_DEG)


func _set_hard(t: Targetable) -> void:
	if t == _hard:
		return
	_hard = t
	_los_lost = 0.0
	_switch_grace = 0.0
	Events.lock_changed.emit(t)


# --- soft lock and aim assist ---------------------------------------------------------------------

## Auto-acquire inside the SPEC §5 cone (7° mouse / 10° pad) at up to 300 m with line of sight. A hard
## lock always wins: while locked the soft target IS the hard one, so the assist pulls where you aim.
func _update_soft() -> void:
	if _hard != null and _is_valid(_hard):
		_soft = _hard
		return
	var space := _space()
	if space == null:
		_soft = null
		return
	var cone := TargetQuery.SOFT_CONE_PAD_DEG if _using_pad() else TargetQuery.SOFT_CONE_MOUSE_DEG
	_soft = _query.best_in_cone(space, _origin(), _view_basis(), TargetQuery.SOFT_RANGE, cone, cone)


func assist_strength() -> float:
	return clampf(float(Settings.get_value(&"aim_assist")), 0.0, 1.0) if soft_target() != null else 0.0


## Look-rate multiplier the rig applies to the stick: 35 % slower over a target (gamepad magnetism).
func look_speed_scale() -> float:
	return lerpf(1.0, STICK_SLOWDOWN, assist_strength())


## Degrees of view rotation the assist adds this tick (same sign convention as mouse motion:
## +x turns right, +y turns down). Mild, proportional, and zero once the target is centred.
func assist_delta(delta: float) -> Vector2:
	var t := soft_target()
	var strength := assist_strength()
	if t == null or strength <= 0.0:
		return Vector2.ZERO
	var angles := _query.angles_to(lead_point(t), _origin(), _view_basis())
	var pull := ASSIST_PULL * strength * delta
	return Vector2(angles.x * pull, -angles.y * pull)


## Where to aim on a moving target: its position plus `LEAD_TIME` of velocity (SPEC §5 "lead
## prediction"). Weapons own their own projectile lead; this only steers the reticle.
func lead_point(t: Targetable) -> Vector3:
	var actor := t.actor() as Node3D
	if actor == null or not (actor is CharacterBody3D):
		return t.global_position
	var v := (actor as CharacterBody3D).velocity
	return t.global_position + v * LEAD_TIME


func _using_pad() -> bool:
	if _rig != null and is_instance_valid(_rig) and _rig.has_method(&"using_pad"):
		return bool(_rig.call(&"using_pad"))
	return false


# --- crosshair ray --------------------------------------------------------------------------------

func _update_aim_point() -> void:
	var origin := _origin()
	var dir := _view_dir()
	_aim_point = origin + dir * RAY_LENGTH
	var hit := _ray(origin, origin + dir * RAY_LENGTH)
	if not hit.is_empty():
		_aim_point = hit["position"] as Vector3


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var space := _space()
	if space == null:
		return {}
	var params := PhysicsRayQueryParameters3D.create(from, to, Layers.MASK_PLAYER_ATTACK)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	return space.intersect_ray(params)


## Aim reads the camera rig's un-shaken pivot, so shake never steals accuracy and the spring arm's
## collision retraction cannot shift the reticle (see camera_rig.gd).
func _origin() -> Vector3:
	if _rig != null and is_instance_valid(_rig) and _rig.has_method(&"aim_origin"):
		return _rig.call(&"aim_origin") as Vector3
	var cam := camera()
	if cam != null:
		return cam.global_position
	var parent := get_parent() as Node3D
	return parent.global_position if parent != null else Vector3.ZERO


func _view_basis() -> Basis:
	if _rig != null and is_instance_valid(_rig):
		var dir := _rig.call(&"look_dir") as Vector3
		return Basis.looking_at(dir, Vector3.UP)
	var cam := camera()
	return cam.global_basis if cam != null else Basis.IDENTITY


func _view_dir() -> Vector3:
	if _rig != null and is_instance_valid(_rig) and _rig.has_method(&"look_dir"):
		return _rig.call(&"look_dir") as Vector3
	return -_view_basis().z


func _space() -> PhysicsDirectSpaceState3D:
	return get_viewport().world_3d.direct_space_state if is_inside_tree() else null


func _view_rank(t: Targetable, origin: Vector3, view: Basis) -> float:
	var angles := _query.angles_to(t.global_position, origin, view)
	return angles.length() - t.priority * 100.0


func _is_ads() -> bool:
	if _rig != null and is_instance_valid(_rig) and _rig.has_method(&"is_ads"):
		return bool(_rig.call(&"is_ads"))
	return Input.is_action_pressed(&"aim")


## Untyped on purpose: a typed `Targetable` parameter rejects a freed instance at the call itself
## ("previously freed") before `is_instance_valid` can run — a lock held on a monster that just died.
func _is_valid(t: Variant) -> bool:
	return t != null and is_instance_valid(t) and (t as Targetable).is_valid_target()
