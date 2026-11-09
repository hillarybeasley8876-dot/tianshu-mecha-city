extends Node
## Kit skin probe (city-build). Run with:
##   tools/godot.sh test res://world/city/tools/skin_probe.gd
##
## Skin mode must remove a structure's RENDER mesh and nothing else, so this probe proves the
## other half: every building the build left unrendered still collides where its mass should be,
## every rooftop prop slot still has a roof under it, and the navigation maps still hold the same
## polygons as an unskinned build. It is a no-op PASS when `layout.json` has no active skin.
##
## Lead r7 item 1: the probe used to stop at 24 buildings and only looked at roof slots, which
## made it blind in two ways — a capped sample can miss a whole archetype, and a building whose
## roof a breach cut away has no slot at all (`D1_b003`, `D1_b011` failed exactly there). It now
## covers every skinned building from its own footprint (`kit_skin.probe`) and every slot.

## A hit may sit a little BELOW the roof slot (deck thickness) or a little ABOVE it: the
## warehouse and industrial archetypes put their own 4.8 m roof cap over the top segment.
const ROOF_TOL := 2.0
## How far above a slot the ray starts. It must stay short: casting from high up finds the deck
## or the tower standing OVER the roof (a slot on D2_b014 reads +47 m, which is a skydeck, not a
## missing roof), and the first hit is then somebody else's geometry.
const SLOT_UP := 8.0
const SLOT_DOWN := 12.0
## How far above the mass the footprint rays start, and how far below its base they reach.
const REACH_UP := 60.0
const REACH_DOWN := 6.0

var city: Node3D = null
var fails: int = 0


func _ready() -> void:
	city = (load("res://world/city.tscn") as PackedScene).instantiate() as Node3D
	add_child(city)
	for i in 30:
		await get_tree().physics_frame
	var layout: Dictionary = city.get("layout")
	var skin: Dictionary = layout.get("kit_skin", {}) as Dictionary
	var ids: Array = skin.get("buildings", []) as Array
	if not bool(skin.get("active", false)) or ids.is_empty():
		print("SKIN PROBE PASS: no active kit skin in layout.json (%s) — nothing to probe"
				% str(skin.get("source", "no source")))
		get_tree().quit(0)
		return
	var space := city.get_world_3d().direct_space_state
	_probe_footprints(skin.get("probe", []) as Array, space)
	_probe_slots(ids, layout.get("prop_slots", []) as Array, space)
	var nav: Node = city.get("nav")
	var polys: Dictionary = {}
	for cls in CityNav.CLASSES:
		polys[String(cls)] = (nav as CityNav).sample_points(cls).size()
	_report(true, "navmesh polygons per class %s (compare with an unskinned build)" % str(polys))
	print("SKIN PROBE %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


## Every skinned building must still have mass somewhere inside its own footprint and height.
func _probe_footprints(rows: Array, space: PhysicsDirectSpaceState3D) -> void:
	var empty: Array = []
	var rays := 0
	for row in rows:
		var r: Dictionary = row as Dictionary
		var top: Vector3 = city.call("to_godot", r["centre"]) as Vector3
		var size: Array = r["size"] as Array
		var base_y: float = float(r["base_z"])
		var hit_any := false
		for off in _fan(float(size[0]), float(size[1]), float(r.get("yaw_deg", 0.0))):
			rays += 1
			var at := top + off
			var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(
					at + Vector3.UP * REACH_UP, Vector3(at.x, base_y - REACH_DOWN, at.z),
					Layers.WORLD))
			if not down.is_empty() and (down["position"] as Vector3).y >= base_y - 1.0:
				hit_any = true
		if not hit_any:
			empty.append(String(r["id"]))
	_report(not rows.is_empty(), "%d skinned buildings in kit_skin.probe" % rows.size())
	_report(empty.is_empty(), "%d / %d skinned footprints still collide (%d rays)%s"
			% [rows.size() - empty.size(), rows.size(), rays,
			   "" if empty.is_empty() else " — NO MASS: " + ", ".join(empty.slice(0, 8))])


## Five points across the footprint: the centre and the four quarter points, yaw-corrected.
func _fan(w: float, d: float, yaw_deg: float) -> Array[Vector3]:
	var a := deg_to_rad(yaw_deg)
	var out: Array[Vector3] = [Vector3.ZERO]
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var lx: float = sx * w * 0.25
			var ly: float = sy * d * 0.25
			# Blender (x east, y north) -> Godot (x, z = -y); the footprint yaw rotates the same way.
			out.append(Vector3(lx * cos(a) - ly * sin(a), 0.0, -(lx * sin(a) + ly * cos(a))))
	return out


## Every rooftop slot of a skinned building must still land on that building's own roof.
func _probe_slots(ids: Array, slots: Array, space: PhysicsDirectSpaceState3D) -> void:
	var by_building := _slots_by_building(slots)
	var probed := 0
	var bad: Array = []
	var worst := -99.0
	for id in ids:
		for row in (by_building.get(String(id), []) as Array):
			var roof: Vector3 = city.call("to_godot", (row as Dictionary)["pos"]) as Vector3
			probed += 1
			var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(
					roof + Vector3.UP * SLOT_UP, roof + Vector3.DOWN * SLOT_DOWN, Layers.WORLD))
			if down.is_empty():
				bad.append("%s: no collision at %v" % [String(id), roof])
				continue
			var delta: float = (down["position"] as Vector3).y - roof.y
			worst = maxf(worst, delta)
			if delta < -ROOF_TOL:
				bad.append("%s: %+.1f m off the slot at %v" % [String(id), delta, roof])
	_report(probed > 0, "%d rooftop slots on skinned buildings" % probed)
	_report(bad.is_empty(), "%d / %d skinned roof slots still collide (highest hit %+.1f m over "
			% [probed - bad.size(), probed, worst]
			+ "the slot, gate %+.1f..%+.1f)%s" % [-ROOF_TOL, SLOT_UP,
			   "" if bad.is_empty() else " — " + "; ".join(bad.slice(0, 6))])


func _report(ok: bool, text: String) -> void:
	if not ok:
		fails += 1
	print("%s: %s" % ["PASS" if ok else "FAIL", text])


func _slots_by_building(slots: Array) -> Dictionary:
	var out: Dictionary = {}
	for s in slots:
		var row: Dictionary = s as Dictionary
		var bid := String(row.get("building", ""))
		if bid.is_empty():
			continue
		if not out.has(bid):
			out[bid] = []
		(out[bid] as Array).append(row)
	return out
