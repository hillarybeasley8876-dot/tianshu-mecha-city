class_name WeaponClockSuite
extends RefCounted
## CONTRACTS §3 clocks: the guns run on `Feel.player_delta` — full speed in witch time, frozen by a
## global hit-stop — while the rounds and missiles in the air stay on the world clock.
##
## Durations are measured with `Feel.real_now()`, the unscaled game clock, so a weapon timer left on
## raw (scaled) delta would show up as a 3.3x miss under the 0.3 slow-mo below.

const WITCH_SCALE := 0.3
const WITCH_SECONDS := 2.0


static func run(h: WeaponTestHarness) -> void:
	await _witch_rate(h)
	await _witch_charge(h)
	await _hit_stop_freezes(h)
	await _settle(h)


static func _fresh(h: WeaponTestHarness) -> PierceLightRifle:
	var r := h.system.rifle
	r.reset_state()
	h.player.energy = h.player.energy_max
	h.player.energy_spent = 0.0
	return r


static func _range(h: WeaponTestHarness) -> DummyTarget:
	h.clear_targets()
	var t := h.add_target(Vector3(0.0, 11.5, -100.0))
	h.aim_at(Vector3(0.0, 11.5, -100.0))
	return t


## Witch time: the world crawls at 0.3 but the rifle still fires its 4 shots per REAL second, so a
## charged volley is not stolen by a perfect dodge.
static func _witch_rate(h: WeaponTestHarness) -> void:
	var r := _fresh(h)
	_range(h)
	h.check("clocks.witch_time_opens", await _open_witch(h),
			"scale %.2f witch %s" % [Engine.time_scale, Feel.is_witch_time()])
	h.check("clocks.world_really_is_slow", absf(Engine.time_scale - WITCH_SCALE) < 0.02,
			"time_scale %.3f — a raw-delta fire rate would only manage 1 shot/s here" % Engine.time_scale)
	var t0 := Feel.real_now()
	var s0 := r.shots_fired
	for i in 4:
		await h.tap(&"fire")
		if i < 3:
			await h.step(0.26)   # the 0.25 s rate cap, on the player's clock
	await h.step(0.03)           # the last tap's release needs a tick to be read
	var real_s := Feel.real_now() - t0
	h.check("clocks.rifle_4_shots_per_real_second_in_witch_time", r.shots_fired - s0 == 4,
			"%d shots in %.3f real s" % [r.shots_fired - s0, real_s])
	h.check("clocks.rifle_burst_fits_one_real_second", real_s <= 1.0, "%.3f real s" % real_s)
	await _settle(h)


## A stage-2 charge still takes 1.2 s of the player's own time, however slow the world is.
static func _witch_charge(h: WeaponTestHarness) -> void:
	var r := _fresh(h)
	var t := _range(h)
	h.check("clocks.witch_time_reopens", await _open_witch(h), "scale %.2f" % Engine.time_scale)
	var t0 := Feel.real_now()
	h.press(&"fire")
	var guard := 0
	while int(h.system.hud_state()["charge_stage"]) < 2 and guard < 900:
		await h.tree.physics_frame
		guard += 1
	var real_s := Feel.real_now() - t0
	h.release(&"fire")
	await h.step(0.05)
	h.near("clocks.stage2_charge_takes_1.2_real_seconds", real_s, r.tuning.stage2_time, 0.08)
	h.near("clocks.stage2_damage_in_witch_time", t.damage_taken, r.tuning.stage2_damage, 1.0)
	await _settle(h)


## The other half of the contract: a global hit-stop freezes the charge instead of charging through
## the freeze (a real-time timer would gain a fifth of a stage here).
static func _hit_stop_freezes(h: WeaponTestHarness) -> void:
	var r := _fresh(h)
	_range(h)
	h.press(&"fire")
	await h.step(0.05)
	var started := Feel.hit_stop(0.25, 0.05)
	h.check("clocks.hit_stop_starts", started, "rate-limited away")
	var before := r.charge_ratio()
	await h.step(0.25)
	var gained := r.charge_ratio() - before
	h.release(&"fire")
	await h.step(0.05)
	h.check("clocks.hit_stop_freezes_the_charge", gained < 0.05,
			"charge grew %.3f of a stage across a 0.25 s hit-stop" % gained)
	h.check("clocks.hit_stop_releases_the_shot", r.shots_fired > 0, "no shot after the freeze")


static func _open_witch(h: WeaponTestHarness) -> bool:
	Feel.slow_mo(WITCH_SCALE, WITCH_SECONDS, 0.0, 0.0, true)
	await h.step(0.05)
	return Feel.is_witch_time()


## Hand the tree back at normal speed: the suites after this one measure seconds, not frames.
static func _settle(h: WeaponTestHarness) -> void:
	h.release_all()
	var guard := 0
	while (Feel.is_witch_time() or Engine.time_scale < 0.99) and guard < 200:
		await h.step(0.05)
		guard += 1
	h.check("clocks.time_scale_restored", absf(Engine.time_scale - 1.0) < 0.01,
			"time_scale %.3f" % Engine.time_scale)
