extends Node
## `world/city/design_layout.json` is the design layout the runtime reads (city-art r12 §3).
##
## `data/map/city_layout.json` is outside `res://`, so the Blender build copies the rows Godot needs
## into the project beside `layout.json` (`blender/city/markers.py`). A hand-made copy would go stale
## the first time the layout moved; this is the gate that says so. It compares the md5 the copy records
## of the file it came from against that file now, and it only runs where `data/` exists at all — an
## exported build has no repo and is not the thing being checked.
##
## Run: tools/godot.sh test res://world/art/tests/test_design_copy.gd
## Refresh: tools/blender.sh run blender/city/markers.py

const COPY := "res://world/city/design_layout.json"
## Keys the Godot side actually reads. A copy that lost one of them is a copy that does not work.
const WANTED: Array[String] = ["buildings", "decks", "streets", "landmarks", "arenas"]

var _failures: int = 0


func _ready() -> void:
	var source := ArtRepo.data("map/city_layout.json")
	if not FileAccess.file_exists(source):
		print("DESIGN COPY no %s in this checkout — nothing to compare (skipped)" % source)
		_report(true)
		return
	if not FileAccess.file_exists(COPY):
		_fail("no %s — run tools/blender.sh run blender/city/markers.py" % COPY)
		_report(false)
		return
	var copy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(COPY))
	if copy.is_empty():
		_fail("%s is not a JSON object" % COPY)
		_report(false)
		return
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	for key in WANTED:
		var want: int = (original.get(key, []) as Array).size()
		var got: int = (copy.get(key, []) as Array).size()
		if got != want:
			_fail("%s has %d `%s` rows, %s has %d" % [COPY, got, key, source, want])
	var stamped := String((copy.get("meta", {}) as Dictionary).get("source_md5", ""))
	var now := FileAccess.get_md5(source)
	if stamped != now:
		_fail("%s was copied from a different %s (stamp %s, now %s) — run "
				% [COPY, source, stamped.substr(0, 8), now.substr(0, 8)]
				+ "tools/blender.sh run blender/city/markers.py")
	_report(_failures == 0)


func _fail(msg: String) -> void:
	print("FAIL %s" % msg)
	_failures += 1


func _report(ok: bool) -> void:
	print("DESIGN COPY TEST %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
