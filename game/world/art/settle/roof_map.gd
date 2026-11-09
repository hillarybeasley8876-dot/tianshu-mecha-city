class_name KitRoofMap
extends RefCounted
## Where a kit building's roof actually IS (city-art r12 §2, city-kit r6's roof map).
##
## Roof dressing used to be aimed at the DESIGN box top: `base_z + height` of the layout row. A Tripo
## building only reaches that height somewhere on its footprint — a podium tower is a tall shaft on a
## low podium, a setback steps in, a crown ends in a spire — so over the rest of the footprint the
## dressing hung in the air and the settle pass had to throw it away. 1 099 units were dropped that way.
##
## city-kit r6 measured the real top surface off every model's DETAIL glb on a 2 m grid in MODEL space
## and wrote it into `world/kit/kit.json` (`models[].roof`): one height byte and one flatness byte per
## cell. This reads that map, pairs it with the instance transforms in `kit_assign.json` (the same
## `Basis(UP, yaw).scaled_local(scale)` the placer builds), and answers the only question the scatterer
## has: "I want to stand here — where is the roof, and may I?"
##
## The transform, once, because it is easy to get backwards. `kit_placer.gd` places an instance at
## `Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(sx, sz, sy)), Vector3(px, pz, -py))`, where
## the row is Blender (x, y, z-up). The model's own Blender point (mx, my, mz) is the Godot model-space
## point (mx, mz, -my). So `model = xf.affine_inverse() * world` gives mx = model.x, my = -model.z, and
## the height read from the map is model.y.
##
## Gate: `tools/citykit/test_roofmap.py` walks the map the way a scatterer would and puts its worst p95
## at 0.376 m against the shipped mesh.

const KIT_JSON := "res://world/kit/kit.json"
const ASSIGN := "res://world/kit/kit_assign.json"
## Index cell for the world-space lookup, metres. A building is 20-60 m across, so 32 m keeps the
## candidate list at one or two entries for almost every query.
const GRID := 32.0
## How far from the aimed point a flat cell may be found before the unit is given up on, per the brief.
const SEARCH_M := 6.0
## A roof this far ABOVE the height the layout aimed at is not the roof the layout meant. Kept small:
## the kit scales its models to the layout box, so the two agree to well under a metre.
const TOP_TOL := 1.5

## model id -> {"cell_m", "nx", "ny", "ox", "oy", "z0", "span", "h", "flat", "foot"}
var _models: Dictionary = {}
## One entry per placed building: {"model", "xf", "inv", "rect"}
var _inst: Array[Dictionary] = []
## world XZ grid key -> PackedInt32Array of `_inst` indices
var _grid: Dictionary = {}
var models: int = 0
var buildings: int = 0
## Why a query came back empty, so the drop count can be read rather than guessed: `miss` is a point no
## kit building covers (the layout row has no kit model, or the model has no map), `noflat` is a point
## the model covers where nothing within `SEARCH_M` is flat enough to stand on.
var miss: int = 0
var noflat: int = 0
var hits: int = 0
## r16b §8: core blocks that passed the footprint test but that no measured map cell reached. They are
## dropped rather than emitted — an unmeasured block has no known mass, and the seed value used to be
## INF, which `top - base < min_h` accepted and `CityOcclusion` turned into a box up to infinity.
var cores_unmeasured: int = 0
## model id (or "-" for a point no kit building covers) -> how many queries ended there. This is what
## turns "344 units dropped" into "the three old-town pitched-roof models dropped 210 of them", which is
## a different bug report from "the map is wrong".
var by_model: Dictionary = {}
## The first few points that no kit building covered, so a miss can be looked up in the layout by hand.
var miss_samples: Array[Vector3] = []


## The map, or an empty one when either file is missing. A missing map is not fatal: the settle pass
## falls back to raycasting the render, which is what it did before r12.
static func load(kit_json: String = KIT_JSON, assign: String = ASSIGN) -> KitRoofMap:
	var out := KitRoofMap.new()
	out._read_models(kit_json)
	out._read_instances(assign)
	return out


func is_empty() -> bool:
	return _inst.is_empty()


