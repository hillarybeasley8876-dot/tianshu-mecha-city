class_name MeleeSpecialSuite
extends RefCounted
## The moves that are not the plain chain (skills-catalog §4.3 / §4.6): the homing lunge and its
## range + EN gate, the charged slash and its crescent wave, the air string with its hover-hang, the
## Return Cut after a perfect parry, the Ram Kick during an assault boost, and the Core Rend rules.


static func run(h: MeleeTestHarness) -> void:
	await _lunge(h)
	await _charge(h)
	await _air(h)
	await _return_cut(h)
	await _ram_kick(h)
	await _execution(h)


## skills-catalog §4.3: a hard lock at 24–80 m arms the lunge (110 m/s, 140 EN). Outside the band or
## without EN the press falls back to the chain.
static func _lunge(h: MeleeTestHarness) -> void:
	h.fresh()
	var target := h.add_dummy(40.0)
	h.aim.lock(target)
	await h.step(0.1)
	h.check("lunge.ready_in_band", h.system.lunge_ready(), "hard lock at 40 m")
	h.eq("lunge.picked", h.system._pick_move(), MeleeTable.LUNGE)
	h.press(&"melee")
	await h.ticks(2)
	h.release(&"melee")
	h.eq("lunge.started", h.system.move, MeleeTable.LUNGE)
	h.near("lunge.en_cost", h.player.energy_spent, MeleeTable.LUNGE_EN, 0.01)
	await h.ticks(MeleeTable.ticks(MeleeTable.field(MeleeTable.LUNGE, "startup")) + 4)
	h.check("lunge.travelled", h.player.lunges > 0, "lunge_to calls %d" % h.player.lunges)
	await h.ticks(MeleeTable.ticks(MeleeTable.field(MeleeTable.LUNGE, "recovery")) + 2)
	## `lunge_to` restarts the mech's lunge timer on every call (CONTRACTS §5), so the homing has to
	## keep re-issuing through the whole travel. Re-issuing only during startup left the mech
	## coasting and falling ~30 m short of a 70 m target — caught by the real-game integration.
	## Measured at the top of the band, where the lunge cannot arrive before the active window ends.
	h.fresh()
	var band_target := h.add_dummy(70.0)
	h.aim.lock(band_target)
	await h.step(0.1)
	h.press(&"melee")
	await h.ticks(2)
	h.release(&"melee")
	await h.ticks(MeleeTable.ticks(MeleeTable.field(MeleeTable.LUNGE, "startup")) + 2)
	var mid := h.player.lunges
	await h.ticks(MeleeTable.ticks(MeleeTable.field(MeleeTable.LUNGE, "active")) - 6)
	h.check("lunge.keeps_homing_through_active", h.player.lunges > mid + 20,
			"lunge_to calls went %d -> %d during the active window" % [mid, h.player.lunges])
	await h.ticks(MeleeTable.ticks(MeleeTable.field(MeleeTable.LUNGE, "recovery")) + 2)
	## Too close: inside the 24 m floor the lunge is not offered.
	h.fresh()
	var close_target := h.add_dummy(18.0)
	h.aim.lock(close_target)
	await h.step(0.1)
	h.check("lunge.refused_below_24m", not h.system.lunge_ready())
	h.eq("lunge.falls_back_to_chain", h.system._pick_move(), MeleeTable.L1)
	## Too far: past 80 m.
	h.fresh()
	var far_target := h.add_dummy(120.0)
	h.aim.lock(far_target)
	await h.step(0.1)
	h.check("lunge.refused_past_80m", not h.system.lunge_ready())
	## Not enough EN.
	h.fresh()
	var poor_target := h.add_dummy(40.0)
	h.aim.lock(poor_target)
	h.player.energy = MeleeTable.LUNGE_EN - 1.0
	await h.step(0.1)
	h.check("lunge.refused_without_en", not h.system.lunge_ready())
	h.eq("lunge.no_en_falls_back", h.system._pick_move(), MeleeTable.L1)


