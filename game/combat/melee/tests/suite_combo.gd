class_name MeleeComboSuite
extends RefCounted
## Frame-data and combo assertions (skills-catalog §4.3): startup / active / recovery at 120 Hz,
## the cancel windows, reach and arc against a dummy hurtbox, multi-hit prevention, the 6-frame input
## buffer and the chain order.


static func run(h: MeleeTestHarness) -> void:
	await _frames(h)
	await _clocks(h)
	await _reach_and_arc(h)
	await _cancel_windows(h)
	await _buffer(h)
	await _chain_order(h)


## CONTRACTS §3 clocks: the string runs on PLAYER time, so witch time (the world at 0.25×, the player
## at full speed) must not stretch a 58-tick L1, and a global hit-stop must hold it mid-arc — that
## freeze is the impact. Both are measured against `Feel.real_now()`.
static func _clocks(h: MeleeTestHarness) -> void:
	h.fresh()
	await h.step(0.1)
	var total := MeleeTable.ticks(MeleeTable.total_frames(MeleeTable.L1))
	Feel.slow_mo(0.25, 4.0, 0.0, 0.0, true)
	await h.ticks(2)
	var opened := Feel.real_now()
	await _begin_and_phase(h, MeleeTable.L1, MeleeSystem.Phase.STARTUP)
	await h.ticks(total + 2)
	var real_swing := Feel.real_now() - opened
	h.eq("clock.witch_string_completes", h.system.move, &"")
	h.near("clock.witch_string_is_real_time", real_swing,
			float(total) / MeleeTable.PHYSICS_HZ, 0.05)
	Feel.slow_mo(1.0, 0.01, 0.0, 0.0, false)
	await h.step(0.6)
	h.fresh()
	await h.step(0.1)
	await _begin_and_phase(h, MeleeTable.L3, MeleeSystem.Phase.STARTUP)
	Feel.hit_stop(0.2, 0.05)
	var stopped := Feel.real_now()
	await h.step(0.12)
	var left: int = h.system.get(&"_tick")
	h.check("clock.hit_stop_holds_the_swing", left < MeleeTable.ticks(
			MeleeTable.field(MeleeTable.L3, "startup")) / 2,
			"tick %d after %.3f real s of hit-stop" % [left, Feel.real_now() - stopped])
	await h.step(0.4)
	h.check("clock.swing_resumes", int(h.system.get(&"_tick")) > left,
			"tick %d never moved on from %d" % [int(h.system.get(&"_tick")), left])
	h.fresh()
	await h.step(0.1)


## L1 / L2 / L3 timings in ticks, read off the live state machine.
static func _frames(h: MeleeTestHarness) -> void:
	h.fresh()
	await h.step(0.1)
	h.check("frames.l1_starts_on_press", await _begin_and_phase(h, MeleeTable.L1, MeleeSystem.Phase.STARTUP))
	await h.ticks(MeleeTable.ticks(MeleeTable.field(MeleeTable.L1, "startup")) - 1)
	h.eq("frames.l1_active_at_startup", h.system.phase, MeleeSystem.Phase.ACTIVE)
	await h.ticks(MeleeTable.ticks(MeleeTable.field(MeleeTable.L1, "active")))
	h.eq("frames.l1_recovery_after_active", h.system.phase, MeleeSystem.Phase.RECOVERY)
	var recovery := MeleeTable.ticks(MeleeTable.field(MeleeTable.L1, "recovery"))
	await h.ticks(recovery)
	h.eq("frames.l1_total_length", h.system.move, &"")
	h.near("frames.l1_total_ticks", float(MeleeTable.ticks(MeleeTable.total_frames(MeleeTable.L1))),
			58.0, 1.0)
	h.fresh()
	await h.step(0.1)
	h.system.combo_step = 2   # the third step of the chain (set after the step: an idle mech resets it)
	h.check("frames.l3_starts", await _begin_and_phase(h, MeleeTable.L3, MeleeSystem.Phase.STARTUP))
	await h.ticks(MeleeTable.ticks(MeleeTable.field(MeleeTable.L3, "startup")))
	h.eq("frames.l3_active", h.system.phase, MeleeSystem.Phase.ACTIVE)
	await h.ticks(MeleeTable.ticks(MeleeTable.field(MeleeTable.L3, "active")))
	h.eq("frames.l3_recovery", h.system.phase, MeleeSystem.Phase.RECOVERY)
	await h.ticks(MeleeTable.ticks(MeleeTable.field(MeleeTable.L3, "recovery")) + 1)
	h.eq("frames.l3_ends", h.system.move, &"")


