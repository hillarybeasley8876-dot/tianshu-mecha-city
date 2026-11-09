extends Node
## Skills unit test entry point: `tools/godot.sh test res://combat/skills/tests/test_skills.gd`.
## Builds the rig (flat ground + SkillRigPlayer carrying the real skill_system.tscn + dummy enemies),
## runs every suite in turn and prints PASS/FAIL per check. Exits 1 if anything failed.

var _harness: SkillTestHarness = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_harness = SkillTestHarness.new(self)
	if not _harness.build():
		_finish()
		return
	await SkillCostSuite.run(_harness)
	await SkillMobilitySuite.run(_harness)
	await SkillFinSuite.run(_harness)
	await SkillAoeSuite.run(_harness)
	await SkillFinisherSuite.run(_harness)
	await SkillClockSuite.run(_harness)
	await SkillInputSuite.run(_harness)
	await SkillDeathSuite.run(_harness)
	_finish()


func _finish() -> void:
	var h := _harness
	if h != null:
		h.release_all()
	var failed: int = h.failures.size() if h != null else 1
	print("TEST %d checks, %d failed" % [h.checks if h != null else 0, failed])
	for line in (h.failures if h != null else PackedStringArray(["harness did not build"])):
		print("TEST FAIL ", line)
	get_tree().quit(1 if failed > 0 else 0)
