class_name ShockcoreBurst
extends Node3D
## S6 Shockcore Burst (震核爆) — 360 degree panic button (skills-catalog §4.4 S6, radius x2).
##
## 18 f of startup with super armour, 6 f active, 20 f of recovery. On the first active frame a
## fresnel shell snaps out to 32 m: 1,800 damage inside 12 m falling to 600 at the rim, 1,400 impact,
## knockback by class (20 m/s on Swarmers and Stalkers, 6 m/s on Brutes, nothing on a boss). Enemy
## projectiles inside the radius are deleted outright, primed enemies COLLAPSE, and a wall between
## the mech and a target blocks it — the burst is line-of-sight gated.

enum S { IDLE, STARTUP, ACTIVE, RECOVERY }

const SHELL_TIME := 0.18          ## juice: the fresnel shell reaches the rim in 0.18 s
const SHELL_LINGER := 0.5         ## the shell keeps fading after it reaches the rim
const SHELL_CORE := Color(0.42, 0.88, 1.0)
const SHELL_RIM := Color(0.92, 1.0, 1.0)
const INHALE_COLOR := Color(0.55, 0.92, 1.0)
const RING_COLOR := Color(0.72, 0.96, 1.0)

var ctx: SkillContext = null
var system: SkillSystem = null

var _state: int = S.IDLE
var _t: float = 0.0
var _fired: bool = false
var _inhale: SkillFxInflow = null
var _centre: Vector3 = Vector3.ZERO
var _victims: int = 0
var _deleted: int = 0


func setup(ctx_: SkillContext, system_: SkillSystem) -> void:
	ctx = ctx_
	system = system_


func is_busy() -> bool:
	return _state != S.IDLE


## Checked BEFORE the charge is spent.
func can_begin() -> bool:
	return _state == S.IDLE and ctx.player != null


## Super armour during the startup (skills-catalog §4.4 S6): the mech cannot be knocked out of it.
func is_super_armoured() -> bool:
	return _state == S.STARTUP


func victims() -> int:
	return _victims


func shots_deleted() -> int:
	return _deleted


func begin() -> bool:
	if _state != S.IDLE or ctx.player == null:
		return false
	_state = S.STARTUP
	_t = 0.0
	_fired = false
	_victims = 0
	_deleted = 0
	if ctx.player.has_method(&"lock_movement"):
		ctx.player.call(&"lock_movement", ctx.tuning.burst_startup, true)
	# 18 f of inhale: motes spiral into the chest and the screen edges pull in behind them.
	if ctx.vfx != null:
		_inhale = ctx.vfx.inflow()
		_inhale.fire(ctx.chest(), 26.0, ctx.tuning.burst_startup + 0.1, INHALE_COLOR, 120, 34.0,
				1.4, 0.8)
	Feel.post(&"radial_blur", 0.35, ctx.tuning.burst_startup)
	_play_action(&"burst")
	return true


func tick(delta: float) -> void:
	match _state:
		S.STARTUP:
			_tick_startup(delta)
		S.ACTIVE:
			_tick_active(delta)
		S.RECOVERY:
			_tick_recovery(delta)
		_:
			pass


func _tick_startup(delta: float) -> void:
	_t += delta
	if _inhale != null:
		_inhale.move_to(ctx.chest(), 26.0 * (1.0 - _t / maxf(ctx.tuning.burst_startup, 0.01)))
	if _t < ctx.tuning.burst_startup:
		return
	_state = S.ACTIVE
	_t = 0.0
	# the blast is centred on the mech's body centre (the capsule origin), not the chest: a 16 m hero
	# whose chest is 11.5 m up would otherwise put every ground-level enemy outside its own core radius
	_centre = ctx.origin()


func _tick_active(delta: float) -> void:
	_t += delta
	if not _fired:
		_fired = true
		_detonate()
	if _t >= ctx.tuning.burst_active:
		_state = S.RECOVERY
		_t = 0.0


func _tick_recovery(delta: float) -> void:
	_t += delta
	if _t >= ctx.tuning.burst_recovery:
		_state = S.IDLE
		_t = 0.0


# --- the burst -----------------------------------------------------------------------------------

