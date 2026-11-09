extends Node
## No absolute home path anywhere under `game/` (city-art r12 §3).
##
## Runtime code used to name the developer's home directory to reach `data/map/city_layout.json`,
## `data/map/kit_assign.json` and `data/vistas.json`. In an exported build those paths still open on the
## machine that made the build and nowhere else, so on any other Mac the roof dressing and the cargo
## blocks silently vanished — a missing file, not an error. This is the gate that keeps it from coming
## back, and it is deliberately blunt: ANY line under `game/` (outside the import cache) that contains
## the developer's home prefix fails, comments included, because a comment is where the next one starts.
##
## Run: tools/godot.sh test res://world/art/tests/test_no_abs_paths.gd

## The two spellings a macOS home path arrives in. Assembled at runtime so this file does not itself
## contain the literal it forbids.
const HOME_PREFIXES: Array[String] = ["/" + "Users" + "/", "/" + "home" + "/"]
## Never walked: the import cache (machine-specific by design) and VCS metadata.
const SKIP_DIRS: Array[String] = [".godot", ".git", ".import"]
## Only text the pack or the editor can carry a path in. Binaries (glb, png, wav) cannot.
const EXTS: Array[String] = ["gd", "tscn", "tres", "gdshader", "gdshaderinc", "json", "godot",
		"cfg", "import", "txt", "md", "csv"]

var _failures: int = 0
var _scanned: int = 0


func _ready() -> void:
	var root := ProjectSettings.globalize_path("res://")
	var hits := _walk(root)
	for hit: String in hits:
		print("FAIL %s" % hit)
		_failures += 1
	print("ABS PATHS scanned %d files under %s, %d absolute home paths"
			% [_scanned, root, hits.size()])
	print("ABS PATHS TEST %s" % ("FAIL" if _failures > 0 else "PASS"))
	get_tree().quit(1 if _failures > 0 else 0)


## Every offending `path:line: text` under `dir`, sorted so the report is stable between runs.
func _walk(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		push_error("test_no_abs_paths: cannot open %s" % dir)
		return out
	for sub in d.get_directories():
		if SKIP_DIRS.has(sub):
			continue
		out.append_array(_walk(dir.path_join(sub)))
	for file in d.get_files():
		if not EXTS.has(file.get_extension()):
			continue
		var path := dir.path_join(file)
		_scanned += 1
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		var lines := text.split("\n")
		for i in lines.size():
			for prefix in HOME_PREFIXES:
				if lines[i].contains(prefix):
					out.append("%s:%d: %s" % [path.trim_prefix(
							ProjectSettings.globalize_path("res://")), i + 1,
							lines[i].strip_edges()])
					break
	out.sort()
	return out
