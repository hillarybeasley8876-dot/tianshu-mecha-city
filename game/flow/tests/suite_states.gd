class_name FlowStateSuite
extends RefCounted
## The state machine end to end: tutorial → district → boss gate → boss, the objective line and its
## order, the checkpoint written at every milestone, and a death putting the player back with the
## spires they had already killed still down.

const TUTORIAL_MARK := "CONTAINER YARD"
const GATE_MARK := "ASCEND TO THE CROWN"


static func run(h: FlowTestHarness) -> void:
	await h.settle()
	_boot(h)
	await _tutorial_death(h)
	_district(h)
	await _respawn(h)
	await _fall_out(h)
	_gate(h)
	await _boss(h)


static func _boot(h: FlowTestHarness) -> void:
	var flow := h.flow
	h.eq(flow.state_name(), &"tutorial", "--spawn skips the drop and starts the tutorial")
	h.eq(flow.spires().size(), 3, "the sandbox places three hive spires (brief §5)")
	h.ok(_seen(h, TUTORIAL_MARK), "the tutorial objective was announced")
	h.ok(flow.director != null and flow.tutorial != null and flow.victory != null,
			"the flow built its director, tutorial and victory children")
	# SPEC §7.1's first checkpoint is written as the tutorial starts, not when the district opens: the
	# yard is a real fight and a death in it used to have nothing to respawn at (r5 brief item 1).
	h.ok(flow.checkpoint() != null and flow.checkpoint().id == &"start",
			"the start checkpoint exists as soon as the tutorial does")
	h.eq(flow.checkpoint().flow_state, &"tutorial", "it resumes the tutorial")


## r5 brief item 1: die in the yard, RETRY, and the run must come back as the tutorial — full HP/EN,
## i-frames, the camera snapped — and clearing A1 afterwards must still open the district.
static func _tutorial_death(h: FlowTestHarness) -> void:
	var flow := h.flow
	h.player.hp = 0.0
	h.player.energy = 0.0
	h.player.die()
	h.eq(flow.state_name(), &"game_over", "a death in the yard ends the run state")
	var snaps := h.rig.snaps
	flow.respawn()
	h.eq(flow.state_name(), &"tutorial", "RETRY in the yard resumes the tutorial, not the district")
	h.eq(h.player.hp, h.player.hp_max, "the yard respawn restores full HP")
	h.eq(h.player.energy, h.player.energy_max, "the yard respawn restores full EN")
	h.ok(h.player.is_invulnerable(), "the yard respawn grants i-frames")
	h.ok(h.rig.snaps > snaps, "the yard respawn snaps the camera to the hero")
	h.ok(flow.checkpoint().id == &"start", "the yard respawn did not lose the checkpoint")
	h.ok(_seen(h, TUTORIAL_MARK), "the yard objective is announced again")
	await h.settle(1)
	# The real path: the director marks the arena done and announces it, which opens the district.
	flow.director.force_clear(&"sandbox")
	h.eq(flow.state_name(), &"district", "clearing the yard after a death still opens the district")
	h.ok(bool(flow.director.arena_state(&"sandbox").get("done", false)),
			"the yard is recorded as finished")


static func _district(h: FlowTestHarness) -> void:
	var flow := h.flow
	var killed: Array[StringName] = []
	flow.spire_destroyed.connect(func(id: StringName, _n: int) -> void: killed.append(id))
	h.objectives.clear()
	h.ok(flow.checkpoint() != null and flow.checkpoint().id == &"start",
			"the start checkpoint is rewritten for the district")
	h.eq(flow.checkpoint().flow_state, &"district", "it now resumes the district")
	var first := h.spire(0)
	# The hive falls without its arena ever being cleared: the checkpoint records no finished arena,
	# so the "every fallen hive's arena stays quiet" half of r5 brief item 6 is the one under test.
	flow.director.reset_arena(&"sandbox")
	first.collapse()
	h.eq(killed.size(), 1, "the flow is told about every destroyed spire")
	h.eq(flow.spires_down().size(), 1, "one spire down")
	h.ok(flow.checkpoint().id == StringName("spire_" + String(first.spire_id)),
			"a destroyed spire writes its own checkpoint")
	h.ok(flow.checkpoint().arenas_done.is_empty(),
			"and it recorded no finished arena, because none was")
	h.ok(_seen(h, "1/3"), "the objective counts 1/3")
	# A spire that is still standing takes damage, then the player dies.
	h.hit(h.spire(1), &"pod_0", 1000.0)
	h.ok(h.spire(1).total_hp() < 20000.0, "the second spire is damaged before the death")


