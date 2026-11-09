extends Node
## Audio (autoload). Owns the buses, the voice pool, the listener, the adaptive score and the
## mapping from gameplay events to sound ids, per CONTRACTS §3:
##   play(id, at, volume_db, pitch) / music_intensity(0..1) / stinger(id)
##
## Gameplay units never have to call Audio: every FEEL row and every Events signal is wired here.
## Extra helpers beyond the contract: play_loop, voice, stop_all, duck_for, debug_state.

const LOW_ARMOUR := 0.35  ## heartbeat threshold, shared with the HUD vignette (juice §11.3)
const CHEST_OFFSET := Vector3(0.0, 2.0, 0.0)
const LISTENER_CAMERA_BLEND := 0.2
const HP_POLL_INTERVAL := 0.25

var events: Dictionary = {}          # StringName -> SoundEvent
var pool: AudioVoicePool
var router: AudioEventRouter
var mixer: AudioMixer
var music: AudioMusicDirector
var voice_queue: AudioVoiceQueue

var _listener: AudioListener3D
var _rng := RandomNumberGenerator.new()
var _warned: Dictionary = {}
var _bound_signals: Array[StringName] = []
var _hp_timer: float = 0.0
var _intensity_target: float = 0.2
var _combat_heat: float = 0.0
## `--audio-trace`: count every id that resolved and asked for a voice, and print the tally at
## shutdown. A drive log is otherwise silent about what sounded, so a moment that *should* be
## audible cannot be told apart from one that silently resolved to nothing.
var _trace: bool = false
var _request_counts: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_trace = Game.has_flag("audio-trace")
	AudioBuses.build()
	var bank := AudioSoundBank.new()
	events = bank.build()
	pool = AudioVoicePool.new()
	pool.name = "VoicePool"
	add_child(pool)
	mixer = AudioMixer.new()
	mixer.name = "Mixer"
	add_child(mixer)
	music = AudioMusicDirector.new()
	music.name = "Music"
	add_child(music)
	voice_queue = AudioVoiceQueue.new()
	voice_queue.name = "VoiceQueue"
	voice_queue.emit_line = _speak
	voice_queue.line_sounding = _line_sounding
	add_child(voice_queue)
	router = AudioEventRouter.new()
	router.name = "EventRouter"
	router.setup(self)
	add_child(router)
	_create_listener()
	_connect_game()
	_connect_feel()
	_apply_settings()
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	play_loop(&"amb_street", true, Vector3.ZERO, -6.0)


func _create_listener() -> void:
	_listener = AudioListener3D.new()
	_listener.name = "Listener"
	# Listener doppler off: the hero's own 110 m/s assault boost would bend every static emitter
	# by up to +6.7 st (dossier §5.7). Flyby sources carry their own doppler instead.
	_listener.doppler_tracking = AudioListener3D.DOPPLER_TRACKING_DISABLED
	add_child(_listener)
	_listener.make_current()


func _connect_game() -> void:
	_bind(&"hit_landed", router.on_hit_landed)
	_bind(&"player_damaged", router.on_player_damaged)
	_bind(&"enemy_staggered", router.on_enemy_staggered)
	_bind(&"enemy_killed", router.on_enemy_killed)
	_bind(&"attack_blocked", router.on_attack_blocked)
	_bind(&"parry_success", router.on_parry_success)
	_bind(&"weapon_fired", router.on_weapon_fired)
	_bind(&"weapon_switched", router.on_weapon_switched)
	_bind(&"melee_swing", router.on_melee_swing)
	_bind(&"skill_used", router.on_skill_used)
	_bind(&"skill_ready", router.on_skill_ready)
	_bind(&"lock_changed", router.on_lock_changed)
	_bind(&"missiles_locked", router.on_missiles_locked)
	_bind(&"overdrive_changed", router.on_overdrive_changed)
	_bind(&"combo_changed", router.on_combo_changed)
	_bind(&"enemy_telegraph", router.on_enemy_telegraph)
	_bind(&"boost_started", router.on_boost_started)
	_bind(&"boost_ended", router.on_boost_ended)
	_bind(&"landed", router.on_landed)
	_bind(&"footstep", router.on_footstep)
	_bind(&"flight_changed", router.on_flight_changed)
	_bind(&"camera_mode_changed", router.on_camera_mode_changed)
	_bind(&"encounter_started", router.on_encounter_started)
	_bind(&"encounter_cleared", router.on_encounter_cleared)
	_bind(&"spire_destroyed", router.on_spire_destroyed)
	_bind(&"boss_intro", router.on_boss_intro)
	_bind(&"boss_phase", router.on_boss_phase)
	_bind(&"objective_changed", router.on_objective_changed)
	_bind(&"paused_changed", router.on_paused_changed)
	_bind(&"player_spawned", router.on_player_spawned)
	_bind(&"world_ready", router.on_world_ready)
	_bind(&"prime_collapsed", router.on_prime_collapsed)
	_bind(&"execution_ready", router.on_execution_ready)
	for signal_name in AudioEventMap.SIMPLE_SIGNALS:
		var id: StringName = AudioEventMap.SIMPLE_SIGNALS[signal_name]
		# A simple cue ignores the payload: drop exactly the signal's own arguments (perfect_dodge has one).
		var handler := router.on_simple.bind(id)
		var args := _arg_count(signal_name)
		_bind(signal_name, handler.unbind(args) if args > 0 else handler)


