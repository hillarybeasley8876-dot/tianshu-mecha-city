class_name CitySettle
extends RefCounted
## Puts every RESTING dressing item on the surface the player sees (city-art r10, the user's
## "地编物件浮空问题解决下"). One pass over each batch, two rules, and an honest count of everything it
## had to throw away.
##
## Why a pass is needed at all: roof dressing is placed at `base_z + height` of the DESIGN box, but a
## Tripo building only reaches that height somewhere on its footprint — a podium tower is a tall shaft
## on a low podium, a setback steps in, a t01 crown ends in a spire. Over the rest of the footprint the
## dressing hung at the box top, up to 122 m above the roof actually under it.
##
## ROOF rule (rooftop machinery, greebles, kit s08): stand on the roof city-kit MEASURED
## (`KitRoofMap`, r12 §2) — the model's own 2 m top-surface grid, read through the instance transform,
## which is the only thing that knows a podium tower's podium is 20 m below its shaft. Where the map has
## no answer (a building with no kit model, a model with no map) the render is raycast as before, and
## that fallback is also the safety net: a unit the map placed is re-checked against the render and
## moved only if the two disagree. A unit with no roof under it at all is DROPPED and counted — a roof
## unit standing in the street is worse than no roof unit.
##
## STREET rule (lamps, barriers, planters, vehicles, stalls, trees, lions — OUR dressing): settle onto
## the highest surface within ±STREET_BAND of where the layout meant it to be. Nothing there means the
## layout's z is wrong for that piece of ground, so it is dropped and its id reported — never silently
## kept.
##
## What is NEVER settled (r10b): city-kit's STRUCTURE — arena cover k01-k12, s06 deck slabs, s05
## pylons, s01/s02/s04 street skirts, s03 market rows, s07 railings, f03 pipe racks, u01/u02 fasciae.
## Their transforms come from the same layout data as city-build's colliders, so moving or dropping one
## leaves the collider behind: invisible walls, invisible floors and holes. `float_audit` reports them
## instead, by `kit_assign.json` row id, and the fix belongs in the rule that placed them.

const RULE_ROOF := 0
const RULE_STREET := 1

## "Near-flat": within 15 degrees of up, per the lead's brief.
const FLAT_COS := 0.9659
## How far from the layout's own z a street prop may be moved. r10b: this was ±3 m and 8 props climbed
## exactly 2.9 m onto the concrete mass of the NEXT tile (`probe_support.gd` names it
## `t5_2_c17_6_0_concrete` at (37.5, 0, 263.7)) — a planter standing on a building plinth two and a half
## metres over the pavement it was placed on. Half the band is under a storey, so a prop can still find
## the kerb it was placed beside and can no longer climb a plinth.
const STREET_BAND := 1.5
## Footprint samples: the centre and four points 40 % of the way to the corners. A thing half on a
## ledge is held by the ledge, and a railing on a slab edge is held by the slab. `float_audit.gd`
## samples exactly these points, so a settled item measures zero there by construction.
const FOOT := 0.4
const REPORT_MAX := 24      ## ids printed per category; the counts are always complete
## How far the roof map's answer may sit from the render's before the render wins. city-kit's own gate
## on the map is a p95 of 0.376 m against the shipped mesh, and the float gate is 0.5 m — so 0.5 m is
## the one number that follows from both: a map answer inside the map's own noise is kept (overruling
## it would fight the measurement it came from), and anything past it is a real disagreement the render
## settles. It still catches a wrong BUILDING, which is metres out, not centimetres.
##
## r16a: this was 1.0 m, and the last two floaters in the city were both map answers the metre let
## through — an antenna array 0.91 m above its roof and a vent stack 0.78 m above its own.
const VERIFY_M := 0.5