## Damage falls off from 1,800 inside 12 m to 600 at the 32 m rim, is blocked by walls, and every
## enemy projectile inside the radius is deleted on the active frame (Assault Armour [AC-AA]).
func _detonate() -> void:
	var t := ctx.tuning
	for e in ctx.enemies_in_radius(_centre, t.burst_radius):
		var to := ctx.centre_of(e) - _centre
		var dist := to.length()
		if not ctx.has_los(_centre, ctx.centre_of(e)):
			continue
		var dmg := t.falloff(dist, t.burst_radius, t.burst_core, t.burst_damage,
				t.burst_edge_damage)
		if dmg <= 0.0:
			continue
		var dir := to.normalized() if to.length_squared() > 0.001 else Vector3.UP
		ctx.damage(e, dmg, HitInfo.EXPLOSIVE, &"shockcore", t.burst_impact,
				ctx.knockback_for(e, t.burst_knock_light, t.burst_knock_heavy, dir), ctx.centre_of(e))
		Feel.local_hit_stop([e], 4.0 / 60.0)
		_victims += 1
	_deleted = _delete_shots()
	_detonate_primes()
	Feel.play(&"shockcore", _centre)
	_draw_burst()
	Feel.post(&"radial_blur", 0.6, 6.0 / 60.0)


## The Shockcore signature (r1 review): a cyan-white fresnel shell snapping out to 32 m over 0.18 s,
## a ground shock ring under it, lightning crawling radially out of the centre, dust lifting off the
## deck and a white flash. No orange fireball — that preset is the fx unit's generic kill blast and
## it drowned the skill's own read.
func _draw_burst() -> void:
	var t := ctx.tuning
	if ctx.vfx != null:
		ctx.vfx.shell().fire(_centre, 1.0, t.burst_radius, SHELL_TIME + SHELL_LINGER,
				SHELL_CORE, SHELL_RIM, 2.4, 2.2)
	# the deck layer only when the shock can reach the deck: an airborne burst 150 m over the street
	# used to stamp its ring, arcs, dust and scorch decal on that street (audit #12)
	var ground := ctx.ground_near(_centre, t.burst_radius)
	if ground != _centre:
		_draw_deck(ground, t)
	SkillFx.flash(self, _centre, Color(0.75, 0.98, 1.0), 9.0, t.burst_radius * 2.0, 5.0)


func _draw_deck(ground: Vector3, t: SkillTuning) -> void:
	if ctx.vfx != null:
		ctx.vfx.ring().fire(ground + Vector3.UP * 0.4, Vector3.UP, 2.0, t.burst_radius, 0.42,
				RING_COLOR, 0.1, 2.6)
		ctx.vfx.arcs().fire(ground + Vector3.UP * 1.0, t.burst_radius * 0.85, 10, 0.26, SHELL_RIM, 0.8)
		ctx.vfx.inflow().fire(ground + Vector3.UP * 1.0, t.burst_radius * 0.7, 0.55,
				Color(0.62, 0.5, 0.4), 90, 12.0, 0.5, 1.6)
	SkillFx.spawn(self, &"dust_ring", ground, Vector3.UP, t.burst_radius / 6.0)
	SkillFx.decal(self, &"scorch_ring", ground, Vector3.UP, t.burst_radius / 9.0)


## Enemy shots are handed back to the enemies unit's own pool, so the recycling stays theirs.
func _delete_shots() -> int:
	var n := 0
	for shot in ctx.enemy_shots_in_radius(_centre, ctx.tuning.burst_radius):
		var at := (shot as Node3D).global_position
		SkillFx.spawn(self, &"spark_burst", at, Vector3.UP, 0.9)
		if ctx.vfx != null:
			# a cyan pop where the shot is deleted, so "the burst eats bullets" reads in one frame
			ctx.vfx.shell().fire(at, 0.4, 4.0, 0.2, SHELL_CORE, SHELL_RIM, 2.6, 2.0)
		if shot.has_method(&"deactivate"):
			shot.call(&"deactivate")
		n += 1
	return n


## The burst is a COLLAPSE detonator (skills-catalog §4.7).
func _detonate_primes() -> void:
	if ctx.player == null or not ctx.player.is_inside_tree():
		return
	ctx.player.get_tree().call_group(&"prime_detonators", &"detonate_primes", _centre,
			ctx.tuning.burst_radius, ctx.player)


func _play_action(id: StringName) -> void:
	if ctx.model != null and is_instance_valid(ctx.model) and ctx.model.has_method(&"play_action"):
		ctx.model.call(&"play_action", id)


func reset() -> void:
	_state = S.IDLE
	_t = 0.0
	_fired = false
	_victims = 0
	_deleted = 0
	if _inhale != null:
		_inhale.stop()
		_inhale = null
