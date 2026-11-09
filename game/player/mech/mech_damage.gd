class_name MechDamage
extends Node
## The player's damage pipeline and the death latch (CONTRACTS §4), split out of `player_mech.gd`.
## This node owns the hit filters, the invulnerability window, the perfect dodge, the last-stand
## request and the `dead` latch; `MechDeath` owns everything the latch stops.
##
## `hp` itself stays on `PlayerMech` — CONTRACTS §5 exposes it and flow's `_restore_player` writes it
## directly — so the latch is SYNCED from it instead of being a second source of truth: `sync()` runs
## at the top of every physics tick and wherever hp changes, which is what keeps `_dead` and
## `is_alive()` from disagreeing.

## FEEL.md / hero-v3 r5 item 4: the blend is 2 frames -- the clips peak on frame 3, so a slower fade
## would eat the snap the lead asked for.
const HIT_BLEND := 0.033
const DEATH_BLEND := 0.08

var player: PlayerMech
var tuning: MechTuning
var loco: MechLocomotion
var dead: bool = false

var _invuln_t: float = 0.0
var _filters: Array[Callable] = []
## r7b item 8: an announcement of this death that did not come from `_die()` (flow's debug `die`
## command and `test_boss_city` both write hp to 0 and emit `player_died` themselves).
var _died_seen: bool = false
var _emitting: bool = false


func setup(p: PlayerMech, t: MechTuning, l: MechLocomotion) -> void:
	player = p
	tuning = t
	loco = l
	Events.player_died.connect(_on_player_died)


## `player_died` must fire ONCE per death. Anything that announces a death without going through the
## pipeline arms `_died_seen`, and `_die()` then stays quiet instead of saying it a second time.
func _on_player_died() -> void:
	if not _emitting:
		_died_seen = true


## CONTRACTS §3: the mercy window is a player timer, so a global hit-stop holds it.
func tick(player_dt: float) -> void:
	_invuln_t = maxf(_invuln_t - player_dt, 0.0)


## One predicate decides whether the mech may act: `is_alive()`. This keeps the latch on the same
## side of it even when hp is written without `heal()` (the flow's revive does exactly that).
func sync() -> void:
	if player.is_alive():
		_died_seen = false  # a stale announcement from a driver that never actually killed the mech
	if player.is_alive() == not dead:
		return
	if dead:
		_revive()
	else:
		_die()


# --- the pipeline (CONTRACTS §4) ------------------------------------------------------------------

func take_hit(hit: HitInfo) -> void:
	if hit == null or not player.is_alive():
		return
	if loco.is_dash_invulnerable() and _is_enemy_attack(hit):
		_perfect_dodge(hit)
		return
	if is_invulnerable():
		hit.final_amount = 0.0
		return
	for f in _filters:
		if f.is_valid() and bool(f.call(hit)):
			hit.final_amount = 0.0  # consumed by a block / parry / barrier
			return
	_apply_damage(hit)


func _is_enemy_attack(hit: HitInfo) -> bool:
	var s := hit.source
	if s == null or s == player:
		return s == null
	return not s.has_method(&"get_team") or int(s.call(&"get_team")) != player.get_team()


## SPEC §4: a hit that lands inside the dash i-frames costs nothing and buys witch time.
func _perfect_dodge(hit: HitInfo) -> void:
	hit.final_amount = 0.0
	Feel.play(&"perfect_dodge", player.global_position)
	Feel.slow_mo(0.3, 0.35, 0.03, 0.15, true)
	Events.perfect_dodge.emit(hit.source)
	player.add_overdrive(tuning.od_perfect_dodge)


