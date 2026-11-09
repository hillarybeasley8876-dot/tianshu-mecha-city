class_name AudioMusicDirector
extends Node
## Adaptive score (ref/research/audio-music.md §6.2-6.3): one AudioStreamInteractive whose clips are
## sourced CC0 tracks, switched bar-synced from `music_intensity(0..1)`.
##
## The tracks are not one key/tempo family, so each clip is a single full mix carrying its own
## bpm/bar_beats/beat_count (from clips.json) and the graph crossfades between them on their own
## bars, rather than layering stems vertically.
##
## Gotchas handled here (dossier §5.10): the interactive stream has no playback position, so a silent
## metronome player restarted at each clip's tempo is the beat clock; music keeps playing while the
## tree is paused. The metronome is (re)started when the *stream* reports the clip changed, not when a
## switch is requested: an interactive stream only queues the switch and enters the destination at the
## next bar or beat, so a metronome restarted at request time runs at an arbitrary phase and every
## quantised stinger after the first switch lands off the grid.
##
## All spacing here is on AudioClock (game seconds): a wall clock turned the 2 s stinger gap into
## 0.4-1.8 s of footage in a movie capture, so stagger/kill/phase stingers stacked.

const CLIPS_PATH := "res://audio/music/clips.json"
const MUSIC_DIR := "res://audio/music/"
const CLIP_ORDER: Array[StringName] = [&"explore", &"combat", &"boss", &"tension", &"spire_cleared",
	&"victory"]
## Sourced CC0 tracks do not share one tempo, so there is no global BPM: every clip carries its own
## bpm/bar_beats/beat_count from clips.json and the graph crossfades between full mixes on their own
## bars (the brief's fallback for tracks outside one key/tempo family).
const FALLBACK_BPM := 120.0
const BEATS_PER_BAR := 4
const STINGER_MIN_GAP_S := 2.0
## Destinations entered at their head (TRANSITION_TO_TIME_START in _add_transitions). Every other
## switch carries the source position (SAME_POSITION / PREVIOUS_POSITION), so the metronome has to
## carry the phase across instead of restarting at 0.
const ENTERS_AT_HEAD: Array[StringName] = [&"boss", &"spire_cleared", &"victory"]
## A switch is queued at the next bar, so the stream should report it within about one bar. If it has
## not after this long, the mixer is not reporting (a headless run never mixes) and the beat clock
## takes the requested clip anyway rather than staying on a tempo nothing is playing.
const SWITCH_TIMEOUT_BARS := 2.0

var intensity: float = 0.2
var clip: StringName = &"explore"        ## the clip the score was last asked for
var playing_clip: StringName = &"explore"  ## the clip the beat clock is following

var _player: AudioStreamPlayer
var _metro: AudioStreamPlayer
var _interactive: AudioStreamInteractive
var _syncs: Dictionary = {}          # clip name -> AudioStreamSynchronized
var _clip_meta: Dictionary = {}     # clip name -> {bpm, beat_count, bar_beats, file}
var _metro_bpm: float = FALLBACK_BPM
var _last_stinger_at: float = -1000.0
var _stinger_requests: int = 0     ## gap checks passed; the test asserts on this, not on playback
var _seen_clip_index: int = -1
## The clip the score last asked for: the ONLY clip the beat clock ever adopts (see _sync_to_stream).
var _want_clip: StringName = &"explore"
## A switch is outstanding: the stream has not reported `_want_clip` yet and the timeout has not run.
var _switch_pending: bool = false
var _pending_since: float = -1.0
var _started: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = _make_player(&"Music")
	_metro = _make_player(&"Music")
	_metro.volume_db = -80.0
	_load_clip_meta()
	_build_stream()
	if _interactive != null:
		_player.stream = _interactive
		_player.play()
		_restart_metronome()
		_started = _player.playing
		# The metronome already runs at the initial clip's tempo: do not let the first poll restart it.
		_seen_clip_index = 0
		playing_clip = StringName(_interactive.get_clip_name(0))


