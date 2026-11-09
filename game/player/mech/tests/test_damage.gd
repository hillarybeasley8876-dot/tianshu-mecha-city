extends "res://player/mech/tests/mech_test_base.gd"
## mech-move damage + hit-stop suite (CONTRACTS §4, FEEL.md): the damage filters, the perfect dodge
## the local hit-stop contract — the mech's own committed states freeze and creep, everything the
## player started keeps running, and no floor contact inside a stop is ever dropped — and the
## last-stand slow-mo (mech-move r7 item 3, folded back in now that feel r5 has landed the row).

## The feel director, so the last-stand row is checked end to end and not only as a request.
const DIRECTOR := preload("res://fx/feel_director.tscn")
## FEEL.md / `MechTuning.od_low_hp`: the line the hit has to cross.
const LINE := 0.15
## The feel row the lead decided on (r16 B5): 0.5x, 1.5 s, 60 s cooldown, witch off.
const WANT_SCALE := 0.5
const SCALE_TOL := 0.02
const HOLD_FROM := 0.1
const HOLD_TO := 1.3
const BACK_TO_ONE := 1.6

## Stands in for the hero model in the hit-pause check, so the contract is tested without depending on
## the hero-asset unit's AnimationTree.
class PauseSpy:
	extends Node3D

	var last: float = 0.0

	func hit_pause(seconds: float) -> void:
		last = seconds


var _dir: Node
var _asked: int = 0
var _played: int = 0
var _hit_at: float = 0.0  ## `Feel.real_now()` of the crossing hit, so samples are measured from it


func _run() -> void:
	await _setup()
	_dir = DIRECTOR.instantiate()
	add_child(_dir)
	Feel.event_requested.connect(func(id: StringName, _at: Vector3, _s: float) -> void:
			if id == &"last_stand":
				_asked += 1)
	_dir.connect(&"event_played", func(id: StringName, _at: Vector3, _s: float) -> void:
			if id == &"last_stand":
				_played += 1)
	await _step(10)
	await _test_hit_pause()
	await _test_damage_filter()
	await _test_perfect_dodge()
	await _test_hit_reactions()
	await _test_death_and_revive()
	await _test_last_stand()
	_report("mech-move damage")


# --- checks --------------------------------------------------------------------------------------

## Audit [2]/[5] (high): a local hit-stop froze the state handlers while the body went on moving at
## full speed, and a floor touched inside the pause was never processed. FEEL.md and juice §2.2: a
## player-started boost, dash or landing never freezes; only the mech's own committed states do.
func _test_hit_pause() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	Input.action_press(&"boost")
	await _until_state(&"slide", 90)
	await _step(60)
	var start := _p.global_position
	_p.hit_pause(0.15)
	_ok(not _loco.is_frozen(), "a hit-stop never freezes a player-started boost")
	await _step(18)
	var skated := Vector2(_p.global_position.x - start.x, _p.global_position.z - start.z).length()
	Input.action_release(&"boost")
	_ok(skated > 4.0, "the boost runs straight through a local hit-stop", "d=%.2f" % skated)

	# A lunge is the mech's own committed motion: it freezes, and creeps at FEEL.md's 5 %.
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_p.lunge_to(_p.global_position + Vector3(0.0, 0.0, -200.0), 110.0, 1.5)
	await _step(2)
	var p0 := _p.global_position
	_p.hit_pause(0.15)
	await _step(18)
	var crept := p0.distance_to(_p.global_position)
	_ok(crept < 2.0, "a local hit-stop freezes a lunge instead of carrying it on", "d=%.2f" % crept)

	# The contact the pause would otherwise swallow: a mech falling into the ground while frozen.
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_p.debug_teleport([0.0, 8.5, 60.0], 0.0)
	_p.lock_movement(0.6)
	_p.hit_pause(0.3)
	_p.apply_impulse(Vector3(0.0, -100.0, 0.0))
	await _step(40)
	_ok(_p.is_on_floor() and _loco.land_kind != &"none",
			"a touchdown inside the hit-stop is not dropped",
			"%s floor=%s" % [_loco.land_kind, _p.is_on_floor()])

	# Audit [3]: a press that arrives during the stop is buffered, not eaten.
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_p.lock_movement(0.25)
	_p.hit_pause(0.12)
	await _step(2)
	await _tap(&"boost")  # pressed AND released inside the freeze
	_ok(_loco.is_frozen(), "the mech is frozen while the lock and the stop overlap")
	var fired := false
	for i in 120:
		await get_tree().physics_frame
		if _dashing():
			fired = true
			break
	_ok(fired, "a tap buffered during the hit-stop still fires when the lock ends",
			String(_p.move_state()))

	# Audit [6] / CONTRACTS §4: the pause must reach the model's animation tree too.
	var real := _p.model()
	var spy := PauseSpy.new()
	add_child(spy)
	_p.set(&"_model", spy)
	_p.hit_pause(0.1)
	_p.set(&"_model", real)
	_ok(spy.last == 0.1, "hit_pause is forwarded to the model", "s=%.2f" % spy.last)
	spy.queue_free()


