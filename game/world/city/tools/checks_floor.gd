class_name CityFloorCheck
extends RefCounted
## C18: every walkable floor the layout declares has a RENDERED up-facing face at its own z.
##
## The bug class this catches (lead, r9): the collider is there, the render is not. A player can
## stand on it and fight on it and sees nothing under their feet. It happened two ways — a deck
## whose slab `skin.py` muted for a `deck_full` row, and a lot placed across a connector trench
## whose cut-out the crust never got. Both are invisible to every other check, because they all
## query COLLISION and the collider was always right.
##
## The index is `ArtSurfaces`, the SAME class the load-time settle pass and `tools/float_audit.gd`
## use: the tile render meshes plus city-kit's `detail` tier. So the gate measures the world the
## game ships, not a second opinion of it.
##
## What is sampled, on a 4 m grid (`GRID`):
##   * every deck polygon minus its holes, at the deck's z;
##   * the three terrain surfaces the render draws (crust, plateau, dock floor) at their z;
##   * every building footprint, at its `base_z` — that is the D4_b034 case, a lot over a trench.
## A sample is skipped when a `blocks` footprint (a building or an arena cover box) already stands
## there: a crate on a deck is the float audit's business, not the floor's. A deck named by a
## `deck_full` row is exempt and counted, because its render is city-kit's model, not my slab.

const GRID := 4.0              ## m: the sampling step the lead asked for
const GRID_OFFSET := 0.37      ## m: the grid never lands on a round coordinate. Chunk seams, hole
                               ##    edges and deck edges are all on integers, and a ray fired at
                               ##    exactly a seam between two abutting faces hits neither - the
                               ##    Crown read as a missing floor along one x = -80 line
const TOL := 0.3               ## m: the rendered face has to be within this of the floor's z
const PROBE := 0.5             ## m: the ray starts this far above the floor, so a rim step or a
                               ##    parapet 1.5 m up is not mistaken for the floor itself
const MIN_UP := 0.7            ## the hit has to face up; a wall is not a floor
const PEEL := 4                ## how many stacked surfaces to step under before giving up
const EDGE := 0.25             ## m: a sample this close to a polygon edge is dropped — the layout's
                               ##    holes sit on 2 m coordinates and the 4 m grid lands on them, and
                               ##    even-odd point-in-polygon is undefined exactly on an edge
const LIST := 8                ## how many offenders to print
const CELL := 64.0             ## m: the bucket size of the `blocks` index

var sampled: int = 0
var exempt_decks: PackedStringArray = []
var offenders: PackedStringArray = []
var worst: float = 0.0
var built_ms: int = 0

## The tile render meshes only. `ArtSurfaces` also indexes city-kit's `detail` buildings as
## `roof`, and a facade at ground level is a wall, not a floor: three samples along the escarpment
## crest were stopping on a kit tower's sloped base and reading as a missing street.
const GROUND_ONLY: Array[StringName] = [ArtSurfaces.GROUND]

var _buckets: Dictionary = {}   ## Vector2i cell -> Array[int] index into `_rows`
var _rows: Array = []           ## {poly: PackedVector2Array, z0, z1}


## Runs the whole gate. `city` is the live world; `layout` is `game/world/city/layout.json`.
func run(city: Node3D, layout: Dictionary) -> bool:
	var t0 := Time.get_ticks_msec()
	var surfaces := ArtSurfaces.new()
	var kit := city.get_node_or_null(^"KitPlacer")
	var supports := surfaces.build(city, kit)
	_index(layout.get("blocks", []))
	for floor: Dictionary in layout.get("floors", []):
		if bool(floor.get("deck_full", false)):
			exempt_decks.append(String(floor["id"]))
			continue
		_floor(floor, surfaces)
	for row: Dictionary in layout.get("blocks", []):
		if String(row.get("kind", "")) == "cover":
			continue
		_footing(row, surfaces)
	surfaces.dispose()
	built_ms = Time.get_ticks_msec() - t0
	print("C18   %d render supports indexed, %d grid samples in %d ms"
			% [supports, sampled, built_ms])
	return offenders.is_empty()


