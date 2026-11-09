extends Node
## Audio unit tests: `tools/godot.sh test res://audio/tests/test_audio.gd`.
## Covers the brief's "Done when": bus layout and ducking, voice caps and stealing, every FEEL id and
## every Events signal resolving to a SoundEvent, the eight distance classes' attenuation against the
## dossier table, and the music clip state machine.

var _fails: int = 0
## Filled in by _feel_table_coverage() and printed by the check that calls it.
var _feel_table_report: String = ""


func _ready() -> void:
	await get_tree().process_frame
	_buses()
	_ducking()
	await _world_duck()
	_distance_classes()
	_event_coverage()
	_aliases()
	await _enemy_routing()
	_signal_coverage()
	await _voice_caps()
	await _voice_stealing()
	await _loops()
	await _music()
	await _clock_regressions()
	_call_sites()
	await _listener()
	print("TEST audio: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(ok: bool, msg: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", msg])
	if not ok:
		_fails += 1


func _close(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


## The clock regressions live in their own file (audio/tests/test_audio_clocks.gd, runnable on its
## own); its failures count towards this suite's.
func _clock_regressions() -> void:
	var clocks: Node = load("res://audio/tests/test_audio_clocks.gd").new()
	clocks.name = "ClockRegressions"
	add_child(clocks)
	await clocks.run_checks()
	_fails += clocks.fails


## Same arrangement for the call-site audit (audio/tests/test_audio_call_sites.gd): it prints every
## literal id another unit hands to Audio and fails on any the bank cannot answer.
func _call_sites() -> void:
	var sites: Node = load("res://audio/tests/test_audio_call_sites.gd").new()
	sites.name = "CallSites"
	add_child(sites)
	_fails += sites.run_checks()


## And for the enemy sound routing (audio/tests/test_audio_enemies.gd).
func _enemy_routing() -> void:
	var enemies: Node = load("res://audio/tests/test_audio_enemies.gd").new()
	enemies.name = "EnemyRouting"
	add_child(enemies)
	await enemies.run_checks()
	_fails += enemies.fails


# --- buses -----------------------------------------------------------------------------------------
func _buses() -> void:
	var names: Array[StringName] = []
	for i in AudioServer.bus_count:
		names.append(AudioServer.get_bus_name(i))
	var expected: Array[StringName] = []
	for row in AudioBuses.LAYOUT:
		expected.append(row["name"])
	_check(names == expected, "bus order matches §5.1: %s" % [names])
	for i in AudioBuses.LAYOUT.size():
		var row: Dictionary = AudioBuses.LAYOUT[i]
		var send := AudioServer.get_bus_send(i)
		var wanted: StringName = row["send"]
		if wanted == &"":
			_check(send == &"", "Master has no send")
		else:
			_check(send == wanted, "%s sends to %s (got %s)" % [row["name"], wanted, send])
			_check(AudioServer.get_bus_index(wanted) < i,
					"%s index %d > send target %d" % [row["name"], i, AudioServer.get_bus_index(wanted)])
	_check(AudioBuses.find_effect(&"Master", "AudioEffectHardLimiter") >= 0,
			"Master has a hard limiter at -1 dB")
	_check(AudioBuses.find_effect(&"UI", "AudioEffectCompressor") < 0, "UI is never ducked")


# --- ducking ---------------------------------------------------------------------------------------
func _ducking() -> void:
	for effect_id in AudioBuses.SIDE_CHAINS:
		var chain: Dictionary = AudioBuses.SIDE_CHAINS[effect_id]
		var key_index := AudioServer.get_bus_index(chain["key"])
		_check(key_index > 0, "%s key %s exists" % [effect_id, chain["key"]])
	# A key must sit to the right of every bus it ducks, or the compressor reads a pre-effect buffer.
	var music := AudioServer.get_bus_index(&"Music")
	var bed := AudioServer.get_bus_index(&"Bed")
	var enemies := AudioServer.get_bus_index(&"Enemies")
	var voice := AudioServer.get_bus_index(&"Voice")
	var impacts := AudioServer.get_bus_index(&"Impacts")
	_check(voice > music and impacts > music, "Music's keys (Voice %d, Impacts %d) are above it (%d)"
			% [voice, impacts, music])
	_check(impacts > bed and voice > bed, "Bed's keys are above it (%d)" % bed)
	_check(impacts > enemies, "Enemies' key is above it (%d)" % enemies)
	# Godot reduces gain by ~2.08x the textbook amount (dossier §5.2), so the designed targets below
	# are what the compressor should actually deliver for a key 4 dB over its threshold.
	var reductions: Array[String] = []
	var sane := true
	for effect_id in AudioBuses.SIDE_CHAINS:
		var chain: Dictionary = AudioBuses.SIDE_CHAINS[effect_id]
		var predicted := 2.08136898 * 4.0 * (1.0 - 1.0 / float(chain["ratio"]))
		reductions.append("%s %.1f dB" % [effect_id, predicted])
		if predicted <= 1.0 or predicted > 14.0:
			sane = false
	_check(sane, "ducking 4 dB over threshold stays in 1..14 dB: %s" % [reductions])
	_check(_close(_sidechain_threshold(&"Music", 0), -14.0, 0.01),
			"Music duck from Voice uses threshold -14 dB")


func _sidechain_threshold(bus: StringName, effect_index: int) -> float:
	var index := AudioServer.get_bus_index(bus)
	if index < 0 or effect_index >= AudioServer.get_bus_effect_count(index):
		return -999.0
	var effect := AudioServer.get_bus_effect(index, effect_index)
	return (effect as AudioEffectCompressor).threshold if effect is AudioEffectCompressor else -999.0


## FEEL's sound column for kill_large / boss_kill ends "; world -6 dB" (docs/FEEL.md). The duck has to
## move the World bus by exactly that, leave the buses that are NOT under World alone, and come back.
func _world_duck() -> void:
	var world := AudioServer.get_bus_index(&"World")
	var base := AudioServer.get_bus_volume_db(world)
	var others: Dictionary = {}
	for bus in [&"Voice", &"UI", &"Cockpit", &"Music"]:
		others[bus] = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))
	Audio.mixer.duck_world(AudioMixer.WORLD_DUCK_DB, 0.2)
	_check(_close(AudioServer.get_bus_volume_db(world) - base, AudioMixer.WORLD_DUCK_DB, 0.01),
		"the kill duck drops World by %.0f dB (%.1f -> %.1f)"
		% [AudioMixer.WORLD_DUCK_DB, base, AudioServer.get_bus_volume_db(world)])
	var untouched: Array[StringName] = []
	for bus in others:
		if not _close(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus)), others[bus],
				0.01):
			untouched.append(bus)
	_check(untouched.is_empty(), "the duck leaves Voice / UI / Cockpit / Music alone (%s)"
			% [untouched])
	# 0.2 s held + the 0.4 s release, then it must be back on the baseline it read.
	for i in 120:
		await get_tree().physics_frame
	_check(_close(AudioServer.get_bus_volume_db(world), base, 0.05),
		"World is back on its baseline after the duck (%.1f, was %.1f)"
		% [AudioServer.get_bus_volume_db(world), base])


