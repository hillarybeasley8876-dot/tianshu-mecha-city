class_name RiftStep
extends Node3D
## S1 Rift Step (裂隙步) — blink (skills-catalog §4.4 S1, reach x2 for our 16 m hero).
##
## With a lock inside 90 m the stick picks the destination: neutral or forward drops the mech 14 m
## BEHIND the target facing it, left / right takes the flank 14 m to that side, back opens the range
## to 50 m. With no lock it is a straight 44 m blink in the stick direction (22 m when the stick is
## neutral the mech blinks forward). 9 f of intangible transit drawn as a streak, 6 f of recovery,
## then a 0.45 s **Ambush** window (+50 % damage, +100 % impact on the next melee or charged shot).
## A 0.6 s decoy shell stays at the origin to draw Swarmers, and the dash chain is reset on arrival.

enum S { IDLE, TRANSIT, RECOVERY }

const FACING_EPSILON := 0.15      ## stick length under this counts as neutral
const DECOY_GROUP := &"decoy"
const STREAK_COLOR := Color(0.55, 0.95, 1.0)
const RIPPLE_RADIUS := 11.0

var ctx: SkillContext = null
var system: SkillSystem = null

var _state: int = S.IDLE
var _t: float = 0.0
var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _face: Vector3 = Vector3.FORWARD
var _decoy: Node3D = null
var _decoy_left: float = 0.0
var _ghost_at: float = 0.0
var _saved_mask: int = -1


func setup(ctx_: SkillContext, system_: SkillSystem) -> void:
	ctx = ctx_
	system = system_


func is_busy() -> bool:
	return _state != S.IDLE


## The blink may only start from idle with a mech to move; checked BEFORE the charge is spent.
func can_begin() -> bool:
	return _state == S.IDLE and ctx.player != null


# --- destination table ---------------------------------------------------------------------------

## Raw (unchecked) destination. `target` is the locked enemy or null; the tests pass it explicitly so
## the table can be asserted without moving the mech.
func destination(stick: Vector2, target: Node3D = null) -> Vector3:
	var origin := ctx.origin()
	if target == null or not is_instance_valid(target):
		return origin + stick_world(stick) * ctx.tuning.rift_free
	var base := _base_of(target)
	if stick.length() < FACING_EPSILON or stick.y >= absf(stick.x):
		return base - _forward_of(target) * ctx.tuning.rift_behind
	var away := origin - base
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.01 else -ctx.facing()
	if stick.y <= -absf(stick.x):
		return base + away * ctx.tuning.rift_backoff
	return base + _right_of(target) * signf(stick.x) * ctx.tuning.rift_flank


## An enemy's origin is its FEET (enemies/body_builder.gd lifts the shape by half its height), while
## the mech's origin is its capsule CENTRE (CONTRACTS §5): the table has to compare like with like or
## the blink buries the mech 7.5 m in the floor (audit #1).
func _base_of(target: Node3D) -> Vector3:
	return target.global_position + Vector3.UP * ctx.half_height()


## Which way the mech looks on arrival: at a locked target, along the blink when there is none. The
## vector is flattened — writing a 3D facing into the body leaves the mech pitched nose-down for the
## rest of the fight, because locomotion only ever yaws (audit #2).
func arrival_facing(stick: Vector2, target: Node3D = null) -> Vector3:
	if target != null and is_instance_valid(target):
		var d := _base_of(target) - destination(stick, target)
		d.y = 0.0
		if d.length_squared() > 0.01:
			return d.normalized()
	return stick_world(stick)


## Camera-relative stick direction on the ground plane; neutral means "straight ahead".
func stick_world(stick: Vector2) -> Vector3:
	var b := ctx.move_basis()
	var dir := b.x * stick.x - b.z * stick.y
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = -b.z
		dir.y = 0.0
	return dir.normalized()


func _forward_of(n: Node3D) -> Vector3:
	var f := -n.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else ctx.facing()


func _right_of(n: Node3D) -> Vector3:
	return _forward_of(n).cross(Vector3.UP).normalized()


# --- execution -----------------------------------------------------------------------------------

## Starts the blink. Returns false when the mech is already in transit.
func begin() -> bool:
	if _state != S.IDLE or ctx.player == null:
		return false
	var stick := _stick()
	var target := ctx.lock_target()
	if target != null and ctx.origin().distance_to(target.global_position) > ctx.tuning.rift_lock_range:
		target = null
	_from = ctx.origin()
	_to = ctx.resolve_free_space(destination(stick, target), ctx.tuning.rift_flank)
	_face = arrival_facing(stick, target)
	_state = S.TRANSIT
	_t = 0.0
	_ghost_at = 0.0
	_spawn_decoy()
	_set_intangible(true)
	_play_action(&"rift_out")
	Feel.play(&"rift_step", _from)
	# The Rift Step signature (r1 review): a bright streak line along the whole path plus a
	# refraction ripple at the end the mech leaves from, so the travel reads in a single frame.
	if ctx.vfx != null:
		var chest := Vector3.UP * SkillContext.CHEST_HEIGHT * 0.6
		ctx.vfx.beam().flash(_from + chest, _to + chest, 3.0, STREAK_COLOR,
				maxf(ctx.tuning.rift_transit, 0.12), 3.0, 0.7)
		_ripple(_from)
	return true


func _stick() -> Vector2:
	if ctx.player != null and ctx.player.has_method(&"move_input"):
		return ctx.player.call(&"move_input")
	return Vector2.ZERO