func _test_damage_filter() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	var hp0 := _p.hp
	var block := func(_hit: HitInfo) -> bool: return true
	_p.add_damage_filter(block)
	var h1 := HitInfo.make(500.0, HitInfo.BALLISTIC, _enemy, &"test_shot")
	_p.take_hit(h1)
	_ok(_p.hp == hp0 and h1.final_amount == 0.0, "a damage filter returning true blocks the hit")
	_p.remove_damage_filter(block)
	var h2 := HitInfo.make(500.0, HitInfo.BALLISTIC, _enemy, &"test_shot")
	_p.take_hit(h2)
	_ok(_near(hp0 - _p.hp, 500.0, 0.01), "an unfiltered hit applies its damage",
			"dmg=%.1f" % (hp0 - _p.hp))


func _test_perfect_dodge() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	var hp0 := _p.hp
	var before := _dodges
	Input.action_press(&"boost")
	await _step(2)
	Input.action_release(&"boost")
	var hit := HitInfo.make(500.0, HitInfo.MELEE, _enemy, &"test_claw")
	_p.take_hit(hit)
	_ok(_p.is_invulnerable(), "the hit landed inside the dash i-frames")
	_ok(_p.hp == hp0 and hit.final_amount == 0.0, "perfect dodge takes no damage")
	_ok(_dodges == before + 1, "Events.perfect_dodge emitted")
	_ok(_p.overdrive > 0.0, "perfect dodge grants OD", "od=%.1f" % _p.overdrive)
	await _wait_slowmo()


## hero-v3 r5 item 4: the model is TOLD it was hit. A light hit flinches, a heavy one rocks it, and a
## knockback at or above `PlayerMech.KNOCKDOWN_IMPULSE` puts it on the floor.
func _test_hit_reactions() -> void:
	var model := _p.model()
	if not _has_model(model):
		return
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	await _wait_vulnerable()
	var light := HitInfo.make(50.0, HitInfo.BALLISTIC, _enemy, &"test_ping")
	_p.take_hit(light)
	_ok(model.call(&"current_action") == &"hit_light", "a small hit plays hit_light",
			String(model.call(&"current_action")))
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	await _wait_vulnerable()
	var heavy := HitInfo.make(_p.tuning.hurt_heavy_damage + 1.0, HitInfo.BALLISTIC, _enemy,
			&"test_slam")
	_p.take_hit(heavy)
	_ok(model.call(&"current_action") == &"hit_heavy", "a big hit plays hit_heavy",
			String(model.call(&"current_action")))
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	await _wait_vulnerable()
	var knock := HitInfo.make(10.0, HitInfo.MELEE, _enemy, &"test_ram")
	knock.knockback = Vector3(0.0, 0.0, PlayerMech.KNOCKDOWN_IMPULSE + 1.0)
	_p.take_hit(knock)
	_ok(model.call(&"current_action") == &"hit_knockdown", "a big knockback plays hit_knockdown",
			String(model.call(&"current_action")))