var surfaces: ArtSurfaces = null
## How far the roof map's answer may sit from the render's before the render wins. A field rather than
## the constant so the r16a before/after can be rendered from one build with one env var
## (`SETTLE_VERIFY_M=1.0` is the rule that shipped the two floaters), the way `SETTLE_STRUCTURE=1`
## reproduces the r10 rule.
var verify_m: float = VERIFY_M
## city-kit's measured roof surfaces (r12 §2). When this is set the ROOF rule asks it first and only
## raycasts the render where the map has no answer, which is what turned 1 099 dropped roof units into
## a few dozen.
var roof_map: KitRoofMap = null
## The baked result (city-art r10). When it has this batch, `settle()` replays the recorded survivors
## and their moves instead of asking the physics world — which is the whole 2.2 s.
var cache: SettleCache = null
## category -> {"kept", "moved", "dropped", "nowhere", "map", "ray"}
var stats: Dictionary = {}
## category -> Array[String] ids that had no surface to stand on (capped at REPORT_MAX)
var reports: Dictionary = {}
var elapsed_ms: int = 0
## Diagnostics (`SETTLE_TRACE=<metres>`): every instance that moved at least this far is reported with
## the surface it landed on. A prop that jumps exactly the width of the band has climbed onto a sill or
## a planter rim, and the band is the thing to change — this is how that is seen rather than guessed.
var trace_m: float = INF
var traces: Array[String] = []
## `ROOF_TRACE=1`: map answers the render refused, with what the render has there instead.
var trace_miss: bool = false
var miss_traces: Array[String] = []
## Survivors of the LAST `settle()` call: the indices kept, and the metres each one moved. A second
## batch drawn over the same transforms (the aviation lamp on its mast) follows these instead of
## being settled on its own mesh, which would slide it off the pole it belongs to. r12: a roof unit
## can move sideways as well as up (onto the nearest flat cell), so the delta is a vector.
var last_kept: PackedInt32Array = []
var last_delta: PackedVector3Array = []


func _init(index: ArtSurfaces) -> void:
	surfaces = index


## Settles one batch in place-safe fashion: `list` is read, a NEW array of survivors is returned, and
## the caller rebuilds its MultiMesh from it (a dropped instance is one fewer instance, not an instance
## parked at the origin).
func settle(list: Array, mesh: Mesh, rule: int, category: String, key: String) -> Array[Transform3D]:
	var t0 := Time.get_ticks_msec()
	var row: Dictionary = stats.get(category,
			{"kept": 0, "moved": 0, "dropped": 0, "nowhere": 0, "map": 0, "ray": 0})
	# `row` is CUMULATIVE over every batch of this category, so the cache has to store this batch's
	# own delta or the replay adds the running total once per batch.
	var nowhere0 := int(row["nowhere"])
	var out: Array[Transform3D] = []
	last_kept = []
	last_delta = []
	if cache != null and cache.has(key):
		var t1 := Time.get_ticks_msec()
		var replayed := _replay(list, row, category, key)
		elapsed_ms += Time.get_ticks_msec() - t1
		return replayed
	var bb := mesh.get_aabb()
	var c := bb.get_center()
	var feet := _feet(bb)
	# A roof unit only ever stands on architecture, so the street/deck/piece supports are not even
	# candidates — that is most of the query's cost gone. Built with append(), not a ternary: a
	# `[a] if cond else []` assigned to a typed array is a RUNTIME error in GDScript, and the failed
	# assignment silently returned 0.0 from `_target`, which put every item in the city on y = 0.
	var kinds: Array[StringName] = []
	if rule == RULE_ROOF:
		kinds.append(ArtSurfaces.ROOF)
	else:
		kinds.append_array(ArtSurfaces.ARCHITECTURE)
	for i in list.size():
		var xf: Transform3D = list[i]
		var base := xf * feet[0]
		var top_y := (xf * Vector3(c.x, bb.end.y, c.z)).y
		var delta := _delta(xf, feet, base, top_y, rule, kinds, row)
		if is_nan(delta.x):
			row["dropped"] = int(row["dropped"]) + 1
			if rule == RULE_STREET:
				row["nowhere"] = int(row["nowhere"]) + 1
			_note(category, "%s#%d at %s" % [key, i, _round(xf.origin)])
			continue
		last_kept.append(i)
		last_delta.append(delta)
		if delta.length() > 0.001:
			row["moved"] = int(row["moved"]) + 1
			if delta.length() >= trace_m:
				traces.append("%-14s %s#%d moved %.2f m (dy %+.2f) onto %s at %s"
						% [category, key, i, delta.length(), delta.y, _round(base + delta),
						   _round(xf.origin)])
			xf.origin += delta
		out.append(xf)
		row["kept"] = int(row["kept"]) + 1
	stats[category] = row
	if cache != null:
		cache.put(key, list.size(), last_kept, last_delta, int(row["nowhere"]) - nowhere0)
	elapsed_ms += Time.get_ticks_msec() - t0
	return out


