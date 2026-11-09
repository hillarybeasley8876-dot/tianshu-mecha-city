extends Node
## Boss unit test entry point.
##   tools/godot.sh test res://enemies/boss/tests/test_boss.gd
## Runs the fight-logic suite and the attack suite against the brief's "Done when" list and prints
## PASS/FAIL per check. Exits 1 if anything failed.

var _harness: BossTestHarness = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_harness = BossTestHarness.new(self)
	if not _harness.build():
		_finish()
		return
	await BossSuite.run(_harness)
	await BossAttackSuite.run(_harness)
	await BossDeckSuite.run(_harness)
	await BossPresentationSuite.run(_harness)
	_finish()


func _finish() -> void:
	var h := _harness
	var failed := 1
	if h != null:
		h.release_all()
		failed = h.failures.size()
		print("BOSS TEST %d checks, %d failed" % [h.checks, failed])
		for line in h.failures:
			print("BOSS TEST FAIL ", line)
	else:
		print("BOSS TEST 0 checks, 1 failed")
		print("BOSS TEST FAIL harness did not build")
	print("PASS" if failed == 0 else "FAIL")
	get_tree().quit(1 if failed > 0 else 0)
