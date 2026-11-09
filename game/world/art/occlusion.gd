class_name CityOcclusion
extends Node3D
## city-art r13: the occluder set. `project.godot` has had `use_occlusion_culling` on since the city was
## a blockout, but the game contained ZERO `OccluderInstance3D`s, so the setting bought nothing. This
## builds them at load from data the art layer already reads — `design_layout.json` and the kit roof
## map — so nothing is rebuilt and nothing is guessed.
##
## The rule that keeps it safe: an occluder may only ever be SMALLER than the thing it stands for.
## - a kit building's core is a stack of 12 m blocks read off city-kit's roof map, each running from the
##   model's base to the LOWEST top surface the map records inside that block — so the box is inside the
##   mass under it from every direction, and a setback, a crown or a spire is never inside it;
## - a blockout building (no kit model) is the design box inset by 2 m, because for those the design box
##   IS the geometry;
## - a deck is emitted as the cells of a grid that are fully inside its polygon, so a courtyard or a
##   hole is never filled in;
## - the ground crust is the street surface itself, per 200 m tile, so a sunken plaza 20 m below the
##   street is not roofed over.
##
##   tools/godot.sh test res://world/art/tests/test_occlusion.gd
##   tools/godot.sh shot --scene=res://world/art/tests/occlusion_dolly.tscn --out=occ   (the gate)

## Occluders are bucketed per 200 m tile so each `OccluderInstance3D` has a tight AABB and the engine
## can skip the ones behind the camera without touching their vertices.
const TILE := 200.0
## Metres a building's footprint is inset on every side before it becomes a box.
const INSET := 2.0
## A footprint thinner than this after the inset has no core left; it is skipped rather than guessed at.
const MIN_FOOT := 4.0
## Deck cells: the deck is emitted as the grid cells whose four corners are all inside the polygon.
const DECK_CELL := 16.0
## How far below the street the crust reaches. It only has to be thick enough to hide what is under it.
const CRUST_DEPTH := 70.0
## A building shorter than this is not worth an occluder (it hides nothing at street level).
const MIN_HEIGHT := 8.0
## The kit core is rasterised on this world grid. Smaller blocks follow the massing more closely and
## occlude more; 12 m keeps the whole city under ~4 000 boxes.
const CORE_BLOCK := 12.0
## A core block shorter than this hides nothing worth a box.
const CORE_MIN_H := 10.0

## Counters, printed by the caller so a run says what it built rather than that it built "some".
var boxes: int = 0
var tiles: int = 0
var capped: int = 0        ## boxes read off the kit roof map (the stepped cores)
var uncapped: int = 0      ## design rows with no kit model under them (blockout boxes)
## r16b §8: the world XZ centre of every design row that actually emitted a box, so the gate can assert
## the rule the builder follows — a row the roof map covers is never also a blockout box — against what
## the builder emitted rather than against its own reasoning.
var blockout: Array[Vector2] = []


## Builds the occluders under `host` and returns the node holding them (null when there is nothing to
## build). `design` is `design_layout.json`; `roofs` may be null or an empty map.
static func build(host: Node3D, design: Dictionary, roofs: KitRoofMap) -> CityOcclusion:
	if host == null or design.is_empty():
		return null
	var occ := CityOcclusion.new()
	occ.name = "Occluders"
	var buckets: Dictionary = occ._collect(design, roofs)
	if buckets.is_empty():
		return null
	occ.tiles = occ._emit(buckets)
	host.add_child(occ)
	return occ


## design_layout rows -> one box per occluder, bucketed by tile.
func _collect(design: Dictionary, roofs: KitRoofMap) -> Dictionary:
	var buckets: Dictionary = {}
	blockout.clear()
	# The kit models first: a real Tripo building's massing is stepped, so its core is a stack of
	# blocks read off the roof map rather than the one box the design layout describes.
	if roofs != null and not roofs.is_empty():
		for core: Dictionary in roofs.cores(CORE_BLOCK, CORE_MIN_H):
			_add(buckets, core["c"], core["half"], 0.0, float(core["y0"]), float(core["y1"]))
		capped = boxes
	for row: Dictionary in design.get("buildings", []):
		_building(row, roofs, buckets)
	for row: Dictionary in design.get("decks", []):
		_deck(row, buckets)
	for row: Dictionary in design.get("streets", []):
		_street(row, buckets)
	return buckets


## A design row is only built when NO kit model stands on it: those are city-build's own blockout boxes
## (the unskinned buildings), where the design box IS the geometry and its top is exact.
func _building(row: Dictionary, roofs: KitRoofMap, buckets: Dictionary) -> void:
	var size: Array = row.get("size", [0.0, 0.0])
	var sx := float(size[0]) - INSET * 2.0
	var sy := float(size[1]) - INSET * 2.0
	if sx < MIN_FOOT or sy < MIN_FOOT:
		return
	var base := float(row.get("base_z", 0.0))
	var top := base + float(row.get("height", 0.0))
	var c: Array = row.get("center", [0.0, 0.0])
	var centre := Vector2(float(c[0]), -float(c[1]))          ## Godot XZ
	if roofs != null and not roofs.is_empty():
		if roofs.covers(Vector3(centre.x, base + 1.0, centre.y)):
			return
		uncapped += 1
	else:
		uncapped += 1
	if top - base < MIN_HEIGHT:
		return
	var yaw := deg_to_rad(-float(row.get("rot", 0.0)))
	blockout.append(centre)
	_add(buckets, centre, Vector2(sx, sy) * 0.5, yaw, base, top)


