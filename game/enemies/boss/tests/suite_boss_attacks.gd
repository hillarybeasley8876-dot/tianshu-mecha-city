class_name BossAttackSuite
extends RefCounted
## The Brood Titan's attack layer (boss unit): telegraph floors, the stomp ring, the beam sweep, the
## summon cap and the phase-3 storm. Also prints the phase-by-phase balance report.

const SETTLE := 0.2


static func run(h: BossTestHarness) -> void:
	_telegraphs(h)
	await _ring(h)
	await _beam(h)
	await _summon(h)
	await _storm(h)
	_balance(h)


## SPEC §7.1: unblockables ≥ 600 ms (boss ≥ 800 ms), parryables ≥ 400 ms — and the brief's gate asks
## for ≥ 0.6 s on every unblockable in EVERY phase, after the phase speed scaling.
static func _telegraphs(h: BossTestHarness) -> void:
	for phase in BossTuning.PHASE_COUNT:
		var table := BossCombat.build_table(phase, [] as Array)
		h.check("telegraph.phase%d_not_empty" % phase, not table.is_empty(),
				"phase %d has no attacks" % phase)
		for a: EnemyAttack in table:
			var floor_s := 0.6 if a.kind == EnemyAttack.UNBLOCKABLE else 0.4
			h.check("telegraph.%s.p%d" % [a.id, phase], a.telegraph >= floor_s,
					"%s windup is %.3f s, floor %.2f s" % [a.id, a.telegraph, floor_s])
			h.check("telegraph.%s.p%d.kind" % [a.id, phase],
					a.kind in [EnemyAttack.PARRYABLE, EnemyAttack.UNBLOCKABLE,
					EnemyAttack.RANGED],
					"%s has kind '%s'" % [a.id, a.kind])
	# P3 is faster than P1 without becoming unreadable.
	var p1 := BossTuning.scaled_row(&"titan_swipe", 1) as Dictionary
	var p3 := BossTuning.scaled_row(&"titan_swipe", 3) as Dictionary
	h.check("telegraph.p3_faster", float(p3["cooldown"]) < float(p1["cooldown"]),
			"the phase 3 swipe cooldown is not shorter than phase 1's")
	h.check("telegraph.p3_still_readable", float(p3["telegraph"]) >= BossTuning.BOSS_MIN_PARRYABLE,
			"the phase 3 swipe windup fell to %.3f s" % float(p3["telegraph"]))
	# The core → attack map is the contract the HUD plate and the whole fight rest on.
	h.check("telegraph.core_map",
			BossTuning.core_row(&"core_l").get("removes") == &"titan_swipe"
			and BossTuning.core_row(&"core_r").get("removes") == &"titan_summon"
			and BossTuning.core_row(&"core_chest").get("removes") == &"titan_beam",
			"the core to attack map is wrong")


## The stomp ring: it reaches the player standing on the deck and misses the one in the air. The
## titan's AI is off for this one so the geometry is fixed — otherwise it walks between the ring and
## the player and the test measures the fight, not the ring.
static func _ring(h: BossTestHarness) -> void:
	h.reset_titan()
	h.titan.set_ai_enabled(false)
	h.titan.global_position = h.arena.ring_point(0.0, 0.55, 1.0)
	h.player.damage_taken = 0.0
	h.player.global_position = h.arena.ring_point(0.0, 0.30, 2.0)
	var attack := EnemyAttack.make(BossTuning.STOMP)
	var ring := _spawn_ring(h, attack)
	h.check("ring.spawned", ring != null, "TitanRing.spawn returned null")
	if ring == null:
		return
	var reach := float(BossTuning.STOMP["shockwave_radius"]) / TitanRing.SPEED
	var gap := h.titan.global_position.distance_to(h.player.global_position)
	h.check("ring.in_range", gap < float(BossTuning.STOMP["shockwave_radius"]),
			"the player is %.0f m out, outside the ring's %.0f m"
			% [gap, float(BossTuning.STOMP["shockwave_radius"])])
	await h.step(reach + SETTLE)
	h.check("ring.hits_grounded", h.player.damage_taken > 0.0,
			"the ring never reached a player standing on the deck")
	h.check("ring.freed", not is_instance_valid(ring), "the ring outlived its radius")

	h.player.damage_taken = 0.0
	h.player.global_position = h.arena.ring_point(0.0, 0.30, 2.0) + Vector3.UP * 20.0
	var air := _spawn_ring(h, attack)
	await h.step(reach + SETTLE)
	h.near("ring.jumpable", h.player.damage_taken, 0.0, 0.001)
	if is_instance_valid(air):
		air.queue_free()
	h.titan.set_ai_enabled(true)


## The ring leaves the foot, on the deck surface — the same point the real stomp uses.
static func _spawn_ring(h: BossTestHarness, attack: EnemyAttack) -> TitanRing:
	var foot := h.titan.global_position + Vector3(0.0, 0.0, -BossTuning.RADIUS)
	foot.y = h.arena.floor_y_at(foot) + 1.0
	return TitanRing.spawn(h.world, foot, attack, h.titan)


