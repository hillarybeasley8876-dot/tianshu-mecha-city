extends Node
## city-art r10: the float gate as a TEST (world/art/tests/test_float.gd), so a future round cannot
## regress it without `tools/godot.sh test` going red.
## Run: tools/godot.sh test res://world/art/tests/test_float.gd
##
## This is `tools/float_audit.gd`'s measurement with one difference: the items come from the layers'
## OWN transform lists rather than a MultiMesh read-back, because `get_instance_transform` returns
## identity under the dummy renderer a head-less test runs on. The surface query is the same
## `ArtSurfaces` the settle pass and the audit use, and the five footprint samples are the same
## `CitySettle._feet`, so all three measure the same thing.
##
## The windowed audit is still the authoritative gate — it sees the batches as the RENDERER has them.
## This is the cheap one that runs in CI.

const FLOAT_GATE := 0.5
## `FLOAT_GATE_M=0.05` lowers the gate for one run, which is how the WORST floaters are ranked (the
## windowed audit only prints what is already past 0.5 m, so it cannot say what the third worst is).
var _gate: float = FLOAT_GATE

var _failures: int = 0
var _surfaces: ArtSurfaces = null
var _worst: Array[Dictionary] = []


func _ready() -> void:
	var gate := OS.get_environment("FLOAT_GATE_M")
	if not gate.is_empty():
		_gate = float(gate)
	var city := (load("res://world/city.tscn") as PackedScene).instantiate()
	add_child(city)
	for i in 3:
		await get_tree().process_frame
	var art := _find_art(city)
	_expect(art != null, "the city instanced a CityArt node")
	if art == null:
		_done()
		return
	var kit := city.get_node_or_null(^"KitPlacer")
	_surfaces = ArtSurfaces.new()
	var n := _surfaces.build(city, kit)
	_expect(n > 1000, "the support index holds %d surfaces, expected more than 1 000" % n)
	var batches := _batches(art, kit)
	_expect(batches.size() > 60, "%d dressing batches, expected more than 60" % batches.size())
	for batch: Dictionary in batches:
		_measure(String(batch["category"]), batch["mesh"] as Mesh, batch["list"] as Array)
	_expect(_worst.is_empty(), "%d instances float more than %.1f m (worst: %s)"
			% [_worst.size(), _gate, _describe()])
	_surfaces.dispose()
	_done()


## Every RESTING batch in the city, as `[category, mesh, list]`. Same categories the windowed audit
## judges; the whitelist is the audit's, in one place. Kit STRUCTURE (deck slabs, pylons, street skirts,
## market rows, railings, pipe racks, arena cover) is deliberately NOT here: r10b stopped settling it,
## and the audit reports it by row id instead of gating it.
func _batches(art: Node, kit: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if kit != null and kit.has_method(&"near_batches"):
		for batch: Dictionary in kit.call(&"near_batches"):
			var model := String(batch["model"])
			if CityArt.kit_role(model) != "dressing":
				continue
			out.append({"category": "kit:" + model, "mesh": batch["mesh"],
					"list": batch["list"]})
	var greebles := art.get_node_or_null(^"Greebles") as RoofGreebles
	if greebles != null:
		for kind: StringName in greebles.emitted:
			if kind == &"mast_lamp":
				continue          ## hangs 9.3 m up its mast
			out.append({"category": "greeble:" + String(kind), "mesh": greebles._mesh_for(kind),
					"list": greebles.emitted[kind]})
	var dressing := art.get_node_or_null(^"Dressing") as PropScatter
	if dressing != null:
		for prop: StringName in dressing.emitted:
			out.append({"category": "prop:" + String(prop),
					"mesh": PropScatter.load_mesh(prop), "list": dressing.emitted[prop]})
	return out


func _measure(category: String, mesh: Mesh, list: Array) -> void:
	if mesh == null:
		return
	var bb := mesh.get_aabb()
	var c := bb.get_center()
	var feet := CitySettle._feet(bb)
	for xf: Transform3D in list:
		var bottom := xf * feet[0]
		var top_y := (xf * Vector3(c.x, bb.end.y, c.z)).y
		var surface := NAN
		for foot in feet:
			var at := xf * foot
			var hit := _surfaces.top_below(Vector3(at.x, maxf(top_y, at.y) + 1.0, at.z))
			if not hit.is_empty() and (is_nan(surface) or float(hit["y"]) > surface):
				surface = float(hit["y"])
		if is_nan(surface):
			continue          ## nothing under it at all: reported by the windowed audit, not gated here
		if bottom.y - surface > _gate:
			_worst.append({"gap": bottom.y - surface, "cat": category, "at": bottom})


## The worst floaters, worst first. r16a: this is the iteration loop's output — a rule change is
## measured head-lessly with `SETTLE_RECOMPUTE=1`, so the positions have to be here and not only in the
## windowed audit.
func _describe() -> String:
	if _worst.is_empty():
		return "none"
	_worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["gap"]) > float(b["gap"]))
	var lines: Array[String] = []
	for i in mini(6, _worst.size()):
		var w: Dictionary = _worst[i]
		lines.append("%.2f m %s at (%.1f, %.1f, %.1f)"
				% [float(w["gap"]), w["cat"], (w["at"] as Vector3).x, (w["at"] as Vector3).y,
				   (w["at"] as Vector3).z])
	if _worst.size() > lines.size():
		lines.append("and %d more" % (_worst.size() - lines.size()))
	return "\nFLOAT      " + "\nFLOAT      ".join(lines)


func _find_art(city: Node) -> Node:
	var stack: Array[Node] = [city]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CityArt:
			return n
		stack.append_array(n.get_children())
	return null


func _done() -> void:
	print("FLOAT TEST %s (%d failures, %d floating)"
			% ["PASS" if _failures == 0 else "FAIL", _failures, _worst.size()])
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if ok:
		return
	_failures += 1
	print("FLOAT TEST FAIL: %s" % what)
