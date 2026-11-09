class_name AudioSoundBank
extends RefCounted
## Turns the row tables in audio/tables/*.gd into SoundEvent resources and loads their streams.
##
## Streams are found by name (export-safe, no directory scan): `res://audio/<dir>/<id>.<ext>` when
## there is one variant, `<id>_01.._NN` otherwise. A `res://audio/events/<id>.tres` file, if present,
## replaces the generated event so a designer can override one id without touching the tables.

const TABLE_PATHS: Array[String] = [
	"res://audio/tables/table_hero.gd", "res://audio/tables/table_weapons.gd",
	"res://audio/tables/table_melee.gd", "res://audio/tables/table_skills.gd",
	"res://audio/tables/table_enemies.gd", "res://audio/tables/table_world.gd",
]

var events: Dictionary = {}     # StringName -> SoundEvent
var missing: Array[StringName] = []


static func all_rows() -> Dictionary:
	var rows: Dictionary = {}
	for path in TABLE_PATHS:
		var table: GDScript = load(path)
		var table_rows: Dictionary = table.rows()
		for key in table_rows:
			if rows.has(key):
				push_error("AudioSoundBank: duplicate sound id '%s'" % key)
			rows[key] = table_rows[key]
	return rows


func build() -> Dictionary:
	var rows := all_rows()
	for id in rows:
		var override := _load_override(id)
		if override != null:
			override.id = id
			events[id] = override
			continue
		var row: Dictionary = rows[id]
		var streams := _load_streams(id, row)
		if streams.is_empty():
			missing.append(id)
			continue
		var far: AudioStream = null
		if row.has("far"):
			var far_streams := _load_streams(StringName(row["far"]), rows.get(row["far"], row))
			far = far_streams[0] if not far_streams.is_empty() else null
		var event := SoundEvent.from_row(id, row, streams, far)
		event.far_delay = row.get("far_delay", false)
		events[id] = event
	if not missing.is_empty():
		push_warning("AudioSoundBank: %d ids have no stream files: %s"
				% [missing.size(), missing.slice(0, 8)])
	return events


func _load_override(id: StringName) -> SoundEvent:
	var path := "res://audio/events/%s.tres" % id
	if not ResourceLoader.exists(path):
		return null
	var resource := ResourceLoader.load(path)
	if resource is SoundEvent:
		return resource
	push_warning("AudioSoundBank: %s is not a SoundEvent, ignored" % path)
	return null


func _load_streams(id: StringName, row: Dictionary) -> Array[AudioStream]:
	var folder: String = "res://audio/%s/" % row.get("dir", "sfx")
	var ext: String = row.get("ext", "wav")
	var variants: int = row.get("variants", 1)
	var loop: bool = row.get("loop", false)
	var streams: Array[AudioStream] = []
	if variants <= 1:
		_append(streams, "%s%s.%s" % [folder, id, ext], loop)
	else:
		for i in variants:
			_append(streams, "%s%s_%02d.%s" % [folder, id, i + 1, ext], loop)
	return streams


func _append(streams: Array[AudioStream], path: String, loop: bool) -> void:
	if not ResourceLoader.exists(path):
		push_warning("AudioSoundBank: missing stream %s" % path)
		return
	var stream := ResourceLoader.load(path)
	if stream is AudioStream:
		streams.append(_prepare(stream, loop))
	else:
		push_error("AudioSoundBank: %s is not an AudioStream" % path)


## Loop points: the WAV importer defaults to loop_mode 0 ("detect from WAV"), so looped beds are
## forced to forward looping over the whole file here. Ours are seamless by construction
## (integer cycle counts or a tail crossfaded into the head), so the whole file is the loop.
static func _prepare(stream: AudioStream, loop: bool) -> AudioStream:
	if loop:
		if stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = 0
		elif stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
	return stream
