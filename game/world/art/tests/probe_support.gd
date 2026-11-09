extends Node
## Diagnostic: what surfaces are under a point, and at what heights? (city-art r10b)
##   PROBE_AT="37.5,0,263.7;4.4,32,-349" tools/godot.sh run res://world/art/tests/probe_support.tscn 60
##
## The settle pass's STREET rule takes the HIGHEST support within ±STREET_BAND of where the layout put
## a prop, so a prop that jumps most of the band has landed on something the rule should not be
## standing on. This prints every support surface in a vertical slice, so that thing can be named
## instead of guessed at.

var _surfaces: ArtSurfaces = null
var _roofs: KitRoofMap = null


func _ready() -> void:
	var city := (load("res://world/city.tscn") as PackedScene).instantiate()
	add_child(city)
	for i in 4:
		await get_tree().process_frame
	_surfaces = ArtSurfaces.new()
	_surfaces.named = true          ## one body per support, so every hit carries its mesh name
	var kit := city.get_node_or_null(^"KitPlacer")
	var n := _surfaces.build(city, kit)
	_roofs = KitRoofMap.load()
	print("PROBE %d supports, roof map %d models / %d buildings"
			% [n, _roofs.models, _roofs.buildings])
	for point in OS.get_environment("PROBE_AT").split(";", false):
		var at := _parse(point)
		_slice(at)
		_map(at)
		_renders(at)
	_surfaces.dispose()
	get_tree().quit(0)


## r16a: what city-kit's MEASURED roof map answers at this point, next to what the render has there.
## A rooftop unit is placed from the map and only re-checked against the render when the two disagree by
## more than `CitySettle.VERIFY_M`, so a map answer that is wrong by less than that ships as a floater —
## which is how two units ended up 0.8 m above their roof.
func _map(at: Vector3) -> void:
	if _roofs == null or _roofs.is_empty():
		print("PROBE   no roof map")
		return
	var hit := _roofs.roof_at(at, at.y + 1.0)
	if hit.is_empty():
		print("PROBE   roof map: nothing flat within %.0f m" % KitRoofMap.SEARCH_M)
		return
	print("PROBE   roof map: y %.2f (%+.2f m from the prop) at %s, moved %s"
			% [(hit["at"] as Vector3).y, (hit["at"] as Vector3).y - at.y, hit["at"], hit["moved"]])



## Every rendered mesh whose world AABB contains the point — the other half of the question. When the
## slice finds no surface where the layout says a deck is, this says whether the deck is drawn at all
## and under what name, which is the difference between "my index missed it" and "nobody drew it".
func _renders(at: Vector3) -> void:
	var stack: Array[Node] = [get_child(0)]
	var found := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as GeometryInstance3D
		if mi == null or not mi.visible:
			continue
		var mesh: Mesh = (mi as MeshInstance3D).mesh if mi is MeshInstance3D \
				else (mi as MultiMeshInstance3D).multimesh.mesh if mi is MultiMeshInstance3D else null
		if mesh == null:
			continue
		var box := mesh.get_aabb().abs()
		var world := Transform3D(mi.global_transform.basis.orthonormalized(), mi.global_position)
		var grown := AABB(world * box.position - Vector3.ONE * 0.5, box.size * world.basis.get_scale() \
				+ Vector3.ONE)
		if not grown.has_point(at):
			continue
		found += 1
		print("PROBE   renders %-40s %-22s aabb y %.1f..%.1f  range %.0f..%.0f"
				% [mi.name, mi.get_class(), world.origin.y + box.position.y,
				   world.origin.y + box.end.y, mi.visibility_range_begin, mi.visibility_range_end])
	print("PROBE   %d rendered meshes contain the point" % found)


## Every distinct support height in a 12 m slice around the point, top down.
func _slice(at: Vector3) -> void:
	print("PROBE at %s" % at)
	var kinds: Array[StringName] = [ArtSurfaces.ROOF, ArtSurfaces.GROUND]
	var seen: Array[float] = []
	var y := at.y + 6.0
	while y > at.y - 6.0:
		var hit := _surfaces.top_below(Vector3(at.x, y, at.z), kinds)
		if not hit.is_empty():
			var hy := float(hit["y"])
			if not seen.any(func(v: float) -> bool: return absf(v - hy) < 0.05):
				seen.append(hy)
				print("PROBE   %-6s y %7.2f  (%+.2f m from the prop)  normal %s  %s"
						% [String(hit["kind"]), hy, hy - at.y, hit["normal"], hit["id"]])
		y -= 0.25
	if seen.is_empty():
		print("PROBE   nothing within 6 m")


static func _parse(text: String) -> Vector3:
	var p := text.split(",")
	if p.size() != 3:
		push_error("PROBE_AT wants x,y,z; got '%s'" % text)
		return Vector3.ZERO
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
