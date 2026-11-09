class_name SkyhookAnchor
extends Node3D
## S2 Skyhook Anchor (天钩锚) — grapple and traversal (skills-catalog §4.4 S2, reach x2).
##
## The cable leaves the `hand_l` socket at 360 m/s and reaches 120 m, snapping onto a locked target
## inside a 15 deg cone. What happens next depends on what it bit:
##   surface  reel 60 -> 92 m/s over 0.6 s; aim more than 25 deg off the cable turns the reel into a
##            swing that auto-detaches at 90 deg with the momentum kept; jump = release + 12 m/s up
##   light    the enemy is yanked to 18 m in front of the mech in 0.35 s and stunned for 0.6 s
##   heavy    the mech is pulled in instead; melee during the reel is the Hook Kick (900 / 700)
##   staggered  handed straight to the melee unit's execution entry (Core Rend)
## The cable has 600 HP and a miss costs the charge, so a grapple is a commitment.
##
## This file owns the shot, the latch and the state machine; `anchor_pull.gd` owns the three attached
## modes, and `cable_visual.gd` / `anchor_fx.gd` the geometry.

enum S { IDLE, FLYING, SURFACE, LIGHT, HEAVY, RETRACT }

## The cable is fired and reeled from the LEFT HAND (CONTRACTS §5): `hand_l` is the socket the
## Undertow Well already throws from, it is on the same arm as `shield_l`, and the right arm carries
## the rifle muzzle and the saber — so the line never crosses the body the camera looks at.
const CABLE_SOCKET: StringName = &"hand_l"

var ctx: SkillContext = null
var system: SkillSystem = null

var _state: int = S.IDLE
var _tip: Vector3 = Vector3.ZERO
var _dir: Vector3 = Vector3.FORWARD
var _anchor_point: Vector3 = Vector3.ZERO
var _enemy: Node3D = null
var _cable_hp: float = 0.0
var _t: float = 0.0
var _visual: CableVisual = null
var _pull: AnchorPull = null
var _cuts: int = 0
var _streak_at: float = 0.0   ## rate limit for the reel ribbons (AnchorFx.STREAK_GAP)


func setup(ctx_: SkillContext, system_: SkillSystem) -> void:
	ctx = ctx_
	system = system_
	_pull = AnchorPull.new(ctx, self)
	_visual = CableVisual.new()
	_visual.name = "CableVisual"
	add_child(_visual)
	_visual.setup(ctx.vfx)


func is_attached() -> bool:
	return _state == S.SURFACE or _state == S.LIGHT or _state == S.HEAVY


func is_busy() -> bool:
	return _state != S.IDLE


## Checked BEFORE the charge is spent: a line already in flight must not eat one.
func can_begin() -> bool:
	return ctx.player != null and not is_attached()


func cable_hp() -> float:
	return _cable_hp


func cut_count() -> int:
	return _cuts


# --- state the attached modes read and write -------------------------------------------------------

func anchor_point() -> Vector3:
	return _anchor_point


func set_anchor_point(p: Vector3) -> void:
	_anchor_point = p


func attached_enemy() -> Node3D:
	return _enemy


func reel_speed() -> float:
	return _pull.reel_speed()


func off_cable_angle() -> float:
	return _pull.off_cable_angle()


func is_swinging() -> bool:
	return _pull.is_swinging()


func release_jump() -> void:
	_pull.release_jump()


func hook_kick() -> float:
	return _pull.hook_kick()


func state() -> int:
	return _state


## Rate-limited reel ribbons; the caller is `AnchorPull._reel_step`.
func reel_streak(delta: float, velocity: Vector3) -> void:
	_streak_at -= delta
	if _streak_at > 0.0:
		return
	_streak_at = AnchorFx.STREAK_GAP
	AnchorFx.reel_streaks(ctx.vfx, ctx.chest(), velocity)


# --- firing --------------------------------------------------------------------------------------

## Shoots the cable. Returns false only when there is no mech to shoot from.
func begin() -> bool:
	if ctx.player == null:
		return false
	detach_silently()
	# Aim from the socket the cable actually leaves, not from the chest: `hand_l` rides ~4 m above the
	# chest pivot, so a direction computed at chest height and flown from the hand overshoots every low
	# anchor by about (hand_y - chest_y) / sin(pitch) -- 25 m on a deck anchor 95 m out, which is how a
	# grapple at a surface well inside the 120 m range ran out of line and missed (r4).
	_tip = ctx.socket(CABLE_SOCKET)
	_dir = ctx.aim_dir_from(_tip)
	var locked := ctx.lock_target()
	if locked != null:
		var to_locked := (ctx.centre_of(locked) - _tip).normalized()
		if rad_to_deg(_dir.angle_to(to_locked)) <= ctx.tuning.anchor_snap_deg \
				and _tip.distance_to(ctx.centre_of(locked)) <= ctx.tuning.anchor_range:
			_dir = to_locked
			_enemy = locked
	_state = S.FLYING
	_t = 0.0
	_cable_hp = ctx.tuning.cable_hp
	_visual.show_cable()
	_play_action(&"anchor_fire")
	Feel.play(&"anchor_latch", ctx.chest(), 0.5)
	return true


# --- flight --------------------------------------------------------------------------------------

