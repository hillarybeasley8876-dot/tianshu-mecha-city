class_name SkillDeathSuite
extends RefCounted
## The skills half of a death (r5): `SkillSystem.on_player_died()` owns the WHOLE teardown, so the
## mech calls one hook and never reaches into our state. mech-move's death gate used to close the
## Overdrive itself, next to the hook — this suite pins the hook doing it alone, and pins that the
## 3 s aftermath (halved EN regen, no dash) does NOT come back with the revive: it is the price of
## spending an Overdrive, not something a corpse passes on to its next life.

const HOME := Vector3(0.0, 8.0, 0.0)
## Where in the 12 s window the killing blow lands — mech-move's `test_death` uses the same moment.
const INTO_OD := 1.25


static func run(h: SkillTestHarness) -> void:
	await _death_ends_the_overdrive(h)


## Die 1.25 s into a running Overdrive with `on_player_died()` as the ONLY call: the window closes
## through its own path (meter 0, exactly one `overdrive_changed(false)`, the model told), the
## aftermath does not start, nothing else moves, and V cannot buy a second one while dead.
static func _death_ends_the_overdrive(h: SkillTestHarness) -> void:
	h.watch_overdrive()
	h.watch_skill_used()
	await _ignite(h)
	var t0 := h.player.game_time
	await h.wait_until(func() -> bool: return h.player.game_time - t0 >= INTO_OD, 6.0)
	h.check("death.overdrive_was_running", h.system.is_overdrive_active()
			and h.player.overdrive > 0.0 and h.player.rig_model.overdrive_on,
			"the mech is not in Overdrive %.2f s in: %s" % [INTO_OD, _od_state(h)])
	h.check("death.meter_was_full", h.player.overdrive >= h.system.tuning.od_required,
			"the meter read %.1f while the window was open" % h.player.overdrive)
	var on0 := h.od_on
	var off0 := h.od_off
	var used0 := h.used_count(&"overdrive")
	var en0 := h.player.energy
	var cds := _carry(h)

	h.player.hp = 0.0
	h.system.on_player_died()  # the ONLY death call: no gate, no end_overdrive(), no reset()

	h.check("death.overdrive_closed", not h.system.is_overdrive_active()
			and not bool(h.system.hud_state()["overdrive_active"]), _od_state(h))
	h.check("death.meter_is_zero", is_zero_approx(h.player.overdrive),
			"the meter reads %.1f on the corpse" % h.player.overdrive)
	h.check("death.one_overdrive_changed_false", h.od_off - off0 == 1 and h.od_on == on0,
			"%d false / %d true since the death" % [h.od_off - off0, h.od_on - on0])
	h.check("death.model_told", not h.player.rig_model.overdrive_on,
			"the model still reads as in Overdrive")
	h.check("death.no_aftermath", not h.system.is_aftermath()
			and is_zero_approx(float(h.system.hud_state()["aftermath"])),
			"the corpse carries a %.2f s aftermath" % float(h.system.hud_state()["aftermath"]))
	h.check("death.charges_and_cooldowns_untouched", _carry(h) == cds,
			"the death moved a charge or a cooldown: %s -> %s" % [cds, _carry(h)])
	h.near("death.no_energy_spent", h.player.energy, en0, 0.01)

	# the gate AND SkillInput both call the hook, so a second call must change nothing
	h.system.on_player_died()
	h.check("death.hook_is_idempotent", h.od_off - off0 == 1 and not h.system.is_aftermath(),
			"a second on_player_died() gave %d more events" % (h.od_off - off0 - 1))

	# V while dead cannot buy a second Overdrive even with a full meter
	h.player.overdrive = h.system.tuning.od_required
	h.press(&"overdrive")
	await h.step(0.45)
	h.release(&"overdrive")
	await h.step(0.1)
	h.check("death.v_while_dead_does_not_ignite", not h.system.is_overdrive_active()
			and h.od_on == on0 and h.used_count(&"overdrive") == used0,
			"%s, %d events, %d activations" % [_od_state(h), h.od_on - on0,
			h.used_count(&"overdrive") - used0])

	# the revive: alive again, still no aftermath — and no EN drain coming out of one
	h.player.hp = h.player.hp_max
	h.player.overdrive = 0.0
	h.player.overdrive_active = false
	await h.step(0.05)
	var en1 := h.player.energy
	await h.step(0.5)
	h.check("death.revive_carries_no_aftermath", not h.system.is_aftermath()
			and not h.system.dashes_blocked() and h.od_off - off0 == 1,
			"%s, dashes_blocked=%s, %d events" % [_od_state(h), h.system.dashes_blocked(),
			h.od_off - off0])
	h.near("death.revive_drains_no_energy", h.player.energy, en1, 0.01)
	h.check("death.mech_is_back", h.player.is_alive() and not h.system.is_overdrive_active(),
			"the rig did not come back clean")
	h.player.hp = h.player.hp_max


## Fill the meter and ignite, leaving the window open with the Lance available.
static func _ignite(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = HOME
	h.player.velocity = Vector3.ZERO
	h.player.global_basis = Basis.IDENTITY
	h.aim.point = Vector3(0.0, 8.0, -300.0)
	h.player.hp = h.player.hp_max
	h.release(&"overdrive")
	await h.step(0.4)  # let the rig land before the meter is spent
	h.player.overdrive = h.system.tuning.od_required
	h.system.try_overdrive()
	await h.wait_until(func() -> bool: return h.system.zenith.can_fire_lance(), 6.0)


## The carry-over numbers a death may not touch: every charge and every cooldown.
static func _carry(h: SkillTestHarness) -> String:
	var hud := h.system.hud_state()
	var parts: PackedStringArray = PackedStringArray()
	for id: String in ["rift_step", "anchor", "fins", "ward", "burst", "well", "plunge"]:
		parts.append("%s=%d/%.2f" % [id, int(hud.get(id + "_charges", 0)),
				float(hud.get(id + "_cd", 0.0))])
	return " ".join(parts)


static func _od_state(h: SkillTestHarness) -> String:
	var hud := h.system.hud_state()
	return "active=%s od=%.1f aftermath=%.2f" % [hud["overdrive_active"],
			h.player.overdrive, float(hud["aftermath"])]