## Hold ≥30 f and release: the charged slash, 1,500 damage, plus a crescent wave that travels.
static func _charge(h: MeleeTestHarness) -> void:
	h.fresh()
	var d := h.add_dummy(20.0)
	await h.step(0.1)
	h.press(&"melee")
	await h.ticks(MeleeTable.ticks(MeleeTable.CHARGE_FRAMES) + 4)
	h.check("charge.stance_opens", h.system.charge.charging, "after %d f" % int(MeleeTable.CHARGE_FRAMES))
	h.check("charge.ratio_grows", h.system.charge_ratio() >= 0.5,
			"ratio %.2f" % h.system.charge_ratio())
	h.release(&"melee")
	await h.ticks(2)
	h.eq("charge.slash_started", h.system.move, MeleeTable.CHARGE_SLASH)
	h.check("charge.not_charging_after_release", not h.system.charge.charging)
	await h.ticks(MeleeTable.ticks(MeleeTable.field(MeleeTable.CHARGE_SLASH, "startup")) + 2)
	var waves := h.root.find_children("CrescentWave", "", true, false)
	h.check("charge.wave_spawned", waves.size() >= 1, "waves %d" % waves.size())
	var wave := waves[0] as Node3D if waves.size() > 0 else null
	var start_z := wave.global_position.z if wave != null else 0.0
	await h.step(0.2)
	var moved := absf((wave.global_position.z if wave != null else 0.0) - start_z)
	h.check("charge.wave_travels", moved > 10.0, "moved %.1f m in 0.2 s" % moved)
	await h.ticks(MeleeTable.ticks(MeleeTable.total_frames(MeleeTable.CHARGE_SLASH)))
	h.check("charge.hit_dummy", d.hits >= 1, "hits %d" % d.hits)
	## A short tap never charges.
	h.fresh()
	await h.step(0.1)
	h.press(&"melee")
	await h.ticks(4)
	h.release(&"melee")
	await h.ticks(2)
	h.check("charge.tap_does_not_charge", not h.system.charge.charging)
	h.eq("charge.tap_is_l1", h.system.move, MeleeTable.L1)


## Air string: L1 → L2 with a 0.3 s hover-hang (skills-catalog §4.3).
static func _air(h: MeleeTestHarness) -> void:
	h.fresh()
	h.player.grounded = false
	h.add_dummy(14.0)
	await h.step(0.1)
	h.eq("air.picks_air_l1", h.system._pick_move(), MeleeTable.AIR_L1)
	h.press(&"melee")
	await h.ticks(2)
	h.release(&"melee")
	await h.ticks(2)
	h.eq("air.l1_started", h.system.move, MeleeTable.AIR_L1)
	h.check("air.hang_set", float(h.system.get(&"_air_hang")) > 0.25,
			"hang %.3f of %.2f s" % [float(h.system.get(&"_air_hang")), MeleeTable.AIR_HANG])
	await h.ticks(MeleeTable.ticks(MeleeTable.total_frames(MeleeTable.AIR_L1)) + 1)
	h.eq("air.next_is_air_l2", h.system._pick_move(), MeleeTable.AIR_L2)
	h.player.grounded = true


## skills-catalog §4.7: a perfect parry opens a 0.8 s Return Cut window; the next press takes it.
static func _return_cut(h: MeleeTestHarness) -> void:
	h.fresh()
	var d := h.add_dummy(16.0)
	await h.step(0.1)
	var hit := HitInfo.make(0.0, HitInfo.MELEE, null, &"test")
	Events.parry_success.emit(hit, null)
	await h.ticks(2)
	h.near("return.window_open", float(h.system.get(&"_return_left")),
			MeleeTable.RETURN_WINDOW, 0.05)
	h.eq("return.picked", h.system._pick_move(), MeleeTable.RETURN_CUT)
	h.press(&"melee")
	await h.ticks(2)
	h.release(&"melee")
	await h.ticks(MeleeTable.ticks(MeleeTable.total_frames(MeleeTable.RETURN_CUT)) + 2)
	h.check("return.hit_for_1400", d.damage_taken >= MeleeTable.field(MeleeTable.RETURN_CUT, "damage"),
			"dealt %.0f" % d.damage_taken)
	## Past the window the chain is back.
	h.fresh()
	await h.step(0.1)
	Events.parry_success.emit(hit, null)
	await h.step(MeleeTable.RETURN_WINDOW + 0.2)
	h.eq("return.expires", h.system._pick_move(), MeleeTable.L1)


