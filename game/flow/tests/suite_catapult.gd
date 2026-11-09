class_name FlowCatapultSuite
extends RefCounted
## The Ascension Catapult (r3): dark until the boss gate opens it, a hero standing on the lit pad is
## thrown up the arc and handed back with the exit velocity over the Crown deck.

const PAD := Vector3(0.0, 10.0, 60.0)
const LANDING := Vector3(0.0, 90.0, -40.0)


static func run(h: FlowTestHarness) -> void:
	var catapult := FlowAscensionCatapult.new()
	catapult.name = "TestCatapult"
	h.root.add_child(catapult)
	catapult.place(PAD, LANDING)
	await h.settle(2)
	h.ok(not catapult.armed, "the pad is dark until the boss gate opens it")
	h.eq(catapult.global_position, PAD, "the pad stands where the map's S4 marker is")
	var ring := catapult.get_node_or_null(^"PadRing") as MeshInstance3D
	var beam := catapult.get_node_or_null(^"Beam") as MeshInstance3D
	h.ok(ring != null and beam != null, "the pad has a ring and a beam")
	h.ok(not ring.visible and not beam.visible, "both stay dark until the gate opens")

	# The hero walks on: the real `body_entered` path, not a direct call.
	h.player.debug_teleport([PAD.x, PAD.y + 2.0, PAD.z])
	catapult.open()
	h.ok(catapult.armed, "opening the gate arms the pad")
	h.ok(ring.visible and beam.visible, "and lights them")
	await h.settle(6)
	h.ok(catapult.flying, "standing on the lit pad launches the hero")

	var launched_from := h.player.global_position
	h.ok(launched_from.y >= PAD.y, "the hero is on the pad when it fires")
	# Fly the arc out on the physics clock.
	var frames := int(FlowAscensionCatapult.FLIGHT_TIME * 120.0) + 30
	await h.settle(frames)
	h.ok(not catapult.flying, "the flight ends and control comes back")
	h.ok(h.player.global_position.y > LANDING.y, "the arc carries the hero above the Crown deck")
	h.ok(absf(h.player.global_position.z - LANDING.z) < 60.0,
			"and over the deck itself, not past it")
	catapult.queue_free()
	await h.settle(2)
	_arc_clears_the_deck(h)
	await _no_crown_mid_flight(h)


## r5 brief item 2: the arc must not cross the Crown deck. The pad sits UNDER it (90 m out from the
## Spire axis, 80 m below the fighting floor), so the path has to swing out past the r 150 rim before
## it rises and come back in above the top disc. Checked against the deck's own numbers — the outer
## ring's floor at `CENTRE.y`, the top disc at `CENTRE.y + 16`, the fins' 24 m tops, and the Ø80 core
## — with the mech's 15 m capsule taken into account at every sample.
static func _arc_clears_the_deck(h: FlowTestHarness) -> void:
	var pad := Vector3(0.0, FlowCrownDeck.CENTRE.y - 62.0, FlowCrownDeck.CENTRE.z - 90.0)
	var landing := Vector3(0.0, FlowCrownDeck.CENTRE.y + 16.0, FlowCrownDeck.CENTRE.z - 65.0)
	var half := 7.5
	var samples := 120
	var outside := 0
	var hits := 0
	for i in samples + 1:
		var at := FlowAscensionCatapult.arc(pad, landing, float(i) / float(samples))
		var flat := Vector2(at.x - FlowCrownDeck.CENTRE.x, at.z - FlowCrownDeck.CENTRE.z).length()
		if flat > 150.0:
			outside += 1
			continue
		if at.y + half <= FlowCrownDeck.CENTRE.y - 8.0:
			continue        # under the slab: that is the pad's own side of the deck
		if at.y - half >= _deck_top(flat):
			continue
		hits += 1
	h.ok(hits == 0, "the swept arc never crosses the Crown deck (%d of %d samples inside r 150 did)"
			% [hits, samples + 1 - outside])
	h.ok(outside > 0, "and it really does go out past the rim (%d samples beyond r 150)" % outside)
	# The landing is on the fighting floor: outside the Ø80 core, inside the top disc.
	var flat_landing := Vector2(landing.x - FlowCrownDeck.CENTRE.x,
			landing.z - FlowCrownDeck.CENTRE.z).length()
	h.ok(flat_landing > 40.0 and flat_landing < 104.0,
			"the arc ends on the fighting floor, clear of the core (r %.0f)" % flat_landing)


static func _deck_top(flat: float) -> float:
	if flat <= 104.0:
		return FlowCrownDeck.CENTRE.y + 16.0
	if flat <= 126.0:
		return FlowCrownDeck.CENTRE.y + 8.0
	return FlowCrownDeck.CENTRE.y


## r5 brief item 2: `reached_crown` must not fire while the catapult is still flying. It used to,
## because the arc's capsule overlaps a deck tile and `is_on_floor()` reads that as a floor.
static func _no_crown_mid_flight(h: FlowTestHarness) -> void:
	var gate := FlowCrownGate.new()
	gate.name = "TestCrownGate"
	h.root.add_child(gate)
	gate.build()
	# An Array, not an int: a GDScript lambda captures its locals BY VALUE, so `n += 1` inside
	# one would count in the lambda's own copy and the check would always read zero.
	var reached: Array[int] = []
	gate.reached_crown.connect(func() -> void: reached.append(1))
	h.player.debug_teleport([FlowCrownDeck.CENTRE.x, 300.0, FlowCrownDeck.CENTRE.z])
	await h.settle(4)
	gate.tick()
	h.eq(reached.size(), 0, "the gate stays shut while the hero is in the air over the deck")
	h.ok(not FlowCrownDeck.touched_down(h.root.get_tree(), h.player),
			"and `touched_down` agrees: the feet are not on anything")
	var landing := h.crown_landing()
	h.player.debug_teleport([landing.x, landing.y + 8.0, landing.z])
	await h.settle(4)
	gate.tick()
	h.eq(reached.size(), 1, "a real touchdown on the fighting floor opens it exactly once")
	gate.queue_free()
	await h.settle(2)
