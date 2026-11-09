class_name SkillClockSuite
extends RefCounted
## CONTRACTS §3 clocks: cooldowns, charges and the OD window run on `Feel.player_delta` (full speed
## in witch time, frozen by a global hit-stop) while the hold gestures run on `Feel.real_delta`.
## Under witch time the world crawls at 0.25x, so a skill that ignored the contract would come back
## four times too late — and a 0.35 s hold would never reach its threshold.

static func run(h: SkillTestHarness) -> void:
	await _cooldown_in_witch_time(h)
	await _hold_in_witch_time(h)


## A cooldown started just before witch time must burn down at REAL speed: after half its cooldown in
## real seconds exactly half of it is left, not an eighth.
static func _cooldown_in_witch_time(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	var t := h.system.tuning
	h.check("clock.burst_fires", h.system.try_burst(), "first press refused")
	var before := float(h.system.hud_state()["burst_cd"])
	h.near("clock.burst_starts_full", before, t.burst_cd, 0.05)
	Feel.slow_mo(0.25, 0.9, 0.01, 0.05, true)
	h.check("clock.witch_active", Feel.is_witch_time(), "witch time did not engage")
	var half := t.burst_cd * 0.5
	await h.step(half)
	var left := float(h.system.hud_state()["burst_cd"])
	h.near("clock.cooldown_real_speed", left, t.burst_cd - half, 0.2)
	h.check("clock.cooldown_not_scaled", left < t.burst_cd - half * 0.6,
			"cooldown ticked at %.2f of real speed" % ((t.burst_cd - left) / half))
	await _clear_slow()


## The 0.35 s fins hold is a gesture, so it is measured on the real clock too: holding for 0.35 real
## seconds raises the Ward even though only ~0.09 s of world time passed.
static func _hold_in_witch_time(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	Feel.slow_mo(0.25, 0.9, 0.01, 0.05, true)
	h.press(&"fins")
	await h.step(h.system.tuning.ward_hold + 0.05)
	h.release(&"fins")
	h.check("clock.hold_real_speed", h.system.fins.ward.is_active(),
			"a %.2f s hold did not raise the ward under witch time" % h.system.tuning.ward_hold)
	await _clear_slow()


## Wait out the slow-mo and make sure the suite leaves the engine at normal speed.
static func _clear_slow() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		Engine.time_scale = 1.0
		return
	for i in 240:
		if not Feel.is_witch_time() and is_equal_approx(Engine.time_scale, 1.0):
			break
		await tree.physics_frame
	Engine.time_scale = 1.0
