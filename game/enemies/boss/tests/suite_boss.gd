class_name BossSuite
extends RefCounted
## The Brood Titan's fight logic (boss unit): phase thresholds, core breaks, the armour split, the
## cinematic invulnerability window, the checkpoints and the death → game_won beat.

const SETTLE := 0.25


static func run(h: BossTestHarness) -> void:
	await _phase_thresholds(h)
	await _phase_cinematic(h)
	await _core_breaks(h)
	_armour(h)
	await _checkpoint(h)
	await _death(h)


## SPEC §7.1: the pool cuts at 65 % and 30 %, and every cut emits `Events.boss_phase` exactly once.
static func _phase_thresholds(h: BossTestHarness) -> void:
	h.reset_titan()
	var t := h.titan
	h.check("phase.starts_at_1", t.phase == 1, "phase is %d" % t.phase)
	h.check("phase.p1_ratio", BossTuning.phase_for(1.0) == 1 and BossTuning.phase_for(0.66) == 1,
			"phase_for above 65%% is not 1")
	h.check("phase.p2_ratio", BossTuning.phase_for(0.65) == 2 and BossTuning.phase_for(0.31) == 2,
			"phase_for between the thresholds is not 2")
	h.check("phase.p3_ratio", BossTuning.phase_for(0.30) == 3 and BossTuning.phase_for(0.0) == 3,
			"phase_for below 30%% is not 3")
	h.near("phase.uptime_p1", BossTuning.HP_MAX * 0.35 / (EnemyTypes.PLAYER_DPS * 0.5),
			105.0, 12.0)
	h.near("phase.uptime_p3", BossTuning.HP_MAX * 0.30 / (EnemyTypes.PLAYER_DPS * 0.5),
			90.0, 12.0)

	t.hp = BossTuning.HP_MAX * 0.66
	h.hit_titan(4000.0)
	h.check("phase.crossed_to_2", t.phase == 2, "phase is %d after crossing 65%%" % t.phase)
	h.check("phase.event_2", h.phases_seen.size() == 1 and h.phases_seen[0] == 2,
			"boss_phase emitted %s" % [h.phases_seen])
	h.check("phase.p2_has_beam", h.attack_ids().has("titan_beam"),
			"phase 2 table is %s" % [h.attack_ids()])
	h.check("phase.p1_had_no_beam", not BossTuning.PHASE_ATTACKS[0].has(&"titan_beam"),
			"the beam is in the phase 1 table")

	await h.step(BossTuning.PHASE_CINEMATIC + SETTLE)
	t.hp = BossTuning.HP_MAX * 0.31
	h.hit_titan(4000.0)
	h.check("phase.crossed_to_3", t.phase == 3, "phase is %d after crossing 30%%" % t.phase)
	h.check("phase.event_3_once", h.phases_seen.size() == 2,
			"boss_phase emitted %s" % [h.phases_seen])
	h.check("phase.p3_has_lightning", h.attack_ids().has("titan_lightning"),
			"phase 3 table is %s" % [h.attack_ids()])


## Brief §4: the transition is a 2–3 s cinematic roar with the player invulnerable. The titan takes no
## damage and runs no AI while it plays, then comes back fighting.
static func _phase_cinematic(h: BossTestHarness) -> void:
	h.reset_titan()
	var t := h.titan
	t.hp = BossTuning.HP_MAX * 0.66
	h.hit_titan(2000.0)
	h.check("cinematic.phase_2", t.phase == 2, "phase is %d" % t.phase)
	h.check("cinematic.ai_off", not t.state() in [EnemyBrain.ATTACK],
			"the titan is attacking during its own phase cinematic")
	var before := t.hp
	h.hit_titan(20000.0)
	h.near("cinematic.invulnerable", t.hp, before, 1.0)
	var dt := BossTuning.PHASE_CINEMATIC
	await h.step(dt * 0.5)
	h.near("cinematic.still_locked_halfway", t.hp, before, 1.0)
	await h.step(dt * 0.5 + SETTLE)
	h.hit_titan(2000.0)
	h.check("cinematic.vulnerable_after", t.hp < before,
			"the titan is still invulnerable %.2f s after the roar" % (dt + SETTLE))
	h.check("cinematic.length_in_band", dt >= 2.0 and dt <= 3.0,
			"the phase cinematic is %.2f s, the brief wants 2-3 s" % dt)