## Collision off for the 9 f of transit (skills-catalog §4.4 S1 "Godot: collision off during
## transit"). The mask is restored in `_arrive` whatever happens.
func _set_intangible(on: bool) -> void:
	var body := ctx.player as CollisionObject3D
	if body == null:
		return
	if on:
		if _saved_mask < 0:
			_saved_mask = body.collision_mask
		body.collision_mask = 0
		if ctx.player.has_method(&"invulnerable_for"):
			ctx.player.call(&"invulnerable_for", ctx.tuning.rift_transit)
	elif _saved_mask >= 0:
		body.collision_mask = _saved_mask
		_saved_mask = -1


func tick(delta: float) -> void:
	_tick_decoy(delta)
	match _state:
		S.TRANSIT:
			_tick_transit(delta)
		S.RECOVERY:
			_tick_recovery(delta)
		_:
			pass


## Zero Shift travels, it does not pop [ZOE-ZS]: the body is swept along the line every tick and a
## ghost is dropped every other frame so the eye reads the path.
func _tick_transit(delta: float) -> void:
	_t += delta
	var u := clampf(_t / maxf(ctx.tuning.rift_transit, 0.0001), 0.0, 1.0)
	var eased := u * u * (3.0 - 2.0 * u)
	(ctx.player as Node3D).global_position = _from.lerp(_to, eased)
	_ghost_at -= delta
	if _ghost_at <= 0.0:
		_ghost_at = SkillTuning.TICK * 2.0
		SkillFx.afterimage(self, ctx.model as Node3D, 0.14, Color(0.45, 0.9, 1.0))
	if u >= 1.0:
		_arrive()


func _arrive() -> void:
	_set_intangible(false)
	var body := ctx.player as CharacterBody3D
	if body != null:
		body.velocity = Vector3.ZERO
	_face_body(_face)
	_state = S.RECOVERY
	_t = 0.0
	_play_action(&"rift_in")
	_ripple(_to)
	SkillFx.flash(self, _to + Vector3.UP * 6.0, Color(0.5, 0.9, 1.0), 4.0, 40.0, 4.0)
	Feel.fov_kick(8.0, 0.18)


## A lens-like ripple sphere: low fresnel power so it reads as a distortion of the air, not a bubble.
func _ripple(at: Vector3) -> void:
	if ctx.vfx == null:
		return
	ctx.vfx.shell().fire(at + Vector3.UP * 6.0, 0.5, RIPPLE_RADIUS, 0.4, Color(0.35, 0.8, 1.0),
			Color(0.8, 0.98, 1.0), 1.3, 1.2)


func _tick_recovery(delta: float) -> void:
	_t += delta
	if _t < ctx.tuning.rift_recovery:
		return
	_state = S.IDLE
	_t = 0.0
	if system != null:
		system.grant_ambush()
	_reset_dash_chain()


## SPEC §4 dash chain: the blink hands the mech its three dashes back. CONTRACTS §5 does not expose a
## reset yet — requested in status/skills.md; until mech-move ships it the blink just leaves the
## normal dash availability alone.
func _reset_dash_chain() -> void:
	if ctx.player.has_method(&"reset_dash_chain"):
		ctx.player.call(&"reset_dash_chain")


## Level facing only: a pitched basis on a CharacterBody3D tilts the collision capsule and every
## `ctx.facing()` consumer with it, and nothing in locomotion re-levels it (audit #2).
func _face_body(dir: Vector3) -> void:
	var body := ctx.player as Node3D
	if body == null:
		return
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	body.global_basis = Basis.looking_at(flat.normalized(), Vector3.UP)


func _play_action(id: StringName) -> void:
	if ctx.model != null and is_instance_valid(ctx.model) and ctx.model.has_method(&"play_action"):
		ctx.model.call(&"play_action", id)


# --- decoy shell ---------------------------------------------------------------------------------

## A 0.6 s shell at the origin that Swarmers prefer over the hero (skills-catalog §4.4 S1 "Tension").
## Published in the `&"decoy"` group; the enemies unit reads it when it can (see status/skills.md).
## The marker node carries the AI contract, the hologram carries the read (r1 review).
func _spawn_decoy() -> void:
	if _decoy != null and is_instance_valid(_decoy):
		_decoy.queue_free()
	_decoy = Node3D.new()
	_decoy.name = "RiftDecoy"
	_decoy.add_to_group(DECOY_GROUP)
	_decoy.set_meta(&"team", 0)
	_decoy.set_meta(&"life", ctx.tuning.rift_decoy)
	add_child(_decoy)
	_decoy.global_position = _from
	_decoy_left = ctx.tuning.rift_decoy
	if ctx.vfx != null and ctx.model != null and is_instance_valid(ctx.model):
		ctx.vfx.decoy().fire(ctx.model as Node3D, ctx.tuning.rift_decoy,
				Color(0.42, 0.86, 1.0), 2.6)
	else:
		SkillFx.afterimage(self, ctx.model as Node3D, ctx.tuning.rift_decoy,
				Color(0.35, 0.8, 1.0))


func _tick_decoy(delta: float) -> void:
	if _decoy == null or not is_instance_valid(_decoy):
		return
	_decoy_left -= delta
	if _decoy_left <= 0.0:
		_decoy.queue_free()
		_decoy = null


## True while a decoy shell is standing where the mech left it.
func has_decoy() -> bool:
	return _decoy != null and is_instance_valid(_decoy)


func reset() -> void:
	_set_intangible(false)
	_state = S.IDLE
	_t = 0.0
	if _decoy != null and is_instance_valid(_decoy):
		_decoy.queue_free()
	_decoy = null
	_decoy_left = 0.0