func _apply_damage(hit: HitInfo) -> void:
	var dmg := 0.0 if Game.has_flag("god") else maxf(hit.amount, 0.0)
	var was := player.hp
	player.hp = maxf(was - dmg, 0.0)
	hit.final_amount = dmg
	Events.player_damaged.emit(hit)
	Events.hit_landed.emit(hit, player)
	Feel.play(&"hurt_heavy" if dmg >= tuning.hurt_heavy_damage else &"hurt_light", player.global_position)
	player.add_overdrive(dmg / player.hp_max * 100.0 * tuning.od_per_hp_percent)
	if dmg >= tuning.hurt_heavy_damage:
		invulnerable_for(tuning.invuln_blink)  # tuning choice: a big hit staggers you briefly
	if player.hp > 0.0:
		_last_stand(was)
		_react_to_hit(hit, dmg)
	sync()  # the latch closes the gate (and zeroes the horizontal speed) BEFORE the knockback
	_knockback(hit)


## A corpse still takes the killing blow's push, but through the body and not through
## `MechLocomotion.apply_impulse`, which would put the wreck back into a movement state.
func _knockback(hit: HitInfo) -> void:
	if hit.knockback == Vector3.ZERO:
		return
	var k := hit.knockback * tuning.knockback_scale
	if dead:
		player.velocity += k
	else:
		loco.apply_impulse(k)


## FEEL.md's `hurt_heavy` slow-mo column and juice-impact §"last stand": the hit that takes the mech
## below `od_low_hp` (15 %) and leaves it alive buys the slow-mo. The 0.5x, the 1.5 s and the 60 s
## cooldown are the feel row's (`fx/events/last_stand.tres`), so there is no second timer here.
## God mode cannot cross the line (it deals 0), and the killing blow is excluded by `hp > 0`.
func _last_stand(hp_before: float) -> void:
	var line := player.hp_max * tuning.od_low_hp
	if hp_before < line or player.hp >= line:
		return
	Feel.play(&"last_stand", player.global_position)


## hero-v3 r5 item 4: the model is told it was hit. A big knockback puts the mech on the floor; any
## other hit is a flinch, light or heavy by the damage against `hurt_heavy_damage`.
func _react_to_hit(hit: HitInfo, dmg: float) -> void:
	if dmg <= 0.0:
		return
	if hit.knockback.length() * tuning.knockback_scale >= PlayerMech.KNOCKDOWN_IMPULSE:
		player.play_model_action(&"hit_knockdown", HIT_BLEND)
		return
	player.play_model_action(&"hit_heavy" if dmg >= tuning.hurt_heavy_damage else &"hit_light", HIT_BLEND)


func _die() -> void:
	dead = true
	MechDeath.enter(player)
	if _died_seen:  # flow's debug `die`, or a test, already announced this death
		_died_seen = false
		return
	_emitting = true
	Events.player_died.emit()
	_emitting = false


func _revive() -> void:
	dead = false
	_died_seen = false
	MechDeath.exit(player)


# --- windows and filters --------------------------------------------------------------------------

func invulnerable_for(seconds: float) -> void:
	_invuln_t = maxf(_invuln_t, seconds)


func is_invulnerable() -> bool:
	return _invuln_t > 0.0 or loco.is_dash_invulnerable()


## `func(hit: HitInfo) -> bool`; true means the hit was consumed (block, parry, barrier).
func add_filter(f: Callable) -> void:
	if f.is_valid() and not _filters.has(f):
		_filters.append(f)


func remove_filter(f: Callable) -> void:
	_filters.erase(f)


func heal(amount: float) -> void:
	player.hp = minf(player.hp + maxf(amount, 0.0), player.hp_max)
	sync()


## Capture affordance (trailer unit): fire the perfect-dodge beat through the same function a real
## dodge uses. A scripted take cannot reliably land an enemy attack inside the dash i-frames, and this
## changes no gameplay number: it only supplies the hit that `_perfect_dodge` would have eaten.
func debug_perfect_dodge() -> void:
	var source: Node = null
	for e: Node in player.get_tree().get_nodes_in_group(&"enemy"):
		if e is Node3D and (e as Node3D).global_position.distance_to(player.global_position) < 80.0:
			source = e
			break
	_perfect_dodge(HitInfo.make(0.0, HitInfo.MELEE, source if source != null else player, &"debug"))
