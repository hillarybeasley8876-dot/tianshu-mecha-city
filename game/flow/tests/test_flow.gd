extends Node
## Flow unit test entry point:
##   tools/godot.sh test res://flow/tests/test_flow.gd -- --sandbox --flow --spawn=0,1,60
## The flags place the three sandbox spires and skip the 400 m drop so the state machine is
## deterministic (`--flow` is what asks the flow to run at all — CONTRACTS §2); the drop-in and victory
## sequences are exercised by the scripted run in status/flow.md instead. Exits 1 if any check failed.

var _harness: FlowTestHarness = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_harness = FlowTestHarness.new()
	if not _harness.build(self):
		_finish()
		return
	if not Game.has_flag("sandbox") or not Game.has_flag("flow") or not Game.has_flag("spawn"):
		_harness.fail("run with: tools/godot.sh test res://flow/tests/test_flow.gd"
				+ " -- --sandbox --flow --spawn=0,1,60")
		_finish()
		return
	await FlowStateSuite.run(_harness)
	await FlowSpireSuite.run(_harness)
	await FlowWaveSuite.run(_harness)
	await FlowWorldSuite.run(_harness)
	await FlowCatapultSuite.run(_harness)
	await FlowE2ESuite.run(_harness)
	_finish()


func _finish() -> void:
	var h := _harness
	var failed: int = h.failures.size() if h != null else 1
	print("TEST %d checks, %d failed, %d skipped" % [h.checks if h != null else 0, failed,
			h.skips.size() if h != null else 0])
	for line in (h.failures if h != null else PackedStringArray(["harness did not build"])):
		print("TEST FAIL ", line)
	if h != null:
		h.release_all()
	get_tree().quit(1 if failed > 0 else 0)
