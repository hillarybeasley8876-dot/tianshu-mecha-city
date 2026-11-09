class_name AudioMixer
extends Node
## Bus-level snapshots and listener zones (ref/research/audio-music.md §5.3), tweened in script.
##
## Zone reverb/delay live on the World bus rather than in Area3D volumes: in 4.7 an AudioStreamPlayer3D
## has area_mask 0 by default, and a reverb Area3D silences the player's own bus (#96480).

const ZONES: Dictionary = {
	&"rooftops": {"room": 0.35, "damping": 0.7, "wet": 0.05, "predelay": 60.0,
		"taps": [[300.0, -18.0]]},
	&"street": {"room": 0.6, "damping": 0.5, "wet": 0.12, "predelay": 40.0,
		"taps": [[117.0, -12.0], [233.0, -16.0]]},
	&"elevated": {"room": 0.5, "damping": 0.6, "wet": 0.08, "predelay": 50.0,
		"taps": [[180.0, -14.0], [320.0, -18.0]]},
	&"tunnel": {"room": 0.8, "damping": 0.3, "wet": 0.28, "predelay": 25.0,
		"taps": [[60.0, -9.0]]},
	&"spire": {"room": 0.55, "damping": 0.5, "wet": 0.08, "predelay": 50.0,
		"taps": [[250.0, -16.0]]},
}

const ZONE_FADE := 1.0
const OPEN_CUTOFF := 20500.0
const LOW_HP_CUTOFF := 8000.0
const CRITICAL_CUTOFF := 2500.0
const HURT_DIP_CUTOFF := 1200.0
const FIRST_PERSON_CUTOFF := 9000.0
const PAUSE_CUTOFF := 800.0
const WITCH_CUTOFF := 3500.0
## FEEL kill_large / boss_kill "world -6 dB" (docs/FEEL.md sound column).
const WORLD_DUCK_DB := -6.0
const WORLD_DUCK_OUT := 0.4

var zone: StringName = &"street"
var _world_bus: int = -1
var _lpf: AudioEffectLowPassFilter
var _reverb: AudioEffectReverb
var _delay: AudioEffectDelay
var _target_cutoff: float = OPEN_CUTOFF
var _first_person: bool = false
var _paused: bool = false
var _witch: bool = false
var _low_hp: float = 1.0
var _world_duck_tween: Tween = null
var _world_base_db: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cache_effects()
	apply_zone(zone, true)


func _cache_effects() -> void:
	_world_bus = AudioServer.get_bus_index(&"World")
	if _world_bus < 0:
		push_error("AudioMixer: no World bus; snapshots disabled")
		return
	var lpf_i := AudioBuses.find_effect(&"World", "AudioEffectLowPassFilter")
	var reverb_i := AudioBuses.find_effect(&"World", "AudioEffectReverb")
	var delay_i := AudioBuses.find_effect(&"World", "AudioEffectDelay")
	if lpf_i < 0 or reverb_i < 0 or delay_i < 0:
		push_error("AudioMixer: World bus is missing its filter/reverb/delay chain")
		return
	_lpf = AudioServer.get_bus_effect(_world_bus, lpf_i) as AudioEffectLowPassFilter
	_reverb = AudioServer.get_bus_effect(_world_bus, reverb_i) as AudioEffectReverb
	_delay = AudioServer.get_bus_effect(_world_bus, delay_i) as AudioEffectDelay


## Pick the zone from the listener height (SPEC §2 layers): trench, street, elevated, rooftops.
func zone_for_height(y: float) -> StringName:
	if y < -12.0:
		return &"tunnel"
	if y < 20.0:
		return &"street"
	if y < 70.0:
		return &"elevated"
	return &"rooftops"


