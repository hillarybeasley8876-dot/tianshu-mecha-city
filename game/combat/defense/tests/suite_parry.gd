class_name DefenseParrySuite
extends RefCounted
## Mirror Guard's parry and block half (skills-catalog §4.4 S5): the 167 ms perfect window and its
## 83 ms anti-mash shrink, the 18-frame minimum guard, the −70 % block inside a 140° front arc, the
## EN drain and the guard break, and the fact that red-glow (`unblockable`) attacks bypass it all.


static func run(h: DefenseTestHarness) -> void:
	await _perfect_window(h)
	await _witch_time_window(h)
	await _spam_window(h)
	await _minimum_guard(h)
	await _perfect_effects(h)
	await _block(h)
	await _block_arc(h)
	await _en_and_break(h)
	await _unblockable(h)


## The first 10 f of a guard are the perfect window (Sekiro 12 f, DMC 6 f — this sits between).
static func _perfect_window(h: DefenseTestHarness) -> void:
	h.fresh()
	await h.step(0.1)
	h.check("parry.idle_is_not_guarding", not h.system.is_guarding())
	h.press(&"guard")
	await h.ticks(1)
	h.check("parry.opens_on_press", h.system.in_perfect_window())
	var perfect_ticks := DefenseTable.perfect_ticks(false)
	await h.ticks(perfect_ticks - 2)
	h.check("parry.still_open_at_the_edge", h.system.in_perfect_window(),
			"%d ticks in" % (perfect_ticks - 1))
	await h.ticks(2)
	h.check("parry.closes_after_the_window", not h.system.in_perfect_window())
	h.check("parry.becomes_a_block", h.system.hud_state()["state"] == "BLOCKING")
	h.near("parry.window_is_167ms", float(perfect_ticks) / DefenseTable.PHYSICS_HZ, 0.1667, 0.005)
	h.release(&"guard")
	await h.step(0.4)


## Under witch time the world crawls but the player does not (CONTRACTS §3): the perfect window is
## 167 ms of REAL time, not 167 ms of the world's slowed clock. Measured with `Feel.real_now()`,
## which is the same clock in a fixed-fps test as in live play.
static func _witch_time_window(h: DefenseTestHarness) -> void:
	h.fresh()
	await h.step(0.1)
	Feel.slow_mo(0.25, 4.0, 0.0, 0.0, true)
	await h.ticks(2)
	h.check("witch.time_is_slowed", Engine.time_scale < 0.9, "scale %.2f" % Engine.time_scale)
	h.press(&"guard")
	await h.ticks(2)
	var opened := Feel.real_now()
	var world := 0.0
	var perfect_ticks := DefenseTable.perfect_ticks(false)
	## Physics ticks are real time, so the same number of ticks must elapse either way.
	for _i in perfect_ticks + 2:
		await h.tree.physics_frame
		world += h.tree.root.get_process_delta_time()
	var real_open := Feel.real_now() - opened
	h.check("witch.window_closed_on_schedule", not h.system.in_perfect_window())
	h.near("witch.window_is_167ms_real", real_open, 0.1667, 0.03)
	## And the world's own clock really did crawl: that is what makes the check above meaningful.
	h.check("witch.world_clock_crawled", world < real_open * 0.5,
			"real %.3f s vs world %.3f s at scale %.2f" % [real_open, world, Engine.time_scale])
	h.release(&"guard")
	Feel.slow_mo(1.0, 0.01, 0.0, 0.0, false)
	await h.step(0.6)
	h.near("witch.time_scale_restored", Engine.time_scale, 1.0, 0.01)