## Blender (x, y, z) -> Godot (x, z, -y), the placer's own conversion.
static func to_godot(p: Array) -> Vector3:
	return Vector3(float(p[0]), float(p[2]), -float(p[1]))


## The roof under `world`, aimed at `top` (the height the layout asked for). Returns
## `{"at": Vector3, "flat": bool, "moved": float}` — the world point the unit's BASE belongs at — or
## `{}` when the model does not cover the point and has no flat cell within `SEARCH_M`.
func roof_at(world: Vector3, top: float) -> Dictionary:
	var best: Dictionary = {}
	var best_y := -INF
	var best_over := INF
	var covered := false
	var blamed := "-"
	for i in _candidates(world):
		var hit := _probe(_inst[i], world, top)
		if hit.is_empty():
			continue
		covered = true
		blamed = String(_inst[i]["model"])
		if not bool(hit.get("stand", false)):
			continue
		var y := (hit["at"] as Vector3).y
		if y <= top + TOP_TOL:
			if y > best_y:
				best_y = y
				best = hit
		elif y < best_over:
			# Everything here is above the aimed height: the layout box is shorter than the model. Take
			# the lowest of them rather than leaving the unit in the air.
			best_over = y
			if best.is_empty():
				best = hit
	if best.is_empty():
		if covered:
			noflat += 1
		else:
			miss += 1
			if miss_samples.size() < 24:
				miss_samples.append(world)
		by_model[blamed] = int(by_model.get(blamed, 0)) + 1
		return {}
	hits += 1
	# The height is the answer; the horizontal move is only needed when the unit had to HOP to a
	# different cell. On a flat cell the unit stays exactly where the scatterer put it — snapping every
	# unit to a cell centre would both jitter the layout and make "moved" meaningless.
	var at: Vector3 = best["at"]
	if bool(best["flat"]):
		at = Vector3(world.x, at.y, world.z)
	best["at"] = at
	best["moved"] = at - world
	return best


