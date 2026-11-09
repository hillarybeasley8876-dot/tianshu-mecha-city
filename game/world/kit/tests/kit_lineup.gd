extends Node3D
## city-kit r8 — the cover line-up: one instance of every cover model, in the real city and under the
## real dusk environment, for the concept-fidelity sheet (lead r8 §4).
##
##   tools/godot.sh shot --scene=res://world/kit/tests/kit_lineup.tscn --out=r8lineup --env-only \
##       --warm=60 --times=9999 "--cams=$PWD/tools/citykit/cams_lineup.json"
##
## **Why a line-up and not the placed instances.** The sheet has to answer "does this model read like
## its concept", and the placed instances cannot answer it for the whole kit: k04 is never placed at
## all (a 25 m barrier cannot fill a 16-33 m cover box), and most of the rest sit under decks where a
## 15 m camera is in shadow behind another box. This puts all twelve in one clear row at the sky
## garden's height, lit by the same sun, with the same `McMaterials.kit` material the city uses.
##
## It is a LOOK-DEV rig and says so: the row is not a place the player can stand, and nothing here
## feeds the shipped scene. `kit_placer.setup`'s `assign` override is what makes that possible without
## touching `kit_assign.json`.

const PLACER := preload("res://world/kit/kit_placer.tscn")
const CITY_SCENE := "res://world/city.tscn"
const LINEUP := "res://world/kit/tests/lineup.json"
## `--lineup=res://...json` — a second row at a different yaw, for the lit-side pick in
## `tools/citykit/fidelity_sheet.py`.
var _path: String = LINEUP


func _ready() -> void:
	_path = _arg(OS.get_cmdline_user_args(), "--lineup=", LINEUP)
	var spec := _read()
	if spec.is_empty():
		push_error("KitLineup: no line-up at " + _path)
		get_tree().quit(1)
		return
	var packed := load(CITY_SCENE) as PackedScene
	if packed == null:
		push_error("KitLineup: cannot load " + CITY_SCENE)
		get_tree().quit(1)
		return
	add_child(packed.instantiate())
	var placer := PLACER.instantiate()
	add_child(placer)
	placer.call("setup", null, {}, _assign(spec))
	print("KitLineup: %d models at %s, spacing %.1f m"
			% [(spec.get("models", []) as Array).size(), spec.get("origin", []),
			float(spec.get("spacing", 0.0))])


static func _arg(args: PackedStringArray, flag: String, def: String) -> String:
	for a in args:
		if a.begins_with(flag):
			return a.substr(flag.length())
	return def


func _read() -> Dictionary:
	if not FileAccess.file_exists(_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	return parsed as Dictionary if parsed is Dictionary else {}


## One `cover` row per model, at the line-up's own positions. The placer's `_add_cover` is used rather
## than `_add_placement` so the pieces get the same near/far pair and the same material path they get
## in an arena.
func _assign(spec: Dictionary) -> Dictionary:
	var origin: Array = spec.get("origin", [0.0, 0.0, 0.0])
	var step := float(spec.get("spacing", 20.0))
	var rows: Array = []
	var yaw := float(spec.get("yaw", 0.0))
	# `yaws` is per model: the fidelity sheet turns each model to the side its own concept shows, and
	# one yaw for the whole row leaves a third of the kit back-lit.
	var yaws: Array = spec.get("yaws", [])
	var i := 0
	for m in spec.get("models", []):
		var y := float(yaws[i]) if i < yaws.size() else yaw
		rows.append({"id": "lineup_%s" % m, "kind": "cover", "model": String(m), "soft": false,
				"pieces": [{"pos": [float(origin[0]) + step * i, float(origin[1]),
						float(origin[2])], "yaw": y, "scale": [1.0, 1.0, 1.0]}]})
		i += 1
	return {"version": 1, "buildings": [], "pieces": [], "cover": rows, "far_lod": []}
