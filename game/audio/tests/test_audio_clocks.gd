extends Node
## Clock regressions for reviews/audio-audit.md findings 1-5: every interval, age and quantisation in
## the audio unit must be measured on game time, never the wall clock.
##
## Run on its own with `tools/godot.sh test res://audio/tests/test_audio_clocks.gd`, or as part of
## `tools/godot.sh test res://audio/tests/test_audio.gd`, which adds it as a child and adds its
## failure count to its own.

var fails: int = 0


func _ready() -> void:
	if get_parent() != get_tree().root:
		return   # driven by test_audio.gd
	await get_tree().process_frame
	await run_checks()
	print("TEST audio clocks: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _check(ok: bool, msg: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", msg])
	if not ok:
		fails += 1


## Burn `ms` of wall time per frame while the game clock advances one fixed step. `tools/godot.sh test`
## runs --fixed-fps 120, so this reproduces the movie-capture condition (18-83 ms of wall time per
## game frame) that made every wall-clock interval in the audio unit shrink — the regression checks
## below must not depend on the capture speed.
func _slow_frames(count: int, ms: int = 25) -> void:
	for i in count:
		OS.delay_msec(ms)
		await get_tree().physics_frame


## Advance `seconds` of game time as fast as the headless loop allows.
func _game_seconds(seconds: float) -> void:
	var ticks := int(ceilf(seconds * float(Engine.physics_ticks_per_second)))
	for i in ticks:
		await get_tree().physics_frame


## Every check below fails on the wall-clock code it replaced (proved by re-patching each source
## file back and re-running this suite).
func run_checks() -> void:
	# FIRST, while the director is still in its initial state: this check needs the beat clock to have
	# no clip latched yet, which is exactly the state `test_audio_clocks.gd` used to flake in.
	await _metronome_ignores_graph_hops()
	await _gatling_release_clock()
	await _interval_clock()
	await _voice_queue_clock()
	await _stinger_clock()
	await _metronome_follows_stream()


## Finding 1: the gatling loop released after 250 ms of *wall* time, so a 15 rps burst in a movie
## capture (one round every ~280 ms of wall time) stopped and re-spun the loop after every round.
func _gatling_release_clock() -> void:
	Audio.stop_all()
	await get_tree().physics_frame
	var router := Audio.router
	router.on_weapon_fired(&"gatling", Vector3.ZERO, Vector3.FORWARD)
	_check(router.gatling_loop_on(), "gatling loop starts on the first round")
	# A kill_large hit-stop: real time runs on, the weapon's own clock (Feel.player_delta) nearly stops.
	_check(Feel.hit_stop(0.35), "global hit-stop accepted for the release test")
	await _slow_frames(14, 25)     # ~0.35 s of wall time, ~0.02 s of weapon-clock time
	_check(router.gatling_loop_on(),
		"the loop survives a hit-stop: release counts player_delta, not wall time")
	# The hit-stop is still running when the slow frames end, so give the weapon clock room to finish
	# the freeze and then accumulate the full release gap.
	await _game_seconds(AudioEventRouter.GATLING_RELEASE_S + 0.9)
	_check(not router.gatling_loop_on(),
		"the loop releases after %.2f s of weapon-clock silence" % AudioEventRouter.GATLING_RELEASE_S)
	Audio.stop_all()
	await get_tree().physics_frame


## Finding 2: per-event min_interval and steal ages ran on Time.get_ticks_msec(), so a 200 ms accent
## interval passed on every 66.7 ms round in a capture and steal ages were inflated ~4x.
func _interval_clock() -> void:
	Audio.stop_all()
	await get_tree().physics_frame
	var timed := SoundEvent.new()
	timed.id = &"test_rate_limited"
	timed.streams = [Audio.events[&"hitmarker"].streams[0]]
	timed.bus = &"UI"
	timed.priority = 30.0
	timed.max_instances = 0
	timed.min_interval_ms = 600
	_check(Audio.pool.play_2d(timed, timed.streams[0], 0.0, 1.0), "rate-limited id starts once")
	await _slow_frames(25, 25)     # 0.62 s of wall time, 0.21 s of game time
	_check(not Audio.pool.play_2d(timed, timed.streams[0], 0.0, 1.0),
		"a 600 ms interval still blocks after 0.62 s of WALL time (measured on the game clock)")
	await _game_seconds(0.55)
	_check(Audio.pool.play_2d(timed, timed.streams[0], 0.0, 1.0),
		"the same id plays again after 600 ms of GAME time")
	Audio.stop_all()
	await get_tree().physics_frame


## Finding 3: the cockpit queue's busy window and 8 s repeat guard ran on the wall clock, so a 1.2 s
## line counted as finished after ~0.3 s of footage and the next line talked over it.
func _voice_queue_clock() -> void:
	var queue := AudioVoiceQueue.new()
	add_child(queue)
	var spoken: Array[StringName] = []
	queue.emit_line = func(id: StringName) -> bool:
		spoken.append(id)
		return true
	queue.request(&"ai_energy_low", 50.0, 1.2)
	queue.request(&"ai_armor_50", 50.0, 1.2)
	_check(spoken.size() == 1, "one cockpit line at a time (%d started)" % spoken.size())
	await _slow_frames(25, 25)     # 0.62 s of wall time, 0.21 s of game time
	_check(spoken.size() == 1, "the 1.2 s line is still speaking after 0.62 s of WALL time")
	# The pool's own report is the upper bound: a line that is still sounding keeps the speaker.
	queue.line_sounding = func(_id: StringName) -> bool: return true
	await _game_seconds(1.5)
	_check(spoken.size() == 1, "a line the pool still reports as sounding holds the speaker")
	queue.line_sounding = func(_id: StringName) -> bool: return false
	await get_tree().physics_frame
	_check(spoken.size() == 2, "the queue advances once the line stops sounding")
	# The 8 s repeat guard is on the same clock: ai_energy_low was spoken ~1.7 s of game time ago.
	await _game_seconds(7.0)
	queue.request(&"ai_energy_low", 50.0, 1.2)
	_check(spoken.size() == 3 and spoken[2] == &"ai_energy_low",
		"a line may repeat once 8 s of game time has passed (%s)" % [spoken])
	queue.request(&"ai_energy_low", 90.0, 1.2)
	_check(spoken.size() == 3, "the same line cannot repeat again straight away")
	queue.queue_free()