func _make_player(bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	return player


## Read the per-clip tempo map written by tools/sfx/music_tracks.py.
func _load_clip_meta() -> void:
	if not FileAccess.file_exists(CLIPS_PATH):
		push_warning("AudioMusicDirector: no %s; falling back to %.0f BPM" % [CLIPS_PATH, FALLBACK_BPM])
		return
	var text := FileAccess.get_file_as_string(CLIPS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Array):
		push_error("AudioMusicDirector: %s is not a JSON array" % CLIPS_PATH)
		return
	for entry: Dictionary in parsed:
		_clip_meta[StringName(entry.get("clip", ""))] = {
			"bpm": float(entry.get("bpm", FALLBACK_BPM)),
			"beat_count": int(entry.get("beat_count", 64)),
			"bar_beats": int(entry.get("bar_beats", BEATS_PER_BAR)),
			"file": String(entry.get("file", "")),
		}


func clip_bpm(clip_name: StringName) -> float:
	return float(_clip_meta.get(clip_name, {}).get("bpm", FALLBACK_BPM))


## The silent metronome is the beat clock (the interactive stream exposes no position). It follows the
## clip the stream is actually playing, at that clip's tempo, so stinger quantisation tracks the music
## instead of one fixed BPM. `phase_s` carries the source position across a SAME_POSITION switch.
func _restart_metronome(phase_s: float = 0.0) -> void:
	var stream := _load(MUSIC_DIR + "metronome.ogg", _metro_bpm, 4, BEATS_PER_BAR)
	if stream == null:
		return
	_metro.stream = stream
	_metro.play()
	if phase_s > 0.0:
		_metro.seek(phase_s)


## Build the clip graph: each clip is one full-mix AudioStreamSynchronized; transitions are
## bar-synced crossfades measured against each clip's own tempo.
func _build_stream() -> void:
	var clips: Array = []
	for name in CLIP_ORDER:
		var stream := _load_clip(name)
		if stream != null:
			clips.append({"name": name, "stream": stream})
	if clips.is_empty():
		push_warning("AudioMusicDirector: no music clips found under %s" % MUSIC_DIR)
		return
	_interactive = AudioStreamInteractive.new()
	_interactive.clip_count = clips.size()
	var index := 0
	for entry in clips:
		var sync := AudioStreamSynchronized.new()
		sync.stream_count = 1
		sync.set_sync_stream(0, entry["stream"])
		sync.set_sync_stream_volume(0, 0.0)
		_interactive.set_clip_name(index, entry["name"])
		_interactive.set_clip_stream(index, sync)
		_syncs[entry["name"]] = sync
		index += 1
	_interactive.initial_clip = 0
	_metro_bpm = clip_bpm(CLIP_ORDER[0])
	_add_transitions()


func _add_transitions() -> void:
	var any := AudioStreamInteractive.CLIP_ANY
	var next_bar := AudioStreamInteractive.TRANSITION_FROM_TIME_NEXT_BAR
	var next_beat := AudioStreamInteractive.TRANSITION_FROM_TIME_NEXT_BEAT
	var same := AudioStreamInteractive.TRANSITION_TO_TIME_SAME_POSITION
	var start := AudioStreamInteractive.TRANSITION_TO_TIME_START
	var previous := AudioStreamInteractive.TRANSITION_TO_TIME_PREVIOUS_POSITION
	var cross := AudioStreamInteractive.FADE_CROSS
	var out := AudioStreamInteractive.FADE_OUT
	var explore := CLIP_ORDER.find(&"explore")
	var combat := CLIP_ORDER.find(&"combat")
	_interactive.add_transition(any, any, next_bar, same, cross, 2.0, false, -1, false)
	_interactive.add_transition(explore, combat, next_beat, same, cross, 1.0, false, -1, false)
	_interactive.add_transition(combat, explore, next_bar, same, cross, 8.0, false, -1, false)
	# The dossier's table wants a 2-bar `tension` riser as the FILLER under the boss switch. Godot's
	# add_transition() has no filler parameter, and the sourced `tension` track is a full 65 s bed, not
	# a 2-bar riser — using it as the filler would play a minute of it before the boss. So the boss
	# clip is entered at its head over a 1-beat fade of the source and then LOOPS (every clip OGG is
	# loop = true). This transition used to carry auto_advance -> `tension`, which made the score
	# leave the boss clip the instant it entered it; that is what the beat clock used to follow.
	_interactive.add_transition(any, CLIP_ORDER.find(&"boss"), next_bar, start, out, 1.0,
			false, -1, false)
	_interactive.add_transition(any, CLIP_ORDER.find(&"spire_cleared"), next_beat, start, cross,
			1.0, true, -1, true)
	_interactive.add_transition(CLIP_ORDER.find(&"spire_cleared"), any,
			AudioStreamInteractive.TRANSITION_FROM_TIME_END, previous, cross, 2.0, false, -1, false)
	_interactive.add_transition(any, CLIP_ORDER.find(&"victory"),
			AudioStreamInteractive.TRANSITION_FROM_TIME_IMMEDIATE, start, out, 1.0, false, -1, false)


func _load_clip(clip_name: StringName) -> AudioStreamOggVorbis:
	var meta: Dictionary = _clip_meta.get(clip_name, {})
	var file := String(meta.get("file", "%s_mix.ogg" % clip_name))
	return _load(MUSIC_DIR + file, float(meta.get("bpm", FALLBACK_BPM)),
			int(meta.get("beat_count", 64)), int(meta.get("bar_beats", BEATS_PER_BAR)))


func _load(path: String, bpm: float, beat_count: int, bar_beats: int) -> AudioStreamOggVorbis:
	if not ResourceLoader.exists(path):
		return null
	var stream := ResourceLoader.load(path)
	if not (stream is AudioStreamOggVorbis):
		push_error("AudioMusicDirector: %s is not an OGG stream" % path)
		return null
	var ogg := stream as AudioStreamOggVorbis
	ogg.loop = true
	ogg.bpm = bpm
	ogg.bar_beats = bar_beats
	ogg.beat_count = beat_count
	return ogg


## Intensity 0..1 picks the clip (SPEC §8: 0.2 explore -> 0.45 contact -> 0.85 boss).
func set_intensity(level: float) -> void:
	intensity = clampf(level, 0.0, 1.0)
	var wanted := _clip_for_intensity(intensity)
	if wanted != clip:
		switch_to(wanted)


func _clip_for_intensity(level: float) -> StringName:
	if level >= 0.85:
		return &"boss"
	if level >= 0.45:
		return &"combat"
	return &"explore"


func switch_to(clip_name: StringName) -> void:
	if not _started or not _syncs.has(clip_name):
		return
	var playback := _player.get_stream_playback() as AudioStreamPlaybackInteractive
	if playback == null:
		return
	# The stream queues the switch and enters the destination at the next bar/beat, so the beat clock
	# is handed over in _sync_to_stream() when the change is observed — not here.
	playback.switch_to_clip_by_name(clip_name)
	clip = clip_name
	_want_clip = clip_name
	_switch_pending = true
	_pending_since = AudioClock.now()


## Hand the beat clock to the clip the SCORE asked for. Polling is the only way to see the stream
## move (switch_to_clip_by_name() only queues and the playback position is not exposed), but the
## stream is not the authority on what the beat clock should be: the graph routes through hops the
## score never asked for, and adopting one of those put the metronome on a tempo nothing had
## requested. That was the r7 flake — the `any -> boss` transition carried auto_advance to `tension`,
## so the moment the (wall-clock) mixer advanced far enough to report a clip change, the boss switch
## handed the beat clock to `tension` (110.0 BPM) instead of `boss` (145.6). Only `_want_clip` adopts.
func _sync_to_stream() -> void:
	if not _started or _interactive == null:
		return
	if not _switch_pending and _want_clip == playing_clip:
		return
	if _switch_pending and AudioClock.since(_pending_since) > _switch_timeout_s(_want_clip):
		_switch_pending = false
		_adopt_clip(_want_clip)
		return
	var playback := _player.get_stream_playback() as AudioStreamPlaybackInteractive
	if playback == null:
		return
	var index := playback.get_current_clip_index()
	if index < 0 or index == _seen_clip_index:
		return
	_seen_clip_index = index
	if StringName(_interactive.get_clip_name(index)) != _want_clip:
		return
	_switch_pending = false
	_adopt_clip(_want_clip)


## Bars of `clip_name` a queued switch is allowed to take before the beat clock stops waiting.
func _switch_timeout_s(clip_name: StringName) -> float:
	var bars: float = float(_clip_meta.get(clip_name, {}).get("bar_beats", BEATS_PER_BAR))
	return SWITCH_TIMEOUT_BARS * bars * 60.0 / maxf(clip_bpm(clip_name), 1.0) + 2.0


func _adopt_clip(name: StringName) -> void:
	playing_clip = name
	var phase := 0.0
	if not ENTERS_AT_HEAD.has(name) and _metro.playing:
		phase = fmod(maxf(_metro.get_playback_position(), 0.0), 60.0 / maxf(_metro_bpm, 1.0))
	_metro_bpm = clip_bpm(name)
	_restart_metronome(phase)


func _process(_delta: float) -> void:
	_sync_to_stream()


## Beat-quantised one-shot. At most one stinger per 2 s of game time (dossier §6.2 global rule) —
## stingers bypass the voice pool, so this gap is their only limit.
func stinger(stinger_id: StringName, immediate: bool = false) -> void:
	if AudioClock.since(_last_stinger_at) < STINGER_MIN_GAP_S:
		return
	var path := MUSIC_DIR + "stingers/%s.ogg" % stinger_id
	if not ResourceLoader.exists(path):
		push_warning("AudioMusicDirector: no stinger %s" % path)
		return
	_last_stinger_at = AudioClock.now()
	_stinger_requests += 1
	if immediate:
		_play_stinger(path)
		return
	var timer := get_tree().create_timer(seconds_to_next_beat(), true, false, true)
	timer.timeout.connect(_play_stinger.bind(path))


func _play_stinger(path: String) -> void:
	var stream := ResourceLoader.load(path) as AudioStreamOggVorbis
	if stream == null:
		return
	var player := _make_player(&"Stinger")
	player.stream = stream
	player.play()
	player.finished.connect(player.queue_free)


## Hardware-clock beat position from the silent metronome player (Godot docs, dossier §6.3). The
## metronome runs at the *current clip's* tempo, restarted on every switch, so this is the beat of the
## music that is actually playing.
func seconds_to_next_beat() -> float:
	var beat := 60.0 / maxf(_metro_bpm, 1.0)
	if _metro == null or not _metro.playing:
		return beat
	var pos := _metro.get_playback_position() + AudioServer.get_time_since_last_mix() \
			- AudioServer.get_output_latency()
	return beat - fmod(maxf(pos, 0.0), beat)


func state() -> Dictionary:
	return {"clip": clip, "playing_clip": playing_clip, "intensity": intensity,
		"started": _started, "bpm": _metro_bpm, "stinger_requests": _stinger_requests,
		"clips": _syncs.keys(),
		"next_beat_s": seconds_to_next_beat(),
		"gains": {}}