## Lead r5: `_dead` was never cleared, so the HELD `death` clip outlived the revive -- the mech got
## up and walked lying on the floor, and a second death played nothing. The flow's revive sets `hp`
## and then calls `heal()`, so that is the hook this checks.
func _test_death_and_revive() -> void:
	var model := _p.model()
	if not _has_model(model):
		return
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	await _wait_vulnerable()
	_p.take_hit(HitInfo.make(_p.hp_max * 2.0, HitInfo.BALLISTIC, _enemy, &"test_kill"))
	_ok(not _p.is_alive(), "the killing blow drops the mech to 0 hp", "hp=%.0f" % _p.hp)
	_ok(model.call(&"current_action") == &"death", "0 hp plays the held death clip",
			String(model.call(&"current_action")))

	# exactly what `flow_progress.gd` `_restore_player` does
	_p.set(&"hp", _p.hp_max)
	_p.heal(_p.hp_max)
	_ok(_p.is_alive(), "the revive brings the mech back", "hp=%.0f" % _p.hp)
	_ok(model.call(&"current_action") != &"death", "a revive releases the held death clip",
			String(model.call(&"current_action")))

	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	await _wait_vulnerable()
	_p.take_hit(HitInfo.make(_p.hp_max * 2.0, HitInfo.BALLISTIC, _enemy, &"test_kill_again"))
	_ok(model.call(&"current_action") == &"death", "a second death plays the clip again",
			String(model.call(&"current_action")))


## A heavy hit buys `tuning.invuln_blink` of mercy, and `_reset` returns as soon as the mech is on the
## floor -- so without this the NEXT hit is swallowed whole and never reaches the model at all.
func _wait_vulnerable() -> void:
	for i in 60:
		if not _p.is_invulnerable():
			return
		await get_tree().physics_frame


## The suites run against whatever `PlayerMech.HERO_MODEL` points at, and the placeholder answers
## `current_action` differently, so the model checks are skipped rather than failed when there is no
## hero in yet.
func _has_model(model: Node3D) -> bool:
	if model != null and model.has_method(&"current_action"):
		return true
	print("SKIP the model checks: no HeroModel on the player")
	return false


# --- the last stand (mech-move r7 item 3, r16 B5) ---------------------------------------------------

## FEEL.md's `hurt_heavy` slow-mo column and juice-impact §"last stand": the hit that takes the mech
## below 15 % and leaves it ALIVE buys the slow-mo. Two halves: the pipeline (does the mech ask, and
## only on a real crossing?) is ours; the director (does the row exist, and does it buy 0.5x for 1.5 s
## on a 60 s cooldown?) is feel's `fx/events/last_stand.tres`.
##
## Every half starts on a fresh cooldown (`reset_rate_limits`): the rows above and the pipeline rows
## below both spend the 60 s, and a row that only passes because the cooldown is still running cannot
## fail at all.
func _test_last_stand() -> void:
	_dir.call(&"reset_rate_limits")
	await _last_stand_pipeline()
	_dir.call(&"reset_rate_limits")
	await _last_stand_director()
	_dir.call(&"reset_rate_limits")
	await _last_stand_killing_blow()


## One hit that takes the mech from at or above 15 % to below it, while it stays alive, asks for
## `last_stand` exactly once. Nothing else does.
func _last_stand_pipeline() -> void:
	_ok(_p.tuning.od_low_hp == LINE, "the last-stand threshold is MechTuning.od_low_hp",
			"%.3f" % _p.tuning.od_low_hp)
	_ok(await _crossing(0.16, 200.0) == 1, "a hit that crosses below 15 % asks once")
	_ok(await _crossing(1.0, 1000.0) == 0, "a hit that stays above 15 % asks nothing")
	_ok(await _crossing(0.10, 200.0) == 0, "a hit that starts below 15 % asks nothing")
	_ok(await _crossing(0.20, 5000.0) == 0, "the killing blow asks nothing",
			"alive=%s" % _p.is_alive())
	var god: Variant = Game.flags.get("god")
	Game.flags["god"] = "true"
	var asked := await _crossing(0.16, 200.0)
	if god == null:
		Game.flags.erase("god")
	else:
		Game.flags["god"] = god
	_ok(asked == 0, "god mode asks nothing")