## Re-pressing within 0.5 s of a release shrinks the window to 5 f (83 ms) — the anti-mash rule.
static func _spam_window(h: DefenseTestHarness) -> void:
	h.fresh()
	await h.step(0.1)
	h.press(&"guard")
	await h.ticks(DefenseTable.ticks(DefenseTable.MIN_GUARD_FRAMES) + 4)
	h.release(&"guard")
	await h.ticks(2)
	h.check("spam.first_guard_ended", not h.system.is_guarding())
	## Re-press immediately: inside SPAM_WINDOW, so the perfect window is halved.
	h.press(&"guard")
	await h.ticks(1)
	var spam_ticks := DefenseTable.perfect_ticks(true)
	await h.ticks(spam_ticks - 1)
	h.check("spam.still_open_at_the_edge", h.system.in_perfect_window(),
			"%d ticks in, window %d" % [spam_ticks, spam_ticks])
	await h.ticks(1)
	h.check("spam.window_already_closed", not h.system.in_perfect_window(),
			"%d ticks in, window %d" % [spam_ticks + 1, spam_ticks])
	h.near("spam.window_is_83ms", float(spam_ticks) / DefenseTable.PHYSICS_HZ, 0.0833, 0.005)
	h.release(&"guard")
	await h.step(DefenseTable.SPAM_WINDOW + 0.3)
	## Past the 0.5 s anti-mash window the full window is back.
	h.press(&"guard")
	await h.ticks(1)
	h.near("spam.full_window_returns", float(h.system.get(&"_perfect_ticks")),
			float(DefenseTable.perfect_ticks(false)), 0.01)
	h.release(&"guard")
	await h.step(0.4)


## However brief the tap, the guard stays up for at least 18 f (0.3 s).
static func _minimum_guard(h: DefenseTestHarness) -> void:
	h.fresh()
	await h.step(0.1)
	var minimum := DefenseTable.ticks(DefenseTable.MIN_GUARD_FRAMES)
	h.press(&"guard")
	await h.ticks(2)
	h.release(&"guard")
	await h.ticks(minimum - 8)
	h.check("min_guard.still_up_before_18f", h.system.is_guarding())
	await h.ticks(8)
	h.check("min_guard.drops_after_18f", not h.system.is_guarding())
	await h.step(0.6)


## Perfect vs a parryable melee hit: 0 damage, the attacker eats 600 stability and 0.6 s of recoil,
## both sides freeze 8 f, and the player banks +150 EN and +4 % OD (skills-catalog §4.4).
static func _perfect_effects(h: DefenseTestHarness) -> void:
	h.fresh()
	var attacker := h.add_attacker()
	await h.step(0.1)
	h.press(&"guard")
	await h.ticks(2)
	var hp_before := h.player.hp
	var hit := h.make_hit(6.0, 900.0, attacker)
	var consumed := _filter(h, hit)
	h.check("perfect.consumes_the_hit", consumed)
	h.near("perfect.zero_damage", h.player.hp - hp_before, 0.0, 0.01)
	h.eq("perfect.counted", h.system.parries, 1)
	h.near("perfect.en_reward", h.player.energy_gained, DefenseTable.PARRY_EN, 0.01)
	h.near("perfect.od_reward", h.player.overdrive, DefenseTable.PARRY_OD, 0.01)
	h.near("perfect.attacker_stability", attacker.status.stability,
			700.0 - DefenseTable.PARRY_STABILITY, 0.01)
	h.check("perfect.attacker_in_recoil", not attacker.ai_enabled,
			"AI paused for %.1f s" % DefenseTable.PARRY_RECOIL)
	await h.step(DefenseTable.PARRY_RECOIL + 0.2)
	h.check("perfect.attacker_recovers", attacker.ai_enabled)
	h.release(&"guard")
	await h.step(0.4)


## Held block: −70 % damage, and the reduction is recorded for the HUD.
static func _block(h: DefenseTestHarness) -> void:
	h.fresh()
	await h.step(0.1)
	h.press(&"guard")
	await h.ticks(DefenseTable.perfect_ticks(false) + 4)
	h.check("block.state_is_blocking", h.system.hud_state()["state"] == "BLOCKING")
	var hit := h.make_hit(6.0, 1000.0)
	var consumed := _filter(h, hit)
	h.check("block.does_not_consume", not consumed, "damage still lands, reduced")
	h.near("block.reduced_amount", hit.amount, 1000.0 * (1.0 - DefenseTable.BLOCK_REDUCTION), 0.01)
	h.near("block.absorbed_recorded", h.system.blocked_damage,
			1000.0 * DefenseTable.BLOCK_REDUCTION, 0.01)
	h.release(&"guard")
	await h.step(0.4)
	## Not guarding at all: the hit lands in full.
	h.fresh()
	await h.step(0.1)
	var raw := h.make_hit(6.0, 1000.0)
	h.check("block.no_guard_no_filter", not _filter(h, raw))
	h.near("block.unguarded_amount", raw.amount, 1000.0, 0.01)