# --- distance classes ------------------------------------------------------------------------------
func _distance_classes() -> void:
	_check(AudioDistance.CLASSES.size() == 8, "eight distance classes (C0..C7)")
	# Values copied from the dossier §5.4 table (dB at that distance, computed with Godot's formula).
	var expected := [
		{"class": 1, "d": 26.0, "db": -14.0}, {"class": 1, "d": 200.0, "db": -51.0},
		{"class": 2, "d": 100.0, "db": -16.0}, {"class": 2, "d": 400.0, "db": -36.0},
		{"class": 3, "d": 200.0, "db": -15.0}, {"class": 3, "d": 800.0, "db": -36.0},
		{"class": 4, "d": 400.0, "db": -15.0}, {"class": 4, "d": 1600.0, "db": -39.0},
		{"class": 5, "d": 800.0, "db": -15.0}, {"class": 5, "d": 1600.0, "db": -25.0},
		{"class": 6, "d": 10.0, "db": -18.0}, {"class": 7, "d": 100.0, "db": -19.0},
	]
	var worst := 0.0
	var worst_msg := ""
	for row in expected:
		var gain := AudioDistance.gain_db(row["class"], row["d"])
		var error := absf(gain - float(row["db"]))
		if error > worst:
			worst = error
			worst_msg = "C%d at %dm = %.1f dB (table %.0f)" % [row["class"], row["d"], gain,
				row["db"]]
	_check(worst <= 1.5, "attenuation matches the §5.4 table at 12 points (worst: %s)" % worst_msg)
	_check(_close(AudioDistance.gain_db(0, 500.0), 0.0, 0.01), "C0 never attenuates")
	_check(not AudioDistance.is_audible(1, 400.0), "C1 is culled beyond 220 m")
	_check(AudioDistance.is_audible(5, 1600.0), "C5 reaches across the 1.6 km map")
	_check(AudioDistance.CLASSES[7]["doppler"], "only C7 tracks doppler")
	var player := AudioStreamPlayer3D.new()
	add_child(player)
	AudioDistance.apply(player, 4)
	_check(player.max_distance == 2000.0 and player.unit_size == 90.0, "C4 applied to a player")
	_check(player.doppler_tracking == AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED,
			"non-flyby players have doppler disabled")
	player.queue_free()


