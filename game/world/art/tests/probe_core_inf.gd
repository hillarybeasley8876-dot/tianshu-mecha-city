extends Node
## city-art r16b §8 diagnostic: how many kit core blocks have NO roof-map cell inside them, and where.
## A block that is inside the instance's footprint but that no map cell lands in keeps the INF it was
## seeded with (`settle/roof_map.gd:161`), and `top - base < min_h` is false for INF, so it shipped as
## a box from the base to infinity. Not a tracked test — it prints, it does not gate.
##   tools/godot.sh test res://world/art/tests/probe_core_inf.gd

const DESIGN := "res://world/city/design_layout.json"


func _ready() -> void:
	var roofs := KitRoofMap.load()
	if roofs == null or roofs.is_empty():
		print("CORE INF no roof map")
		get_tree().quit(1)
		return
	var cores := roofs.cores(CityOcclusion.CORE_BLOCK, CityOcclusion.CORE_MIN_H)
	var inf_n := 0
	var tall := -INF
	var worst := {}
	for core: Dictionary in cores:
		var y0 := float(core["y0"])
		var y1 := float(core["y1"])
		if not is_finite(y1):
			inf_n += 1
			if worst.is_empty():
				worst = core
			continue
		tall = maxf(tall, y1 - y0)
	print("CORE INF %d cores, %d with an infinite top, tallest finite %.1f m"
		% [cores.size(), inf_n, tall])
	if not worst.is_empty():
		var c: Vector2 = worst["c"]
		print("CORE INF first at (%.1f, %.1f) base %.2f" % [c.x, c.y, float(worst["y0"])])
	# Which instances own them: the blocks come back per block, so group by the tile they sit in.
	var per_tile := {}
	for core: Dictionary in cores:
		if is_finite(float(core["y1"])):
			continue
		var c: Vector2 = core["c"]
		var key := "%d,%d" % [int(floor(c.x / 100.0)), int(floor(c.y / 100.0))]
		per_tile[key] = int(per_tile.get(key, 0)) + 1
	var keys: Array = per_tile.keys()
	keys.sort()
	print("CORE INF tiles (100 m): %d" % keys.size())
	for key: String in keys:
		print("   %-10s %d" % [key, per_tile[key]])
	get_tree().quit(0)
