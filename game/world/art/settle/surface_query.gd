class_name ArtSurfaces
extends RefCounted
## The surface the player SEES, as a query (city-art r10). One class, two callers: the settle pass
## (`CitySettle`, at load) and the lead's gate (`tools/float_audit.gd`, after load). There is no second
## copy of this code — if the audit and the settle disagreed about what holds a thing, the gate would
## be measuring a world nobody ships.
##
## SUPPORT is the RENDERED geometry: city-kit's near meshes (its own transform lists, never a MultiMesh
## read-back, so this works head-less) plus city-build's tile render meshes. Collision is no evidence:
## it is the blockout boxes, which stood at full height while every kit model drew sunk by half its
## height on 11-03 and nothing measured it.
##
## Every support carries a `kind`, because the settle rules are not the same for a roof and a street:
##   roof   — a kit building (tier `detail`): the only thing a rooftop unit may stand on
##   piece  — a kit street/cover model (tiers `lod`, `cover_near`): dressing, never a support
##   ground — a city-build tile render mesh: streets, deck slabs, viaducts, terrain
##
## The index is the PHYSICS world, not a `TriangleMesh` grid. Measured on this machine, one
## `Mesh.create_trimesh_shape()` costs 0.022 us per triangle where `TriangleMesh.create_from_faces()`
## costs 0.37 us — 17x — and a `direct_space_state.intersect_ray` answers in ~1 us with the broadphase
## already done. That is the difference between a settle pass that fits the 1.5 s load budget and one
## that costs 2.3 s. The bodies live on their own collision LAYERS, are masked against nothing, are
## STATIC (a dynamic body falls — see `_static_body`), and are freed by `dispose()` as soon as the pass
## is over, so no other unit ever sees them.

const DROP := 160.0       ## how far below a query point a surface still counts

const ROOF: StringName = &"roof"
const PIECE: StringName = &"piece"
const GROUND: StringName = &"ground"
## What a RESTING thing may stand on. `piece` is deliberately NOT in it: dressing does not hold up
## dressing. A railing that settles onto the railing beside it, or a lamp onto a market stall that is
## itself about to move, is how the pass ends up measuring a world nobody ships.
const ARCHITECTURE: Array[StringName] = [ROOF, GROUND]
## Collision layers, used only by this class's own queries. Nothing is ever masked against them.
const LAYER_ROOF := 1 << 20
const LAYER_GROUND := 1 << 21

var _world: World3D = null
## ONE static body per kind, carrying every support as a shape with its own transform. 1 600 separate
## bodies cost 647 ms of the index build in `body_set_space`/`body_set_state` alone; two bodies cost
## nothing, and the ray still reports which kind it hit because that is the body's RID.
var _bodies: Dictionary = {}           ## StringName kind -> RID
var _shapes: Array[ConcavePolygonShape3D] = []
var _shape_of: Dictionary = {}         ## Mesh -> ConcavePolygonShape3D (shared by every instance)
var _query: PhysicsRayQueryParameters3D = null
var _supports: int = 0
var built_ms: int = 0
var shape_ms: int = 0
var body_ms: int = 0
var rays: int = 0
## Diagnostics only (`probe_support.gd`, the audit's "what is under it"): one body PER SUPPORT instead
## of one per kind, so a hit carries the support's name. It costs the 647 ms above, so the settle pass
## never turns it on.
var named: bool = false
var _solo: Array[RID] = []
var _name_of: Dictionary = {}          ## RID -> String
var _kind_of: Dictionary = {}          ## RID -> StringName


func size() -> int:
	return _supports


## Points the index at a world. Everything else needs this first.
func setup(world: World3D) -> bool:
	dispose()
	_world = world
	if _world == null:
		push_error("ArtSurfaces: no World3D — the settle pass has no surface to read")
		return false
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.DOWN)
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	return true


## Collects every support under `city` and puts it in the physics world. Returns the support count.
func build(city: Node, kit: Node = null) -> int:
	var t0 := Time.get_ticks_msec()
	if not setup((city as Node3D).get_world_3d()):
		return 0
	if kit != null and kit.has_method(&"near_batches"):
		for batch: Dictionary in kit.call(&"near_batches"):
			var tier := String(batch["tier"])
			if tier != "detail":
				continue          ## `piece` is dressing; it holds nothing up
			var list: Array = batch["list"]
			var name := String(batch["name"])
			for i in list.size():
				add(batch["mesh"] as Mesh, list[i] as Transform3D, "%s#%d" % [name, i], ROOF)
	var tiles := city.get_node_or_null(^"Tiles")
	if tiles != null:
		var stack: Array[Node] = [tiles]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			var mi := n as MeshInstance3D
			# An HLOD proxy starts at 430 m and a hidden one is not on screen at all: neither is a
			# surface the player can see a railing standing on.
			# `mi.visible`, not `is_visible_in_tree()`: the walk is 1 200 nodes deep in an imported
			# glb hierarchy and the parent chain is the city's own, which is always visible.
			if mi == null or mi.mesh == null or not mi.visible or mi.visibility_range_begin > 0.0:
				continue
			add(mi.mesh, mi.global_transform, String(mi.name), GROUND)
	built_ms = Time.get_ticks_msec() - t0
	return _supports