# --- coverage --------------------------------------------------------------------------------------
func _event_coverage() -> void:
	var rows := AudioSoundBank.all_rows()
	var missing_files: Array[StringName] = []
	for id in rows:
		if not Audio.events.has(id):
			missing_files.append(id)
	_check(missing_files.is_empty(), "every table row has stream files (%d missing: %s)"
			% [missing_files.size(), missing_files.slice(0, 5)])
	var feel_missing: Array[StringName] = []
	for feel_id in AudioEventMap.FEEL_IDS:
		if not Audio.events.has(AudioEventMap.sound_for_feel(feel_id)):
			feel_missing.append(feel_id)
		for extra in AudioEventMap.extras_for_feel(feel_id):
			if not Audio.events.has(extra):
				feel_missing.append(extra)
	_check(feel_missing.is_empty(), "all %d FEEL ids resolve to a SoundEvent (%s)"
			% [AudioEventMap.FEEL_IDS.size(), feel_missing])
	var table_ok := _feel_table_coverage()
	_check(table_ok, _feel_table_report)
	var bad_buses: Array[StringName] = []
	for id in Audio.events:
		var event: SoundEvent = Audio.events[id]
		if not event.is_valid() or AudioServer.get_bus_index(event.bus) < 0:
			bad_buses.append(id)
	_check(bad_buses.is_empty(), "every event has streams on a real bus (%s)" % [bad_buses])
	var bad_classes: Array[StringName] = []
	for id in Audio.events:
		var event: SoundEvent = Audio.events[id]
		if event.distance_class < 0 or event.distance_class >= AudioDistance.CLASSES.size():
			bad_classes.append(id)
	_check(bad_classes.is_empty(), "every event uses C0..C7 (%s)" % [bad_classes])


## The real coverage gate: EVERY row of docs/FEEL.md (the lead's source of truth, read by
## `FeelTable`) must reach a sound. FEEL_IDS is a hand-kept copy, so a row the feel unit adds — r7's
## `last_stand`, `boss_kill` and the three gatling vent rows — used to land with no FEEL_IDS entry and
## no bank row, and the only symptom was an "unknown sound id" WARNING in somebody else's drive log.
## This reads the table itself, so a new row cannot ship silent.
func _feel_table_coverage() -> bool:
	var ids := FeelTable.ids()
	var silent: Array[String] = []
	for feel_id in ids:
		var sound_id := AudioEventMap.sound_for_feel(feel_id)
		if not Audio.events.has(sound_id):
			silent.append("%s -> %s" % [feel_id, sound_id])
		for extra in AudioEventMap.extras_for_feel(feel_id):
			if not Audio.events.has(extra):
				silent.append("%s extra %s" % [feel_id, extra])
	_feel_table_report = "all %d docs/FEEL.md rows reach a sound (%d silent: %s)" % [ids.size(),
			silent.size(), silent.slice(0, 6)]
	return ids.size() >= 40 and silent.is_empty()