func summary() -> String:
	return ("%d samples on a %.0f m grid, %d with no rendered face within %.1f m (worst %.1f m), "
			+ "%d deck_full decks exempt") % [sampled, GRID, offenders.size(), TOL, worst,
			exempt_decks.size()]


func list() -> String:
	var want := LIST
	var env := OS.get_environment("C18_LIST")
	if not env.is_empty():
		want = int(env)
	var out := PackedStringArray()
	for i in mini(want, offenders.size()):
		out.append(offenders[i])
	return ", ".join(out)


# ------------------------------------------------------------------ one floor
func _floor(floor: Dictionary, surfaces: ArtSurfaces) -> void:
	var z := float(floor["z"])
	var outer := _ring(floor["polygon"])
	var holes: Array = []
	for h: Array in floor.get("holes", []):
		var ring := _ring(h)
		if ring.size() >= 3:
			holes.append({"ring": ring, "box": _bbox(ring)})
	var box := _bbox(outer)
	var x := box.position.x + GRID * 0.5 + GRID_OFFSET
	while x < box.end.x:
		var y := box.position.y + GRID * 0.5 + GRID_OFFSET
		while y < box.end.y:
			if _inside(outer, x, y) and not _in_any(holes, x, y) \
					and not _on_edge(outer, holes, x, y) and not _blocked(x, y, z):
				_probe(surfaces, Vector3(x, z + PROBE, -y), z,
						"%s (%.1f, %.1f)" % [String(floor["id"]), x, y])
			y += GRID
		x += GRID


## A building's own footing: is there a rendered face at its base_z under its footprint? This is
## the case a floor-by-floor sweep cannot see, because the lot is not a floor — D4_b034 stood
## 14 m over `con_W7_U3_ramp`'s trench with the crust cut away under it.
func _footing(row: Dictionary, surfaces: ArtSurfaces) -> void:
	var c: Array = row["c"]
	var s: Array = row["s"]
	var z := float(row["z0"])
	var yaw := float(row.get("yaw", 0.0))
	for fx in [-0.35, 0.0, 0.35]:
		for fy in [-0.35, 0.0, 0.35]:
			var p := _rotate(c, s, yaw, fx, fy)
			_probe(surfaces, Vector3(p.x, z + PROBE, -p.y), z,
					"footing (%.1f, %.1f, %.1f) at (%.1f, %.1f)" % [float(c[0]), float(c[1]), z, p.x, p.y])


## The rendered face, peeling anything stacked on top of it. A deck carries 0.5 m `mc_up_accent`
## light strips and 1.5 m rim steps; a ray that stops at the first surface would call every one of
## them a missing floor. So a hit ABOVE the tolerance band is stepped under and the ray continues,
## up to `PEEL` surfaces deep.
func _probe(surfaces: ArtSurfaces, from: Vector3, z: float, what: String) -> void:
	sampled += 1
	var at := from
	var last := NAN
	var why := ""
	for i in PEEL:
		var hit := surfaces.top_below(at, GROUND_ONLY)
		if hit.is_empty():
			break
		last = float(hit["y"])
		var n: Vector3 = hit["normal"]
		if absf(last - z) <= TOL and n.y >= MIN_UP:
			return
		why = " normal (%.2f, %.2f, %.2f) kind %s" % [n.x, n.y, n.z, String(hit["kind"])]
		if last < z - TOL:
			break
		at = Vector3(at.x, last - 0.05, at.z)
	if is_nan(last):
		offenders.append("%s: nothing rendered" % what)
		worst = maxf(worst, 999.0)
		return
	offenders.append("%s: face at %+.1f m%s" % [what, last - z, why])
	worst = maxf(worst, absf(last - z))


