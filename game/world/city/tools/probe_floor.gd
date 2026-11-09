extends Node
## city-build r9: every RENDERED up-facing surface in a vertical column, named. (lead r9)
##   PROBE_AT="483.3,80,299.3;513,80,-570" tools/godot.sh run res://world/city/tools/probe_floor.tscn 60
##
## `world/art/tests/probe_support.tscn` slices +-6 m around a point, which is exactly the wrong
## window when the question is "the cover is 48 m up: what is under it?". This walks the whole
## column from +400 m to -400 m in 0.2 m steps against the SAME index the float audit uses
## (`ArtSurfaces`, built from the RENDER tiles), and prints every distinct height with the mesh
## that carries it — so a missing deck top face is named, not guessed at.
##
## PROBE_KIT=1 also reports city-kit's own instances (tier `lod` and `cover_near`) whose world AABB
## contains the column: those are PIECE to `ArtSurfaces` (dressing never holds dressing) but they
## are exactly what a `deck_full` row leaves behind when it mutes my slab.

const STEP := 0.2
const TOP := 400.0
const BOTTOM := -400.0

var _surfaces: ArtSurfaces = null


func _ready() -> void:
	var city := (load("res://world/city.tscn") as PackedScene).instantiate()
	add_child(city)
	for i in 4:
		await get_tree().process_frame
	_surfaces = ArtSurfaces.new()
	_surfaces.named = true
	var kit := city.get_node_or_null(^"KitPlacer")
	print("PROBE %d supports" % _surfaces.build(city, kit))
	if OS.get_environment("PROBE_ALLKIT") == "1":
		# `ArtSurfaces` calls a kit `lod`/`cover_near` mesh a PIECE: dressing never holds dressing.
		# A `deck_full` row is different - it is the FLOOR, drawn by city-kit instead of by my
		# slab - so this adds those batches as supports too, to answer "does the player see a
		# floor here?" rather than "does my tile draw one?".
		var extra := 0
		for batch: Dictionary in kit.call(&"near_batches"):
			if String(batch["tier"]) == "detail":
				continue
			var list: Array = batch["list"]
			for i in list.size():
				_surfaces.add(batch["mesh"] as Mesh, list[i] as Transform3D,
						"%s#%d" % [String(batch["name"]), i], ArtSurfaces.GROUND)
				extra += 1
		print("PROBE +%d kit piece instances counted as supports" % extra)
	for point in OS.get_environment("PROBE_AT").split(";", false):
		var at := _parse(point)
		_column(at)
		if OS.get_environment("PROBE_KIT") == "1":
			_kit(city, at)
	_surfaces.dispose()
	get_tree().quit(0)


## Every distinct support height straight down from the point, highest first.
func _column(at: Vector3) -> void:
	print("PROBE column at %s (x %.1f z %.1f)" % [at, at.x, at.z])
	var seen: Array[float] = []
	var y := at.y + TOP
	while y > at.y + BOTTOM:
		var hit := _surfaces.top_below(Vector3(at.x, y, at.z))
		if not hit.is_empty():
			var hy := float(hit["y"])
			if not seen.any(func(v: float) -> bool: return absf(v - hy) < 0.05):
				seen.append(hy)
				print("PROBE   %-6s y %8.2f  %+.1f m from the probe  normal %s  mesh %s"
						% [String(hit["kind"]), hy, hy - at.y, hit["normal"], String(hit["id"])])
		y -= STEP
	if seen.is_empty():
		print("PROBE   NOTHING in the whole column")


## city-kit instances whose world AABB contains the point: what a `deck_full` row replaced my
## slab with. Reported by batch name so the row id can be found in `kit_assign.json`.
func _kit(city: Node, at: Vector3) -> void:
	var kit := city.get_node_or_null(^"KitPlacer")
	if kit == null or not kit.has_method(&"near_batches"):
		print("PROBE   no kit placer")
		return
	var found := 0
	for batch: Dictionary in kit.call(&"near_batches"):
		var mesh := batch["mesh"] as Mesh
		if mesh == null:
			continue
		var box := mesh.get_aabb().abs()
		for t: Transform3D in batch["list"]:
			var w := Transform3D(t.basis.orthonormalized(), t.origin)
			var grown := AABB(w * box.position - Vector3.ONE * 0.5,
					box.size * w.basis.get_scale() + Vector3.ONE)
			if not grown.has_point(at):
				continue
			found += 1
			print("PROBE   kit %-28s tier %-10s y %.1f..%.1f"
					% [String(batch["name"]), String(batch["tier"]),
					   w.origin.y + box.position.y, w.origin.y + box.end.y])
	print("PROBE   %d kit instances over the point" % found)


static func _parse(text: String) -> Vector3:
	var p := text.split(",")
	if p.size() != 3:
		push_error("PROBE_AT wants x,y,z; got '%s'" % text)
		return Vector3.ZERO
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
