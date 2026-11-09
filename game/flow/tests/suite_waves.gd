class_name FlowWaveSuite
extends RefCounted
## Encounter data and the wave machine: start conditions (on enter / half the previous wave dead /
## cleared / timer), the escalation per destroyed spire and the 40-enemy budget (CONTRACTS §2).

const ARENA := &"sandbox"


static func run(h: FlowTestHarness) -> void:
	_data(h)
	_machine(h)


static func _data(h: FlowTestHarness) -> void:
	FlowEncounterWaves.reset_cache()
	var a1 := FlowEncounterWaves.waves(&"A1")
	h.eq(a1.size(), 3, "A1 is three mini-combats (brief: 2 ripper waves + 1 mantis)")
	h.eq(a1[0]["id"], &"A1_w1", "the first wave keeps its id")
	h.eq(a1[0]["start"]["kind"], &"on_enter", "wave 1 starts on entering the arena")
	h.eq(a1[1]["start"]["kind"], &"previous_half", "wave 2 overlaps wave 1 (dossier rule 6)")
	h.eq(a1[2]["start"]["kind"], &"previous_cleared", "the mantis waits for a cleared yard")
	h.eq((a1[2]["groups"] as Array)[0]["type"], &"mantis", "the tutorial ends on a mantis")
	h.ok(FlowEncounterWaves.waves(&"nope").is_empty(), "a missing arena file yields no waves")
	var group := {"count": 8, "escalate": true}
	h.eq(FlowEncounterWaves.group_count(group, 0), 8, "no spires down: the authored count")
	h.eq(FlowEncounterWaves.group_count(group, 2), 12, "two spires down: +25 % each")
	h.eq(FlowEncounterWaves.group_count({"count": 8}, 3), 8, "a group without `escalate` never grows")


## The wave machine on its own director, with a spawn hook standing in for the enemies unit.
static func _machine(h: FlowTestHarness) -> void:
	var dir := FlowEncounterDirector.new()
	dir.name = "TestEncounters"
	dir.spawn_hook = func(type: StringName, _at: Vector3, count: int) -> Array:
		var made: Array = []
		for i in count:
			var e := FlowFakeEnemy.new()
			e.enemy_type = type
			h.root.add_child(e)
			made.append(e)
		return made
	h.root.add_child(dir)
	dir.build_sandbox(Vector3.ZERO, 200.0)
	var state := dir.arena_state(ARENA)
	if not h.ok(not state.is_empty(), "the sandbox arena exists"):
		return
	var zone := state["zone"] as FlowArenaZone
	h.player.debug_teleport([0.0, 1.0, 0.0])
	h.ok(zone.contains(h.player.global_position), "the hero stands inside the arena footprint")
	h.ok(not zone.contains(Vector3(0.0, 4000.0, 0.0)), "far above the arena is outside it")
	h.ok(not zone.contains(Vector3(900.0, 1.0, 900.0)), "a block away is outside it")
	zone.poll(h.player.global_position)
	h.ok(bool(state["active"]), "entering the arena arms it")
	dir.tick(0.1)
	h.eq(dir.live_count(), 4, "wave 1 spawns on enter")
	h.eq(int(state["index"]), 1, "one wave started")
	# Wave 2 waits until half of wave 1 is dead.
	_kill(dir, 1)
	dir.tick(0.1)
	h.eq(int(state["index"]), 1, "one of four dead is not half")
	_kill(dir, 1)
	dir.tick(0.1)
	h.eq(int(state["index"]), 2, "half of wave 1 dead starts wave 2")
	h.eq(dir.live_count(), 7, "wave 2 is 4 rippers + 1 mantis on top of the survivors")
	_kill(dir, 7)
	dir.tick(0.1)
	h.ok(bool(state["done"]), "the arena is cleared once every wave is dead")
	h.ok("clear:sandbox" in h.encounters, "Events.encounter_cleared fired for the arena")
	h.ok("start:sandbox" in h.encounters, "Events.encounter_started fired for the arena")
	_budget(h, dir)
	dir.queue_free()


## CONTRACTS §2: 40 enemies with AI, never more, whatever the data asks for.
static func _budget(h: FlowTestHarness, dir: FlowEncounterDirector) -> void:
	dir.spawn_hook = func(_t: StringName, _at: Vector3, count: int) -> Array:
		var made: Array = []
		for i in count:
			var e := FlowFakeEnemy.new()
			h.root.add_child(e)
			made.append(e)
		return made
	dir.reset_arena(ARENA, false)
	dir.set_spires_down(3)
	h.eq(dir.budget_left(), FlowEncounterDirector.BUDGET, "a cleared field has the whole budget")
	# Ask for far more than the budget in one wave.
	var arena := dir.arena_state(ARENA)
	arena["waves"] = [{"id": &"flood", "start": {"kind": &"on_enter"},
			"groups": [{"type": &"ripper", "count": 500}]}]
	arena["active"] = true
	dir.tick(0.1)
	h.eq(dir.live_count(), FlowEncounterDirector.BUDGET,
			"a wave of 500 is trimmed to the 40-enemy budget")


static func _kill(dir: FlowEncounterDirector, count: int) -> void:
	var state := dir.arena_state(ARENA)
	var live := state["live"] as Array
	for i in mini(count, live.size()):
		var e := live[i] as FlowFakeEnemy
		if e != null:
			e.alive = false
