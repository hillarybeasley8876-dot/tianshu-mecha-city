class_name SkillFinisherSuite
extends RefCounted
## S8 Plunge Breaker and the Zenith Overdrive -> Zenith Lance: the height gate, the dive's damage
## bonus, the OD-100 gate, the Overdrive buff values and the lance's duration and tick count.

static func run(h: SkillTestHarness) -> void:
	await _plunge_gate(h)
	await _plunge_damage(h)
	await _od_gate(h)
	await _od_buffs(h)
	await _od_ghosts(h)
	await _lance_shake(h)
	await _lance_sweep_cap(h)
	await _lance(h)


## skills-catalog §4.5: the mech is rooted and the beam may only sweep at 40 deg/s, so the Lance is a
## positioning statement rather than a flick shot. Measured PER PHYSICS TICK — a real-clock window is
## not available under the test host's variable frame rate.
static func _lance_sweep_cap(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	h.player.global_basis = Basis.IDENTITY
	h.aim.point = Vector3(0.0, 3.0, -400.0)
	h.player.overdrive = h.system.tuning.od_required
	h.system.try_overdrive()
	await h.wait_until(func() -> bool: return h.system.zenith.can_fire_lance(), 6.0)
	h.system.zenith.begin_lance()
	await h.wait_until(func() -> bool: return h.system.zenith.lance.is_beaming(), 6.0)
	var lance := h.system.zenith.lance
	var prev := lance.beam_dir()
	# a 70 deg aim change: an unclamped beam would snap the whole way in one tick
	h.aim.point = Vector3(376.0, 3.0, -137.0)
	var worst := 0.0
	var turned := 0.0
	for _i in 120:
		await h.tree.physics_frame
		var now := lance.beam_dir()
		var step := rad_to_deg(prev.angle_to(now))
		worst = maxf(worst, step)
		turned += step
		prev = now
	var cap := h.system.tuning.lance_turn_deg / 120.0
	h.check("lance.sweep_capped_at_40_deg_per_s", worst <= cap * 1.5,
			"worst single-tick turn %.3f deg, the cap is %.3f deg/tick (%.1f deg over 120 ticks)"
			% [worst, cap, turned])
	h.check("lance.sweep_actually_turns", turned > 1.0,
			"the beam never turned (%.2f deg over 120 ticks)" % turned)
	await h.wait_until(func() -> bool: return not lance.is_running(), 16.0)


# --- S8 Plunge Breaker ----------------------------------------------------------------------------

## The plunge needs the mech airborne AND at least 16 m up; either half failing refuses it.
static func _plunge_gate(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	await h.step(0.1)
	h.check("plunge.refused_on_ground", not h.system.plunge.height_ok(),
			"the gate passed while standing")
	h.check("plunge.grounded_refused", not h.system.try_plunge(), "the plunge fired from the floor")
	h.check("plunge.charge_kept", h.system.slot(&"plunge").charges == 1,
			"the refusal spent a charge")
	await h.lift(12.0)
	h.check("plunge.refused_below_16m", not h.system.plunge.height_ok(),
			"the gate passed at 12 m")
	await h.lift(40.0)
	h.check("plunge.allowed_high", h.system.plunge.height_ok(), "the gate failed at 40 m")
	h.check("plunge.fires", h.system.try_plunge(), "the plunge was refused at 40 m")
	h.system.plunge.reset()


## +10 % per 20 m fallen, capped at +50 %; the rim of the 20 m blast takes 500 x the bonus.
static func _plunge_damage(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	var t := h.system.tuning
	var p := h.system.plunge
	h.near("plunge.bonus_none", p.height_bonus(10.0), 1.0, 0.001)
	h.near("plunge.bonus_one_step", p.height_bonus(20.0), 1.1, 0.001)
	h.near("plunge.bonus_three_steps", p.height_bonus(60.0), 1.3, 0.001)
	h.near("plunge.bonus_capped", p.height_bonus(400.0), 1.5, 0.001)

	h.player.global_position = Vector3(0.0, 60.0, 0.0)
	h.player.grounded = false
	var foe := h.add_target(Vector3(0.0, 0.0, -6.0))
	await h.step(0.05)
	h.check("plunge.dive_starts", h.system.try_plunge(), "the dive was refused")
	h.check("plunge.hanging", p.is_diving(), "not in the hang or the dive")
	h.check("plunge.lands", await h.wait_until(func() -> bool: return foe.damage_taken > 0.0, 4.0),
			"the dive never reached the ground")
	h.check("plunge.impact_damage", foe.damage_taken > t.plunge_damage * 0.9,
			"the blast did %.0f" % foe.damage_taken)
	h.check("plunge.bonus_applied", p.last_height_bonus() > 1.0,
			"bonus %.3f after a 60 m fall" % p.last_height_bonus())
	h.check("plunge.airlock_launched", p.last_launch_count() >= 1,
			"%d launched" % p.last_launch_count())
	await h.step(t.plunge_recovery + 0.1)
	h.check("plunge.recovers", not p.is_busy(), "never left the recovery")

	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 40.0, 0.0)
	h.player.grounded = false
	# the Brood Titan's centre of mass is 45 m up, well outside a 20 m ground blast; the dummy is
	# built short so the impact can actually reach it (the boss rules are what is under test here)
	var boss := h.add_boss(Vector3(0.0, 0.0, -6.0), 20.0)
	boss.invincible = true
	await h.step(0.05)
	h.system.try_plunge()
	await h.wait_until(func() -> bool: return boss.damage_taken > 0.0, 4.0)
	h.check("plunge.boss_not_launched", p.last_launch_count() == 0,
			"%d bosses launched" % p.last_launch_count())
	h.check("plunge.boss_still_damaged", boss.damage_taken > 0.0, "the boss took nothing")


# --- Zenith Overdrive ----------------------------------------------------------------------------

## The ultimate is gated on a full OD meter, not on a cooldown.
static func _od_gate(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	await h.step(0.05)
	h.player.overdrive = 40.0
	h.check("od.refused_below_100", not h.system.try_overdrive(), "fired at 40 %")
	h.check("od.not_active", not h.system.is_overdrive_active(), "went active anyway")
	h.player.overdrive = h.system.tuning.od_required
	h.check("od.fires_at_100", h.system.try_overdrive(), "refused at a full meter")
	h.check("od.active", h.system.is_overdrive_active(), "never went active")
	h.check("od.model_told", h.player.rig_model.overdrive_on, "HeroModel.set_overdrive(true) not called")
	h.near("od.duration", h.system.overdrive_left(), h.system.tuning.od_duration, 0.1)
	h.check("od.second_press_refused", not h.system.try_overdrive(), "stacked a second Overdrive")


## +25 % damage, +30 % impact, and every cooldown reset then ticking 2.5x faster.
static func _od_buffs(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var t := h.system.tuning
	# Baseline cooldown rate, measured OUTSIDE the Overdrive. Rates, not totals: the ignition's 0.3x
	# slow-mo scales the physics delta, so every window is normalised by the game time the rig
	# actually accumulated rather than by the number of frames.
	h.system.try_burst()
	h.check("od.pre_reset_cooling", h.system.slot(&"burst").left > 0.0, "burst was never used")
	var base_left0 := h.system.slot(&"burst").left
	var base_t0 := h.player.game_time
	await h.step(0.2)
	h.near("od.cooldown_rate_normal",
			(base_left0 - h.system.slot(&"burst").left) / maxf(h.player.game_time - base_t0, 0.0001),
			1.0, 0.1)

	h.system.burst.reset()   # its state machine is not the slot's; the ignition needs it idle
	h.player.locked_for = 0.0
	h.player.overdrive = t.od_required
	h.system.try_overdrive()
	await h.step(0.02)
	h.check("od.cooldowns_reset", h.system.slot(&"burst").ready(), "burst did not come back")
	h.near("od.damage_multiplier", h.system.ctx.damage_mult, t.od_damage, 0.001)
	h.near("od.impact_multiplier", h.system.ctx.impact_mult, t.od_impact, 0.001)
	h.check("od.hud_reports_active", bool(h.system.hud_state()["overdrive_active"]),
			"hud_state says inactive")
	# the 0.45 s ignition roots the mech AND runs at 0.3x time (Feel.slow_mo), so nothing else may
	# fire until it is over and the lance is not offered before then
	h.check("od.lance_locked_during_ignition", not bool(h.system.hud_state()["lance_ready"]),
			"the lance was offered during the ignition")
	h.check("od.rooted_during_ignition", not h.system.try_burst(),
			"a skill fired while the ignition had the mech rooted")
	h.check("od.ignition_ends",
			await h.wait_until(func() -> bool: return h.system.zenith.can_fire_lance(), 4.0),
			"the ignition never finished")
	h.check("od.lance_ready_flag", bool(h.system.hud_state()["lance_ready"]),
			"lance_ready is false after the ignition")
	h.system.try_burst()
	var od_left0 := h.system.slot(&"burst").left
	var od_t0 := h.player.game_time
	await h.step(0.2)
	h.near("od.cooldown_rate_overdrive",
			(od_left0 - h.system.slot(&"burst").left) / maxf(h.player.game_time - od_t0, 0.0001),
			t.od_cd_tick, 0.25)


## Afterimages are a motion read: the gate is shut at rest (five ghosts on one pose turned the mech
## into a flat gold blob) and opens as soon as the mech is moving at 12 m/s or faster.
static func _od_ghosts(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var gate := h.system.tuning.od_afterimage_speed
	h.player.velocity = Vector3.ZERO
	h.check("od.ghosts_off_at_rest", not h.system.zenith.ghosts_allowed(),
			"ghosts were allowed while standing still")
	h.player.velocity = Vector3(0.0, 0.0, -(gate - 1.0))
	h.check("od.ghosts_off_below_gate", not h.system.zenith.ghosts_allowed(),
			"ghosts were allowed at %.1f m/s" % (gate - 1.0))
	h.player.velocity = Vector3(0.0, 0.0, -gate)
	h.check("od.ghosts_on_at_gate", h.system.zenith.ghosts_allowed(),
			"ghosts were refused at %.1f m/s" % gate)
	# a pure vertical fall is not planar motion: the ghosts must not stack during a hover
	h.player.velocity = Vector3(0.0, -60.0, 0.0)
	h.check("od.ghosts_off_vertical", not h.system.zenith.ghosts_allowed(),
			"ghosts were allowed on a vertical fall")
	h.player.velocity = Vector3.ZERO


## FEEL.md asks for "0.15 continuous" shake through the beam. Asking for 0.15 on every 120 Hz tick
## pinned the camera's additive trauma at its 1.0 clamp for the whole 3 s beam and its tail (audit #3);
## re-deriving camera_shake.gd's decay constant to top the floor up was the interim fix. The beam now
## states the floor itself through `Feel.shake_floor`, so the only additive trauma the lance injects is
## the one-shot at beam open.
static func _lance_shake(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	h.player.global_basis = Basis.IDENTITY
	var t := h.system.tuning
	# a GDScript lambda captures locals BY VALUE, so every tally lives in one Dictionary the callbacks
	# mutate — the previous version's `trauma += amount` never reached the assertion.
	var acc := {"trauma": 0.0, "biggest": 0.0, "floors": 0, "floor_trauma": 0.0, "floor_seconds": 0.0}
	var on_shake := func(amount: float, _origin: Vector3) -> void:
		acc["trauma"] = float(acc["trauma"]) + amount
		acc["biggest"] = maxf(float(acc["biggest"]), amount)
	var on_floor := func(amount: float, seconds: float) -> void:
		acc["floors"] = int(acc["floors"]) + 1
		acc["floor_trauma"] = maxf(float(acc["floor_trauma"]), amount)
		acc["floor_seconds"] = maxf(float(acc["floor_seconds"]), seconds)
	Feel.shake_requested.connect(on_shake)
	Feel.shake_floor_requested.connect(on_floor)
	h.player.overdrive = t.od_required
	h.system.try_overdrive()
	h.aim.point = Vector3(0.0, 3.0, -300.0)
	await h.wait_until(func() -> bool: return h.system.zenith.can_fire_lance(), 4.0)
	h.system.zenith.begin_lance()
	await h.wait_until(func() -> bool: return not h.system.zenith.lance.is_running(), 16.0)
	Feel.shake_requested.disconnect(on_shake)
	Feel.shake_floor_requested.disconnect(on_floor)
	# the additive impulse is the one-shot at beam open and nothing else
	var trauma := float(acc["trauma"])
	h.check("lance.shake_additive_is_the_opening_shot_only", trauma <= ZenithLance.SHAKE_TRAUMA * 1.01,
			"%.2f additive trauma over the beam, the opening shot is %.2f"
			% [trauma, ZenithLance.SHAKE_TRAUMA])
	h.check("lance.shake_is_per_tick_small", float(acc["biggest"]) <= 0.16,
			"a single request asked for %.3f trauma" % float(acc["biggest"]))
	h.check("lance.shake_floor_held_through_the_beam", int(acc["floors"]) > 100,
			"only %d floor requests over a %0.1f s beam" % [int(acc["floors"]), t.lance_beam])
	h.near("lance.shake_floor_value", float(acc["floor_trauma"]), ZenithLance.SHAKE_TRAUMA, 0.001)
	h.check("lance.shake_floor_has_a_duration", float(acc["floor_seconds"]) > 0.0,
			"a floor request with %.3f s would expire between ticks" % float(acc["floor_seconds"]))


## 0.8 s of charge, then a 3 s beam ticking 10 times a second at 450 damage.
static func _lance(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	h.player.global_basis = Basis.IDENTITY
	var t := h.system.tuning
	var in_beam := h.add_target(Vector3(0.0, 0.0, -200.0))
	var off_beam := h.add_target(Vector3(120.0, 0.0, -200.0))
	await h.step(0.05)
	h.player.overdrive = t.od_required
	h.system.try_overdrive()
	h.aim.point = Vector3(0.0, 3.0, -300.0)   # level with the target's centre of mass
	await h.wait_until(func() -> bool: return h.system.zenith.can_fire_lance(), 4.0)
	h.check("lance.starts", h.system.zenith.begin_lance(), "begin_lance refused")
	h.check("lance.charging", h.system.zenith.is_charging(), "not charging")
	await h.step(t.lance_charge * 0.4)
	h.near("lance.no_damage_while_charging", in_beam.damage_taken, 0.0, 0.01)
	h.check("lance.firing",
			await h.wait_until(func() -> bool: return h.system.zenith.is_firing(), 6.0),
			"the beam never started")
	# the 0.8 s charge runs at 0.3x time, so the whole sequence is far longer in frames than in
	# game seconds
	await h.wait_until(func() -> bool: return not h.system.zenith.lance.is_running(), 14.0)
	var want_ticks := int(t.lance_rate * t.lance_beam)
	var got_ticks := h.system.zenith.lance.ticks_fired()
	h.check("lance.tick_count", absi(got_ticks - want_ticks) <= 2,
			"%d ticks, wanted about %d" % [got_ticks, want_ticks])
	h.near("lance.damage_per_tick", in_beam.damage_taken / float(maxi(got_ticks, 1)),
			t.lance_damage * t.od_damage, 5.0)
	h.near("lance.off_beam_untouched", off_beam.damage_taken, 0.0, 0.01)
	h.check("lance.ends_overdrive", not h.system.is_overdrive_active(),
			"the Overdrive outlived the lance")
	h.check("lance.aftermath", h.system.is_aftermath(), "no 3 s aftermath")
	h.check("lance.dashes_blocked", h.system.dashes_blocked(), "dashes are free in the aftermath")
	h.check("lance.model_reset", not h.player.rig_model.overdrive_on,
			"set_overdrive(false) never called")