func _aliases() -> void:
	var broken: Array[StringName] = []
	for alias in AudioTableAliases.ALIASES:
		var target: StringName = AudioTableAliases.ALIASES[alias]
		if not Audio.events.has(target):
			broken.append(alias)
	_check(broken.is_empty(), "all %d feel-layer aliases resolve to a real event (%s)"
			% [AudioTableAliases.ALIASES.size(), broken])


func _signal_coverage() -> void:
	# get_signal_list() also reports Object/Node's built-ins; only Events' own signals are ours.
	var inherited: Array[StringName] = []
	for entry in Node.new().get_signal_list():
		inherited.append(entry["name"])
	var declared: Array[StringName] = []
	for entry in Events.get_signal_list():
		if not inherited.has(entry["name"]):
			declared.append(entry["name"])
	var bound := Audio.bound_signal_names()
	var unbound: Array[StringName] = []
	for signal_name in declared:
		if not bound.has(signal_name):
			unbound.append(signal_name)
	_check(unbound.is_empty(), "all %d Events signals are wired (%s)" % [declared.size(), unbound])
	_check(bound.size() == declared.size(), "no stale bindings (%d bound, %d declared)"
			% [bound.size(), declared.size()])


# --- voice budget ----------------------------------------------------------------------------------
func _voice_caps() -> void:
	var event: SoundEvent = Audio.events[&"footstep_hero"]
	Audio.stop_all()
	await get_tree().process_frame
	var started := 0
	for i in 6:
		if Audio.pool.play_3d(event, event.streams[0], Vector3(0, 0, -5.0 * i), 0.0, 1.0, true):
			started += 1
	_check(started <= event.max_instances, "cap %d honoured (%d started of 6)"
			% [event.max_instances, started])
	_check(Audio.pool.active_count(&"footstep_hero") <= event.max_instances,
			"active count respects the cap (%d)" % Audio.pool.active_count(&"footstep_hero"))
	var interval: SoundEvent = Audio.events[&"hitmarker"]
	var first := Audio.pool.play_2d(interval, interval.streams[0], 0.0, 1.0)
	var second := Audio.pool.play_2d(interval, interval.streams[0], 0.0, 1.0)
	_check(first and not second, "min interval blocks an immediate repeat")
	Audio.stop_all()
	await get_tree().process_frame


func _voice_stealing() -> void:
	Audio.stop_all()
	await get_tree().process_frame
	var cheap := SoundEvent.new()
	cheap.id = &"test_filler"
	cheap.streams = [Audio.events[&"debris_concrete"].streams[0]]
	cheap.bus = &"World"
	cheap.priority = 20.0
	cheap.max_instances = 0
	var started := 0
	for i in AudioVoicePool.NEAR_VOICES:
		if Audio.pool.play_3d(cheap, cheap.streams[0], Vector3(0, 0, -float(i)), 0.0, 1.0, true):
			started += 1
		if i % AudioVoicePool.MAX_NEW_PER_TICK == AudioVoicePool.MAX_NEW_PER_TICK - 1:
			# the pool resets its per-tick counter in _physics_process, so let a tick pass
			await get_tree().physics_frame
			await get_tree().physics_frame
	_check(started == AudioVoicePool.NEAR_VOICES, "near pool filled (%d)" % started)
	# The steal rule is "lowest priority - 10 * age", so age alone eventually makes a voice cheap;
	# what must never happen is a *quieter* sound evicting a more important one.
	var cheaper := SoundEvent.new()
	cheaper.id = &"test_filler_low"
	cheaper.streams = cheap.streams
	cheaper.bus = &"World"
	cheaper.priority = 5.0
	cheaper.max_instances = 0
	_check(not Audio.pool.play_3d(cheaper, cheaper.streams[0], Vector3.ZERO, 0.0, 1.0, true),
			"a priority-5 voice never evicts priority-20 voices")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var loud: SoundEvent = Audio.events[&"finisher"]
	_check(Audio.pool.play_3d(loud, loud.streams[0], Vector3.ZERO, 0.0, 1.0, true),
			"a priority-%d voice steals a priority-%d one" % [loud.priority, cheap.priority])
	_check(not Audio.pool.play_3d(loud, loud.streams[0], Vector3.ZERO, 0.0, 1.0, true)
			or Audio.pool.active_count(&"finisher") == 1, "cap 1 on the finisher")
	var protected: SoundEvent = Audio.events[&"parry_perfect"]
	_check(protected.priority >= AudioVoicePool.PROTECTED_PRIORITY,
			"the parry is priority %d and never stolen" % protected.priority)
	Audio.stop_all()
	await get_tree().process_frame


