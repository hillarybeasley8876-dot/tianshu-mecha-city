extends Node
## How many different facades the city actually wears (city-art r12 §1, gate "Count").
##
## The shader picks a facade in two steps: the model's `kit.json` BAND picks the FAMILY, and a hash of
## the building's own world cell picks the VARIANT inside it. This walks every kit building instance
## and makes the same two decisions in GDScript, so the answer is a number rather than an impression.
##
## The hash has to be the SHADER's hash, not merely a hash: `mc_creep.gdshaderinc`'s `hash21` is
## float32 arithmetic, and GDScript's `float` is a double, so the naive port returns different numbers
## for the same input. Every step here therefore goes through `Vector2`, whose components are `real_t`
## (float32 in a standard build), which is what makes the two agree to the last bit.
##
## Run: tools/godot.sh run res://world/art/tests/probe_facade_variety.tscn 30

const ASSIGN := "res://world/kit/kit_assign.json"
const KIT_JSON := "res://world/kit/kit.json"
## `mc_kit_body.gdshaderinc`: the block hash and the per-building seed.
const BLOCK_M := 7.0
const BUILDING_M := 29.0
## The gate: no single (family, variant) pair may hold more than this share of the city's buildings.
const MAX_SHARE := 0.25

var _failures: int = 0


func _ready() -> void:
	var bands := _bands()
	var counts: Dictionary = {}          # "fam.var" -> instances
	var by_family: Dictionary = {}
	var values: Array[float] = []
	var examples: Dictionary = {}
	var rows := 0
	for row: Dictionary in _buildings():
		var model := String(row.get("model", ""))
		if not bands.has(model):
			continue
		var family := int(McKitSkin.FAMILY_BY_BAND.get(bands[model], -1))
		if family < 0:
			continue
		rows += 1
		var p: Array = row.get("pos", [0.0, 0.0, 0.0])
		# Blender (x, y, z) -> Godot (x, z, -y), the placer's own conversion; only XZ is used.
		var world := Vector2(float(p[0]), -float(p[1]))
		var b_var := building_var(world)
		values.append(b_var)
		var key := "%d.%d" % [family, facade_variant(b_var, family)]
		counts[key] = int(counts.get(key, 0)) + 1
		# One example per pair, so a reviewer can point a camera at a balcony variant and see it.
		if not examples.has(key):
			examples[key] = "%s at godot (%.0f, %.0f), top %.0f m" % [model, world.x, world.y,
					float(row.get("height", 0.0))]
		by_family[family] = int(by_family.get(family, 0)) + 1
	_report(counts, by_family, values, rows, examples)
	get_tree().quit(1 if _failures > 0 else 0)


func _report(counts: Dictionary, by_family: Dictionary, values: Array[float], rows: int,
		examples: Dictionary) -> void:
	var keys: Array = counts.keys()
	keys.sort()
	var top := 0
	var top_key := "-"
	for k: String in keys:
		print("FACADE %-6s %4d buildings   e.g. %s" % [k, int(counts[k]), examples.get(k, "-")])
		if int(counts[k]) > top:
			top = int(counts[k])
			top_key = k
	var share := float(top) / maxf(float(rows), 1.0)
	var names: Array = by_family.keys()
	names.sort()
	for f: int in names:
		print("FACADE family %d: %d buildings" % [f, int(by_family[f])])
	print("FACADE %d buildings, %d distinct (family, variant) pairs, most common %s at %.1f %%"
			% [rows, counts.size(), top_key, share * 100.0])
	if values.size() > 1:
		var lo: float = values[0]
		var hi: float = values[0]
		var sum := 0.0
		for v in values:
			lo = minf(lo, v)
			hi = maxf(hi, v)
			sum += v
		print("FACADE per-building value b_var: min %.3f mean %.3f max %.3f — the wall value is "
				% [lo, sum / float(values.size()), hi] + "±15 % of it, so no two neighbours match")
	_expect(counts.size() >= 6, "at least six distinct facades in the city (got %d)" % counts.size())
	_expect(share < MAX_SHARE, "no (family, variant) pair holds more than %.0f %% (top %s at %.1f %%)"
			% [MAX_SHARE * 100.0, top_key, share * 100.0])
	print("FACADE VARIETY %s" % ("PASS" if _failures == 0 else "FAIL"))


## `mc_creep.gdshaderinc`'s `hash21`, in float32. Every intermediate is a `Vector2` component, which is
## `real_t`; a plain GDScript float would be a double and the two would disagree from the first
## multiply onwards.
static func hash21(p: Vector2) -> float:
	var q := Vector2(p.x * 443.897 - floor(p.x * 443.897), p.y * 441.423 - floor(p.y * 441.423))
	var d: float = q.dot(q + Vector2(19.19, 19.19))
	q += Vector2(d, d)
	var m: float = q.x * q.y
	return m - floor(m)


## `mc_kit_body.gdshaderinc`: `b_var`, the per-BUILDING value the facade and the lit windows share.
static func building_var(world: Vector2) -> float:
	var blk := Vector2(floor(world.x / BLOCK_M), floor(world.y / BLOCK_M))
	var seed := Vector2(hash21(blk) * 255.0, hash21(blk + Vector2(3.7, 3.7)) * 61.0)
	var cell := Vector2(floor(world.x / BUILDING_M), floor(world.y / BUILDING_M))
	return hash21(cell + seed)


## `mc_facade_style.gdshaderinc`'s `facade_variant`.
static func facade_variant(b_var: float, family: int) -> int:
	var h: float = fposmod(b_var * 37.13 + float(family) * 0.317, 1.0)
	return int(floor(h * 3.0))


func _bands() -> Dictionary:
	var out: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT_JSON))
	if not (parsed is Dictionary):
		push_error("probe_facade_variety: %s is not a JSON object" % KIT_JSON)
		return out
	for row: Dictionary in ((parsed as Dictionary).get("models", []) as Array):
		out[String(row.get("id", ""))] = String(row.get("band", ""))
	return out


func _buildings() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ASSIGN))
	if not (parsed is Dictionary):
		push_error("probe_facade_variety: %s is not a JSON object" % ASSIGN)
		return []
	return (parsed as Dictionary).get("buildings", []) as Array


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL %s" % msg)
		_failures += 1