## r13: the SOLID CORE of every placed kit building, as world-space boxes on a `block` metre grid.
##
## One box per grid block that lies wholly inside the instance's own footprint, from the model's base to
## the LOWEST top surface the map records anywhere in that block. Such a box is inside the building's
## mass from every direction, which is the property that makes it safe to hide things behind — and
## unlike "the lowest FLAT cell over the whole footprint" it is not dragged to the ground by one
## entrance canopy in the corner of a 140 m tower (that rule capped the median building at 22 % of its
## height and the occluders were worth 0.5 % of the draws).
##
## Returns `[{"c": Vector2 world xz, "half": Vector2, "y0": float, "y1": float}]`.
func cores(block: float, min_h: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for inst: Dictionary in _inst:
		var model: Dictionary = _models.get(inst["model"], {})
		if model.is_empty():
			continue
		var boxes := _core_blocks(inst, model, block, min_h)
		out.append_array(boxes)
	return out


## One instance's core boxes: the blocks of the world grid its footprint covers completely, each lifted
## to the lowest top surface inside it.
func _core_blocks(inst: Dictionary, model: Dictionary, block: float, min_h: float) -> Array[Dictionary]:
	var foot: Vector2 = model["foot"]
	var xf: Transform3D = inst["xf"]
	var rect: Rect2 = inst["rect"]
	var base := xf.origin.y
	var g0 := Vector2(floor(rect.position.x / block), floor(rect.position.y / block))
	var g1 := Vector2(floor(rect.end.x / block), floor(rect.end.y / block))
	var valid: Dictionary = {}
	var half := Vector2(block, block) * 0.5
	for gz in range(int(g0.y), int(g1.y) + 1):
		for gx in range(int(g0.x), int(g1.x) + 1):
			var c := Vector2((float(gx) + 0.5) * block, (float(gz) + 0.5) * block)
			if _inside_footprint(xf, foot, c, half):
				valid[_bkey(gx, gz)] = INF
	if valid.is_empty():
		return []
	# One pass over the map's cells, bucketed into the blocks that survived the footprint test.
	var cell_m := float(model["cell_m"])
	var nx := int(model["nx"])
	var ny := int(model["ny"])
	var h: PackedByteArray = model["h"]
	var z0 := float(model["z0"])
	var span := float(model["span"])
	var ox := float(model["ox"])
	var oy := float(model["oy"])
	var bx := xf.basis.x
	var bz := xf.basis.z
	var by := xf.basis.y.y
	# The cell's world square, as an axis-aligned half-extent. The map is 2 m in MODEL space, so a model
	# the kit scaled 6x has 12 m cells — wider than the block grid — and crediting only the block under
	# the cell's CENTRE left blocks with no cell in them. A block whose footprint test passed but that no
	# cell credited kept the INF it was seeded with above, `INF - base < min_h` is false, and it shipped
	# as an occluder from the base to infinity (r16b §8: 25 of them, in 7 tiles).
	var half_cell := Vector2(
		0.5 * cell_m * (absf(bx.x) + absf(bz.x)),
		0.5 * cell_m * (absf(bx.z) + absf(bz.z)))
	# `ART_CORES_LEGACY=1` puts the pre-r16b rule back — centre-only crediting, and no finite guard —
	# which is how `test_occlusion.gd` proves its finite-core check has teeth. Debug only: it ships
	# occluders that reach to infinity.
	var legacy := OS.get_environment("ART_CORES_LEGACY") == "1"
	if legacy:
		half_cell = Vector2.ZERO
	for cy in range(ny):
		for cx in range(nx):
			var idx := cy * nx + cx
			if h[idx] == 0:
				continue
			var mx := ox + (float(cx) + 0.5) * cell_m
			var my := oy + (float(cy) + 0.5) * cell_m
			var wx := xf.origin.x + bx.x * mx - bz.x * my
			var wz := xf.origin.z + bx.z * mx - bz.z * my
			var top := base + by * (z0 + float(h[idx]) / 255.0 * span)
			# Every block the cell's square touches, not just the one under its centre. Taking the MIN
			# over a superset can only lower a box, and an occluder may only ever be smaller than the
			# mass it stands for (`occlusion.gd` header).
			for gz in range(int(floor((wz - half_cell.y) / block)), int(floor((wz + half_cell.y) / block)) + 1):
				for gx in range(int(floor((wx - half_cell.x) / block)), int(floor((wx + half_cell.x) / block)) + 1):
					var key := _bkey(gx, gz)
					if not valid.has(key):
						continue
					valid[key] = minf(float(valid[key]), top)
	var out: Array[Dictionary] = []
	for key: String in valid:
		var top := float(valid[key])
		# No measured cell reached this block, so nothing is known about the mass there: it is skipped,
		# never guessed at, and never emitted as an infinite box.
		if not is_finite(top) and not legacy:
			cores_unmeasured += 1
			continue
		if top - base < min_h:
			continue
		var g := key.split(",")
		out.append({"c": Vector2((float(g[0]) + 0.5) * block, (float(g[1]) + 0.5) * block),
			"half": half, "y0": base, "y1": top})
	return out


## Is the whole `block` square inside the instance's own footprint? Tested in the instance's local
## frame, where the footprint is an axis-aligned rectangle.
func _inside_footprint(xf: Transform3D, foot: Vector2, c: Vector2, half: Vector2) -> bool:
	var inv := xf.affine_inverse()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var w := Vector3(c.x + sx * half.x, xf.origin.y, c.y + sz * half.y)
			var l := inv * w
			if absf(l.x) > foot.x * 0.5 or absf(-l.z) > foot.y * 0.5:
				return false
	return true


static func _bkey(gx: int, gz: int) -> String:
	return "%d,%d" % [gx, gz]


## r13: does any placed kit building cover this world point? The occluder builder uses it to leave the
## design box out where a real model stands, so the two never stack.
func covers(world: Vector3) -> bool:
	for i in _candidates(world):
		if (_inst[i]["rect"] as Rect2).has_point(Vector2(world.x, world.z)):
			return true
	return false


## r13: the LOWEST flat roof surface anywhere inside a world-space XZ rectangle, or NAN when the map
## covers none of it (a blockout building, an unskinned model, a model with no map). The occluder
## builder caps a building's core at this height: an occluder that rose to the design box top would
## hide the setbacks, crowns and podium roofs the player can see, and occlusion culling that hides
## something visible is worse than no occlusion culling at all.
func lowest_flat(rect: Rect2) -> float:
	var lowest := INF
	for i in _candidates_rect(rect):
		var inst: Dictionary = _inst[i]
		var model: Dictionary = _models.get(inst["model"], {})
		if model.is_empty():
			continue
		var cell_m := float(model["cell_m"])
		var flat: PackedByteArray = model["flat"]
		var h: PackedByteArray = model["h"]
		var nx := int(model["nx"])
		var ny := int(model["ny"])
		for cy in range(ny):
			for cx in range(nx):
				var idx := cy * nx + cx
				if idx >= flat.size() or flat[idx] <= 127:
					continue
				var w: Vector3 = _to_world(inst, model, Vector2i(cx, cy), int(h[idx]))
				if not rect.has_point(Vector2(w.x, w.z)):
					continue
				lowest = minf(lowest, w.y)
	return lowest if lowest < INF else NAN


## Every instance whose footprint overlaps `rect`, from the XZ index (the same grid `_candidates` uses,
## keyed on the whole rectangle rather than one point).
func _candidates_rect(rect: Rect2) -> PackedInt32Array:
	var seen := {}
	var out := PackedInt32Array()
	for key in _rect_keys(rect.grow(GRID)):
		for i in _grid.get(key, PackedInt32Array()):
			if seen.has(i):
				continue
			seen[i] = true
			if (_inst[i]["rect"] as Rect2).intersects(rect):
				out.append(i)
	return out


## The instances whose footprint could contain `world`, from the XZ index.
func _candidates(world: Vector3) -> PackedInt32Array:
	return _grid.get(_key(world.x, world.z), PackedInt32Array())


## One instance's answer for one point: `{}` when the model does not cover it at all, `{"stand": false}`
## when it covers it but nothing within `SEARCH_M` is flat (a mast, a parapet or a slope is recorded at
## its own top with `flat = 0`, which is the honest answer — a machine does not stand on a mast), and
## `{"stand": true, "at", "flat", "hop"}` when there is somewhere to put it.
func _probe(inst: Dictionary, world: Vector3, top: float) -> Dictionary:
	var model: Dictionary = _models.get(inst["model"], {})
	if model.is_empty():
		return {}
	var local: Vector3 = (inst["inv"] as Transform3D) * world
	var cell_m := float(model["cell_m"])
	var nx := int(model["nx"])
	var ny := int(model["ny"])
	var cx := int(floor((local.x - float(model["ox"])) / cell_m))
	var cy := int(floor((-local.z - float(model["oy"])) / cell_m))
	var flat: PackedByteArray = model["flat"]
	var h: PackedByteArray = model["h"]
	if cx < 0 or cy < 0 or cx >= nx or cy >= ny:
		return {}
	var here := cy * nx + cx
	var covered := h[here] != 0 or flat[here] != 0
	var reach := int(ceil(SEARCH_M / cell_m))
	var best_d := INF
	var best: Dictionary = {}
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var gx := cx + dx
			var gy := cy + dy
			if gx < 0 or gy < 0 or gx >= nx or gy >= ny:
				continue
			var idx := gy * nx + gx
			if idx >= flat.size() or flat[idx] <= 127:
				continue
			var d := Vector2(float(dx), float(dy)).length() * cell_m
			if d > SEARCH_M or d >= best_d:
				continue
			best_d = d
			best = {"cell": Vector2i(gx, gy), "h": h[idx]}
	if best.is_empty():
		return {"stand": false} if covered else {}
	return {
		"stand": true,
		"at": _to_world(inst, model, best["cell"] as Vector2i, int(best["h"])),
		"flat": best_d <= 0.001,
		"hop": best_d,
	}


## The world position of one map cell's surface: the cell's own centre in model space, lifted to the
## height the map records, then through the instance transform.
func _to_world(inst: Dictionary, model: Dictionary, cell: Vector2i, h: int) -> Vector3:
	var cell_m := float(model["cell_m"])
	var mx := float(model["ox"]) + (float(cell.x) + 0.5) * cell_m
	var my := float(model["oy"]) + (float(cell.y) + 0.5) * cell_m
	var mz := float(model["z0"]) + float(h) / 255.0 * float(model["span"])
	return (inst["xf"] as Transform3D) * Vector3(mx, mz, -my)


static func _key(x: float, z: float) -> String:
	return "%d,%d" % [int(floor(x / GRID)), int(floor(z / GRID))]


## `world/kit/kit.json` -> one decoded map per model. The two byte planes are base64 in the file; they
## are decoded once here and never again.
func _read_models(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("KitRoofMap: no %s — roof dressing falls back to the render" % path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("KitRoofMap: %s is not a JSON object" % path)
		return
	for row: Dictionary in ((parsed as Dictionary).get("models", []) as Array):
		var roof: Dictionary = row.get("roof", {})
		if roof.is_empty():
			continue
		var h := Marshalls.base64_to_raw(String(roof.get("h", "")))
		var flat := Marshalls.base64_to_raw(String(roof.get("flat", "")))
		var nx := int(roof.get("nx", 0))
		var ny := int(roof.get("ny", 0))
		if nx <= 0 or ny <= 0 or h.size() < nx * ny or flat.size() < nx * ny:
			push_warning("KitRoofMap: %s has a truncated roof map (%dx%d, %d/%d bytes)"
					% [row.get("id", "?"), nx, ny, h.size(), flat.size()])
			continue
		var origin: Array = roof.get("origin", [0.0, 0.0])
		_models[String(row.get("id", ""))] = {
			"cell_m": float(roof.get("cell_m", 2.0)), "nx": nx, "ny": ny,
			"ox": float(origin[0]), "oy": float(origin[1]),
			"z0": float(roof.get("z0", 0.0)), "span": float(roof.get("z_span", 1.0)),
			"h": h, "flat": flat,
			"foot": Vector2(float((row.get("footprint", [1.0, 1.0]) as Array)[0]),
					float((row.get("footprint", [1.0, 1.0]) as Array)[1])),
		}
		models += 1


## `kit_assign.json`'s `buildings` rows -> one instance each, with the placer's own transform. A row
## with no model, or a model with no map, is skipped: the settle pass raycasts those.
func _read_instances(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("KitRoofMap: no %s — roof dressing falls back to the render" % path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("KitRoofMap: %s is not a JSON object" % path)
		return
	for row: Dictionary in ((parsed as Dictionary).get("buildings", []) as Array):
		var model := String(row.get("model", ""))
		if not _models.has(model):
			continue
		var s: Array = row.get("scale", [1.0, 1.0, 1.0])
		var scale := Vector3(float(s[0]), float(s[2]), float(s[1]))
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(row.get("yaw", 0.0))))
				.scaled_local(scale), to_godot(row.get("pos", [0.0, 0.0, 0.0])))
		var i := _inst.size()
		_inst.append({"model": model, "xf": xf, "inv": xf.affine_inverse(),
				"rect": _rect(xf, _models[model])})
		_index(i, _inst[i]["rect"] as Rect2)
		buildings += 1


## The instance's world XZ footprint, as the AABB of its four rotated corners.
func _rect(xf: Transform3D, model: Dictionary) -> Rect2:
	var foot: Vector2 = model["foot"]
	var rect := Rect2()
	var first := true
	for k in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
		var c: Vector2 = k
		var w: Vector3 = xf * Vector3(c.x * foot.x, 0.0, c.y * foot.y)
		var p := Vector2(w.x, w.z)
		rect = Rect2(p, Vector2.ZERO) if first else rect.expand(p)
		first = false
	return rect


func _index(i: int, rect: Rect2) -> void:
	for key in _rect_keys(rect):
		var list: PackedInt32Array = _grid.get(key, PackedInt32Array())
		list.append(i)
		_grid[key] = list


## Every index cell a world XZ rectangle touches.
static func _rect_keys(rect: Rect2) -> PackedStringArray:
	var out := PackedStringArray()
	for gz in range(int(floor(rect.position.y / GRID)), int(floor(rect.end.y / GRID)) + 1):
		for gx in range(int(floor(rect.position.x / GRID)), int(floor(rect.end.x / GRID)) + 1):
			out.append("%d,%d" % [gx, gz])
	return out

