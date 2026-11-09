extends Node
## Defence unit test entry point: `tools/godot.sh test res://combat/defense/tests/test_defense.gd`.
## Builds the rig (a MeleeRigPlayer carrying the real defense_system.tscn + live EnemyProjectile
## shots), runs both suites and prints PASS/FAIL per check. Exits 1 if anything failed.

var _harness: DefenseTestHarness = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_harness = DefenseTestHarness.new(self)
	if not _harness.build():
		_finish()
		return
	await DefenseParrySuite.run(_harness)
	await DefenseCatchSuite.run(_harness)
	await DefenseAuditSuite.run(_harness)
	await DefenseVisualSuite.run(_harness)
	_harness.fresh()
	_finish()


func _finish() -> void:
	var h := _harness
	var failed: int = h.failures.size() if h != null else 1
	print("TEST %d checks, %d failed" % [h.checks if h != null else 0, failed])
	for line in (h.failures if h != null else PackedStringArray(["harness did not build"])):
		print("TEST FAIL ", line)
	get_tree().quit(1 if failed > 0 else 0)
