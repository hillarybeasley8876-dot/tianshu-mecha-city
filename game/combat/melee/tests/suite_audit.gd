class_name MeleeAuditSuite
extends RefCounted
## Regressions for the numeric-robustness audit (reviews/melee-defense-audit.md). Each block is the
## exact trigger from a finding and fails on the pre-audit code:
##   1. the Core Rend requested its camera cut WITHOUT the per-request clock, so the rig advanced the
##      shot list on real time while the execution counted down on player time — every `finisher`
##      slow-mo ended the cut ~0.3 s early and put the `core` shot before the rupture.
##
## Audit finding 6 (`SaberVisual._swing_hold` decaying on the world clock) is GONE with the arc
## placement itself: review r4 deleted the hold along with `place_swing`, because the blade is the
## socket now. The check that replaced it is `hand.*` in suite_hand.gd.


## A rig that records the clock the Core Rend asks for (camera-aim's CONTRACTS §5 signature).
class RigSpy:
	extends Node3D
	var calls: int = 0
	var clock: StringName = &""
	var duration: float = 0.0

	func request_cinematic(_shots: Array, duration_: float, clock_: StringName = &"real") -> void:
		calls += 1
		clock = clock_
		duration = duration_


## A rig from before the clock argument: the director must still drive it instead of erroring.
class RigLegacy:
	extends Node3D
	var calls: int = 0

	func request_cinematic(_shots: Array, _duration: float) -> void:
		calls += 1


static func run(h: MeleeTestHarness) -> void:
	await _cut_runs_on_player_time(h)


## [finding 1] An execution must ask for the PLAYER clock, and must still work against a rig that
## predates the argument.
static func _cut_runs_on_player_time(h: MeleeTestHarness) -> void:
	var saved: Node = Game.camera_rig
	var spy := RigSpy.new()
	spy.name = "RigSpy"
	h.root.add_child(spy)
	Game.camera_rig = spy
	h.fresh()
	var enemy := h.add_dummy(10.0)
	enemy.stagger()
	await h.ticks(2)
	var started: bool = h.system.executor.start(enemy)
	h.check("cut.execution_starts", started)
	h.eq("cut.rig_was_asked", spy.calls, 1)
	h.eq("cut.runs_on_the_player_clock", spy.clock, &"player")
	h.near("cut.duration_matches_the_execution", spy.duration,
			float(ExecutionDirector.CLASSES[&"light"]["duration"]), 0.001)
	h.system.executor.cancel()
	h.fresh()
	await h.ticks(2)

	var legacy := RigLegacy.new()
	legacy.name = "RigLegacy"
	h.root.add_child(legacy)
	Game.camera_rig = legacy
	var enemy2 := h.add_dummy(10.0)
	enemy2.stagger()
	await h.ticks(2)
	h.check("cut.starts_against_a_two_arg_rig", h.system.executor.start(enemy2))
	h.eq("cut.two_arg_rig_was_asked", legacy.calls, 1)
	h.system.executor.cancel()
	Game.camera_rig = saved as Node3D
	legacy.queue_free()
	spy.queue_free()
	h.fresh()
	await h.step(0.1)
