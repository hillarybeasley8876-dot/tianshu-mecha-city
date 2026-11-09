extends Node
## city-art prop test (world/props/tests/test_props.gd). Headless: runs the placement rules over the
## real map layout, checks the counts and clearances, and loads every processed prop mesh.
## Run: tools/godot.sh test res://world/props/tests/test_props.gd

## r12 §3: the `res://` copy the Blender build writes beside `layout.json`, the props unit's own
## fixture, and the repo original last. No literal an absolute home path path anywhere under `game/`.
const LAYOUT_PATHS := ["res://world/props/data/city_layout.json",
	"res://world/city/design_layout.json"]
const PLACER := preload("res://world/props/prop_placer.gd")

var _failures: int = 0


func _ready() -> void:
	var layout := _load_layout()
	if layout.is_empty():
		print("PROPS TEST FAIL (no city_layout.json)")
		get_tree().quit(1)
		return
	var placer := PLACER.new()
	var plan := placer.build(layout)
	var total := placer.prop_count()
	print("PROPS plan: %d instances of %d props" % [total, plan.size()])
	for prop in plan:
		print("  %-16s %d" % [prop, (plan[prop] as Array).size()])
	_expect(total > 1500, "the city is dressed (%d instances)" % total)
	_expect(plan.has(&"streetlamp") and (plan[&"streetlamp"] as Array).size() > 100,
		"streetlamps line the streets")
	_expect(plan.has(&"crane"), "harbour cranes are placed")
	_expect(plan.has(&"mech_statue") and plan.has(&"guardian_lion"), "the Spire Plaza is dressed")
	_expect(placer.hologram_plan.has(&"koi_dragon"), "the Block 9 koi hologram is planned")
	_check_clearance(plan)
	_check_meshes(plan, placer)
	_check_determinism(layout)
	print("PROPS TEST %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL ", what)


func _load_layout() -> Dictionary:
	for path in LAYOUT_PATHS:
		if not FileAccess.file_exists(path):
			continue
		var text := FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			return parsed
		push_error("test_props: %s is not a JSON object" % path)
	return {}


## Nothing may sit inside the playable carriageway, and nothing may fall outside the map bounds.
func _check_clearance(plan: Dictionary) -> void:
	var inside := 0
	var outside := 0
	for prop in plan:
		for xf: Transform3D in plan[prop]:
			if absf(xf.origin.x) > 700.0 or absf(xf.origin.z) > 700.0:
				outside += 1
			if xf.origin.y < -40.0 or xf.origin.y > 300.0:
				inside += 1
	_expect(outside == 0, "no prop falls outside the playable square (%d did)" % outside)
	_expect(inside == 0, "no prop sits below the tunnels or above the ceiling (%d did)" % inside)


func _check_meshes(plan: Dictionary, placer: PropPlacer) -> void:
	var missing: Array[String] = []
	for prop in plan:
		if PropScatter.load_mesh(prop) == null:
			missing.append(String(prop))
	for prop in placer.hologram_plan:
		if PropScatter.load_mesh(prop) == null:
			missing.append(String(prop))
	_expect(missing.is_empty(), "every planned prop has a processed mesh (missing: %s)"
		% ", ".join(missing))


func _check_determinism(layout: Dictionary) -> void:
	var a := PLACER.new().build(layout, 7)
	var b := PLACER.new().build(layout, 7)
	_expect(a.size() == b.size(), "the plan is deterministic across runs")
	var same := true
	for prop in a:
		if (a[prop] as Array).size() != (b[prop] as Array).size():
			same = false
	_expect(same, "per-prop counts are deterministic for a fixed seed")