# ------------------------------------------------------------------ the `blocks` index
## 915 masses x 220 000 samples is 200 M point-in-rect tests in GDScript, which is minutes. They
## are bucketed into 64 m cells once, so a sample only ever tests the handful that can reach it.
func _index(rows: Array) -> void:
	for row: Dictionary in rows:
		var c: Array = row["c"]
		var s: Array = row["s"]
		var yaw := float(row.get("yaw", 0.0))
		var poly := PackedVector2Array()
		for fx in [-0.5, 0.5]:
			for fy in [-0.5, 0.5]:
				poly.append(_rotate(c, s, yaw, fx, fy))
		var id := _rows.size()
		_rows.append({"poly": poly, "z0": float(row["z0"]), "z1": float(row["z1"])})
		var box := _bbox(poly)
		var lo := Vector2i((Vector2(box.position.x, box.position.y) / CELL).floor())
		var hi := Vector2i((Vector2(box.end.x, box.end.y) / CELL).floor())
		for cx in range(lo.x, hi.x + 1):
			for cy in range(lo.y, hi.y + 1):
				var key := Vector2i(cx, cy)
				var bucket: Array = _buckets.get(key, [])
				bucket.append(id)
				_buckets[key] = bucket


## Does a mass already stand at this sample? A building hides the floor it stands on and a cover
## box hides the deck under it; neither is a missing face.
func _blocked(x: float, y: float, z: float) -> bool:
	var bucket: Array = _buckets.get(Vector2i((Vector2(x, y) / CELL).floor()), [])
	for id: int in bucket:
		var row: Dictionary = _rows[id]
		if z < float(row["z0"]) - 0.5 or z > float(row["z1"]) - 0.5:
			continue
		if _inside(row["poly"], x, y):
			return true
	return false


# ------------------------------------------------------------------ geometry helpers
## Even-odd point in polygon. Holes are tested as a UNION (`_in_any`), not by the same parity,
## because the crust's cuts overlap freely — the canal and the dock trench share 23 373 m2.
static func _inside(poly: PackedVector2Array, x: float, y: float) -> bool:
	var hit := false
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		if (a.y > y) != (b.y > y) and x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x:
			hit = not hit
	return hit


## Every ring carries its own bbox, so a sample outside one is rejected in four comparisons.
static func _ring(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in points:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


## A sample sitting on a ring's own edge tells us nothing: the layout puts its holes on 2 m
## coordinates, the 4 m grid lands exactly on them, and even-odd point-in-polygon is undefined
## there — which read as 11 "missing" faces along the edge of every hole in W3_foundry_l2.
static func _on_edge(outer: PackedVector2Array, holes: Array, x: float, y: float) -> bool:
	if _near_ring(outer, x, y):
		return true
	for h: Dictionary in holes:
		var box: AABB = h["box"]
		if x < box.position.x - EDGE or x > box.end.x + EDGE \
				or y < box.position.y - EDGE or y > box.end.y + EDGE:
			continue
		if _near_ring(h["ring"], x, y):
			return true
	return false


static func _near_ring(ring: PackedVector2Array, x: float, y: float) -> bool:
	var p := Vector2(x, y)
	var n := ring.size()
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var ab := b - a
		var ll := ab.length_squared()
		var t := 0.0 if ll < 1e-9 else clampf((p - a).dot(ab) / ll, 0.0, 1.0)
		if p.distance_to(a + ab * t) <= EDGE:
			return true
	return false


## Every hole carries its own bbox, so a sample outside one is rejected in four comparisons.
static func _in_any(holes: Array, x: float, y: float) -> bool:
	for h: Dictionary in holes:
		var box: AABB = h["box"]
		if x < box.position.x or x > box.end.x or y < box.position.y or y > box.end.y:
			continue
		if _inside(h["ring"], x, y):
			return true
	return false


static func _bbox(poly: PackedVector2Array) -> AABB:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(Vector3(lo.x, lo.y, 0.0), Vector3(hi.x - lo.x, hi.y - lo.y, 0.0))


static func _rotate(c: Array, s: Array, yaw_deg: float, fx: float, fy: float) -> Vector2:
	var a := deg_to_rad(yaw_deg)
	var lx := fx * float(s[0])
	var ly := fy * float(s[1])
	return Vector2(float(c[0]) + lx * cos(a) - ly * sin(a),
			float(c[1]) + lx * sin(a) + ly * cos(a))