## Reach ×2 for the 16 m hero: L1 hits at 17 m, misses at 24 m; L3's 200° arc reaches a flank target
## that L1's 120° arc cannot. Small dummies keep the assertion about the arc, not the cube's corners.
static func _reach_and_arc(h: MeleeTestHarness) -> void:
	h.fresh()
	var near_dummy := h.add_dummy(17.0, 4.0)
	await h.step(0.1)
	await _swing(h, MeleeTable.L1)
	h.check("reach.l1_hits_at_17m", near_dummy.hits == 1,
			"hits %d at 17 m (reach %0.1f)" % [near_dummy.hits,
			MeleeTable.field(MeleeTable.L1, "reach")])
	h.check("reach.l1_one_hit_per_swing", near_dummy.hits == 1, "multi-hit prevention")
	h.near("reach.l1_damage", near_dummy.damage_taken,
			MeleeTable.field(MeleeTable.L1, "damage"), 0.01)
	h.near("reach.l1_impact", near_dummy.stagger_taken,
			MeleeTable.field(MeleeTable.L1, "impact"), 0.01)
	h.fresh()
	## 30 m: beyond the 18 m reach even after L1's 6 m step-in closes the gap.
	var far_dummy := h.add_dummy(30.0, 4.0)
	await h.step(0.1)
	await _swing(h, MeleeTable.L1)
	h.eq("reach.l1_misses_at_30m", far_dummy.hits, 0)
	## L3 sweeps 200° (±100°), so a target 90° off the front is inside the arc.
	h.fresh()
	var flank := h.add_dummy(17.0, 4.0)
	flank.global_position = _flank_point(h, 90.0, 17.0)
	h.aim.look_at_point(h.player.global_position + Vector3(0.0, 0.0, -50.0))
	await h.step(0.1)
	h.system.combo_step = 2
	await _swing(h, MeleeTable.L3)
	h.check("arc.l3_covers_90_degrees", flank.hits >= 1, "hits %d at 90°" % flank.hits)
	## L1 sweeps only 120° (±60°), so the same flank target is outside it.
	h.fresh()
	var flank2 := h.add_dummy(17.0, 4.0)
	flank2.global_position = _flank_point(h, 90.0, 17.0)
	h.aim.look_at_point(h.player.global_position + Vector3(0.0, 0.0, -50.0))
	await h.step(0.1)
	await _swing(h, MeleeTable.L1)
	h.eq("arc.l1_excludes_90_degrees", flank2.hits, 0)
	## Behind the mech: nothing lands.
	h.fresh()
	var behind := h.add_dummy(17.0, 4.0)
	behind.global_position = h.player.global_position + Vector3(0.0, 0.0, 17.0)
	h.aim.look_at_point(h.player.global_position + Vector3(0.0, 0.0, -50.0))
	await h.step(0.1)
	await _swing(h, MeleeTable.L1)
	h.eq("arc.l1_excludes_rear", behind.hits, 0)


## `degrees` off the mech's forward (-Z) at `metres`.
static func _flank_point(h: MeleeTestHarness, degrees: float, metres: float) -> Vector3:
	var a := deg_to_rad(degrees)
	return h.player.global_position + Vector3(sin(a), 0.0, -cos(a)) * metres


