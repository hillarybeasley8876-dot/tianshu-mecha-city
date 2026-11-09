extends Node
## Diagnostic probe (audio r7): force the wall-clock condition that made the beat-clock check flake.
## NOT a suite: `probe_*.gd`, so tools/suites.sh's coverage check ignores it.
##
##   tools/godot.sh test res://audio/tests/probe_boss_switch.gd
##
## `probe_clock_drift.gd` proves `AudioClock` (Feel.real_now) and the physics-frame count are the SAME
## clock — they cannot drift, even through a 900 ms stall. The clock that CAN differ is the wall clock,
## and that is the one the audio mixer runs on. So the flake needs the loop to be slow enough in WALL
## time for the mixer to reach the explore clip's next bar (2.508 s at 95.7 BPM) inside the 8 s of game
## time `_settle_music()` waits — which a loaded machine does and an idle one (24,000 frames/s here)
## never does.
##
## `stall_ms` per frame buys that wall time without touching the game clock: 960 frames x 4 ms = 3.8 s
## of wall time and exactly 8 s of game time, the same ratio a loaded full-table pass has.

const SETTLE_FRAMES := 960
const STALL_MS := 4


func _ready() -> void:
	await get_tree().process_frame
	var music := Audio.music
	print("PROBE start stall=%dms/frame" % STALL_MS)
	Audio.music_intensity(1.0)
	await get_tree().physics_frame
	var wall0 := Time.get_ticks_msec()
	for f in SETTLE_FRAMES:
		OS.delay_msec(STALL_MS)
		await get_tree().physics_frame
	var wall := Time.get_ticks_msec() - wall0
	var interactive: AudioStreamInteractive = music.get("_interactive")
	var playback := music.get("_player").get_stream_playback() as AudioStreamPlaybackInteractive
	var index := playback.get_current_clip_index() if playback != null else -99
	print("PROBE wall=%.2fs game=%.2fs stream_idx=%d(%s) adopt=%s want=%s bpm=%.1f"
		% [float(wall) / 1000.0, Feel.real_now(), index,
			StringName(interactive.get_clip_name(index)) if index >= 0 else &"-",
			music.playing_clip, music.clip, float(music.state()["bpm"])])
	print("PROBE VERDICT %s" % ("boss adopted" if music.playing_clip == &"boss"
			and is_equal_approx(float(music.state()["bpm"]), music.clip_bpm(&"boss"))
			else "NOT boss (%.1f BPM on %s)" % [float(music.state()["bpm"]), music.playing_clip]))
	get_tree().quit(0)
