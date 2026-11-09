class_name FlowEncounterWaves
extends RefCounted
## Reads and validates `res://flow/encounters/<arena>.json` (brief §2). The tables live inside the
## project so an exported build carries them (lead r1 must-fix 1); they are read with `FileAccess` on
## the `res://` path exactly like `world/city.gd` reads its layout.
##
## A wave is: `id`, `start` (when it begins) and `groups` (what it spawns where).
## ```
## {"id": "A1_w2", "start": {"kind": "previous_half"},
##  "groups": [{"type": "ripper", "count": 6, "socket": "A1_sp2", "escalate": true}]}
## ```
## `start.kind` is `on_enter` (the arena trigger), `previous_half` (half the previous wave is dead —
## the Insomniac overlap of dossier rule 6), `previous_cleared`, or `timer` with `"delay"` seconds on
## the world clock. A malformed row is reported once with the file and the wave id, never silently
## skipped.

const DIR := "res://flow/encounters/"
const START_KINDS: Array[StringName] = [&"on_enter", &"previous_half", &"previous_cleared", &"timer"]
## Count growth per destroyed spire for groups marked `escalate` (SPEC §8: the district gets worse).
const PER_SPIRE := 0.25
## Metres the monsters of one group are spread over around their socket, so a pack arrives as a
## front rather than a stack (dossier §4.5: spawns near each sub-space, spread across it).
const GROUP_SPREAD := 22.0

static var _cache: Dictionary = {}
static var _warned: Dictionary = {}


## The whole arena table, cached. Empty when the file is missing (warned once).
static func load_arena(arena_id: StringName) -> Dictionary:
	if _cache.has(arena_id):
		return _cache[arena_id]
	var path := DIR + String(arena_id) + ".json"
	var out: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			out = _validate(parsed as Dictionary, arena_id)
		else:
			_warn(arena_id, "not a JSON object")
	else:
		_warn(arena_id, "no file at " + path)
	_cache[arena_id] = out
	return out


static func waves(arena_id: StringName) -> Array[Dictionary]:
	return load_arena(arena_id).get("waves", []) as Array[Dictionary]


static func label(arena_id: StringName) -> String:
	return String(load_arena(arena_id).get("label", String(arena_id)))


## Enemy count of a group after escalation for `spires_down` destroyed spires.
static func group_count(group: Dictionary, spires_down: int) -> int:
	var base := int(group.get("count", 0))
	if not bool(group.get("escalate", false)) or spires_down <= 0:
		return base
	return base + int(round(float(base) * PER_SPIRE * float(spires_down)))


static func _validate(raw: Dictionary, arena_id: StringName) -> Dictionary:
	var waves_out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for row: Variant in raw.get("waves", []):
		var w := row as Dictionary
		if w == null:
			continue
		var id := String(w.get("id", ""))
		if id == "" or seen.has(id):
			_warn(arena_id, "wave with a missing or duplicate id '%s'" % id)
			continue
		var start := _start_of(w.get("start", {}) as Dictionary, id, arena_id)
		if start.is_empty():
			continue
		var groups := _groups_of(w.get("groups", []), id, arena_id)
		if groups.is_empty():
			continue
		seen[id] = true
		waves_out.append({"id": StringName(id), "start": start, "groups": groups})
	return {"arena": StringName(raw.get("arena", arena_id)), "label": String(raw.get("label", "")),
			"music": float(raw.get("music", 0.5)), "waves": waves_out}


static func _start_of(start: Dictionary, wave_id: String, arena_id: StringName) -> Dictionary:
	var kind := StringName(start.get("kind", "on_enter"))
	if kind not in START_KINDS:
		_warn(arena_id, "wave '%s' has start kind '%s'" % [wave_id, kind])
		return {}
	return {"kind": kind, "delay": float(start.get("delay", 0.0))}


static func _groups_of(rows: Variant, wave_id: String, arena_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Variant in rows as Array:
		var g := row as Dictionary
		if g == null:
			continue
		var type := StringName(g.get("type", ""))
		if not EnemyTypes.is_type(type):
			_warn(arena_id, "wave '%s' wants unknown enemy type '%s'" % [wave_id, type])
			continue
		out.append({"type": type, "count": maxi(int(g.get("count", 0)), 0),
				"socket": StringName(g.get("socket", "")),
				"escalate": bool(g.get("escalate", false))})
	return out


static func _warn(arena_id: StringName, message: String) -> void:
	var key := "%s: %s" % [arena_id, message]
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("FlowEncounterWaves: %s" % key)


## Test hook: forget the parsed files so a test can rewrite one and reload it.
static func reset_cache() -> void:
	_cache.clear()
	_warned.clear()