## Finding 4: the 2 s stinger gap ran on the wall clock and stingers bypass the voice pool, so in a
## capture the gap shrank to 0.4-1.8 s and stagger/kill/phase stingers stacked.
func _stinger_clock() -> void:
	var music := Audio.music
	var before: int = music.state()["stinger_requests"]
	music.stinger(&"stinger_stagger")
	_check(music.state()["stinger_requests"] == before + 1, "the first stinger passes the gap check")
	music.stinger(&"stinger_kill_large")
	_check(music.state()["stinger_requests"] == before + 1, "a second stinger inside 2 s is dropped")
	await _slow_frames(100, 25)    # 2.5 s of wall time, 0.83 s of game time
	music.stinger(&"stinger_kill_large")
	_check(music.state()["stinger_requests"] == before + 1,
		"the 2 s gap still holds after 2.5 s of WALL time")
	await _game_seconds(1.4)
	music.stinger(&"stinger_kill_large")
	_check(music.state()["stinger_requests"] == before + 2,
		"a stinger passes once 2 s of GAME time has elapsed")


## Finding 5: the metronome restarted at request time, but the interactive stream only enters the
## destination at the next bar/beat — so every quantised stinger after the first switch was off-grid.
## A headless mixer never reports a clip change, so the director's switch timeout is what hands the
## beat clock over here; either way it must not happen on the frame the switch was asked for.
func _metronome_follows_stream() -> void:
	var music := Audio.music
	Audio.music_intensity(0.2)
	await _settle_music()
	_check(music.playing_clip == &"explore", "the score settles on explore (%.1f BPM)"
		% float(music.state()["bpm"]))
	var was_bpm: float = float(music.state()["bpm"])
	Audio.music_intensity(1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(music.clip == &"boss", "the switch request is recorded immediately")
	_check(music.playing_clip == &"explore"
		and is_equal_approx(float(music.state()["bpm"]), was_bpm),
		"the beat clock stays on the playing clip's tempo (%.1f BPM) until the stream switches"
		% was_bpm)
	await _settle_music()
	_check(music.playing_clip == &"boss"
		and is_equal_approx(float(music.state()["bpm"]), music.clip_bpm(&"boss")),
		"the beat clock reaches the requested clip (%.1f BPM) once the wait is over"
		% float(music.state()["bpm"]))
	Audio.music_intensity(0.2)
	await _settle_music()
	_check(is_equal_approx(float(music.state()["bpm"]), music.clip_bpm(&"explore")),
		"and follows the score back down to explore")


## r7 (tooling r1b Request 18): the beat clock must follow the clip the SCORE asked for, not whatever
## clip the interactive graph happens to be walking through. `any -> boss` used to carry
## auto_advance -> `tension`, so the moment the mixer advanced far enough to report a clip change the
## boss switch handed the beat clock to `tension` (110.0 BPM) instead of `boss` (145.6) — the flake
## that failed 1 of 4 full table passes and 0 of 4 solo runs.
##
## The condition is WALL time, not game time: `probe_clock_drift.gd` shows AudioClock and the
## physics-frame count are the same clock to within 0.000 s even through a 900 ms stall, while the
## mixer runs on the wall clock. An idle headless loop runs ~24,000 frames/s, so 8 s of game time is
## ~40 ms of wall time and the mixer never reaches the explore clip's 2.508 s bar — the timeout always
## won and the suite was green. Under load the same 8 s of game time takes seconds of wall time, the
## mixer reaches the bar, and the graph hop fires. `_slow_frames` buys that wall time deliberately.
func _metronome_ignores_graph_hops() -> void:
	var music := Audio.music
	Audio.music_intensity(0.2)
	await _settle_music()
	Audio.music_intensity(1.0)
	await get_tree().physics_frame
	var wall0 := Time.get_ticks_msec()
	await _slow_frames(960, 4)     # ~5 s of WALL time inside the same 8 s of game time
	var wall_s := float(Time.get_ticks_msec() - wall0) / 1000.0
	var index := _stream_clip_index()
	_check(music.playing_clip == &"boss"
			and is_equal_approx(float(music.state()["bpm"]), music.clip_bpm(&"boss")),
		"the beat clock stays on the requested clip while the mixer walks the graph "
		+ "(%.1f BPM on %s after %.1f s of wall time, stream on clip %d)"
		% [float(music.state()["bpm"]), music.playing_clip, wall_s, index])
	Audio.music_intensity(0.2)
	await _settle_music()


## What the interactive stream reports as current — the diagnostic half of the check above. -1 when
## there is no playback (a mixer that never started).
func _stream_clip_index() -> int:
	var music := Audio.music
	var player: AudioStreamPlayer = music.get("_player")
	var playback := player.get_stream_playback() as AudioStreamPlaybackInteractive
	return playback.get_current_clip_index() if playback != null else -1



## Wait out a queued switch: two bars of the slowest clip plus the crossfade (SWITCH_TIMEOUT_BARS).
func _settle_music() -> void:
	await _game_seconds(8.0)
