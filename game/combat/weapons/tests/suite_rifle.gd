class_name RifleSuite
extends RefCounted
## P1 Pierce-Light rifle checks: rate cap, range falloff at 100/300/500 m and past the 500 m cut-off,
## charge stage timings and their round + EN costs, pierce counts and the stage-2 blast.

static func run(h: WeaponTestHarness) -> void:
	await _curve(h)
	await _rate(h)
	await _falloff(h)
	await _charge(h)
	await _pierce(h)
	await _dry(h)


## An empty cell must never swallow the trigger (look review item 1): pressing reloads, and a cell
## left empty reloads itself 0.25 s later. Before the fix both paths did nothing at all.
static func _dry(h: WeaponTestHarness) -> void:
	var r := _fresh(h)
	h.clear_targets()
	h.add_target(Vector3(0.0, 11.5, -100.0))
	h.aim_at(Vector3(0.0, 11.5, -100.0))
	r.ammo = 0
	var s0 := r.shots_fired
	await h.tap(&"fire", 0.05)
	h.check("rifle.dry_trigger_starts_reload", r.reloading, "reloading %s" % r.reloading)
	h.check("rifle.dry_trigger_fires_nothing", r.shots_fired == s0, "shots %d" % (r.shots_fired - s0))
	await h.step(r.tuning.reload_time + 0.1)
	h.check("rifle.dry_reload_refills", r.ammo == r.tuning.magazine and not r.reloading,
			"ammo %d reloading %s" % [r.ammo, r.reloading])
	# Left alone: the last round leaves, 0.25 s pass, the cell reloads without any key press.
	r.ammo = 1
	await h.tap(&"fire", 0.02)
	h.check("rifle.last_round_empties", r.ammo == 0, "ammo %d" % r.ammo)
	await h.step(r.tuning.auto_reload_delay * 0.5)
	h.check("rifle.auto_reload_waits", not r.reloading,
			"reloaded after %.2f s" % (r.tuning.auto_reload_delay * 0.5))
	await h.step(r.tuning.auto_reload_delay + 0.05)
	h.check("rifle.auto_reload_kicks_in", r.reloading, "still dry after the delay")
	await h.step(r.tuning.reload_time + 0.1)
	h.check("rifle.auto_reload_refills", r.ammo == r.tuning.magazine, "ammo %d" % r.ammo)


static func _fresh(h: WeaponTestHarness) -> PierceLightRifle:
	var r := h.system.rifle
	r.reset_state()
	h.player.energy = h.player.energy_max
	h.player.energy_spent = 0.0
	return r


static func _curve(h: WeaponTestHarness) -> void:
	var t := h.system.rifle.tuning
	h.near("rifle.curve.full_200", t.damage_at(200.0), 1.0, 0.0001)
	h.near("rifle.curve.mid_275", t.damage_at(275.0), 0.8, 0.0001)
	h.near("rifle.curve.knee_350", t.damage_at(350.0), 0.6, 0.0001)
	h.near("rifle.curve.cutoff_500", t.damage_at(500.0), 0.0, 0.0001)


static func _rate(h: WeaponTestHarness) -> void:
	var r := _fresh(h)
	h.clear_targets()
	var t := h.add_target(Vector3(0.0, 11.5, -100.0))
	h.aim_at(Vector3(0.0, 11.5, -100.0))
	var s0 := r.shots_fired
	await h.tap(&"fire", 0.05)
	h.check("rifle.tap_fires_one", r.shots_fired - s0 == 1, "shots %d" % (r.shots_fired - s0))
	h.check("rifle.tap_costs_one_round", r.ammo == r.tuning.magazine - 1, "ammo %d" % r.ammo)
	h.check("rifle.hit_registers_mark", t.status.marks == 1, "marks %d" % t.status.marks)
	var s1 := r.shots_fired
	await h.tap(&"fire", 0.02)
	await h.tap(&"fire", 0.02)
	h.check("rifle.rate_capped_at_240rpm", r.shots_fired - s1 == 0,
			"shots %d inside the 0.25 s cap" % (r.shots_fired - s1))
	await h.step(0.3)
	await h.tap(&"fire", 0.02)
	h.check("rifle.fires_after_cap", r.shots_fired - s1 == 1, "shots %d" % (r.shots_fired - s1))


static func _falloff(h: WeaponTestHarness) -> void:
	var r := _fresh(h)
	for spec: Array in [[100.0, 230.0, 1.0], [300.0, 0.0, 0.0], [500.0, 138.0, 1.0]]:
		var dist: float = spec[0]
		h.clear_targets()
		var t := h.add_target(Vector3(0.0, 11.5, -dist))
		h.aim_at(Vector3(0.0, 11.5, -dist))
		r.reset_state()
		await h.tap(&"fire", 0.05)
		if dist == 300.0:
			# the muzzle sits 12 m ahead of the chest, so this is a ~282 m hit: inside the
			# falloff, above the 60 % floor
			h.check("rifle.damage_300m_falloff", t.damage_taken > 160.0 and t.damage_taken < 190.0,
					"got %.1f, expected ~0.78x230" % t.damage_taken)
		else:
			h.near("rifle.damage_%dm" % int(dist), t.damage_taken, spec[1], spec[2])
	h.clear_targets()
	var far := h.add_target(Vector3(0.0, 11.5, -560.0))
	h.aim_at(Vector3(0.0, 11.5, -560.0))
	r.reset_state()
	await h.tap(&"fire", 0.05)
	h.check("rifle.cutoff_560m_misses", far.hits == 0, "hits %d past the 500 m cut-off" % far.hits)


