class_name FlowE2ESuite
extends RefCounted
## The r4 harness pieces that can be checked without a window: the crown gate no longer parks the
## boss unit's arena (lead r4 item 1), the capture geometry helpers answer the truth on a real floor,
## and `--boss-hp-scale` scales the titan exactly once (lead r4 item 3).

const ARENA_FAKE := "FakeBossArena"


## Stand-ins with the two properties `_scale_boss_hp` scales (`Object.set` on a plain Node3D has
## nothing to write to).
class FakeTitan extends Node3D:
	var hp: float = 1000.0
	var hp_max: float = 1000.0


class FakeCore extends Node3D:
	var hp: float = 200.0
	var hp_max: float = 200.0


static func run(h: FlowTestHarness) -> void:
	_crown_gate(h)
	await h.settle(2)
	_view_geometry(h)
	_boss_hp_scale(h)


## The Crown gate is only the trigger and the catapult now: the boss arena belongs to the boss unit,
## whose own `armed` flag keeps its return catapult out of the district.
static func _crown_gate(h: FlowTestHarness) -> void:
	var gate := h.flow.crown
	h.ok(not gate.has_method(&"park_boss_arena"),
			"the crown gate no longer carries the park_boss_arena workaround")
	h.ok(not gate.has_method(&"release"), "and no release() to hand a parked arena back")
	var arena := Node3D.new()
	arena.name = ARENA_FAKE
	arena.set_physics_process(true)
	h.root.add_child(arena)
	arena.add_to_group(&"boss_arena")
	gate.tick()
	gate.tick()
	h.ok(arena.is_physics_processing(),
			"ticking the gate leaves the boss arena's own physics alone")
	arena.queue_free()


## `sees` / `openness` / `standable` / `floor_under`: what the E2E uses to choose where to stand and to
## decide whether a frame is a wall. Checked against the harness's own 2000 m floor.
static func _view_geometry(h: FlowTestHarness) -> void:
	var view := FlowDebugView.new()
	var above := Vector3(0.0, 40.0, 0.0)
	h.ok(FlowDebugView.sees(above, above + Vector3.FORWARD * 50.0),
			"open air has line of sight along itself")
	h.ok(not FlowDebugView.sees(above, Vector3(0.0, -10.0, 0.0)),
			"a point under the floor is not in sight from above it")
	h.near(FlowDebugView.openness(above), 1.0, "40 m up is completely open", 0.01)
	var buried := Vector3(0.0, -2.5, 0.0)
	h.near(FlowDebugView.openness(buried), 0.0,
			"inside the floor is completely closed (a ray from inside a solid hits nothing)", 0.01)
	h.ok(FlowDebugView.standable(Vector3(20.0, 0.0, 20.0)), "the flat floor is standable")
	h.ok(not FlowDebugView.standable(Vector3(0.0, -10.0, 0.0)),
			"a stand whose chest is inside the floor is not standable")
	h.eq(view.floor_under(above, 60.0), Vector3(0.0, 0.0, 0.0),
			"floor_under finds the top of the floor slab")
	h.eq(view.floor_under(Vector3(0.0, 900.0, 0.0), 60.0), Vector3.INF,
			"floor_under answers INF when the ray finds nothing (never the probe point itself)")
	h.eq(view.lowest_floor(Vector3(0.0, 900.0, 0.0), 60.0), Vector3(0.0, 900.0, 0.0),
			"lowest_floor falls back to where it was asked about, not to thin air below it")


## `--boss-hp-scale`: the titan's pool and its cores, once, and only when the flag is there.
static func _boss_hp_scale(h: FlowTestHarness) -> void:
	var debug := h.flow.get_node_or_null(^"Debug") as FlowDebug
	if not h.ok(debug != null, "the flow carries its debug command node"):
		return
	var boss := FakeTitan.new()
	boss.name = "FakeTitan"
	h.root.add_child(boss)
	boss.add_to_group(&"boss")
	var core := FakeCore.new()
	core.name = "FakeCore"
	boss.add_child(core)
	core.add_to_group(&"boss_core")

	debug.call(&"_scale_boss_hp")
	h.eq(boss.hp_max, 1000.0, "no flag, no scaling")
	Game.flags[FlowDebug.HP_SCALE_FLAG] = "0.25"
	debug.call(&"_scale_boss_hp")
	h.eq(boss.hp_max, 250.0, "the titan's pool is scaled")
	h.eq(boss.hp, 250.0, "and its current HP with it")
	h.eq(core.hp_max, 50.0, "and so is every core's")
	debug.call(&"_scale_boss_hp")
	h.eq(boss.hp_max, 250.0, "and only once, however often it is asked")
	Game.flags.erase(FlowDebug.HP_SCALE_FLAG)
	boss.queue_free()
