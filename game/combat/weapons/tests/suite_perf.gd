class_name PerfSuite
extends RefCounted
## Budget check (CONTRACTS §2): 600 live projectiles + 24 missiles must cost well under 4 ms of
## physics per frame. Headless frames are uncapped, so wall-clock per physics frame IS the cost.

const BULLETS := 600
const MISSILES := 24
const FRAMES := 30          ## 0.25 s: every round is still inside the 400 m cut-off


static func run(h: WeaponTestHarness) -> void:
	h.release_all()
	h.clear_targets()
	var idle := await _measure(h, 0, 0)
	var loaded := await _measure(h, BULLETS, MISSILES)
	var cost := loaded - idle
	print("PERF idle %.3f ms/frame, loaded %.3f ms/frame, weapons cost %.3f ms/frame" \
			% [idle, loaded, cost])
	h.check("perf.600_projectiles_24_missiles_under_4ms", cost < 4.0,
			"%.3f ms/frame for %d rounds + %d missiles" % [cost, BULLETS, MISSILES])


static func _measure(h: WeaponTestHarness, bullets: int, missiles: int) -> float:
	var pm := h.system.bullets
	var mm := h.system.missiles
	pm.clear()
	mm.clear()
	var origin := h.player.global_position + Vector3(0.0, 11.5, 0.0)
	for i in bullets:
		var jitter := Vector3(randf_range(-0.02, 0.02), randf_range(-0.02, 0.02), -1.0)
		pm.fire(origin, jitter.normalized(), 52.0, 22.0, 900.0, 1.4, i % 3 == 0)
	for i in missiles:
		var side := float(i - MISSILES / 2) * 6.0
		mm.launch(origin + Vector3(side, 0.0, 0.0), Vector3(side * 0.01, 0.2, -1.0).normalized(),
				null, origin + Vector3(side, 0.0, -2000.0))
	await h.step(1.0 / 120.0)
	h.check("perf.load_is_live", bullets == 0 or pm.active_count() >= bullets - 4,
			"%d rounds in flight" % pm.active_count())
	h.check("perf.missiles_are_live", missiles == 0 or mm.active_count() == missiles,
			"%d missiles in flight" % mm.active_count())
	var t0 := Time.get_ticks_usec()
	for f in FRAMES:
		await h.tree.physics_frame
	var ms := float(Time.get_ticks_usec() - t0) / float(FRAMES) / 1000.0
	pm.clear()
	mm.clear()
	await h.step(1.0 / 120.0)
	return ms