## SPEC §7.1: a core takes ×2.5 off its own pool and ×1.0 off the main pool, and breaking it staggers
## the titan and removes the attack that core was feeding.
static func _core_breaks(h: BossTestHarness) -> void:
	h.reset_titan()
	var t := h.titan
	h.check("core.three", t.cores.size() == 3, "%d cores" % t.cores.size())
	h.near("core.hp", t.cores[0].hp_max, BossTuning.CORE_HP, 1.0)

	var index := h.core_index(&"l_shoulder")
	h.check("core.l_shoulder_exists", index >= 0, "no l_shoulder core")
	var main_before := t.hp
	var hit := 1000.0
	h.hit_core(index, hit)
	h.near("core.pool_mult", t.cores[index].hp_max - t.cores[index].hp, hit * 2.5, 1.0)
	h.check("core.main_mult", (main_before - t.hp) <= hit * 1.001,
			"a core hit took %.1f off the main pool, more than x1.0 of %.1f"
			% [main_before - t.hp, hit])
	h.check("core.not_broken_yet", not t.cores[index].broken, "the core broke on one 1000 hit")
	h.check("core.answers_actor_api", t.cores[index].is_alive() and t.cores[index].get_team() == 1,
			"a core must answer is_alive() / get_team() as a hit receiver (CONTRACTS §4)")

	h.hit_core(index, (BossTuning.CORE_HP - hit * 2.5) / BossTuning.CORE_POOL_MULT)
	h.check("core.broken", t.cores[index].broken, "the core survived its whole pool")
	h.check("core.broken_signal", h.cores_broken.has("l_shoulder"),
			"core_broken fired %s" % [h.cores_broken])
	h.check("core.broken_is_not_alive", not t.cores[index].is_alive(), "a broken core says it is alive")
	h.check("core.staggers", t.status.is_staggered(), "breaking a core did not stagger the titan")
	h.near("core.stagger_time", BossTuning.STAGGER_TIME, 3.4, 0.01)
	h.check("core.attack_removed", not h.attack_ids().has("titan_swipe"),
			"the L shoulder core did not remove the swipe: %s" % [h.attack_ids()])
	h.check("core.other_attacks_stay", h.attack_ids().has("titan_stomp"),
			"removing the swipe also removed the stomp")

	var right := h.core_index(&"r_shoulder")
	h.hit_core(right, BossTuning.CORE_HP / BossTuning.CORE_POOL_MULT)
	h.check("core.summon_removed", not h.attack_ids().has("titan_summon"),
			"the R shoulder core did not remove the summon: %s" % [h.attack_ids()])
	h.reset_titan()
	h.check("core.restored", not t.cores[0].broken and t.cores[0].hp == BossTuning.CORE_HP,
			"the checkpoint did not put the core back")


## SPEC §7.1 / brief §2: legs are armoured at ×0.5, the head at ×0.6, the body at ×1.0. `EnemyTypes`
## has no titan row, so this is the boss unit's own table and needs its own gate.
static func _armour(h: BossTestHarness) -> void:
	h.reset_titan()
	var body := h.hit_titan(1000.0, &"body")
	var legs := h.hit_titan(1000.0, &"legs")
	var head := h.hit_titan(1000.0, &"head")
	h.check("armour.body_full", body.final_amount > legs.final_amount,
			"body %.1f is not above legs %.1f" % [body.final_amount, legs.final_amount])
	h.near("armour.legs_half", legs.final_amount / maxf(body.final_amount, 1.0), 0.5, 0.05)
	h.check("armour.head_lower", head.final_amount < body.final_amount,
			"head %.1f is not below body %.1f" % [head.final_amount, body.final_amount])


## SPEC §7.1 checkpoints: dying restores the boss to the START of the phase it was in, whole.
static func _checkpoint(h: BossTestHarness) -> void:
	h.reset_titan()
	var t := h.titan
	t.hp = BossTuning.HP_MAX * 0.20
	h.hit_titan(1000.0)
	h.check("checkpoint.in_p3", t.phase == 3, "phase is %d at 20%%" % t.phase)
	await h.step(BossTuning.PHASE_CINEMATIC + SETTLE)
	t.restore_for_checkpoint(t.phase)
	h.near("checkpoint.hp_at_threshold", t.hp, BossTuning.HP_MAX * 0.30, 1.0)
	h.check("checkpoint.phase_kept", t.phase == 3, "the checkpoint moved the boss to phase %d"
			% t.phase)
	h.check("checkpoint.alive", t.is_alive(), "the boss is dead after a checkpoint")
	h.check("checkpoint.p2_start", is_equal_approx(BossTuning.phase_start_hp(2),
			BossTuning.HP_MAX * 0.65), "phase 2 starts at %.0f" % BossTuning.phase_start_hp(2))


## Brief §5: the killing blow runs a 3 s collapse and `Events.game_won` fires once, 4 s later. The
## director owns the victory beat, so the harness runs one.
static func _death(h: BossTestHarness) -> void:
	h.reset_titan()
	var t := h.titan
	var director := BossDirector.new()
	director.name = "BossDirector"
	director.arena = h.arena
	director.fight_started = true
	director.titan = t
	h.root.add_child(director)
	t.death_started.connect(director._on_death_started)
	var wins := [0]
	var counter := func() -> void: wins[0] = int(wins[0]) + 1
	Events.game_won.connect(counter)
	t.hp = 500.0
	h.hit_titan(2000.0)
	h.check("death.killed", not t.is_alive(), "the titan survived a 2000 hit at 500 HP")
	h.check("death.no_instant_win", int(wins[0]) == 0, "game_won fired before the collapse")
	await h.step(BossTuning.DEATH_CINEMATIC + 0.4)
	h.check("death.game_won_once", int(wins[0]) == 1, "game_won fired %d times" % int(wins[0]))
	await h.step(1.5)
	h.check("death.game_won_still_once", int(wins[0]) == 1,
			"game_won fired %d times in total" % int(wins[0]))
	Events.game_won.disconnect(counter)
	director.queue_free()
	# A dead titan must stop being a target: no hurtboxes, no lock point, out of the enemy group.
	h.check("death.not_targetable", not t.is_in_group(&"enemy"),
			"the corpse is still in the &\"enemy\" group")
