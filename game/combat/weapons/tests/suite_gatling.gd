class_name GatlingSuite
extends RefCounted
## P2 Thunder Spindle checks: spin-up and 15 rounds/s, per-shot heat and the cooling curve, bullet
## damage with range falloff, the overheat round count, and the three active-vent windows.
##
## The first overheat is reached by really firing ~118 rounds; the later vent variants start from
## `heat = 99.2` (one round short) so the test does not spend 8 s of simulation per window.

static func run(h: WeaponTestHarness) -> void:
	h.system.switch_weapon(1)
	await h.step(0.4)
	h.check("gatling.is_selected", h.system.current_weapon() == &"gatling",
			"weapon %s" % h.system.current_weapon())
	await _rate_and_heat(h)
	await _falloff(h)
	await _overheat_and_vent(h)


static func _burst(h: WeaponTestHarness, seconds: float) -> int:
	var g := h.system.gatling
	var n0 := g.rounds_fired
	await h.hold(&"fire", seconds)
	return g.rounds_fired - n0


static func _rate_and_heat(h: WeaponTestHarness) -> void:
	var g := h.system.gatling
	g.reset_state()
	h.clear_targets()
	h.add_target(Vector3(0.0, 11.5, -100.0), 24.0)
	h.aim_at(Vector3(0.0, 11.5, -100.0))
	var tracers0 := h.system.bullets.tracers
	var n := await _burst(h, 1.4)
	h.check("gatling.spinup_then_15rps", n >= 14 and n <= 17,
			"%d rounds in 1.4 s (0.3 s spin-up then 15/s)" % n)
	h.near("gatling.heat_per_shot", g.heat, 0.85 * float(n), 1.0)
	var tracers := h.system.bullets.tracers - tracers0
	h.check("gatling.tracer_every_third", tracers == int(n / 3.0),
			"%d tracers for %d rounds" % [tracers, n])
	h.check("gatling.ejects_casings", h.system.casings.ejected >= n,
			"%d casings for %d rounds" % [h.system.casings.ejected, n])
	var heat0 := g.heat
	await h.step(0.3)
	h.check("gatling.cool_delay_holds", absf(g.heat - heat0) < 1.0, "heat %.2f" % g.heat)
	var heat1 := g.heat
	await h.step(0.3)
	h.near("gatling.cools_30_per_s", heat1 - g.heat, 30.0 * 0.3, 1.0)


static func _falloff(h: WeaponTestHarness) -> void:
	var g := h.system.gatling
	for spec: Array in [[100.0, 52.0], [300.0, 26.0], [500.0, 0.0]]:
		var dist: float = spec[0]
		g.reset_state()
		h.clear_targets()
		var t := h.add_target(Vector3(0.0, 11.5, -dist), 24.0)
		h.aim_at(Vector3(0.0, 11.5, -dist))
		await _burst(h, 0.55)
		await h.step(0.7)
		if spec[1] == 0.0:
			h.check("gatling.cutoff_500m", t.hits == 0, "%d hits past the 350 m cut-off" % t.hits)
			continue
		var per := t.damage_taken / maxf(float(t.hits), 1.0)
		h.near("gatling.damage_%dm_per_bullet" % int(dist), per, spec[1], 1.5)


static func _overheat_and_vent(h: WeaponTestHarness) -> void:
	var g := h.system.gatling
	g.reset_state()
	h.clear_targets()
	h.add_target(Vector3(0.0, 11.5, -100.0), 24.0)
	h.aim_at(Vector3(0.0, 11.5, -100.0))
	h.press(&"fire")
	var guard := 0
	while g.state == ThunderSpindleGatling.State.READY and guard < 1400:
		await h.step(0.05)
		guard += 6
	h.release(&"fire")
	h.check("gatling.overheats_after_~118_rounds", g.overheated(),
			"state %d after %d rounds" % [g.state, g.rounds_fired])
	h.check("gatling.overheat_round_count", g.rounds_fired >= 117 and g.rounds_fired <= 119,
			"%d rounds" % g.rounds_fired)
	await _vent_perfect(h)
	await _vent_good(h)
	await _vent_miss(h)


## Wind the heat gauge up to one round short of the vent, then trip it and let go at once, so the
## needle starts from a known position.
static func _trip_vent(h: WeaponTestHarness) -> void:
	var g := h.system.gatling
	g.reset_state()
	g.heat = 99.2
	h.press(&"fire")
	var guard := 0
	while not g.overheated() and guard < 120:
		await h.step(1.0 / 120.0)
		guard += 1
	h.release(&"fire")


## Wait until the needle reaches `target` seconds into its sweep (from wherever it is now).
static func _vent_wait(h: WeaponTestHarness, target: float) -> void:
	var g := h.system.gatling
	var current := g.needle() * g.tuning.vent_sweep
	if target > current:
		await h.step(target - current)


static func _vent_perfect(h: WeaponTestHarness) -> void:
	var g := h.system.gatling
	await _trip_vent(h)
	if not g.overheated():
		h.check("gatling.vent_perfect_setup", false, "did not overheat")
		return
	var wait := g.tuning.vent_mark * g.tuning.vent_sweep + 0.02   ## marker ±50 ms is the window
	await _vent_wait(h, wait)
	await h.tap(&"fire", 0.02)
	h.near("gatling.vent_perfect_clears_heat", g.heat, 0.0, 0.001)
	h.check("gatling.vent_perfect_superheats", g.superheated_left > 3.5,
			"superheated %.2f s left" % g.superheated_left)
	h.clear_targets()
	var t := h.add_target(Vector3(0.0, 11.5, -100.0), 24.0)
	h.aim_at(Vector3(0.0, 11.5, -100.0))
	await _burst(h, 0.55)
	await h.step(0.5)
	var per := t.damage_taken / maxf(float(t.hits), 1.0)
	h.near("gatling.superheated_damage", per, 52.0 * 1.3, 2.0)


static func _vent_good(h: WeaponTestHarness) -> void:
	var g := h.system.gatling
	await _trip_vent(h)
	if not g.overheated():
		h.check("gatling.vent_good_setup", false, "did not overheat")
		return
	await _vent_wait(h, g.tuning.vent_mark * g.tuning.vent_sweep + 0.08)
	await h.tap(&"fire", 0.02)
	h.check("gatling.vent_good_state", g.state == ThunderSpindleGatling.State.VENT_GOOD,
			"state %d" % g.state)
	h.check("gatling.vent_good_heat_pending", g.heat > 90.0, "heat %.1f" % g.heat)
	await h.step(0.85)
	h.near("gatling.vent_good_clears_after_0.8s", g.heat, 0.0, 0.001)
	h.check("gatling.vent_good_no_superheat", g.superheated_left <= 0.0, "superheated")


static func _vent_miss(h: WeaponTestHarness) -> void:
	var g := h.system.gatling
	await _trip_vent(h)
	if not g.overheated():
		h.check("gatling.vent_miss_setup", false, "did not overheat")
		return
	await _vent_wait(h, 0.1)
	await h.tap(&"fire", 0.02)
	h.check("gatling.vent_miss_jams", g.state == ThunderSpindleGatling.State.JAM,
			"state %d" % g.state)
	await h.step(3.0)
	h.check("gatling.jam_lasts_3.2s", g.state == ThunderSpindleGatling.State.JAM,
			"unjammed early (state %d)" % g.state)
	await h.step(0.35)
	h.check("gatling.jam_clears", g.state == ThunderSpindleGatling.State.READY,
			"state %d" % g.state)