static func _respawn(h: FlowTestHarness) -> void:
	var flow := h.flow
	h.player.hp = 100.0
	h.player.energy = 0.0
	h.player.die()
	h.eq(flow.state_name(), &"game_over", "death ends the run state")
	flow.respawn()
	h.eq(flow.state_name(), &"district", "respawn returns to the checkpoint's state")
	h.eq(h.player.hp, h.player.hp_max, "respawn restores full HP")
	h.eq(h.player.energy, h.player.energy_max, "respawn restores full EN")
	h.ok(h.player.is_invulnerable(), "respawn grants i-frames")
	h.eq(flow.spires_down().size(), 1, "the spire that was down stays down")
	h.eq(h.spire(1).total_hp(), 20000.0, "a standing spire comes back whole")
	h.ok(not h.spire(0).is_alive(), "the destroyed spire is still destroyed")
	# r5 brief item 6: the arena of a hive that is down must not fight again, even though the
	# checkpoint recorded no finished arena.
	var yard := flow.director.arena_state(&"sandbox")
	h.ok(bool(yard.get("done", false)) and not bool(yard.get("active", false))
			and (yard.get("live", []) as Array).is_empty(),
			"the fallen hive's arena is done, idle and empty after the respawn")
	await h.settle(4)
	yard = flow.director.arena_state(&"sandbox")
	h.ok(bool(yard.get("done", false)) and int(yard.get("index", 0)) > 0,
			"and it stays quiet for 4 s — no wave restarted")


## r5 brief item 5: falling out of the world is a respawn, not a 3,000 m fall with nothing listening.
## The city's open U4/U5/U6 tunnel ends are how a player gets here; the teleport is the same state.
static func _fall_out(h: FlowTestHarness) -> void:
	var flow := h.flow
	h.player.hp = 4000.0
	h.player.debug_teleport([0.0, -200.0, -330.0])
	await h.settle(4)
	h.ok(h.player.global_position.y > FlowBounds.FALL_Y,
			"a mech below the world is put back inside it within a few ticks")
	h.eq(h.player.hp, h.player.hp_max, "the fall-out respawn restores full HP")
	h.eq(h.player.energy, h.player.energy_max, "the fall-out respawn restores full EN")
	h.eq(flow.state_name(), &"district", "and it resumes the checkpoint's state")
	h.ok(FlowBounds.half() > 0.0, "the playable bounds came from the city layout")
	h.eq(FlowBounds.reason(h.player), "", "the respawned hero is inside the world")
	# A hero that is merely high up, or out over the skyline but still inside the square, is fine.
	h.player.debug_teleport([0.0, 240.0, 0.0])
	h.eq(FlowBounds.reason(h.player), "", "height alone is not out of the world")
	h.player.debug_teleport([FlowBounds.half() - 10.0, 8.0, 0.0])
	h.eq(FlowBounds.reason(h.player), "", "and neither is standing near the edge")
	h.player.debug_teleport([FlowBounds.half() + 10.0, 8.0, 0.0])
	h.ok(FlowBounds.reason(h.player) != "", "but past the bounds is")


static func _gate(h: FlowTestHarness) -> void:
	var flow := h.flow
	h.objectives.clear()
	h.spire(1).collapse()
	h.spire(2).collapse()
	h.eq(flow.spires_down().size(), 3, "three spires down")
	h.eq(flow.state_name(), &"boss_gate", "the third spire opens the boss gate")
	h.ok(_seen(h, "3/3"), "the objective counted the last spire")
	h.ok(_seen(h, GATE_MARK), "the boss-gate objective was announced")
	var district_at := _index_of(h, "3/3")
	var gate_at := _index_of(h, GATE_MARK)
	h.ok(district_at >= 0 and gate_at > district_at,
			"the objectives arrived in order: 3/3 then the crown")


