class_name SoundEvent
extends Resource
## One sound id: which streams to pick from, where it sits in the mix, and how the voice pool
## budgets it. Rows come from game/audio/tables/*.gd; a `audio/events/<id>.tres` file overrides
## the row of the same id (the loader prefers the file when it exists).

## Filled in by the loader: the snake_case id this event answers to.
var id: StringName = &""
@export var streams: Array[AudioStream] = []
@export var bus: StringName = &"World"
## 0..7 -> C0 near-field .. C7 flyby (audio/distance.gd CLASSES).
@export var distance_class: int = 2
## 0..100; the voice pool steals the lowest `priority - 10 * age_s`.
@export var priority: float = 50.0
## Hard cap on simultaneous voices of this id.
@export var max_instances: int = 4
## Minimum spacing between two plays of this id, in milliseconds.
@export var min_interval_ms: int = 0
@export var volume_db: float = 0.0
@export var pitch_min: float = 1.0
@export var pitch_max: float = 1.0
## Played instead of `streams` beyond `far_switch_m`, and delayed by d/343 s when `far_delay`.
@export var far_variant: AudioStream = null
@export var far_switch_m: float = 500.0
@export var far_delay: bool = false
@export var loop: bool = false
## Hero socket for C0 events (muzzle_r, hand_r, wing_l, ...); empty = follow the player root.
@export var near_socket: StringName = &""


func is_valid() -> bool:
	return not streams.is_empty()


func pick_stream(rng: RandomNumberGenerator, distance_m: float) -> AudioStream:
	if far_variant != null and distance_m > far_switch_m:
		return far_variant
	if streams.size() == 1:
		return streams[0]
	return streams[rng.randi_range(0, streams.size() - 1)]


func pick_pitch(rng: RandomNumberGenerator) -> float:
	if is_equal_approx(pitch_min, pitch_max):
		return pitch_min
	return rng.randf_range(pitch_min, pitch_max)


static func from_row(event_id: StringName, row: Dictionary, loaded: Array[AudioStream],
		far: AudioStream) -> SoundEvent:
	var event := SoundEvent.new()
	event.id = event_id
	event.streams = loaded
	event.bus = row.get("bus", &"World")
	event.distance_class = row.get("class", 2)
	event.priority = row.get("prio", 50.0)
	event.max_instances = row.get("cap", 4)
	event.min_interval_ms = row.get("interval_ms", 0)
	event.volume_db = row.get("volume_db", 0.0)
	event.pitch_min = row.get("pitch_min", 1.0)
	event.pitch_max = row.get("pitch_max", 1.0)
	event.far_variant = far
	event.far_switch_m = row.get("far_switch_m", 500.0)
	event.far_delay = row.get("far_delay", false)
	event.loop = row.get("loop", false)
	event.near_socket = row.get("socket", &"")
	return event