## The block arc is 140° in front; anything from behind gets through untouched.
static func _block_arc(h: DefenseTestHarness) -> void:
	h.fresh()
	await h.step(0.1)
	h.press(&"guard")
	await h.ticks(DefenseTable.perfect_ticks(false) + 4)
	var front := h.make_hit(6.0, 1000.0)
	_filter(h, front)
	h.near("arc.front_is_reduced", front.amount, 300.0, 0.01)
	var side := h.make_hit(6.0, 1000.0)
	side.position = h.player.global_position + Vector3(6.0, 0.0, 0.0)  # 90° off: outside 140°
	_filter(h, side)
	h.near("arc.side_at_90_is_not_reduced", side.amount, 1000.0, 0.01)
	var rear := h.make_hit(6.0, 1000.0)
	rear.position = h.player.global_position + Vector3(0.0, 0.0, 6.0)
	_filter(h, rear)
	h.near("arc.rear_is_not_reduced", rear.amount, 1000.0, 0.01)
	h.release(&"guard")
	await h.step(0.4)


## EN: 60/s while blocking plus 25 per 100 absorbed; hitting 0 breaks the guard for 1.0 s.
static func _en_and_break(h: DefenseTestHarness) -> void:
	h.fresh()
	await h.step(0.1)
	## 0.25 s is inside the 0.3 s catch threshold, so the block rate (60/s) is what is being measured.
	h.press(&"guard")
	await h.step(0.25)
	h.release(&"guard")
	var spent := h.player.energy_spent
	h.check("en.drains_while_blocking", spent > DefenseTable.BLOCK_EN_PER_SEC * 0.2,
			"spent %.1f in 0.25 s" % spent)
	h.near("en.drain_is_60_per_sec", spent, DefenseTable.BLOCK_EN_PER_SEC * 0.25, 2.0)
	await h.step(0.5)
	## Past 0.3 s the catch field is open and the drain is 140/s (skills-catalog §4.4).
	h.fresh()
	await h.step(0.1)
	h.press(&"guard")
	await h.step(0.5)
	h.release(&"guard")
	var catch_spent := h.player.energy_spent
	var expected := DefenseTable.BLOCK_EN_PER_SEC * DefenseTable.CATCH_HOLD \
			+ DefenseTable.CATCH_EN_PER_SEC * (0.5 - DefenseTable.CATCH_HOLD)
	h.near("en.catch_field_drains_140_per_sec", catch_spent, expected, 8.0)
	await h.step(0.5)
	h.fresh()
	await h.step(0.1)
	h.player.energy = 20.0
	h.press(&"guard")
	await h.step(0.4)
	h.check("en.guard_breaks_at_zero", h.system.hud_state()["guard_break"],
			"state %s" % h.system.hud_state()["state"])
	h.check("en.break_stuns_the_mech", h.player.lock_left > 0.5,
			"lock %.2f s" % h.player.lock_left)
	h.check("en.break_drops_the_shield", not h.system.is_guarding())
	h.release(&"guard")
	await h.step(DefenseTable.GUARD_BREAK_TIME + 0.2)
	h.check("en.recovers_after_1s", not h.system.hud_state()["guard_break"])


## Red-glow attacks (`hit.unblockable`) ignore the perfect window and the block alike (SPEC §7).
static func _unblockable(h: DefenseTestHarness) -> void:
	h.fresh()
	await h.step(0.1)
	h.press(&"guard")
	await h.ticks(2)
	var red := h.make_hit(6.0, 1500.0)
	red.unblockable = true
	red.parryable = false
	h.check("unblockable.bypasses_the_parry", not _filter(h, red))
	h.near("unblockable.full_damage", red.amount, 1500.0, 0.01)
	h.eq("unblockable.no_parry_counted", h.system.parries, 0)
	await h.ticks(DefenseTable.perfect_ticks(false) + 4)
	var red2 := h.make_hit(6.0, 1500.0)
	red2.unblockable = true
	h.check("unblockable.bypasses_the_block", not _filter(h, red2))
	h.near("unblockable.block_does_not_reduce", red2.amount, 1500.0, 0.01)
	h.release(&"guard")
	await h.step(0.4)


## Runs the hit through the player's real pipeline (CONTRACTS §5 add_damage_filter).
static func _filter(h: DefenseTestHarness, hit: HitInfo) -> bool:
	for f: Callable in h.player.filters:
		if f.is_valid() and bool(f.call(hit)):
			return true
	return false