## Brief §3: the beam sweeps for exactly its active window and covers BEAM_SWEEP_DEG.
static func _beam(h: BossTestHarness) -> void:
	h.reset_titan()
	var active := float(BossTuning.BEAM["active"])
	var beam := TitanBeam.spawn(h.world, h.titan.global_position + Vector3.UP * 48.0, 0.0, h.titan)
	h.check("beam.spawned", beam != null, "TitanBeam.spawn returned null")
	if beam == null:
		return
	beam.start()
	await h.step(active * 0.5)
	h.check("beam.runs_midway", is_instance_valid(beam) and beam.running,
			"the beam stopped before half its window")
	h.near("beam.mid_sweep", rad_to_deg(beam.rotation.y), 0.0, 1.0)
	await h.step(active * 0.5 + SETTLE)
	h.check("beam.stops_on_time", not is_instance_valid(beam),
			"the beam outlived its %.1f s window" % active)
	var want := BossTuning.BEAM_SWEEP_DEG
	h.check("beam.sweep_arc", want >= 90.0 and want <= 180.0,
			"a %.0f deg sweep is not a readable sweep" % want)
	h.check("beam.telegraph", float(BossTuning.BEAM["telegraph"]) >= 0.8,
			"the beam inhale is %.2f s, the boss floor is 0.8 s"
			% float(BossTuning.BEAM["telegraph"]))


## Brief §3: 6 rippers + 2 harriers off the deck edge, never more than SUMMON_CAP alive.
static func _summon(h: BossTestHarness) -> void:
	h.reset_titan()
	var spawner := h.titan.spawner()
	h.check("summon.spawner", spawner != null, "the titan has no spawner for its adds")
	if spawner == null:
		return
	spawner.clear()
	await h.frame()
	var before := spawner.alive_count()
	BossCombat.summon(h.titan)
	await h.frame()
	# The titan fights for real during the earlier suites and may have summoned already, so the gate
	# is the size of THIS wave, not the total on the deck.
	var added := spawner.alive_count() - before
	var wanted := BossTuning.SUMMON_RIPPERS + BossTuning.SUMMON_HARRIERS
	h.check("summon.first_wave", added == wanted, "this summon brought %d adds, wanted %d"
			% [added, wanted])
	for i in 3:
		BossCombat.summon(h.titan)
		await h.frame()
	h.check("summon.cap", spawner.alive_count() <= BossTuning.SUMMON_CAP,
			"%d adds are alive, the cap is %d" % [spawner.alive_count(), BossTuning.SUMMON_CAP])
	spawner.clear()
	await h.frame()


## Phase 3: the storm calls telegraphed circles that strike after their full windup.
static func _storm(h: BossTestHarness) -> void:
	h.reset_titan()
	h.player.damage_taken = 0.0
	h.player.global_position = h.titan.global_position + Vector3(0.0, 2.0, 60.0)
	BossCombat.storm(h.titan)
	await h.frame()
	var strikes := h.root.get_tree().get_nodes_in_group(&"titan_lightning")
	h.check("storm.circles", strikes.size() == BossTuning.LIGHTNING_CIRCLES,
			"%d circles, wanted %d" % [strikes.size(), BossTuning.LIGHTNING_CIRCLES])
	await h.step(float(BossTuning.LIGHTNING["telegraph"]) + BossTuning.LIGHTNING_CIRCLES * 0.22
			+ SETTLE)
	h.check("storm.cleared", h.root.get_tree().get_nodes_in_group(&"titan_lightning").is_empty(),
			"the strikes never cleaned themselves up")
	h.check("storm.telegraph", float(BossTuning.LIGHTNING["telegraph"]) >= 0.8,
			"the lightning windup is %.2f s, the boss floor is 0.8 s"
			% float(BossTuning.LIGHTNING["telegraph"]))


## One line per phase: the pool, the uptime at 50 % of the SPEC §7.1 player DPS, and the target.
static func _balance(h: BossTestHarness) -> void:
	var dps := EnemyTypes.PLAYER_DPS * 0.5
	var cuts := [1.0, BossTuning.PHASE_THRESHOLDS[0], BossTuning.PHASE_THRESHOLDS[1], 0.0]
	var targets := [90.0, 120.0, 90.0]
	for i in BossTuning.PHASE_COUNT:
		var pool: float = float(cuts[i]) - float(cuts[i + 1])
		var seconds := BossTuning.HP_MAX * pool / dps
		h.check("balance.p%d_uptime" % (i + 1), absf(seconds - float(targets[i])) <= 30.0,
				"phase %d lasts %.0f s, the target is %.0f s" % [i + 1, seconds, targets[i]])
		print("BALANCE phase %d  pool %6.0f  uptime %5.0f s (target %.0f s)"
				% [i + 1, BossTuning.HP_MAX * pool, seconds, targets[i]])
	print("BALANCE cores   3 x %5.0f  (x%.1f to the core pool, x%.1f to the main pool)"
			% [BossTuning.CORE_HP, BossTuning.CORE_POOL_MULT, BossTuning.CORE_MAIN_MULT])