## A deck is a polygon with holes at one height. It is emitted as the grid cells whose corners are ALL
## inside the polygon and outside every hole, so the occluder is always a subset of the slab.
func _deck(row: Dictionary, buckets: Dictionary) -> void:
	var poly: Array = row.get("polygon", [])
	if poly.size() < 3:
		return
	var top := float(row.get("z", 0.0))
	var y0 := top - maxf(float(row.get("thickness", 2.0)), 1.0)
	var holes: Array = row.get("holes", [])
	var pts := PackedVector2Array()
	for p: Array in poly:
		pts.append(Vector2(float(p[0]), -float(p[1])))
	var hole_polys: Array[PackedVector2Array] = []
	for h: Array in holes:
		var hp := PackedVector2Array()
		for p: Array in (h if h is Array else []):
			hp.append(Vector2(float(p[0]), -float(p[1])))
		if hp.size() >= 3:
			hole_polys.append(hp)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var half := Vector2(DECK_CELL, DECK_CELL) * 0.5
	var gx := int(ceil((hi.x - lo.x) / DECK_CELL))
	var gz := int(ceil((hi.y - lo.y) / DECK_CELL))
	for iz in range(gz):
		for ix in range(gx):
			var c := lo + Vector2((float(ix) + 0.5) * DECK_CELL, (float(iz) + 0.5) * DECK_CELL)
			if not _cell_inside(c, half, pts, hole_polys):
				continue
			_add(buckets, c, half, 0.0, y0, top)


## The crust: the street surface itself, one box per polyline segment at the segment's own height.
func _street(row: Dictionary, buckets: Dictionary) -> void:
	var pts: Array = row.get("points", [])
	if pts.size() < 2:
		return
	var top := float(row.get("z", 0.0))
	var half_w := float(row.get("width", 20.0)) * 0.5
	for i in range(pts.size() - 1):
		var a := Vector2(float((pts[i] as Array)[0]), -float((pts[i] as Array)[1]))
		var b := Vector2(float((pts[i + 1] as Array)[0]), -float((pts[i + 1] as Array)[1]))
		var d := b - a
		var length := d.length()
		if length < 1.0:
			continue
		_add(buckets, (a + b) * 0.5, Vector2(half_w, length * 0.5),
			atan2(d.y, d.x) - PI * 0.5, top - CRUST_DEPTH, top)


## A grid cell counts only when all four of its corners are inside the polygon and outside every hole.
func _cell_inside(c: Vector2, half: Vector2, poly: PackedVector2Array,
		holes: Array[PackedVector2Array]) -> bool:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := c + Vector2(sx * half.x, sz * half.y)
			if not Geometry2D.is_point_in_polygon(p, poly):
				return false
			for h in holes:
				if Geometry2D.is_point_in_polygon(p, h):
					return false
	return true


## Appends one oriented box to its tile's bucket. `half` is the half-extent in the box's own axes.
func _add(buckets: Dictionary, centre: Vector2, half: Vector2, yaw: float,
		y0: float, y1: float) -> void:
	var key := _key(centre)
	var list: Array = buckets.get(key, [])
	list.append({"c": centre, "h": half, "yaw": yaw, "y0": y0, "y1": y1})
	buckets[key] = list
	boxes += 1


## One `OccluderInstance3D` per bucket, its vertices relative to the tile centre so the instance's
## AABB stays inside the tile it belongs to.
func _emit(buckets: Dictionary) -> int:
	var made := 0
	for key: String in buckets:
		var rows: Array = buckets[key]
		var origin := _origin(key)
		var verts := PackedVector3Array()
		var idx := PackedInt32Array()
		for row: Dictionary in rows:
			_box(row, origin, verts, idx)
		if verts.is_empty():
			continue
		var occ := ArrayOccluder3D.new()
		occ.vertices = verts
		occ.indices = idx
		var inst := OccluderInstance3D.new()
		inst.name = "Occ_" + key.replace(",", "_")
		inst.occluder = occ
		inst.position = Vector3(origin.x, 0.0, origin.y)
		add_child(inst)
		made += 1
	return made


## Eight corners and twelve triangles, wound counter-clockwise seen from outside the box.
static func _box(row: Dictionary, origin: Vector2, verts: PackedVector3Array,
		idx: PackedInt32Array) -> void:
	var base := verts.size()
	var c: Vector2 = row["c"]
	var h: Vector2 = row["h"]
	var yaw := float(row["yaw"])
	var cos_y := cos(yaw)
	var sin_y := sin(yaw)
	var y0 := float(row["y0"])
	var y1 := float(row["y1"])
	for iy in [y0, y1]:
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var lx := sx * h.x
				var lz := sz * h.y
				verts.append(Vector3(
					c.x - origin.x + lx * cos_y - lz * sin_y, iy,
					c.y - origin.y + lx * sin_y + lz * cos_y))
	# 0..3 bottom (in xz: -x-z, -x+z, +x-z, +x+z), 4..7 top in the same order. Every triangle below is
	# wound so its right-hand normal points OUT of the box; `test_occlusion.gd` is the gate on that,
	# because an inside-out occluder hides whatever stands in front of it.
	for tri in [[0, 2, 1], [1, 2, 3], [4, 5, 6], [5, 7, 6],
			[0, 1, 4], [1, 5, 4], [1, 3, 5], [3, 7, 5],
			[0, 4, 2], [2, 4, 6], [2, 6, 3], [3, 6, 7]]:
		for v: int in tri:
			idx.append(base + v)


static func _key(p: Vector2) -> String:
	return "%d,%d" % [int(floor(p.x / TILE)), int(floor(p.y / TILE))]


static func _origin(key: String) -> Vector2:
	var parts := key.split(",")
	return Vector2((float(parts[0]) + 0.5) * TILE, (float(parts[1]) + 0.5) * TILE)