## Frees every body and shape. Called as soon as the pass is over: 1 500 static bodies left in the
## world would be in every broadphase for the rest of the session.
func dispose() -> void:
	for kind in _bodies:
		PhysicsServer3D.free_rid(_bodies[kind])
	for rid in _solo:
		PhysicsServer3D.free_rid(rid)
	_bodies.clear()
	_solo.clear()
	_name_of.clear()
	_kind_of.clear()
	_shapes.clear()
	_shape_of.clear()
	_supports = 0


## The highest support surface straight down from `from`, restricted to `kinds`. Returns
## `{y, normal, kind, id}` — `{}` when nothing is there within DROP. `id` is the support's name, and is
## only filled in when the index was built with `named`.
func top_below(from: Vector3, kinds: Array[StringName] = ARCHITECTURE) -> Dictionary:
	if _world == null:
		return {}
	_query.from = from
	_query.to = from + Vector3.DOWN * DROP
	_query.collision_mask = _mask(kinds)
	rays += 1
	var hit := _world.direct_space_state.intersect_ray(_query)
	if hit.is_empty():
		return {}
	var rid := hit["rid"] as RID
	return {"y": (hit["position"] as Vector3).y, "normal": hit["normal"] as Vector3,
			"kind": _kind_of.get(rid, ROOF if rid == _bodies.get(ROOF, RID()) else GROUND),
			"id": String(_name_of.get(rid, ""))}


static func _mask(kinds: Array[StringName]) -> int:
	var mask := 0
	for kind in kinds:
		mask |= LAYER_ROOF if kind == ROOF else LAYER_GROUND
	return mask


## A support body. `PhysicsServer3D.body_create()` returns a DYNAMIC body in 4.7.2 + Jolt, so a body
## left at its default mode falls at 9.8 m/s² from the tick it enters the space: a top face that starts
## at y = 0 was at y = −4.94 one second later, and every settle decision and every float measurement
## taken against it described a world that had sunk. Found by hero-v3 r9
## (`game/player/model/hero3/tests/probe_surface_mode.gd`); proven here by
## `world/art/tests/test_surface_static.gd`.
##
## `ART_SURFACES_DYNAMIC=1` puts the bug back, which is how the before/after in that test and the
## r16a audit numbers were measured. Debug only — it makes every support in the city fall.
static func _static_body() -> RID:
	var body := PhysicsServer3D.body_create()
	if OS.get_environment("ART_SURFACES_DYNAMIC") != "1":
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	return body


## `id` is only used in warnings and, when `named` is on, as the support's name in a hit.
func add(mesh: Mesh, xf: Transform3D, id: String, kind: StringName) -> void:
	if mesh == null:
		return
	if not _shape_of.has(mesh):
		var ts := Time.get_ticks_usec()
		var shape := mesh.create_trimesh_shape()
		shape_ms += (Time.get_ticks_usec() - ts) / 1000
		if shape == null:
			push_warning("ArtSurfaces: %s has no triangles; it cannot hold anything up" % id)
			return
		_shape_of[mesh] = shape
		_shapes.append(shape)
	var tb := Time.get_ticks_usec()
	var body: RID = _bodies.get(kind, RID())
	if named:
		body = _static_body()
		PhysicsServer3D.body_set_space(body, _world.space)
		PhysicsServer3D.body_set_collision_layer(body, LAYER_ROOF if kind == ROOF else LAYER_GROUND)
		PhysicsServer3D.body_set_collision_mask(body, 0)
		_solo.append(body)
		_name_of[body] = id
		_kind_of[body] = kind
	elif not _bodies.has(kind):
		body = _static_body()
		PhysicsServer3D.body_set_space(body, _world.space)
		PhysicsServer3D.body_set_collision_layer(body, LAYER_ROOF if kind == ROOF else LAYER_GROUND)
		PhysicsServer3D.body_set_collision_mask(body, 0)
		_bodies[kind] = body
	PhysicsServer3D.body_add_shape(body, (_shape_of[mesh] as ConcavePolygonShape3D).get_rid(), xf)
	_supports += 1
	body_ms += (Time.get_ticks_usec() - tb) / 1000