static func _charge(h: WeaponTestHarness) -> void:
	var r := _fresh(h)
	h.clear_targets()
	var t := h.add_target(Vector3(0.0, 11.5, -100.0))
	h.aim_at(Vector3(0.0, 11.5, -100.0))
	h.press(&"fire")
	await h.step(0.65)
	h.release(&"fire")
	await h.step(0.05)
	h.near("rifle.stage1_damage", t.damage_taken, 700.0, 1.0)
	h.check("rifle.stage1_rounds", r.ammo == r.tuning.magazine - 3, "ammo %d" % r.ammo)
	h.near("rifle.stage1_en", h.player.energy_spent, 120.0, 0.01)
	t.reset()
	r.reset_state()
	h.player.energy_spent = 0.0
	h.check("rifle.stage1_no_detonation", t.primes == 0, "primes %d" % t.primes)
	t.status.prime(4.0)          # COLLAPSE only fires on a primed target (CONTRACTS §4)
	h.press(&"fire")
	await h.step(1.25)
	h.release(&"fire")
	await h.step(0.05)
	h.near("rifle.stage2_damage", t.damage_taken, 1400.0, 1.0)
	h.check("rifle.stage2_rounds", r.ammo == r.tuning.magazine - 5, "ammo %d" % r.ammo)
	h.near("rifle.stage2_en", h.player.energy_spent, 200.0, 0.01)
	h.check("rifle.stage2_detonates_prime", t.primes == 1, "primes %d" % t.primes)
	h.check("rifle.stage2_hit_marker_kill_or_normal", h.system.hud_state().has("last_hit_kind"),
			"no last_hit_kind in hud_state")
	h.check("rifle.stage2_hit_marker_time", int(h.system.hud_state()["last_hit_usec"]) > 0,
			"last_hit_usec %d" % int(h.system.hud_state()["last_hit_usec"]))
	t.reset()
	r.reset_state()
	var s0 := r.shots_fired
	h.press(&"fire")
	await h.step(3.05)
	h.release(&"fire")
	await h.step(0.05)
	h.check("rifle.auto_fires_at_3s", r.shots_fired - s0 == 1, "shots %d" % (r.shots_fired - s0))
	h.near("rifle.auto_fire_is_stage2", t.damage_taken, 1400.0, 1.0)


static func _pierce(h: WeaponTestHarness) -> void:
	var r := _fresh(h)
	h.clear_targets()
	var near_t := h.add_target(Vector3(0.0, 11.5, -100.0))
	var mid_t := h.add_target(Vector3(0.0, 11.5, -200.0))
	var far_t := h.add_target(Vector3(0.0, 11.5, -300.0))
	h.aim_at(Vector3(0.0, 11.5, -300.0))
	await h.tap(&"fire", 0.05)
	h.check("rifle.normal_stops_at_first", near_t.hits == 1 and mid_t.hits == 0 and far_t.hits == 0,
			"hits %d/%d/%d" % [near_t.hits, mid_t.hits, far_t.hits])
	for t: DummyTarget in [near_t, mid_t, far_t]:
		t.reset()
	r.reset_state()
	h.press(&"fire")
	await h.step(0.65)
	h.release(&"fire")
	await h.step(0.05)
	h.check("rifle.stage1_pierces_one", near_t.hits == 1 and mid_t.hits == 1 and far_t.hits == 0,
			"hits %d/%d/%d" % [near_t.hits, mid_t.hits, far_t.hits])
	for t: DummyTarget in [near_t, mid_t, far_t]:
		t.reset()
	r.reset_state()
	h.player.energy = h.player.energy_max
	h.press(&"fire")
	await h.step(1.25)
	h.release(&"fire")
	await h.step(0.05)
	h.check("rifle.stage2_pierces_all",
			near_t.hits == 1 and mid_t.hits == 1 and far_t.hits >= 1,
			"hits %d/%d/%d" % [near_t.hits, mid_t.hits, far_t.hits])
	h.clear_targets()
	var main := h.add_target(Vector3(0.0, 11.5, -100.0), 6.0)
	var splash := h.add_target(Vector3(6.0, 11.5, -100.0), 4.0)   # clear of the beam, inside the blast
	h.aim_at(Vector3(0.0, 11.5, -100.0))
	r.reset_state()
	h.player.energy = h.player.energy_max
	h.press(&"fire")
	await h.step(1.25)
	h.release(&"fire")
	await h.step(0.05)
	h.check("rifle.stage2_blast_splashes", splash.hits == 1, "splash hits %d" % splash.hits)
	h.check("rifle.stage2_blast_falloff", splash.damage_taken > 0.0
			and splash.damage_taken < main.damage_taken,
			"splash %.0f vs direct %.0f" % [splash.damage_taken, main.damage_taken])
