extends Node
## Weapons unit test entry point: `tools/godot.sh test res://combat/weapons/tests/test_weapons.gd`.
## Builds the rig (flat ground + RigPlayer carrying the real weapon_system.tscn + dummy hurtboxes),
## runs every suite in turn and prints PASS/FAIL per check. Exits 1 if anything failed.

var _harness: WeaponTestHarness = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_harness = WeaponTestHarness.new(self)
	if not _harness.build():
		_finish()
		return
	await RifleSuite.run(_harness)
	await WeaponShaderSuite.run(_harness)
	await WeaponClockSuite.run(_harness)
	await WeaponRobustSuite.run(_harness)
	await GatlingSuite.run(_harness)
	await FpVfxSuite.run(_harness)
	await FpNearSuite.run(_harness)
	await MissileSuite.run(_harness)
	await WeaponTeardownSuite.run(_harness)
	_harness.system.switch_weapon(-1)
	await _harness.step(0.4)
	await PerfSuite.run(_harness)
	_finish()


func _finish() -> void:
	var h := _harness
	var failed: int = h.failures.size() if h != null else 1
	print("TEST %d checks, %d failed" % [h.checks if h != null else 0, failed])
	for line in (h.failures if h != null else PackedStringArray(["harness did not build"])):
		print("TEST FAIL ", line)
	get_tree().quit(1 if failed > 0 else 0)
