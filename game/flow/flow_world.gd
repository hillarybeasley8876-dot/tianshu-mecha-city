class_name FlowWorld
extends RefCounted
## The flow unit's read-only view of the map (CONTRACTS §7, lead r1 must-fix 1). Nothing here opens a
## file outside `res://` any more and nothing reads the Blender source layout: the live world is the
## source of truth. Hive sites are its `&"hive_site"` markers, arenas are its `&"arena"` Area3Ds (real
## convex footprints, so a concave arena triggers where it is drawn and not where its bounding box
## would be), spawn points come from its `&"spawn_zone"` areas, and the insertion point is the
## `PlayerSpawn` marker. A world without them degrades to the sandbox table or to an empty map with one
## warning — never a crash, because the demo also runs on the sandbox deck.

## Sandbox spires (brief §5): deck, plateau and trench of `core/sandbox/sandbox.tscn`, in Godot axes.
const SANDBOX_HIVES: Array[Array] = [
	["hive_deck", Vector3(-220.0, 40.0, -40.0)],
	["hive_plateau", Vector3(-260.0, 24.0, 300.0)],
	["hive_trench", Vector3(185.0, -30.0, 0.0)],
]
## Spawn points generated for an arena the world does not give `spawn_zone`s for: this many points
## spread along the footprint, pulled in from the edge so a pack arrives inside the fight.
const SOCKETS_PER_ARENA := 6
const SOCKET_INSET := 0.22


# --- markers --------------------------------------------------------------------------------------

## A named marker in the live world (CONTRACTS §7), or null when the world does not have it.
static func world_marker(marker: StringName) -> Node3D:
	var world := Game.world
	if world == null:
		return null
	return world.find_child(String(marker), true, false) as Node3D


## Every Node3D of `group` in the live world, or an empty array without a world.
static func world_group(group: StringName) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if Game.world == null or not Game.world.is_inside_tree():
		return out
	for node in Game.world.get_tree().get_nodes_in_group(group):
		if node is Node3D:
			out.append(node as Node3D)
	return out


## Insertion point H0: the world's `PlayerSpawn` marker (CONTRACTS §7), falling back to the sandbox
## spawn so the drop-in still has somewhere to land.
static func player_start() -> Transform3D:
	var marker := world_marker(&"PlayerSpawn")
	if marker != null:
		return marker.global_transform
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 60.0))


# --- hive spires ----------------------------------------------------------------------------------

## Hive spires of the live world: [{id, arena, pos, height}] from the `&"hive_site"` markers. Under
## `--sandbox` the three grey-box test spires replace them (brief §5).
static func hives() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Game.has_flag("sandbox"):
		for row in SANDBOX_HIVES:
			out.append({"id": StringName(row[0]), "arena": &"sandbox", "pos": row[1] as Vector3,
					"height": 60.0})
		return out
	for site in world_group(&"hive_site"):
		out.append({"id": StringName(site.get_meta(&"site_id", site.name)),
				"arena": StringName(site.get_meta(&"arena", "")),
				"pos": site.global_position,
				"height": float(site.get_meta(&"height", 60.0))})
	if out.is_empty() and Game.world != null:
		push_warning("FlowWorld: the world has no &\"hive_site\" markers — no spires to destroy")
	return out


# --- arenas ---------------------------------------------------------------------------------------

## Every arena of the live world: {id, area, parts (world-space convex footprints), lo, hi, centre,
## sockets}. The footprints are the world's own convex decomposition; `lo`/`hi` are the vertical span
## of its trigger volume, which is where flow's own trigger has to listen too.
static func arenas() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for area in world_group(&"arena"):
		var id := StringName(area.get_meta(&"arena_id", area.name))
		if id == &"":
			push_warning("FlowWorld: an &\"arena\" area has no arena_id — skipped")
			continue
		out.append(_arena_row(id, area as Node3D))
	return out


static func arena(id: StringName) -> Dictionary:
	for a in arenas():
		if a["id"] == id:
			return a
	return {}


static func _arena_row(id: StringName, area: Node3D) -> Dictionary:
	var parts: Array[PackedVector3Array] = []
	var lo := INF
	var hi := -INF
	for child in area.get_children():
		var cs := child as CollisionShape3D
		if cs == null or not (cs.shape is ConvexPolygonShape3D):
			continue
		var hull := cs.shape as ConvexPolygonShape3D
		var pts := PackedVector3Array()
		for p in hull.points:
			pts.append(cs.global_transform * Vector3(p.x, 0.0, p.z))
		if pts.size() >= 3:
			parts.append(pts)
		lo = minf(lo, cs.global_position.y - float(cs.scale.y) * 0.5)
		hi = maxf(hi, cs.global_position.y + float(cs.scale.y) * 0.5)
	if parts.is_empty():
		push_warning("FlowWorld: arena '%s' has no convex shapes — using its origin as a point" % id)
		lo = area.global_position.y
		hi = lo + 80.0
		parts.append(_point_hull(area.global_position))
	return {"id": id, "area": area, "parts": parts, "lo": lo, "hi": hi,
			"centre": _centre_of(parts), "sockets": sockets_of(id, parts, hi)}


## A degenerate one-metre footprint, so an arena without geometry still has a trigger.
static func _point_hull(at: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		out.append(at + Vector3(cos(a), 0.0, sin(a)) * 0.5)
	return out


static func _centre_of(parts: Array[PackedVector3Array]) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for part in parts:
		for p in part:
			sum += p
			n += 1
	return sum / float(maxi(n, 1))


# --- spawn sockets --------------------------------------------------------------------------------

## Spawn sockets of an arena: [{id, pos, kind}]. The world's `&"spawn_zone"` areas that stand inside
## the footprint are used as they are; without them the sockets are generated along the footprint, so
## an encounter file can always name `<arena>_sp1..6`. Generated positions sit at the top of the
## trigger volume — the director snaps them onto the ground before anything spawns there.
static func sockets_of(id: StringName, parts: Array[PackedVector3Array],
		hi: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var bounds := _bounds_of(parts)
	for zone in world_group(&"spawn_zone"):
		if bounds.has_point(Vector2(zone.global_position.x, zone.global_position.z)):
			out.append({"id": StringName(zone.get_meta(&"zone_id", zone.name)),
					"pos": zone.global_position,
					"kind": StringName(zone.get_meta(&"zone_kind", "hatch"))})
	if not out.is_empty():
		return out
	var centre := _centre_of(parts)
	var ring := _perimeter(parts)
	for i in SOCKETS_PER_ARENA:
		var p: Vector3 = ring[int(round(float(i) * float(ring.size())
				/ float(SOCKETS_PER_ARENA))) % ring.size()]
		out.append({"id": StringName("%s_sp%d" % [id, i + 1]),
				"pos": p.lerp(centre, SOCKET_INSET) + Vector3.UP * hi,
				"kind": &"hatch"})
	return out


## XZ bounds of every footprint part, padded so a zone just outside the drawn edge still counts.
static func _bounds_of(parts: Array[PackedVector3Array]) -> Rect2:
	var rect := Rect2()
	var first := true
	for part in parts:
		for p in part:
			var v := Vector2(p.x, p.z)
			if first:
				rect = Rect2(v, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(v)
	return rect.grow(8.0)


## The outline of the largest part, walked once, so the generated sockets spread around the arena.
static func _perimeter(parts: Array[PackedVector3Array]) -> PackedVector3Array:
	var best := PackedVector3Array()
	for part in parts:
		if part.size() > best.size():
			best = part
	return best if not best.is_empty() else PackedVector3Array([Vector3.ZERO])
