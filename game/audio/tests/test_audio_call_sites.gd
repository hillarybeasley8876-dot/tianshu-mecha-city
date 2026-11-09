extends Node
## Call-site audit: every literal sound id another unit passes to the Audio autoload must resolve.
##
## `Audio.play(&"…")` warns once per unknown id and then plays nothing, so a typo or a renamed bank
## row silently mutes a moment for the whole game (reviews/audio-r5.md). This walks every .gd under
## res:// (skipping tests and the import cache) and fails on any id the bank cannot answer.
##
## Runnable on its own (`tools/godot.sh test res://audio/tests/test_audio_call_sites.gd`) and run by
## test_audio.gd, whose failure count it adds to.

const SKIP_DIRS: Array[String] = ["tests", ".godot", "addons", ".git"]
## Outside res://audio/ only the autoload's own calls count; inside it the router calls its own
## `play(&"…")` helper, so the `Audio.` prefix is optional there.
const CALL_OUTSIDE := "Audio\\.(play|play_loop|voice|stinger)\\(&\"([a-z0-9_]+)\""
const CALL_INSIDE := "(?<![A-Za-z0-9_])(?:Audio\\.)?(play|play_loop|voice|stinger)\\(&\"([a-z0-9_]+)\""

var fails: int = 0


func _ready() -> void:
	if get_parent() != get_tree().root:
		return   # driven by test_audio.gd
	await get_tree().process_frame
	run_checks()
	print("TEST audio call sites: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


## Returns the number of failures so a parent suite can add them (test_audio.gd).
func run_checks() -> int:
	var sites := scan()
	var bad: Array[String] = []
	for site in sites:
		var verdict := _verdict(site["method"], site["id"])
		if verdict != "":
			bad.append("%s:%d %s(&\"%s\") -> %s"
					% [site["file"], site["line"], site["method"], site["id"], verdict])
	print("call sites scanned: %d" % sites.size())
	for row in sites:
		print("  %s:%d %s(&\"%s\")" % [row["file"], row["line"], row["method"], row["id"]])
	_check(bad.is_empty(), "every Audio call-site id resolves (%d unresolved)" % bad.size())
	for line in bad:
		print("  UNRESOLVED %s" % line)
	return fails


func _check(ok: bool, msg: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", msg])
	if not ok:
		fails += 1


## "" when the id is answerable, otherwise why it is not.
func _verdict(method: String, id: StringName) -> String:
	match method:
		"stinger":
			var path := AudioMusicDirector.MUSIC_DIR + "stingers/%s.ogg" % id
			return "" if ResourceLoader.exists(path) else "no stinger file at %s" % path
		"voice":
			return "" if Audio.events.has(id) else "not in the bank (voice lines resolve directly)"
		_:
			var event: SoundEvent = Audio.resolve(id)
			if event == null:
				return "Audio.resolve() returned null"
			return "" if event.is_valid() else "resolved to an event with no streams"


# --- scanning ---------------------------------------------------------------------------------------
func scan() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_walk("res://", out)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["file"] != b["file"]:
				return String(a["file"]) < String(b["file"])
			return int(a["line"]) < int(b["line"]))
	return out


func _walk(dir_path: String, out: Array[Dictionary]) -> void:
	# DirAccess is fine here: this file only ever runs from source under tools/godot.sh test, never
	# from an exported build (runtime code uses ResourceLoader.list_directory instead).
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("AudioCallSites: cannot open %s" % dir_path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not SKIP_DIRS.has(entry):
				_walk(full, out)
		elif entry.ends_with(".gd"):
			_scan_file(full, out)
		entry = dir.get_next()
	dir.list_dir_end()


func _scan_file(path: String, out: Array[Dictionary]) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return
	var inside := path.begins_with("res://audio/")
	var regex := RegEx.new()
	regex.compile(CALL_INSIDE if inside else CALL_OUTSIDE)
	var lines := text.split("\n")
	for i in lines.size():
		for result in regex.search_all(lines[i]):
			out.append({"file": path, "line": i + 1, "method": result.get_string(1),
					"id": StringName(result.get_string(2))})
