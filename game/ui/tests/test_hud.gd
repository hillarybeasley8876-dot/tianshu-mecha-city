extends Node
## HUD unit test entry point: `tools/godot.sh test res://ui/tests/test_hud.gd`.
## Builds the real `ui/hud.tscn` over a fake player, camera rig and enemies, then runs the widget,
## feedback and menu suites. Exits 1 if any check failed.

var _harness: HudTestHarness = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_harness = HudTestHarness.new()
	if not _harness.build(self):
		_finish()
		return
	await HudWidgetSuite.run(_harness)
	await HudAccessSuite.run(_harness)
	await HudLookSuite.run(_harness)
	await HudClockSuite.run(_harness)
	await HudFeedbackSuite.run(_harness)
	await HudMenuSuite.run(_harness)
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
