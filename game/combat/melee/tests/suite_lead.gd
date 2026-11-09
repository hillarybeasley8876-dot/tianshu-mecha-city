class_name MeleeLeadSuite
extends RefCounted
## Regressions for the standing lead notes (reviews/melee-defense-lead.md):
##   - the 14 m blade must only exist while melee is active — ignite on the first melee input
##     (0.12 s out of the hilt, with a flash), stow 0.6 s after the last melee action, and the
##     model's own hilt rides the hip until the blade is drawn;
##   - a LOCAL hit-stop on the player (`hit_pause`) must hold the move clock, or the saber keeps
##     sweeping while the arm creeps at 5 %;
##   - `EnemyBase.handles_own_knockback()` → MeleeStrike must not add its own shove on top.


static func run(h: MeleeTestHarness) -> void:
	await _blade_life(h)
	await _hit_stop_holds_the_swing(h)
	await _no_double_push(h)


static func _blade_life(h: MeleeTestHarness) -> void:
	h.fresh()
	h.add_dummy(10.0)
	await h.step(0.2)
	var saber: SaberVisual = h.system.saber
	var model := h.player.model_ref as MeleeRigModel
	h.check("blade.stowed_at_rest", not saber.lit)
	h.check("blade.hilt_on_the_hip_at_rest", model != null and not model.saber_drawn)
	h.near("blade.nothing_out_at_rest", saber.extend_ratio(), 0.0, 0.02)
	h.tap(&"melee", 3)
	## `Input.action_*` is accumulated, so the press lands a frame later; give the system the tick
	## after that to run `_blade_life` on the move the press started.
	await h.ticks(2)
	h.check("blade.ignites_on_the_first_input", saber.lit)
	h.check("blade.hilt_drawn_on_ignition", model != null and model.saber_drawn)
	h.check("blade.extends_rather_than_pops", saber.extend_ratio() < 1.0,
			"%.2f out two ticks after ignition" % saber.extend_ratio())
	await h.step(MeleeTable.BLADE_EXTEND + 0.1)
	h.near("blade.fully_extended", saber.extend_ratio(), 1.0, 0.02)
	await h.step(MeleeTable.BLADE_STOW + 0.4)
	h.check("blade.stows_after_the_last_melee_action", not saber.lit)
	h.near("blade.retracted_into_the_hilt", saber.extend_ratio(), 0.0, 0.02)
	h.check("blade.hilt_back_on_the_hip", model != null and not model.saber_drawn)
	h.fresh()
	await h.step(0.1)


## A landed hit puts the player in its own local hit-stop. `Feel.player_delta` still runs at full
## speed through it (it is not the global stop), so the move clock has to be held explicitly.
static func _hit_stop_holds_the_swing(h: MeleeTestHarness) -> void:
	h.fresh()
	h.add_dummy(10.0)
	await h.step(0.1)
	h.press(&"melee")
	await h.ticks(1)
	h.release(&"melee")
	h.check("stop.move_started", h.system.phase == MeleeSystem.Phase.STARTUP)
	h.player.model_ref.call(&"hit_pause", 0.3)
	await h.ticks(24)
	h.check("stop.model_reports_the_local_stop", bool(h.player.model_ref.call(&"paused")))
	h.eq("stop.startup_held_through_the_stop", h.system.phase, MeleeSystem.Phase.STARTUP)
	await h.ticks(30)
	h.check("stop.move_resumes_after_the_stop",
			h.system.phase != MeleeSystem.Phase.STARTUP,
			"phase %d" % h.system.phase)
	h.fresh()
	await h.step(0.1)


static func _no_double_push(h: MeleeTestHarness) -> void:
	h.fresh()
	var dummy := h.add_dummy(8.0)
	var hit := HitInfo.make(100.0, HitInfo.MELEE, h.player, &"melee_l1")
	hit.knockback = Vector3(0.0, 0.0, 8.0)
	dummy.velocity = Vector3.ZERO
	dummy.own_knockback = true
	h.system.strike.shove(dummy, hit)
	h.check("shove.enemy_that_handles_its_own_is_untouched", dummy.velocity.length() < 0.001,
			"moved %.2f m/s — that is the double push" % dummy.velocity.length())
	dummy.own_knockback = false
	h.system.strike.shove(dummy, hit)
	h.near("shove.applied_when_the_enemy_does_not", dummy.velocity.length(), 8.0, 0.001)
	h.fresh()
	await h.step(0.1)
