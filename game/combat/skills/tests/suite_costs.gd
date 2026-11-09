class_name SkillCostSuite
extends RefCounted
## Cooldowns, charges and EN costs for every skill (CONTRACTS §5 / skills-catalog §4.4-4.5): each
## activation must spend exactly its tuned EN and exactly one charge, refuse while cooling, refuse
## on an empty gauge, and come back on schedule.

static func run(h: SkillTestHarness) -> void:
	await _costs(h)
	await _cooldowns(h)
	await _charges(h)
	await _empty_gauge(h)


## EN spent per activation, read straight from the tuning table so the numbers cannot drift apart.
static func _costs(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	var t := h.system.tuning
	h.system.try_burst()
	h.near("cost.burst", h.player.energy_spent, t.burst_cost, 0.01)
	h.reset()
	h.player.energy_spent = 0.0
	h.system.try_well()
	h.near("cost.well", h.player.energy_spent, t.well_cost, 0.01)
	h.reset()
	h.player.energy_spent = 0.0
	h.system.try_fins()
	h.near("cost.fins", h.player.energy_spent, t.fins_cost, 0.01)
	h.reset()
	h.player.energy_spent = 0.0
	h.system.try_ward()
	h.near("cost.ward", h.player.energy_spent, t.ward_cost, 0.01)
	h.reset()
	h.player.energy_spent = 0.0
	h.system.try_anchor()
	h.near("cost.anchor", h.player.energy_spent, t.anchor_cost, 0.01)
	h.reset()
	h.player.energy_spent = 0.0
	h.system.try_rift_step()
	h.near("cost.rift_step", h.player.energy_spent, t.rift_cost, 0.01)


## A single-charge skill refuses a second press until its cooldown has run out, then comes back and
## announces itself on Events.skill_ready.
static func _cooldowns(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	var t := h.system.tuning
	var ready_events: Array[StringName] = []
	var on_ready := func(id: StringName) -> void: ready_events.append(id)
	Events.skill_ready.connect(on_ready)
	h.check("cd.burst_fires", h.system.try_burst(), "first press refused")
	var hud := h.system.hud_state()
	h.near("cd.burst_full", float(hud["burst_cd"]), t.burst_cd, 0.05)
	h.check("cd.burst_not_ready", not bool(hud["burst_ready"]), "ready flag still set")
	h.check("cd.burst_refuses_second", not h.system.try_burst(), "second press was allowed")
	await h.step(t.burst_cd * 0.5)
	h.check("cd.burst_still_cooling", not h.system.try_burst(), "fired at half the cooldown")
	await h.step(t.burst_cd * 0.55)
	h.check("cd.burst_ready_again", h.system.try_burst(), "still cooling after the full cd")
	h.check("cd.burst_announced", ready_events.has(&"burst"), "no skill_ready for burst")
	Events.skill_ready.disconnect(on_ready)


## The Skyhook carries two charges that refill one at a time, 5 s each (skills-catalog §4.4 S2).
static func _charges(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	var t := h.system.tuning
	h.check("charges.anchor_two", h.system.slot(&"anchor").charges_max == t.anchor_charges,
			"charges_max %d" % h.system.slot(&"anchor").charges_max)
	h.system.try_anchor()
	h.system.anchor.reset()
	h.system.try_anchor()
	h.check("charges.anchor_second_ok", h.system.slot(&"anchor").charges == 0,
			"charges %d after two shots" % h.system.slot(&"anchor").charges)
	h.check("charges.anchor_third_refused", not h.system.try_anchor(), "third shot was allowed")
	await h.step(t.anchor_recharge * 1.05)
	h.check("charges.anchor_one_back", h.system.slot(&"anchor").charges == 1,
			"charges %d after one recharge" % h.system.slot(&"anchor").charges)
	await h.step(t.anchor_recharge * 1.05)
	h.check("charges.anchor_full", h.system.slot(&"anchor").charges == t.anchor_charges,
			"charges %d after two recharges" % h.system.slot(&"anchor").charges)


## An empty gauge blocks the skill outright — and nothing is spent when it refuses.
static func _empty_gauge(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.energy = 10.0
	h.player.energy_spent = 0.0
	h.check("en.burst_refused", not h.system.try_burst(), "burst fired on 10 EN")
	h.near("en.nothing_spent", h.player.energy_spent, 0.0, 0.01)
	h.check("en.charge_kept", h.system.slot(&"burst").charges == 1, "charge was consumed anyway")
	h.player.energy = h.player.energy_max
	h.check("en.burst_after_refill", h.system.try_burst(), "burst refused on a full gauge")