func _arg_count(signal_name: StringName) -> int:
	for info in Events.get_signal_list():
		if StringName(info["name"]) == signal_name:
			return (info["args"] as Array).size()
	return 0


func _bind(signal_name: StringName, handler: Callable) -> void:
	if not Events.has_signal(signal_name):
		push_error("Audio: Events has no signal '%s'" % signal_name)
		return
	Events.connect(signal_name, handler)
	_bound_signals.append(signal_name)


func _connect_feel() -> void:
	if not Feel.event_requested.is_connected(router.on_feel_event):
		Feel.event_requested.connect(router.on_feel_event)
	if not Feel.witch_time_changed.is_connected(mixer.set_witch_time):
		Feel.witch_time_changed.connect(mixer.set_witch_time)


# --- public API (CONTRACTS §3) -------------------------------------------------------------------
func play(id: StringName, at: Vector3 = Vector3.INF, volume_db: float = 0.0,
		pitch: float = 1.0) -> void:
	var event: SoundEvent = resolve(id)
	if event == null:
		warn_once(id)
		return
	if not event.is_valid():
		warn_once(id)
		return
	if event.loop:
		play_loop(id, true, at, volume_db)
		return
	var near_field := event.distance_class == 0
	var position := _resolve(at, event)
	_trace_request(event.id)
	var stream := event.pick_stream(_rng, _listener_pos().distance_to(position))
	var final_pitch := pitch * event.pick_pitch(_rng)
	if at == Vector3.INF and not near_field:
		pool.play_2d(event, stream, volume_db, final_pitch)
		return
	var distance := _listener_pos().distance_to(position)
	if not AudioDistance.is_audible(event.distance_class, distance):
		return
	# The far layer of a big event arrives d/343 s late: the flash-boom gap that sells city scale.
	var delay := clampf((distance - 120.0) / AudioDistance.SPEED_OF_SOUND, 0.0, 2.5)
	if event.far_delay and delay > 0.0:
		get_tree().create_timer(delay, true, false, true).timeout.connect(
				_play_delayed.bind(event, stream, position, volume_db, final_pitch))
		return
	pool.play_3d(event, stream, position, volume_db, final_pitch, near_field)


func _play_delayed(event: SoundEvent, stream: AudioStream, at: Vector3, volume_db: float,
		pitch: float) -> void:
	pool.play_3d(event, stream, at, volume_db, pitch, false)


func play_loop(id: StringName, on: bool, at: Vector3 = Vector3.INF, volume_db: float = 0.0) -> void:
	var event: SoundEvent = resolve(id)
	if event == null or not event.is_valid():
		warn_once(id)
		return
	_trace_request(event.id)
	pool.set_loop(event, event.pick_stream(_rng, 0.0), _resolve(at, event), on, volume_db)


func music_intensity(level: float) -> void:
	_intensity_target = clampf(level, 0.0, 1.0)
	# An explicit request is authoritative (CONTRACTS §3: the flow unit drives the score from the
	# encounter state). Combat heat is only a *supplement* that keeps the score up between flow
	# updates, so it is clamped to what was just asked for — otherwise a single `add_heat(1.0)` from a
	# boss intro held the score at boss for the 12 s it takes to decay, over a later
	# `music_intensity(0.2)`. `add_heat` still lifts it again on the next hit or kill.
	_combat_heat = minf(_combat_heat, _intensity_target)
	music.set_intensity(maxf(_intensity_target, _combat_heat))


func stinger(id: StringName) -> void:
	music.stinger(id)


## Cockpit AI line through the priority queue (dossier §1.5: one at a time, no repeat within 8 s).
func voice(line_id: StringName, priority: float = 50.0, length_s: float = 1.2) -> void:
	voice_queue.request(line_id, priority, length_s)


func stop_all() -> void:
	pool.stop_all()
	voice_queue.clear()


func bound_signal_names() -> Array[StringName]:
	return _bound_signals.duplicate()


## How many times each id resolved and asked the pool for a voice this run (`--audio-trace`). These
## are REQUESTS, counted before the pool's cap / min-interval budget, so a high count does not mean
## that many voices: `heartbeat_loop` is re-requested every HP poll and `hurt_light` is rate-limited.
func request_counts() -> Dictionary:
	return _request_counts.duplicate()


func _trace_request(id: StringName) -> void:
	if _trace:
		_request_counts[id] = int(_request_counts.get(id, 0)) + 1


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or _request_counts.is_empty():
		return
	var rows: Array[String] = []
	for id in _request_counts:
		rows.append("%s=%d" % [id, _request_counts[id]])
	rows.sort()
	print("AUDIOTRACE %d ids requested %s" % [rows.size(), " ".join(rows)])


