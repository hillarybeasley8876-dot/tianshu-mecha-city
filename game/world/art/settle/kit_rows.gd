class_name KitRows
extends RefCounted
## Which `kit_assign.json` row a placed kit instance came from (city-art r10b).
##
## The settle pass used to move and drop kit pieces that are STRUCTURE — deck slabs, viaduct pylons,
## arena cover — whose collider city-build builds from the same layout box. A visual that moves or
## vanishes while its collider stays makes invisible walls, invisible floors and holes, so those
## batches are no longer settled. What replaces the gate is a REPORT: every structure instance off its
## surface by more than 0.5 m, named by the row that placed it, so the bug can be fixed in the rule that
## placed it (`tools/citykit/pieces.py`, `cover.py`) instead of patched at load.
##
## `kit_placer.gd` is city-kit's and keeps no row ids, so the mapping is rebuilt here from the same
## file it reads, by position: Blender (x, y, z-up) -> Godot (x, z, -y), the placer's own conversion.

const PATH := "res://world/kit/kit_assign.json"
## The design layout keeps the decks the runtime one drops. `ArtRepo.design_layout()` is the `res://`
## copy the Blender build writes beside `layout.json` (city-art r12 §3 — it used to be an absolute
## home path that an exported build on any other machine could not open).
const RUNTIME_LAYOUT := "res://world/city/layout.json"
## Positions in the file are rounded to 0.01 m and the runtime transform is float32, so the lookup
## cell is coarse and the candidate inside it is picked by real distance.
const CELL := 0.25
const MAX_DIST := 1.0

## cell key -> Array of {"id", "kind", "model", "layer", "at"}
var _cells: Dictionary = {}
var rows: int = 0


static func _key(at: Vector3) -> String:
	return "%d,%d,%d" % [roundi(at.x / CELL), roundi(at.y / CELL), roundi(at.z / CELL)]


static func to_godot(p: Array) -> Vector3:
	return Vector3(float(p[0]), float(p[2]), -float(p[1]))


func _put(at: Vector3, id: String, kind: String, model: String, layer: int) -> void:
	var key := _key(at)
	var list: Array = _cells.get(key, [])
	list.append({"id": id, "kind": kind, "model": model, "layer": layer, "at": at})
	_cells[key] = list
	rows += 1


## The row that placed the instance at `at`, or `{}` when the file has nothing there (a skipped row, or
## a piece the placer derived rather than read).
func at(at: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := MAX_DIST
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var key := _key(at + Vector3(dx, dy, dz) * CELL)
				for entry: Dictionary in _cells.get(key, []):
					var d := (entry["at"] as Vector3).distance_to(at)
					if d < best_d:
						best_d = d
						best = entry
	return best


## Reads the assignment file. `cover` rows carry their stack layer: `tools/citykit/cover.py` lays copies
## bottom-up (`off[2] = iz * ch`), so layer 0 is every copy at the box's own bottom z and everything
## above rests on the copy under it by construction.
static func load_file(path: String = PATH) -> KitRows:
	var out := KitRows.new()
	if not FileAccess.file_exists(path):
		push_warning("KitRows: %s is missing — structure instances cannot be named" % path)
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("KitRows: %s is not a JSON object" % path)
		return out
	var data := parsed as Dictionary
	for row: Dictionary in (data.get("cover", []) as Array):
		var base := INF
		for piece: Dictionary in (row.get("pieces", []) as Array):
			base = minf(base, float((piece["pos"] as Array)[2]))
		for piece: Dictionary in (row.get("pieces", []) as Array):
			var p: Array = piece["pos"]
			out._put(to_godot(p), String(row["id"]), "cover", String(row["model"]),
					0 if absf(float(p[2]) - base) < 0.01 else 1)
	for row: Dictionary in (data.get("pieces", []) as Array):
		var segs: Array = row.get("segments", [])
		if segs.is_empty():
			var p: Array = row.get("pos", [0, 0, 0])
			out._put(to_godot(p), String(row["id"]), String(row["kind"]), String(row["model"]), 0)
			continue
		for seg: Dictionary in segs:
			out._put(to_godot(seg["pos"] as Array), String(row["id"]), String(row["kind"]),
					String(row["model"]), 0)
	return out


## Deck id -> `{"z", "thickness", "span", "muted", "full"}`, from the design layout's `decks` and the
## runtime layout's `kit_skin`.
##
## Two facts the render cannot be asked for:
##   `span`  — the layout itself declares the deck a skybridge or a canopy (`skybridge`, `canopy`,
##             `kind == "skydeck"`). Nothing is under it by design; it is held at its ends.
##   `muted` — city-build muted this deck's parapet render because the kit's railing row replaced it
##             (`kit_skin.decks`), so there is no rendered face at the polygon edge for the railing to
##             stand on. `full` is the same for the whole slab (`kit_skin.decks_full`).
## In both cases the authoritative surface is the layout's own `z`, not what the renderer draws.
static func load_decks() -> Dictionary:
	var out: Dictionary = {}
	var design := _read(ArtRepo.design_layout())
	for deck: Dictionary in (design.get("decks", []) as Array):
		out[String(deck["id"])] = {
			"z": float(deck.get("z", 0.0)),
			"thickness": float(deck.get("thickness", 0.0)),
			"span": bool(deck.get("skybridge", false)) or bool(deck.get("canopy", false)) \
					or String(deck.get("kind", "")) == "skydeck",
			"muted": false,
			"full": false,
		}
	var skin := (_read(RUNTIME_LAYOUT).get("kit_skin", {}) as Dictionary)
	for key: String in ["decks", "decks_full"]:
		for id: String in (skin.get(key, []) as Array):
			if not out.has(id):
				out[id] = {"z": NAN, "thickness": 0.0, "span": false, "muted": false, "full": false}
			out[id]["muted"] = true
			out[id]["full"] = key == "decks_full"
	return out


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}
