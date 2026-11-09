extends Node
## The roof map, read the way a scatterer reads it (city-art r12 §2).
##
## `tools/citykit/test_roofmap.py` is the gate on the MAP (it raycasts the shipped mesh and puts the
## worst p95 at 0.376 m). This is the gate on the READER: that the base64 planes decode, that the cell
## index is the one the format documents, and that the world answer comes back through the placer's own
## transform — the three places a sign error would hide, and each of them fails silently by putting
## every roof unit a few metres wrong rather than by erroring.
##
## Run: tools/godot.sh test res://world/art/tests/test_roof_map.gd

const SAMPLE := 40          ## buildings probed; every one is a whole transform round trip

var _failures: int = 0


func _ready() -> void:
	var map := KitRoofMap.load()
	_expect(not map.is_empty(), "the map has buildings (%d models, %d buildings)"
			% [map.models, map.buildings])
	_expect(map.models >= 20, "the kit's building models carry roof maps (got %d)" % map.models)
	_expect(map.buildings >= 300, "every kit building instance is indexed (got %d)" % map.buildings)
	if not map.is_empty():
		_check_heights(map)
		_check_unknown(map)
		_check_coverage(map)
	print("ROOF MAP TEST %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Every sampled building must answer at its own centre with a roof between its base and its top. A
## transposed axis or a flipped sign puts the answer hundreds of metres away, which this catches.
func _check_heights(map: KitRoofMap) -> void:
	var rows := _rows()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261104
	var checked := 0
	var flat_hits := 0
	var worst := 0.0
	for n in SAMPLE:
		var row: Dictionary = rows[rng.randi_range(0, rows.size() - 1)]
		var pos: Array = row.get("pos", [0.0, 0.0, 0.0])
		var centre := KitRoofMap.to_godot(pos)
		var top := centre.y + float(row.get("height", 0.0))
		var hit := map.roof_at(centre, top)
		if hit.is_empty():
			continue
		checked += 1
		if bool(hit.get("flat", false)):
			flat_hits += 1
		var y := (hit["at"] as Vector3).y
		worst = maxf(worst, absf(y - top))
		_expect(y >= centre.y - 1.0 and y <= top + 1.0,
				"%s: the roof at its own centre (%.1f m) is inside the building (base %.1f, top %.1f)"
				% [row.get("id", "?"), y, centre.y, top])
	_expect(checked >= SAMPLE / 2, "%d of %d sampled buildings answered (got %d)"
			% [SAMPLE / 2, SAMPLE, checked])
	_expect(flat_hits > 0, "some sampled centres are flat enough to stand on (got %d)" % flat_hits)
	print("ROOF MAP %d buildings probed, %d answered, %d on a flat cell, worst |roof - box top| %.1f m"
			% [SAMPLE, checked, flat_hits, worst])


## A point far outside the map has to come back empty rather than snapping to the nearest building:
## that is what stops a roof unit being teleported across the city onto a roof it has nothing to do with.
func _check_unknown(map: KitRoofMap) -> void:
	var hit := map.roof_at(Vector3(9000.0, 40.0, 9000.0), 40.0)
	_expect(hit.is_empty(), "a point 9 km outside the map has no roof")


## The invariant that actually matters: every model city-kit PLACES as a building has a map, and every
## building row is indexed. A model without one is a roof the dressing cannot be aimed at, and it
## arrives at the settle pass as a dropped unit rather than as an error.
func _check_coverage(map: KitRoofMap) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KitRoofMap.KIT_JSON))
	var mapped: Dictionary = {}
	for row: Dictionary in ((parsed as Dictionary).get("models", []) as Array):
		if row.has("roof"):
			mapped[String(row.get("id", ""))] = true
	var missing: Dictionary = {}
	var rows := 0
	var unmapped := 0
	for row: Dictionary in _rows():
		rows += 1
		var model := String(row.get("model", ""))
		if not mapped.has(model):
			missing[model] = true
			unmapped += 1
	var names: Array = missing.keys()
	names.sort()
	_expect(missing.is_empty(), "every placed building model has a roof map (%d of %d rows do not; "
			% [unmapped, rows] + "missing %s)" % ", ".join(names))
	print("ROOF MAP %d building rows, %d on a model with no map (%d distinct)"
			% [rows, unmapped, missing.size()])


func _rows() -> Array:
	var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(KitRoofMap.ASSIGN))
	var out: Array = []
	for row in ((parsed as Dictionary).get("buildings", []) as Array):
		if row is Dictionary and (row as Dictionary).has("height"):
			out.append(row)
	return out


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL %s" % msg)
		_failures += 1
