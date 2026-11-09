extends Node
## Contract test for CONTRACTS §2 (flags): `--sandbox` alone is free play for every other unit, so
## GameFlow must stay completely idle there — no drop-in, no tutorial, no test spires, no waves.
##   tools/godot.sh test res://flow/tests/test_flow_idle.gd -- --sandbox --spawn=0,1,60
## The mirror of `test_flow.gd`, which runs the same build with `--flow` added.

var _harness: FlowTestHarness = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_harness = FlowTestHarness.new()
	if not _harness.build(self):
		_finish()
		return
	if not Game.has_flag("sandbox") or Game.has_flag("flow"):
		_harness.fail("run with: tools/godot.sh test res://flow/tests/test_flow_idle.gd"
				+ " -- --sandbox --spawn=0,1,60  (no --flow)")
		_finish()
		return
	await _harness.settle(6)
	var h := _harness
	var flow := h.flow
	h.ok(not FlowGameFlow.should_run(), "--sandbox without --flow means the flow does not run")
	h.eq(flow.state_name(), &"title", "the state machine never leaves the title")
	h.ok(flow.spires().is_empty(), "no test spires are placed in another unit's sandbox")
	h.ok(flow.director.arena_ids().is_empty(), "no arena triggers and therefore no waves")
	h.eq(h.root.get_tree().get_nodes_in_group(&"hive_spire").size(), 0,
			"nothing joins the &\"hive_spire\" group")
	h.ok(h.player.global_position.y < 50.0,
			"the hero stands on the sandbox spawn instead of being dropped from 400 m")
	h.ok(h.player.global_position.distance_to(Vector3(0.0, 1.0, 60.0)) < 5.0,
			"the hero was not moved at all")
	h.ok(flow.checkpoint() == null, "no checkpoint is written")
	_finish()


func _finish() -> void:
	var h := _harness
	var failed: int = h.failures.size() if h != null else 1
	print("TEST %d checks, %d failed" % [h.checks if h != null else 0, failed])
	for line in (h.failures if h != null else PackedStringArray(["harness did not build"])):
		print("TEST FAIL ", line)
	if h != null:
		h.release_all()
	get_tree().quit(1 if failed > 0 else 0)
