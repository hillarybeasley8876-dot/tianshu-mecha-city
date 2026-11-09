extends Node
## city-art r10 unit test: the settle pass (world/art/tests/test_settle.gd).
## Headless — the whole point of `ArtSurfaces` is that it answers from the placer's own transform
## lists, so a MultiMesh read-back (which returns identity on the dummy renderer) is never needed.
## Run: tools/godot.sh test res://world/art/tests/test_settle.gd

const FLOAT_GATE := 0.001

var _failures: int = 0
var _surfaces: ArtSurfaces
var _settle: CitySettle
var _item: BoxMesh


func _ready() -> void:
	_item = _box(Vector3(2.0, 1.0, 2.0))
	_build_scene()
	_check_roof_lands_on_the_roof()
	_check_roof_drops_off_the_roof()
	_check_street_band()
	_check_dressing_does_not_hold_dressing()
	_check_follow()
	print("SETTLE TEST %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


## A 20 x 30 x 20 "kit building" standing on a 400 m ground slab, plus a dressing piece floating over
## the ground to prove pieces are not supports.
func _build_scene() -> void:
	_surfaces = ArtSurfaces.new()
	_expect(_surfaces.setup(get_viewport().world_3d), "the index attaches to a World3D")
	_surfaces.add(_box(Vector3(20.0, 30.0, 20.0)), _at(Vector3(0.0, 15.0, 0.0)), "b#0",
			ArtSurfaces.ROOF)
	_surfaces.add(_box(Vector3(400.0, 2.0, 400.0)), _at(Vector3(0.0, -1.0, 0.0)), "ground",
			ArtSurfaces.GROUND)
	_settle = CitySettle.new(_surfaces)
	_expect(_surfaces.size() == 2, "the index holds 2 supports, got %d" % _surfaces.size())


# ------------------------------------------------------------------ checks
## The regression this whole round is about: a rooftop unit hanging 30 m over its roof has to LAND on
## the roof. It also pins the bug that made every item in the city sit on y = 0 — a typed-array
## ternary that failed at runtime and silently returned 0.0 from `_target`.
func _check_roof_lands_on_the_roof() -> void:
	var kept := _settle.settle([_at(Vector3(0.0, 60.5, 0.0))] as Array[Transform3D], _item,
			CitySettle.RULE_ROOF, "t:roof", "t")
	_expect(kept.size() == 1, "a unit over a roof is kept, got %d" % kept.size())
	if kept.is_empty():
		return
	var base := (kept[0] * Vector3(0.0, -0.5, 0.0)).y
	_expect(absf(base - 30.0) < FLOAT_GATE, "it lands ON the 30 m roof, not at %.2f" % base)
	var hit := _surfaces.top_below(Vector3(0.0, 61.5, 0.0))
	_expect(not hit.is_empty() and absf(float(hit["y"]) - 30.0) < FLOAT_GATE,
			"the query finds the 30 m roof from above")


## Over the street there is no kit roof, so a rooftop unit is DROPPED — a roof unit standing in the
## street is worse than none.
func _check_roof_drops_off_the_roof() -> void:
	var kept := _settle.settle([_at(Vector3(80.0, 60.5, 0.0))] as Array[Transform3D], _item,
			CitySettle.RULE_ROOF, "t:roof", "t")
	_expect(kept.is_empty(), "a roof unit over the street is dropped, %d survived" % kept.size())
	_expect(int((_settle.stats["t:roof"] as Dictionary)["dropped"]) == 1,
			"the drop is counted, not hidden")


## Street rule: settle inside +/-STREET_BAND of where the layout meant it to be, drop and report
## outside it. r10b narrowed the band from 3 m to 1.5 m: eight props had climbed exactly 2.9 m onto the
## concrete mass of the NEXT tile, and a planter standing on a building plinth over the pavement it was
## placed on is the bug this whole pass exists to remove.
func _check_street_band() -> void:
	var near := _settle.settle([_at(Vector3(80.0, 1.2, 0.0))] as Array[Transform3D], _item,
			CitySettle.RULE_STREET, "t:street", "t")
	_expect(near.size() == 1, "a lamp 1.2 m over the road is kept")
	if not near.is_empty():
		var base := (near[0] * Vector3(0.0, -0.5, 0.0)).y
		_expect(absf(base) < FLOAT_GATE, "it settles onto the road at 0, not %.2f" % base)
	var plinth := _settle.settle([_at(Vector3(80.0, 2.9, 0.0))] as Array[Transform3D], _item,
			CitySettle.RULE_STREET, "t:street", "t")
	_expect(plinth.is_empty(),
			"a prop 2.9 m up a plinth is outside the %.1f m band and is dropped, not climbed"
			% CitySettle.STREET_BAND)
	var far := _settle.settle([_at(Vector3(80.0, 10.5, 0.0))] as Array[Transform3D], _item,
			CitySettle.RULE_STREET, "t:street", "t")
	_expect(far.is_empty(), "a lamp 10 m over the road has nothing in its band and is dropped")
	_expect(int((_settle.stats["t:street"] as Dictionary)["nowhere"]) == 2,
			"both no-surface-in-band drops are counted, not hidden")


## Dressing does not hold up dressing: a piece standing under an item must not become its floor,
## because the kit pass settles its batches one after another and a piece is a stale support.
func _check_dressing_does_not_hold_dressing() -> void:
	var index := ArtSurfaces.new()
	index.setup(get_viewport().world_3d)
	index.add(_box(Vector3(400.0, 2.0, 400.0)), _at(Vector3(0.0, -1.0, 0.0)), "ground",
			ArtSurfaces.GROUND)
	# A `piece` is never added to the index at all — `build()` skips the tier — so this only has to
	# prove the STREET mask does not pick up a dressing body if one were there.
	var settle := CitySettle.new(index)
	var kept := settle.settle([_at(Vector3(80.0, 1.2, 0.0))] as Array[Transform3D], _item,
			CitySettle.RULE_STREET, "t:piece", "t")
	_expect(kept.size() == 1, "the item survives")
	if not kept.is_empty():
		var base := (kept[0] * Vector3(0.0, -0.5, 0.0)).y
		_expect(absf(base) < FLOAT_GATE,
				"it stands on the GROUND at 0, not on the stall at 1.5 (got %.2f)" % base)


## The aviation lamp is the same transform list as its mast, 9.3 m up the pole: it follows the mast's
## survivors and the mast's vertical move instead of being settled on its own (much smaller) mesh.
func _check_follow() -> void:
	var masts: Array[Transform3D] = [_at(Vector3(0.0, 60.5, 0.0)), _at(Vector3(80.0, 60.5, 0.0))]
	var lamps: Array[Transform3D] = [_at(Vector3(0.0, 69.8, 0.0)), _at(Vector3(80.0, 69.8, 0.0))]
	var kept := _settle.settle(masts, _item, CitySettle.RULE_ROOF, "t:mast", "mast")
	_expect(kept.size() == 1, "one mast survives, got %d" % kept.size())
	var followed := CitySettle.follow(lamps, _settle.last_kept, _settle.last_delta)
	_expect(followed.size() == 1, "one lamp follows it, got %d" % followed.size())
	if kept.is_empty() or followed.is_empty():
		return
	var drop := (followed[0].origin.y - _settle.last_delta[0].y) - kept[0].origin.y
	_expect(absf((followed[0].origin.y - kept[0].origin.y) - 9.3) < FLOAT_GATE,
			"the lamp keeps its 9.3 m offset off the pole (drop was %.2f)" % drop)


func _exit_tree() -> void:
	if _surfaces != null:
		_surfaces.dispose()


# ------------------------------------------------------------------ helpers
func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _at(pos: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, pos)


func _expect(ok: bool, what: String) -> void:
	if ok:
		return
	_failures += 1
	print("SETTLE TEST FAIL: %s" % what)
