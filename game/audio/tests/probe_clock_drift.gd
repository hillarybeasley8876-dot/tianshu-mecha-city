extends Node
## Diagnostic probe (audio r7): can `AudioClock` (Feel.real_now, an idle-frame accumulator clamped at
## 0.1 s per frame) drift away from the physics-frame count that `test_audio_clocks._settle_music()`
## counts? tooling r1b's Request 18 guessed it could. NOT a suite: `probe_*.gd`, so tools/suites.sh's
## coverage check ignores it.
##
##   tools/godot.sh test res://audio/tests/probe_clock_drift.gd
##
## Each round stalls the main thread for `stall_ms` (the condition a loaded machine creates) and then
## reports how much game time and how many physics frames actually passed.

const ROUNDS := 6
const STALLS := [0, 8, 30, 120, 300, 900]
const SETTLE_FRAMES := 240


func _ready() -> void:
	await get_tree().process_frame
	print("PROBE tps=%d max_physics_steps=%d max_fps=%d" % [Engine.physics_ticks_per_second,
		ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame", 8),
		Engine.max_fps])
	for i in ROUNDS:
		await _round(STALLS[i])
	print("PROBE done")
	get_tree().quit(0)


func _round(stall_ms: int) -> void:
	var frames0 := Engine.get_physics_frames()
	var real0 := Feel.real_now()
	var wall0 := Time.get_ticks_msec()
	for f in SETTLE_FRAMES:
		if stall_ms > 0 and f == SETTLE_FRAMES / 2:
			OS.delay_msec(stall_ms)
		await get_tree().physics_frame
	var frames := Engine.get_physics_frames() - frames0
	var real := Feel.real_now() - real0
	var wall := Time.get_ticks_msec() - wall0
	print("PROBE stall=%4dms  physics_frames=%4d (%.3f s)  real_now=%.3f s  wall=%.3f s  "
		% [stall_ms, frames, float(frames) / float(Engine.physics_ticks_per_second), real,
			float(wall) / 1000.0]
		+ "drift=%+.3f s (real - frames/120)" % (real - float(frames)
			/ float(Engine.physics_ticks_per_second)))