## The cable tip is stepped along the ray each tick and the first thing it touches decides the mode
## (skills-catalog §4.4 S2 "Godot: ray step per tick").
func _tick_flight(delta: float) -> void:
	var from := _tip
	_tip += _dir * ctx.tuning.anchor_speed * delta
	if _enemy != null and is_instance_valid(_enemy) and ctx.is_alive(_enemy):
		var centre := ctx.centre_of(_enemy)
		if _segment_near(from, _tip, centre, 6.0):
			_latch_enemy()
			return
	var space := _space()
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(from, _tip, Layers.MASK_PLAYER_ATTACK)
		q.exclude = [_player_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			_latch_surface(hit["position"] as Vector3)
			return
	if ctx.chest().distance_to(_tip) >= ctx.tuning.anchor_range:
		_miss()


## Squared distance from `p` to the segment a-b, compared against `radius` (generous, because the
## hurtbox raycast can slip past a fast-moving enemy between ticks).
func _segment_near(a: Vector3, b: Vector3, p: Vector3, radius: float) -> bool:
	var ab := b - a
	var len2 := ab.length_squared()
	var t := 0.0 if len2 < 0.0001 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return a.distance_squared_to(p.lerp(b, t)) <= radius * radius


func _latch_enemy() -> void:
	_anchor_point = ctx.centre_of(_enemy)
	_tip = _anchor_point
	_t = 0.0
	if ctx.is_staggered(_enemy) and _try_execution(_enemy):
		detach_silently()
		return
	_state = S.HEAVY if ctx.is_heavy(_enemy) else S.LIGHT
	_pull.on_latch()
	_play_action(&"anchor_fire")
	Feel.play(&"anchor_latch", _anchor_point)
	AnchorFx.latch(self, ctx.vfx, _anchor_point, 1.2)


func _latch_surface(at: Vector3) -> void:
	_anchor_point = at
	_tip = at
	_enemy = null
	_state = S.SURFACE
	_t = 0.0
	_pull.on_latch()
	Feel.play(&"anchor_latch", at)
	AnchorFx.latch(self, ctx.vfx, at, 1.0)


func _miss() -> void:
	_state = S.RETRACT
	_t = 0.0
	_enemy = null


## Core Rend hand-off (skills-catalog §4.7 "Skyhook on a staggered target -> instant Core Rend").
func _try_execution(target: Node3D) -> bool:
	var melee := _melee_system()
	if melee == null or not melee.has_method(&"try_execution"):
		return false
	return bool(melee.call(&"try_execution", target))


func _melee_system() -> Node:
	if ctx.player == null:
		return null
	return ctx.player.get_node_or_null(^"MeleeSystem")


# --- frame ---------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	match _state:
		S.FLYING:
			_tick_flight(delta)
		S.SURFACE:
			_pull.tick_surface(delta)
		S.LIGHT:
			_pull.tick_light(delta)
		S.HEAVY:
			_pull.tick_heavy(delta)
		S.RETRACT:
			_tick_retract(delta)
		_:
			pass
	_draw()


## The cable has 600 HP: heavy attacks that land on the mech while it is reeling chew through it, and
## a knockback big enough to throw the mech off detaches outright (skills-catalog §4.4 S2 "Tension").
func damage_cable(amount: float) -> bool:
	if not is_attached() or amount <= 0.0:
		return false
	_cable_hp -= amount
	if _cable_hp <= 0.0:
		_cuts += 1
		detach(false)
		return true
	return false


## `keep_momentum` false drops the velocity with the cable (a cut line, not a release).
func detach(keep_momentum: bool) -> void:
	if _state == S.IDLE:
		return
	if not keep_momentum:
		var body := ctx.player as CharacterBody3D
		if body != null:
			body.velocity = body.velocity * 0.3
	_state = S.RETRACT
	_t = 0.0
	_enemy = null


## Drops the line with no retract animation and no momentum change (a new shot, or a reset).
func detach_silently() -> void:
	_state = S.IDLE
	_enemy = null
	_t = 0.0
	if _pull != null:
		_pull.reset()
	if _visual != null:
		_visual.hide_cable()


func _tick_retract(delta: float) -> void:
	_t += delta
	var home := ctx.socket(CABLE_SOCKET)
	var back := _tip.move_toward(home, ctx.tuning.anchor_speed * 1.5 * delta)
	_tip = back
	if _t >= 0.18 or back.distance_to(home) < 1.0:
		detach_silently()


func _draw() -> void:
	if _state == S.IDLE or not _visual.is_shown():
		return
	var tip := _tip
	if is_attached():
		tip = ctx.centre_of(_enemy) if _enemy != null and is_instance_valid(_enemy) else _anchor_point
	_visual.draw(ctx.socket(CABLE_SOCKET), tip)


func _play_action(id: StringName) -> void:
	if ctx.model != null and is_instance_valid(ctx.model) and ctx.model.has_method(&"play_action"):
		ctx.model.call(&"play_action", id)


func _player_rid() -> RID:
	var body := ctx.player as CollisionObject3D
	return body.get_rid() if body != null else RID()


func _space() -> PhysicsDirectSpaceState3D:
	if ctx.player == null or not ctx.player.is_inside_tree():
		return null
	return (ctx.player as Node3D).get_world_3d().direct_space_state


func hud_state() -> Dictionary:
	return {"anchor_attached": is_attached(), "anchor_state": _state,
			"anchor_cable_hp": maxf(_cable_hp, 0.0)}


func reset() -> void:
	detach_silently()
	_cuts = 0
	_cable_hp = 0.0