## Replays a baked batch: same survivors, same vertical moves, same counts — without a single ray.
func _replay(list: Array, row: Dictionary, category: String, key: String) -> Array[Transform3D]:
	var cached := cache.row(key)
	if int(cached["n"]) != list.size():
		# The fingerprint covers every input, so this should be impossible; if it ever happens the
		# baked survivors belong to a different list and must not be applied to this one.
		push_error("CitySettle: baked batch '%s' has %d instances, this one has %d — the cache is "
				% [key, int(cached["n"]), list.size()] + "stale in a way the stamp did not catch")
		return [] as Array[Transform3D]
	last_kept = cached["kept"]
	last_delta = cached["d"]
	var out: Array[Transform3D] = []
	for j in last_kept.size():
		var xf: Transform3D = list[last_kept[j]]
		if last_delta[j].length() > 0.001:
			row["moved"] = int(row["moved"]) + 1
			xf.origin += last_delta[j]
		out.append(xf)
	row["kept"] = int(row["kept"]) + last_kept.size()
	row["dropped"] = int(row["dropped"]) + int(cached["n"]) - last_kept.size()
	row["nowhere"] = int(row["nowhere"]) + int(cached["nowhere"])
	stats[category] = row
	return out


## A parallel batch that rides on the one just settled: same survivors, same move.
static func follow(list: Array, kept: PackedInt32Array, delta: PackedVector3Array) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for j in kept.size():
		if kept[j] >= list.size():
			push_error("CitySettle.follow: index %d is past a batch of %d — the two lists are not the "
					% [kept[j], list.size()] + "same length, so one of them is not drawn over the other")
			break
		var xf: Transform3D = list[kept[j]]
		xf.origin += delta[j]
		out.append(xf)
	return out


## How far this item's base has to move, or a vector whose x is NAN when it has nowhere to go.
##
## ROOF items ask `KitRoofMap` first (r12 §2): the model's own measured top surface knows a podium from
## a shaft, which the render's raycast also knows but only after 2.2 s of physics bodies have been
## built. The map is then CHECKED against the render wherever the physics index exists — the render is
## the ground truth, and a map answer more than `VERIFY_M` away from it is a map answer that lost. That
## check is what keeps `float_audit` at zero floating while the placement is done from the map.
## `row["map"]` / `row["ray"]` are how the two are told apart in the report.
func _delta(xf: Transform3D, feet: Array[Vector3], base: Vector3, top_y: float, rule: int,
		kinds: Array[StringName], row: Dictionary) -> Vector3:
	if rule == RULE_ROOF and roof_map != null:
		var d := _map_delta(base, top_y)
		if not is_nan(d.x):
			row["map"] = int(row.get("map", 0)) + 1
			if surfaces == null:
				return d
			var ray := _ray_delta(xf, feet, base, top_y, rule, kinds, base.y + d.y + 1.0)
			if is_nan(ray.x):
				_trace_miss(base + d, xf, feet)
				return ray                       # the render has no roof here; the map was wrong
			if absf(d.y - ray.y) > verify_m:
				row["ray"] = int(row.get("ray", 0)) + 1
				row["map_bad"] = int(row.get("map_bad", 0)) + 1
				return ray
			return d
		row["ray"] = int(row.get("ray", 0)) + 1
	elif rule == RULE_ROOF:
		row["ray"] = int(row.get("ray", 0)) + 1
	return _ray_delta(xf, feet, base, top_y, rule, kinds)


## The roof map, asked at the unit's own base point. Asking it at all five footprint samples was tried
## and is worse: a sample may hop to a flat cell up to 6 m away, so its height belongs to a different
## patch of roof than the ray under that foot, and the two then disagree by metres (29 units floating).
## One point, then the render checks it, is the combination that measures zero floating.
func _map_delta(base: Vector3, top_y: float) -> Vector3:
	var hit := roof_map.roof_at(base, top_y)
	if hit.is_empty():
		return Vector3(NAN, NAN, NAN)
	return hit["moved"] as Vector3