## skills-catalog §4.3: L1 cancels from f14 to f24 (into L2, dash, guard, skills), L3 only into
## movement from f22 to f34, and the charged slash never cancels.
static func _cancel_windows(h: MeleeTestHarness) -> void:
	h.fresh()
	await h.step(0.1)
	h.system.move = MeleeTable.L1
	h.system.phase = MeleeSystem.Phase.RECOVERY
	h.check("cancel.l1_closed_at_f13", not _open_at_frame(h, MeleeTable.L1, 13.0))
	h.check("cancel.l1_open_at_f14", _open_at_frame(h, MeleeTable.L1, 14.0))
	h.check("cancel.l1_open_at_f24", _open_at_frame(h, MeleeTable.L1, 24.0))
	h.check("cancel.l1_closed_at_f25", not _open_at_frame(h, MeleeTable.L1, 25.0))
	h.check("cancel.l3_closed_at_f21", not _open_at_frame(h, MeleeTable.L3, 21.0))
	h.check("cancel.l3_open_at_f22", _open_at_frame(h, MeleeTable.L3, 22.0))
	h.check("cancel.l3_closed_at_f35", not _open_at_frame(h, MeleeTable.L3, 35.0))
	h.check("cancel.charge_slash_never_opens",
			not _open_at_frame(h, MeleeTable.CHARGE_SLASH, 20.0))
	h.system.move = &""
	h.system.phase = MeleeSystem.Phase.IDLE
	## A press inside the window chains straight into the next step.
	h.fresh()
	var d := h.add_dummy(16.0, 6.0)
	await h.step(0.1)
	h.press(&"melee")
	await h.ticks(2)
	h.release(&"melee")
	await h.ticks(MeleeTable.ticks(15.0))
	h.eq("cancel.chain_step_1", h.system.move, MeleeTable.L1)
	h.press(&"melee")
	await h.ticks(2)
	h.release(&"melee")
	await h.ticks(2)
	h.eq("cancel.chained_into_l2", h.system.move, MeleeTable.L2)
	h.check("cancel.dummy_was_hit", d.hits >= 1, "hits %d" % d.hits)


## Parks the state machine on 60 fps frame `frame` of `move` and asks whether the window is open.
static func _open_at_frame(h: MeleeTestHarness, move: StringName, frame: float) -> bool:
	h.system.move = move
	h.system.set("_tick", MeleeTable.ticks(frame - 1.0))
	return h.system.cancel_open()


## SPEC §3: a press up to 6 frames before the window still comes out.
static func _buffer(h: MeleeTestHarness) -> void:
	h.fresh()
	await h.step(0.1)
	h.press(&"melee")
	await h.ticks(2)
	h.release(&"melee")
	await h.ticks(1)
	h.eq("buffer.first_move_started", h.system.move, MeleeTable.L1)
	## Press again around f11: the window opens at f14, so this lands in the 6-frame buffer.
	await h.ticks(MeleeTable.ticks(9.0))
	h.press(&"melee")
	await h.ticks(2)
	h.release(&"melee")
	h.eq("buffer.pending", h.system.get(&"_buffer"), MeleeTable.L2)
	await h.ticks(MeleeTable.ticks(8.0))
	h.eq("buffer.fired_in_window", h.system.move, MeleeTable.L2)


## The chain is L1 → L2 → L3 and wraps; a 1.5 s pause restarts it at L1 (skills-catalog §4.3).
static func _chain_order(h: MeleeTestHarness) -> void:
	h.fresh()
	await h.step(0.1)
	var seen: Array[StringName] = []
	for i in 3:
		h.system.reset()
		h.system.combo_step = i
		seen.append(h.system._pick_move())
	for i in 3:
		h.eq("chain.step_%d" % (i + 1), seen[i], MeleeTable.GROUND_CHAIN[i])
	h.fresh()
	await h.step(0.1)
	await _swing(h, MeleeTable.L1)
	h.eq("chain.step_after_l1", h.system.combo_step, 1)
	await h.step(MeleeTable.COMBO_RESET + 0.2)
	h.eq("chain.resets_after_1_5s", h.system.combo_step, 0)
	h.eq("chain.picks_l1_again", h.system._pick_move(), MeleeTable.L1)


## Presses melee and waits out the whole move.
static func _swing(h: MeleeTestHarness, id: StringName) -> void:
	h.press(&"melee")
	await h.ticks(2)
	h.release(&"melee")
	await h.ticks(MeleeTable.ticks(MeleeTable.total_frames(id)) + 2)


## Presses melee once and checks the move and phase it produced.
static func _begin_and_phase(h: MeleeTestHarness, id: StringName, phase: int) -> bool:
	h.press(&"melee")
	await h.ticks(1)
	h.release(&"melee")
	return h.system.move == id and h.system.phase == phase
