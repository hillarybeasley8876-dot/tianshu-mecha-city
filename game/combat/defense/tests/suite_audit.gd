class_name DefenseAuditSuite
extends RefCounted
## Regressions for the numeric-robustness audit (reviews/melee-defense-audit.md). Each block is the
## exact trigger from a finding and fails on the pre-audit code:
##   2. the catch field's 3 s hold limit counted from the OPEN, so a round caught after a long empty
##      stretch was thrown back on the tick it arrived;
##   3. clear() turned physics back on without restoring the velocity _freeze() zeroed, so rounds let
##      go by a guard break hung in mid-air;
##   4. _guard() caught again in the very tick _drain() broke the guard, re-freezing what clear() had
##      just released, with nothing left to ever release it;
##   5. the parry-recoil SceneTreeTimer ran with process_always = true, so a pause spent the 0.6 s.


static func run(h: DefenseTestHarness) -> void:
	await _hold_limit_counts_from_the_first_catch(h)
	await _break_hands_velocity_back(h)
	await _break_does_not_recapture(h)
	await _recoil_survives_a_pause(h)


## [finding 2] Hold through an empty field for longer than CATCH_MAX_TIME, THEN catch: the round must
## freeze and orbit, not bounce back instantly. Pre-audit `catch_field.tick` grew `_held` from the
## moment the field opened, so `held_time() >= 3.0` was already true on the first catch.
static func _hold_limit_counts_from_the_first_catch(h: DefenseTestHarness) -> void:
	h.fresh()
	await h.step(0.05)
	h.press(&"guard")
	await h.step(DefenseTable.CATCH_HOLD + DefenseTable.CATCH_MAX_TIME + 0.4)
	h.eq("holdcap.field_is_empty_first", h.system.catch_count(), 0)
	var shot := h.add_shot(9.0, 200.0)
	await h.step(0.25)
	h.check("holdcap.late_catch_still_holds", h.system.catch_count() >= 1,
			"caught %d — the hold limit must start at the first catch" % h.system.catch_count())
	h.check("holdcap.late_catch_is_frozen", not shot.is_physics_processing())
	h.check("holdcap.late_catch_not_bounced", not shot.is_reflected(),
			"an instant reflector is not a catch field")
	await h.step(0.2)
	h.check("holdcap.late_catch_keeps_holding", h.system.catch_count() >= 1)
	h.release(&"guard")
	await h.step(0.4)


## [finding 3] EN 0 under a full field breaks the guard: every held round must fly on with the speed it
## had when it was caught, not hang at its orbit slot with physics on and no velocity.
static func _break_hands_velocity_back(h: DefenseTestHarness) -> void:
	h.fresh()
	await h.step(0.05)
	h.press(&"guard")
	await h.open_catch_field()
	var shot := h.add_shot(9.0, 200.0)
	await h.step(0.25)
	h.check("vel.round_is_caught", h.system.catch_count() >= 1)
	h.check("vel.frozen_has_no_velocity", (shot.get(&"velocity") as Vector3).length() < 0.01)
	h.player.energy = 0.0
	await h.ticks(3)
	h.eq("vel.guard_broke", h.system.hud_state()["state"], "BROKEN")
	h.check("vel.physics_back_on", shot.is_physics_processing())
	h.check("vel.speed_restored", (shot.get(&"velocity") as Vector3).length() > 1.0,
			"speed %.1f — a round let go without a throw has to fly again"
			% (shot.get(&"velocity") as Vector3).length())
	h.release(&"guard")
	await h.step(1.2)


## [finding 5] A perfect parry locks the attacker's AI for 0.6 s. Opening the pause menu inside that
## window must not spend the reward: the SceneTreeTimer is pausable (process_always = false) and ticks
## on physics frames, so it only runs while the game does.
static func _recoil_survives_a_pause(h: DefenseTestHarness) -> void:
	h.fresh()
	var attacker := h.add_attacker()
	await h.step(0.1)
	h.press(&"guard")
	await h.ticks(2)
	var hit := h.make_hit(6.0, 900.0, attacker)
	var consumed := false
	for f: Callable in h.player.filters:
		if f.is_valid():
			consumed = bool(f.call(hit)) or consumed
	h.check("recoil.parry_landed", consumed)
	h.check("recoil.ai_is_locked_out", not attacker.ai_enabled,
			"AI paused for %.1f s" % DefenseTable.PARRY_RECOIL)
	h.tree.paused = true
	await h.step(DefenseTable.PARRY_RECOIL + 0.3)
	h.check("recoil.pause_does_not_expire_the_lockout", not attacker.ai_enabled,
			"a paused tree must not tick the recoil away")
	h.tree.paused = false
	await h.step(DefenseTable.PARRY_RECOIL + 0.3)
	h.check("recoil.ai_comes_back_after_resume", attacker.ai_enabled)
	h.release(&"guard")
	await h.step(0.4)


## [finding 4] The break and the catch happen in the same tick: `_drain` -> `_break_guard` -> `clear()`
## released the orbit, then `_catch` re-froze whatever was still inside 12 m and — with the guard gone
## — nothing would ever release it. One tick after the break the field must be empty and every round
## moving.
static func _break_does_not_recapture(h: DefenseTestHarness) -> void:
	h.fresh()
	await h.step(0.05)
	h.press(&"guard")
	await h.open_catch_field()
	var shots: Array[EnemyProjectile] = []
	for i in 8:
		shots.append(h.add_shot(7.0 + float(i % 4) * 0.9))
	await h.step(0.3)
	var caught := h.system.catch_count()
	h.check("recap.rounds_are_caught", caught >= 3, "caught %d" % caught)
	h.player.energy = 0.0
	await h.ticks(2)
	h.eq("recap.field_is_empty_after_the_break", h.system.catch_count(), 0)
	var stuck := 0
	for s in shots:
		if is_instance_valid(s) and (not s.is_physics_processing()
				or (s.get(&"velocity") as Vector3).length() < 0.01):
			stuck += 1
	h.eq("recap.no_round_left_frozen", stuck, 0)
	## And the break is not a release either: nothing was thrown back at 135 %.
	var thrown := 0
	for s in shots:
		if is_instance_valid(s) and s.is_reflected():
			thrown += 1
	h.eq("recap.break_does_not_throw", thrown, 0)
	h.release(&"guard")
	await h.step(1.2)