## The render, asked directly: the highest near-flat surface of the right kind under the item's feet.
## `from_y` is where the downward ray starts. It defaults to the height the layout aimed at, which is
## right when the layout is what is being checked; when the ray is VERIFYING a roof-map answer it starts
## just above that answer instead — a podium tower's podium can be 180 m below the box top, and
## `ArtSurfaces.DROP` is 160 m, so a ray from the box top finds nothing and calls a good roof missing.
func _ray_delta(xf: Transform3D, feet: Array[Vector3], base: Vector3, top_y: float, rule: int,
		kinds: Array[StringName], from_y: float = INF) -> Vector3:
	var start := from_y
	if is_inf(start):
		start = top_y + 1.0 if rule == RULE_ROOF else base.y + STREET_BAND + 0.01
	var best: Dictionary = {}
	for foot in feet:
		var at := xf * foot
		var hit := surfaces.top_below(Vector3(at.x, start, at.z), kinds)
		if hit.is_empty():
			continue
		# The test comes BEFORE the "highest wins" choice, not after. A duct run 8 m long puts one of its
		# five footprint samples on the parapet beside it, and taking the highest first and testing that
		# one threw the whole unit away because the parapet is vertical — 449 units, all of them standing
		# on a perfectly good flat roof a few centimetres lower.
		if rule == RULE_ROOF:
			if hit["kind"] != ArtSurfaces.ROOF:
				continue          # not a kit building roof: a roof unit has no business here
			if (hit["normal"] as Vector3).y < FLAT_COS:
				continue          # a slope
		elif float(hit["y"]) < base.y - STREET_BAND:
			continue          # outside the band the layout's own z is wrong for this piece of ground
		if best.is_empty() or float(hit["y"]) > float(best["y"]):
			best = hit
	if best.is_empty():
		return Vector3(NAN, NAN, NAN)
	return Vector3(0.0, float(best["y"]) - base.y, 0.0)


## The five footprint points the audit samples, in the mesh's own space.
static func _feet(bb: AABB) -> Array[Vector3]:
	var c := bb.get_center()
	var feet: Array[Vector3] = [Vector3(c.x, bb.position.y, c.z)]
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var k2: Vector2 = k
		feet.append(Vector3(c.x + k2.x * FOOT * bb.size.x, bb.position.y,
				c.z + k2.y * FOOT * bb.size.z))
	return feet


## `ROOF_TRACE=1`: a map answer the render refuses. Prints what IS under the point, with every kind
## enabled and from well above, so "the map is wrong" can be told from "the ray cannot see that far".
func _trace_miss(at: Vector3, xf: Transform3D, feet: Array[Vector3]) -> void:
	if not trace_miss or miss_traces.size() >= 16:
		return
	var lines: Array[String] = []
	for foot in feet:
		var p := xf * foot
		var hit := surfaces.top_below(Vector3(p.x, at.y + 2.0, p.z), ArtSurfaces.ARCHITECTURE)
		lines.append("%s" % ("nothing" if hit.is_empty() else "%s y=%.2f n=%.3f id=%s"
				% [hit["kind"], float(hit["y"]), (hit["normal"] as Vector3).y, hit["id"]]))
	miss_traces.append("map said y=%.2f at %s -> %s" % [at.y, _round(at), ", ".join(lines)])


func _note(category: String, line: String) -> void:
	var list: Array = reports.get(category, [])
	if list.size() < REPORT_MAX:
		list.append(line)
	reports[category] = list


static func _round(v: Vector3) -> Vector3:
	return Vector3(snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1))


## One line per category, plus the dropped ids. This is the evidence the lead asked for: every count
## of dropped items, per category, never a silent skip.
func report() -> void:
	var names := stats.keys()
	names.sort()
	var dropped := 0
	for category: String in names:
		var row: Dictionary = stats[category]
		dropped += int(row["dropped"])
		print("SETTLE %-22s kept=%-5d moved=%-5d dropped=%-4d (no surface in band=%d, by map=%d, "
				% [category, int(row["kept"]), int(row["moved"]), int(row["dropped"]),
				   int(row["nowhere"]), int(row.get("map", 0))]
				+ "map overruled=%d, by ray=%d)" % [int(row.get("map_bad", 0)), int(row.get("ray", 0))])
		for line: String in reports.get(category, []):
			print("SETTLE   dropped %s %s" % [category, line])
	print("SETTLE %d items dropped in %d ms (%d rays, %s)"
			% [dropped, elapsed_ms, surfaces.rays if surfaces != null else 0,
			   "computed" if surfaces != null else "replayed from the bake"])
	if roof_map != null:
		print("SETTLE roof map: %d placed, %d with no kit building under them, %d with no flat cell "
				% [roof_map.hits, roof_map.miss, roof_map.noflat] + "within %.0f m" % KitRoofMap.SEARCH_M)
		var blame: Array = roof_map.by_model.keys()
		blame.sort_custom(func(a: String, b: String) -> bool:
				return int(roof_map.by_model[a]) > int(roof_map.by_model[b]))
		for i in mini(blame.size(), 10):
			print("SETTLE   no roof on %-6s %d" % [blame[i], int(roof_map.by_model[blame[i]])])
		for at in roof_map.miss_samples:
			print("SETTLE   no kit building at %s" % CitySettle._round(at))
	for line in traces:
		print("SETTLE   moved %s" % line)
	for line in miss_traces:
		print("SETTLE   map refused %s" % line)
