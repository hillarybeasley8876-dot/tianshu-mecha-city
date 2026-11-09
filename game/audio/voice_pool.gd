class_name AudioVoicePool
extends Node
## Voice budget and stealing (ref/research/audio-music.md §5.6): 40 world + 12 near-field 3D voices
## and one AudioStreamPolyphonic (24 voices) for 2D. Six of the world players are reserved for
## loops, so a swarm can never steal the flight or gatling bed.
##
## Steal rule: when a pool is full, steal the voice with the lowest `priority - 10 * age_s` if that
## is lower than the incoming voice's priority; otherwise drop the new sound.
##
## Every interval and every age here is measured on AudioClock (game seconds). On a wall clock a movie
## capture's 70 ms frames shrank a 200 ms accent interval to nothing and inflated steal ages ~4x.

const WORLD_VOICES := 40
const NEAR_VOICES := 12
const LOOP_VOICES := 6
const POLY_2D_VOICES := 24
const MAX_NEW_PER_TICK := 8
const STEAL_AGE_WEIGHT := 10.0
const PROTECTED_PRIORITY := 100.0

var _world: Array[AudioStreamPlayer3D] = []
var _near: Array[AudioStreamPlayer3D] = []
var _loop_players: Array[AudioStreamPlayer3D] = []
var _world_busy: Array[Dictionary] = []
var _near_busy: Array[Dictionary] = []
var _two_d: AudioStreamPlayer
var _two_d_playback: AudioStreamPlaybackPolyphonic
var _two_d_voices: Dictionary = {}   # polyphonic voice id -> {event_id, priority, started_at}
var _loop_by_id: Dictionary = {}     # StringName -> AudioStreamPlayer3D
var _last_played_at: Dictionary = {} # StringName -> AudioClock.now() seconds
var _new_this_tick: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_pools()


func _build_pools() -> void:
	for i in WORLD_VOICES - LOOP_VOICES:
		_world.append(_make_3d(&"World"))
		_world_busy.append({})
	for i in NEAR_VOICES:
		_near.append(_make_3d(&"Player"))
		_near_busy.append({})
	for i in LOOP_VOICES:
		_loop_players.append(_make_3d(&"World"))
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = POLY_2D_VOICES
	_two_d = AudioStreamPlayer.new()
	_two_d.name = "Poly2D"
	_two_d.bus = &"UI"
	_two_d.stream = poly
	_two_d.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_two_d)
	_two_d.play()
	_two_d_playback = _two_d.get_stream_playback() as AudioStreamPlaybackPolyphonic
	if _two_d_playback == null:
		push_error("AudioVoicePool: AudioStreamPolyphonic playback unavailable; 2D sounds muted")


func _make_3d(bus: StringName) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.bus = bus
	player.max_polyphony = 1     # we control stealing ourselves (dossier §5.6)
	player.area_mask = 0         # 4.7 default: no Area3D processing, zones are listener-side
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	AudioDistance.apply(player, 2)
	add_child(player)
	return player


func _physics_process(_delta: float) -> void:
	_new_this_tick = 0
	_retire_finished()


func _retire_finished() -> void:
	for slot in _world_busy.size():
		if not _world_busy[slot].is_empty() and not _world[slot].playing:
			_world_busy[slot] = {}
	for slot in _near_busy.size():
		if not _near_busy[slot].is_empty() and not _near[slot].playing:
			_near_busy[slot] = {}
	for voice_id in _two_d_voices.keys():
		if not _two_d_playback.is_stream_playing(voice_id):
			_two_d_voices.erase(voice_id)


## Voices of `event_id` currently sounding (2D, world, near and loops).
func active_count(event_id: StringName) -> int:
	var count := 0
	for slot in _world_busy:
		if slot.get("event_id", &"") == event_id:
			count += 1
	for slot in _near_busy:
		if slot.get("event_id", &"") == event_id:
			count += 1
	for voice in _two_d_voices.values():
		if voice["event_id"] == event_id:
			count += 1
	if _loop_by_id.has(event_id):
		count += 1
	return count


## True when this id may start now: per-event instance cap and minimum interval (dossier §3).
func budget_ok(event: SoundEvent) -> bool:
	if _new_this_tick >= MAX_NEW_PER_TICK:
		return false
	if event.min_interval_ms > 0:
		var last: float = _last_played_at.get(event.id, -1000000.0)
		if AudioClock.since(last) * 1000.0 < float(event.min_interval_ms):
			return false
	return event.max_instances <= 0 or active_count(event.id) < event.max_instances


func voice_stats() -> Dictionary:
	return {
		"world_free": _free_slot(_world_busy) >= 0,
		"world_used": _used_slots(_world_busy),
		"near_used": _used_slots(_near_busy),
		"two_d_used": _two_d_voices.size(),
		"loops": _loop_by_id.size(),
		"world_total": _world.size(),
		"near_total": _near.size(),
		"two_d_total": POLY_2D_VOICES,
		"loop_total": LOOP_VOICES,
	}