static func _boss(h: FlowTestHarness) -> void:
	var flow := h.flow
	# The real landing: the point the catapult's arc ends on and every boss checkpoint saves. Standing
	# on it is a real touchdown, which is what the gate now asks for (r5 brief item 2).
	var landing := h.crown_landing()
	h.player.debug_teleport([landing.x, landing.y + 8.0, landing.z])
	await h.settle(3)
	h.eq(flow.state_name(), &"boss", "a real touchdown on the deck starts the boss fight")
	h.ok(flow.checkpoint().id == &"boss_p1", "the first boss phase is a checkpoint")
	_saved_on_the_deck(h, landing, "boss_p1", flow.checkpoint().at.origin)
	h.eq(flow.progress.hint(), "", "the catapult hint is gone once the fight starts")
	h.ok(_last_objective(h).find("CATAPULT") < 0,
			"and the objective line in the fight does not carry it")
	# The next phase checkpoint must NOT follow the hero: a phase change can happen anywhere on the
	# deck, and the old code saved the live transform (r5 brief item 2).
	var elsewhere := Vector3(FlowCrownDeck.CENTRE.x + 130.0, landing.y + 8.0,
			FlowCrownDeck.CENTRE.z)
	h.player.debug_teleport([elsewhere.x, elsewhere.y, elsewhere.z])
	Events.boss_phase.emit(2)
	h.ok(flow.checkpoint().id == &"boss_p2", "a phase change writes the next boss checkpoint")
	_saved_on_the_deck(h, landing, "boss_p2", flow.checkpoint().at.origin)
	h.player.die()
	h.eq(flow.state_name(), &"game_over", "the player can still die in the boss fight")
	flow.respawn()
	h.eq(flow.state_name(), &"boss", "the boss checkpoint puts the player back in the fight")
	_saved_on_the_deck(h, landing, "the boss RETRY", h.player.global_position)
	h.eq(flow.progress.hint(), "", "the respawn does not bring the catapult hint back")
	await h.settle(1)
	_abort(h)


## The saved point must be a standing one ON the probed fighting floor: the same XZ, and exactly a
## capsule's half height above it. A point inside the deck, or wherever the hero happened to be when
## the phase changed, strands the next RETRY.
static func _saved_on_the_deck(h: FlowTestHarness, landing: Vector3, what: String,
		at: Vector3) -> void:
	var flat := Vector2(at.x - landing.x, at.z - landing.z).length()
	var lift := FlowBounds.half_height(h.player)
	h.ok(flat < 1.0 and absf(at.y - landing.y - lift) < 0.5,
			"%s stands on the probed fighting-floor point (%.1f m out, %.1f m up, want %.1f)"
			% [what, flat, at.y - landing.y, lift])


static func _last_objective(h: FlowTestHarness) -> String:
	return h.objectives[h.objectives.size() - 1] if h.objectives.size() > 0 else ""


## r5 brief item 5: PAUSE → ABORT is the way out of a run the player no longer wants. It ends at the
## title, unpaused, with nothing carried over — START from there is 0/3.
static func _abort(h: FlowTestHarness) -> void:
	var flow := h.flow
	h.root.get_tree().paused = true
	flow.abort_to_title()
	h.eq(flow.state_name(), &"title", "ABORT goes back to the title")
	h.ok(not h.root.get_tree().paused, "and it leaves the game unpaused")
	h.eq(flow.spires_down().size(), 0, "the aborted run counts no spires")
	h.ok(flow.checkpoint() == null, "and it leaves no checkpoint behind")
	for i in 3:
		h.ok(h.spire(i).is_alive(), "spire %d stands again after the abort" % i)
	h.eq(h.spire(0).total_hp(), 20000.0, "and it is whole")
	h.ok(not bool(flow.director.arena_state(&"sandbox").get("done", true)),
			"the arenas re-arm for the next run")
	h.ok(not flow.director.enabled, "and no waves start under the title")


static func _seen(h: FlowTestHarness, needle: String) -> bool:
	return _index_of(h, needle) >= 0


static func _index_of(h: FlowTestHarness, needle: String) -> int:
	for i in h.objectives.size():
		if h.objectives[i].contains(needle):
			return i
	return -1
