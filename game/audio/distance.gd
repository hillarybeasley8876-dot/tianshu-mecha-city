class_name AudioDistance
extends RefCounted
## The eight distance classes of ref/research/audio-music.md §5.4 and the attenuation maths the
## voice pool needs before a sound is spawned (priority falls 1 per 3 dB of predicted loss).
##
## C0 is near-field on the hero's sockets: attenuation disabled, mixed by the camera's orientation.

const SPEED_OF_SOUND := 343.0
const DISABLED := AudioStreamPlayer3D.ATTENUATION_DISABLED
const INVERSE := AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
const INVERSE_SQUARE := AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE

const CLASSES: Array[Dictionary] = [
	{"name": &"C0", "model": DISABLED, "unit": 1.0, "max_db": 0.0, "max_distance": 0.0,
		"filter_hz": 20500.0, "filter_db": 0.0, "panning": 0.35, "doppler": false},
	{"name": &"C1", "model": INVERSE, "unit": 6.0, "max_db": 0.0, "max_distance": 220.0,
		"filter_hz": 5000.0, "filter_db": -24.0, "panning": 1.0, "doppler": false},
	{"name": &"C2", "model": INVERSE, "unit": 20.0, "max_db": 3.0, "max_distance": 600.0,
		"filter_hz": 4000.0, "filter_db": -24.0, "panning": 1.0, "doppler": false},
	{"name": &"C3", "model": INVERSE, "unit": 45.0, "max_db": 3.0, "max_distance": 1100.0,
		"filter_hz": 3000.0, "filter_db": -30.0, "panning": 0.8, "doppler": false},
	{"name": &"C4", "model": INVERSE, "unit": 90.0, "max_db": 6.0, "max_distance": 2000.0,
		"filter_hz": 2500.0, "filter_db": -36.0, "panning": 0.6, "doppler": false},
	{"name": &"C5", "model": INVERSE, "unit": 200.0, "max_db": 6.0, "max_distance": 3000.0,
		"filter_hz": 2000.0, "filter_db": -36.0, "panning": 0.5, "doppler": false},
	{"name": &"C6", "model": INVERSE_SQUARE, "unit": 4.0, "max_db": 0.0, "max_distance": 60.0,
		"filter_hz": 6000.0, "filter_db": -12.0, "panning": 1.0, "doppler": false},
	{"name": &"C7", "model": INVERSE, "unit": 15.0, "max_db": 3.0, "max_distance": 400.0,
		"filter_hz": 5000.0, "filter_db": -24.0, "panning": 1.4, "doppler": true},
]


static func class_at(index: int) -> Dictionary:
	return CLASSES[clampi(index, 0, CLASSES.size() - 1)]


static func apply(player: AudioStreamPlayer3D, index: int) -> void:
	var klass: Dictionary = class_at(index)
	player.attenuation_model = klass["model"]
	player.unit_size = klass["unit"]
	player.max_db = klass["max_db"]
	player.max_distance = klass["max_distance"]
	player.attenuation_filter_cutoff_hz = klass["filter_hz"]
	player.attenuation_filter_db = klass["filter_db"]
	player.panning_strength = klass["panning"]
	# Doppler only on flyby sources: the listener's own speed would bend every static emitter
	# by up to +6.7 st (dossier §5.7).
	player.doppler_tracking = (AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
			if klass["doppler"] else AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED)


## Gain in dB that Godot will apply at `distance_m`, mirroring audio_stream_player_3d.cpp:
## inverse distance law capped at max_db, then the extra (1 - d/max_distance) fade.
static func gain_db(index: int, distance_m: float) -> float:
	var klass: Dictionary = class_at(index)
	if klass["model"] == DISABLED:
		return 0.0
	var unit: float = maxf(klass["unit"], 0.001)
	var d: float = maxf(distance_m, 0.001)
	var slope: float = 40.0 if klass["model"] == INVERSE_SQUARE else 20.0
	var gain: float = -slope * log(d / unit) / log(10.0)
	# max_db is a ceiling on the *gain*, so a source inside its unit_size never exceeds it.
	gain = minf(gain, klass["max_db"])
	var max_distance: float = klass["max_distance"]
	if max_distance > 0.0:
		if d >= max_distance:
			return -80.0
		gain += 20.0 * log(1.0 - d / max_distance) / log(10.0)
	return gain


## Positive dB lost at this distance; used to demote a voice's priority before it is spawned.
static func loss_db(index: int, distance_m: float) -> float:
	return maxf(-gain_db(index, distance_m), 0.0)


static func is_audible(index: int, distance_m: float) -> bool:
	var klass: Dictionary = class_at(index)
	var max_distance: float = klass["max_distance"]
	return max_distance <= 0.0 or distance_m < max_distance
