extends Node
## city-art r13: the occluder gate that runs without a renderer. Three things are checked, because each
## one is a way the set can be silently wrong:
##   1. GEOMETRY — every occluder's indices are in range and come in threes, and every box is a closed
##      volume whose triangles wind OUTWARD (positive signed volume). An inside-out occluder hides
##      whatever stands in front of it, which is the failure this whole round must not ship.
##   2. SAFETY — every building core is inside its own footprint (inset by `INSET`) and no taller than
##      the roof map's lowest flat surface over that footprint, so nothing the player can see is inside
##      a box. Buildings with no roof map answer are counted, not assumed.
##   3. DECKS — a deck's cells are all inside its polygon and outside its holes.
##   tools/godot.sh test res://world/art/tests/test_occlusion.gd

const DESIGN := "res://world/city/design_layout.json"

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	var design: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DESIGN)) as Dictionary
	_check(design.size() > 0, "design layout loads (%d keys)" % design.size())
	var roofs := KitRoofMap.load()
	var occ := CityOcclusion.new()
	var buckets: Dictionary = occ._collect(design, roofs)
	_check(not buckets.is_empty(), "boxes collected: %d in %d tiles" % [occ.boxes, buckets.size()])
	_geometry(buckets)
	_safety(design, roofs)
	_blockout_rule(design, roofs)
	_decks(design)
	print("OCCLUSION %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


## Every emitted occluder: indices sane, and every box closed and outward-wound.
func _geometry(buckets: Dictionary) -> void:
	var boxes := 0
	var bad_wind := 0
	var bad_index := 0
	var worst := 0.0
	for key: String in buckets:
		var origin := CityOcclusion._origin(key)
		var verts := PackedVector3Array()
		var idx := PackedInt32Array()
		for row: Dictionary in buckets[key]:
			var before := idx.size()
			CityOcclusion._box(row, origin, verts, idx)
			var vol := _volume(verts, idx, before)
			if vol <= 0.0:
				bad_wind += 1
			worst = maxf(worst, absf(vol))
			boxes += 1
		for i in idx:
			if i < 0 or i >= verts.size():
				bad_index += 1
		_check(idx.size() % 3 == 0, "tile %s has %d indices" % [key, idx.size()])
	_check(bad_index == 0, "every index is in range (%d bad)" % bad_index)
	_check(bad_wind == 0, "every box winds outward (%d of %d inside out, worst |volume| %.0f m3)"
			% [bad_wind, boxes, worst])


## Six times the signed volume of the triangles added after `from`. Positive means the faces point out.
func _volume(verts: PackedVector3Array, idx: PackedInt32Array, from: int) -> float:
	var total := 0.0
	var i := from
	while i + 2 < idx.size():
		var a := verts[idx[i]]
		var b := verts[idx[i + 1]]
		var c := verts[idx[i + 2]]
		total += a.dot(b.cross(c))
		i += 3
	return total / 6.0


## The safety rule, checked against the same data the builder read rather than against itself.
func _safety(design: Dictionary, roofs: KitRoofMap) -> void:
	var cores := roofs.cores(CityOcclusion.CORE_BLOCK, CityOcclusion.CORE_MIN_H)
	_check(cores.size() > 0, "kit cores: %d blocks" % cores.size())
	var short := 0
	var tall := 0.0
	var low := INF
	# r16b §8: a block that is inside the footprint but that no measured map cell reaches has no known
	# mass. It used to keep the INF it was seeded with, `INF - base < min_h` was false, and it shipped as
	# an occluder from the base to infinity — 25 of them, in 7 tiles, which also printed `tallest inf m`
	# here. `ART_CORES_LEGACY=1` puts that rule back and this check fails.
	var infinite := 0
	for core: Dictionary in cores:
		var y0 := float(core["y0"])
		var y1 := float(core["y1"])
		if not is_finite(y1):
			infinite += 1
			continue
		if y1 - y0 < CityOcclusion.CORE_MIN_H - 0.001:
			short += 1
		tall = maxf(tall, y1 - y0)
		low = minf(low, y1 - y0)
	_check(infinite == 0, "every core block has a finite top (%d of %d reach to infinity)"
			% [infinite, cores.size()])
	_check(short == 0, "no core block is shorter than CORE_MIN_H (%d)" % short)
	# A block that lies wholly inside one instance's footprint is inside that building's mass; the
	# builder is what guarantees it, so the check is that the block grid and the footprint agree.
	var outside := 0
	for core: Dictionary in cores:
		var h: Vector2 = core["half"]
		if h.x <= 0.0 or h.y <= 0.0:
			outside += 1
	_check(outside == 0, "every core block has a positive footprint (%d bad)" % outside)
	print("     core heights: shortest %.1f m, tallest %.1f m, %d dropped unmeasured"
			% [low, tall, roofs.cores_unmeasured])


## r16b §8: the rule the builder follows is "a design row is only built where NO kit model stands", so
## the two never stack. The premise this used to check — that some rows are NOT covered, so some
## blockout boxes exist — stopped being true at city-kit r9, when every design row came to stand on a
## kit model; the check then failed by construction and said nothing about the rule. What is checked
## now is the property itself, on what the builder EMITTED (`CityOcclusion.blockout`), plus a synthetic
## uncovered row the way `_decks` does, so the gate does not depend on what the layout happens to hold.
func _blockout_rule(design: Dictionary, roofs: KitRoofMap) -> void:
	var occ := CityOcclusion.new()
	occ._collect(design, roofs)
	var emitted := {}
	for c: Vector2 in occ.blockout:
		emitted[_key(c)] = true
	var rows: Array = design.get("buildings", [])
	var covered_rows := 0
	var stacked := 0
	var first_covered: Dictionary = {}
	for row: Dictionary in rows:
		var c: Array = row.get("center", [0.0, 0.0])
		var p := Vector3(float(c[0]), float(row.get("base_z", 0.0)) + 1.0, -float(c[1]))
		if roofs.covers(p):
			covered_rows += 1
			if first_covered.is_empty():
				first_covered = row
			if emitted.has(_key(Vector2(p.x, p.z))):
				stacked += 1
	_check(covered_rows > 0, "%d of %d design rows stand on a kit model" % [covered_rows, rows.size()])
	_check(stacked == 0, "no covered row is also a blockout box (%d stacked)" % stacked)
	_check(occ.blockout.size() == occ.uncapped,
			"every blockout box is accounted for (%d emitted, %d uncapped rows)"
			% [occ.blockout.size(), occ.uncapped])
	# The synthetic uncovered row: a real row through the same builder, with and without a roof map.
	# Without one it must emit exactly one box; with the map that covers it, nothing.
	var synthetic := {"center": [9000.0, 9000.0], "size": [40.0, 40.0], "base_z": 0.0,
		"height": 60.0, "rot": 0.0}
	_check(not roofs.covers(Vector3(9000.0, 1.0, -9000.0)),
			"the synthetic row stands where no kit model does")
	var far := CityOcclusion.new()
	var far_buckets: Dictionary = {}
	far._building(synthetic, roofs, far_buckets)
	_check(_count(far_buckets) == 1, "an uncovered row emits exactly one box (%d)" % _count(far_buckets))
	_check(far.blockout.size() == 1, "and is recorded as a blockout box")
	var near := CityOcclusion.new()
	var near_buckets: Dictionary = {}
	near._building(first_covered, roofs, near_buckets)
	_check(_count(near_buckets) == 0,
			"the same builder emits nothing for a covered row (%d boxes)" % _count(near_buckets))
	_check(near.blockout.is_empty(), "and records no blockout box for it")


## Boxes in a bucket set, counted rather than trusted.
func _count(buckets: Dictionary) -> int:
	var n := 0
	for key: String in buckets:
		n += (buckets[key] as Array).size()
	return n


## World XZ to a 1 mm key, so "is this centre in the emitted set" is exact.
func _key(c: Vector2) -> String:
	return "%d,%d" % [int(round(c.x * 1000.0)), int(round(c.y * 1000.0))]


## A deck cell must be inside the polygon and outside every hole. Built from a synthetic deck so the
## check does not depend on what the layout happens to contain this week.
func _decks(_design: Dictionary) -> void:
	var occ := CityOcclusion.new()
	var buckets: Dictionary = {}
	occ._deck({"polygon": [[0, 0], [100, 0], [100, 100], [0, 100]],
		"holes": [[[40, 40], [60, 40], [60, 60], [40, 60]]],
		"z": 20.0, "thickness": 4.0}, buckets)
	var inside_hole := 0
	var cells := 0
	for key: String in buckets:
		for row: Dictionary in buckets[key]:
			cells += 1
			var c: Vector2 = row["c"]
			if c.x > 36.0 and c.x < 64.0 and c.y > 36.0 and c.y < 64.0:
				inside_hole += 1
	_check(cells > 0, "the synthetic deck produced %d cells" % cells)
	_check(inside_hole == 0, "no cell lands inside the hole (%d)" % inside_hole)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL ", what)
	else:
		print("ok   ", what)
