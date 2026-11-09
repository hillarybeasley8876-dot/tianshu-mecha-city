class_name ZenithOverdrive
extends Node3D
## Zenith Overdrive (天顶超驱) — the 12 s ultimate that ends in the Zenith Lance (skills-catalog §4.5).
##
## Needs a full OD meter. Ignition is 0.45 s of super armour at 0.3x time (the feel row owns the
## slow-mo), the body shifts crimson to gold through `HeroModel.set_overdrive(true)`, and for 12 s:
## every cooldown already reset and now ticking 2.5x faster, EN regen x3, dashes refunded, damage
## +25 %, damage taken -30 %, impact +30 %. A ghost is dropped every 3 f while the mech is moving.
##
## The SkillSystem owns the buff arithmetic and the meter; this file owns the performance — the
## ignition, the afterimage cadence and the hand-off into `ZenithLance`, which fires when the player
## presses again or automatically with 1.0 s left.

const GHOST_COLOR := Color(1.0, 0.72, 0.3)
## The body aura that carries the overdrive while the mech is standing still: the hero's gold glow
## strips and vents only burn when the thrusters do, so at rest nothing on the model reads (r2
## review). A slow, faint pulse on the silhouette — no afterimages, so nothing stacks.
const AURA_GAP := 0.3
const AURA_RADIUS := 13.0

var ctx: SkillContext = null
var system: SkillSystem = null
var lance: ZenithLance = null

var _ignite_left: float = 0.0
var _ghost_at: float = 0.0
var _ghosts: int = 0
var _aura_at: float = 0.0


func setup(ctx_: SkillContext, system_: SkillSystem) -> void:
	ctx = ctx_
	system = system_
	lance = ZenithLance.new()
	lance.name = "ZenithLance"
	add_child(lance)
	lance.setup(ctx, system)


func ghosts_spawned() -> int:
	return _ghosts


func is_igniting() -> bool:
	return _ignite_left > 0.0


## 0.45 s of super armour at 0.3x time; the mech is invulnerable for the whole ignition so the
## ultimate can never be interrupted out of its own wind-up.
func ignite() -> void:
	_ignite_left = ctx.tuning.od_ignite
	_ghost_at = 0.0
	_ghosts = 0
	if ctx.player != null and ctx.player.has_method(&"invulnerable_for"):
		ctx.player.call(&"invulnerable_for", ctx.tuning.od_ignite)
	if ctx.player != null and ctx.player.has_method(&"lock_movement"):
		ctx.player.call(&"lock_movement", ctx.tuning.od_ignite, true)
	if ctx.model != null and is_instance_valid(ctx.model) and ctx.model.has_method(&"set_overdrive"):
		ctx.model.call(&"set_overdrive", true)
	_play_action(&"overdrive_ignite")
	Feel.play(&"overdrive_ignite", ctx.chest())
	Feel.slow_mo(0.3, 0.25, 0.03, 0.12)
	if ctx.vfx != null:
		# gold ignition: an expanding shell off the chest, a deck ring and the gold rim that stays
		# up for the whole 12 s window
		ctx.vfx.shell().fire(ctx.chest(), 1.0, 34.0, 0.5, Color(1.0, 0.72, 0.3),
				Color(1.0, 0.95, 0.75), 2.2, 2.0)
		var deck := ctx.ground_near(ctx.feet(), 8.0)
		if deck != ctx.feet():
			ctx.vfx.ring().fire(deck + Vector3.UP * 0.4, Vector3.UP, 3.0, 40.0, 0.5,
					Color(1.0, 0.8, 0.35), 0.1, 2.6)
		ctx.vfx.vignette.open(Color(1.0, 0.72, 0.3), 0.42, ctx.tuning.od_duration, 0.5, 0.5)
	SkillFx.flash(self, ctx.chest(), GHOST_COLOR, 8.0, 90.0, 8.0)


func tick(delta: float) -> void:
	if _ignite_left > 0.0:
		_ignite_left = maxf(_ignite_left - delta, 0.0)
	if system != null and system.is_overdrive_active():
		_tick_ghosts(delta)
		_tick_aura(delta)
	lance.tick(delta)


## A faint gold pulse on the silhouette for the whole 12 s, so the state reads at rest as well as in
## motion. Deliberately slow and weak: this is a state tell, not an effect.
func _tick_aura(delta: float) -> void:
	if ctx.vfx == null:
		return
	_aura_at -= delta
	if _aura_at > 0.0:
		return
	_aura_at = AURA_GAP
	ctx.vfx.shell().fire(ctx.chest(), AURA_RADIUS * 0.6, AURA_RADIUS, AURA_GAP + 0.12,
			Color(1.0, 0.72, 0.3), Color(1.0, 0.92, 0.62), 1.1, 2.6)


## A ghost every 3 f, each living 0.25 s (skills-catalog §4.5 "Afterimages" [GW-TA]) — but only
## while the mech is actually moving: standing still, five ghosts stack on one pose and the hero
## turns into a flat gold blob (r2 review). At rest the overdrive reads through the body's gold
## glow strips, the vents and the gold rim instead.
func _tick_ghosts(delta: float) -> void:
	_ghost_at -= delta
	if _ghost_at > 0.0 or not ghosts_allowed():
		return
	_ghost_at = ctx.tuning.od_afterimage_gap
	if SkillFx.afterimage(self, ctx.model as Node3D, ctx.tuning.od_afterimage_life, GHOST_COLOR):
		_ghosts += 1


## Is the mech moving fast enough for afterimages to read? Exposed because the ghosts themselves are
## drawn by the fx library, which the headless suite does not have — this is the part that is testable.
func ghosts_allowed() -> bool:
	return ctx != null and ctx.planar_speed() >= ctx.tuning.od_afterimage_speed


func can_fire_lance() -> bool:
	if system == null or not system.is_overdrive_active():
		return false
	return _ignite_left <= 0.0 and not lance.is_running()


## Press again, or the auto-fire at 1.0 s left (skills-catalog §4.5).
func begin_lance() -> bool:
	if not can_fire_lance():
		return false
	Events.ultimate_fired.emit()
	return lance.begin()


func is_charging() -> bool:
	return lance.is_charging()


func is_firing() -> bool:
	return lance.is_running()


func _play_action(id: StringName) -> void:
	if ctx.model != null and is_instance_valid(ctx.model) and ctx.model.has_method(&"play_action"):
		ctx.model.call(&"play_action", id)


func hud_state() -> Dictionary:
	return {"od_ghosts": _ghosts}


func reset() -> void:
	_ignite_left = 0.0
	_ghost_at = 0.0
	_ghosts = 0
	_aura_at = 0.0
	if ctx != null and ctx.model != null and is_instance_valid(ctx.model) \
			and ctx.model.has_method(&"set_overdrive"):
		ctx.model.call(&"set_overdrive", false)
	if lance != null:
		lance.reset()