func apply_zone(new_zone: StringName, immediate: bool = false) -> void:
	if not ZONES.has(new_zone) or _reverb == null:
		return
	zone = new_zone
	var data: Dictionary = ZONES[new_zone]
	var time := 0.0 if immediate else ZONE_FADE
	_tween_property(_reverb, "room_size", data["room"], time)
	_tween_property(_reverb, "damping", data["damping"], time)
	_tween_property(_reverb, "wet", data["wet"], time)
	_tween_property(_reverb, "predelay_msec", data["predelay"], time)
	var taps: Array = data["taps"]
	for i in 2:
		var active := i < taps.size()
		var delay_ms: float = taps[i][0] if active else 120.0
		var level_db: float = taps[i][1] if active else -60.0
		_tween_property(_delay, "tap%d_delay_ms" % (i + 1), delay_ms, time)
		_tween_property(_delay, "tap%d_level_db" % (i + 1), level_db, time)
	_delay.tap1_active = not taps.is_empty()
	_delay.tap2_active = taps.size() > 1


## HP ratio drives the muffled-world snapshot (juice §11.3).
func set_hp_ratio(ratio: float) -> void:
	_low_hp = ratio
	_refresh_cutoff()


func set_first_person(on: bool) -> void:
	_first_person = on
	_set_bus_volume(&"Player", 2.0 if on else 0.0)
	_set_bus_volume(&"Cockpit", 3.0 if on else 0.0)
	_refresh_cutoff()


func set_paused(on: bool) -> void:
	_paused = on
	_set_bus_volume(&"Master", -10.0 if on else 0.0)
	_refresh_cutoff()


func set_witch_time(on: bool) -> void:
	_witch = on
	_refresh_cutoff()


## FEEL hurt_heavy: World dips to 1.2 kHz for 400 ms, in 30 ms / out 400 ms (dossier §5.3).
func hurt_dip() -> void:
	if _lpf == null:
		return
	_lpf.cutoff_hz = HURT_DIP_CUTOFF
	var tween := create_tween()
	tween.tween_property(_lpf, "cutoff_hz", _cutoff_target(), 0.4).set_delay(0.03)


## FEEL kill_large / boss_kill: "world -6 dB" for `seconds`, then back in 400 ms. A volume duck, not
## the hurt_dip filter — the point is to make room under the kill, not to muffle it. World is the
## parent of Bed / Enemies / Player / Weapons / Impacts, so ducking it leaves Voice, UI, Cockpit and
## Music alone (they have their own sidechains). A duck already running keeps its baseline and is
## restarted; a finished one re-reads the bus, so a settings change in between is picked up.
func duck_world(db: float = WORLD_DUCK_DB, seconds: float = 0.5) -> void:
	var index := AudioServer.get_bus_index(&"World")
	if index < 0:
		return
	if _world_duck_tween != null and _world_duck_tween.is_valid():
		_world_duck_tween.kill()
	else:
		_world_base_db = AudioServer.get_bus_volume_db(index)
	var ducked := _world_base_db + db
	AudioServer.set_bus_volume_db(index, ducked)
	_world_duck_tween = create_tween()
	_world_duck_tween.tween_method(_set_world_db, ducked, _world_base_db, WORLD_DUCK_OUT)\
			.set_delay(seconds)


func _set_world_db(db: float) -> void:
	_set_bus_volume(&"World", db)


func _refresh_cutoff() -> void:
	if _lpf == null:
		return
	_lpf.cutoff_hz = _cutoff_target()


func _cutoff_target() -> float:
	var cutoff := OPEN_CUTOFF
	if _low_hp < 0.15:
		cutoff = CRITICAL_CUTOFF
	elif _low_hp < 0.3:
		cutoff = LOW_HP_CUTOFF
	if _first_person:
		cutoff = minf(cutoff, FIRST_PERSON_CUTOFF)
	if _witch:
		cutoff = minf(cutoff, WITCH_CUTOFF)
	if _paused:
		cutoff = PAUSE_CUTOFF
	return cutoff


func _set_bus_volume(bus: StringName, db: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, db)


func _tween_property(target: Object, property: String, value: Variant, time: float) -> void:
	if time <= 0.0:
		target.set(property, value)
		return
	create_tween().tween_property(target, property, value, time)


func snapshot() -> Dictionary:
	return {"zone": zone, "cutoff_hz": _lpf.cutoff_hz if _lpf else -1.0,
		"wet": _reverb.wet if _reverb else -1.0, "first_person": _first_person,
		"paused": _paused, "witch": _witch, "low_hp": _low_hp}
