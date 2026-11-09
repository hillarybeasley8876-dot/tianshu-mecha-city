extends Node
## Melee unit test entry point: `tools/godot.sh test res://combat/melee/tests/test_melee.gd`.
## Builds the rig (flat ground + MeleeRigPlayer carrying the real melee_system.tscn + dummy enemies),
## runs both suites and prints PASS/FAIL per check. Exits 1 if anything failed.

var _harness: MeleeTestHarness = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_harness = MeleeTestHarness.new(self)
	if not _harness.build():
		_finish()
		return
	await MeleeComboSuite.run(_harness)
	await MeleeSpecialSuite.run(_harness)
	await MeleeCinematicSuite.run(_harness)
	await MeleeAuditSuite.run(_harness)
	await MeleeLeadSuite.run(_harness)
	await MeleeHandSuite.run(_harness)
	await MeleeBladeSuite.run(_harness)
	_harness.fresh()
	_finish()


func _finish() -> void:
	var h := _harness
	var failed: int = h.failures.size() if h != null else 1
	print("TEST %d checks, %d failed" % [h.checks if h != null else 0, failed])
	for line in (h.failures if h != null else PackedStringArray(["harness did not build"])):
		print("TEST FAIL ", line)
	get_tree().quit(1 if failed > 0 else 0)