## SPEC §4: melee during an assault boost is the Ram Kick, ×2.5 against a staggered target.
static func _ram_kick(h: MeleeTestHarness) -> void:
	h.fresh()
	h.player.move_state_name = &"assault"
	var d := h.add_dummy(16.0)
	await h.step(0.1)
	h.eq("ram.picked_while_assaulting", h.system._pick_move(), MeleeTable.RAM_KICK)
	h.press(&"melee")
	await h.ticks(MeleeTable.ticks(MeleeTable.total_frames(MeleeTable.RAM_KICK)) + 2)
	h.release(&"melee")
	h.near("ram.base_damage", d.damage_taken,
			MeleeTable.field(MeleeTable.RAM_KICK, "damage"), 0.01)
	h.fresh()
	h.player.move_state_name = &"assault"
	var staggered := h.add_dummy(16.0)
	staggered.stagger()
	h.aim.lock(staggered)
	await h.step(0.1)
	h.press(&"melee")
	await h.ticks(MeleeTable.ticks(MeleeTable.total_frames(MeleeTable.RAM_KICK)) + 2)
	h.release(&"melee")
	h.near("ram.x2_5_vs_staggered", staggered.damage_taken,
			MeleeTable.field(MeleeTable.RAM_KICK, "damage") * MeleeTable.RAM_KICK_STAGGER_MULT, 0.01)
	h.player.move_state_name = &"idle"
	h.aim.lock(null)


## skills-catalog §4.6 Core Rend: a press on a staggered enemy inside 14 m and ±60° executes it,
## makes the player invulnerable for the lock and pays out EN / OD / HP.
static func _execution(h: MeleeTestHarness) -> void:
	h.fresh()
	var victim := h.add_dummy(10.0)
	h.aim.lock(victim)
	await h.step(0.1)
	h.check("exec.not_available_before_stagger", not h.system.execution_available())
	victim.stagger()
	await h.step(0.1)
	h.check("exec.available_when_staggered", h.system.execution_available())
	h.player.hp = h.player.hp_max * 0.5
	h.press(&"melee")
	await h.ticks(2)
	h.release(&"melee")
	h.check("exec.running", h.system.executor.active, "director active")
	h.eq("exec.hit_enemy", victim.executions, 1)
	h.check("exec.invulnerable", h.player.is_invulnerable(), "i-frames for the lock")
	h.near("exec.en_reward", h.player.energy_gained, ExecutionDirector.REWARD_EN, 1.0)
	h.near("exec.od_reward", h.player.overdrive, ExecutionDirector.REWARD_OD, 0.01)
	h.near("exec.hp_reward", h.player.healed, h.player.hp_max * ExecutionDirector.REWARD_HP, 1.0)
	h.eq("exec.class_light", ExecutionDirector.class_of(victim), &"light")
	await h.step(1.1)
	h.check("exec.finished", not h.system.executor.active)
	## Out of range: 20 m is past the 14 m gate, so the press is a normal swing.
	h.fresh()
	var far := h.add_dummy(20.0)
	h.aim.lock(far)
	far.stagger()
	await h.step(0.1)
	h.check("exec.refused_past_14m", not h.system.execution_available())
	## Outside the ±60° cone: the monster is looking the other way, so its core faces away.
	h.fresh()
	var turned := h.add_dummy(10.0)
	turned.global_rotation.y = 0.0   # look_at already turned it toward the mech; undo that
	h.aim.lock(turned)
	turned.stagger()
	await h.step(0.1)
	h.check("exec.refused_outside_cone", not h.system.execution_available())
	## Durations by class (skills-catalog §4.6): brute 1.8 s, colossus 2.4 s.
	h.fresh()
	var brute := h.add_dummy(10.0)
	brute.enemy_type = &"juggernaut"
	h.eq("exec.class_brute", ExecutionDirector.class_of(brute), &"brute")
	h.near("exec.brute_duration", float(ExecutionDirector.CLASSES[&"brute"]["duration"]), 1.8, 0.001)
	h.near("exec.colossus_duration", float(ExecutionDirector.CLASSES[&"colossus"]["duration"]),
			2.4, 0.001)