## Sets hp to `from` of the max, lands `dmg`, and returns how many `last_stand` requests it produced.
func _crossing(from: float, dmg: float) -> int:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	await _wait_slowmo()
	_p.hp = _p.hp_max * from
	_clear_invuln()
	await _step(4)
	_asked = 0
	_p.take_hit(HitInfo.make(dmg, HitInfo.BALLISTIC, _enemy, &"test_last_stand"))
	await _step(4)
	return _asked


func _clear_invuln() -> void:
	var host: Object = (_p.call(&"damage") as Object) if _p.has_method(&"damage") else _p
	host.set(&"_invuln_t", 0.0)


func _last_stand_director() -> void:
	var has_row := bool(_dir.call(&"has_event", &"last_stand"))
	_ok(has_row, "fx/events/last_stand.tres is loaded (feel r5)",
			"" if has_row else "no FeelEvent for id 'last_stand'")
	var played := await _director_play()
	_ok(played == 1, "the director plays the row on a crossing hit", "%d plays" % played)
	var scale := await _hold_scale()
	_ok(_near(minf(scale.x, scale.y), WANT_SCALE, SCALE_TOL)
			and _near(maxf(scale.x, scale.y), WANT_SCALE, SCALE_TOL),
			"last stand holds time_scale at %.1fx from %.1f s to %.1f s real"
					% [WANT_SCALE, HOLD_FROM, HOLD_TO],
			"%.3f..%.3f" % [scale.x, scale.y])
	var back := await _scale_at(BACK_TO_ONE)
	_ok(back == 1.0, "time_scale is back to 1.0 by %.1f s" % BACK_TO_ONE, "%.3f" % back)
	_ok(await _director_play() == 0, "a second crossing inside the 60 s cooldown changes nothing")


## On a FRESH cooldown, so the row can actually fail: the killing blow must not buy the slow-mo.
func _last_stand_killing_blow() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	await _wait_slowmo()
	_p.hp = _p.hp_max * 0.20
	_clear_invuln()
	await _step(4)
	var before := _played
	_p.take_hit(HitInfo.make(_p.hp_max, HitInfo.BALLISTIC, _enemy, &"test_last_stand_kill"))
	await _step(4)
	_ok(_played == before, "a killing blow from 20 % plays nothing on a fresh cooldown",
			"alive=%s played=%d" % [_p.is_alive(), _played - before])


## One crossing hit; returns how many times the DIRECTOR actually played the row.
func _director_play() -> int:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	await _wait_slowmo()
	_p.hp = _p.hp_max * 0.16
	_clear_invuln()
	await _step(4)
	var before := _played
	_p.take_hit(HitInfo.make(200.0, HitInfo.BALLISTIC, _enemy, &"test_last_stand"))
	_hit_at = Feel.real_now()
	await _step(1)
	return _played - before


## min/max of `Engine.time_scale` over the real-second window the row is supposed to hold it.
func _hold_scale() -> Vector2:
	var lo := 2.0
	var hi := 0.0
	while Feel.real_now() - _hit_at < HOLD_TO:
		if Feel.real_now() - _hit_at >= HOLD_FROM:
			lo = minf(lo, Engine.time_scale)
			hi = maxf(hi, Engine.time_scale)
		await get_tree().physics_frame
	return Vector2(lo, hi)


func _scale_at(seconds: float) -> float:
	while Feel.real_now() - _hit_at < seconds:
		await get_tree().physics_frame
	return Engine.time_scale