## Follows AudioTableAliases so a layer id from another unit lands on the mixed event (see the
## alias table's header). The returned event keeps the *target* id, so the voice pool's cap counts
## a row once no matter how many layer ids asked for it.
func resolve(id: StringName) -> SoundEvent:
	var target: StringName = AudioTableAliases.ALIASES.get(id, id)
	var event: SoundEvent = events.get(target)
	if event == null and target != id:
		return events.get(id)
	return event


func listener_position() -> Vector3:
	return _listener_pos()


func chest_position() -> Vector3:
	return _chest_position()


func debug_state() -> Dictionary:
	return {"voices": pool.voice_stats(), "mixer": mixer.snapshot(), "music": music.state(),
		"voice_queue": voice_queue.state(), "events": events.size(),
		"bound_signals": _bound_signals.size(), "listener": _listener_pos()}


# --- internals --------------------------------------------------------------------------------------
func _resolve(at: Vector3, event: SoundEvent) -> Vector3:
	if at != Vector3.INF:
		return at
	if event.distance_class == 0 and event.near_socket != &"":
		var socket := _socket_position(event.near_socket)
		if socket != Vector3.INF:
			return socket
	return _chest_position()


func _listener_pos() -> Vector3:
	return _listener.global_position if _listener else Vector3.ZERO


func _chest_position() -> Vector3:
	var player := _player()
	return player.global_position + CHEST_OFFSET if player else Vector3.ZERO


func _player() -> Node3D:
	var player: Node = Game.player if Game else null
	return player as Node3D


func _socket_position(socket_name: StringName) -> Vector3:
	var player := _player()
	if player == null or not player.has_method("model"):
		return Vector3.INF
	var model: Node = player.call("model")
	if model == null or not model.has_method("socket"):
		return Vector3.INF
	var node: Node = model.call("socket", socket_name)
	return (node as Node3D).global_position if node is Node3D else Vector3.INF


func _speak(line_id: StringName) -> bool:
	var event: SoundEvent = events.get(line_id)
	if event == null or not event.is_valid():
		warn_once(line_id)
		return false
	return pool.play_2d(event, event.streams[0], 0.0, 1.0)


## Still talking? The queue holds the speaker until the pool says the stream actually stopped, so a
## long line never gets talked over (audio/voice_queue.gd `_busy`).
func _line_sounding(line_id: StringName) -> bool:
	return pool != null and pool.active_count(line_id) > 0


func warn_once(id: StringName) -> void:
	if _warned.has(id):
		return
	_warned[id] = true
	push_warning("Audio: unknown or empty sound id '%s'" % id)


func _apply_settings() -> void:
	_set_bus_db(&"Master", AudioBuses.MASTER_TRIM_DB + float(Settings.get_value(&"master_volume_db")))
	_set_bus_db(&"Music", Settings.get_value(&"music_volume_db"))
	_set_bus_db(&"Stinger", Settings.get_value(&"music_volume_db"))
	for bus in [&"World", &"Bed", &"Enemies", &"Player", &"Weapons", &"Impacts"]:
		_set_bus_db(bus, Settings.get_value(&"sfx_volume_db"))


func _on_setting_changed(key: StringName) -> void:
	if String(key).ends_with("volume_db"):
		_apply_settings()


func _set_bus_db(bus: StringName, db: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, db)


# --- per-frame ---------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	_track_listener()
	_hp_timer += delta
	if _hp_timer >= HP_POLL_INTERVAL:
		_hp_timer = 0.0
		_poll_player_state()
	_decay_combat_heat(delta)


## Panning from the camera, attenuation from the chest (dossier §5.5): with the camera 26 m back, a
## camera-positioned listener would push every hero sound away.
func _track_listener() -> void:
	if _listener == null:
		return
	var camera := get_viewport().get_camera_3d()
	var chest := _chest_position()
	if camera == null:
		_listener.global_position = chest
		return
	var blended := chest.lerp(camera.global_position, LISTENER_CAMERA_BLEND)
	_listener.global_transform = Transform3D(camera.global_basis, blended)
	var zone := mixer.zone_for_height(blended.y)
	if zone != mixer.zone:
		mixer.apply_zone(zone)


func _poll_player_state() -> void:
	var player := _player()
	if player == null:
		return
	var ratio := 1.0
	if "hp" in player and "hp_max" in player and float(player.hp_max) > 0.0:
		ratio = float(player.hp) / float(player.hp_max)
	mixer.set_hp_ratio(ratio)
	play_loop(&"heartbeat_loop", ratio < LOW_ARMOUR, Vector3.INF, -4.0)
	if ratio < 0.25:
		voice(&"ai_armor_critical", 90.0, 1.4)
	elif ratio < 0.5:
		voice(&"ai_armor_50", 60.0, 1.2)


## Combat heat: recent fighting keeps the score up even if the flow unit has not set intensity yet.
func _decay_combat_heat(delta: float) -> void:
	_combat_heat = maxf(_combat_heat - delta * 0.08, 0.0)
	music.set_intensity(maxf(_intensity_target, _combat_heat))


func add_combat_heat(amount: float) -> void:
	_combat_heat = clampf(maxf(_combat_heat, amount), 0.0, 1.0)