func _loops() -> void:
	Audio.stop_all()
	await get_tree().process_frame
	for i in AudioVoicePool.LOOP_VOICES:
		Audio.play_loop(&"amb_street", true, Vector3.ZERO)
		var id: StringName = [&"amb_tunnel_hum", &"amb_wind_high", &"amb_storm_crown",
			&"distant_battle_bed", &"neon_buzz", &"spire_pulse_loop"][i]
		Audio.play_loop(id, true, Vector3(0, 0, -float(i)))
	_check(Audio.pool.voice_stats()["loops"] == AudioVoicePool.LOOP_VOICES,
			"%d loop voices in use" % AudioVoicePool.LOOP_VOICES)
	var stream: AudioStream = Audio.events[&"saber_hum_loop"].streams[0]
	_check(stream is AudioStreamWAV and (stream as AudioStreamWAV).loop_mode
			== AudioStreamWAV.LOOP_FORWARD, "WAV loops are forced to forward looping")
	var ogg: AudioStream = Audio.events[&"amb_street"].streams[0]
	_check(ogg is AudioStreamOggVorbis and (ogg as AudioStreamOggVorbis).loop,
			"OGG beds loop")
	Audio.play_loop(&"amb_tunnel_hum", false)
	_check(Audio.pool.voice_stats()["loops"] == AudioVoicePool.LOOP_VOICES - 1,
			"stopping a loop frees its voice")
	Audio.stop_all()
	await get_tree().process_frame


# --- music -----------------------------------------------------------------------------------------
func _music() -> void:
	var music := Audio.music
	var state: Dictionary = music.state()
	_check(state["started"], "the interactive stream is playing")
	var clips: Array = state["clips"]
	_check(clips.size() >= 5, "%d sourced clips in the graph: %s" % [clips.size(), clips])
	for clip_name in clips:
		_check(ResourceLoader.exists("res://audio/music/%s_mix.ogg" % clip_name),
				"clip %s has a rendered mix" % clip_name)
	Audio.music_intensity(0.2)
	await get_tree().process_frame
	_check(music.clip == &"explore", "intensity 0.2 -> explore")
	Audio.music_intensity(0.6)
	await get_tree().process_frame
	_check(music.clip == &"combat", "intensity 0.6 -> combat")
	Audio.music_intensity(1.0)
	await get_tree().process_frame
	_check(music.clip == &"boss", "intensity 1.0 -> boss")
	Audio.music_intensity(0.2)
	await get_tree().process_frame
	_check(music.clip == &"explore", "intensity back to 0.2 -> explore")
	# Each sourced track carries its own tempo, so the beat clock must follow the clip that is
	# playing rather than one global BPM.
	var beat := music.seconds_to_next_beat()
	var clip_beat := 60.0 / float(state["bpm"])
	_check(beat > 0.0 and beat <= clip_beat + 0.001,
			"metronome reports %.3f s to the next beat at %.1f BPM (<= %.3f)"
			% [beat, float(state["bpm"]), clip_beat])
	Audio.stinger(&"stinger_stagger")
	await get_tree().process_frame
	Audio.stinger(&"stinger_kill_large")
	_check(true, "a second stinger inside 2 s is dropped, not stacked")


func _listener() -> void:
	var state := Audio.debug_state()
	_check(state["bound_signals"] > 20, "%d events bound" % state["bound_signals"])
	_check(state["events"] >= 180, "%d sound events loaded" % state["events"])
	_check(state["mixer"]["zone"] is StringName, "mixer reports a listener zone")
	_check(state["voices"]["world_total"] == AudioVoicePool.WORLD_VOICES
			- AudioVoicePool.LOOP_VOICES, "world pool sized for %d voices"
			% (AudioVoicePool.WORLD_VOICES - AudioVoicePool.LOOP_VOICES))
