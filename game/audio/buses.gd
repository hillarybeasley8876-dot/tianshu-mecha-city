class_name AudioBuses
extends RefCounted
## Bus layout and ducking of ref/research/audio-music.md §5.1-5.2, built at runtime.
##
## Index order is load-bearing twice over: a bus may only *send* to a lower index, and buses are
## mixed from the highest index down, so a sidechain key must sit to the RIGHT of the bus it ducks.

## Master trim, calibrated by measuring a busy capture with ffmpeg ebur128 (dossier §5.9): the raw
## bank mixes to about -17 LUFS under sustained fire, and the target is -23 LUFS.
const MASTER_TRIM_DB := -5.0

const LAYOUT: Array[Dictionary] = [
	{"name": &"Master", "send": &"", "effects": ["limiter"]},
	{"name": &"Music", "send": &"Master", "effects": ["duck_voice_music", "duck_impacts_music"]},
	{"name": &"Stinger", "send": &"Music", "effects": []},
	{"name": &"UI", "send": &"Master", "effects": []},
	{"name": &"World", "send": &"Master", "effects": ["world_lpf", "zone_reverb", "zone_delay"]},
	{"name": &"Bed", "send": &"World", "effects": ["duck_impacts_bed", "duck_voice_bed"]},
	{"name": &"Enemies", "send": &"World", "effects": ["duck_impacts_enemies"]},
	{"name": &"Player", "send": &"World", "effects": []},
	{"name": &"Weapons", "send": &"World", "effects": ["glue_weapons"]},
	{"name": &"Impacts", "send": &"World", "effects": ["glue_impacts"]},
	{"name": &"Voice", "send": &"Master", "effects": ["voice_hpf", "voice_comp"]},
	{"name": &"Cockpit", "send": &"Master", "effects": []},
]

## Godot's compressor reduces gain by ~2.08x the textbook amount (dossier §5.2, measured), so each
## threshold below is tuned for the target reduction in the comment, not for the textbook value.
const SIDE_CHAINS := {
	"duck_voice_music": {"key": &"Voice", "threshold": -14.0, "ratio": 4.0, "target": 7.0},
	"duck_impacts_music": {"key": &"Impacts", "threshold": -8.0, "ratio": 2.0, "target": 3.0},
	"duck_impacts_bed": {"key": &"Impacts", "threshold": -10.0, "ratio": 3.0, "target": 8.0},
	"duck_voice_bed": {"key": &"Voice", "threshold": -14.0, "ratio": 2.0, "target": 4.0},
	"duck_impacts_enemies": {"key": &"Impacts", "threshold": -10.0, "ratio": 2.0, "target": 3.0},
}


static func build() -> void:
	_reset()
	AudioServer.set_bus_volume_db(0, MASTER_TRIM_DB)
	for i in LAYOUT.size():
		var row: Dictionary = LAYOUT[i]
		var index := 0 if i == 0 else AudioServer.bus_count
		if i > 0:
			AudioServer.add_bus()
		AudioServer.set_bus_name(index, row["name"])
		AudioServer.set_bus_send(index, row["send"] if row["send"] != &"" else &"Master")
		if row["name"] == &"Master":
			AudioServer.set_bus_send(index, &"")
		for effect_id in row["effects"]:
			_add_effect(index, effect_id)


static func _reset() -> void:
	AudioServer.lock()
	for i in range(AudioServer.bus_count - 1, 0, -1):
		AudioServer.remove_bus(i)
	var master := AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_name(master, &"Master")
	AudioServer.set_bus_send(master, &"")
	AudioServer.unlock()


static func _add_effect(bus: int, effect_id: String) -> void:
	var effect := _make_effect(effect_id)
	if effect == null:
		push_error("AudioBuses: unknown effect '%s'" % effect_id)
		return
	AudioServer.add_bus_effect(bus, effect)


static func _make_effect(effect_id: String) -> AudioEffect:
	if SIDE_CHAINS.has(effect_id):
		var chain: Dictionary = SIDE_CHAINS[effect_id]
		var comp := AudioEffectCompressor.new()
		comp.sidechain = chain["key"]
		comp.threshold = chain["threshold"]
		comp.ratio = chain["ratio"]
		comp.attack_us = 1000.0 if chain["key"] == &"Impacts" else 2000.0
		comp.release_ms = 350.0 if chain["key"] == &"Impacts" else 500.0
		return comp
	match effect_id:
		"limiter":
			var limiter := AudioEffectHardLimiter.new()
			limiter.ceiling_db = -1.0
			limiter.pre_gain_db = 0.0
			limiter.release = 0.10
			return limiter
		"world_lpf":
			var lpf := AudioEffectLowPassFilter.new()
			lpf.cutoff_hz = 20500.0
			return lpf
		"zone_reverb":
			var reverb := AudioEffectReverb.new()
			reverb.room_size = 0.5
			reverb.damping = 0.5
			reverb.wet = 0.08
			reverb.predelay_msec = 50.0
			reverb.dry = 1.0
			return reverb
		"zone_delay":
			var delay := AudioEffectDelay.new()
			delay.tap1_delay_ms = 117.0
			delay.tap1_level_db = -12.0
			delay.tap2_delay_ms = 233.0
			delay.tap2_level_db = -16.0
			delay.dry = 1.0
			return delay
		"glue_weapons":
			return _glue(-8.0, 2.0, 20.0, 80.0)
		"glue_impacts":
			return _glue(-6.0, 3.0, 20.0, 120.0)
		"voice_hpf":
			var hpf := AudioEffectHighPassFilter.new()
			hpf.cutoff_hz = 140.0
			return hpf
		"voice_comp":
			return _glue(-20.0, 3.0, 500.0, 150.0)
	return null


static func _glue(threshold: float, ratio: float, attack_us: float,
		release_ms: float) -> AudioEffectCompressor:
	var comp := AudioEffectCompressor.new()
	comp.threshold = threshold
	comp.ratio = ratio
	comp.attack_us = attack_us
	comp.release_ms = release_ms
	return comp


static func find_effect(bus_name: StringName, effect_class: String) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return -1
	for i in AudioServer.get_bus_effect_count(index):
		if AudioServer.get_bus_effect(index, i).get_class() == effect_class:
			return i
	return -1