func _used_slots(busy: Array[Dictionary]) -> int:
	var count := 0
	for slot in busy:
		if not slot.is_empty():
			count += 1
	return count


func _free_slot(busy: Array[Dictionary]) -> int:
	for i in busy.size():
		if busy[i].is_empty():
			return i
	return -1


## Positional sound. `near` selects the hero's near-field pool (C0 events). Returns false when the
## pool dropped the sound (over budget), which callers treat as a normal outcome, not an error.
func play_3d(event: SoundEvent, stream: AudioStream, at: Vector3, volume_db: float, pitch: float,
		near: bool) -> bool:
	if not budget_ok(event):
		return false
	var players: Array[AudioStreamPlayer3D] = _near if near else _world
	var busy: Array[Dictionary] = _near_busy if near else _world_busy
	var slot := _free_slot(busy)
	if slot < 0:
		slot = _steal_slot(busy, event.priority)
		if slot < 0:
			return false
	var player := players[slot]
	AudioDistance.apply(player, event.distance_class)
	player.bus = event.bus
	player.stream = stream
	player.global_position = at
	player.volume_db = volume_db + event.volume_db
	player.pitch_scale = pitch
	player.play()
	busy[slot] = {"event_id": event.id, "priority": event.priority,
		"started_at": AudioClock.now()}
	_last_played_at[event.id] = AudioClock.now()
	_new_this_tick += 1
	return true


## Non-positional sound on the polyphonic 2D player (UI, voice, cockpit, stingers).
func play_2d(event: SoundEvent, stream: AudioStream, volume_db: float, pitch: float) -> bool:
	if _two_d_playback == null or not budget_ok(event):
		return false
	if _two_d_voices.size() >= POLY_2D_VOICES and not _steal_2d(event.priority):
		return false
	var voice_id := _two_d_playback.play_stream(stream, 0.0, volume_db + event.volume_db, pitch,
			AudioServer.PLAYBACK_TYPE_DEFAULT, event.bus)
	if voice_id < 0:
		return false
	_two_d_voices[voice_id] = {"event_id": event.id, "priority": event.priority,
		"started_at": AudioClock.now()}
	_last_played_at[event.id] = AudioClock.now()
	_new_this_tick += 1
	return true


## Start (or re-aim) a looping bed. Loop voices are never stolen; asking for a seventh loop warns.
func set_loop(event: SoundEvent, stream: AudioStream, at: Vector3, on: bool,
		volume_db: float = 0.0) -> void:
	if not on:
		if _loop_by_id.has(event.id):
			(_loop_by_id[event.id] as AudioStreamPlayer3D).stop()
			_loop_by_id.erase(event.id)
		return
	var player: AudioStreamPlayer3D = _loop_by_id.get(event.id)
	if player == null:
		player = _first_free_loop()
		if player == null:
			push_warning("AudioVoicePool: no loop voice free for '%s' (cap %d)"
					% [event.id, LOOP_VOICES])
			return
		_loop_by_id[event.id] = player
	AudioDistance.apply(player, event.distance_class)
	player.bus = event.bus
	player.stream = stream
	player.global_position = at
	player.volume_db = volume_db + event.volume_db
	if not player.playing:
		player.play()


func stop_all() -> void:
	for player in _world + _near + _loop_players:
		player.stop()
	for slot in _world_busy.size():
		_world_busy[slot] = {}
	for slot in _near_busy.size():
		_near_busy[slot] = {}
	for event_id in _loop_by_id.keys():
		_loop_by_id.erase(event_id)
	if _two_d_playback != null:
		for voice_id in _two_d_voices.keys():
			_two_d_playback.stop_stream(voice_id)
		_two_d_voices.clear()


func _first_free_loop() -> AudioStreamPlayer3D:
	var taken: Array = _loop_by_id.values()
	for player in _loop_players:
		if not taken.has(player):
			return player
	return null


func _steal_slot(busy: Array[Dictionary], incoming: float) -> int:
	var worst := -1
	var worst_score := incoming
	for i in busy.size():
		var slot: Dictionary = busy[i]
		if slot.is_empty() or slot["priority"] >= PROTECTED_PRIORITY:
			continue
		var score: float = slot["priority"] - STEAL_AGE_WEIGHT * AudioClock.since(slot["started_at"])
		if score < worst_score:
			worst_score = score
			worst = i
	return worst


func _steal_2d(incoming: float) -> bool:
	var worst_id := -1
	var worst_score := incoming
	for voice_id in _two_d_voices:
		var voice: Dictionary = _two_d_voices[voice_id]
		if voice["priority"] >= PROTECTED_PRIORITY:
			continue
		var score: float = float(voice["priority"]) \
				- STEAL_AGE_WEIGHT * AudioClock.since(voice["started_at"])
		if score < worst_score:
			worst_score = score
			worst_id = voice_id
	if worst_id < 0:
		return false
	_two_d_playback.stop_stream(worst_id)
	_two_d_voices.erase(worst_id)
	return true
